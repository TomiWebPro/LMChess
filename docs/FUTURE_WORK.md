# Future Work

Status: open items only
Last updated: 2026-10-25 (UTC) — §11.41 (agent-setup silent-swallow
closure — the final two screen-level silent-swallow catches in lib/
closed). A fresh independent parallel subagent audit (full
FUTURE_WORK.md open-item inventory incl. every "Done when" string; an
end-to-end ci.yaml defect audit; a lib/test/tool convention + marker
audit) again confirmed ZERO FUTURE_WORK.md open items implementable-and-
verifiable on this Linux host (§9.1/§9.2/§11.3/§14.1-§14.2 Windows-
native-blocked, §2.6 upstream-external — live-checked this run via the
GitHub API: flutter/flutter#190903 still `merged: false` — the `dart
format` gate owner-decision-pending, coverage-artifact comparison
needing ≥2 real CI runs), NO P0 (crash) or P1 (correctness) code or
workflow-file defects, and the ci.yaml workflow clean end-to-end (strict
duplicate-key PyYAML: ubuntu-gate 13 + windows-nightly 12 steps, 27
timeout-minutes keys; all bash blocks pass `bash -n`; both windows
PowerShell blocks parse with 0 errors under real pwsh 7.6.8 with the
§11.38 `$LASTEXITCODE` null-guards). The audit's one suspected smoke-gate
race was verified as a FALSE POSITIVE — the post-loop geometry verdict
uses `${WIDTH:-0}`/`${HEIGHT:-0}` plus `WIDTH=0`/`HEIGHT=0`
initializers, so a vanished window at the final loop iteration still
fails the ≥100x100 check. The lib/test/tool audit DID surface genuine
remaining silent-swallow catches, proving §11.40's "last silent-swallow
in lib/" claim wrong; this run closes the final two SCREEN-level ones as
its ONE deliverable: `lib/src/ui/screens/agent_setup_screen.dart`
`_loadKeyPresence` (secure-store READ failure silently rendered as "No
key stored" — the read-side sibling of the §11.24/§11.25 write/delete
fixes, so "store failed" read exactly like "no key" to operators) and
`_testConnection` (a throwing connection probe dropped with zero
diagnostics). Both catches now surface the failure via `dart:developer`
`log()` (name `agent-setup`, error + stack trace) with ZERO behavior
change, per the §11.35/§11.40 diagnostics standard; the class + method
docs restate the contract ("store failed" logged, "no key" quiet). Two
new deterministic offline widget tests in `test/ui/agent_setup_test.dart`
pin the degrade contract: a read-failing `SecureKeyStore` fake → the
edit-mode indicator degrades to lock_open (no Clear action) with the
throw contained; a throwing `connectionTesterProvider` probe → the
generic "Connection failed" banner with the throw contained and no
pending timer. Evidence: `flutter analyze` → `No issues found! (ran in
2.4s)`; `flutter test test/ui/agent_setup_test.dart` → 34/34 pass (32
baseline + 2 new); related seams (connection_tester 8, resolve_api_key
6, swallow_diagnostics 8) → 22/22 pass; full `flutter test` → 671/671
pass (669 baseline + 2 new). Recorded in `automation-track.md` (Run
Log); per the open-items-only rule this file gains no new completed-work
section — no open FUTURE_WORK item was touched (§9.1/§9.2/§11.3/§14
remain Windows-blocked, §2.6 upstream-external; the `dart format` gate
and the coverage-artifact comparison still await their owner decisions
/ ≥2 real CI runs).
Previously (2026-10-25) — §11.40 (arena-chaos runner-failure
diagnostics — the last silent-swallow catch in lib/ closed). A fresh
independent parallel subagent audit (full FUTURE_WORK.md open-item
inventory incl. every "Done when" string; an end-to-end ci.yaml defect
audit; a lib/test/tool convention + marker audit) again confirmed ZERO
FUTURE_WORK.md open items implementable-and-verifiable on this Linux
host (§9.1/§9.2/§11.3/§14.1-§14.2 Windows-native-blocked, §2.6
upstream-external — live-checked this run via the GitHub API:
flutter/flutter#190903 still `merged: false` — the `dart format` gate
owner-decision-pending, coverage-artifact comparison needing ≥2 real CI
runs), NO P0 (crash) or P1 (correctness) code or workflow-file defects,
and the ci.yaml workflow clean end-to-end. The lib/test/tool audit DID
surface one genuine code-P2 diagnostics gap, closed as this run's ONE
deliverable: `lib/src/ui/screens/arena_screen.dart`'s chaotic-game
runner-failure catch (`catch (_) { result = null; }`) — the LAST
silent-swallow catch site in lib/, inconsistent with the repo's own
§11.35 diagnostics standard — dropped an `AgentRunner.runTurn`
exception with zero diagnostics, so a genuine runner-internal bug was
indistinguishable from a provider outage in the stats. The catch now
surfaces the failure via `dart:developer` `log()` (name `arena-chaos`,
error + stack trace) with zero behavior change; a test-only seam
(`ArenaScreen({..., chaosRunner})` per the §10.5/§11.24 precedent) plus
a deterministic offline widget suite (`test/ui/arena_chaos_diagnostics_test.dart`,
2 tests) pin the degrade contract — a throwing runner → every chaotic
turn plays the seeded fallback (`ply.fallback == true`), the tournament
still concludes both games with valid chains, no exception escapes, and
StatsLog records `providerError: true`; the default no-seam path is
pinned unchanged (model plies, zero providerError). Evidence:
`flutter analyze` → `No issues found! (ran in 2.3s)`; new suite 2/2
pass; related suites 72/72 pass; full `flutter test` → 669/669 pass
(667 baseline + 2 new). Recorded in `automation-track.md` (Run Log);
per the open-items-only rule this file gains no new completed-work
section — no open FUTURE_WORK item was touched (§9.1/§9.2/§11.3/§14
remain Windows-blocked, §2.6 upstream-external; the `dart format` gate
and the coverage-artifact comparison still await their owner decisions
/ ≥2 real CI runs).
Previously (2026-10-24) — §11.39 (download-tool verification
honesty fix). A fresh independent parallel subagent audit (full
FUTURE_WORK.md open-item inventory incl. every "Done when" string; an
end-to-end ci.yaml defect audit; a lib/test convention + marker audit)
again confirmed ZERO FUTURE_WORK.md open items implementable-and-
verifiable on this Linux host (§9.1/§9.2/§11.3/§14.1-§14.2 Windows-
native-blocked, §2.6 upstream-external — live-checked this run via the
GitHub API: flutter/flutter#190903 still `merged: false` — the `dart
format` gate owner-decision-pending, coverage-artifact comparison still
needing ≥2 real CI runs, and the ~98-commit local queue still unpushable
— no GitHub credentials on this host), NO P0 (crash) or P1 (correctness)
code or workflow-file defects, and the ci.yaml workflow itself clean
(end-to-end fresh-eyes audit: no Linux-fixable defect found this run).
The lib/test/tool audit DID surface one genuine P1 correctness defect,
closed as this run's ONE deliverable: `tool/download_stockfish.dart`
`extractAndVerify` — the linchpin of the §11.7/§11.17 real-engine CI
gates — promised (its own doc comment, §11.19) that a binary failing
size/SHA-256/`file` verification after extraction is discarded + thrown,
but the code path after `verifyBinary` returned `false` printed
"verification failed after extraction; treating the archive as corrupt"
and then fell off the end of the `try` block **normally**: no
`_discardArchive`, no rethrow, so `fetchPlatform` reported
`FetchResult(ok: true, 'fetched')` and `main` exited 0 — the CI engine
download step stayed green with a wrongly-sized/hashed binary left in
`assets/engines/` and the unusable archive kept in the cache (the §11.19
self-heal re-download never ran). Fix: that branch now throws
`StateError('binary failed verification after extraction')`, so the
existing `on Object` handler discards archive + partial binary and the
bounded two-attempt loop performs the clean re-download, failing the
fetch honestly if the re-download is also bad. New deterministic offline
test (valid-archive-wrong-binary, loopback server) was proven to FAIL as
a false-green against the pre-fix code, then passes with the fix:
`ok: false`, exactly one re-download, archive + binary both gone; the 5
existing §11.19 tests and the real CLI happy path (`OK present`, uciok
handshake) are unchanged. Evidence: `flutter analyze` → `No issues
found! (ran in 2.4s)` (Flutter 3.47.6 stable, Dart 3.13.5); `flutter
test test/download_stockfish_test.dart` → 6/6 pass (5 existing + 1
new); full `flutter test` → 667/667 pass (All tests passed! — 666
baseline + 1 new); `dart run tool/download_stockfish.dart linux-x86-64`
→ `OK present` with size/sha256/file/uciok re-verified. Recorded in
`automation-track.md` (Run Log); per the open-items-only rule this file
gains no new completed-work section — no open FUTURE_WORK item was
touched (§9.1/§9.2/§11.3/§14 remain Windows-blocked, §2.6
upstream-external; the `dart format` gate and the coverage-artifact
comparison still await their owner decisions / ≥2 real CI runs).
Previously (2026-10-24) — §11.38 (Windows-gate exit-code
honesty fix). A fresh independent parallel subagent audit (full
FUTURE_WORK.md open-item inventory incl. every "Done when" string; an
end-to-end ci.yaml defect audit; a lib/test convention + marker audit)
again confirmed ZERO FUTURE_WORK.md open items implementable-and-
verifiable on this Linux host (§9.1/§9.2/§11.3/§14.1-§14.2 Windows-
native-blocked, §2.6 upstream-external — live-checked this run via the
GitHub API: flutter/flutter#190903 still `merged: false` — the `dart
format` gate owner-decision-pending, coverage-artifact comparison still
needing ≥2 real CI runs, and the ~96-commit local queue still unpushable
— no GitHub credentials on this host) and NO P0 (crash) or P1
(correctness) code or workflow-file defects. The ci.yaml audit DID
surface one new, Linux-verifiable P2 gate-honesty defect, closed as this
run's ONE deliverable: both windows-nightly gate steps (the §9.1
integration step and the §9.2 UIA smoke step) ended `Exit
$LASTEXITCODE`, and a never-launched gated command left `$LASTEXITCODE`
at `$null` — `$null -ne 0` printed the `::error::` line but `Exit $null`
returns 0 in PowerShell 7, a silent false green (the integration step
explicitly sets `$ErrorActionPreference = "Continue"`, so its
never-launched case degraded to exit 0). Both steps now guard
`if ($null -eq $LASTEXITCODE) { ... Exit 1 }` before the existing
check — "no exit code recorded" is a hard gate failure; healthy paths
byte-identical (proven under real PowerShell 7.6.8: cmd-not-found →
exit 1 [was 0]; child exit 7 → exit 7 OLD/NEW; child exit 0 → green 0
OLD/NEW; full edited blocks run verbatim against both classes).
Evidence: `flutter analyze` → `No issues found! (ran in 2.2s)`; full
`flutter test` → 666/666 pass (01:55, All tests passed! — no Dart
changes); strict duplicate-key PyYAML re-parse clean (ubuntu-gate 13 +
windows-nightly 12 steps; 27 timeout-minutes keys); all 7
windows-nightly PowerShell blocks parse with 0 errors under real
PowerShell 7.6.8; all 13 bash blocks pass `bash -n`. Recorded in
`automation-track.md` (Run Log); per the open-items-only rule this file
gains no new completed-work section — no open FUTURE_WORK item was
touched (§9.1/§9.2/§11.3/§14 remain Windows-blocked, §2.6
upstream-external; the `dart format` gate and the coverage-artifact
comparison still await their owner decisions / ≥2 real CI runs).
Previously (2026-10-24) — §11.36 docs/baseline accuracy run on the
terminal branch: an independent parallel subagent audit (full
FUTURE_WORK.md open-item inventory + end-to-end ci.yaml defect audit)
confirmed ZERO FUTURE_WORK.md open items implementable-and-verifiable on
this Linux host (§9.1/§9.2/§11.3/§14.1-§14.2 Windows-native-blocked, §2.6
upstream-external, the `dart format` gate owner-decision-pending, the
coverage-artifact comparison needing ≥2 real CI runs, and the ~92-commit
local queue still unpushable — no GitHub credentials on this host) and NO
P0 (crash) or P1 (correctness) code or workflow-file defects. The one real
finding was a stale-fact in the source of truth: the "Verified baseline"
block still asserted 651/651 @ 2026-10-22 while the suite has been 666/666
since §11.35. This run re-verified the full baseline itself — `flutter
analyze` → `No issues found! (ran in 2.2s)`; full `flutter test` → 666/666
pass (01:55, All tests passed!); `flutter build linux --release` → `✓
Built build/linux/x64/release/bundle/llm_chess_arena`; release binary
alive after 20s under a fresh Xvfb :117 (no orphan — the §11.27 env
contract) — and updated the block in place to (2026-10-24) 666/666.
Recorded in `automation-track.md` (Run Log); per the open-items-only rule
this file gains no new completed-work section — no open FUTURE_WORK item
was touched (§9.1/§9.2/§11.3/§14 remain Windows-blocked, §2.6
upstream-external; the `dart format` gate and the coverage-artifact
comparison still await their owner decisions / ≥2 real CI runs).
Previously (2026-10-24) — §11.35: the §11.33 audit-trail
code-P2 list is now FULLY closed — the §11.34 diagnostics pattern
(`dart:developer` `log()` on silent-swallow catch sites, zero
behavior change) is extended to the six remaining borderline sites:
`backend_bridge.dart` `testAgentConnection` (name `connection-tester`;
doc contract restated — failure reason surfaced with no secret
material) and `rawToolCallFrom` (name `backend-bridge`);
`OpenAiProvider`/`AnthropicProvider`/`GeminiProvider` `testConnection`
(names `openai-provider`/`anthropic-provider`/`gemini-provider`;
Ollama inherits the openai site); `variant_review.dart` `evaluateBoard`
(name `variant-review`); `variant_projection.dart` `project` (name
`variant-projection`). New deterministic offline suite
`test/swallow_diagnostics_test.dart` (8 tests, fake `http.BaseClient`
throwing before any wire I/O) pins `rawToolCallFrom`'s malformed-JSON
raw-preserved/null-map path and the transport-failure→false contract
for all three providers (+ a 200→true happy path). Verified with
`flutter analyze` → `No issues found! (ran in 2.5s)`, related suites
→ 56/56 pass, and full `flutter test` → 666/666 pass (658 baseline +
8 new). Recorded in `automation-track.md` (Run Log); per the
open-items-only rule this file gains no new completed-work section —
no open FUTURE_WORK item was touched (§9.1/§9.2/§11.3/§14 remain
Windows-blocked, §2.6 upstream-external; the `dart format` gate and
the coverage-artifact comparison still await their owner decisions /
≥2 real CI runs).
Previously (2026-10-24) §11.34: the §11.33 audit-trail
code-P2 list is now empty — its top candidate, "engine failure
diagnostics silently swallowed in lib/src/review/engine_adapter.dart",
is closed. `dart:developer` `log()` calls now surface the four
silent-swallow sites (zero behavior change): the
`HeuristicEvaluator._extractPlacement` decode-error catch (still
degrades to "unsupported"), the stderr drain/surface sub (each
non-empty stderr line at warning), the stdout sub's onError, and the
exit-code watcher ("exited unexpectedly (code N)" — unexpected-exit
path only, since dispose() nulls `_process` first). The stale class
doc ("fen or pieces") now states the true contract: "fen field
required; boards without FEN interop out of scope". New deterministic
offline suite `test/engine_adapter_test.dart` (7 tests); verified
with `flutter analyze` → `No issues found!` and full `flutter test`
→ 658/658 pass (651 baseline + 7 new). Recorded in
`automation-track.md` (Run Log); per the open-items-only rule this
file gains no new completed-work section — no open FUTURE_WORK item
was touched (§9.1/§9.2/§11.3/§14 remain Windows-blocked, §2.6
upstream-external; the `dart format` gate and the coverage-artifact
comparison still await their owner decisions / ≥2 real CI runs).
Previously (2026-10-24) §11.33: §11.16's maintained-in-place
timeout-minutes contract is reconciled with the current workflow after the
§11.31 CI P3 #2 merge. The live §11.16 section still asserted the
pre-merge state — "all 26 steps", "all 28 `timeout-minutes` keys
(26 steps + 2 jobs)", and a separate "coverage 30" bound — while the
§11.31 merge absorbed the coverage RUN step into the gating Test step,
and the §11.17 header recap's "26 steps (… coverage 30 …)" parenthetical
had the same stale count. The workflow now has ubuntu-gate 13 +
windows-nightly 12 = **25 steps** and 25 + 2 jobs = **27 timeout-minutes
keys** (re-measured this run with the strict duplicate-key PyYAML
loader: 25/25 steps carry exactly one `timeout-minutes:` key; §11.16's
step list drops the phantom "coverage 30" entry — coverage collection is
bounded by the merged Test step's `timeout-minutes: 30` — and the
§11.16 bullet that promised "the coverage step keeps
`continue-on-error: true`" now states the true post-merge contract:
the §11.4 "coverage never reddens the gate" property holds at the
ARTIFACT level only, via the §11.22 upload step's `continue-on-error:
true` + `if-no-files-found: warn`, with a coverage-collection failure
with all tests green being the documented accepted residual of the
merge (the ci.yaml step comment §11.31). The §11.16 evidence block and
the §11.17 recap parenthetical are updated to match (25 steps; the two
`bash -n` "failures" are the Windows-only §9.1/§9.2 PowerShell blocks,
per the §11.12 precedent). No Dart/test/workflow-file changes — a pure
docs-contract correction, verified with `flutter analyze` → `No issues
found!` and the full `flutter test` → 651/651 pass (01:54, All tests
passed!). Recorded in `automation-track.md` (Run Log); per the
open-items-only rule this file gains no new completed-work section —
no open FUTURE_WORK item was touched (§9.1/§9.2/§11.3/§14 remain
Windows-blocked, §2.6 upstream-external; the `dart format` gate and the
coverage-artifact comparison still await their owner decisions / ≥2 real
CI runs).
Previously (2026-10-24) §11.32:
Event Viewer excerpt export no longer aborts on the no-matching-events
failure class (details in `automation-track.md` Run Log). On the §9.2
NON-crash failure class (control count < 40, uninvocable controls — no
0xC0000005) no fresh Application-log event exists, so `Get-WinEvent`
writes a `NoMatchingEventsFound` error; the "Run UIA smoke (§9.2)" run
block never overrode `$ErrorActionPreference` (the §9.1 block sets
`"Continue"`, this one deliberately stays strict), so under the runner
wrapper's prepended `'stop'` the error aborted the script BEFORE the
`::error::` line and before `Exit $LASTEXITCODE` — the smoke's §9.2
exit-code semantics (0/1/2, "2=crash detected in Event Viewer")
degraded to 1 at the step level and the excerpt carried no Event
Viewer data exactly when the §11.30 diagnostics are needed. The
command now ends `-ErrorAction SilentlyContinue`: the expected no-match
case respects the pipeline (empty excerpt, still uploaded via the
§11.30 step's `if-no-files-found: warn`), strictness elsewhere
unchanged, and on the crash class the fix is inert (byte-identical
export, proven). Windows-only execution path — no Linux gate impact;
no Dart/test files changed. Evidence: `flutter analyze` → `No issues
found!`; full `flutter test` → 651/651 pass (01:52, no Dart changes);
strict duplicate-key PyYAML re-parse clean (ubuntu-gate 13 +
windows-nightly 12 steps; 27 timeout-minutes keys); all bash run
blocks pass `bash -n` (the 2 "failures" are the Windows-only §9.1/§9.2
PowerShell blocks, per the §11.12 precedent); the actual edited block
parses with 0 errors under real PowerShell 7.6.8 (user-local
`~/sdk/pwsh`, Parser.ParseInput + scriptblock::Create); and the
abort-vs-survive semantics are proven empirically with verbatim
OLD/HEAD vs NEW failure branches under a `Write-Error` stub of the
exact non-terminating error class — OLD: abort, exit 1, no `::error::`,
0-byte excerpt; NEW: `::error::` printed, exit 2 preserved, empty
excerpt; crash class: OLD and NEW byte-identical (exit 2, real 148-byte
excerpt). The open-item set is otherwise unchanged: §9.1/§9.2/§11.3/
§14.1-§14.2 remain Windows-native; §2.6 remains upstream-external
(flutter/flutter#190903 still `merged: false` per the §11.31 live
check); the `dart format` gate (102/127-file churn) remains
pending its explicit owner decision; coverage-artifact comparison still
needs ≥2 real CI runs; and the ~80-commit local queue still cannot be
pushed (no GitHub credentials on this host).
Previously (2026-10-24) §11.31: CI P3 #2 CLOSED — the
ubuntu-gate's `flutter test` + `flutter test test/ui --coverage` pair
is merged into ONE full-suite `flutter test --coverage` step (details
in `automation-track.md` Run Log). This run made the §11.4-owner
decision the §11.29/§11.30 audits recorded as pending: the merged step
gates on the test results and produces `coverage/lcov.info` as a
byproduct of the same run; lcov semantics widen from test/ui-only to
full-suite (70 SF entries vs 66 — adding san.dart + the storage layer,
exercised only by unit suites); measured 02:04 vs the old pair's
~3m38s (~48% less test-execution per push); the §11.22 upload keeps
`if: always()` + `continue-on-error: true` + `if-no-files-found: warn`
so artifact-level failures still can never redden the gate. The
open-item set is otherwise unchanged: §9.1/§9.2/§11.3/§14.1-§14.2
remain Windows-native; §2.6 remains upstream-external
(flutter/flutter#190903 re-checked live: still `merged: false`); the
`dart format` gate (102/127-file churn) remains pending its explicit
owner decision; coverage-artifact comparison still needs ≥2 real CI
runs; and the ~80-commit local queue still cannot be pushed (no GitHub
credentials on this host). Evidence: `flutter analyze` → `No issues
found! (ran in 2.3s)`; full `flutter test` → 651/651 pass (01:53);
merged `flutter test --coverage` → 651/651 pass (02:04, lcov.info
10,774 lines / 70 SF); workflow re-parses clean via a strict
duplicate-key PyYAML loader (ubuntu-gate 13 + windows-nightly 12
steps; continue-on-error steps now ubuntu-gate 1 + windows-nightly 1;
27 timeout-minutes keys); all 13 bash run blocks pass `bash -n` (the 2
"failures" are the Windows-only §9.1/§9.2 PowerShell blocks, per the
§11.12 precedent). Recorded in `automation-track.md` (Run Log); per
the open-items-only rule this file gains no new completed-work section
(§11.4's mechanism description was updated in place).
Previously (2026-10-24) §11.29: hourly NO-ACTIONABLE-ITEM
run (terminal branch). An independent parallel subagent audit (full
section inventory, track "Next:" clauses, marker grep across
lib/test/tool/integration_test/.github, docs/ roadmap scan) confirms
no open item here is implementable-and-verifiable on this Linux host:
§9.1/§9.2/§11.3/§14.1-§14.2 are Windows-native; §2.6 is
upstream-external (local SDK 3.47.6, flutter/flutter#190903 unmerged);
CI P3 #2 (coverage merge) stays open pending the explicit §11.4-owner
decision; the `dart format` gate stays open pending an explicit owner
decision; coverage-artifact comparison needs ≥2 real CI runs; the
75-commit local queue cannot be pushed (no GitHub credentials on this
host). Zero code/test/workflow changes — baseline re-verified only:
`flutter analyze` → `No issues found!`; full `flutter test` → 651/651
pass (02:06). No open item was touched, so per the open-items-only rule
this file gains no new completed-work section. Recorded in
`automation-track.md` (Run Log). Next: re-push once credentials exist;
trigger the §11.3 windows-nightly (`workflow_dispatch` or the 06:00 UTC
schedule) on hosted `windows-latest` per the §13 decision + §11.3
checklist — the ONLY remaining functional gap (§14.1-§14.2); or
re-check §2.6 on the next Flutter upgrade / when `flutter/flutter#190903`
lands.
Previously (2026-10-24) §11.28: the remaining docs-nits
batch from the §11.22/§11.23 audit trail is closed (CI P3 #2 — the
`flutter test` + `test/ui --coverage` merge — stays open pending the
explicit §11.4-owner decision the audit recorded; nothing left on this
host is P0/P1). A docs-accuracy pass with zero open-item code changes:
the stale "22 `test/ui/` suites" is corrected to 23 (the 23rd suite,
arena_variant_review_test.dart, shipped 2026-10-23 — the count was wrong
in the §11.21 docs-accuracy entry where 642 was right but 22 never was);
the §11.16 step/key counts now match the re-measured workflow
("24 steps/26 keys" → "26 steps/28 keys": windows-nightly grew 10 → 12
in §11.17; §11.27 programmatically asserted 26 steps + 2 jobs = 28 keys);
the live "Verified baseline" block reports 651/651; the two dangling
`docs/RUNBOOK.md "Linux desktop"` cross-references (FUTURE_WORK.md §11.6
and the ci.yaml build-deps comment) now point at the real "## Prereqs"
heading — where both the build-deps line and the documented
Xvfb + `LIBGL_ALWAYS_SOFTWARE=1` headless-start recipe live; and
`tool/download_stockfish.dart` `--help` now documents the `--direct`
alias for `--no-proxy` (the parser has accepted it since §11.19; the help
text never said so). Evidence: `flutter analyze` → `No issues found!`;
full `flutter test` → 651/651 pass (no Dart behavior change — help-text
+ docs only); ci.yaml re-parses with the §11.28 contract asserted
(ubuntu-gate 14 + windows-nightly 12 steps, 28 timeout-minutes keys);
`dart run tool/download_stockfish.dart --help` lists `--direct`.
Recorded in `automation-track.md` (Run Log); per the open-items-only rule
this file gains no new completed-work section — no open FUTURE_WORK item
was touched (§9.1/§9.2/§11.3/§14 remain Windows-blocked, §2.6
upstream-external).
Previously (2026-10-24) §11.27: the ubuntu-gate's
software-GL contract now reaches the processes that actually render.
Both Xvfb display steps previously prefixed `LIBGL_ALWAYS_SOFTWARE=1`
ONLY to the Xvfb launch line, so the two processes that matter — the
§11.15 release-binary smoke and the §11.11 headless integration suite —
inherited nothing. On a runner with a reachable GPU driver the app could
silently pick hardware GL, breaking the smoke's reproducibility: its
window-wait budget (15s + 75×1s) was measured under llvmpipe, where the
first frame takes ~26-52s, and the §11.15 gate exists precisely to catch
"alive but never properly rendered". Both steps now
`export LIBGL_ALWAYS_SOFTWARE=1` right next to `export DISPLAY=`,
matching the documented headless recipe (docs/RUNBOOK.md "## Prereqs":
`DISPLAY=:91 LIBGL_ALWAYS_SOFTWARE=1 ./build/.../llm_chess_arena`), and
the now-redundant env-prefix on the Xvfb lines is removed. Evidence:
workflow re-parses clean via strict duplicate-key PyYAML (ubuntu-gate 14
steps, windows-nightly 12 — step counts unchanged, only run-block content
changed); all 14 bash run blocks pass `bash -n` (the sole "failures" are
the two Windows-only §9.1/§9.2 PowerShell blocks, per the §11.12
precedent); the FULL modified smoke block run verbatim against the real
Linux release bundle on a fresh display → `smoke ok: release binary alive
after 15s and window mapped (title llm_chess_arena, 1278x720) under Xvfb
+ openbox`, exit 0, no :113 Xvfb or app orphan; the §11.11 headless suite
under the exported var → 12/12 pass, exit 0, no orphan; `flutter
analyze` → `No issues found! (ran in 2.2s)`; full `flutter test` →
651/651 pass (All tests passed! — no Dart changes). Recorded in
`automation-track.md` (Run Log); per the open-items-only rule this file
gains no new completed-work section — no open FUTURE_WORK item was
touched (§9.1/§9.2/§11.3/§14 remain Windows-blocked, §2.6
upstream-external).
Previously (2026-10-24) §11.26: the final code-P2 audit
candidate is closed — `test/clock_seam_test.dart`'s "defaults to
DateTime.now" test no longer asserts an absolute wall-clock year
(`expect(now.year, greaterThanOrEqualTo(2026))` — fails on any machine
with a pre-2026 clock). The default clock's output is now checked
relatively against an immediately adjacent `DateTime.now()` reading
(`now.difference(reference).inSeconds.abs() <= 300`): `DateTime.difference`
normalizes the local/UTC offset, no absolute epoch/year dependency exists,
and the test still proves the default resolves to the real wall clock.
Test-only determinism fix (no lib/ code changed). Evidence: `flutter
analyze` → `No issues found! (ran in 2.2s)`; `flutter test
test/clock_seam_test.dart` → 8/8 pass; clock-seam consumers → 84/84 pass;
full `flutter test` → 651/651 pass (01:54, All tests passed! — count
unchanged). Recorded in `automation-track.md` (Run Log); per the
open-items-only rule this file gains no new completed-work section — no
open FUTURE_WORK item was touched (§9.1/§9.2/§11.3/§14 remain
Windows-blocked, §2.6 upstream-external).
Previously (2026-10-24) §11.25: `resolveApiKey` no longer
silently swallows a secure-store read failure (closes audit code-P2 #2
from the §11.22/§11.23 trail — the read-side sibling of the §11.24 #3
fix). The old `catch (_)` at `agent_config.dart` `resolveApiKey` returned
`''` on ANY keychain read failure, so "store failed" read exactly like "no
key stored": a configured agent with a stored key silently degraded to
keyless (later auth failures with zero diagnostics; Test Connection failed
for the wrong reason). The empty catch is gone: the failure is logged via
`dart:developer` by default (the storage layer's own write-error fallback
pattern) or handed to a new optional `onReadError` sink mirroring
`LocalAppStore.onWriteError` — operators can now distinguish "no key"
(quiet `''`) from "store failed" (logged/observed). The resolver still
never throws and returns `''` on failure, preserving the keyless-backend
contract. Six new deterministic offline tests in
`test/resolve_api_key_test.dart` pin the short-circuits, the quiet
no-secret path, the degrades-to-'' path, and the onReadError report path.
Evidence: `flutter analyze` → `No issues found! (ran in 2.1s)`; `flutter
test test/resolve_api_key_test.dart test/turn_provider_test.dart
test/connection_tester_seam_test.dart` → 20/20 pass (6 new + 14 related);
full `flutter test` → 651/651 pass (645 + 6 new, 01:57, All tests
passed!). Recorded in `automation-track.md` (Run Log); per the
open-items-only rule this file gains no new completed-work section — no
open FUTURE_WORK item was touched (§9.1/§9.2/§11.3/§14 remain
Windows-blocked, §2.6 upstream-external).
Previously (2026-10-24) §11.24: the AgentSetupScreen "Clear stored
key" action no longer silently swallows a secure-store delete failure. The
repo convention (deterministic fakes, no empty catch) was broken at
`agent_setup_screen.dart` `_clearApiKey`: on a secure-store delete error the
old code cleared the UI state FIRST and let `catch (_)` swallow the failure,
so the screen switched to "No key stored" while the secret still existed in
the store — the user is lied to, and a later Save with a new key orphans the
old secret (it is overwritten under a NEW ref). The write path (`_save`) had
always surfaced the failure as a SnackBar, so Clear was the lone silent
swallow. The fix mirrors the save path: a failed `deleteApiKey` keeps the
"stored" indicator + Clear action and shows
`Could not clear the stored API key.`; the UI can no longer claim the key is
gone while the store still holds it. A test-only seam was added —
`AgentSetupScreen({..., keyStore})` (defaults to the platform
`SecureKeyStore`) — so the failure path is exercised with a deterministic
fake (no platform secure backend in widget tests). The Clear path previously
had ZERO test coverage; three new tests pin it (stored-key edit rendering,
success clears + indicator flips, failure shows SnackBar + keeps the
indicator; the failure test was proven to fail against the old swallow
logic). Evidence: `flutter analyze` → `No issues found! (ran in 2.3s)`;
`flutter test test/ui/agent_setup_test.dart` → 32/32 pass (29 + 3 new); full
`flutter test` → 645/645 pass (642 + 3 new, 01:54, All tests passed!).
Recorded in `automation-track.md` (Run Log); per the open-items-only rule
this file gains no new completed-work section.
Previously (2026-10-24) §11.23: ubuntu-gate no longer runs on the
nightly schedule. The `schedule` event in `on:` exists solely for the §11.3
windows-nightly gate, but ubuntu-gate carried no job-level `if:`, so every
nightly cron redundantly re-ran the FULL Linux gate (~15-20 min) with zero
code changes to exercise — wasted runner minutes and confusing red runs
from nothing. The job now carries `if: github.event_name != 'schedule'`
(+ a §11.23 comment): it runs on every push/PR and on manual
workflow_dispatch exactly as before and skips only the schedule event;
windows-nightly's own `if:` keeps it schedule/dispatch-only. Step counts
unchanged (ubuntu-gate 14, windows-nightly 12); no Dart/test files changed.
Evidence: workflow re-parses clean via a strict duplicate-key PyYAML scan
with the job if-contracts asserted; all bash run blocks pass `bash -n`;
`flutter analyze` → `No issues found! (ran in 2.2s)`; full `flutter test`
→ 642/642 pass (01:55, All tests passed!). Recorded in
`automation-track.md` (Run Log); per the open-items-only rule this file
gains no new completed-work section.
Previously (2026-10-24) §11.22 run: the ci.yaml coverage artifact
upload step could redden the gate. §11.4's documented contract is "coverage
can never redden the gate" (and the coverage RUN step carries
`continue-on-error: true`), but the `if: always()` "Upload coverage
artifact" step that followed it did **not** — a transient
`actions/upload-artifact@v4` backend failure (a documented Actions failure
mode) would have turned the entire ubuntu-gate job red on a non-gating
concern even though analyze/test/build/smoke/integration all passed. The
upload step now carries `continue-on-error: true`, so a failed artifact
push degrades to a warning exactly like a failed coverage run
(`if-no-files-found: warn` already covers the missing-lcov case). Steps
unchanged (ubuntu-gate 14, windows-nightly 12). No Dart/test files changed.
Evidence: strict duplicate-key PyYAML re-parse clean (ubuntu-gate 14 steps —
now with 2 continue-on-error steps — windows-nightly 12); all bash run
blocks pass `bash -n` (the sole "failure" is the Windows-only §9.1
PowerShell block, per the §11.12 precedent); `flutter analyze` → `No issues
found!`; full `flutter test` → 642/642 pass (no Dart changes).
Previously (2026-10-24) the docs-accuracy cleanup run reconciled stale
claims in ARCHITECTURE.md (perft regression tests now exist and pass, 9
screens, test suite no longer deferred), ENGINE_RUNTIME.md (§3.3 → the real
"Flutter upgrade gate" heading in RUNBOOK.md), and the "boot + e2e smoke
tests" flutter-test comments in README.md + RUNBOOK.md (the suite is the
full 642-test regression). No open item changed: §9.1/§9.2, §11.3, and
§14.1/§14.2 remain Windows-blocked; §2.6 is upstream-external.
Previously (2026-10-24) §11.21 guards the §11.15/§11.18
Linux-release-smoke xwininfo captures: the three
`xwininfo -id "$WIN_ID" ... | awk` substitutions in the smoke step were
unguarded under `set -euo pipefail` (the `xdotool search` line already
carried `|| true`), so a window destroyed between the search and a capture
call — an app crash right after mapping, the exact failure class this gate
exists to catch — made xwininfo exit 1, pipefail propagated it, the failing
assignment aborted the step INSIDE the window loop, and the `::error::`
diagnostic, `cat smoke.log`, and the
`kill -9 "$APP_PID" "$XVFB_PID" "$WM_PID"` teardown never ran: the :77 display
leaked on the runner (the §11.12/§11.14 leak class). The captures now end
`|| true`, so a vanished window degrades to empty values; the loop's next
iteration re-searches and a window that stays gone flows into the post-loop
verdict, which prints full diagnostics and always runs the teardown (exit 1).
Evidence: workflow re-parses clean via strict duplicate-key PyYAML
(ubuntu-gate 14 steps, windows-nightly 12 — step counts unchanged); extracted
smoke block passes `bash -n`; the abort is proven empirically — a real
failing `xwininfo -id <bad>` substitution in a `set -euo pipefail` shell
aborts it (exit 1, nothing after) while the guarded form survives — and a
full-block harness (fake xdotool always finds the window, fake xwininfo
always exits 1) running the OLD block verbatim exits 1 with ZERO output and
leaves all three stub daemons (Xvfb/WM/app) alive, while the NEW block prints
the full `::error::`, tears down, exits 1, and leaks nothing; the FULL
modified smoke block run verbatim against the real Linux release bundle on a
fresh display → `smoke ok: release binary alive after 15s and window mapped
(title llm_chess_arena, 1278x720) under Xvfb + openbox`, exit 0, no orphan
Xvfb/app; `flutter analyze` → `No issues found!`; full `flutter test` →
642/642 pass (no Dart changes).
Previously (2026-10-24) §11.20 fixes the frozen Stockfish CI cache
slots. Both engine-restore steps (ubuntu-gate §11.7, windows-nightly §11.17)
used CONSTANT cache keys (`${{ runner.os }}-stockfish-linux-x86-64` /
`-windows-x86-64`), so after a Stockfish release bump (sf_19 → sf_20 — the
README pins size + SHA-256 the download tool verifies against) the restored
slot would stay permanently frozen stale: every run restores 103 MiB, the
download tool's self-heal rejects the mismatch and re-downloads, and the
fresh binary is never saved — actions/cache saves only on a primary-key
miss, so the constant key guarantees both a permanent 103 MiB re-download
per run AND a cache slot that can never refresh. The keys are now
`${{ runner.os }}-stockfish-<platform>-${{ hashFiles('assets/engines/<platform>/README.md') }}`,
so bumping the pinned README changes the key and invalidates the slot —
exactly one fresh download after a bump, then the new binary is cached
under the new key. No restore-keys fallback on purpose (a version-less
prefix would re-introduce the permanent stale restore). Content-validity is
still enforced on every restore by the tool's size/SHA-256/`file`/UCI
re-verification. §11.7/§11.17's "fixed key" design is thereby superseded.
Evidence: `flutter analyze` → `No issues found!`; full `flutter test` →
642/642 pass (no Dart changes); workflow re-parses clean via strict
duplicate-key PyYAML (ubuntu-gate 14 steps, windows-nightly 12 — step counts
unchanged, only each cache step's `with:` changed); all bash run blocks pass
`bash -n`; hash-invalidation property proven empirically — sha256 of the
current linux/windows READMEs vs a bumped copy differ, so the key expression
changes when the pinned version changes. Previously (2026-10-24) §11.19 makes the Stockfish download tool
self-heal corrupt caches. `tool/download_stockfish.dart` — the linchpin of the
§11.7/§11.17 real-engine gates — trusted any cached release archive blindly
(`ensureArchive` returned a file at `--archive-dir` on existence alone), so a
truncated archive (a killed download; the §11.16 CI step timeout can SIGKILL
the tool mid-write) stuck every later run at extraction forever with no
automatic recovery — directly contradicting the documented "stale caches
self-heal" promise, which was true only for the extracted binary, never the
archive layer. `fetchPlatform` now runs a bounded two-attempt loop: new helper
`extractAndVerify` deletes the unusable archive and any partial binary on ANY
failure (unlistable archive, failed member extraction, or a binary that fails
size/SHA-256/`file`/handshake after extraction) and throws; `fetchPlatform`
then re-downloads exactly once (`fetched (re-downloaded: cached archive was
corrupt)`). A pure download failure (no archive obtained at all) is
deliberately NOT retried — the same URLs would only double the hang. The
helper also creates `dest.parent` itself (the old code relied on
`fetchPlatform`'s pre-create, so a direct call into a missing directory could
hang forever in `File.openWrite`'s lazy-open error path — this run's
direct-call probe hit exactly that hang). `--base-url=`/`baseOverride` added as
a single-candidate download-base seam for loopback tests. New
`test/download_stockfish_test.dart` (5 deterministic offline tests): corrupt
cache recovery (discard + exactly one re-download + verified binary), bounded
retry when the re-download is also garbage (no corrupt cache left; a later run
starts clean), no-retry on pure download failure, `baseOverride`
single-candidate semantics, and the helper's happy path on a valid cached
archive — loopback HTTP server only, no external network. Evidence:
`flutter analyze` → `No issues found!`; `flutter test
test/download_stockfish_test.dart` → 5/5 pass; full `flutter test` → 642/642
pass (637 + 5 new); real happy path unchanged (`OK present`); and the REAL
recovery was proven empirically: fresh fetch of the real 81,388,977-byte
archive → extract+verify OK → truncate the cached archive to 1 KiB and delete
the binary → the same command recovers (`tar: Unexpected EOF in archive` →
`re-downloading once` → `OK fetched (re-downloaded: cached archive was
corrupt)`, full archive restored, size/sha256/file/uciok re-verified).
Previously (2026-10-24) §11.18 closes the last bypass in the §11.15
Linux-release smoke gate: the window-size sanity check (width/height ≥ 100)
only gated the `break` inside the 75×1 s window-search loop, never the
post-loop verdict — a window that was `IsViewable` at a capped <100×100 size
through all 75 iterations exhausted the loop without breaking and was
greenlit (`smoke ok: ... 50x50`). The post-loop guard now also enforces
`${WIDTH:-0} -ge 100` / `${HEIGHT:-0} -ge 100` and the `::error::` message
reports the observed `map_state` + geometry, so everything §11.15 documented
is enforced unconditionally. Previously (2026-10-24) §13 open decisions RESOLVED: the
Windows-runner question (hosted `windows-latest` vs a dedicated VM for the
§9.1/§9.2/§11.3 native validation) is DECIDED **hosted `windows-latest`, no
dedicated VM required**. Evidence (verified against the hosted Windows Server
2022 image): the job runs in a real **interactive console session** (measured:
session 2, user `runneradmin`, `explorer.exe` running, windows enumerable by
accessibility bridges — pyjab's `windows-gui.yml` runs exactly this class of
attach-to-a-launched-app GUI automation on `windows-latest`); **WinAppDriver
1.2.2009.02003 is preinstalled** on the image (runner-images
Windows2022-Readme.md), so the §9.2 UIAutomationCore client needs no install;
`flutter test integration_test/... -d windows` against the real Windows
binary is routine on hosted runners (per the Flutter docs, xvfb is the
LINUX-only virtual-display requirement); the runner account is a local admin
with **UAC disabled** (GitHub Docs), so UIA client registration and Event
Viewer `Get-WinEvent` reads work. Caveats for the first §11.3 run: default
resolution 1024x768 (raise via `Set-DisplayResolution` if the smoke needs a
larger window), display scale fixed at 96 DPI (no DPI-scaling coverage), and
the desktop is unattended (windows render off-screen and receive synthetic
input, nothing is physically displayed). Fallback: a dedicated VM only if the
first hosted run hits a session-specific failure (UIA attach fails, Event
Viewer unreadable, Windows-11-only rendering delta — the image is Server
2022). The §13 safe-mode question is DECIDED **no safe-mode toggle** — keep
the `ExcludeSemantics`/`IndexedStack` hardening and retire it only via the
upstream engine fix (§2.6). §11.3's remaining text now carries the first-run
trigger checklist. Previously (2026-10-23) §11.17 makes the real-engine
Stockfish E2E actually run on the windows-nightly gate: `test/e2e_smoke_test.dart` hardcoded
`assets/engines/linux-x86-64/stockfish`, so on the Windows runner the test
always skipped (and that job had no engine download step at all) — the §11.7
engine gate existed only for the ubuntu job. The test now resolves the host
binary via `EmbeddedEngine.bundledAssetPath()` (Windows → `windows-x86-64/
stockfish.exe`, Linux → `linux-x86-64/stockfish`, null → honest skip), sharing
one top-level value between the `skip:` predicate and the test body so the two
can never disagree; `windows-nightly` gained the same
cache-restore + `dart run tool/download_stockfish.dart windows-x86-64`
download pair the ubuntu-gate has. §11.16 bounds every ubuntu-gate and
windows-nightly job and step with `timeout-minutes`: the workflow previously
relied on GitHub's default 360-minute job timeout, so a hung step (pub get,
engine download, apt, build, smoke, integration test) could stall the gate for
up to 6 hours and overlap the next scheduled run. Both jobs now carry a job
level backstop (ubuntu-gate 90 min — ~4x the observed ~15-20 min green wall
time — windows-nightly 180 min) and every one of the 25 steps carries its own
tighter bound (checkout 5, Setup Flutter 15, pub-cache restore 5, pub get 5,
analyze 10, engine cache 5, engine download 15, full-suite test+coverage 30,
apt install 15, build linux 30, smoke 15, linux integration 20, coverage
upload 5, build windows 60, windows integration 30, UIA smoke 20). The
§11.14 §11.15
bounded loops inside the smoke step stay unchanged (the step timeout is a
belt-and-braces backstop). §11.15 closes the last false-pass hole in
the §11.6 Linux-release smoke: it previously proved **process aliveness**
only (`kill -0` after the 15 s window), but `linux/runner/my_application.cc`
shows the window only once the FIRST Flutter frame renders
(`first_frame_cb`) — and under software GL (llvmpipe) that frame took
~26-52 s on the dev host, so every prior smoke green was also a "no window
yet" green. The smoke now waits up to 75 s for an anchored-titled
(`^llm_chess_arena$`) window with `map_state == IsViewable` and sane
geometry via `xwininfo` (xdotool's `--onlyvisible` is deliberately NOT
used — its `_NET_CLIENT_LIST` visibility lagged the real mapping by tens of
seconds), dumps `smoke.log` and exits 1 on timeout, and prints the mapped
geometry on success (`smoke ok: ... window mapped (title llm_chess_arena,
1278x720) ...`). `xdotool` added to the ubuntu-gate apt install. §11.14 adds an Xvfb startup readiness gate
to both ubuntu-gate display steps (the §11.6 Linux-release smoke on :77 and
the §11.11 headless integration suite on :79): each probes the display with
`xdpyinfo` before launching (clean `::error::` refusal when a stale leaked
server already owns the display), then waits up to 5s for the freshly
launched server to answer (exit 1 on early death or timeout). Previously a
backgrounded `Xvfb :N &` that died instantly was invisible to `set -e` — the
step failed later with a confusing `cannot open display`, or silently
attached to the stale leaked server still answering on that display (three
leaks :77/:79/:99 observed on the dev host). §11.13 removes the last 12
`// ignore_for_file` suppressions from the repo (11 files suppressed
`dangling_library_doc_comments`; the integration test also suppressed a dead
`camel_case_types`; the e2e smoke suppressed `avoid_print`). Every suppression
is replaced by the repo's canonical proper fix — a `library;` directive after
the library doc comment (the same fix the §6.5 cleanup applied to
watch_screen_test.dart) and `debugPrint` for the e2e smoke's five intentional
status prints. `flutter analyze` now reports `No issues found!` with **zero**
`// ignore` / `// ignore_for_file` lines anywhere in lib/, test/,
integration_test/, or tool/. §11.12 makes the §11.11 integration-test step's
Xvfb teardown actually run on the failure path; §11.11 executes the §9.1
integration suite headless on the ubuntu-gate every push; §11.10 fixed the dead
semantics-dump failure fallback; §11.9 removed all real-network calls from the
test suite; §2.6 still no upstream fix (flutter/flutter#175041 open, PR #190903
unmerged; 3.47.7 does not contain it) → local 3.47.6 stays on mitigation;
§11.8 pins both CI jobs to known-good Flutter 3.47.6
Related: [Runbook](RUNBOOK.md), [Engine runtime](ENGINE_RUNTIME.md),
[Variant rules](VARIANT.md), [Chess engine notes](CHESS_ENGINE.md)

