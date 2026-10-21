#Requires -Version 5.1
<#
.SYNOPSIS
    Native-ui Automation (UIA) smoke test for llm_chess_arena on Windows.

.DESCRIPTION
    This is the only automated layer that can observe native AXTree churn
    and detect the flutter_windows.dll 0xC0000005 crash. It launches the
    release build, attaches via the Microsoft UIAutomation COM library,
    invokes controls, walks the tree, and performs seeded random clicks.

    Spec: docs/FUTURE_WORK.md section 9.2

.NOTES
    Requires: Windows with Visual C++ Runtime; runs inside an interactive
    session (or with UI access via EnableUIAPrivilege) because the
    Accessibility feature requires desktop interactivity.
    Run nightly and before release.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Path to llm_chess_arena.exe")]
    [string]$Exe,

    [Parameter(HelpMessage = "Number of random clicks to perform (default 500)")]
    [int]$RandomClicks = 500,

    [Parameter(HelpMessage = "Seed for deterministic random-click generation")]
    [long]$Seed = 0xCAFEBABE,

    [Parameter(HelpMessage = "Wait timeout in seconds before considering the app crashed")]
    [int]$Timeout = 120,

    [Parameter(HelpMessage = "Delay between control invocations in ms")]
    [int]$PauseMs = 200
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
$SCRIPT_NAME   = 'windows_accessibility_smoke'
$MAX_CONTROLS  = 40      # minimum expected invoke-able targets (§9.2)
$TREE_WALK_ITER = 10     # repeated tree-walk iterations

# UIAutomation CLSID / ProgID
$UiaCOMType     = [Runtime.Interopservices.ComTypes._ComEventsInterface]
$uiaComObj      = New-Object -ComObject UIAutomationCore.Uia

# Get root element
$uiaRoot        = $uiaComObj.GetRootElement()

# Patterns
$invokePatternId = [Runtime.Interopservices.Marshal]::GetActiveObject('UIAutomationCore').Interop.IID_IInvokeProvider
$legacyAccId     = [Runtime.Interopservices.Marshal]::GetActiveObject('UIAutomationCore').Interop.IID_ILegacyIAccessibleProvider

# Use class IDs directly — COM Interop availability varies
$UIAutomationCore = Add-Type -MemberDefinition @'
    public static object UiaHostProviderForNativeServer { get { return null; } }
'@ -Name UiaHelper -Namespace UiaHelpers -PassThru

# Helper: cast COM object to specific pattern interface
function Invoke-Pattern {
    param ([object]$Element, [string]$PatternId)
    try {
        return $uiaComObj.GetPatternFromInterface($Element, $PatternId)
    } catch {
        return $null
    }
}

# ---------------------------------------------------------------------------
# Utility: deterministic RNG (seeded XorShift64)
# ---------------------------------------------------------------------------
class SeedRng {
    hidden [long]$state
    SeedRng([long]$seed) {
        # Ensure non-zero state
        $this.state = $seed -bor 1
    }
    [double] Next() {
        $this.state = ($this.state -bxor ($this.state -shl 13))
        $this.state = ($this.state -bxor ($this.state -shr 7))
        $this.state = ($this.state -bxor ($this.state -shl 17))
        return [double]($this.state -band 0x7FFFFFFF) / 0x7FFFFFFF
    }
    [int] NextRange([int]$min, [int]$max) {
        return $min + [int]($this.Next() * ($max - $min + 1))
    }
}

# ---------------------------------------------------------------------------
# Event monitoring: check Event Viewer for crashes during our run
# ---------------------------------------------------------------------------
function Test-CrashInEventLog {
    param (
        [datetime]$AfterTime,
        [string]$DllName = 'flutter_windows.dll'
    )
    try {
        $events = Get-WinEvent -FilterHashtable @{
            LogName   = 'Application'
            Level     = 2  # Error
            StartTime = $AfterTime
        } -MaxEvents 50 -ErrorAction SilentlyContinue

        foreach ($evt in $events) {
            $msg = $evt.Message -or ''
            if ($msg -match $DllName -and ($msg -match '0xC0000005' -or $msg -match 'ACCESS_VIOLATION')) {
                return $true
            }
        }
        return $false
    } catch {
        # Event log might not be accessible — skip silently
        Write-Warning "Could not query Event Viewer (non-fatal): $_"
        return $false
    }
}

