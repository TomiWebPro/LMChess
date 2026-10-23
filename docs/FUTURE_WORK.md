# Future Work

Status: open items only
Last updated: 2026-10-23 (UTC) — arena `VariantReviewLog` recording path
closed for review: stale "chaotic games not recorded" wiring note at
`arena_screen.dart` corrected (games ARE recorded losslessly since 61d58d7)
and 4 new tests pin the recording/isolation/E2E path; §2.6 still no upstream
fix (flutter/flutter#175041 open, PR #190903 unmerged) → local 3.47.6 stays
on mitigation
Related: [Runbook](RUNBOOK.md), [Engine runtime](ENGINE_RUNTIME.md),
[Variant rules](VARIANT.md), [Chess engine notes](CHESS_ENGINE.md)

All planned implementation, test coverage, and testability work is complete.
The remaining items are release validation, CI automation, and process
integration that cannot be closed on Linux. Completed work and the crash
investigation history are preserved in `automation-track.md` and git history.

Verified baseline (2026-10-22):

- `flutter analyze` — 0 issues.
- `flutter test` — 631/631 pass.
- `flutter build linux --release` — succeeds; release binary starts under Xvfb.
- Roadmap §12 — 18/18 deliverables present; §10.1–10.8 refactors complete.
- Interaction matrix §6 — all 12 screen/widget suites present.
- §15 Chessboard interaction & motion is complete: §15.1 drag-and-drop,
  §15.2 move-animation layer, §15.3 fast ply scrubbing, and §15.4 premove /
  multipremove shipped.

---

## 9. Windows integration and native smoke (P0 — not executed)

The test and tooling are written, but neither layer has been run against a
Windows release build. This is the only remaining functional verification.

### 9.1 Windows integration test

`integration_test/accessibility_windows_test.dart` exists (12 tests: all 8
destinations, dialogs, rapid Play↔Watch switches, theme/resize churn). It
compiles cleanly but has not been run on Windows. It still needs a real Windows
desktop run:

```powershell
flutter test integration_test/accessibility_windows_test.dart -d windows
```

### 9.2 UIA process smoke

`tool/windows_accessibility_smoke.ps1` exists and implements the §9.2
requirements: launch release exe, attach UIAutomation, require ≥40 invocable
controls, walk the UIA tree, perform 500 seeded random clicks, check Event
Viewer for a fresh `flutter_windows.dll` `0xC0000005`, and always kill the app.

It has **not** been run with an accessibility client attached. Required run:

```powershell
flutter build windows --release
powershell -ExecutionPolicy Bypass -File tool/windows_accessibility_smoke.ps1 `
  -Exe build\windows\x64\runner\Release\llm_chess_arena.exe `
  -RandomClicks 500
```

Then repeat once with Narrator or Inspect.exe attached. Record the Flutter
revision, build hash, date, control count, click count, and Event Viewer result
in `automation-track.md`.

**Done when:** the smoke survives 500 random clicks and ≥40 control invocations
with no new `0xC0000005`/`0xC000041D` event, both with and without an
accessibility client attached (acceptance criteria 14.1–14.2).

---

## 11. CI/CD (P0/P1 — incomplete)

### 11.3 Nightly Windows gate (P0 — workflow fixed, awaiting first Windows run)

`.github/workflows/ci.yaml` now defines a scheduled `windows-nightly` job
(nightly + `workflow_dispatch`) that builds the Windows release, runs the
§9.1 integration test, invokes the §9.2 UIA smoke, and uploads output
artifacts. It has not completed a run yet, so the gate is not proven.

Process fixes shipped 2026-10-22:

- The integration-test and UIA-smoke steps now fail the job on **any**
  non-zero exit. Previously only the smoke's exit code 2 gated the job — a
  red §9.1 integration test or a smoke exit code 1 (exe/app failure) could
  pass silently. Event Viewer excerpt export now triggers on any smoke
  failure, not only the crash path.
- The job no longer pre-launches the release exe. The UIA smoke script owns
  the app lifecycle (it launches via `Start-Process -PassThru` and always
  kills the process in its own `finally` block, §9.2 steps 3 + 8). The
  previous job-level `Start-Process` double-launched the app, splitting UIA
  attachment and seeded random clicks between two windows.

Remaining:

- Trigger the workflow and confirm all steps actually pass on a Windows
  runner. The UIA smoke needs an interactive desktop/UIA session; GitHub's
  hosted `windows-latest` runner may not provide one, so a dedicated VM may be
  required (see §13).

**Done when:** a green scheduled Windows run is linked from the repository and
its artifacts prove the native gate passed.

### 11.4 Coverage (P2 — DONE)

`flutter test test/ui --coverage` is now run in CI as a non-gating step on the
ubuntu-gate job (`continue-on-error: true`): it generates `coverage/lcov.info`
and uploads it as a `coverage-lcov` artifact so coverage trends can be
reported. Coverage is explicitly not the success metric — the goal is that
every interaction-matrix control is exercised and every transition asserts
the semantics invariants, not a line-coverage number. See
`automation-track.md` for the run evidence.

### 11.5 Dependency hygiene (P2 — DONE)

`pubspec.yaml` declared five dependencies with zero references anywhere in
`lib/`, `test/`, `tool/`, or `integration_test/`, polluting the dependency
graph and the pub cache restore in CI. Removed:

- `import_lint` (dev) — no `import_lint.yaml`, no `dart run import_lint`
  invocation, no CI integration anywhere; completely dead.
- `cupertino_icons` — Flutter template leftover; no `CupertinoIcons` usage.
- `intl` — no direct imports; demoted to transitive (still required by
  `cupertino_ui` / `flutter_localizations` via the SDK chain).
- `collection` — no direct imports; demoted to transitive (still required by
  `flutter_riverpod` / the Flutter SDK).
- `hive_ce` — only `hive_ce_flutter` is imported; `hive_ce` demoted to
  transitive (still required by `hive_ce_flutter`).

Evidence: `flutter analyze` → `No issues found!`; full `flutter test` →
631/631 pass unchanged after the pubspec edit. See `automation-track.md`
for the run log.

### 11.6 Linux release build + Xvfb smoke on the ubuntu gate (P1 — DONE)

`flutter analyze` + `flutter test` cannot catch runner/plugin/CMake
regressions — on every push the CI Linux job checked Dart only, while the
release binary was never built or started anywhere except the nightly
Windows job. The `ubuntu-gate` job now hard-gates the Linux release
artifact on every push/PR:

- **Install Linux desktop build deps** — `ninja-build pkg-config
  libgtk-3-dev libsecret-1-dev libjsoncpp-dev xvfb openbox` (ubuntu-latest
  preinstalls clang/cmake/ninja/pkg-config but not the GTK/Secret/jsoncpp
  dev headers; xvfb + openbox are the headless-start recipe from
  `docs/RUNBOOK.md` "Linux desktop").
- **Build Linux release** — `flutter build linux --release`.
- **Smoke start Linux release (Xvfb)** — `set -euo pipefail`; starts
  `Xvfb :77` + `openbox` with `LIBGL_ALWAYS_SOFTWARE=1`, launches
  `build/linux/x64/release/bundle/llm_chess_arena`, requires the process to
  survive a 15 s window (`kill -0`), then terminates it with a bounded
  SIGTERM→SIGKILL teardown. The 2026-10-22 baseline proved this binary
  starts under Xvfb; the step makes that a hard gate on every push. Engine
  assets are gitignored and first-run Stockfish extraction is lazy
  (`lib/main.dart`), so startup must not require an engine download.

Evidence: workflow re-parses clean via PyYAML (ubuntu-gate now 11 steps,
windows-nightly untouched); all new run blocks pass `bash -n`; locally the
exact commands run green — `flutter analyze` → `No issues found!`,
`flutter build linux --release` → `✓ Built
build/linux/x64/release/bundle/llm_chess_arena`, and the exact smoke recipe
(Xvfb :77 + openbox + release binary) exits 0 with the binary alive after
15 s; full `flutter test` → 631/631 pass unchanged (no Dart changes). See
`automation-track.md` for the run log.

---

## 15. Chessboard interaction and motion (P1/P2 — complete)

The chessboard interaction roadmap is shipped in full: §15.1 drag-and-drop,
§15.2 explicit from→to move-animation layer, §15.3 keyboard + move-list ply
scrubbing, and §15.4 premove / multipremove (click-click or drag queue up to
five premoves with ghost pieces + numbered destination markers, validated in
sequence, executing one per human turn through the normal move path, with
right-click/Escape/Clear cancellation and queen-default promotion premoves).
Evidence for each shipped tranche is in `automation-track.md`; the premove
suite is `test/ui/premove_test.dart`.

---

## 2.6 Upstream dependency (P1 — external)

The root cause is in the Flutter Windows accessibility bridge
(`flutter/flutter#175041`); the app-level semantics hardening is a mitigation,
not a fix. The known-issue note is now part of the Flutter upgrade gate in
`docs/RUNBOOK.md` (step 8 removes it). On each Flutter upgrade:

- Check whether the upstream fix has landed and in which revision.
- Re-run the §9.1/§9.2 gates before removing the known-issue warning.
- Keep the `ExcludeSemantics`/`IndexedStack` hidden-tab guard and stable
  semantics roots regardless of the upstream status.

Status check 2026-10-23 (RUNBOOK upgrade-gate step 1; local SDK Flutter 3.47.6
stable, engine `b8c8d3d8d5` / `692136cb65`, released 2026-09-30): **no fix has
landed in a stable release.** Upstream `flutter/flutter#175041` remains open
(P3, `needs repro info`), and candidate engine fix
`flutter/flutter#190903` (`[Windows] Avoid null parent dereference in
AccessibilityBridge`) is **open and unmerged** (`merged: false`, last updated
2026-10-21, CI state `unstable`). The fix revision is therefore unknown and no
stable engine contains it. Field reports still reproduce the crash on
3.44.9/3.47.x stable; one independent beta test reported the AXTree
root-mismatch did not reproduce on `3.48.0-0.1.pre`, but UIA control exposure
remained host-only, so that beta is **not** evidence of a complete fix. Keep
the known-issue note, semantics hardening, and upgrade gate.

**Done when:** a Flutter revision containing the fix is validated on Windows,
or the upstream issue is closed and the workaround is formally retired.

---

## 13. Open decisions (not scheduled)

- **Windows runner:** hosted Windows runner vs. a dedicated VM with an
  interactive desktop session for UIA/Narrator. Needed for §11.3.
- **Safe mode:** should the app disable custom semantics for screen-reader
  users until the engine fix lands? Current preference is to fix/ship the tree,
  not add an accessibility regression.
- ~~**Telemetry isolation**~~ **DECIDED 2026-10-23:** `StatsLog`,
  `QualityLog`, `ReviewLog`, and `VariantReviewLog` are now injectable stores
  (per-`ProviderScope` instances exposed through `statsLogProvider` /
  `qualityLogProvider` / `reviewLogProvider` / `variantReviewLogProvider`).
  Screens read/write their store via `ref.read`, so each `ProviderScope`
  gets fully isolated state and the old process-static singletons +
  `resetTelemetry` test hygiene are gone. Run evidence: `automation-track.md`.

---

## 14. Remaining acceptance criteria

Only these are still open:

- [ ] **14.1** Windows UIA smoke survives 500 random clicks and ≥40 control
      invocations on a release build, with Narrator or Inspect.exe attached.
- [ ] **14.2** Event Viewer shows no new `flutter_windows.dll` `0xC0000005`
      during the smoke.

Already met: 14.3 (`flutter test` green, zero pending timers), 14.4 (every
matrix control has an observable-behavior test), 14.5 (semantics suite reports
zero duplicate ids/null parents/reparenting), 14.6 (monkey sweeps complete
without Dart exceptions), 14.7 (`flutter analyze` clean), 14.8 (Flutter
upgrade gate is part of `docs/RUNBOOK.md` and referenced by the release
process in `docs/ENGINE_RUNTIME.md`).

---

Section numbers not present here (§5–§8, §10, §12) refer to completed work;
see the pre-2026-10-21 revision of this file in git history or
`automation-track.md`.