All planned implementation, test coverage, and testability work is complete.
The remaining items are release validation, CI automation, and process
integration that cannot be closed on Linux. Completed work and the crash
investigation history are preserved in `automation-track.md` and git history.

Verified baseline (2026-10-25, re-verified §11.41):

- `flutter analyze` — 0 issues.
- `flutter test` — 671/671 pass.
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

The suite is widget-level and deterministic, so it now also executes headless
on the ubuntu-gate every push (§11.11) — it was written 2026-10-21 and had
never run anywhere until §11.11 discovered 8/12 tests failing (stale
`Statistics` label, ambiguous Home-card/More-sheet text, unenabled semantics
in the live binding, wrong anchors) — so the Windows run is now the only
native gap for that file.

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
- (§11.30, 2026-10-24) The "Upload smoke artifacts" step now carries
  `continue-on-error: true` (plus `if-no-files-found: warn`), mirroring
  the ubuntu-gate "Upload coverage artifact" step's §11.22 contract: the
  step is `if: always()` and uploads purely diagnostic files
  (`uia_smoke_output.txt`, `event_viewer_excerpt.txt`), so a transient
  `actions/upload-artifact@v4` backend failure (a documented Actions
  failure mode) must not redden the entire nightly on a non-gating
  concern — a red §9.1/§9.2 gate is the only thing that should fail this
  job.