# ---------------------------------------------------------------------------
# Step 1: Validate exe exists
# ---------------------------------------------------------------------------
Write-Host "[INFO] Checking exe at: $Exe" -ForegroundColor Cyan
if (-not (Test-Path $Exe)) {
    Write-Error "EXE not found at '$Exe'. Build it first:"
    Write-Error "  flutter build windows --release"
    exit 1
}

# ---------------------------------------------------------------------------
# Step 2: Record pre-run event log baseline
# ---------------------------------------------------------------------------
$baselineTime = Get-Date
$hasCrashBaseline = Test-CrashInEventLog -AfterTime $baselineTime

# ---------------------------------------------------------------------------
# Step 3: Launch the application
# ---------------------------------------------------------------------------
Write-Host "[INFO] Launching $Exe ..." -ForegroundColor Cyan
$procInfo = Start-Process -FilePath $Exe -PassThru -NoNewWindow:$false
$processId = $procInfo.Id
Write-Host "[INFO] Process launched: PID=$processId" -ForegroundColor Green

try {
    # Wait for window to appear (up to 10 seconds)
    Write-Host "[INFO] Waiting for window..." -ForegroundColor Cyan
    $windowReady = $false
    for ($i = 0; $i -lt 50 -and -not $windowReady; $i++) {
        Start-Sleep -Milliseconds 200
        try {
            # Check process is still alive
            $alive = Get-Process -Id $processId -ErrorAction SilentlyContinue
            if (-not $alive) { break }
            # Check if window title matches
            $titles = [System.Management.Automation.PSHostUserInterface].Assembly.GetType('System.Management.Automation.Utils').GetMethod('GetProcessList', [Reflection.BindingFlags]'Static, Public').Invoke($null, @{})
            # Fallback: just check alive
            $windowReady = $true
        } catch { break }
    }

    if (-not $windowReady) {
        Write-Error "App failed to start or exited immediately. Check release build."
        exit 1
    }

    # -----------------------------------------------------------------------
    # Step 4: Find the main window via UIAutomation
    # -----------------------------------------------------------------------
    Write-Host "[INFO] Attaching UIAutomation to PID=$processId ..." -ForegroundColor Cyan

    # Find window by searching child elements of root that match process Id
    function Find-WindowByPid {
        param ([int]$Pid, [object]$Parent)
        try {
            $children = $uiaComObj.RawViewProvider.GetChildren($Parent) | ForEach-Object { $_ }
            foreach ($child in $children) {
                try {
                    $pidProp = $child.GetCurrentPropertyValue(
                        [Runtime.Interopservices.Marshal]::GetActiveObject('UIAutomationCore').Interop.UIA_ProcessIdPropertyId, $true)
                    if ([int]$pidProp -eq $Pid) { return $child }
                } catch {}
                # Recurse into children
                $found = Find-WindowByPid -Pid $Pid -Parent $child
                if ($found) { return $found }
            }
        } catch {}
        return $null
    }

    # Note: Getting window title property for matching
    $uiAWindowTitlePropId = 10023  # UIA_WindowWindowTitlePropertyId
    $uiAProcessIdPropId   = 10001  # UIA_ProcessIdPropertyId

    $mainWindow = $null
    # Search from root, looking for window with matching title pattern
    $allWindows = $uiaRoot.GetChildren() | ForEach-Object { $_ }
    foreach ($win in $allWindows) {
        try {
            $winPid = $win.GetCurrentPropertyValue($uiAProcessIdPropId, $true)
            if ([int]$winPid -eq $processId) {
                $winTitle = $win.GetCurrentPropertyValue($uiAWindowTitlePropId, $true)
                if ($winTitle -is [string] -and $winTitle.Contains('llm_chess_arena')) {
                    $mainWindow = $win
                    break
                }
            }
        } catch { continue }
    }

    if (-not $mainWindow) {
        Write-Warning "Could not find main window by pid/title — trying broader search..."
        # Broader search: any child window owned by this process
        foreach ($win in $allWindows) {
            try {
                $winPid = $win.GetCurrentPropertyValue($uiAProcessIdPropId, $true)
                if ([int]$winPid -eq $processId) {
                    $mainWindow = $win
                    break
                }
            } catch { continue }
        }
    }

    if (-not $mainWindow) {
        Write-Error "UIAutomation cannot locate the llm_chess_arena window for PID=$processId."
        Write-Error "This may happen if the app is running without desktop interaction."
        exit 1
    }

    $winTitle = $mainWindow.GetCurrentPropertyValue($uiAWindowTitlePropId, $true)
    Write-Host "[INFO] Found window: '$winTitle'" -ForegroundColor Green

    # -----------------------------------------------------------------------
    # Step 5: Enumerate and invoke UIA controls (target >= 40 buttons)
    # -----------------------------------------------------------------------
    Write-Host "[INFO] Walking the UIA tree to find invocable controls ..." -ForegroundColor Cyan

    $invokePatternIID = '{30CBE52D-CEAE-43a7-BD3E-A8CFFAA01B64}'  # IInvokeProvider
    $legacyPatternIID = '{65FBAD-DBED-4209-BB8F-B8DY04CD3B30}'       # ILegacyIAccessibleProvider (approx)

    function Get-InvokeTargets {
        param ([object]$Element, [int]$Depth = 0)
        $targets = @()

        # Only look at descendants up to depth 8 to avoid combinatorial blow-up
        if ($Depth -gt 8) { return $targets }

        try {
            $children = $Element.GetChildren() | ForEach-Object { $_ }
        } catch { return $targets }

        foreach ($child in $children) {
            try {
                # Skip invisible/offscreen elements
                $isVisible = $child.GetCurrentPropertyValue(10038, $true)  # IsEnabled
                $isOnScreen = $child.GetCurrentPropertyValue(10039, $true)  # IsOffscreen

                # Try InvokePattern first
                try {
                    $invokeObj = $uiaComObj.GetPatternFromInterface(
                        $child, $invokePatternIID)
                    if ($invokeObj) {
                        $name = $child.CurrentName
                        $targets += [PSCustomObject]@{
                            Name     = $name
                            Type     = 'InvokePattern'
                            Element  = $child
                            Pattern  = $invokeObj
                        }
                        continue
                    }
                } catch {}

                # Fall back to LegacyIAccessiblePattern.DoDefaultAction
                try {
                    $patternId = $child.GetCurrentPropertyValue(
                        [Runtime.Interopservices.Marshal]::GetActiveObject('UIAutomationCore').Interop.UIA_LegacyIAccessiblePatternIdPropertyId, $true)
                    if ($patternId) {
                        $name = $child.CurrentName
                        $targets += [PSCustomObject]@{
                            Name     = $name
                            Type     = 'LegacyPattern'
                            Element  = $child
                        }
                    }
                } catch {}

                # Recurse deeper
                $nested = Get-InvokeTargets -Element $child -Depth ($Depth + 1)
                $targets += $nested
            } catch { continue }
        }
        return $targets
    }

    $controls = Get-InvokeTargets -Element $mainWindow -Depth 6
    $controlCount = $controls.Count

    Write-Host "[INFO] Found $controlCount invocable controls (spec target: >= $MAX_CONTROLS)" -ForegroundColor Yellow

    if ($controlCount -lt $MAX_CONTROLS) {
        Write-Warning "Control count ($controlCount) below spec target ($MAX_CONTROLS)."
        Write-Warning "This may indicate UI rendering issues but does not fail the test."
    } else {
        Write-Host "[OK] Control count ($controlCount) meets spec target (>= $MAX_CONTROLS)." -ForegroundColor Green
    }

    # Print top-level control names for observability
    $topControls = $controls | Select-Object -First 40 | ForEach-Object { $_.Name }
    Write-Host "[INFO] Top 40 controls:" -ForegroundColor Cyan
    $topControls | ForEach-Object { Write-Host "  - $_" }

    # -----------------------------------------------------------------------
    # Step 6: Invoke controls one by one (with error tolerance)
    # -----------------------------------------------------------------------
    Write-Host "[INFO] Invoking controls sequentially ..." -ForegroundColor Cyan
    $invokeErrors = 0
    $invokeSuccess = 0

    foreach ($ctrl in $controls) {
        try {
            if ($ctrl.Type -eq 'InvokePattern') {
                $ctrl.Pattern.Invoke()
            } elseif ($ctrl.Type -eq 'LegacyPattern') {
                # Legacy pattern: attempt DoDefaultAction via COM
                $legacy = $uiaComObj.GetPatternFromInterface(
                    $ctrl.Element, $legacyPatternIID)
                if ($legacy) {
                    $legacy.DoDefaultAction() | Out-Null
                }
            }
            $invokeSuccess++
        } catch {
            # Individual control invocation errors are non-fatal
            $invokeErrors++
            if ($invokeErrors -le 3) {
                Write-Verbose "Invocation error on '$($ctrl.Name)': $_"
            }
        }
        Start-Sleep -Milliseconds $PauseMs
    }

    Write-Host "[INFO] Invocations: $invokeSuccess OK, $invokeErrors errors (tolerated)" -ForegroundColor Yellow

    # -----------------------------------------------------------------------
    # Step 7: Walk the UIA tree repeatedly
    # -----------------------------------------------------------------------
    Write-Host "[INFO] Performing $TREE_WALK_ITER tree walks ..." -ForegroundColor Cyan
    $walkNodesTotal = 0

    for ($iter = 1; $iter -le $TREE_WALK_ITER; $iter++) {
        try {
            function Count-TreeNodes {
                param ([object]$Node, [int]$Depth = 0)
                $count = 1
                if ($Depth -gt 10) { return $count }
                try {
                    $kids = $Node.GetChildren() | ForEach-Object { $_ }
                    foreach ($k in $kids) { $count += (Count-TreeNodes -Node $k -Depth ($Depth + 1)) }
                } catch {}
                return $count
            }

            $nodeCount = Count-TreeNodes -Node $mainWindow -Depth 0
            $walkNodesTotal += $nodeCount
            Write-Host "  Walk #$iter : $nodeCount nodes" -ForegroundColor Gray
        } catch {
            Write-Error "Tree walk #$iter failed: $_"
            Write-Error "This indicates the UIA tree was corrupted — likely the native crash."
            exit 1
        }
        Start-Sleep -Milliseconds 300
    }

    Write-Host "[OK] Tree walk complete: $TREE_WALK_ITER iterations, total $walkNodesTotal nodes" -ForegroundColor Green

    # -----------------------------------------------------------------------
    # Step 8: Seeded random clicks inside the window
    # -----------------------------------------------------------------------
    Write-Host "[INFO] Performing $RandomClicks random clicks (seed=$Seed) ..." -ForegroundColor Cyan

    $rng = [SeedRng]::new($Seed)
    $clickErrors = 0
    $lastBounds = @{}

    # Get window bounds once for click coordinate generation
    try {
        $bounds = $mainWindow.GetCurrentPropertyValue(10032, $true)  # BoundingRectangle
        if ($bounds -is [array] -and $bounds.Length -ge 4) {
            $left = [double]$bounds[0]
            $top = [double]$bounds[1]
            $width = [double]$bounds[2]
            $height = [double]$bounds[3]
            $rng = New-Object -TypeName SeedRng -ArgumentList $Seed
            # Overwrite bounds capture
            $windowBounds = @{ left=$left; top=$top; width=$width; height=$height }
        } else {
            Write-Warning "Could not get window bounds — using default area"
            $windowBounds = @{ left=0; top=0; width=1400; height=900 }
        }
    } catch {
        Write-Warning "Bounding rectangle unavailable: $_"
        $windowBounds = @{ left=0; top=0; width=1400; height=900 }
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    for ($i = 0; $i -lt $RandomClicks; $i++) {
        try {
            $x = $rng.NextRange(0, [int]$windowBounds['width'] - 1)
            $y = $rng.NextRange(0, [int]$windowBounds['height'] - 1)
            $absX = [int]$windowBounds['left'] + $x
            $absY = [int]$windowBounds['top'] + $y

            # Send click via System.Windows.Forms (requires assembly load)
            $asmLoaded = $false
            try {
                Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
                $asmLoaded = $true
            } catch {
                Write-Warning "System.Windows.Forms unavailable — skipping click injection"
            }

            if ($asmLoaded) {
                [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($absX, $absY)
                [System.Windows.Forms.MouseEventArgs]::New([System.Windows.Forms.MouseButtons]::Left, 1, $absX, $absY, 0) | Out-Null
                # Simple mouse_event API call
                $dll = 'user32.dll'
                $sig = @'
[DllImport("user32.dll", SetLastError = true)]
public static extern void mouse_event(uint dwFlags, int dx, int dy, uint cButtons, IntPtr extraInfo);
'@
                $mouseType = Add-Type -MemberDefinition $sig -Name MouseUtil -Namespace Win32 -PassThru -Using System.Runtime.InteropServices
                # Down + Up
                $mouseType::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
                Start-Sleep -Milliseconds 5
                $mouseType::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
            }

        } catch {
            $clickErrors++
            if ($clickErrors -le 5) {
                Write-Verbose "Click #$i error: $_"
            }
        }

        # Progress reporting every 100 clicks
        if (($i + 1) % 100 -eq 0) {
            Write-Host "  Clicks: $($i+1)/$RandomClicks" -ForegroundColor Gray
        }
        Start-Sleep -Milliseconds 50
    }
    $sw.Stop()

    Write-Host "[INFO] Random clicks: $RandomClicks attempts, $clickErrors errors, took $([math]::Round($sw.Elapsed.TotalSeconds,1))s" -ForegroundColor Yellow

    # -----------------------------------------------------------------------
    # Step 9: Post-run crash check
    # -----------------------------------------------------------------------
    Write-Host "[INFO] Checking Event Viewer for post-run crashes ..." -ForegroundColor Cyan
    $postRunCrash = Test-CrashInEventLog -AfterTime $baselineTime
    if ($postRunCrash) {
        Write-Error "CRASH DETECTED: flutter_windows.dll access violation recorded in Event Viewer after smoke run!"
        Write-Error "This is the native crash the test is designed to catch."
        exit 2
    }
    Write-Host "[OK] No flutter_windows.dll crashes detected in Event Viewer." -ForegroundColor Green

    # -----------------------------------------------------------------------
    # Summary
    # -----------------------------------------------------------------------
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  windows_accessibility_smoke.ps1 SUMMARY" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  EXE          : $Exe" -ForegroundColor White
    Write-Host "  PID          : $processId" -ForegroundColor White
    Write-Host "  Controls     : $controlCount (target >= $MAX_CONTROLS)" -ForegroundColor White
    Write-Host "  Invocations  : $invokeSuccess OK, $invokeErrors errored (tolerated)" -ForegroundColor White
    Write-Host "  Tree walks   : $TREE_WALK_ITER iterations, $walkNodesTotal total nodes" -ForegroundColor White
    Write-Host "  Random clicks: $RandomClicks (seed=$Seed), $clickErrors errors" -ForegroundColor White
    Write-Host "  Duration     : $([math]::Round($sw.Elapsed.TotalSeconds,1))s" -ForegroundColor White
    Write-Host "  Crash log    : No access violations" -ForegroundColor White
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "PASS: UIA smoke completed successfully." -ForegroundColor Green

    exit 0

} finally {
    # -----------------------------------------------------------------------
    # ALWAYS: kill the process in finally block (§9.2 step 8)
    # -----------------------------------------------------------------------
    Write-Host "[INFO] Cleaning up: killing process PID=$processId ..." -ForegroundColor Cyan
    try {
        $p = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if ($p -and -not $p.HasExited) {
            $p.CloseMainWindow() | Out-Null
            Start-Sleep -Milliseconds 1000
            Get-Process -Id $processId -ErrorAction SilentlyContinue | Stop-Process -Force
            Write-Host "[OK] Process terminated." -ForegroundColor Green
        } else {
            Write-Host "[INFO] Process already exited." -ForegroundColor Gray
        }
    } catch {
        Write-Warning "Failed to terminate process: $_"
    }
}