Remaining:

- Trigger the workflow and confirm all steps actually pass on a Windows
  runner. **Runner decision: DECIDED 2026-10-24 (§13) — use the hosted
  `windows-latest` runner; no dedicated VM required.** First-run checklist:
  1. `workflow_dispatch` the workflow (or wait for the 06:00 UTC schedule)
     and confirm the job reaches the §9.2 smoke step.
  2. Expect the §9.1 integration test to run against the real Windows binary
     (`flutter test integration_test/accessibility_windows_test.dart -d
     windows`), the Stockfish E2E to EXECUTE rather than skip (§11.17), and
     the UIA smoke to report ≥40 invocable controls + 500 random clicks with
     exit 0.
  3. Watch the §13 caveats in the artifacts: the runner's default 1024x768
     resolution (raise via `Set-DisplayResolution` if the smoke's window
     bounds are too small for its random clicks) and Event Viewer access from
     the runner account (the smoke's step 7 reads it via `Get-WinEvent`).
  4. If the job fails at a session-specific step (UIA attach, Event Viewer,
     window rendering), capture the `uia-smoke-artifacts` + Event Viewer
     excerpt, and only THEN move to a dedicated VM per the §13 fallback
     criteria.

**Done when:** a green scheduled Windows run is linked from the repository and
its artifacts prove the native gate passed.

### 11.4 Coverage (P2 — DONE; CI P3 #2 merge 2026-10-24)

Coverage is explicitly not the success metric — the goal is that every
interaction-matrix control is exercised and every transition asserts
the semantics invariants, not a line-coverage number. Since CI P3 #2
(2026-10-24, §11.4-owner decision) the ubuntu-gate "Test" step runs the
full suite once as `flutter test --coverage`: it gates on the test
results and generates `coverage/lcov.info` as a byproduct, uploaded by
the §11.22 `if: always()` + `continue-on-error: true` step (a missing
lcov or a failed artifact push degrades to a warning, never a red gate)
so coverage trends can be reported. This merges the former pair of a
gating `flutter test` + a non-gating `flutter test test/ui --coverage`
(`continue-on-error: true`), which ran the interaction-matrix suite
twice per push; the lcov semantics widened from test/ui-only to
full-suite (a superset of coverage data for the trend artifact). See
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
  `docs/RUNBOOK.md` "Prereqs").
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

### 11.7 Real-engine E2E smoke in CI (P2 — DONE)

`test/e2e_smoke_test.dart` holds the only real-engine test in the repo
("embedded stockfish evaluates and stays honest"): it connects to the
actual Stockfish binary, evaluates a real position with
`source == 'stockfish-uci'`, and asserts `supported`/`scoreCp`/`bestMoveUci`
plus the variant-JSON "unsupported" honesty check. The test self-gates on
`assets/engines/linux-x86-64/stockfish` — and the binary is gitignored with
no download step anywhere in CI, so the engine path ran **zero times** on
every push/PR while `flutter test` still printed green.

The `ubuntu-gate` job now makes the real-engine test an actual gate:

- **Restore Stockfish engine cache** — `actions/cache@v4` on
  `assets/engines/linux-x86-64` (the 103 MiB linux-x86-64 binary; only the
  first runner downloads). Stale caches self-heal:
  `download_stockfish.dart` re-verifies size + SHA-256 + `file` type + UCI
  handshake and re-fetches on any mismatch, so the fixed key can never
  smuggle a corrupt binary past the gate.
- **Download Stockfish engine** — `dart run
  tool/download_stockfish.dart linux-x86-64` (official GitHub URL first,
  `gh.llkk.cc` proxy fallback; strict host verification ends with a `uciok`
  handshake; exit 1 on any failure so a broken fetch cannot silently skip
  the E2E test).

Evidence: the exact commands run green on the dev host —
`dart run tool/download_stockfish.dart linux-x86-64` → `OK present`
(size/sha256/file/handshake all verified) and
`flutter test test/e2e_smoke_test.dart` → 5/5 pass WITH the engine test
executing (`-- stockfish: 30 cp, best c7c5`), not skipping; full
`flutter test` → 635/635 pass unchanged; `flutter analyze` → `No issues
found!`. The engine test itself was not touched — it still skips gracefully
on machines without the binary. See `automation-track.md` for the run log.

### 11.8 CI Flutter SDK pinning (P1 — DONE)

Both CI jobs used a **floating** `flutter-version: "3.x"` / `channel: stable`
selector (`subosito/flutter-action@v2`), so every run could resolve a
different Flutter SDK: analyze results, lint defaults, test behavior, and
effective flag semantics drifted between pushes and diverged from the local
dev toolchain. The repo already treats a specific stable as known-good —
Flutter 3.47.6 (Dart 3.13.5), exercised by every run-log baseline — but CI
never pinned it. The deferred `dart format` gate (see the §11.7 run log)
was blocked precisely on this unpinned fragility.

Both jobs (`ubuntu-gate` + `windows-nightly`) now pin:

- `flutter-version: "3.47.6"` / `channel: stable`, with a comment that the
  RUNBOOK.md "Flutter upgrade gate" step 2 is the only sanctioned way to
  bump it (re-validate §9.1/§9.2 first).

Evidence: workflow re-parses clean via PyYAML (ubuntu-gate 13 steps,
windows-nightly 10 steps — counts unchanged; only the `with:` block of each
Setup Flutter step changed); the pin matches the local known-good — Flutter
3.47.6 stable, Dart 3.13.5; `flutter analyze` → `No issues found!`; full
`flutter test` → 635/635 pass (no Dart changes). See
`automation-track.md` for the run log.

### 11.9 No real network in the test suite (P1 — DONE)

Since the §11.8 SDK pin, bare `flutter test` runs integration-style tests in
the pinned gate on every push/PR. Three tests in
`test/connection_tester_seam_test.dart` invoked the **default**
`connectionTesterProvider` (lines 34–38, 179–181, 199–200), which wraps
`testAgentConnection` → `agent_backend.createProvider(...).testConnection()` —
a real HTTP ping against a live LLM endpoint — directly contradicting the
file's own header rule ("must never open an HTTP socket or ping a real LLM
endpoint"). One of them also asserted real wall-clock `< 30s` via `Stopwatch`,
the flakiest line in the suite. This is now fixed; the three tests assert only
the provider's pure shape and pin invocation behaviour through deterministic
overrides (the live network path is the production seam, exercised
interactively).

Evidence: `flutter analyze` → `No issues found!`; `flutter test
test/connection_tester_seam_test.dart` → 8/8 pass (returns instantly — no
socket is opened during the run); related `test/ui/agent_setup_test.dart` →
29/29 pass; full `flutter test` → 635/635 pass. See `automation-track.md` for
the run log.

### 11.10 Semantics-dump failure fallback actually dumps (P2 — DONE)

`expectNoExceptionWithSemanticsDump` in `test/support/semantics_invariants.dart`
documents "print the semantics-tree dump before failing", but the fallback was
unreachable dead code: the first line,
`expect(tester.takeException(), isNull, reason: '…')`, **drains** the pending
exception and `expect` **throws synchronously** when the value is non-null, so
the second `takeException()` inside `if (tester.takeException() != null)`
could never return non-null. On a real failure the test died at the `expect`
with no tree dump; on a clean pass the fallback branch — and `_dumpTree`
itself — never ran. The helper now drains the exception once into a local and,
when it is non-null, prints the semantics-tree dump **before** failing with
`fail('exception during $context: $exception')`, restoring the documented
behaviour and making `_dumpTree` live again. The clean-path behaviour used as
a "no pending exception" gate by `test/ui/semantics_stability_test.dart` (17
sites) and `test/ui/monkey_tap_test.dart` (6 sites) is unchanged.

Two new tests in `test/support/integration_test.dart` pin both paths: a
clean-pass (`returnsNormally` + `takeException()` null) and a forced failure —
a `GestureDetector` `onTap` throwing `StateError('forced kboom')` (recorded
deterministically by the test framework) — asserted to fail with both the
context and the exception text, drain the pending exception, and actually
print the dump (`[4] label="tap-me"` observed in the run output).

Evidence: `flutter analyze` → `No issues found!`; `flutter test
test/support/integration_test.dart` → 20/20 pass (18 old + 2 new); caller
suites `test/ui/semantics_stability_test.dart test/ui/monkey_tap_test.dart` →
37/37 pass; full `flutter test` → 637/637 pass (635 baseline + 2 new). See
`automation-track.md` for the run log.

### 11.11 Never-executed §9.1 integration suite fixed + gated on Linux CI (P1 — DONE)

`integration_test/accessibility_windows_test.dart` (12 widget-level tests per
§9.1) had **never executed anywhere**: bare `flutter test` does not discover
`integration_test/`, and the windows-nightly job has not run — so the 12 tests
compiled but ran zero times on every push/PR. The first-ever headless run
(`flutter test integration_test/accessibility_windows_test.dart -d linux`
under Xvfb) failed 8/12 with four platform-independent test bugs:

1. `_destinationLabel(4)` was `'Statistics'` but the shell's rail/sheet label
   is `'Stats'` — the affected tests silently no-oped via `isNotEmpty` guards.
2. `find.text('Settings')` / `'Agents'` / `'Review'` were ambiguous — the Home
   tab behind the modal bottom sheet renders same-text cards; sheet-item
   lookups now scope via `find.byType(BottomSheet)`.
3. `find.bySemanticsLabel(...)` returned 0 everywhere because the live
   integration binding never enables semantics — `_pumpApp` now returns a
   `SemanticsHandle` from `tester.ensureSemantics()`, disposed in `try/finally`
   (`addTearDown` runs after the flutter_test handle-verification and leaks).
4. Several anchor texts did not exist on the target screens ("AI" vs the real
   "AI Opponent" label, "Statistics" vs "No stats yet", etc.).

The new `_tapDestination` helper prefers tapping the real semantics node and
falls back to `find.text(label).first` (the repo widget-suite convention) on
bindings without per-render-object `debugSemantics` — deterministic on both
Windows+UIA and headless Linux. The suite is now a hard ubuntu-gate step
(`flutter test integration_test/accessibility_windows_test.dart -d linux`
under its own Xvfb :79) so it runs on every push; the native Windows run
(§9.1) remains the only native gap for that file.

Evidence: `flutter analyze` → `No issues found!`; `flutter test
integration_test/accessibility_windows_test.dart -d linux` → 12/12 pass
(was 4/12 at the first probe); full `flutter test` → 637/637 pass unchanged
(no lib/ or test/ changes); workflow re-parses clean via PyYAML (ubuntu-gate
14 steps; windows-nightly untouched); new run block passes `bash -n`. See
`automation-track.md` for the run log.

### 11.12 Xvfb teardown dead-on-failure in the §11.11 step + dead GITHUB_OUTPUT writes (P1 — DONE)

The §11.11 integration-test step started an Xvfb :79 and ran under
`set -euo pipefail`:

```bash
flutter test integration_test/accessibility_windows_test.dart -d linux
EXIT=$?
kill -9 "$XVFB_PID" 2>/dev/null || true
exit $EXIT
```

On a **red** run, `set -e` aborts the shell at the failing `flutter test`
line, so `EXIT=$?`, the `kill -9 "$XVFB_PID"` teardown, and `exit` were all
unreachable dead code — the :79 display server leaked on the runner (and the
"cleanup" lines were misleading on the one path they mattered most). The step
now captures the exit code without aborting:

```bash
flutter test integration_test/accessibility_windows_test.dart -d linux || EXIT=$?
kill -9 "$XVFB_PID" 2>/dev/null || true
exit ${EXIT:-0}
```

The job still fails on any non-zero exit (the hard gate is unchanged); the
only change is that the teardown now runs on BOTH paths. Also in the same
pass:

- Removed two dead `echo "exit_code=$($LASTEXITCODE)" >> $env:GITHUB_OUTPUT`
  writes in `windows-nightly` (lines 196/246) — grep confirms nothing
  consumes `steps.integration-test.outputs.exit_code` /
  `steps.uia-smoke.outputs.exit_code`; the gating is the explicit
  `Exit $LASTEXITCODE` in each step. The now-unused step `id: integration-test`
  and `id: uia-smoke` were removed with them.
- Added the missing `set -euo pipefail` to the "Install Linux desktop build
  deps" step so every ubuntu-gate `run:` block is consistent (GitHub's
  default shell is already `bash -e -o pipefail`, so this is belt-and-braces
  plus `-u`).

Evidence: workflow re-parses clean via PyYAML (ubuntu-gate 14 steps,
windows-nightly 10 steps); all 9 ubuntu-gate bash run-blocks pass `bash -n`
(the two `bash -n` "failures" are the PowerShell blocks, Windows-only by
design); the fix is proven empirically on this host — a replication of the
PRE-fix block with a failing command leaves the :79 Xvfb alive (PID observed
surviving), while the POST-fix block on the failure path propagates the exact
exit code (3) and kills :79, on the success path exits 0 and kills :79, and
the REAL `flutter test integration_test/... -d linux` run (12/12 pass, 00:34)
leaves no :79 process behind; `flutter analyze` → `No issues found!`; full
`flutter test` → 637/637 pass (no Dart changes). See `automation-track.md`
for the run log.

### 11.13 Zero `// ignore` suppressions in the repo (P2 — DONE)

The analyzer config (`analysis_options.yaml`) explicitly documents
`// ignore:` / `// ignore_for_file` as the escape hatch for lint suppressions,
and the §6.5 lint-cleanup run fixed `dangling_library_doc_comments` in
watch_screen_test.dart the **proper** way (a `library;` directive after the
library doc comment) — yet eleven files still hid the same lint behind
`// ignore_for_file`, and one integration-test line suppressed a lint that no
longer fires. Every suppression in the repo is now gone:

- **11 files** (`test/support/arena_test_harness.dart:29`,
  `test/support/semantics_invariants.dart:37`,
  `test/connection_tester_seam_test.dart:8`, `test/clock_seam_test.dart:8`,
  `test/ui/arena_screen_test.dart:6`, `test/ui/arena_variant_review_test.dart:14`,
  `test/ui/deterministic_deep_states_test.dart:7`, `test/ui/elo_injection_test.dart:6`,
  `test/ui/semantics_stability_test.dart:21`, `test/ui/stable_keys_test.dart:8`,
  `integration_test/accessibility_windows_test.dart:15`) suppressed
  `dangling_library_doc_comments` — each now ends its library doc comment with
  the repo-standard `library;` directive. The `// ignore_for_file:
  dangling_library_doc_comments, camel_case_types` line in the integration
  test also suppressed a **dead** lint: removing it fired only the doc lint
  (probe-verified), because no camel-case type exists in that file.
- **`test/e2e_smoke_test.dart`** suppressed `avoid_print` for its five
  intentional per-section status prints; the prints now use `debugPrint`
  (from `package:flutter/foundation.dart`, the canonical app-logging
  API) and the suppression is gone.

`grep -rn "ignore_for_file" lib test integration_test tool` now returns
**nothing** — the analyzer is clean without a single suppression, so a future
`flutter analyze` run can never be masking a lint it should be reporting
(the whole point of the protocol's "never hide issues with `// ignore`" rule).
No lib/, workflow, or test-behavior change: the edits are header directives
and the `print`→`debugPrint` call-site rewrite only.

Evidence: `flutter analyze` → `No issues found! (ran in 2.6s)`; touched
suites `flutter test test/support/integration_test.dart test/e2e_smoke_test.dart
test/connection_tester_seam_test.dart test/clock_seam_test.dart
test/ui/elo_injection_test.dart test/ui/stable_keys_test.dart
test/ui/semantics_stability_test.dart test/ui/arena_screen_test.dart
test/ui/arena_variant_review_test.dart
test/ui/deterministic_deep_states_test.dart` → 126/126 pass; the headless
§9.1/§11.11 run `flutter test integration_test/accessibility_windows_test.dart
-d linux` → 12/12 pass (00:34) under Xvfb :79; full regression
`flutter test` → 637/637 pass (no lib/ changes). See `automation-track.md`
for the run log.

### 11.14 Xvfb startup readiness gate on both ubuntu-gate display steps (P1 — DONE)

Both ubuntu-gate steps that start a display server — the §11.6 Linux-release
smoke (`Xvfb :77`) and the §11.11 headless integration suite (`Xvfb :79`) —
launched a backgrounded `Xvfb :N ... &` with **no readiness assertion**. A
dead-on-arrival Xvfb is invisible to `set -e`: the step would fail later
with a confusing `cannot open display`, or — worse — silently attach the
smoke/suite to the **stale leaked server still answering on that display**.
The hazard is real: three leaked Xvfb servers (`:77/:79/:99` from earlier
smoke/integration runs) were verified alive on the dev host during this run.

Both steps now gate the display environment before anything attaches:

- `x11-utils` (provides `xdpyinfo`) added to the ubuntu-gate "Install Linux
  desktop build deps" step.
- Pre-flight probe **before** launching: if the display already answers,
  fail immediately with `::error::display :N already in use by another X
  server (stale Xvfb from a prior run?); refusing to attach to it` — no
  doomed Xvfb is spawned and no "Server is already active" noise is emitted.
- Post-launch bounded readiness loop (up to 50×100 ms = 5 s): exit 1 with a
  clear `::error::` if the PID dies during startup or the display never
  answers (`xdpyinfo`), with `kill -9` cleanup on the timeout path.
- The smoke's openbox + app launch, and the integration step's §11.12
  `|| EXIT=$?` / `kill -9 "$XVFB_PID"` / `exit ${EXIT:-0}` teardown tail,
  now run only behind a guaranteed-live display.

Step counts unchanged (ubuntu-gate 14, windows-nightly 10); only
`with:`/`run:` content changed. No Dart/test files changed.

Evidence: `flutter analyze` → `No issues found! (ran in 2.3s)`; full
regression `flutter test` → 637/637 pass (no Dart changes); workflow
re-parses clean via PyYAML; all bash run-blocks pass `bash -n`. All four
gate paths proven empirically on this host: (a) smoke on OCCUPIED :77 (real
stale server) → clean refusal, exit 1, no orphan; (b) integration on
OCCUPIED :79 → same, exit 1; (c) smoke on fresh :85 → gate passes ~100 ms,
release binary alive 15 s, exit 0, no Xvfb left behind; (d) integration on
fresh :88 with the REAL `flutter test
integration_test/accessibility_windows_test.dart -d linux` → 12/12 pass,
exit 0, no orphan; plus synthetic proofs of the startup-death and 5 s
timeout guard branches (both exit 1). See `automation-track.md` for the run
log.

### 11.15 Linux-release smoke requires the window to actually map (P1 — DONE)

The §11.6 smoke proved **process aliveness only** (`kill -0` after the
15 s window) — a binary that stays alive while its window never maps
(display connection failure, GDK_BACKEND fallback, first frame never
rendered) passed the gate. That failure class is real for this app:
`linux/runner/my_application.cc` shows the window only once the FIRST
Flutter frame renders (`first_frame_cb`), and under the smoke's software GL
(llvmpipe) that frame took ~26-52 s on the dev host — well past the 15 s
window, so every prior smoke green was also a "no window yet" green. The
smoke step now additionally requires the app's window to be mapped,
sane-sized, and correctly titled:

- `xdotool` added to the ubuntu-gate apt install list.
- After the 15 s aliveness check, a bounded loop (up to 75×1 s — the first
  frame under llvmpipe is slow) searches for the window with an **anchored**
  title regex (`xdotool search --name "^llm_chess_arena$"`; `xdotool
  --name` is an unanchored regex, and the pre-first-frame 10x10 helper
  window is named `com.llmarena.llm_chess_arena` so it never matches), then
  requires `map_state == IsViewable` with width/height ≥ 100 via
  `xwininfo`. `xdotool --onlyvisible` is deliberately NOT used: it resolves
  visibility through the WM's `_NET_CLIENT_LIST`, which was observed
  lagging the actual mapping by tens of seconds, while `xwininfo` reads the
  server's real map state. On timeout the step dumps `smoke.log` and exits
  1 with a `::error::`; success prints the mapped geometry:
  `smoke ok: release binary alive after 15s and window mapped (title
  llm_chess_arena, 1278x720) under Xvfb + openbox`.

Evidence: workflow re-parses clean via PyYAML (ubuntu-gate 14 steps,
windows-nightly 10 — step counts unchanged; only `with:`/`run:` content
changed); both changed run blocks pass `bash -n`; the exact block is proven
empirically on this host — POSITIVE path on fresh :97 (rebuild + the exact
block): `smoke ok: ... (1278x720) ...`, exit 0 in ~53 s (15 s aliveness +
~37 s window wait; first frame observed at ~51 s), no orphan :97 Xvfb and
no app process left; NEGATIVE path (`NO_APP`, window never appears): the
guard fires `::error::release binary is alive but no mapped window titled
'llm_chess_arena' ...` and exits 1 with no orphan Xvfb left. `flutter
analyze` → `No issues found! (ran in 2.3s)`; full regression `flutter test`
→ 637/637 pass (no Dart changes). See `automation-track.md` for the run
log.

### 11.16 Bound every gate job and step with `timeout-minutes` (P1 — DONE)

The workflow relied entirely on GitHub's default **360-minute** job timeout:
a hung step — a stalled `flutter pub get`, a slow/hung 103 MiB engine
download, an apt mirror hang, a deadlocked `flutter test`, a smoke app that
never exits — could stall the gate for up to 6 hours and overlap the next
scheduled `windows-nightly` run. No `timeout-minutes` existed anywhere
(`grep` returned zero before this run). Every job and step is now bounded:

- **Job-level backstops** — `ubuntu-gate`: `timeout-minutes: 90`
  (~4x the observed ~15-20 min green wall time including the first-run
  Stockfish download); `windows-nightly`: `timeout-minutes: 180`
  (the §9.1 integration test + §9.2 UIA smoke are interactive and wider).
- **Step-level bounds (all 25 steps across both jobs)** — checkout 5,
  Setup Flutter 15, pub-cache restore 5, pub get 5, analyze 10, engine
  cache restore 5, engine download 15, Test (full suite + coverage) 30,
  apt install 15, `flutter build linux --release` 30, Linux smoke 15 (the
  §11.14/§11.15 internal loops are already bounded — this is a
  belt-and-braces backstop), Linux integration 20, coverage artifact
  upload 5, `flutter build windows --release` 60, Windows unit/widget
  tests 30, §9.1 integration 30, §9.2 UIA smoke 20, smoke artifacts
  upload 5.
- The §11.31 CI P3 #2 merge absorbed the separate coverage run step into
  the gating Test step, so coverage collection is bounded by the Test
  step's `timeout-minutes: 30` — the §11.4 "coverage never reddens the
  gate" contract now holds at the ARTIFACT level only: the §11.22 upload
  step keeps `continue-on-error: true` + `if-no-files-found: warn`, so a
  missing lcov or a failed artifact push still cannot redden the gate
  (a coverage-collection failure with all tests green is the documented
  accepted residual of the merge, per the ci.yaml step comment).

Evidence: workflow re-parses clean via PyYAML **with a strict
duplicate-key loader** (ubuntu-gate 13 steps, windows-nightly 12 — the
separate coverage step merged into the gating Test step by §11.31, so
25 steps total; every step carries exactly one `timeout-minutes:` key);
all 27 `timeout-minutes` keys present (25 steps + 2 jobs) and exactly one
per step/job; every bash run-block passes `bash -n` (the two "failures"
are the Windows-only §9.1/§9.2 PowerShell blocks — Windows-only by
design, per §11.12); `flutter analyze` → `No issues found! (ran in 2.4s)`;
full regression `flutter test` → 637/637 pass (01:48, All tests passed! —
no Dart changes).
See `automation-track.md` for the run log.

### 11.17 Real-engine E2E runs on the Windows gate too (P1 — DONE)

The §11.7 engine gate was ubuntu-only in two separate ways: the Job had the
download step, but the test itself hardcoded
`assets/engines/linux-x86-64/stockfish`. On a Windows runner — the
`windows-nightly` gate — that path never exists, so
`test/e2e_smoke_test.dart`'s Stockfish section **always skipped**, and the
Windows job had no engine download step at all. A `flutter_windows.dll`
engine integration regression could not redden that job. Both halves are
fixed:

- **`test/e2e_smoke_test.dart`** no longer hardcodes a platform path. The
  test resolves the bundled binary for the current host via
  `EmbeddedEngine.bundledAssetPath()` (Linux → `linux-x86-64/stockfish`,
  Windows → `windows-x86-64/stockfish.exe`, macOS → `macos-universal/
  stockfish`, null for web/iOS/unshipped combos) — the *same* resolver the
  app's runtime extraction uses, so the smoke always probes the path the
  app would actually extract. A single top-level
  `hostEngineBinary` value is shared by the `skip:` predicate and the test
  body (they previously evaluated two separate existence checks and could
  disagree); the skip message names the host and the
  `dart run tool/download_stockfish.dart <platform>` fetch command.
- **`.github/workflows/ci.yaml`** — `windows-nightly` gained the same two
  steps the ubuntu-gate has: "Restore Stockfish engine cache (§11.17)"
  (`actions/cache@v4` on `assets/engines/windows-x86-64`, fixed key — the
  download tool's size/SHA-256/`file`/UCI re-verification self-heals stale
  caches) and "Download Stockfish engine (real-engine E2E, §11.17)"
  (`dart run tool/download_stockfish.dart windows-x86-64`, exit 1 on any
  failure so a broken fetch cannot silently skip the E2E). The Windows
  release asset is a `.zip`; the tool extracts it with `unzip`, which Git
  for Windows ships and prepends to `PATH` on the `windows-latest` image.
  The strict host UCI handshake runs on the first download; only the first
  runner pays the ~103 MiB transfer, and the failure of the download step
  fails the job — a red engine path can no longer slip through the nightly.

Evidence: `flutter analyze` → `No issues found!`; `flutter test
test/e2e_smoke_test.dart` → 5/5 pass locally with the engine test
EXECUTING (`-- stockfish: 30 cp, best c7c5`) rather than skipping
(unchanged behavior on Linux); workflow re-parses clean via PyYAML
(windows-nightly 12 steps, ubuntu-gate 14 — only the two engine steps
added); the download tool was verified against the pinned
`windows-x86-64` binary (`size ok`/`sha256 ok`/`file ok (PE32+...)`, the
foreign-arch handshake degrades to a warning exactly as designed); full
regression `flutter test` → 637/637 pass (no behavior change on Linux).
See `automation-track.md` for the run log.

### 11.18 Linux-release smoke: window-size sanity check actually enforced (P1 — DONE)

The §11.15 smoke requires the app window to be mapped (`map_state ==
IsViewable`) **and** sane-sized (width/height ≥ 100), but the size check only
gated the `break` inside the 75×1 s window-search loop — the post-loop verdict
re-checked only the window id and map state. A window that stayed IsViewable
at a capped <100×100 size through all 75 iterations exhausted the loop without
breaking, passed the post-loop guard, and was printed as a success:
`smoke ok: ... 50x50`. The §11.15 sanity requirement was therefore bypassable
exactly when the window had a real problem (mapped but with wrong/negligible
geometry). The post-loop guard now also requires `${WIDTH:-0} -ge 100` and
`${HEIGHT:-0} -ge 100`, and the error message reports the observed
`map_state` + geometry so a capped window is visible in the log:
`::error::release binary is alive but no mapped window titled
'llm_chess_arena' with sane geometry on :77 (expected map_state IsViewable and
>= 100x100 px; got map_state='IsViewable', 50x50; ...)`. The success line's
`${WIDTH}x${HEIGHT}` is now guaranteed ≥ 100×100.

Evidence: workflow re-parses clean via PyYAML (strict duplicate-key loader;
ubuntu-gate 14 steps, windows-nightly 10 — step counts unchanged, only the
smoke step's post-loop `if` changed); the smoke run block passes `bash -n`;
`flutter analyze` → `No issues found! (ran in 2.4s)`; full regression
`flutter test` → 637/637 pass (01:53, All tests passed! — no Dart changes).
The verdict logic is proven empirically on this host with an 8-case synthetic
probe: capped 50×50 viewable → FAIL, real 1278×720 → PASS, empty window id →
FAIL, IsUnMapped → FAIL, xwininfo empty dimensions → FAIL, 99×99/100×99/
99×100 boundaries → FAIL, exact 100×100 → PASS; and the full modified smoke
block ran against the real Linux release binary under a fresh Xvfb :91 →
`smoke ok: release binary alive after 15s and window mapped (title
llm_chess_arena, 1278x720) under Xvfb + openbox`, exit 0, no :91 Xvfb/app
orphan left behind (the pre-existing leaked :77/:79 servers remain untouched
per the §11.12/§11.14 precedent — the §11.14 pre-flight probe correctly
refused the occupied :77). See `automation-track.md` for the run log.

### 11.19 Download tool self-heals corrupt cached archives (P1 — DONE)

`tool/download_stockfish.dart` is the linchpin of the §11.7/§11.17 real-engine
gates, and its `ensureArchive` trusted any cached release archive blindly — a
file existing under `--archive-dir` was returned as-is, never verified. A
truncated archive (a killed download — the §11.16 CI step timeout can SIGKILL
the tool mid-write) therefore stuck every later run at extraction forever:
`tar -tzf`/`tar -xzOf` failed, the corrupt archive was never deleted, and the
run reported FAIL every time with no automatic recovery. That directly
contradicted the documented "stale caches self-heal: ... re-fetches on any
mismatch" promise (§11.7/§11.17) — which was true only for the extracted
binary, never for the archive layer.

The tool now self-heals:

- **`fetchPlatform` runs a bounded two-attempt loop.** Attempt 1 uses whatever
  is cached (or downloads if missing). New helper `extractAndVerify` deletes
  the archive and any partial binary on ANY failure — an unlistable archive, a
  failed member extraction, or a binary that fails size/SHA-256/`file`/
  handshake after extraction — and throws. `fetchPlatform` then re-downloads
  exactly once and reports `fetched (re-downloaded: cached archive was
  corrupt)`. A pure download failure (no archive obtained at all) is
  deliberately NOT retried — the same URLs would only double the hang.
- **`extractAndVerify` creates `dest.parent` itself.** The original code
  relied on `fetchPlatform`'s pre-create, so a direct call into a missing
  directory could hang forever in `File.openWrite`'s lazy-open error path —
  this run's direct-call probe hit exactly that hang before the fix.
- **`--base-url=` + `baseOverride`** (default unchanged): a single-candidate
  download-base override so tests can point at a loopback server; documented
  in `--help`.

New `test/download_stockfish_test.dart` (5 deterministic offline tests):
(1) a corrupt cached archive is discarded, re-downloaded exactly once, and the
recovered binary verifies; (2) a re-download that also yields garbage is
bounded (exactly one re-download attempt) and leaves no corrupt archive or
partial binary behind, so a later run starts from a clean cache; (3) a pure
download failure is NOT retried (fails fast with `all download candidates
failed`); (4) `baseOverride` yields a single candidate under the given base
(the official base is unchanged without it); (5) `extractAndVerify` succeeds
on a valid cached archive without any download and leaves the valid archive in
place. All downloads go to a loopback HTTP server — no external network — and
the fake `PlatformAsset` reports its own payload's size/SHA-256 so verification
is self-contained.

Evidence: `flutter analyze` → `No issues found!`; `flutter test
test/download_stockfish_test.dart` → 5/5 pass; full regression `flutter test`
→ 642/642 pass (637 baseline + 5 new); real happy path unchanged
(`dart run tool/download_stockfish.dart linux-x86-64` → `OK present`, with
size/sha256/file/uciok all verified); and the REAL recovery was proven
empirically on this host — fetch a fresh real archive (81,388,977 bytes),
extract + verify OK, then truncate the cached archive to 1 KiB and delete the
binary, and re-run the same command: `tar: Unexpected EOF in archive` →
`re-downloading once` → `OK fetched (re-downloaded: cached archive was
corrupt)` with the full 81 MB archive restored and size/sha256/file/uciok
re-verified. See `automation-track.md` for the run log.

### 11.20 Engine cache keys invalidate on the pinned release (P1 — DONE)

Both engine-restore steps — the ubuntu-gate's §11.7 step and the
windows-nightly's §11.17 step — used a CONSTANT cache key:
`${{ runner.os }}-stockfish-linux-x86-64` resp.
`${{ runner.os }}-stockfish-windows-x86-64`. The §11.7/§11.17 design comment
called this a "fixed key" whose staleness was safely handled by the download
tool's size/SHA-256/`file`/UCI self-heal — which is true for CORRECTNESS but
not for freshness: after a Stockfish release bump (the per-platform
`assets/engines/*/README.md` pins a new size + SHA-256, sf_19 → sf_20), the
constant key still HITS the old frozen-stale slot, so every run restores
103 MiB of a binary that the tool then rejects and re-downloads — a permanent
103 MiB re-download per run, forever — and the freshly downloaded correct
binary is never saved back, because `actions/cache@v4` saves only on a
primary-key **miss** and the constant key never misses. The cache slot can
therefore never refresh on its own after a release bump; the repo documented
nothing about the manual cache-eviction chore that the design silently
created.

Fixed by keying the cache on the pinned version contract itself:

- Both keys now end in
  `-${{ hashFiles('assets/engines/<platform>/README.md') }}` (the README is
  committed and pins the exact size + SHA-256 the download tool verifies
  against). A release bump edits that README, which changes the hash and thus
  the key: the bump's first run does one fresh 103 MiB download (cache miss),
  and the correct binary is then saved under the NEW key — subsequent runs
  hit the fresh cache.
- **No `restore-keys` fallback on purpose.** A version-less prefix (the
  canonical pub-cache pattern) would partially restore the frozen-stale slot
  after a bump and re-introduce exactly the permanent-stale-restore loop this
  fix eliminates, with no correctness upside — content validity is already
  enforced on every restore by the download tool's size/SHA-256/`file`/UCI
  re-verification, regardless of which cache the bytes came from.
- The §11.7/§11.17 "fixed key" wording is superseded; the download tool, the
  engine READMEs, and the download steps are unchanged.

Evidence: workflow re-parses clean via PyYAML with a strict duplicate-key
loader (ubuntu-gate 14 steps, windows-nightly 12 — step counts unchanged;
only each cache step's `with:` block changed); all bash run blocks pass
`bash -n` (the sole "failure" is the Windows-only §9.1 PowerShell block, per
§11.12); `flutter analyze` → `No issues found! (ran in 2.4s)`; full
regression `flutter test` → 642/642 pass (All tests passed! — no Dart
changes); the invalidation property is proven empirically — `sha256sum` of
the current linux-x86-64 README
(`c9798ef3fb62a1ac79c386c72d991b877e117b6c7beab8dfa1845d5c609e3a2f`) vs a
bumped copy (`f681d999e3fae5b24c29d4336a44a1b1f3f5fca7d843cca3f0766e7ccc94b0a1`)
differ, and the windows-x86-64 README hashes to a distinct independent value
(`947f1e188b6eb80ecdc955d627f4d578dc9d868ba9b8e754a9584cbc1af7a444`), so a
README content change ⇒ key change ⇒ slot invalidation on both platforms.
See `automation-track.md` for the run log.

---

### 11.21 Linux-release smoke: xwininfo captures guarded against the vanishing-window abort (P1 — DONE)

The §11.15/§11.18 smoke step's window-verdict loop reads the window geometry
with three `xwininfo -id "$WIN_ID" ... | awk` command substitutions. Under the
step's `set -euo pipefail` those substitutions were **unguarded** — the
`xdotool search` line above them already carried `|| true` (line `WIN_ID=$(
xdotool search ... | head -1 || true)`), but the three xwininfo captures were
missed. The failure mode is the exact class this gate exists to catch: the app
crashes right after mapping its window (first-frame abort, display failure,
renderer stall), so the window id found by `xdotool search` is destroyed
before the next `xwininfo` call. `xwininfo` then exits 1 ("No such window"),
`pipefail` propagates that into the command substitution, the failing
assignment makes `set -e` abort the shell **inside the loop** — and the
`::error::` diagnostic, `cat smoke.log`, and the
`kill -9 "$APP_PID" "$XVFB_PID" "$WM_PID"` teardown that follow the loop never
run. The :77 display server leaks on the runner (the §11.12/§11.14 leak class
— a gate failure now leaks the very resource the §11.14 readiness gate was
added to protect), and the crash is reported with no context.

The three captures now end with `|| true`, matching the existing xdotool
guard. A vanished window degrades to an empty capture; the loop's next
iteration re-searches, and a window that stays gone flows into the post-loop
verdict below — which prints the full `::error::` diagnostic with the observed
map state + geometry, dumps `smoke.log`, runs the teardown, and exits 1. A
healthy window behaves exactly as before (the captures succeed, `|| true` is a
no-op). Step counts unchanged (ubuntu-gate 14, windows-nightly 12); no
Dart/test files changed.

Evidence: workflow re-parses clean via PyYAML with a strict duplicate-key
loader (ubuntu-gate 14 steps, windows-nightly 12 — step counts unchanged, only
the three capture lines changed); the extracted smoke run block passes
`bash -n`. The abort semantics are proven empirically on this host (bash
5.3.9, same semantics class as the runners' bash 5.x): a real
`MAP_STATE=$(xwininfo -id <bad-id> 2>/dev/null | awk ...)` under
`set -euo pipefail` aborts the shell (exit 1, the line after never runs),
while the `|| true`-guarded form survives with an empty capture. The teardown
consequence is proven with a full-block harness: the OLD block (from
`git show HEAD:...ci.yaml`, verbatim, with Xvfb/openbox/app stubbed as
long-lived PID-recording daemons and fake `xdotool` (always finds a window) +
fake `xwininfo` (always exit 1) simulating the vanished window) exits 1 with
**zero output** and leaves all three stub daemons alive — the silent leak; the
NEW block (same harness) prints the full
`::error::release binary is alive but no mapped window titled 'llm_chess_arena'
... got map_state='<none>', 0x0 ...`, exits 1, and tears all three stubs down
(no leaks). The positive path is unchanged: the FULL modified smoke block run
verbatim against the real Linux release bundle on a fresh Xvfb display →
`smoke ok: release binary alive after 15s and window mapped (title
llm_chess_arena, 1278x720) under Xvfb + openbox`, exit 0, no orphan Xvfb or
app process left behind. `flutter analyze` → `No issues found!`; full
regression `flutter test` → 642/642 pass (All tests passed! — no Dart
changes). See `automation-track.md` for the run log.

---

### 11.22 Coverage artifact upload can no longer redden the gate (P2 — DONE)

The §11.4 contract is "coverage is explicitly NOT the success metric ... it
never gates the build", and the coverage RUN step
(`ci.yaml` "Test coverage (§11.4)") carries `continue-on-error: true` — but
the `if: always()` "Upload coverage artifact" step that followed it did
**not**. A transient `actions/upload-artifact@v4` backend failure (a
documented Actions service failure mode) would have turned the entire
ubuntu-gate job red on a non-gating concern — exactly the case §11.4 says
coverage "can never redden the gate" for — while every real gate
(analyze/test/build/smoke/integration) had passed. The upload step now also
carries `continue-on-error: true`, so a failed artifact push degrades to a
warning (visible in the job log) exactly like a failed coverage run;
`if-no-files-found: warn` already handled the missing-lcov.info case. The
`coverage-lcov` artifact upload itself is unchanged (name/path/retention
identical), so coverage trend reporting works exactly as before on the
successful path. Step counts unchanged (ubuntu-gate 14, windows-nightly 12)
— only the one step gained `continue-on-error: true` + a §11.22 comment.
No Dart/test files changed.

Evidence: workflow re-parses clean via strict duplicate-key PyYAML (jobs:
ubuntu-gate + windows-nightly; ubuntu-gate 14 steps — now 2
continue-on-error steps: coverage run + upload; windows-nightly 12, no
change); all five multi-command bash run blocks pass `bash -n` (the sole
"failure" is the Windows-only §9.1 PowerShell block, Windows-only by design
per §11.12); `flutter analyze` → `No issues found!`; full regression
`flutter test` → 642/642 pass (no Dart changes). The gate-reddening failure
mode is documented in §11.4's own step comment (never gates the build) and
this section; the fix makes the two coverage steps behaviorally symmetric.
See `automation-track.md` for the run log.

---

### 11.39 Download tool: post-extraction verification failure no longer false-greens (P1 — DONE)

`tool/download_stockfish.dart` `extractAndVerify` is the linchpin of the
§11.7/§11.17 real-engine CI gates (size/SHA-256/`file`/UCI verification
before the E2E engine tests run), and its own doc comment (§11.19) promises
that "on ANY failure … a binary that fails verification after extraction"
is discarded and thrown so a later attempt re-downloads cleanly. The actual
code path after `verifyBinary` returned `false` printed
`verification failed after extraction; treating the archive as corrupt`
and then **fell off the end of the `try` block normally** — no
`_discardArchive`, no rethrow, so the adjacent `on Object` handler never
fired. `extractAndVerify` returned to `fetchPlatform`, which reported
`FetchResult(ok: true, 'fetched')` and `main` exited **0**: the CI engine
download step ("exit 1 on any failure so a broken fetch cannot silently
skip the E2E test") stayed green exactly when the downloaded binary was
wrong, the bad binary was left in `assets/engines/`, and the unusable
archive stayed in the cache — so the §11.19 self-heal re-download could
never run. Found by this run's parallel lib/test/tool convention audit and
confirmed empirically (a valid tar.gz holding a one-byte-flipped payload:
the old code printed the message, then `ok: true`, no discard, no
re-download; the new pinning test FAILED against that code exactly as a
false-green). Fix: the verification-failure branch now
`throw StateError('binary failed verification after extraction')`, so the
existing `on Object` handler discards the archive and any partial binary
and `fetchPlatform`'s bounded two-attempt loop (§11.19) performs the clean
re-download — reporting the fetch honestly (`ok: false`, exit 1) when the
re-download is also bad. New deterministic offline test 6
(`binary failing post-extraction verification is discarded and reported as
a bounded failure (§11.39)`, valid-archive-wrong-binary served by the
existing loopback server; cached copy = same wrong archive): `result.ok`
is false, exactly one re-download, the unusable archive and the partially
extracted/wrong binary are both deleted. The 5 existing §11.19 tests are
byte-unchanged and still pass; the real CLI happy path is unchanged
(`dart run tool/download_stockfish.dart linux-x86-64` → `OK present` with
size/sha256/file/uciok re-verified).

Evidence: `flutter analyze` → `No issues found! (ran in 2.4s)` (Flutter
3.47.6 stable, Dart 3.13.5 — matches the §11.8 CI pin); `flutter test
test/download_stockfish_test.dart` → 6/6 pass (5 existing + 1 new); full
regression `flutter test` → 667/667 pass (All tests passed! — 666
baseline + 1 new); new test proven RED against the pre-fix code (`Expected:
false, Actual: <true> — bad binary must fail, not false-green`) and GREEN
with the fix. See `automation-track.md` for the run log.

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

## 13. Open decisions (resolved 2026-10-24)

No open decisions remain. The two long-standing questions are decided below.

- ~~**Windows runner**~~ **DECIDED 2026-10-24 — use the GitHub-hosted
  `windows-latest` runner; no dedicated VM required.** Evidence, all verified
  against the hosted Windows Server 2022 image (sources at the end):
  1. The job runs in a real **interactive console session** — not Session 0.
     A measured diagnostic on `windows-latest` (pyjab's `windows-gui.yml`,
     which runs exactly this class of attach-to-a-launched-app GUI +
     accessibility-bridge automation on the hosted runner) reports an active
     console session (`qwinsta`: `>console runneradmin 2 Active`), user
     `runneradmin`, `explorer.exe` running, and the launched app's window
     present in the desktop's top-level window list.
  2. UIA tooling is **preinstalled**: `WinAppDriver 1.2.2009.02003` ships on
     the Windows Server 2022 image (runner-images `Windows2022-Readme.md`,
     "Tools" section), so the §9.2 smoke's `UIAutomationCore` COM client needs
     no install step.
  3. `flutter test integration_test/... -d windows` against the real Windows
     binary is routine on hosted runners — per the Flutter integration-testing
     docs, **xvfb is the LINUX-only virtual-display requirement**; Windows
     needs no virtual display.
  4. The runner account is a local admin with **UAC disabled** (GitHub Docs,
     "Administrative privileges"), so UIA client registration and the §9.2
     step-7 Event Viewer read (`Get-WinEvent`) work.
  Caveats for the first §11.3 run: default resolution **1024x768** (raise via
  `Set-DisplayResolution -Width 1920 -Height 1080 -Force` if the smoke needs
  a larger window; not all modes are supported — runner-images#2935), display
  scale fixed at **96 DPI / 1.0** (no DPI-scaling coverage on a hosted
  runner), and the desktop is **unattended** (windows render off-screen and
  receive synthetic `mouse_event` input, but nothing is physically displayed).
  **Fallback criteria:** move to a dedicated VM only if the first hosted run
  hits a session-specific failure the image cannot reproduce — UIA attachment
  fails, Event Viewer is unreadable from the runner account, or a
  Windows-11-only rendering difference matters (the image is Server 2022, not
  Windows 11).
- ~~**Safe mode**~~ **DECIDED 2026-10-24 — no safe-mode toggle.** Do not
  disable custom semantics for screen-reader users until the engine fix lands;
  that would itself be an accessibility regression. Keep the shipped hardening
  (the `ExcludeSemantics` + `IndexedStack` hidden-tab guard and the stable
  semantics roots) and keep the upstream engine fix (`flutter/flutter#175041`,
  §2.6) as the only retirement path. The §9.2 UIA smoke and §14.1/§14.2 are
  the evidence gate: revisit only if that validation or a field report shows
  the hardening is insufficient in practice.
- ~~**Telemetry isolation**~~ **DECIDED 2026-10-23:** `StatsLog`,
  `QualityLog`, `ReviewLog`, and `VariantReviewLog` are now injectable stores
  (per-`ProviderScope` instances exposed through `statsLogProvider` /
  `qualityLogProvider` / `reviewLogProvider` / `variantReviewLogProvider`).
  Screens read/write their store via `ref.read`, so each `ProviderScope`
  gets fully isolated state and the old process-static singletons +
  `resetTelemetry` test hygiene are gone. Run evidence: `automation-track.md`.

Sources: actions/runner-images `Windows2022-Readme.md` (WinAppDriver
preinstalled); `gaozhao1989/pyjab` `.github/workflows/windows-gui.yml`
(measured interactive session + GUI/accessibility automation on
`windows-latest`); flutter.dev integration-testing docs (desktop device runs;
xvfb Linux-only); GitHub Docs "GitHub-hosted runners · Administrative
privileges" (Windows VMs are local admins, UAC disabled); runner-images#2935
(resolution changeable but mode-limited).

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
