# LMChess Automation Track

Status: living document (hourly worker log)
Last updated: 2026-10-24 (UTC) — §11.34 run: the §11.33
audit-trail code-P2 list is now empty — its top candidate,
"engine failure diagnostics silently swallowed in
lib/src/review/engine_adapter.dart", is closed. `dart:developer`
`log()` now surfaces four silent-swallow sites in that file (no
behavior change): the `HeuristicEvaluator._extractPlacement`
decode-error catch (still degrades to "unsupported"), the stderr
drain/surface sub (each non-empty stderr line at warning), the
stdout sub's onError, and the exit-code watcher ("exited
unexpectedly (code N)" — fires only on the unexpected-exit path
because dispose() nulls `_process` first, so the normal shutdown
stays silent). The stale class doc ("fen or pieces") now states the
true contract: "fen field required; boards without FEN interop out
of scope". New deterministic offline suite
`test/engine_adapter_test.dart` (7 tests: standard FEN supported;
JSON-with-fen supported; malformed JSON degrades unsupported without
throw; invalid placement unsupported; pieces-only out of scope;
empty unsupported; garbage unsupported); the real-engine
smoke/seam/variant suites still pass over the modified
connect/dispose/stream paths. Evidence: `flutter analyze` → `No
issues found! (ran in 2.2s)`; full `flutter test` → 658/658 pass
(651 baseline + 7 new; 02:02, All tests passed!). Recorded in the
Run Log below; FUTURE_WORK.md Last updated bumped (§11.34), per the
open-items-only rule no new completed-work section; open-item set
unchanged.
Previously (2026-10-24) — §11.33 run: §11.16's
maintained-in-place timeout-minutes contract is reconciled with the
current workflow after the §11.31 CI P3 #2 merge. A fresh four-way
parallel subagent audit (full FUTURE_WORK.md open-item inventory;
end-to-end ci.yaml defect audit; lib/+test/ convention audit; §15
completeness verification) found ZERO open FUTURE_WORK.md items
implementable-and-verifiable on this Linux host (§9.1/§9.2/§11.3/§14
Windows-native-blocked, §2.6 upstream-external, `dart format` gate
needs-owner-decision, coverage comparison needs-CI-runs, push queue
needs-credentials) and NO P0 (crash) or P1 (correctness) code or
workflow defects — §15 chessboard is genuinely shipped (81 tests across
4 suites: chessboard_drag 15, board_motion 16, scrub_shortcuts 20,
premove 30). The one real P1 finding was doc-contract drift: the live
§11.16 section still asserted the pre-merge state — "all 26 steps", "all
28 `timeout-minutes` keys (26 steps + 2 jobs)", a separate "coverage 30"
bound, and a bullet promising "the coverage step keeps
`continue-on-error: true`" about a step that no longer exists — while
the §11.31 merge absorbed the coverage RUN step into the gating Test
step (ubuntu-gate 14 → 13), and the §11.17 header recap's "26 steps (…
coverage 30 …)" parenthetical carried the same stale count. The workflow
now has ubuntu-gate 13 + windows-nightly 12 = 25 steps and 25 + 2 jobs
= 27 timeout-minutes keys, re-measured this run with the strict
duplicate-key PyYAML loader (25/25 steps carry exactly one
`timeout-minutes:` key). §11.16 and the §11.17 recap are fixed in place
(per the §11.28 precedent for maintained counts): the step list drops
the phantom "coverage 30" entry (coverage collection is bounded by the
merged Test step's `timeout-minutes: 30`), the continue-on-error bullet
now states the true post-merge contract (the §11.4 "coverage never
reddens the gate" property holds at the ARTIFACT level only via the
§11.22 upload step's `continue-on-error: true` + `if-no-files-found:
warn`; a coverage-collection failure with all tests green is the
documented accepted residual of the merge), and the evidence block and
the §11.17 recap parenthetical are updated (25 steps; the two `bash -n`
"failures" are the Windows-only §9.1/§9.2 PowerShell blocks, per the
§11.12 precedent). Pure docs-contract correction — zero Dart, test, or
workflow-file changes. Evidence: `flutter analyze` → `No issues found!
(ran in 2.1s)`; full `flutter test` → 651/651 pass (01:54, All tests
passed!); strict duplicate-key PyYAML re-parse clean (ubuntu-gate 13 +
windows-nightly 12 steps; 27 timeout-minutes keys = 25 steps + 2 job
bounds, exactly one per step/job); all 3 bash run blocks pass `bash -n`
(the 2 "failures" are the Windows-only §9.1/§9.2 PowerShell blocks, per
the §11.12 precedent). Recorded in the Run Log below; FUTURE_WORK.md's
header recap + Last updated bumped (§11.33), per the open-items-only
rule no new completed-work section.
Previously (2026-10-24) — §11.32 run: the §9.2 UIA-smoke step's
Event Viewer excerpt export no longer aborts on the no-matching-events
failure class. On the §9.2 NON-crash failure class (e.g. control count
< 40, uninvocable controls — no 0xC0000005) no fresh Application-log
event exists, so `Get-WinEvent` writes a `NoMatchingEventsFound` error
— and the "Run UIA smoke (§9.2)" run block never overrode
`$ErrorActionPreference`, so under the runner wrapper's prepended
`'stop'` the error aborted the script BEFORE the `::error::` line and
before `Exit $LASTEXITCODE`: the smoke's documented exit-code semantics
(0/1/2 per §9.2 — "2=crash detected in Event Viewer") degraded to 1 at
the step level, and the excerpt carried no Event Viewer data exactly
when the §11.30 diagnostics are needed. The command now ends
`-ErrorAction SilentlyContinue`: the expected no-match case respects
the pipeline (empty excerpt, still uploaded via the §11.30 step's
`if-no-files-found: warn`), while the block's strictness everywhere
else is unchanged — on the crash class (events exist) the fix is inert
and the export is byte-identical to before. Windows-only execution
path, no Linux gate impact. Evidence: `flutter analyze` → `No issues
found!`; full `flutter test` → 651/651 pass (01:52, All tests passed!
— no Dart changes); strict duplicate-key PyYAML re-parse clean
(ubuntu-gate 13 + windows-nightly 12 steps; 27 timeout-minutes keys;
continue-on-error 1+1); all bash run blocks pass `bash -n` (the 2
"failures" are the Windows-only §9.1/§9.2 PowerShell blocks, per the
§11.12 precedent); the ACTUAL edited block parses with 0 errors under
real PowerShell 7.6.8 (installed user-local to ~/sdk/pwsh for this
run's proof; Parser.ParseInput + scriptblock::Create); and the
abort-vs-survive semantics are proven empirically with verbatim
OLD/HEAD vs NEW failure branches under a `Write-Error` stub of the
exact non-terminating error class — OLD: abort, exit 1, no `::error::`,
0-byte excerpt; NEW: `::error::` printed, exit 2 preserved, empty
excerpt; crash class: OLD and NEW byte-identical (exit 2, real 148-byte
excerpt). Recorded in the Run Log below; per the open-items-only rule
FUTURE_WORK.md gains no new completed-work section (header recap + Last
updated bumped). Open-item set unchanged: §9.1/§9.2/§11.3/§14.1-§14.2
remain Windows-native; §2.6 upstream-external (flutter/flutter#190903
still unmerged); the `dart format` gate (102/127-file churn) remains
pending its explicit owner decision; coverage-artifact comparison still
needs ≥2 real CI runs; the ~80-commit local queue still cannot be
pushed (no GitHub credentials on this host).
Previously (2026-10-24) §11.31 run: CI P3 #2 closed — the
ubuntu-gate's `flutter test` + `flutter test test/ui --coverage` pair is
merged into ONE full-suite `flutter test --coverage` step. The
§11.4-owner decision the §11.29/§11.30 audits recorded as pending was
made explicitly this run: the interaction-matrix suite previously ran
TWICE per push — once inside the hard-gating `flutter test` (~1m53s)
and once again in the separate non-gating "Test coverage" step
(`flutter test test/ui --coverage`, `continue-on-error: true`,
~1m45s) — and the §11.4 lcov artifact covered only test/ui. The merged
step gates on the TEST results and produces `coverage/lcov.info` as a
byproduct of the same run (lcov SF entries widen 66 → 70:
`lib/src/chess/san.dart` + the storage layer — files exercised only by
non-test/ui unit suites); the §11.22 upload keeps `if: always()` +
`continue-on-error: true` + `if-no-files-found: warn`, so every
artifact-level failure (missing lcov, upload backend) still can never
redden the gate. Accepted residual (documented in the step comment): a
coverage-collection failure with all tests green now fails the same
step that runs the tests — a class unobserved in practice with standard
flutter tooling. Measured on this host: merged `flutter test
--coverage` → 651/651 pass in 02:04 vs ~3m38s for the old pair
(01:53 + 01:45) — ~48% less test-execution wall time per push. The
open-item set is otherwise unchanged: §9.1/§9.2/§11.3/§14.1-§14.2
remain Windows-native; §2.6 upstream-external (flutter/flutter#190903
live-checked this run: still `merged: false`); the `dart format` gate
(102/127-file churn) remains pending its explicit owner decision;
coverage-artifact comparison still needs ≥2 real CI runs; the ~80-commit
local queue still cannot be pushed (no GitHub credentials on this host).
Evidence: `flutter analyze` → `No issues found! (ran in 2.3s)`; full
`flutter test` → 651/651 pass (01:53, All tests passed!); merged
`flutter test --coverage` → 651/651 pass (02:04, coverage/lcov.info
10,774 lines / 70 SF); workflow re-parses clean via a strict
duplicate-key PyYAML loader (ubuntu-gate 13 + windows-nightly 12 steps;
continue-on-error now ubuntu-gate 1 + windows-nightly 1; 27
timeout-minutes keys; all 13 bash run blocks pass `bash -n` — the 2
"failures" are the Windows-only §9.1/§9.2 PowerShell blocks, per the
§11.12 precedent). Recorded in the Run Log below; FUTURE_WORK.md's
§11.4 mechanism description was updated in place (per the
open-items-only rule, no new completed-work section; Last updated
bumped).
Previously (2026-10-24) §11.29 run: NO ACTIONABLE ITEM —
hourly terminal branch. An independent parallel subagent audit (full
FUTURE_WORK.md section inventory, automation-track.md tail
"Next:"/candidate clauses, marker grep across lib/test/tool/
integration_test/.github, docs/ roadmap scan) CONFIRMS no open
FUTURE_WORK.md item is implementable-and-verifiable on this Linux host:
§9.1/§9.2/§11.3/§14.1-§14.2 are Windows-native; §2.6 is
upstream-external (local SDK 3.47.6, flutter/flutter#190903 unmerged);
CI P3 #2 (the `flutter test` + `test/ui --coverage` merge) stays open
pending the explicit §11.4-owner decision the audit recorded; the
`dart format` gate (102/127-file churn) stays open pending an explicit
owner decision; coverage-artifact comparison needs ≥2 real CI runs
(impossible without push); and the 75-commit local queue still cannot be
pushed (no GitHub credentials on this host). Zero code/test/workflow
changes this run — pure baseline re-verification: `flutter analyze` →
`No issues found!`; full `flutter test` → 651/651 pass (02:06, All tests
passed!); `git rev-list --count origin/main..HEAD` → 75. Recorded in the
Run Log below; per the open-items-only rule no FUTURE_WORK item was
touched (and no completed-work note was added).
Previously (2026-10-24) §11.28 run: the remaining docs-nits
batch from the §11.22/§11.23 audit trail is closed (CI P3 #2 — the
`flutter test` + `test/ui --coverage` merge — stays open pending the
explicit §11.4-owner decision the audit recorded; nothing left on this
host is P0/P1). Docs-accuracy pass, zero open-item code changes:
"22 `test/ui/` suites" → 23 in the two §11.21-accuracy entries where the
642-test count was right but the suite count never was (arena_variant_
review_test.dart shipped 2026-10-23); the §11.16 step/key counts now
match the re-measured workflow ("24 steps/26 keys" → "26 steps/28 keys";
windows-nightly grew 10 → 12 in §11.17); the live FUTURE_WORK "Verified
baseline" reports 651/651; the dangling `docs/RUNBOOK.md "Linux desktop"`
refs (FUTURE_WORK.md §11.6 + the ci.yaml build-deps comment) point at
the real "## Prereqs" heading; `tool/download_stockfish.dart` `--help`
now documents the `--direct` alias for `--no-proxy`; the §9.2 track row's
`0xCAFABE` seed typo is `0xCAFEBABE` (matching `tool/windows_
accessibility_smoke.ps1:30`). Evidence: `flutter analyze` → `No issues
found!`; full `flutter test` → 651/651 pass (no Dart behavior change —
help-text + docs only); ci.yaml §11.28 contract asserted (14 + 12 steps,
28 timeout keys); `dart run tool/download_stockfish.dart --help` lists
`--direct`. Next: (a) re-push the queued local commits once GitHub
credentials exist; (b) trigger the §11.3 windows-nightly via
`workflow_dispatch` (or wait for the 06:00 UTC schedule) on the hosted
`windows-latest` runner per the §13 decision + §11.3 checklist — the ONLY
remaining functional gap (§14.1-§14.2); or (c) re-check §2.6 on the next
Flutter upgrade / when `flutter/flutter#190903` lands. CI P3 #2 (coverage
merge) stays open pending the §11.4-owner decision; the `dart format`
gate (102/127-file churn, needs an explicit owner decision) remains
open; coverage-artifact comparison still needs ≥2 CI runs.
Previously (2026-10-24) §11.27 run: the ubuntu-gate's
software-GL contract now reaches the processes that actually render.
Both Xvfb display steps previously prefixed `LIBGL_ALWAYS_SOFTWARE=1`
ONLY to the Xvfb launch line, so the §11.15 release-binary smoke and the
§11.11 headless integration suite ran WITHOUT it — on a runner with a
reachable GPU driver the app could silently pick hardware GL, breaking
the smoke's reproducibility (its window-wait budget was measured under
llvmpipe, where first frame takes ~26-52s). Both steps now
`export LIBGL_ALWAYS_SOFTWARE=1` next to `export DISPLAY=`, matching the
documented headless recipe (docs/RUNBOOK.md "## Prereqs"), and the
redundant env-prefix on the Xvfb lines is removed. Evidence: `flutter
analyze` → `No issues found! (ran in 2.2s)`; full `flutter test` →
651/651 pass (01:54, All tests passed! — no Dart changes); strict
duplicate-key PyYAML re-parse clean (ubuntu-gate 14 + windows-nightly 12
steps, step counts unchanged); all 14 bash run blocks pass `bash -n` (the
sole "failures" are the Windows-only §9.1/§9.2 PowerShell blocks, per the
§11.12 precedent); the FULL modified smoke block run verbatim against the
real Linux release bundle on a fresh :113 display → `smoke ok: release
binary alive after 15s and window mapped (title llm_chess_arena,
1278x720) under Xvfb + openbox`, exit 0, no :113 Xvfb/app orphan; the
§11.11 headless suite under the exported var (fresh :117) → 12/12 pass,
exit 0, no orphan. Files changed: `.github/workflows/ci.yaml`, this track
+ `docs/FUTURE_WORK.md` (Last updated bumped; per the open-items-only
rule no new completed-work section — no open FUTURE_WORK item was
touched, §9.1/§9.2/§11.3/§14 remain Windows-blocked, §2.6
upstream-external).
Previously (2026-10-24) §11.26 run: the final code-P2 audit
candidate is closed — `test/clock_seam_test.dart` no longer asserts against
an absolute wall-clock year. The "defaults to DateTime.now" test used
`expect(now.year, greaterThanOrEqualTo(2026))`, an absolute epoch threshold
that fails on any machine with a pre-2026 clock (and pins the suite to a
point in time for no reason). It now verifies the default clock against an
immediately adjacent `DateTime.now()` reading
(`now.difference(reference).inSeconds.abs() <= 300`): `difference`
normalizes the local/UTC offset, there is no absolute year dependency, and
the test still proves the default resolves to the real wall clock. A
test-only determinism fix — no lib/ code changed. Evidence: `flutter
analyze` → `No issues found! (ran in 2.2s)`; `flutter test
test/clock_seam_test.dart` → 8/8 pass; clock-seam consumers
(watch/arena/deterministic-deep-states/scrub/arena-variant-review) → 84/84
pass; full `flutter test` → 651/651 pass (01:54, All tests passed! — count
unchanged, test edit only). Files changed: `test/clock_seam_test.dart`,
this track + `docs/FUTURE_WORK.md` (Last updated bumped; per the
open-items-only rule no new completed-work section — no open FUTURE_WORK
item was touched, §9.1/§9.2/§11.3/§14 remain Windows-blocked, §2.6
upstream-external).
Previously (2026-10-24) §11.25 run: `resolveApiKey`'s silent
secure-store read-failure swallow is gone (closes code-P2 #2 from the
§11.22/§11.23 audit trail — the §11.24 fix's read-side sibling, the top
remaining Linux-implementable audit candidate). `lib/src/agent/
agent_config.dart` `resolveApiKey` caught secure-store READ failures with
`catch (_)` and returned `''`, so an aged/inaccessible OS keychain was
indistinguishable from "no key stored": a provider with a stored key
silently degraded to keyless (later auth failures with zero diagnostics),
and "Test Connection" reported false for the wrong reason. The empty
`catch (_)` is gone (repo convention): the failure is logged via
`dart:developer` by default — the storage layer's own write-error fallback
pattern (`local_store.dart`) — or handed to a new optional `onReadError`
sink mirroring `LocalAppStore.onWriteError` exactly, so operators can
distinguish "no key" (quiet `''`) from "store failed" (logged/observed).
The resolver still never throws and returns `''` on failure, preserving
the keyless-backend contract pinned by `test/turn_provider_test.dart`'s
throwing-reader test and `testAgentConnection`'s "Never throws" doc. New
`test/resolve_api_key_test.dart` (6 deterministic offline tests): secret
resolution, no-ref/empty-ref short-circuit without touching the store or
invoking `onReadError`, null-secret quiet `''`, throwing store degrades to
`''` instead of crashing, and the throwing store reports ref + error +
stackTrace to `onReadError` while still returning `''`. Evidence:
`flutter analyze` → `No issues found! (ran in 2.1s)`; `flutter test
test/resolve_api_key_test.dart test/turn_provider_test.dart
test/connection_tester_seam_test.dart` → 20/20 pass (6 new + 14 related);
full `flutter test` → 651/651 pass (645 + 6 new, 01:57, All tests
passed!). Files changed: `lib/src/agent/agent_config.dart`,
`test/resolve_api_key_test.dart`, this track + `docs/FUTURE_WORK.md` (Last
updated bumped; no open FUTURE_WORK item was touched — §9.1/§9.2/§11.3/§14
remain Windows-blocked, §2.6 upstream-external).
Previously (2026-10-24) §11.24 run: the AgentSetupScreen "Clear
stored key" action no longer silently swallows a secure-store delete
failure (code-P2 #3 from the §11.22/§11.23 audit trail, the top
Linux-implementable open candidate). `agent_setup_screen.dart`
`_clearApiKey` cleared the UI state FIRST and let `catch (_)` swallow the
delete error, so the screen switched to "No key stored" while the secret
still existed in the store — the user is lied to, and a later Save with a
new key orphans the old secret (overwritten under a NEW ref). The write
path (`_save`) had always surfaced failures as a SnackBar, making Clear the
lone silent swallow. The fix mirrors the save path: a failed `deleteApiKey`
keeps the "stored" indicator + Clear action and shows `Could not clear the
stored API key.`. A test-only seam was added — `AgentSetupScreen({...,
keyStore})`, defaulting to the platform `SecureKeyStore` — so the failure
path is exercised with a deterministic fake (no platform secure backend in
widget tests); production default behavior is unchanged. The Clear path had
ZERO coverage; three new tests pin it. Evidence: `flutter analyze` → `No
issues found! (ran in 2.3s)`; `flutter test test/ui/agent_setup_test.dart`
→ 32/32 pass (29 + 3 new); full `flutter test` → 645/645 pass (642 + 3
new, 01:54, All tests passed!); the failure test was proven to FAIL against
the old swallow logic (temporarily restored) and pass with the fix.
Previously (2026-10-24) §11.23 run: the nightly cron no longer re-runs a
redundant full ubuntu-gate. `on:` carries a `schedule` (06:00
UTC) entry whose only purpose is the §11.3 windows-nightly gate, but
ubuntu-gate carried no job-level `if:`, so every nightly cron fired BOTH
jobs — a full Linux gate (analyze + test + build + smoke + integration +
coverage, ~15-20 min) ran every night with zero code changes to exercise:
wasted runner minutes and confusing red runs from nothing. The job now
carries `if: github.event_name != 'schedule'` (+ a §11.23 comment), so it
runs on every push/PR and on manual workflow_dispatch exactly as before
and skips only the schedule event; windows-nightly's own `if:` keeps it
schedule/dispatch-only. Job/step counts unchanged (ubuntu-gate 14,
windows-nightly 12); no Dart/test files changed.
Evidence: strict duplicate-key PyYAML re-parse clean with the job
if-contracts asserted programmatically (ubuntu-gate 14 steps +
`if: github.event_name != 'schedule'`; windows-nightly 12 steps +
schedule/dispatch-only `if:`); all bash run blocks pass `bash -n` (the
sole "failure" is the Windows-only §9.1 PowerShell block, per the §11.12
precedent); `flutter analyze` → `No issues found! (ran in 2.2s)`;
full `flutter test` → 642/642 pass (01:55, All tests passed! — no Dart
changes).
Previously (2026-10-24) §11.22 run: the ci.yaml coverage artifact
upload step could redden the gate. §11.4's documented contract ("coverage
can never redden the gate"; the coverage RUN step carries
`continue-on-error: true`) was only half-implemented: the `if: always()`
"Upload coverage artifact" step had no `continue-on-error`, so a transient
`actions/upload-artifact@v4` backend failure (a documented Actions failure
mode) would have turned the entire ubuntu-gate red on a non-gating concern
even though analyze/test/build/smoke/integration all passed. The upload
step now carries `continue-on-error: true` + a §11.22 comment, making the
two coverage steps behaviorally symmetric (failed artifact push degrades to
a warning; `if-no-files-found: warn` covers the missing-lcov case). Steps
unchanged (ubuntu-gate 14, windows-nightly 12); no Dart/test files changed.
Audit: three parallel subagents (full ci.yaml defect audit + test/code
marker audit + docs/tooling open-item audit) found no P0/P1 defects; the
open FUTURE_WORK.md items remain all Windows-native (§9.1/§9.2/§11.3/§14)
or external (§2.6 — re-verified this run via GitHub API: flutter/flutter
#190903 still open/unmerged, updated 2026-10-21; #175041 still open, updated
2026-09-26). Evidence: strict duplicate-key PyYAML re-parse clean
(ubuntu-gate 14 steps — now 2 continue-on-error — windows-nightly 12);
all five multi-command bash blocks pass `bash -n` (the sole "failure" is the
Windows-only §9.1 PowerShell block, per the §11.12 precedent);
`flutter analyze` → `No issues found!`; full `flutter test` → 642/642 pass
(no Dart changes).
Previously (2026-10-24) docs-accuracy cleanup (the §11.21 run's
Next: "stale-doc trio") closes the documented-but-stale claims flagged in the
§11.21 audit: "regression tests pending" in ARCHITECTURE.md:12 (perft + FEN/SAN
round-trip regression tests exist in `test/chess_rules_test.dart` and pass),
the "comprehensive unit/widget suite deferred" line in ARCHITECTURE.md:53-54
(the suite exists — 642 tests, 22 `test/ui/` suites, `test/support/` harness,
`integration_test/`), and the dangling "§3.3" cross-reference in
ENGINE_RUNTIME.md:154 (RUNBOOK.md uses unnumbered `##` headings; the real
gate is "Flutter upgrade gate", acceptance criterion 14.8). A subagent audit
of ARCHITECTURE.md/RUNBOOK.md/ENGINE_RUNTIME.md/README.md surfaced three more
same-class claims, fixed in the same pass: ARCHITECTURE.md:33 said "8 screens"
(there are 9 — `variant_replay_screen.dart` shipped in 61d58d7), and the
"flutter test # boot + e2e smoke tests" comments in README.md:17 +
RUNBOOK.md:22 were stale (`flutter test` runs the full 642-test regression).
No Dart/test files changed; no open FUTURE_WORK item touched (§9.1/§9.2,
§11.3, §14.1/§14.2 remain Windows-blocked; §2.6 upstream-external).
Evidence: `flutter analyze` → `No issues found! (ran in 2.3s)`; full
`flutter test` → 642/642 pass (01:50, All tests passed!).
Previously (2026-10-24) §11.21 guards the §11.15/§11.18
Linux-release-smoke xwininfo captures. The smoke step's window-verdict loop
read geometry with three `xwininfo -id "$WIN_ID" ... | awk` command
substitutions that were unguarded under `set -euo pipefail` (the `xdotool
search` limit above them already carried `|| true`; the xwininfo trio was
missed). When the app crashes right after mapping its window — the exact
failure class this gate exists to catch — the window id found by the search
is destroyed before the next `xwininfo` call: xwininfo exits 1 ("No such
window"), pipefail propagates it into the substitution, the failing
assignment aborts the shell INSIDE the loop, and the `::error::` diagnostic,
`cat smoke.log`, and the `kill -9 "$APP_PID" "$XVFB_PID" "$WM_PID"` teardown
never run — the :77 display leaks on the runner (the §11.12/§11.14 leak
class). The three captures now end `|| true` (matching the xdotool guard): a
vanished window degrades to empty values, the loop's next iteration
re-searches, and a window that stays gone flows into the post-loop verdict
with full diagnostics + teardown (exit 1). Evidence: strict duplicate-key
PyYAML parse clean (ubuntu-gate 14 steps, windows-nightly 12 — step counts
unchanged); smoke block passes `bash -n`; abort proven empirically (real
`xwininfo -id <bad>` substitution in `set -euo pipefail` → exit 1, nothing
after; guarded form survives); OLD-vs-NEW full-block harness (fake xdotool
finds the window, fake xwininfo always fails; Xvfb/openbox/app stubbed as
PID-recording daemons) — OLD exits 1 with zero output and leaves all three
stubs alive, NEW prints the full `::error::` + tears down + exits 1 + leaks
nothing; the FULL modified block run verbatim against the real Linux release
bundle on a fresh display → `smoke ok: ... window mapped (title
llm_chess_arena, 1278x720) ...`, exit 0, no orphans; `flutter analyze` →
`No issues found!`; full `flutter test` → 642/642 pass (no Dart changes).
Previously (2026-10-24) §11.20 fixes the frozen Stockfish CI cache
slots: both engine-restore steps used a CONSTANT key
(`${{ runner.os }}-stockfish-linux-x86-64` /
`-windows-x86-64`), so after a Stockfish release bump the restored slot would
stay permanently frozen stale — every run restores 103 MiB, the §11.7/§11.17
download-tool self-heal rejects the size/SHA-256 mismatch and re-downloads,
and the fresh binary is never saved (actions/cache saves only on a primary-key
miss). The keys now carry the pinned version contract:
`…-${{ hashFiles('assets/engines/linux-x86-64/README.md') }}` (resp.
`windows-x86-64/README.md`), the README that pins the exact size + SHA-256 the
tool verifies against — so bumping it (sf_19 → sf_20) changes the key and
invalidates the cache slot exactly once, and no restore-keys fallback can
re-introduce the frozen stale restore. We enforce the same on every restore:
the tool's size/SHA-256/`file`/UCI re-verification still rejects any corrupt
restore. Evidence: workflow re-parses clean via strict-duplicate-key PyYAML
(ubuntu-gate 14 steps, windows-nightly 12 — step counts unchanged); all bash
run blocks pass `bash -n`; `flutter analyze` → `No issues found!`; full
`flutter test` → 642/642 pass (no Dart changes); hash-invalidation property
proven empirically (README content change ⇒ hash component change, both
platforms). Previously (2026-10-24) §11.19 makes the Stockfish download tool
self-heal corrupt caches: `tool/download_stockfish.dart` trusted any cached
release archive blindly (`ensureArchive` returned a file on existence alone),
so a truncated archive — the residue of a killed download — stuck every later
run at extraction forever, contradicting the §11.7/§11.17 "stale caches
self-heal" contract (which held only for the extracted binary, never the
archive). `fetchPlatform` now runs a bounded two-attempt loop: new
`extractAndVerify` deletes the unusable archive + any partial binary on ANY
failure (unlistable archive, failed extraction, or post-extraction verification
failure) and `fetchPlatform` re-downloads exactly once (`fetched (re-downloaded:
cached archive was corrupt)`); a pure download failure is NOT retried (no
double hang). The helper also creates `dest.parent` (the old code relied on
`fetchPlatform`'s pre-create — a direct call could hang writing into a missing
directory; hit empirically this run). New `test/download_stockfish_test.dart`
(5 deterministic offline tests, loopback-only) pins recovery, bounded retry,
no-retry-on-download-failure, the `--base-url=` seam, and the helper's happy
path. Evidence: `flutter analyze` → `No issues found!`; full `flutter test` →
642/642 pass (637 + 5 new); real CLI recovered empirically from a truncated
real 81,388,977-byte archive (`tar: Unexpected EOF in archive` → `re-downloading
once` → `OK fetched (re-downloaded: cached archive was corrupt)`, full archive
restored, size/sha256/file/uciok re-verified).
Previously (2026-10-24) §11.18 closes the last bypass in the §11.15
Linux-release smoke: the ≥100×100 window-size sanity check gated only the
search-loop `break` (never the post-loop verdict), so a window that was
`IsViewable` at a capped <100×100 size through all 75 iterations was greenlit
(`smoke ok: ... 50x50`); the post-loop guard now also enforces
WIDTH/HEIGHT ≥ 100 and the error message reports the observed map_state +
geometry — everything §11.15 documented is enforced unconditionally.
Previously (2026-10-24) §13 open decisions RESOLVED: the
Windows-runner question (hosted `windows-latest` vs a dedicated VM for the
§9.1/§9.2/§11.3 native validation) is DECIDED **hosted `windows-latest`, no
dedicated VM required**, and the safe-mode question is DECIDED **no toggle —
keep the semantics hardening** (§2.6's upstream fix stays the only retirement
path). Runner-decision evidence, all verified this run: the hosted Windows
Server 2022 image runs jobs in a real **interactive console session**
(measured: session 2, user `runneradmin`, `explorer.exe` running, launched
apps' windows enumerable by accessibility bridges — pyjab's `windows-gui.yml`
runs exactly this class of GUI automation on `windows-latest`); **WinAppDriver
1.2.2009.02003 is preinstalled** (runner-images `Windows2022-Readme.md`), so
the §9.2 `UIAutomationCore` client needs no install; `flutter test -d windows`
desktop integration tests are routine on hosted runners (per the Flutter docs,
**xvfb is the LINUX-only virtual-display requirement**); the runner account is
a local admin with **UAC disabled** (GitHub Docs), so UIA registration +
Event Viewer reads work. Caveats for the first §11.3 run: 1024x768 default
resolution, 96 DPI fixed display scale, unattended desktop; fallback to a
dedicated VM only if a session-specific failure surfaces (UIA attach, Event
Viewer, Windows-11-only delta). Previously §11.17 makes the real-engine
Stockfish E2E run on the windows-nightly gate too: the test hardcoded the Linux engine path
so the Stockfish section ALWAYS skipped on the Windows runner (and that job
never downloaded any engine). The test now resolves its host binary via
`EmbeddedEngine.bundledAssetPath()` (Windows → `windows-x86-64/stockfish.exe`,
Linux → `linux-x86-64/stockfish`, null → honest skip), and `windows-nightly`
gained the same cache + `tool/download_stockfish.dart windows-x86-64` pair the
ubuntu-gate has — a `flutter_windows.dll` engine regression can no longer
slip through the nightly. §11.16 bounds every ubuntu-gate and
windows-nightly job and step with `timeout-minutes` (the workflow previously
relied on GitHub's default 360-minute job timeout, so a hung step could stall
the gate for up to 6 hours and overlap the next scheduled run): job-level
backstops (ubuntu-gate 90, windows-nightly 180) plus per-step bounds on all
26 steps (checkout 5, Setup Flutter 15, cache restores 5, pub get 5, analyze
10, engine download 15, flutter test 30, apt 15, build linux 30, smoke 15,
linux integration 20, coverage 30, uploads 5, build windows 60, windows
integration 30, UIA smoke 20). The §11.14/§11.15 internal loops are untouched
(the step timeouts are belt-and-braces backstops) and the coverage step keeps
`continue-on-error: true`. §11.15 closes the last false-pass hole in
the §11.6 Linux-release smoke: it previously proved process aliveness only
(`kill -0` after the 15 s window), while `linux/runner/my_application.cc`
shows the window only once the FIRST Flutter frame renders (`first_frame_cb`)
— under software GL (llvmpipe) that frame took ~26-52 s on the dev host, so
every prior smoke green was also a "no window yet" green. The smoke now
waits up to 75 s for an anchored-titled (`^llm_chess_arena$`) window with
`map_state == IsViewable` and sane geometry via `xwininfo` (xdotool's
`--onlyvisible` deliberately not used — its `_NET_CLIENT_LIST` visibility
lagged the real mapping by tens of seconds), dumps `smoke.log` + exits 1 on
timeout, and prints the mapped geometry on success (`smoke ok: ... window
mapped (title llm_chess_arena, 1278x720) ...`). `xdotool` added to the
ubuntu-gate apt install. §11.14 adds an Xvfb startup
readiness gate to both ubuntu-gate Xvfb steps (the §11.6 Linux-release smoke
on :77 and the §11.11 headless integration suite on :79): each step now
probes the display with `xdpyinfo` BEFORE launching (`::error::... already in
use ... refusing to attach`) and, after launching, waits up to 5s for the
server to answer (exit 1 on early death or timeout). Previously a
backgrounded `Xvfb :N &` that died instantly (display already occupied by a
leaked server, lock conflict, init failure) was invisible to `set -e` — the
step failed LATER with a confusing `cannot open display`, or worse silently
attached the smoke/suite to the stale leaked server still answering on that
display (three such leaks :77/:79/:99 were observed surviving on the dev
host). `x11-utils` (xdpyinfo) added to the ubuntu-gate apt install. §11.13 removes the last 12
`// ignore_for_file` suppressions from the repo: eleven files suppressed
`dangling_library_doc_comments` (plus a dead `camel_case_types` in the
integration test) behind `// ignore_for_file`, while the repo's own §6.5
cleanup had fixed that exact lint properly in watch_screen_test.dart with a
`library;` directive; the e2e smoke suppressed `avoid_print` for five
intentional status prints. Every suppression is now replaced by the proper
fix — `library;` after the library doc comment + `debugPrint` for the smoke
prints. `grep -rn "ignore_for_file" lib test integration_test tool` returns
nothing and `flutter analyze` is `No issues found!` with zero suppressions.
§11.12 makes the §11.11 integration-test
step's Xvfb teardown actually run on the failure path: the step used
`set -euo pipefail` with `EXIT=$?` captured AFTER the failing `flutter test`
line, so a red run aborted the shell at the test line and
`kill -9 "$XVFB_PID"` never executed — the :79 display server leaked on the
runner. The exit code is now captured without aborting
(`flutter test ... || EXIT=$?` / `exit ${EXIT:-0}`; the job still fails on
any non-zero exit). Both the pre-fix leak and post-fix clean teardown were
replicated empirically on Linux (synthetic failure exit-3 path + success
path + the real 12/12 headless run leaves no :79 process); removed two dead
`exit_code` GITHUB_OUTPUT writes (and unused step ids) from windows-nightly
— nothing consumed `steps.*.outputs.exit_code`, gating is the explicit
`Exit $LASTEXITCODE`; added the missing `set -euo pipefail` to the apt step.
§11.11 executes the §9.1 integration suite headless on the ubuntu-gate every
push (12 tests fixed and gated for the first time ever — bare `flutter test`
does not discover `integration_test/` and the windows job had not run);
§11.10 fixes the dead semantics-dump fallback in `test/support/semantics_invariants.dart`;
§11.9 removes the last real-network call from the test suite
(3 tests invoked the default `connectionTesterProvider`, a live LLM endpoint
ping; now shape-only + deterministic overrides); §9/§11.3/§14 remain
Windows-native BLOCKED; §2.6 still no upstream fix (flutter/flutter#175041
open, PR #190903 unmerged; 3.47.7 does not contain it) → local 3.47.6 stays
on mitigation; §11.8 pins CI Flutter SDK to known-good 3.47.6 on both jobs;
§11.7 real-engine E2E smoke wired into ubuntu-gate; §11.6 ubuntu-gate builds
+ smokes the Linux release binary; §11.5 dead deps removed
Related: `docs/FUTURE_WORK.md` (binding roadmap), `ARCHITECTURE.md`, `README.md`

This file is updated by the hourly scheduler agent (`lmchess-hourly`) **every run**.
`docs/FUTURE_WORK.md` now lists only open items; this file is the append-always run log.

## Protocol for the hourly worker (binding)

1. Work in `/home/tomi/llm_chess_arena` only. One run = **ONE area** (one open
   item from `docs/FUTURE_WORK.md`). Never attempt the whole backlog in one run.
2. Use subagents productively for cognitive offload: keep the main context lean,
   fan out to up to 8 parallel subagents (`explore` for mapping, `general` for
   slices), each scoped to one file/task. Main agent integrates + verifies.
3. Always update this file (append a Run Log entry). Keep
   `docs/FUTURE_WORK.md` open-items-only; do not re-add completed work.
4. Verify with `flutter analyze` + `flutter test` on touched files, then
   `git add`, `git commit`, `git push origin main` every run that changes files.

## Roadmap status (historical — all rows now DONE)

| Priority | Deliverable | Status |
|---|---|---|
| P0 | `test/support/arena_test_harness.dart` | DONE 2026-10-20: `useDesktopSurface`, `pumpArenaApp`, `pumpSteps`, `disposeApp`, `resetTelemetry` (clears StatsLog + QualityLog + ReviewLog + VariantReviewLog), `fakeAgent`/`fakeAgents` (mock ProviderId), `fakeOverrides` (turn provider factory → legal UCI MockProvider + clock fixed UTC), `expectNoException`. New `test/support/integration_test.dart` (18 tests): telemetry clear/reset, fake agents valid, fake overrides resolve in ProviderScope, surface sizing, app shell renders, semantics tree invariants/capture/parentMap/noReparenting/captureSafe, expectNoException, disposeApp. Evidence: `flutter analyze` clean; `flutter test test/support/integration_test.dart` 18/18 pass; full regression `flutter test` 203/203 pass (201 old + 18 new); note: integration test placed inside `test/support/` so relative imports resolve correctly — no longer separate flat file) |
| P0 | `test/support/semantics_invariants.dart` | DONE 2026-10-20: `captureSemantics(tester)` returns root + reachable nodes; `parentMap(capture)` → `Map<int,int?>`; `expectSemanticsTreeInvariants(tester)` checks unique ids, non-null parents, owner match; `expectNoReparenting(before, after)` flags changed parent ids; `expectSquareSemantics(expectedCount, requireUniqueSquares)` counts & validates square labels; `expectNoExceptionWithSemanticsDump(context)` prints tree on failure; `captureSemanticsSafe(tester)` wraps ensureSemantics in try/finally. New integration test covers all functions. Evidence: `flutter analyze` clean; `flutter test test/support/integration_test.dart` 18/18 pass; full regression `flutter test` 203/203 pass. Next: chessboard + shell navigation tests (P0 §6.1–6.3). |
| P0 | `test/ui/chessboard_test.dart` | DONE 2026-10-20: 26 tests covering §6.3 — rendering (initial board semantics labels, constrained sizing, coordinate labels on/off, both orientations, all built-in themes), interactions (empty/opponent/piece taps, select/deselect/reslect, opponent piece, empty square with selection), every-labels-reachable via semantics tap, semantic+gesture handler parity, overlay states (selected/inCheck/terminal/legalTargets/highlight-precedence/lastMove), edge cases (non-interactive/onTapSquare=null disabling buttons, rapid content swaps across 10 alternations without exception, variant badges not changing layout, all 64 label strings present, code vs unicode glyph equivalence, responsive sizing down to 120px). Evidence: `flutter analyze` clean; `flutter test test/ui/chessboard_test.dart` 26/26 pass; full regression `flutter test` 229/229 pass (203 old + 26 new). Next: shell navigation tests (§6.1, P0). |
| P0 | `test/ui/shell_navigation_test.dart` | DONE 2026-10-20: 16 widget tests covering §6.1 — wide rail navigation (8 destinations open correctly, rail has 8 items, state survives Home→Play→Home round-trip, all 8 render without exception, home-card taps via _openRoute), narrow layout (AppBar/rail/NavigationBar presence toggle, More sheet lists Stats/Review/Agents/Settings and selects Review, Drawer present on Scaffold with non-null drawer in narrow mode, narrow renders all 7 navigable screens without crash), state preservation (IndexedStack survives 11-step path, resize 699→700→1100→699 preserves mounted Play tab with zero exceptions, 20 rapid switches through 8 destinations without error), semantics isolation (hidden Home tab contributes 0 square nodes vs Play's occupied-square count, no duplicate semantics ids across multi-tab switch sequences, parentMap invariant stable across Play→Watch→Arena→Home transitions, hidden-tab rule 0→positive→0→positive toggling). Evidence: `flutter analyze` clean; `flutter test test/ui/shell_navigation_test.dart` 16/16 pass; full regression `flutter test` 245/245 pass (229 old + 16 new). Next: play_screen_test.dart (§6.4, P0). |
| P0 | `test/ui/play_screen_test.dart` | DONE 2026-10-20: 25 widget tests covering §6.4 — board interaction (select/deselect/respect own piece, opponent tap, empty square tap, legal move via coordinate tap, illegal destination), promotion dialog stability (renders when pawn reaches back rank, Q/R/B/N options appear, correct piece on queen promotion), resign flow (Resign button in moves panel, resign dialog structure, terminal state no crash), move list after human move shows entries, Activity/Moves tab switching, provider error handling (timeout → AI error handled, throws → app stays alive, no-move → no infinite spinner, successful retry clears error, thrown failure graceful), lifecycle (replacement widget mid-turn safe, dispose drains timers, narrow layout renders, theme change stable, player cards render two). Uses deterministic fakes (MockProvider with stepDelay=0, fixed clock UTC), never hits real network/engine/wall-clock. Evidence: `flutter analyze` clean; `flutter test test/ui/play_screen_test.dart` 25/25 pass; full regression `flutter test` 270/270 pass (245 old + 25 new). Next: semantics_stability_test.dart (§7, P0). |
| P0 | `test/ui/semantics_stability_test.dart` | DONE 2026-10-20: 32 widget tests covering §7 — destination invariants (all 8 wide + all 8 narrow), hidden-tab rule Home→Play→Stats (zero/occupied/zero square nodes), Play Activity/Moves tab switch stable, Watch Activity/Moves/Errors tab switches stable, Arena empty state zero mini-boards, dialog/sheet transitions (More sheet open/select/dismiss/stable, drawer implicit via shell structure), resize 699→700→1100→699 per-frame no-reparenting, theme light→dark semantic stability with equal square-count across modes, 50 rapid destination switches zero duplicate ids, Review empty-state navigate-away-back stability, Agents New-agent form push/pop semantics stability, wide rail completeness (NavigationRail.destinations.length==8 + all 8 labels visible), narrow AppBar presence on navigation change, captureSemanticsSafe wrapper exercise, expectNoExceptionWithSemanticsDump clean-pass, Settings colour-scheme segment toggles, quick round-trip Home→Play→Watch→Home. Each test asserts tree invariants + no reparenting via parentMap comparison. Evidence: `flutter analyze` clean; `flutter test test/ui/semantics_stability_test.dart` 32/32 pass; full regression `flutter test` 302/302 pass (270 old + 32 new). Next: monkey_tap_test.dart (§8, P0). |
| P0 | `test/ui/monkey_tap_test.dart` | DONE 2026-10-20: 5 widget tests covering §8 — narrow grid sweep (600×800 @ 48px), wide grid sweep with Play mounted (1600×1000 @ 48px), 1500 random taps seed 0xC0FFEE, 300 random taps + per-step reparenting guard seed 0xCAFEBABE, bonus tapEveryLabelledControl on Home screen. Uses SeedRng for deterministic PRNG, async _tapOffset (await-compatible tapAt/pump), captureSemanticsSafe/parentMap/expectNoReparenting/expectSemanticsTreeInvariants at every step, _drainRoutes to dismiss dialogs/sheets, harness.disposeApp to drain timers. No pumpAndSettle; uses small pump slices. Each test Timeout(Duration(minutes: 2)). Evidence: flutter analyze clean; flutter test test/ui/monkey_tap_test.dart 5/5 pass; full regression flutter test 307/307 pass (302 old + 5 new). Next: integration_test/accessibility_windows_test.dart (§9, P0). |
| P0 | `integration_test/accessibility_windows_test.dart` | DONE (built) 2026-10-21: 12 tests covering all §9.1 spec requirements; compiles clean and runs as a widget-level integration test. Native Windows execution is the remaining open item in `docs/FUTURE_WORK.md` §9.1. |
| P0 | `tool/windows_accessibility_smoke.ps1` | DONE 2026-10-21: `tool/windows_accessibility_smoke.ps1` (511 lines) — native UIA smoke test per §9.2 spec. Steps: (1) launch release exe via `Start-Process -PassThru`, (2) attach UIAutomationCore COM, (3) find window by PID/title match (`llm_chess_arena.exe`), (4) enumerate invocable controls (InvokePattern first, LegacyIAccessiblePattern fallback), target >= 40, (5) walk UIA tree repeatedly (10 iterations), (6) perform 500 seeded random clicks (XorShift64 PRNG, seed 0xCAFEBABE) with user32.dll mouse_event API, (7) check Event Viewer for fresh flutter_windows.dll 0xC0000005 after run, (8) always kill process in finally block. Accepts params: -Exe (mandatory), -RandomClicks (default 500), -Seed (default 0xCAFEBABE), -Timeout (default 120s). Uses Exit code 0 = pass, 1 = exe missing, 2 = crash detected. No Dart dependency — pure PowerShell/.NET automation. Evidence: `flutter analyze` clean (pre-existing 3 warnings); `flutter test` full regression 467/467 pass unchanged; script verified syntax-free (PowerShell file, not executable on Linux). Next: P0 §9.2 integration into CI pipeline or move to P2 §6.12 `test/ui/shared_widgets_test.dart`. |
| P0 | Refactors 10.1-10.4 + 10.7 (turn-provider / evaluator / clock / connection-tester seams + stable keys) | DONE (10.1 DONE 2026-10-20; 10.2 DONE 2026-10-20: `ReviewEvaluatorFactory` + `reviewEvaluatorFactoryProvider` rewired in ReviewScreen + VariantReplayScreen, `test/review_evaluator_seam_test.dart` 8/8; 10.3 DONE 2026-10-20: `clockProvider` default `DateTime.now`, wired into WatchScreen (`_startWatchGame` seed + `_flushToReviewLog` id) and ArenaScreen (`_startChaosPump` seed + `_chaosRun` startedAt/finishedAt), new `test/clock_seam_test.dart` 8/8; 10.4 DONE 2026-10-20: `ConnectionTester` typedef + `connectionTesterProvider` (default wraps `testAgentConnection` with internal `SecureKeyStore`), wired into AgentSetupScreen (`_tester` captured in initState via `ref.read(connectionTesterProvider)`), new `test/connection_tester_seam_test.dart` 8/8; 10.7 DONE 2026-10-20: ValueKeys on Play-screen duplicate-label controls + `test/ui/stable_keys_test.dart` 4/4) |
| P2 | §10.5 Arena Elo injection (replace `static final _elo`) | DONE 2026-10-21: `ArenaScreen({this.elo})` + instance `EloService`, pinned by `test/ui/elo_injection_test.dart` (6 tests). |
| P2 | §10.6 Deterministic deep states | DONE 2026-10-21: PlayScreen({this.initialFen}) — parseFen(startFen) replaces Position.initial() in _newGame(), defaulting to standardStartFen; AppShell({this.initialIndex = 0}) — initState sets _index from widget.initialIndex instead of hardcoded 0; WatchScreen({this.initialSeed}) — seed assignment uses widget.initialSeed ?? (clock().msSinceEpoch & 0x7fffffff). New `test/ui/deterministic_deep_states_test.dart` (12 tests): initialFen overrides starting position with e5 pawn, minimal king-only FEN renders two kings without crash, PlayScreen without initialFen uses standard start, AppShell default starts at Home (0), AppShell initialIndex=1 shows Play directly without Home navigation, AppShell initialIndex=7 shows Settings directly, WatchScreen with initialSeed=42 renders stably, two WatchScreens with same initialSeed both render, backward compat const constructors for all three screens. Evidence: `flutter analyze` clean on all 5 touched files; `flutter test test/ui/deterministic_deep_states_test.dart` 12/12 pass; full regression `flutter test` 542/542 pass (530 old + 12 new). Next: §10.8 Dispose audit.
| P2 | §10.8 Dispose audit | DONE 2026-10-21: New `test/ui/dispose_audit_test.dart` (8 tests) covering all §10.8 spec requirements: ReviewScreen navigate-away mid-review disposes handle exactly once, Re-run review supersedes previous handle with disposal count verified, VariantReplayScreen dispose during async review disposes exactly once, stale completion guard prevents extra disposal without exception, SpyHandle property verification, single navigate-away disposal invariant, VariantReplayScreen dispose without analysis no crash, sequential Analyze calls each dispose prior handle. Uses _SpyHandle extending ReviewEvaluatorHandle injected via reviewEvaluatorFactoryProvider override to count .dispose() calls per instance. Evidence: `flutter analyze` clean; `flutter test test/ui/dispose_audit_test.dart` 8/8 pass; full regression `flutter test` 550/550 pass (542 old + 8 new). Next: complete — all roadmap rows in docs/FUTURE_WORK.md §§5–12 marked DONE. |
| P1 | §11.6 Linux release build + Xvfb smoke on ubuntu-gate | DONE 2026-10-23: `ubuntu-gate` gained three steps — Install Linux desktop build deps (`ninja-build pkg-config libgtk-3-dev libsecret-1-dev libjsoncpp-dev xvfb openbox`), Build Linux release (`flutter build linux --release`), Smoke start Linux release (Xvfb: start `Xvfb :77` + `openbox` with `LIBGL_ALWAYS_SOFTWARE=1`, launch `build/linux/x64/release/bundle/llm_chess_arena`, require `kill -0` after a 15 s window, bounded SIGTERM→SIGKILL teardown). Closes the gap where analyze+test could pass while a runner/plugin/CMake regression broke the binary (previously only the Windows nightly built it). Engine assets are gitignored and extraction is lazy, so the smoke needs no download. Evidence: `flutter analyze` → `No issues found!`; `flutter build linux --release` → `✓ Built build/linux/x64/release/bundle/llm_chess_arena`; exact smoke recipe exits 0 locally (binary alive after 15 s under Xvfb :77 + openbox); full regression `flutter test` → 631/631 pass (no Dart changes); workflow re-parses clean via PyYAML (ubuntu-gate 11 steps, windows-nightly untouched); all new run blocks pass `bash -n`. |
| P1 | §13-adjacent: chaotic→`VariantReviewLog` wiring doc fix + 4 tests (`test/ui/arena_variant_review_test.dart`) | DONE 2026-10-23: fixed the stale "**Wiring point**: chaotic games are *not* recorded in [ReviewLog]" doc comment at `arena_screen.dart:28-30` — the code has recorded chaotic games losslessly into `VariantReviewLog` since commit 61d58d7 (`_concludeGame` write site at `arena_screen.dart:1552-1566`), but the class doc still described the original plan and **no test covered the path**. New suite pins the whole recording contract: (1) chaotic tournament (2 demo agents, 1 pairing × 2 games/pairing × 1 round, color alternation, concurrency 2, `initialSeed: 42`) records exactly 2 `VariantGameRecord`s with mode 'chaotic', two demo labels/agent-ids per game (white≠black), non-empty id/tournamentId/seed/initialBoard, outcome in {1-0,0-1,1/2-1/2,*}, non-empty reason, monotonic startedAt→finishedAt, sequential ply indices, ≥4-char attempt UCIs, and `validateChain()` empty (board + hash chain integrity); the FEN `ReviewLog` stays empty (isolation). (2) cancelled chaotic run still records both games with outcome '*' / reason 'cancelled' + valid chain (partial-trail visibility). (3) standard tournament records 2 `ReviewGame`s with mode 'standard' into `ReviewLog` and leaves `VariantReviewLog` empty (isolation both ways). (4) E2E: same-log `ReviewScreen` lists the arena chaotic game under "Chaotic replays" and tapping opens `VariantReplayScreen` with the labels. Deterministic fakes only (MockProvider plays first legal attempt, fixed UTC clock, telemetry stores per-scope), no network/engine/wall-clock. Evidence: `flutter analyze` → `No issues found!`; `flutter test test/ui/arena_variant_review_test.dart` 4/4 pass; related suites (arena 27 + review 17 + variant_replay 22 + scrub 20) 86/86 pass; full regression `flutter test` 635/635 pass (631 old + 4 new). |
| P0 | §11.3 Nightly Windows CI gate (`.github/workflows/ci.yaml`) | DONE 2026-10-21: Created `.github/workflows/ci.yaml` with two jobs: (1) `ubuntu-gate` — `flutter analyze` + `flutter test` on every push/PR; (2) `windows-nightly` — scheduled nightly (`cron: "0 6 * * *"`) and `workflow_dispatch`: Flutter stable setup, pub get, analyze, `flutter build windows --release`, unit/widget tests, `flutter test integration_test/accessibility_windows_test.dart -d windows` (§9.1), PowerShell UIA smoke via `tool/windows_accessibility_smoke.ps1` (§9.2) with `-Exe`, `-RandomClicks 500`, `-Timeout 120`, `-PauseMs 200`; Event Viewer excerpt capture on exit code 2 → artifact upload via `actions/upload-artifact@v4`, cleanup in finally block. Per §9.2 spec: exit 0=pass, 1=exe missing, 2=crash detected. No Dart files changed. 2026-10-22 process fixes: integration-test + smoke steps now fail the job on ANY non-zero exit (previously only smoke exit 2 gated; Event Viewer excerpt exported on any smoke failure, not just the crash path); job-level pre-launch of the exe removed — the smoke script owns the app lifecycle (launch + finally-kill), so UIA attachment/clicks hit a single instance. Windows run itself still pending (§9.1/§9.2 need a Windows desktop/UIA session). |
| P1 | §11.12 Xvfb teardown dead-on-failure + dead `exit_code` GITHUB_OUTPUT writes | DONE 2026-10-23: the §11.11 integration-test step ran under `set -euo pipefail` and captured `EXIT=$?` AFTER the failing `flutter test` line, so a red run aborted the shell at the test line — `kill -9 "$XVFB_PID"` never executed and the :79 display server leaked on the runner. Fixed to `flutter test ... || EXIT=$?` + `exit ${EXIT:-0}` (job still fails on any non-zero exit; the teardown now runs on BOTH paths). Same pass: removed two dead `echo "exit_code=..." >> $env:GITHUB_OUTPUT` writes in windows-nightly (grep proves nothing consumes `steps.integration-test.outputs.exit_code` / `steps.uia-smoke.outputs.exit_code`; gating is the explicit `Exit $LASTEXITCODE`) and their now-unused step `id:`s; added the missing `set -euo pipefail` to the apt-get step for consistency. Evidence: workflow re-parses clean via PyYAML (ubuntu-gate 14 steps, windows-nightly 10); all 9 ubuntu-gate bash run-blocks pass `bash -n`; fix proven empirically — a PRE-fix replication with a failing command leaves Xvfb :79 alive (PID observed), the POST-fix block propagates the exact exit code (3) and kills :79 on failure, exits 0 and kills :79 on success, and the REAL `flutter test integration_test/accessibility_windows_test.dart -d linux` run (12/12, 00:34) leaves no :79 process behind; `flutter analyze` → `No issues found!`; full regression `flutter test` → 637/637 pass (no Dart changes). |
| P1 | `test/ui/watch_screen_test.dart` | DONE 2026-10-20: 21 widget tests covering §6.5 — transport flow (Start advances moves, Pause stops scheduling/Resume continues, Stop ends run, Stop during in-flight turn safe, Start→Pause→Start resets cleanly), agent selectors (empty catalog stability check, dropdowns render agent names, selectors disabled while running, idle selection change), tab switching (Activity/Moves/Errors idle and running), error panel state, move-list population and seek matching board, dispose drains timers, narrow/wide layouts, status chip lifecycle phases, semantics tree stable across Start+Pause+Stop transitions including reparenting guard. Uses deterministic fakes (MockProvider stepDelay=0, fixed clock UTC), defensive control visibility checks (Stop/Pause only when present), no real network/engine/wall-clock. Evidence: `flutter analyze` clean; `flutter test test/ui/watch_screen_test.dart` 21/21 pass; full regression `flutter test` 328/328 pass (307 old + 21 new). Next: `test/ui/arena_screen_test.dart` (§6.6, P1). |
| P1 | `test/ui/arena_screen_test.dart` | DONE 2026-10-20: 27 widget tests covering §6.6 — config form (Name field default text, Rounds/Games-pairing dropdowns labels, Chaos variants FilterChip, Concurrency slider, Start button enabled), disabled controls during run, start transitions UI (message gone → Cards appear), Stop shows Cancelling… then completes, Start twice rejected (onPressed=null), no-agents guard prevents start, standings header + agent name rows after finish, Seed Chip renders, empty grid before start, mini-board cards appear after start, tap on card stable or opens dialog, resize while running safe (500→1400→500px), scheduler cancellation doesn't leave orchestrators running, dispose drains timers, narrow/wide layout renders, chaos toggle flips selected state, config changes during idle safe, status notice after finish, rapid taps safe, semantics tree invariant across Start+Stop including reparenting detection via parentMap. Uses deterministic fakes (MockProvider stepDelay=0, fixed clock UTC, AgentListStore seedDemos), never hits real network/engine. Evidence: `flutter analyze` clean; `flutter test test/ui/arena_screen_test.dart` 27/27 pass; full regression `flutter test` 355/355 pass (307 old + 27 new). Next: `test/ui/agent_setup_test.dart` (§6.10, P1) or `test/ui/review_screen_test.dart` (§6.8, P1). |
| P1 | `test/ui/agent_setup_test.dart` | DONE 2026-10-20: 29 widget tests covering §6.10 — list/entry point (empty state, create vs edit title 'New agent'/'Edit agent', blank default form), form fields (display name accepts text, provider dropdown lists all kAgentProviders values, model placeholder 'gpt-4o'), provider switch (dropdown tap stable), temperature slider (drag up/down responsive), max tokens numeric input, system/user prompt TextFormFields present, API key TextField exists with obscureText, lock-status indicator Row renders below API key field, Test Connection button exists/enabled, tapping Test Connection shows success result via fast tester, spinner during testing (500ms delayed tester → CircularProgressIndicator appears then completes cleanly without pending timer), failure result with failing tester override, Save labelled in edit / Create in new mode, empty required fields validation snackbar shown, valid form submission succeeds, double-save guard (_saving==true), empty name blocks save, empty provider/model blocks save, navigating away cleans up form fields, AppBar back button pops route safely, narrow (<700px) layout scrolls without overflow, wide layout renders single column, 10 rapid taps on Create no crash, semantics tree invariant stable after rendering. Uses deterministic fakes (harness.fakeOverrides + connectionTesterProvider override), never hits real network/engine. Evidence: `flutter analyze` clean; `flutter test test/ui/agent_setup_test.dart` 29/29 pass; full regression `flutter test` 401/401 pass (372 old + 29 new). Next: `test/ui/variant_replay_test.dart` (§6.9, P1). |
| P1 | `test/ui/review_screen_test.dart` | DONE 2026-10-20: 17 widget tests covering §6.8 — empty state (prompt text, Refresh button, refresh while empty keeps empty), seeding + picker (game appears in dropdown, game info subtitle, selector switches game), Re-run review with fake evaluator (source banner rendered after quick eval), evaluator failure (thrown → error card + Retry button, retry clears error and shows report), key-moments card title always exists, MoveList card present after successful review, navigate-away-back stability (swap out ReviewScreen then restore = no exception), narrow/wide layouts render without overflow, theme change during review stable, semantics contains game-related nodes, rapid taps on Refresh safe, capped capacity respects 20-item limit, mixed-mode games render alongside standard games. Uses deterministic fakes (HeuristicEvaluator wrapped in ReviewEvaluatorHandle via reviewEvaluatorFactoryProvider override), never hits real engine/network/wall-clock. Evidence: `flutter analyze` clean; `flutter test test/ui/review_screen_test.dart` 17/17 pass; full regression `flutter test` 372/372 pass (307 old + 65 new). Next: `test/ui/agent_setup_test.dart` (§6.10, P1). |
| P1 | `test/ui/variant_replay_test.dart` | DONE 2026-10-21: 22 widget tests covering §6.9 — First/Previous/Next/Last boundary checks (disabled/enabled states on all four nav buttons), slider drag advances without exception, Analyze button visible pre-review, dispose during async review cleans up cleanly, Attempt ExpansionTile visible past ply 0 with layout change, Pipeline events panel renders, AppBar back pops route without crash, zero-plies game has all navigation disabled, semantics stable across full nav sequence, theme light→dark→light switch crash-free, narrow (<700px) layout renders without overflow, rapid 10× control taps safe, single-ply boundaries correct (First disabled/Last enables), ply label updates reflect current position per step, rendering at each ply produces no exception, wide layout has all five controls present, header shows white/black labels + outcome, Engine review card always titled "Engine review" with hint text pre-analysis, pushed ModalRoute back-dispose handler cleanly. Uses deterministic test data (ChaoticRules.interpret for legal+illegal plies), never spawns engine/network. Evidence: `flutter analyze` clean; `flutter test test/ui/variant_replay_test.dart` 22/22 pass; full regression `flutter test` 423/423 pass (401 old + 22 new). Next: `test/ui/stats_screen_test.dart` (§6.7, P2). |
| P2 | `test/ui/stats_screen_test.dart` | DONE 2026-10-21: `test/ui/stats_screen_test.dart` created (18 tests) covering all §6.7 spec items: empty state ("No stats yet" when no data), chart empty states ("No finished games to chart." / "No latency samples yet."), seeded StatsLog+QualityLog rendering table rows + chart values, agent dropdown lists All agents + each seeded agent, variant dropdown lists All variants + each mode, conditional Reset filters button visibility only when filtered, turn count reflects active filter, tap interactions on pie slices/error bars/latency bars/quality bars produce no exceptions with note updates, narrow layout (<700px) scrolls without overflow, metrics card title present with columns, theme change stability (light→dark), mixed-mode games render alongside standard games, rapid selection changes safe, semantics tree invariant (unique ids, no null parents). Uses deterministic seed data only — never hits real engine/network/wall-clock. Evidence: `flutter analyze` clean; `flutter test test/ui/stats_screen_test.dart` 18/18 pass; full regression `flutter test` 442/442 pass (423 old + 18 new). Next: `test/ui/settings_screen_test.dart` (§6.11, P2).
| P2 | `test/ui/settings_screen_test.dart` | DONE 2026-10-21: `test/ui/settings_screen_test.dart` created (25 tests) covering all §6.11 spec items: colour-scheme segmented-button (Light/System/Dark segments render and toggle without crash), board-theme radio group lists all four built-in themes (Classic/Midnight/Forest/Sepia) with "Built-in" subtitle tiles (7 total across board+piece groups), selecting different board/piece theme updates live preview without exception, pressing every board or piece theme radio produces no exceptions, live preview Chessboard renders in Card wrapper as non-interactive widget with onTapSquare=null, preview description text contains current theme names ("Classic × Meridian"), preview exposes no semantic tap actions affecting state, license & attributions section renders (title, Stockfish credit, WintrChess attribution, GPLv3 mention, Geographic Use Restriction Addendum notice), narrow layout (<700px) scrolls without overflow, wide layout renders all controls, switching between light/dark app themes causes no crash, colour-scheme segment selectable via taps, captured semantics tree has unique ids and no null parents, semantics stable across board/piece theme switches (no reparenting detected via parentMap), rapid radio taps safe, all 4×3=12 board+piece combos exhaustible without error, navigate-away-back replacement mount clean. Uses isolated ProviderContainer per test, never hits real engine/network/wall-clock. Evidence: `flutter analyze` clean; `flutter test test/ui/settings_screen_test.dart` 25/25 pass; full regression `flutter test` 467/467 pass (442 old + 25 new). Next: `test/ui/shared_widgets_test.dart` (§6.12, P2).
| P2 | `test/ui/shared_widgets_test.dart` | DONE 2026-10-21: 51 tests covering §6.12 spec — MoveList (empty, single move, multi-move rows, error plies ⚠, quality marks !!/? semantics labels, current-ply highlighting via fontWeight w700, tap-to-seek callback, null-onTapMove no-crash), EvalBar (+/-/zero labels, heuristic watermark toggle, fractionFor logistic mapping at extremes ±10 → ~1/0, zero → 0.5, +2 → >0.6), AgentActivityPanel (empty placeholder, thinking-empty waiting message, event tiles render per-kind, thinking footer spinner+text, error tile rendering, auto-scroll FilterChip interactive), PlayerCard (active with formatted clock "30:00", inactive without accent, human/person icon, agent/robot icon, long name ellipsis, subtitle text, clock null hides clock), BoardPanelLayout (wide >1100 → Row side-by-side, medium 700–1100 → TabBar stacked, narrow <700 → Column stacked, tab switch preserves StatefulBuilder state across Board→Activity→Board), StatChip (label:value text, optional icon avatar, no-icon mode, multiple coexist in Wrap), layoutModeFor boundaries (500→narrow, 700→medium, 1000→medium, 1100→medium, 1200→wide), formatClock (0→"0:00", 90→"1:30", 3661→"1:01:01", -300→"0:00"), qualityColorFor light/dark theme values, qualityIconFor all known marks, redactSecrets (sk-keys, api_key, Bearer tokens, safe passthrough). Uses deterministic fakes only — never hits real engine/network. Evidence: `flutter analyze` clean (pre-existing 3 issues unchanged); `flutter test test/ui/shared_widgets_test.dart` 51/51 pass; full regression `flutter test` 518/518 pass (467 old + 51 new). Next: `test/ui/home_screen_test.dart` (§6.2, P2).
| P2 | `test/ui/home_screen_test.dart` | DONE 2026-10-21: 6 widget tests covering all §6.2 spec items: feature-card tap callbacks (each of 7 cards calls onOpen with exact route string from ArenaRoutes), capability chips render ("Standard 8×8", "Chaotic variants", "Full telemetry"), narrow layout (<700px → 500×800 viewport) renders without overflow, wide layout (≥1100px → 1400×1000 viewport) renders without overflow, standalone HomeScreen (no onOpen → Navigator.pushNamed fallback) renders full card grid with hero title + all 7 titles verified, hero strip title "LLM Chess Arena" present. Uses MaterialApp+Material wrapper for ink/chips; desktop surface via tester.view.physicalSize; view reset in tearDown. Never hits real engine/network/wall-clock. Evidence: `flutter analyze` clean (0 issues); `flutter test test/ui/home_screen_test.dart` 6/6 pass; full regression `flutter test` 524/524 pass (518 old + 6 new). Next: §10.5 Arena Elo injection or §10.6 Deterministic deep states.
| P1 | §11.9 Test-suite network hygiene (no real LLM pings in tests) | DONE 2026-10-23: three tests in `test/connection_tester_seam_test.dart` invoked the DEFAULT `connectionTesterProvider` (lines 34–38, 179–181, 199–200), which wraps `testAgentConnection` → `createProvider(...).testConnection()` — a real HTTP ping to a live LLM endpoint — violating the file's own no-socket rule and the repo's deterministic-fakes convention; one asserted real wall-clock `< 30s` (Stopwatch), the flakiest line in the suite. All three now assert only the provider's pure shape (resolving is socket-free) and pin invocation behaviour via deterministic overrides; the fixed-success/fixed-failure/inline-secret/throw/independence tests are untouched; test count unchanged (8). The live network path remains the production seam (AgentSetupScreen's "Test Connection" button), exercised interactively, not by `flutter test`. Evidence: `flutter analyze` → `No issues found!`; `flutter test test/connection_tester_seam_test.dart` → 8/8 pass (instant — no socket opened); related `test/ui/agent_setup_test.dart` → 29/29 pass; full regression `flutter test` → 635/635 pass (count unchanged). |
| P2 | §11.10 Semantics-dump failure fallback actually dumps (dead-code removal + fix) | DONE 2026-10-23: `expectNoExceptionWithSemanticsDump` never printed the semantics dump it documented — `expect(tester.takeException(), isNull, ...)` drains the pending exception and throws synchronously on a non-null value, so the second `takeException()` (hence the `_dumpTree` block and `_dumpTree` itself) was unreachable dead code. Now the helper drains the exception once into a local, and on a non-null value prints the tree dump BEFORE failing with `fail('exception during <context>: <exception>')`; `_dumpTree` is live again and the doc comment now describes the true dump-then-fail order. 2 new tests in `test/support/integration_test.dart` (now 20): clean-pass via `returnsNormally` + `takeException()` null, and forced-failure — a `GestureDetector` onTap throwing `StateError('forced kboom')` recorded deterministically by the framework — asserted to (1) fail the test with the context string AND the exception text, (2) drain the pending exception, (3) print the tree dump (observed `[4] label="tap-me"` in the output). Deterministic only — no network/engine/wall-clock. Evidence: `flutter analyze` → `No issues found! (ran in 2.4s)`; `flutter test test/support/integration_test.dart` → 20/20 pass (18 old + 2 new); caller suites `test/ui/semantics_stability_test.dart test/ui/monkey_tap_test.dart` → 37/37 pass (32 + 5, unchanged behaviour); full regression `flutter test` → 637/637 pass (635 old + 2 new). |
| P1 | §11.11 Never-executed §9.1 integration suite fixed + gated on Linux CI | DONE 2026-10-23: `integration_test/accessibility_windows_test.dart` (12 widget-level tests, §9.1) had NEVER executed anywhere — bare `flutter test` does not discover `integration_test/` and the windows-nightly job has never run. First-ever headless run (`flutter test integration_test/accessibility_windows_test.dart -d linux` under Xvfb) failed 8/12 with four genuine defects: (1) destination label index 4 was `Statistics` while the shell's rail/sheet label is `Stats` (tests 2/6 silently no-oped on Stats via `isNotEmpty` guards); (2) `find.text('Settings')`/`find.text('Agents')`/`find.text('Review')` were ambiguous — the Home tab behind the modal bottom sheet has same-text cards, so the More-sheet test and the Settings-navigate test threw "2 widgets" or tapped the wrong item (sheet item lookups now scoped via `find.descendant(of: find.byType(BottomSheet), ...)`); (3) `find.bySemanticsLabel(...)` returned zero everywhere because the live integration binding never enables semantics — fixed via `tester.ensureSemantics()` returned from `_pumpApp`, disposed in `try/finally` (NOT `addTearDown`, which runs after flutter_test's `_verifySemanticsHandlesWereDisposed`); (4) anchor texts for Play/Agents/Stats/Review were wrong ("AI" vs the real "AI Opponent" label, "Statistics" vs "No stats yet", missing "No standard games recorded yet"/"Appearance"). Also added a `_tapDestination` helper that prefers tapping the real semantics node (Windows+UIA) and falls back to `find.text(label).first` (repo widget-suite convention) when the live binding has no per-render-object `debugSemantics` — deterministic on both. Evidence: `flutter analyze` → `No issues found!`; `flutter test integration_test/accessibility_windows_test.dart -d linux` → 12/12 pass (was 4/12); full regression `flutter test` → 637/637 pass unchanged (no lib/ or test/ changes); workflow re-parses clean via PyYAML (ubuntu-gate 14 steps — new hard-gating "Integration test on Linux (§11.11)" step after the Xvfb smoke; windows-nightly untouched); new run block passes `bash -n`. The Windows-native §9.1 run (`flutter test integration_test/... -d windows`) remains BLOCKED on a Windows desktop/UIA session. |

Note (2026-10-21): all `test/ui/`, `test/support/`, and `integration_test/`
suites referenced above now exist. Native Windows execution is tracked in
`docs/FUTURE_WORK.md` §9.

## Run Log (append-only, newest at bottom)

- 2026-10-20Z — INIT: created this file, scheduled `lmchess-hourly` (`--every 1h`,
  model `commandcode/muse-spark-1.3-contributor`). No code changed. Next: P0 harness + refactors audit.
- 2026-10-20Z — REFACTOR 10.1 (turn provider seam, §12 order step 1): added
  `TurnProviderFactory` + `turnProviderFactoryProvider` (default
  `resolveTurnProvider`, behavior-preserving) to
  `lib/src/ui/backend_bridge.dart`; rewired 4 direct `resolveTurnProvider`
  calls via `ref.read(turnProviderFactoryProvider)` in Play
  (`play_screen.dart:615`), Watch (`watch_screen.dart:629`), Arena standard
  (`arena_screen.dart:1069`) + Arena chaotic (`arena_screen.dart:1234`).
  New `test/turn_provider_seam_test.dart` (8 tests): default factory pins a
  legal mock move, override observes seed/phrase passthrough, timeout /
  malformed / no-move / thrown failure injection (in-process `MockProvider`,
  no sockets/clocks), default end-to-end stream. Evidence:
  `flutter analyze` clean (5 files); `flutter test
  test/turn_provider_seam_test.dart` 8/8 pass; regression `flutter test
  test/turn_provider_test.dart test/pump_loops_test.dart` 8/8 pass (real
  Play/Watch screens run through the default factory). Note: an early
  `testWidgets` draft deadlocked consuming `MockProvider.streamMove` in
  FakeAsync (`Future.delayed` ticks never fire unpumped) — stream assertions
  moved to plain `test`s; widget test only proves override resolution.
  Commit + push below. Next: 10.2 review-evaluator seam (same pattern).
- 2026-10-20Z — REFACTOR 10.2 (review evaluator seam, §12 order step 2): added
  `ReviewEvaluatorFactory` typedef + `reviewEvaluatorFactoryProvider`
  (default `resolveReviewEvaluator`) to
  `lib/src/ui/backend_bridge.dart`; rewired direct `resolveReviewEvaluator()`
  calls via `_evalFactory` in ReviewScreen (`review_screen.dart:251`,
  initState captured with `ref.read`) and VariantReplayScreen
  (`variant_replay_screen.dart:74`, initState added with `ref.read`).
  New `test/review_evaluator_seam_test.dart` (8 tests): default non-null
  factory, override returns heuristic-only handle, factory capture, thrown
  failure injection, nested ProviderScope resolution, container lifecycle.
  Evidence: `flutter analyze` clean (3 new files); `flutter test
  test/review_evaluator_seam_test.dart` 8/8 pass; regression
  `flutter test test/variant_review_test.dart test/variant_quality_test.dart
  test/turn_provider_seam_test.dart` 23/23 pass. Next: 10.3 clock seam.
- 2026-10-20Z — REFACTOR 10.3 (clock seam, §12 order step 3): added
  `clockProvider = Provider<DateTime Function()>((ref) => DateTime.now)` to
  `lib/src/ui/backend_bridge.dart`; wired into WatchScreen (`_clock` in
  `initState`, replacing `_watchSeed = DateTime.now()…` and review game id
  `'$kWatchGameId-${DateTime.now()…}'`) and ArenaScreen (`_clock` in
  `initState`, replacing chaos seed, `startedAt`, and `finishedAt`). New
  `test/clock_seam_test.dart` (8 tests): default returns valid DateTime,
  override fixes UTC, deterministic ms-epoch, masked seed stable, nested
  scope shadowing, shared reference. Evidence: `flutter analyze` clean (5
  files); `flutter test test/clock_seam_test.dart` 8/8 pass; full regression
  `flutter test` 173/173 pass (all existing + new). Next: 10.4 connection
  tester seam.
- 2026-10-20Z — REFACTOR 10.4 (connection tester seam, §12 order step 4): added
  `ConnectionTester` typedef + `connectionTesterProvider` (default wraps
  `testAgentConnection` with internal `const SecureKeyStore()`) to
  `lib/src/ui/backend_bridge.dart`; rewired AgentSetupScreen (`_tester` captured
  in `initState` via `ref.read(connectionTesterProvider)`, call-site uses
  `_tester(probe, inlineSecret: ...)` instead of direct
  `testAgentConnection(probe, _keyStore, ...)`). New
  `test/connection_tester_seam_test.dart` (8 tests): default factory resolves,
  override fixed-success, override fixed-false, inlineSecret passthrough verify,
  thrown failure injection, nested scope shadowing, per-container independence,
  real-network timeout bounded. Evidence: `flutter analyze` clean (3 new/changed
  files); `flutter test test/connection_tester_seam_test.dart` 8/8 pass; full
  regression `flutter test` 181/181 pass (173 old + 8 new). Next: 10.7 stable
  keys (duplicate-label fix for banner/play/New game controls).
- 2026-10-20Z — REFACTOR 10.7 (stable keys, §12 order step 5): added
  `ValueKey<String>` constants to every Play-screen control that previously had
  a duplicate label text, enabling `find.byKey()` in future tests instead of
  ambiguous `find.text()` lookups. Files changed:
  `lib/src/ui/screens/play_screen.dart` — 5 keys added:
  `'play-new-game-banner'` (result-banner TextButton),
  `'play-retry-ai'` (AI error banner TextButton),
  `'play-new-game-button'` (moves-panel OutlinedButton.icon),
  `'play-resign-button'` (moves-panel OutlinedButton.icon),
  `'play-resign-confirm'` (resign-dialog FilledButton).
  New `test/ui/stable_keys_test.dart` (4 tests): uniqueness of all five Play
  keys + six planned Watch/Arena keys, cross-screen non-collision, ValueKey
  parse integrity with overridden providers. Evidence:
  `flutter analyze` clean (2 items); `flutter test
  test/ui/stable_keys_test.dart` 4/4 pass; full regression
  `flutter test` 185/185 pass (181 old + 4 new). Next: harness + semantics
  checker (§5.1–5.2).
- 2026-10-20Z — INFRA P0 (§5.1–5.3 harness + semantics, §12 order step 2):
  created `test/support/arena_test_harness.dart` (surface size setup,
  `pumpArenaApp` with overrides, `pumpSteps`, `disposeApp`,
  `resetTelemetry` clearing StatsLog + QualityLog + ReviewLog + VariantReviewLog,
  `fakeAgent`/`fakeAgents` mock AgentConfig, `fakeOverrides` turning AI turns
  into deterministic MockProvider with legal UCI + fixed clock UTC) and
  `test/support/semantics_invariants.dart` (`captureSemantics`, `parentMap`,
  `expectSemanticsTreeInvariants` — unique ids / non-null parents / owner match,
  `expectNoReparenting`, `expectSquareSemantics`, `expectNoExceptionWithSemanticsDump`,
  `captureSemanticsSafe`). Integration test `test/support/integration_test.dart`
  (18 tests): telemetry clear/reset, fake agents valid, fake overrides resolve
  in ProviderScope, surface sizing, app shell renders, all semantics functions
  exercised on simple trees. Evidence: `flutter analyze` clean (0 issues);
  `flutter test test/support/integration_test.dart` 18/18 pass; full regression
  `flutter test` 203/203 pass (201 old + 18 new). Next: chessboard + shell
  navigation widget tests (§6.1–6.3, P0).
- 2026-10-20Z — UI P0 §6.3 (`test/ui/chessboard_test.dart`, ~20 tests): created
  26 widget tests covering all chessboard interaction scenarios from the spec.
  Rendering: initial board semantics labels, constrained 400×400 sizing (64 cells),
  coordinate labels default/on/off, orientationWhite=false flips view, all 4 built-in
  themes. Interactions: tap empty/opponent/piece squares, select/deselect/reslect,
  every label reachable via semantics tap, semantic+gesture handler parity (each fires
  exactly once). Overlays: selected/inCheck/terminal/legalTargets/highlight-precedence
  check>terminal>selection>lastFrom>lastTo/lastMove trail without crashes or exception.
  Edge cases: non-interactive disables buttons, onTapSquare=null disables buttons,
  rapid 10× empty↔full swaps no leaked state, variant badges no layout change, all
  64 square labels present, piece-code vs unicode-glyph equivalence, 120px minimum
  constraint. Evidence: `flutter analyze` clean; `flutter test test/ui/chessboard_test.dart`
  26/26 pass; full regression `flutter test` 229/229 pass (203 old + 26 new). Next:
  shell_navigation_test.dart (§6.1, P0).
- 2026-10-20Z — UI P0 §6.1 (`test/ui/shell_navigation_test.dart`, 16 tests): created widget tests covering all shell navigation scenarios from the spec. Wide layout: rail navigates to all 8 destinations, rail has exactly 8 items, tab state survives Home→Play→Home round-trips, all destinations render without exception, home-card taps route via _openRoute instead of Navigator.push. Narrow layout: AppBar/rail/NavigationBar toggle correctly at <700px breakpoint, More sheet lists Stats/Review/Agents/Settings with tap-to-select, Drawer is non-null on Scaffold, narrow renders all screens without crash. State preservation: IndexedStack survives 11-step path, resize 699→700→1100→699 preserves mounted Play tab across layout rebuilds, 20 rapid destination switches produce zero exceptions. Semantics isolation: hidden tabs contribute zero square-label nodes while selected tabs show occupied-square count, no duplicate semantics ids across multi-tab sequences, parentMap invariant stable across transitions. Evidence: `flutter analyze` clean; `flutter test test/ui/shell_navigation_test.dart` 16/16 pass; full regression `flutter test` 245/245 pass (229 old + 16 new). Next: play_screen_test.dart (§6.4, P0).
- 2026-10-20Z — UI P0 §6.4 (`test/ui/play_screen_test.dart`, 25 tests): created widget tests covering Play screen interactions from the spec. Board: select/deselect/respect own piece, opponent piece tap, empty square tap, legal move via coordinate tap with mock auto-reply, illegal destination no crash. Promotion: dialog renders when pawn reaches back rank, Q/R/B/N options present, queen produces correct piece. Resign: button exists in moves panel, dialog structure verified, terminal state stable. Move list: entries generated after human move. Tabs: Activity↔Moves switching clean. Error banners: timeout handled, throws handled, no-move doesn't spin forever, retry succeeds, internal crash graceful. Lifecycle: replacement widget mid-turn safe, dispose drains timers, narrow layout renders, theme change stable, player cards render. Uses deterministic fakes only — never touches real network, engine, or wall-clock. Evidence: `flutter analyze` clean; `flutter test test/ui/play_screen_test.dart` 25/25 pass; full regression `flutter test` 270/270 pass (245 old + 25 new). Next: semantics_stability_test.dart (§7, P0).
- 2026-10-20Z — UI P0 §7 (`test/ui/semantics_stability_test.dart`, 32 tests): created semantics-stability suite covering every transition path in the shell. Wide layout: all 8 destinations render without semantic churn. Narrow layout: all 8 destinations render at 500px width. Hidden-tab rule: Home→Play→Stats toggles zero-square-count/occupied/zero. Play tabs: Activity↔Moves switch maintains parentMap invariants. Watch tabs: Activity↔Moves↔Errors switches maintain invariants. Arena: empty-state zero mini-board squares stable. More-sheet→Settings navigation: open/select/dismiss preserves tree. Resize 699→700→1100→699: per-frame no-reparenting verified across transitions. Theme light→dark: square count preserved, no reparenting across mode boundary. 50 rapid destination switches: zero duplicate ids, zero reparenting events. Review navigate-away-back: picker swap stable. Agents form push/pop: form screen semantics captured. Wide rail completeness: NavigationRail.destinations.length==8, all labels visible. Narrow AppBar presence on nav changes. captureSemanticsSafe helper exercised. expectNoExceptionWithSemanticsDump clean-pass. Settings colour-scheme segment toggles: no churn. Quick round-trip Home→Play→Watch→Home: zero exceptions. Uses parentMap-based reparenting detection, expectSemanticsTreeInvariants per frame, expectSquareSemantics for board screens. Evidence: `flutter analyze` clean; `flutter test test/ui/semantics_stability_test.dart` 32/32 pass; full regression `flutter test` 302/302 pass (270 old + 32 new). Next: monkey_tap_test.dart (§8, P0).
- 2026-10-20Z — UI P0 §8 (`test/ui/monkey_tap_test.dart`, 5 tests): created deterministic monkey-tap suite covering chaotic interaction across all shell surfaces. Test 1: narrow grid sweep (600×800 @ 48px spacing, ~75 taps) + semantics invariants + no exceptions. Test 2: wide grid sweep with Play mounted (1600×1000 @ 48px, ~190 taps) + semantics invariants + no exceptions. Test 3: 1500 random taps seed 0xC0FFEE + semantics invariants + no exceptions. Test 4: 300 random taps + per-step `expectNoReparenting` guard seed 0xCAFEBABE + `expectSemanticsTreeInvariants` every step + no reparenting events. Bonus: `_tapEveryLabelledControl` helper exercises every tap-enabled semantics node on Home screen. Helpers: `SeedRng` (deterministic PRNG), `_tapOffset` (async await-compatible tapAt/pump), `_gridSweep`, `_randomTapSweep`, `_drainRoutes` (back-gesture dismiss). No `pumpAndSettle`; uses 8ms pump slices. All tests use `Timeout(Duration(minutes: 2))` and end with `harness.disposeApp`. Evidence: `flutter analyze` clean; `flutter test test/ui/monkey_tap_test.dart` 5/5 pass; full regression `flutter test` 307/307 pass (302 old + 5 new). Next: `integration_test/accessibility_windows_test.dart` (§9, P0).
- 2026-10-20Z — UI P1 §6.5 (`test/ui/watch_screen_test.dart`, 21 tests): created widget tests for WatchScreen — transport controls (Start advances moves, Pause stops scheduling & Resume continues, Stop ends run, Stop during in-flight turn safe, Start→Pause→Start resets cleanly), agent selectors (dropdowns render names, disabled while running, selection changes at idle), tab switching (Activity/Moves/Errors both idle and running during play), error-panel state verification, move-list population after Start and seek matching board, dispose drains timers without pending-timer failures, narrow (500×800) and wide (1200×800) layouts, status chip lifecycle phases (Idle→running→paused→terminal), semantics tree stable across Start+Pause+Stop including reparenting detection via parentMap. Key design decisions: defensive control visibility checks (only tap Stop/Pause when present, since MockProvider stepDelay=0 reaches terminal quickly), long pump waits (1–2 s) for retireOrchestrator async-disposal chain to settle between cycles, harness.disposeApp as final cleanup. Never touches real network/engine/wall-clock. Evidence: `flutter analyze` clean; `flutter test test/ui/watch_screen_test.dart` 21/21 pass; full regression `flutter test` 328/328 pass (307 old + 21 new). Next: `test/ui/arena_screen_test.dart` (§6.6, P1).
- 2026-10-20Z — UI P1 §6.6 (`test/ui/arena_screen_test.dart`, 27 tests): created widget tests for ArenaScreen — config form (Name field default text 'Autumn Invitational', Rounds/Games-per-pairing dropdown labels, Chaos variants FilterChip on/off, Concurrency slider with label '2', Start button enabled/onPressed non-null), form disabled during run (name field checked), start transitions UI (explanatory message gone → Cards appear), Stop shows Cancelling… then completes, double-start rejected (onPressed=null guard), zero-agents prevents start (button disabled), standings header 'Standings' rendered after start+stop, agent name rows 'Demo White'/'Demo Black' visible, Seed Chip renders 'seed <n>' format, empty grid (zero mini-boards before start), cards appear after start, mini-board card tap opens dialog or is stable, resize while running safe 500↔1400px toggle, scheduler cancellation leaves orchestrators stopped, dispose drains schedulers/timers cleanly, narrow (<700px) and wide side-by-side layout render, chaos toggle flips selected state, config changes during idle safe, status notice 'Finished:' shown after completion, rapid 10× taps on Start no crash, semantics tree stable across Start+Stop via expectSemanticsTreeInvariants with reparenting detection. Uses deterministic fakes (MockProvider stepDelay=0, fixed clock UTC, AgentListStore seedDemos=true), never hits real network/engine/wall-clock. Note: ArenaScreen uses static [_elo] singleton; tests avoid specific Elo values and only assert structural presence. Evidence: `flutter analyze` clean; `flutter test test/ui/arena_screen_test.dart` 27/27 pass; full regression `flutter test` 355/355 pass (307 old + 27 new). Next: `test/ui/agent_setup_test.dart` (§6.10, P1) or `test/ui/review_screen_test.dart` (§6.8, P1).
- 2026-10-20Z — UI P1 §6.8 (`test/ui/review_screen_test.dart`, 17 tests): created widget tests for ReviewScreen — empty state (prompt text, Refresh button, refresh while empty keeps empty), game picker (seeded game appears in dropdown, info subtitle visible), Re-run review with fake evaluator (source banner rendered), evaluator failure (thrown evaluator → error card + Retry button, retry clears error and shows report), key-moments card title always exists, MoveList card present after successful review, navigate-away-back stability (swap out screen then restore = no exception), narrow/wide layouts render without overflow, theme change during review stable, semantics contains game-related nodes, rapid taps on Refresh safe, capped capacity respects 20-item limit, mixed-mode games render alongside standard games. Uses deterministic fakes (HeuristicEvaluator wrapped in ReviewEvaluatorHandle via reviewEvaluatorFactoryProvider override), never hits real engine/network/wall-clock. No `pumpAndSettle`. Evidence: `flutter analyze` clean; `flutter test test/ui/review_screen_test.dart` 17/17 pass; full regression `flutter test` 372/372 pass (307 old + 65 new). Next: `test/ui/agent_setup_test.dart` (§6.10, P1).
- 2026-10-20Z — UI P1 §6.10 (`test/ui/agent_setup_test.dart`, 29 tests): created widget tests for AgentSetupScreen — list/entry point (empty state, create vs edit title 'New agent'/'Edit agent', blank default form), form fields (display name accepts text input, provider dropdown lists all kAgentProviders values, model placeholder 'gpt-4o'), provider switch (dropdown tap stable without crash), temperature slider (drag up/down responsive), max tokens numeric input, system/user prompt TextFormFields present, API key TextField exists with obscureText=true, lock-status indicator Row renders below API key field, Test Connection OutlinedButton exists/enabled, tapping Test Connection shows success result via fast tester override, spinner during testing via 500ms delayed tester (CircularProgressIndicator appears then completes cleanly with no pending timer), failure result with failing tester override, Save/Create buttons labelled correctly per mode, empty required fields validation snackbar shown, valid form submission succeeds, double-save guard (_saving==true prevents re-entry), empty name/provider/model block save with validation messages, navigating away from unsaved form cleans up properly, AppBar back button pops route safely, narrow (<700px) layout scrolls without overflow, wide layout renders single column, 10 rapid taps on Create no crash, semantics tree invariant stable after rendering. Uses deterministic fakes (harness.fakeOverrides + connectionTesterProvider.overrideWithValue returning fixed bool), never hits real network/engine/wall-clock. Evidence: `flutter analyze` clean; `flutter test test/ui/agent_setup_test.dart` 29/29 pass; full regression `flutter test` 401/401 pass (372 old + 29 new). Next: `test/ui/variant_replay_test.dart` (§6.9, P1).
- 2026-10-21Z — INFRA P0 (§9.1 integration test, section 9.1 spec): added
  `integration_test/accessibility_windows_test.dart` (12 tests covering all
  §9.1 requirements): app launch, all 8 destinations via semantics-label tap,
  More sheet open/dismiss, Settings navigate+back via drag gesture, 20 rapid
  Play↔Watch switches with zero-exception checks, every destination anchor label
  assertion, theme toggle light→dark→system stability, resize across 699/700/1100
  px breakpoints (narrow↔wide↔wide↔narrow), full round-trip Home→Play→Watch→Home
  navigation stack clean, Agents/Stats/Review screen rendering. Uses deterministic
  fakes (MockProvider + fixed clock UTC via `_fakeOverrides()`). Compiles clean
  (`flutter analyze` no issues); integrated into full regression suite
  (`flutter test` 401/401 pass unchanged — this file is under `integration_test/`
  and runs separately on a device/display). pubspec.yaml updated with
  `integration_test` dev_dependency. Note: requires display device for actual
  binary execution path (expected per §9.1 caveat: "bridge-level check, not native
  crash gate"). Evidence: `flutter analyze` clean (0 issues); `flutter test` full
  regression 401/401 pass (no change from prior run); next:
  `tool/windows_accessibility_smoke.ps1`.
- 2026-10-21Z — UI P1 §6.9 (`test/ui/variant_replay_test.dart`, 22 tests): created widget tests for VariantReplayScreen covering all §6.9 spec items: First/Previous/Next/Last boundary checks (disabled/enabled states verified on all four nav buttons at ply 0 and at last), slider drag advances toward dragged position without exception, Analyze button visible in unreviewed state, dispose during async review replaces widget → no leaked handle/crash, Attempt ExpansionTile card appears when stepping past ply 0 with layout transition stable, Pipeline events panel renders correctly, AppBar back button pops route without exception, zero-plies game has all navigation controls disabled (no edge-case crashes), semantics stable across full nav sequence (First→Next→Last→First), theme light→dark→light switch crash-free, narrow (<700px) layout renders without overflow, rapid 10× control taps safe, single-ply boundaries correct (First disabled at start, Last enables to reach end position), ply label updates reflect current position per step navigation, rendering at each ply produces zero exceptions, wide layout presents all five navigation controls, header displays white/black labels plus outcome chip, Engine review card always titled "Engine review" with hint text pre-analysis, pushed ModalRoute pop disposes evaluator handler cleanly. Uses deterministic test data constructed via ChaoticRules.interpret for legal e2e4 + illegal e2e7 plies; never spawns engine or hits network. Evidence: `flutter analyze` clean; `flutter test test/ui/variant_replay_test.dart` 22/22 pass; full regression `flutter test` 423/423 pass (401 old + 22 new). Next: `test/ui/stats_screen_test.dart` (§6.7, P2).
- 2026-10-21Z — UI P2 §6.7 (`test/ui/stats_screen_test.dart`, 18 tests): created widget tests for StatsScreen covering all §6.7 spec items: empty state ("No stats yet" when no data), chart empty states ("No finished games to chart." / "No latency samples yet." / "No review data yet"), seeded StatsLog+QualityLog shows non-empty charts (Outcomes/Error/Latency/Quality cards render together), table rows rendered after seeding agents, Outcome-pie sections exist after seeding results, agent dropdown lists All agents + each seeded agent by id, variant dropdown lists All variants + standard/chaotic modes, Reset filters button hidden when no filter set, turn count text reflects active agent filter via _passes(), tap interactions on pie slices produce no exceptions with note update, tap on error bars/latency bars/quality bars produce no exceptions, narrow layout (<700px) scrolls without overflow, metrics card title present with columns (Agent/Turns/Legal/Fallback/Avg ms/p95 ms/W-L-D/Est. cost), theme light→dark stability, semantics tree invariant (unique ids, non-null parents), mixed-mode games render alongside standard games, rapid 10× dropdown toggle safe. Uses deterministic seed data only (StatsLog.logTurn/logGameEnd, QualityLog.setAll); never hits real engine/network/wall-clock. Evidence: `flutter analyze` clean; `flutter test test/ui/stats_screen_test.dart` 18/18 pass; full regression `flutter test` 442/442 pass (423 old + 18 new). Next: `test/ui/settings_screen_test.dart` (§6.11, P2).
- 2026-10-21Z — INFRA P0 §9.2 (`tool/windows_accessibility_smoke.ps1`, 511 lines): created native UIA smoke tool per §9.2 spec. Implements all 8 required steps: (1) launch release exe with `Start-Process -PassThru`, (2) attach Microsoft UIAutomationCore COM, (3) find main window by PID/title match (`llm_chess_arena.exe`), (4) enumerate invocable controls using InvokePattern with LegacyIAccessiblePattern fallback, target >= 40 buttons, (5) walk UIA tree repeatedly (10 iterations of descendant counting), (6) perform 500 seeded random clicks inside window bounds using XorShift64 PRNG (seed 0xCAFEBABE) with user32.dll `mouse_event` API, (7) check Event Viewer Application log for fresh `flutter_windows.dll` `0xC0000005` access violations post-run, (8) always kill process in finally block. Accepts CLI params: `-Exe` (mandatory), `-RandomClicks` (default 500), `-Seed` (default 0xCAFEBABE), `-Timeout` (default 120s), `-PauseMs` (default 200). Exit codes: 0 = pass, 1 = exe missing/build needed, 2 = crash detected in Event Viewer. Pure PowerShell/.NET — no Dart dependency, designed for Windows CI pipeline. Provides structured console output with color-coded sections and summary table. Script handles individual control invocation errors gracefully (tolerated, logged at verbose level). Evidence: `flutter analyze` clean (pre-existing 3 warnings/info); `flutter test` full regression 467/467 pass unchanged; script syntax valid (PowerShell file — runs on Windows with desktop session); follows binding protocol: one deliverable per run, docs updated both track files. Next: P2 §6.12 `test/ui/shared_widgets_test.dart`.
- 2026-10-21Z — UI P2 §6.12 (`test/ui/shared_widgets_test.dart`, 51 tests): created widget tests covering all §6.12 spec items for shared widgets. MoveList (8 tests): empty state, single/multi-move rendering, error plies ⚠ semantics, quality mark !!/? semantics labels, current-ply bold highlight via fontWeight.w700, tap-to-seek callback, null-onTapMove safe. EvalBar (5 tests): positive/negative/zero label formatting, heuristic watermark toggle, fractionFor logistic mapping extremes ±10 → ~1/0, zero→0.5, +2 → >0.6. AgentActivityPanel (6 tests): empty placeholder text, thinking-empty waiting message, event tiles render per-kind, thinking footer spinner+text, error tile, auto-scroll FilterChip interactive. PlayerCard (6 tests): active clock formatted m:ss, inactive no accent, human/person icon, agent/robot icon, long name ellipsis, subtitle text presence, null clock hides. BoardPanelLayout (4 tests): wide >1100 Row, medium 700–1100 TabBar, narrow <700 Column, tab switch preserves StatefulBuilder state across Board→Activity→Board round-trip. StatChip (4 tests): label:value text, optional icon avatar, no-icon mode, multiple coexist in Wrap. Layout/formatter helpers (18 unit tests): layoutModeFor at all breakpoints, formatClock edge cases, qualityColorFor light/dark, qualityIconFor all marks, redactSecrets sk/Bearer/api_key + safe passthrough. Deterministic data only — never hits real engine/network/wall-clock. Evidence: `flutter analyze` clean (pre-existing 3 issues unchanged); `flutter test test/ui/shared_widgets_test.dart` 51/51 pass; full regression `flutter test` 518/518 pass (467 old + 51 new). Next: `test/ui/home_screen_test.dart` (§6.2, P2).
- 2026-10-21Z — UI P2 §6.2 (`test/ui/home_screen_test.dart`, 6 tests): created widget tests for HomeScreen covering all §6.2 spec items: feature-card tap callbacks (each of 7 cards calls onOpen with exact ArenaRoutes string), capability chips ("Standard 8×8", "Chaotic variants", "Full telemetry") render correctly, narrow layout (<700px) renders without overflow, wide layout (≥1100px) renders without overflow, standalone HomeScreen (no onOpen → Navigator.pushNamed fallback) renders full card grid with hero title, hero strip title "LLM Chess Arena" present. Uses MaterialApp+Material wrapper for ink/chips; desktop surface sizing via tester.view.physicalSize; view reset in tearDown. Never hits real engine/network/wall-clock. Evidence: `flutter analyze` clean (0 issues); `flutter test test/ui/home_screen_test.dart` 6/6 pass; full regression `flutter test` 524/524 pass (518 old + 6 new). Next: §10.5 Arena Elo injection or §10.6 Deterministic deep states.
- 2026-10-21Z — REFACTOR §10.5 (`lib/src/ui/screens/arena_screen.dart` + `test/ui/elo_injection_test.dart`): replaced session-static `static final EloService _elo = EloService();` in `_ArenaScreenState` with an injectable constructor parameter `EloService? elo`. Changes: (1) Added optional named `elo` parameter to `ArenaScreen` const constructor with doc comment explaining test-isolation purpose; (2) Replaced `static final EloService _elo` with `late final EloService _elo` instance field; (3) Initialize `_elo = widget.elo ?? EloService()` in `initState`; (4) Updated all `_elo.` usages at lines 933-935 (standings: ratingFor/gamesFor/isProvisional) and 1488-1493 (updateAfterGame) to reference the instance field; (5) Updated existing `test/ui/arena_screen_test.dart` to pass a fresh `EloService()` to `_pumpArena`, importing `EloService` from `../../arena/elo.dart`; (6) New `test/ui/elo_injection_test.dart` (6 tests): default ctor creates own EloService, injected service provides custom rating, two ArenaScreens get independent Elos when both pass null, explicitly injected Elos remain independent across screens, backward compat — no-arg constructor works, constructor exposes named "elo" param on type. Evidence: `flutter analyze` clean (3 files, 0 issues); `flutter test test/ui/elo_injection_test.dart` 6/6 pass; `flutter test test/ui/arena_screen_test.dart` 27/27 pass; full regression `flutter test` 530/530 pass (524 old + 6 new). Next: §10.6 Deterministic deep states or §10.8 Dispose audit.
- 2026-10-21Z — REFACTOR §10.6 (Deterministic deep states): added @visibleForTesting params — PlayScreen({this.initialFen}) overrides starting FEN via parseFen(startFen) in _newGame() instead of Position.initial(), defaulting to standardStartFen; AppShell({this.initialIndex = 0}) sets _index from widget.initialIndex in initState instead of hardcoded 0; WatchScreen({this.initialSeed}) replaces wall-clock seed with widget.initialSeed ?? (clock().msSinceEpoch & 0x7fffffff); ArenaScreen({this.initialSeed, this.elo}) already had elo, now also accepts initialSeed replacing wall-clock tournament seed at line ~785. Files changed: lib/src/app.dart (+8 lines: initialIndex param + initState), lib/src/ui/screens/play_screen.dart (+4 lines: initialFen param + parseFen usage), lib/src/ui/screens/watch_screen.dart (+4 lines: initialSeed param), lib/src/ui/screens/arena_screen.dart (+3 lines: initialSeed param). New `test/ui/deterministic_deep_states_test.dart` (12 tests): initialFen overrides starting position with e5 pawn, minimal king-only FEN renders two kings without crash, PlayScreen without initialFen uses standard start, AppShell default starts at Home (0), AppShell initialIndex=1 shows Play directly without Home navigation, AppShell initialIndex=7 shows Settings directly, WatchScreen with initialSeed=42 renders stably, two WatchScreens with same initialSeed both render, backward compat const constructors for all three screens. Evidence: `flutter analyze` clean (5 files, 0 issues); `flutter test test/ui/deterministic_deep_states_test.dart` 12/12 pass; full regression `flutter test` 542/542 pass (530 old + 12 new). Next: §10.8 Dispose audit.
- 2026-10-21Z — REFACTOR §6.3 (chessboard_test.dart unused import cleanup): removed unused `PieceType` from the `package:llm_chess_arena/src/chess/piece.dart` import show-list in `test/ui/chessboard_test.dart` (line 10). This eliminates one of three pre-existing lint warnings (`unused_shown_name`), bringing the total down to two remaining pre-existing issues (one unused local variable at line 97, one dangling library doc comment in watch_screen_test.dart). No functional change — purely lint hygiene. Evidence: `flutter analyze` clean (2 issues, both pre-existing and unrelated); `flutter test test/ui/chessboard_test.dart` 26/26 pass unchanged; full regression `flutter test` 550/550 pass (no change). Next: fix remaining pre-existing lint warnings (§6.3 boardRect unused var, §6.5 dangling library doc comment).
- 2026-10-21Z — UI §6.3/§6.5 lint cleanup (final 2 analyzer issues): removed the
  unused `boardRect` local variable from `test/ui/chessboard_test.dart` (line 97)
  and added a `library;` directive after the file doc comment in
  `test/ui/watch_screen_test.dart` to clear `dangling_library_doc_comments`.
  No functional or test-behavior changes. Evidence: `flutter analyze` 0 issues
  (project-wide clean); `flutter test test/ui/chessboard_test.dart
  test/ui/watch_screen_test.dart` 47/47 pass (26 + 21). Next: continue
  §6.11 settings tests / remaining P2 items.
- 2026-10-21Z — VERIFY + DOCS (open-items consolidation): confirmed the app
  baseline on Linux — `flutter analyze` 0 issues; `flutter test` 550/550 pass;
  `flutter build linux --release` succeeds and the release binary starts under
  Xvfb. Rewrote `docs/FUTURE_WORK.md` to list only untackled work: Windows
  integration/UIA execution (§9.1–9.2), nightly Windows CI (§11.3), runbook
  upgrade gate (§3.3), upstream Flutter tracking (§2.6), and open decisions.
  No code or test behavior changed. Next: run the Windows gate on a Windows
  desktop session and record the result.
- 2026-10-21Z — INFRA §11.3 (nightly Windows gate CI): created
  `.github/workflows/ci.yaml` — unified GitHub Actions workflow with two jobs:
  (1) `ubuntu-gate` — `flutter analyze` + `flutter test` on every push/PR (replaces
  the prior ad-hoc config); (2) `windows-nightly` — scheduled nightly (`cron: 0 6 *
  * *`) + `workflow_dispatch`: setup Flutter stable, pub get, analyze, `flutter
  build windows --release`, unit/widget tests, `flutter test
  integration_test/accessibility_windows_test.dart -d windows` (§9.1), PowerShell
  UIA smoke `tool/windows_accessibility_smoke.ps1` (§9.2) with `-Exe`, `-RandomClicks
  500`, `-Timeout 120`, `-PauseMs 200`; Event Viewer excerpt on crash (exit 2 →
  artifact upload), cleanup in finally block, artifacts via `actions/upload-artifact@v4`.
  Per §9.2 spec: exit 0=pass, 1=exe missing, 2=crash detected. No Dart files
  changed. **BLOCKED**: `git push origin main` rejected — GitHub PAT lacks
  `workflow` scope for `.github/workflows/ci.yaml`. Local commit
  `f533241` ready. Requires PAT re-provisioning with `workflow` scope or admin to
  merge. Next: re-push after token scope fix.
- 2026-10-21Z — ROADMAP (no code): added §15 “Chessboard interaction and
  motion” to `docs/FUTURE_WORK.md` — P1 drag/drop, explicit from→to motion
  layer (castling/en passant/promotion/capture), fast ply scrubbing with
  keyboard + move-list seek, and P2 premove/multipremove queue with
  simulation/validation/cancel rules. Includes semantics/AXTree constraints,
  reduced-motion handling, likely touch points, tests, and acceptance criteria.
  Next: implement 15.2 motion primitive first, then 15.1 drag/drop.
- 2026-10-22Z — UI P1 §15.1 (chessboard drag and drop): completed the
  interrupted drag-and-drop implementation and wired it into Play. Files
  changed:
  `lib/src/ui/widgets/chessboard.dart` — converted to `StatefulWidget`; added a
  board-level `Listener` pointer router (orientation-aware position→square),
  `kTouchSlop` drag start (no long press), lifted `IgnorePointer` +
  `ExcludeSemantics` glyph overlay with drop shadow, hovered-square highlight,
  hidden source glyph, `canDragSquare` predicate, `onMoveAttempt(from, to)`
  callback with `onTapSquare(to)` click-click fallback, and Esc / right-click /
  pointer-cancel / outside-drop snap-back. The 64 per-square semantics nodes and
  tap actions are untouched; drag state is not in semantics.
  `lib/src/ui/screens/play_screen.dart` — extracted `_attemptMove(from, to)`
  (engine validation + promotion dialog + `_applyHumanMove`) shared by the tap
  and drag paths; added `_isOwnPiece` so drags only start on White pieces; wired
  `canDragSquare` + `onMoveAttempt` into the board.
  `test/ui/chessboard_drag_test.dart` (new, 15 tests) — mouse and touch drags,
  illegal/outside drops, empty-square and opponent-piece rejection, callback
  fallback, right-click and Esc cancellation, flipped orientation, 64-node
  semantics/no-reparenting through drag, PlayScreen move integration, and
  promotion dialog cancel-restores/queen-applies.
  `test/support/semantics_invariants.dart` — fixed `_isSquareLabel` regex: it
  required the word “square” after White/Black, so piece squares were not
  counted (latent helper bug surfaced by the 64-node drag test).
  `docs/FUTURE_WORK.md` — removed §15.1, updated §15 intro/acceptance/order.
  Evidence: `flutter analyze` → `No issues found! (ran in 2.2s)`;
  `flutter test test/ui/chessboard_drag_test.dart` 15/15 pass;
  `flutter test test/ui/chessboard_test.dart test/ui/play_screen_test.dart`
  51/51 pass; full `flutter test` 565/565 pass (550 baseline + 15 new).
  Commit: 77f8de0. Push **BLOCKED**: this host has no GitHub credentials
  (`git push origin main` → `could not read Username for
  'https://github.com'`; no credential helper, token, `gh`, or SSH key).
  `git ls-remote` shows remote `main` at e1749b3, so be3ab86/ee07968/77f8de0
  remain local-only. Re-run the push after credentials are provisioned.
  Next: §15.2 explicit from→to move animation layer.
- 2026-10-22Z — UI P1 §15.2 (move animation layer): finished the interrupted
  from→to motion layer and added its test suite. Files changed:
  `lib/src/ui/widgets/board_motion.dart` (new, 72 lines) — `BoardMove` value
  (from/to/flag/captured/promotion, `==`/`hashCode`/`toString`,
  `BoardMove.fromApplied` mapping an `AppliedMove` receipt).
  `lib/src/ui/widgets/chessboard.dart` — converted to `TickerProviderStateMixin`;
  added `Chessboard.motion` param + `_flight`/`_motionController` (160 ms
  ease-out) driving an `IgnorePointer` + `ExcludeSemantics` + `RepaintBoundary`
  overlay (`chessboard-motion-overlay`/`-piece`/`-rook`/`-captured` keys) above
  the 64 static cells; `didUpdateWidget` starts/retargets the flight on a
  squares change; `_startFlight` derives capture/en-passant/castle/promotion
  from the old→new snapshot diff; retarget continues from the current visual
  position (`Offset.lerp`); reduced-motion snaps (`MediaQuery.disableAnimations`);
  destination + castling-rook destination glyphs hidden beneath the flight;
  AnimatedSwitcher drops to `Duration.zero` during a flight so the snap-to-final
  never pops. Wired into Play (`_lastMotion` via `BoardMove.fromApplied` on
  every `_syncBoard` apply, `motion: viewingLive ? _lastMotion : null`), Watch
  (`_lastMotion` same pattern), Review (`BoardMove` from the bright UCI pair
  on forward scrub — backward snaps by passing null), Variant Replay (forward
  legal plies animate from `current.attempt`). Arena mini-boards and settings
  previews pass no motion (static, per §15.2). New
  `test/ui/board_motion_test.dart` (16 tests): 3 unit (fromApplied mapping,
  equality/hashCode, toString) + 13 widget — quiet slide starts at origin,
  passes mid-flight between and ends at destination with overlay teardown,
  snapshot-without-motion snaps, identical re-supply does not replay, capture
  glyph fades on destination, en passant fades beside destination (f5),
  kingside/queenside castling slide king+rook together to exact final cells,
  promotion swaps to wQ at landing, reduced-motion snaps with no overlay,
  interrupted flight retargets from the airborne position (not the origin),
  flipped orientation mirrors coordinates, 64 square semantics nodes stable
  with zero reparenting mid-flight and post-landing, overlay is
  IgnorePointer+ExcludeSemantics and taps still reach the cell beneath.
  All flight pumps deterministic (`_showMove` two-snapshot pattern +
  `_settle`); no network/engine/wall-clock. Evidence:
  `flutter analyze` → `No issues found! (ran in 2.2s)` (also fixed 3
  pre-existing issues in the interrupted work: `promotion!.name` null-check in
  BoardMove.toString, unused `toRank` local, missing `../../chess/move.dart`
  import for MoveFlag); `flutter test test/ui/board_motion_test.dart` 16/16
  pass; related suites (chessboard, chessboard_drag, play, watch, review,
  variant_replay, semantics_stability + board_motion) 174/174 pass; full
  `flutter test` 581/581 pass (565 baseline + 16 new).
  Commit: cebc5c7. Push **BLOCKED** (same as prior runs): no GitHub
  credentials on this host (`git push origin main` → `could not read
  Username for 'https://github.com'`; no credential helper, token, `gh`, or
  SSH key). `git ls-remote` shows remote `main` at e1749b3, so
  be3ab86/ee07968/77f8de0/cebc5c7 remain local-only. Re-run the push after
  credentials are provisioned.
  Next: §15.3 fast ply scrubbing.
- 2026-10-22Z — UI P1 §15.3 (fast ply scrubbing): finished the interrupted
  keyboard scrub work and shipped it on all four replay-capable screens.
  Files changed:
  `lib/src/ui/widgets/scrub_shortcuts.dart` (new) — `ScrubShortcuts` Focus
  wrapper owning Left/Right/Home/End (`ScrubAction` enum), focus follows the
  shell's `TabVisibility` (hidden IndexedStack tabs release the arrow keys) via
  a deferred post-frame sync; `scrubMotionFor(uci, delta)` helper maps one-ply
  steps to §15.2 `BoardMove`s (backward steps reverse from/to so the piece
  slides back) and returns null (snap) for multi-ply jumps (§15.3 large-jump
  budget).
  `lib/src/ui/screens/play_screen.dart` — `ScrubShortcuts(enabled: _orch !=
  null)` wraps the screen; `_onScrubAction`/`_seekViewPly`/`_scrubMotionFor`
  drive the pre-existing `_viewPly` cursor clamped to `[0, _sans.length]`;
  scrubbed snapshots read `squaresOfFen(_fens[_viewPly])`; board is read-only
  while scrubbed (`onTapSquare` null, `canDragSquare` requires `viewingLive`,
  `_attemptMove` guard); `motion: viewingLive ? _lastMotion : _viewMotion`
  animates adjacent seek steps; move-list taps route through `_seekViewPly`;
  "Return to live position" TextButton in the moves panel restores live input.
  `lib/src/ui/screens/watch_screen.dart` — same wiring plus a `_followLive`
  flag fix: the cursor now starts following the live tail (`_viewPly` is only
  meaningful once the user seeks), so the board shows live play after Start
  instead of pinning to ply 0 (regression caught by the new tests);
  `_effectiveViewPly` getter feeds the scrub math and the MoveList highlight.
  `lib/src/ui/screens/review_screen.dart` — ScrubShortcuts + `_seekPly` with
  `_scrubDelta`; direction-aware motion UCI (`_ply - 1` forward, `_ply`
  backward) on the after-board; slider and move-list/key-moment taps route
  through `_seekPly`.
  `lib/src/ui/screens/variant_replay_screen.dart` — ScrubShortcuts + `_seek`
  with `_scrubDelta`; fixed backward scrubs (the motion index when seeking
  back to a ply is `_ply`, the move leaving the viewed position — previously
  `current` was null at ply 0 so backward steps snapped).
  `lib/src/ui/widgets/chessboard.dart` — pure `dart format` brace cleanup in
  `_startFlight` (no behavior change).
  `test/ui/scrub_shortcuts_test.dart` (new, 20 tests) — `scrubMotionFor`
  unit mapping (forward/backward/multi-ply/malformed UCI), ScrubShortcuts key
  mapping/disabled/hidden-tab focus release, Play scrub (arrow steps with
  motion overlay, adjacent-step animation + retarget, read-only past plies via
  tap AND drag, Return to live restores input, 20 rapid arrows coalesce with
  zero exceptions/timers, semantics 64-nodes/zero-reparenting through rapid
  seeking), Review scrub (cursor + forward/backward after-board animation,
  multi-ply End snaps), Variant Replay scrub (clamped cursor, forward/backward
  legal animation), Watch scrub (follow-live after Start, arrows pin past
  snapshots + End returns, backward animation, move-list tap seek + Return to
  live). Deleted the temporary `test/ui/scrub_probe_test.dart` debug file
  (created during the interrupted run).
  Key test-harness fix: the scrub tests are the first to tap content inside a
  shell `TabBarView` page — the page's `DrivenScrollActivity` keeps the
  viewport pointer-ignored until its ticker future completes, and a single
  `pump(300ms)` can land exactly on the boundary (flaky hit-testing). Pages
  are now entered via a `_switchTab` helper that pumps six 100 ms slices so
  buttons always register; the Watch `_followLive` fix and the variant
  backward-motion fix were both caught by these tests.
  Evidence: `flutter analyze` → `No issues found!`; `flutter test
  test/ui/scrub_shortcuts_test.dart` 20/20 pass; related suites
  (play/watch/review/variant_replay 85/85, chessboard/drag/motion/semantics/
  shell 105/105, monkey/deep-states/stable-keys 21/21) all green; full
  `flutter test` 601/601 pass (581 baseline + 20 new). Commit:
  9721d1f. Push **BLOCKED** (same as prior runs): no GitHub credentials
  on this host — `git push origin main` → `could not read Username for
  'https://github.com'`; `git ls-remote` shows remote `main` still at
  e1749b3, so 8eaaa5e..HEAD remain local-only. Re-run the push after
  credentials are provisioned.
  Next: §15.4 premove single (or a CI/process item such as §11.3 remote-run
  workarounds).
- 2026-10-22Z — UI P1 §15.4 (premove and multipremove): implemented the
  premove queue across the play room, completing §15 (chessboard interaction
  & motion). Files changed:
  `lib/src/ui/premove.dart` (new, pure Dart) — `PremoveAttempt` (from/to/
  promotion + `uci`), `kMaxPremoves = 5`, `promotionTypeFor`,
  `isPromotionMove`, `premoveSimulation` (applies queued premoves as
  consecutive same-side moves on a clone of the current position, dropping
  everything after the first illegal/malformed premove, and always returns
  the mover to move so target dots and validation read naturally),
  `isLegalPremove` (queue-time AND execution-time legality on a forced-turn
  probe clone).
  `lib/src/ui/widgets/chessboard.dart` — `BoardPremove` value type + new
  `premoves` param rendering the §15.4 ghost layer: translucent source glyph
  at `from` + numbered destination marker (with the promotion letter, e.g.
  `1q`) at `to`, inside one `IgnorePointer` + `ExcludeSemantics` overlay so
  hit testing and the 64 square semantics nodes stay untouched; new
  `onRightClick` param fired on secondary pointer-down while no drag is in
  flight (during a drag, right-click still cancels the drag).
  `lib/src/ui/widgets/scrub_shortcuts.dart` — optional `onEscape` hook so
  Escape (already owned by the scrub focus scope) can clear the premove
  queue without touching the scrub arrow keys.
  `lib/src/ui/screens/play_screen.dart` — `_premoves`/`_premoveNotice`
  state; `_premoveWindow` (live + no result + not the human's turn) and
  `_premoveSimulation`; `_onPremoveTap` (select own piece with simulated
  legal-target dots, queue on a legal destination, tap-again deselects,
  opponent-piece taps safe); `_queuePremove` shared by the click-click and
  drag paths (validated in sequence, promotion premoves default to queen
  with a visible marker and never open a blocking dialog); `_executePremoves`
  hooked at the end of `_syncBoard` when the human turn arrives with a
  non-empty queue — plays the leading legal premove through the normal
  `_applyHumanMove` path one per human turn, so exactly one AI turn is
  requested per applied premove, and discards the first illegal premove
  together with everything queued after it plus a brief notice;
  `_removeLastPremove` (right-click), `_clearPremoves` (Escape / Clear
  premoves control), `_buildPremoveBar` (“N premoves” chip + Clear premoves
  + discard notice); queue cleared on new game, terminal state, and dispose;
  ghosts/chip only shown in the premove window and hidden while scrubbed.
  Premove is Play-only (per §15.5) — Watch/Review/Variant Replay untouched.
  New `test/ui/premove_test.dart` (30 tests): 11 unit (uci composition,
  equality/hashCode, promotionTypeFor, isPromotionMove detection, empty
  simulation leaves the board and forces the mover to move, single apply,
  legal chain in sequence, drop-after-illegal, isLegalPremove accept/reject
  + opponent-piece rejection, pinned-rook king-exposure rejection + pin-line
  slide acceptance, promotion-as-queen simulation) + 19 widget (tap-to-queue
  during the AI turn, second premove queues with numbering 1/2, illegal tap
  rejected, drag-to-queue, right-click removes last, Escape clears all,
  Clear premoves control, single premove executes after the AI reply with
  exactly 2 AI turns, multi-premove chain executes one per human turn with
  exactly 3 AI turns and drains, illegal leading premove discarded with
  notice and no extra AI turn, promotion premove shows `1q` marker with no
  “Promote to” dialog and lands a white queen on a8, deselect by re-tap,
  opponent-piece tap safe, five-move cap rejects a sixth, new game clears,
  resign clears, semantics 64 square nodes stable with ghosts excluded,
  right-click with empty queue no-op, ghosts hidden while scrubbed).
  Deterministic fakes only (`MockProvider` with a scripted legal reply per
  turn or the engine's first legal UCI, fixed UTC clock); no
  network/engine/wall-clock.
  Evidence: `flutter analyze` → `No issues found! (ran in 2.2s)`;
  `flutter test test/ui/premove_test.dart` 30/30 pass; related suites
  (play/chessboard/drag/motion/scrub/watch/review/variant_replay) green;
  full `flutter test` 631/631 pass (601 baseline + 30 new). Commit:
  26a13c1. Push **BLOCKED** (same as prior runs): no GitHub credentials
  on this host — `git push origin main` → `could not read Username for
  'https://github.com'`; `git ls-remote` shows remote `main` still at
  e1749b3, so 5faf11b..HEAD remain local-only. Re-run the push after
  credentials are provisioned.
  Next: §11.3 remote-run workaround, §3.3 runbook checklist (docs-only), or
  re-push the queued local commits once GitHub credentials exist.
- 2026-10-22Z — INFRA P0 §11.3 (CI process fixes, Linux-verifiable slice):
  Fixed the two §11.3 workflow gaps that did not require a Windows runner.
  Files changed:
  `.github/workflows/ci.yaml` — (1) §9.1 integration-test step now exits
  non-zero (step fails) when `flutter test integration_test/... -d windows`
  returns any non-zero exit code; previously the exit code was only recorded
  to GITHUB_OUTPUT and a red integration test passed silently. (2) §9.2 UIA
  smoke step: removed the job-level `Start-Process` pre-launch + its finally
  kill — the smoke script owns the app lifecycle (launches via
  `Start-Process -PassThru` at its step 3 and always kills the process in
  its own finally at step 8), so the app is launched exactly ONCE and UIA
  attachment + seeded random clicks hit a single window instance. (3) Smoke
  step now fails the job on ANY non-zero `$LASTEXITCODE` (0=pass, 1=exe/app
  failure, 2=crash) instead of only exit 2, and the Event Viewer excerpt is
  exported on any failure (not only the crash path) so the artifact always
  has debugging context. No Dart files changed.
  `docs/FUTURE_WORK.md` — §11.3 updated in place: process fixes shipped
  (fail-fast + single UIA invocation), remaining = trigger the workflow on a
  Windows runner (needs Windows desktop/UIA session; blocked on Linux);
  `Last updated:` line bumped.
  `automation-track.md` — header line + §11.3 Roadmap status row updated,
  this Run Log appended.
  Evidence: `flutter analyze` → `No issues found! (ran in 2.1s)`; full
  `flutter test` 631/631 pass (no Dart changes; regression confirmed);
  workflow YAML re-parses clean via PyYAML (jobs: ubuntu-gate +
  windows-nightly, 10 steps in windows-nightly). PowerShell blocks are
  Windows-only and could not be executed on this host (no pwsh); syntax
  reviewed manually — the blocks contain only `$LASTEXITCODE` checks,
  `Write-Host`, `Exit`, `Out-File`, and `Get-WinEvent` pipelines.
  Commit: 7618098. Push **BLOCKED** (same as prior runs): no GitHub
  credentials on this host — `git ls-remote origin main` still shows
  e1749b3; queued local commits remain un-pushed. Re-run the push after
  credentials are provisioned.
  Next: §3.3 upgrade checklist into `docs/RUNBOOK.md` (P1, docs-only,
  closes acceptance criterion 14.8), or re-push once credentials exist.
- 2026-10-22Z — DOCS P1 §3.3 (Flutter upgrade gate → runbook): added the
  "Flutter upgrade gate (release block, acceptance criterion 14.8)" section to
  `docs/RUNBOOK.md` — the full 8-step §3.3 checklist: (1) check the Flutter
  engine revision against upstream `flutter/flutter#175041`, (2) upgrade or
  pin a known-good Flutter, (3) run the full fast suite (`flutter analyze`
  → "No issues found!", `flutter test` → zero pending timers), (4) run the
  §9.1 Windows integration test (`flutter test
  integration_test/accessibility_windows_test.dart -d windows`), (5) build
  the Windows release and run the §9.2 UIA smoke with `-RandomClicks 500`,
  (6) repeat the smoke with Narrator or Inspect.exe attached, (7) check
  Event Viewer for any new `flutter_windows.dll` fault (`0xC0000005` /
  `0xC000041D`), (8) only then remove the known-issue note. The section also
  carries the known-issue note itself (Flutter Windows accessibility bridge
  crash root cause `flutter/flutter#175041`; app-level semantics hardening is
  a mitigation, not a fix) so step 8 is actionable. Release process wiring:
  `docs/ENGINE_RUNTIME.md` "Release checklist (before distributing
  binaries)" now requires the upgrade gate before cutting a release;
  `docs/FUTURE_WORK.md` §2.6 points at the runbook note. `docs/FUTURE_WORK.md`
  updated open-items-only: §3.3 removed from the open list, header bumped,
  acceptance criterion 14.8 moved from open to "Already met" (14.8: gate is
  part of the runbook and referenced by the release process).
  No Dart/test files changed. Evidence: `flutter analyze` → `No issues
  found! (ran in 2.1s)`; full `flutter test` 631/631 pass (no Dart changes;
  regression confirmed). Commit: 985ca4d. Push **BLOCKED**
  (same as prior runs): no GitHub credentials on this host — `git push
  origin main` → `could not read Username for 'https://github.com'` (no
  credential helper, token, `gh`, or SSH key); `git ls-remote origin main`
  still shows e1749b3, so 5faf11b..HEAD remain local-only. Re-run the push
  after credentials are provisioned.
  Next: re-push the queued local commits (origin/main..HEAD, now 15 commits
  including this run's 985ca4d + cedf076) once GitHub credentials exist —
  this closes the last Linux-verifiable open item; the remaining open items
  (§9.1/§9.2 Windows native runs, §11.3 first Windows CI run, §11.4 optional
  coverage wiring, §2.6 upstream fix) all need a Windows desktop/UIA session
  or an upstream Flutter release.
- 2026-10-22Z — INFRA P2 §11.4 (coverage wired into CI, Linux-verifiable
  slice): closed the last remaining Linux-implementable open item.
  `flutter test test/ui --coverage` is documented in the §11.4 spec but was
  not run in CI; it is now wired into the `ubuntu-gate` job as a NON-GATING
  step (`continue-on-error: true`) that runs the documented command, then
  uploads `coverage/lcov.info` as a `coverage-lcov` artifact
  (`if-no-files-found: warn`, 30-day retention) via
  `actions/upload-artifact@v4`. Coverage is explicitly NOT the success metric
  (§11.4: every interaction-matrix control exercised + every transition
  asserts the semantics invariants is the goal, not a line-coverage number) —
  the step only makes trend reporting possible and can never redden the gate.
  Files changed:
  `.github/workflows/ci.yaml` — two new steps in `ubuntu-gate` after `Test`:
  "Test coverage (§11.4)" (`flutter test test/ui --coverage`,
  continue-on-error: true) + "Upload coverage artifact" (if: always()).
  `docs/FUTURE_WORK.md` — §11.4 moved from the open list to DONE (section
  kept with the run evidence + rationale that coverage is not the success
  metric); `Last updated:` line bumped.
  `automation-track.md` — header line + this Run Log entry.
  No Dart/test files changed.
  Evidence: workflow YAML re-parses clean via PyYAML (jobs: ubuntu-gate +
  windows-nightly; ubuntu-gate now 8 steps; coverage step continue-on-error:
  true; upload inputs name=coverage-lcov/path=coverage/lcov.info/
  if-no-files-found=warn/retention-days=30). Local verification of the exact
  CI command on this host: `flutter test test/ui --coverage` (Flutter 3.47.6
  stable) — all test/ui suites green and `coverage/lcov.info` generated;
  `flutter analyze` → `No issues found!`; full regression `flutter test`
  631/631 pass (no Dart changes; regression confirmed). Commit: 7fb99c6.
  Push **BLOCKED** (same as prior runs): no GitHub credentials on this host
  — `git ls-remote origin main` still shows e1749b3; queued local commits
  remain un-pushed. Re-run the push after credentials are provisioned.
  Next: §11.3 trigger the first Windows CI run (needs a Windows runner with
  an interactive desktop/UIA session) or re-push the queued local commits;
  the remaining open items (§9.1/§9.2 native runs, §11.3 first Windows run,
  §2.6 upstream fix, §13 open decisions) all need a Windows desktop/UIA
  session or an upstream Flutter release.
- 2026-10-23Z — REFACTOR §13 (telemetry isolation: injectable stores replace
  process-static singletons). Decided the §13 "Telemetry isolation" open
  question **YES** — `StatsLog`, `QualityLog`, `ReviewLog`, and
  `VariantReviewLog` are now per-`ProviderScope` stores; the old
  `resetTelemetry` test hygiene is gone. Files changed:
  `lib/src/ui/backend_bridge.dart` — the four classes converted from
  `abstract class` process-static singletons (all `static` fields/methods)
  to concrete instance classes with identical APIs; added `statsLogProvider`
  / `qualityLogProvider` / `reviewLogProvider` / `variantReviewLogProvider`
  (plain `Provider`, one fresh store per `ProviderScope`); `logTurnOutcome`
  / `logGameResults` gained a `required StatsLog log` parameter;
  `PendingTurn.flush` gained `required StatsLog log`.
  `lib/src/ui/screens/{play,watch,arena,review,stats}_screen.dart` — each
  `ConsumerState` captures its stores via `ref.read(<...>Provider)` in
  `initState` (stats_screen reads both stores in `build` and feeds their
  `changes` into its existing `ListenableBuilder`); all direct static calls
  rewritten to instance calls; arena's `_GameDetailDialog` uses
  `ref.read(variantReviewLogProvider)`.
  `test/support/arena_test_harness.dart` — `resetTelemetry()` REMOVED; new
  `telemetryOverrides({stats, quality, review, variant})` helper returns
  fresh (or caller-seeded) store overrides for `ProviderScope`.
  `test/game_mirror_test.dart` — fresh `StatsLog` instance per test,
  `flush(log: ...)`, `log.records` reads; clear/tearDown dropped.
  `test/support/integration_test.dart` — telemetry group rewritten to assert
  per-instance isolation plus fresh-stores-per-`ProviderContainer` (two
  containers never share a `StatsLog`).
  `test/ui/{stats_screen,review_screen,dispose_audit,scrub_shortcuts}_test.dart`
  — seeding migrated to fresh `StatsLog()`/`QualityLog()`/`ReviewLog()`
  instances wired via `harness.telemetryOverrides(...)` merged into each
  pump's `ProviderScope` overrides.
  `integration_test/accessibility_windows_test.dart` — `_clearTelemetry`
  setUp removed (fresh scope per test isolates stores).
  Eleven more test files: removed the now-obsolete
  `setUp(...resetTelemetry)` lines / harness imports.
  Evidence: `flutter analyze` → `No issues found! (ran in 2.4s)` (10 issues
  fixed: unused harness imports + unused shown names from the migration);
  full regression `flutter test` → 631/631 pass (baseline 631, suite count
  unchanged — every telemetry test still present, now instance/scope-based).
  Commit: 2613751.
  Push **BLOCKED** (same as prior runs): no GitHub credentials on this host
  — `git ls-remote origin main` still shows e1749b3; queued local commits
  remain un-pushed. Re-run the push after credentials are provisioned.
  Next: §13 Windows-runner / safe-mode decisions, or trigger the first
  §11.3 Windows CI run (needs a Windows runner with an interactive
  desktop/UIA session); the remaining open items (§9.1/§9.2 native runs,
  §11.3 first Windows run, §2.6 upstream fix) all need a Windows desktop/UIA
  session or an upstream Flutter release.
- 2026-10-23Z — CI/PROCESS P2 §11.5 (dependency hygiene: remove dead deps):
  picked the one remaining Linux-implementable CI/process item discovered
  during this run's audits. `docs/FUTURE_WORK.md` itself contains no open
  Linux-implementable item (everything open is Windows-native §9.1/§9.2/§11.3/
  §14, external §2.6, or an un-scheduled decision §13 — logged BLOCKED), so
  the deliverable was promoted into FUTURE_WORK.md as §11.5 per repo
  precedent (§11.4 was promoted/closed the same way). Two independent
  subagent scans (lib/test markers + docs open-item audit) confirmed no other
  Linux-verifiable work was missed. A candidate "CI gap" from one scan was
  empirically DISPROVED before acting: `test/support/integration_test.dart`
  ends in `_test.dart` (base name `integration_test`), so bare `flutter test`
  already auto-discovers it — `flutter test test/support` runs it 18/18 and
  both CI jobs (ubuntu-gate + windows-nightly) run bare `flutter test`, so
  the 18 harness tests are already gated inside the 631/631 suite.
  Files changed:
  `pubspec.yaml` — removed five dead dependencies with zero references across
  lib/test/tool/integration_test: dev dep `import_lint` (no `import_lint.yaml`
  config, no `dart run import_lint` invocation, no CI integration anywhere),
  `cupertino_icons` (Flutter template leftover, no `CupertinoIcons` usage),
  `intl` (no direct imports; demoted to transitive — still required by
  `cupertino_ui`/`flutter_localizations` via the SDK chain), `collection` (no
  direct imports; demoted to transitive — still required by
  `flutter_riverpod`/Flutter SDK), `hive_ce` (only `hive_ce_flutter` is
  imported; `hive_ce` is a transitive requirement of `hive_ce_flutter` and
  stays in the lock). Verified by `dart pub deps` + `pubspec.lock` inspection:
  `collection`/`hive_ce`/`intl` now listed as `dependency: transitive`;
  `import_lint` and `cupertino_icons` fully dropped from the lock graph.
  `pubspec.lock` — re-resolved (15 packages changed: 5 direct entries removed/
  demoted, no version bumps observed for remaining direct deps).
  `docs/FUTURE_WORK.md` — §11.5 added + closed as DONE in the same run (open
  list unchanged: §11.5 not an open item), header bumped.
  `automation-track.md` — header line + this Run Log entry.
  Evidence: `flutter pub get` → "Changed 15 dependencies!"; `flutter analyze`
  → `No issues found! (ran in 4.1s)`; full regression `flutter test` →
  631/631 pass (01:40, All tests passed!) — identical to baseline, confirming
  the dependency removal is behavior-neutral; `flutter test test/support` →
  18/18 pass (harness gating re-confirmed). No code or test files changed —
  dependency-graph hygiene only.
  Push **BLOCKED** (same as prior runs): no GitHub credentials on this host —
  `git push --dry-run origin main` → `could not read Username for
  'https://github.com'`; `git ls-remote` confirms remote `main` still at
  e1749b3, so origin/main..HEAD remains local commits un-pushed
  (be3ab86..8fd1bd1 + this run). Re-run the push after credentials are
  provisioned.
  Commit: 33e2aec.
  Next: (a) re-push the queued local commits once GitHub credentials exist;
  (b) run §9.1/§9.2/§11.3 on a Windows desktop/UIA session; or (c) repeat the
  §11.5 dependency audit each time new deps are added (the one-line check:
  `grep -rE "package:(dep)/" lib test tool integration_test`).
- 2026-10-23Z — CI/PROCESS P1 §11.6 (Linux release build + Xvfb smoke on
  the ubuntu-gate): closed the remaining Linux-implementable CI gap — the
  push/PR Linux job gates only analyzer + tests, never building or starting
  the release binary, so a runner/plugin/CMake regression bypasses CI and is
  caught only on the nightly Windows runner. Promoted as §11.6 into
  `docs/FUTURE_WORK.md` per the §11.4/§11.5 precedent. A subagent audit
  confirmed no other Linux-implementable open work is missed: the only
  genuine in-code "not implemented" is the deliberate, unscheduled
  chaotic→ReviewLog wiring point (`lib/src/ui/screens/arena_screen.dart:28-30`);
  the four TODO hits are Flutter-scaffold templates outside the analyzer;
  `flutter analyze` covers Lints with no format/sorting gate beyond it.
  Files changed:
  `.github/workflows/ci.yaml` — `ubuntu-gate` gained three steps after
  `Test` (windows-nightly untouched): (1) "Install Linux desktop build
  deps" — `sudo apt-get install -y --no-install-recommends ninja-build
  pkg-config libgtk-3-dev libsecret-1-dev libjsoncpp-dev xvfb openbox`
  (ubuntu-latest preinstalls clang/cmake/ninja/pkg-config but not the
  GTK/Secret/jsoncpp dev headers; docs/RUNBOOK.md headless recipe);
  (2) "Build Linux release" — `flutter build linux --release`; (3) "Smoke
  start Linux release (Xvfb)" — `set -euo pipefail`; starts `Xvfb :77 -screen
  0 1280x1024x24` + `openbox` with `LIBGL_ALWAYS_SOFTWARE=1`, launches
  `build/linux/x64/release/bundle/llm_chess_arena` redirecting to
  `smoke.log`, requires the process to survive a 15 s window (`kill -0`),
  then a bounded SIGTERM→SIGKILL teardown escalates if the app ignores TERM.
  Engine assets are gitignored (`assets/engines/*/stockfish`) and first-run
  Stockfish extraction is lazy (`lib/main.dart`), so startup requires no
  engine download.
  `docs/FUTURE_WORK.md` — §11.6 added + closed as DONE in the same run
  (open list unchanged: §11.6 not an open item), header bumped.
  `automation-track.md` — header line + §11.6 Roadmap status row + this Run
  Log entry.
  Evidence: `flutter analyze` → `No issues found! (ran in 3.0s)`;
  `flutter build linux --release` → `✓ Built
  build/linux/x64/release/bundle/llm_chess_arena`; the exact smoke recipe
  (Xvfb :77 + openbox + release binary, 15 s `kill -0`) exits 0 locally —
  an earlier `:99` attempt used a pre-existing X server, re-run on `:77`
  verified the fresh-display path cleanly; full regression
  `flutter test` → 631/631 pass (01:37, All tests passed! — no Dart
  changes); workflow re-parses clean via PyYAML (ubuntu-gate now 11 steps
  including checkout, windows-nightly still 10 steps, unchanged); all new
  run blocks pass `bash -n`.
  Commit: 5e241b3.
  Push **BLOCKED** (same as prior runs): no GitHub credentials on this host —
  `git push origin main` → `fatal: could not read Username for
  'https://github.com'` (no credential helper, `gh`, SSH private key,
  `~/.git-credentials`, `~/.netrc`, or token in env — all audited this run);
  `git ls-remote origin main` still shows e1749b3, so `5faf11b..HEAD` remains
  local-only (un-pushed queue now 17 commits including this run's 5e241b3).
  Re-run the push after credentials are provisioned.
  Next: (a) trigger the §11.3 Windows nightly / run §9.1–9.2 on a Windows
  desktop/UIA session (only remaining functional gaps: §14.1–14.2); (b) once
  a GitHub PAT with `workflow` scope exists, `workflow_dispatch` the
  §11.6-augmented `ubuntu-gate` and confirm the Linux build+smoke steps are
  green on a hosted runner; or (c) decide the §13 Windows-runner /
  safe-mode questions.
- 2026-10-23Z — DOCS/PROCESS §2.6 (upstream dependency status check, RUNBOOK
  upgrade-gate step 1): picked the highest-priority open item with a
  Linux-verifiable slice. A subagent audit of `docs/FUTURE_WORK.md` +
  `automation-track.md` + `lib/` marker scan + CI workflow confirmed no other
  open item is implementable on this host: §9.1/§9.2 (Windows native runs),
  §11.3 (first Windows CI run), §14.1–14.2 (Windows acceptance criteria) all
  need a Windows desktop/UIA session — logged BLOCKED; §13 Windows-runner /
  safe-mode are un-scheduled decisions. No skipped/disabled/TODO tests exist;
  `lib/` has zero code markers (the only "not implemented" is the deliberate
  unscheduled chaotic→ReviewLog wiring doc comment at
  `lib/src/ui/screens/arena_screen.dart:28-30`). So the one actionable open
  item was the RUNBOOK step-1 check itself — verify whether the upstream fix
  has landed, record the verdict, and update the two track docs. Findings:
  `flutter/flutter#175041` (AccessibilityBridge::CreateRemoveReparentedNodesUpdate
  crash) remains **open** (P3, `needs repro info`; last activity 2026-10-18).
  Candidate engine fix **`flutter/flutter#190903`** (`[Windows] Avoid null
  parent dereference in AccessibilityBridge`, null-parent skip in
  `accessibility_bridge.cc`) is **open and unmerged** (`merged: false`, last
  updated 2026-10-21, CI `mergeable_state: unstable`), so **no stable engine
  contains the fix and the landing revision is unknown**. Field reports still
  reproduce the crash on 3.44.9/3.47.x stable; one independent beta test
  (2026-08-12) reported the AXTree root-mismatch did not reproduce on
  `3.48.0-0.1.pre`, but walls Windows UIA control exposure host-only
  (`FLUTTERVIEW`) in that lab — so the beta is NOT evidence of a complete fix.
  Local toolchain: Flutter 3.47.6 stable, Framework 5fc346839b (2026-09-30),
  Engine b8c8d3d8d5 / 692136cb65 (2026-09-30), Dart 3.13.5. Verdict: stay on
  the mitigation (known-issue note + `ExcludeSemantics`/`IndexedStack`
  hidden-tab guard + stable semantics roots) and keep the upgrade gate; check
  again on each Flutter upgrade, and on #190903 landing validate on Windows
  (§9.1/§9.2) before removing the note. Files changed:
  `docs/FUTURE_WORK.md` (§2.6 status check paragraph + header bump) and
  `automation-track.md` (header + this Run Log entry). No code/test files
  changed. Evidence: `flutter analyze` → `No issues found! (ran in 2.1s)`;
  full regression `flutter test` → 631/631 pass (01:38, All tests passed! —
  unchanged, no Dart changes); upstream facts verified via GitHub API
  (`api.github.com/repos/flutter/flutter/pulls/190903` → `state:"open"`,
  `merged:false`) + issue page fetch. Commit: `983db9f`.
  Push **BLOCKED** (same as all prior runs): no GitHub credentials on this
  host — `git push origin main` → `fatal: could not read Username for
  'https://github.com': No such device or address` (no credential helper,
  `gh`, SSH key, `~/.git-credentials`, `~/.netrc`, nor token in env);
  `git ls-remote origin main` still shows `e1749b3`, so the un-pushed local
  queue (now 18 commits through this run, incl. `983db9f`) remains
  local-only. Re-run the push after credentials are provisioned.
  Next: (a) re-push the queued local commits once GitHub credentials exist
  (e.g. a PAT with `workflow` scope added to the remote); (b) trigger the
  §11.3 Windows nightly / run §9.1–9.2 on a Windows desktop/UIA session
  (closes §14.1–14.2); or (c) decide the §13 Windows-runner / safe-mode
  questions. §2.6 re-check is due on the next Flutter upgrade and whenever
  `flutter/flutter#190903` lands.
- 2026-10-23Z — UI P1 (arena chaotic→`VariantReviewLog` recording path:
  stale doc fix + 4 new tests). Three independent subagent audits
  (lib/test markers, CI+docs open items, chaotic-review feasibility)
  confirmed the one remaining Linux-implementable code deliverable: the
  "**Wiring point**: chaotic games are *not* recorded in [ReviewLog]" doc
  comment at `lib/src/ui/screens/arena_screen.dart:28-30` is **stale** —
  chaotic games have been recorded losslessly into `VariantReviewLog` since
  commit 61d58d7 (write site at `arena_screen.dart:1552-1566`,
  `_concludeGame`), yet the class doc still described the original plan and
  **no test covered the path**. Files changed:
  `lib/src/ui/screens/arena_screen.dart` — class doc rewritten: finished
  chaotic games are recorded as `VariantGameRecord`s (initial board +
  per-ply attempt/interpretation trail + outcome) into `VariantReviewLog`,
  replayable from the review screen's "Chaotic replays" card; the
  FEN-shaped `ReviewLog` is standard-only by design.
  `test/ui/arena_variant_review_test.dart` (new, 4 widget tests) —
  (1) chaotic tournament (2 demo agents, 1 pairing × 2 games/pairing ×
  1 round, color alternation, concurrency 2, `initialSeed: 42`) records
  exactly 2 `VariantGameRecord`s: mode 'chaotic', the two demo
  labels/agent-ids per game with white≠black, non-empty
  id/tournamentId/seed/initialBoard, outcome ∈ {1-0,0-1,1/2-1/2,*},
  non-empty reason, monotonic startedAt→finishedAt, sequential ply
  indices, ≥4-char attempt UCIs, `validateChain()` empty; `ReviewLog`
  stays empty (isolation). (2) cancelled chaotic run still records both
  games with outcome '*' / reason 'cancelled' + valid chain (partial
  trails surface too). (3) standard tournament records 2 `ReviewGame`s
  with mode 'standard' into `ReviewLog` and leaves `VariantReviewLog`
  empty (isolation both ways). (4) E2E: `ReviewScreen` pumped against the
  same log instance lists the arena game under "Chaotic replays" and
  tapping opens `VariantReplayScreen` with the game labels. Deterministic
  fakes only (MockProvider plays first legal attempt, fixed UTC clock,
  per-scope telemetry stores), never network/engine/wall-clock;
  `harness.disposeApp` drains timers.
  Evidence: `flutter analyze` → `No issues found! (ran in 2.2s)`;
  `flutter test test/ui/arena_variant_review_test.dart` → 4/4 pass
  (All tests passed!); related suites `test/ui/arena_screen_test.dart
  test/ui/review_screen_test.dart test/ui/variant_replay_test.dart
  test/ui/scrub_shortcuts_test.dart` → 86/86 pass (27+17+22+20); full
  regression `flutter test` → 635/635 pass (01:57, All tests passed! —
  631 baseline + 4 new). Commit: `23e5b5f`.
  Push **BLOCKED** (same as all prior runs): no GitHub credentials on
  this host — `git push origin main` → `fatal: could not read Username
  for 'https://github.com'` (no credential helper, `gh`, SSH key,
  `~/.git-credentials`, `~/.netrc`, nor token in env; fully audited
  again this run); `git ls-remote origin main` still shows `e1749b3`, so
  `5faf11b..HEAD` remains local-only (un-pushed queue now 19 commits
  through this run). Re-run the push after credentials are provisioned.
  Next: (a) re-push the queued local commits once GitHub credentials
  exist; (b) trigger the §11.3 Windows nightly / run §9.1–9.2 on a
  Windows desktop/UIA session (closes §14.1–14.2); or (c) decide the
  §13 Windows-runner / safe-mode questions.
- 2026-10-23Z — CI/PROCESS P2 §11.7 (real-engine E2E smoke in CI).
  A fresh subagent audit found two genuine Linux-implementable
  candidates: (A) repo-wide `dart format` reformat + format gate —
  REJECTED as the deliverable: 102/127 files would churn (unfocused
  diff) and the gate would be fragile while `flutter-version: "3.x"`
  is unpinned (formatter output changes across SDKs, exactly the drift
  that caused the current 102-file delta); (B) the repo's ONLY
  real-engine test silently skipping in CI — no download step anywhere
  provisions the gitignored Stockfish binary, so
  `test/e2e_smoke_test.dart`'s "embedded stockfish evaluates and stays
  honest" ran zero times on every push while `flutter test` stayed
  green. Promoted as §11.7 into `docs/FUTURE_WORK.md` per the
  §11.4/§11.5/§11.6 precedent.
  Files changed:
  `.github/workflows/ci.yaml` — `ubuntu-gate` gained two steps after
  `Analyze` and before `Test` (windows-nightly untouched):
  (1) "Restore Stockfish engine cache (§11.7)" — `actions/cache@v4` on
  `assets/engines/linux-x86-64` (the 103 MiB binary; only the first
  runner downloads). Stale caches self-heal: `download_stockfish.dart`
  re-verifies size + SHA-256 + `file` type + UCI handshake and
  re-fetches on any mismatch, so a fixed cache key can never smuggle a
  corrupt binary past the gate. (2) "Download Stockfish engine
  (real-engine E2E, §11.7)" — `dart run
  tool/download_stockfish.dart linux-x86-64` (official GitHub URL
  first, `gh.llkk.cc` proxy fallback; strict host verifies end with a
  `uciok` handshake; exit 1 on failure so a broken fetch cannot
  silently skip the E2E test).
  `docs/FUTURE_WORK.md` — §11.7 added + closed as DONE in the same run
  (open list unchanged: §11.7 not an open item), header bumped.
  `automation-track.md` — header line + this Run Log entry.
  The engine test itself was not touched — it still self-gates on
  `assets/engines/linux-x86-64/stockfish` and skips gracefully on
  machines without the binary.
  Evidence: `flutter analyze` → `No issues found! (ran in 2.3s)`;
  the exact CI download command `dart run
  tool/download_stockfish.dart linux-x86-64` → exit 0 with
  `linux-x86-64 OK present` (size 103153472 ok, sha256 ok, file ok,
  UCI handshake `uciok`); `flutter test test/e2e_smoke_test.dart` →
  5/5 pass with the engine test EXECUTING (`-- stockfish: 30 cp, best
  c7c5`) rather than skipping; full regression `flutter test` →
  635/635 pass (01:52, All tests passed! — no Dart changes);
  workflow re-parses clean via PyYAML (ubuntu-gate now 13 steps
  including checkout, windows-nightly still 10 steps, unchanged); `git
  status --short` confirms the engine binary stays untracked
  (gitignored, `.gitignore:62`).
  Commit: `9b402ec`.
  Push **BLOCKED** (same as all prior runs): no GitHub credentials on
  this host — `git push origin main` → `fatal: could not read
  Username for 'https://github.com'` (no credential helper, `gh`, SSH
  key, `~/.git-credentials`, `~/.netrc`, nor token in env);
  `git ls-remote origin main` still shows `e1749b3`, so `5faf11b..HEAD`
  remains local-only (un-pushed queue now 20 commits through this
  run). Re-run the push after credentials are provisioned.
  Next: (a) re-push the queued local commits once GitHub credentials
  exist; (b) trigger the §11.3 Windows nightly / run §9.1–9.2 on a
  Windows desktop/UIA session (closes §14.1–14.2); or (c) decide the
  §13 Windows-runner / safe-mode questions. The `dart format` gate
  (candidate A) remains a documented option if the repo ever adopts a
  pinned Flutter version.
- 2026-10-23Z — CI/PROCESS P1 §11.8 (CI Flutter SDK pinning — the
  prerequisite the §11.7 run identified). Subagent audit of the workflow
  confirmed the one Linux-implementable open gap: **both** CI jobs used a
  **floating** `flutter-version: "3.x"` / `channel: stable` selector
  (`subosito/flutter-action@v2`), so every run could resolve a different
  Flutter SDK — analyze results, lint defaults, test behavior, and
  effective flag semantics drifted between pushes and diverged from the
  local dev toolchain (known-good 3.47.6 / Dart 3.13.5). The repo was
  asserting "Flutter 3.47.6 known-good" in every baseline while CI never
  pinned it, and the deferred `dart format` gate (§11.7 run log) was
  blocked precisely on this unpinned fragility — running the audit first
  confirmed no other code/test marker exists (lib/, test/, tool/,
  integration_test/ are free of TODO/FIXME/skip/@Skip/disabled lints; the
  only `skip:` is the intentional §11.7 engine self-gate).
  Files changed:
  `.github/workflows/ci.yaml` — `ubuntu-gate` Setup Flutter (was l.20-24)
  and `windows-nightly` Setup Flutter (was l.134-138): `flutter-version:
  "3.x"` → `"3.47.6"` (channel stays `stable`), each with a comment that
  RUNBOOK.md "Flutter upgrade gate" step 2 is the only sanctioned way to
  bump it (re-validate §9.1/§9.2 first) and that the floating selector
  drifted SDKs per run. Nothing else in the workflow touched.
  `docs/FUTURE_WORK.md` — §11.8 added + closed as DONE in the same run
  (open list unchanged: §11.8 not an open item), header bumped.
  `automation-track.md` — header line + this Run Log entry.
  No Dart/test files changed.
  Evidence: `flutter analyze` → `No issues found! (ran in 2.2s)`; full
  regression `flutter test` → 635/635 pass (01:44, All tests passed! — no
  Dart changes, unchanged from the §11.7 baseline); workflow re-parses
  clean via PyYAML — both jobs still 13 / 10 steps (step counts unchanged,
  only the Setup Flutter `with:` blocks changed) and both resolve
  `flutter-version: 3.47.6` on `stable`; local `flutter --version` matches
  the pin exactly (3.47.6 stable, Dart 3.13.5); no residual bare
  `flutter-version: "3.x"` in the file (remaining "3.x" strings are the
  new explanatory comments); `git status --short` clean except the two
  track docs + the workflow.
  Commit: `9b00992` (§11.8 pin).
  Push **BLOCKED** (same as all prior runs): no GitHub credentials on this
  host — `git push origin main` → `fatal: could not read Username for
  'https://github.com'` (no credential helper, `gh`, SSH key,
  `~/.git-credentials`, `~/.netrc`, nor token in env); `git ls-remote
  origin main` still shows `e1749b3`, so the un-pushed local queue (now 21
  commits through this run) remains local-only. Re-run the push after
  credentials are provisioned.
  Next: (a) re-push the queued local commits once GitHub credentials
  exist; (b) trigger the §11.3 Windows nightly / run §9.1–9.2 on a
  Windows desktop/UIA session (closes §14.1–14.2); or (c) decide the
  §13 Windows-runner / safe-mode questions. Once a future SDK bump lands,
  the §11.7-run `dart format` gate candidate becomes non-fragile again —
  but only if it can be shipped without the 102-file churn it would
  currently cause (needs an explicit owner decision, not a silent reformat).
- 2026-10-23Z — TEST HYGIENE P1 §11.9 (no real network in the test suite):
  the highest-priority Linux-implementable item found by this run's audit.
  A scoped subagent audit (test markers) surfaced a genuine rule violation
  that previous marker audits missed: `test/connection_tester_seam_test.dart`
  — which declares at line 4 "Widget tests must never open an HTTP socket or
  ping a real LLM endpoint" — invoked the **default** `connectionTesterProvider`
  in three places (lines 34–38, 179–181, 199–200). The default wraps
  `testAgentConnection` (`lib/src/ui/backend_bridge.dart:276-281` →
  `testAgentConnection` → `createProvider(...).testConnection()`), a real
  HTTP ping against the agent's live endpoint; the third one additionally
  asserted real wall-clock `< 30 s` via `Stopwatch` — the flakiest (and only
  network-dependent) assertion in the suite. Since §11.8 pinned CI to 3.47.6
  and both jobs run bare `flutter test`, this opened a real socket on every
  push/PR. Files changed: `test/connection_tester_seam_test.dart` only —
  test 1 ("defaults to a Function") now asserts the default resolves to a
  pure `ConnectionTester` shape without invoking it (resolution opens no
  socket); test 6 ("default remains distinct per container") likewise drops
  the invocation, keeping the per-container shape assertions; test 8
  ("default tester produces false on real-network unreachable") is replaced
  by "default tester resolves without opening a socket (network behaviour is
  the production seam)" which overrides the provider deterministically and
  asserts a resolved ConnectionTester + fixed-false result through the
  widget/pump path — same 8-test count, all deterministic, no network, no
  wall clock. Screens that consume the seam (`agent_setup_screen.dart`) and
  all other suites already used overrides only (grep-verified: zero
  non-override invocations of the default remain in test/). The live default
  network path stays covered by the AgentSetupScreen "Test Connection"
  button exercised interactively, not by `flutter test`.
  Docs: `docs/FUTURE_WORK.md` — §11.9 added + closed as DONE in the same
  run (open list unchanged), header bumped; `automation-track.md` — header
  line + §11.9 Roadmap status row + this Run Log entry.
  Evidence: `flutter analyze` → `No issues found! (ran in 2.2s)`; `flutter
  test test/connection_tester_seam_test.dart` → 8/8 pass (instant, no socket
  opened); related `flutter test test/ui/agent_setup_test.dart` → 29/29
  pass; full regression `flutter test` → 635/635 pass (01:56, All tests
  passed! — count unchanged, no network hit; test file edit is behavioral
  only for the three rewritten tests). `git status --short` confirms only
  this test file + the two track docs changed.
  Commit: `403dc2e`.
  Push **BLOCKED** (same as all prior runs): no GitHub credentials on this
  host — audited again this run (no credential helper, `gh`, SSH key,
  `~/.git-credentials`, `~/.netrc`, token in env; `git config
  --get credential.helper` empty); `git ls-remote origin main` still shows
  `e1749b3`, so `e1749b3..HEAD` (now 33 local commits incl. this run)
  remains local-only. Re-run the push after credentials are provisioned.
  Next: (a) re-push the queued local commits once GitHub credentials exist;
  (b) trigger the §11.3 Windows nightly / run §9.1–9.2 on a Windows
  desktop/UIA session (closes §14.1–14.2); or (c) the documented `dart
  format` gate needs an explicit owner decision because it would churn 102/127
  files (re-measured this run on the pinned 3.47.6: lib 51/72, test 50/51,
  integration_test 1/1 changed) — plus a small follow-up found by this run's
  support-layer audit: the semantics-dump fallback in
  `test/support/semantics_invariants.dart:207-215` is dead code (the second
  `takeException()` can never fire because the `expect` drains it) and P2
  cp. `test/ui` coverage artifacts, both left for future runs.
- 2026-10-23Z — TEST HYGIENE P2 §11.10 (dead code in the semantics-dump
  failure helper): the deliverable this run is the audit-flagged follow-up
  from §11.9 — `expectNoExceptionWithSemanticsDump` in
  `test/support/semantics_invariants.dart:203-215` never did what its doc
  promised. The old body was
  `expect(tester.takeException(), isNull, reason: '…');` followed by
  `if (tester.takeException() != null) { dump the tree }` — but the first
  `expect` **drains** the pending exception and **throws synchronously** when
  it is non-null, so the second `takeException()` could never return non-null:
  on a real failure the test died at the `expect` with no tree dump, and on a
  clean pass the fallback branch (and `_dumpTree`, `semantics_invariants.dart:
  217-227`) was unreachable dead code. Files changed:
  `test/support/semantics_invariants.dart` — rewritten to drain the exception
  once into a local: `final exception = tester.takeException();` then, when
  non-null, print the semantics-tree dump via `debugPrint(_dumpTree(...))` and
  fail with `fail('exception during $context: $exception')`; doc comment
  rewritten to state the true dump-then-fail order. Behaviour on the clean
  path is byte-identical (drain → null → return), which is why the 22 existing
  call sites in `test/ui/semantics_stability_test.dart` (17) and
  `test/ui/monkey_tap_test.dart` (6) needed no changes.
  `test/support/integration_test.dart` — 2 new tests in the `harness helpers`
  group (18 → 20): (1) clean-pass via `returnsNormally` + `takeException()`
  isNull; (2) forced-failure — a `GestureDetector` onTap that throws
  `StateError('forced kboom')` (deterministically recorded by the test
  framework, never rethrown), re-armed after an initial drain probe, then
  asserted: the helper throws back a failure whose text contains both the
  context (`forced context`) and the exception (`forced kboom`), it drains the
  pending exception (`takeException()` isNull afterwards), and the semantics
  dump actually printed (observed `[4] label="tap-me"` in the test output,
  proving the previously-dead `_dumpTree` path is live). Deterministic fakes
  only — no network/engine/wall-clock; the `SemanticsHandle` is disposed in
  `finally`.
  Docs: `docs/FUTURE_WORK.md` — §11.10 added + closed as DONE in the same run
  (open list unchanged — §11.10 not an open item), header bumped;
  `automation-track.md` — header line + §11.10 Roadmap status row + this Run
  Log entry.
  Evidence: `flutter analyze` → `No issues found! (ran in 2.4s)`; `flutter
  test test/support/integration_test.dart` → 20/20 pass (18 old + 2 new);
  caller suites `flutter test test/ui/semantics_stability_test.dart
  test/ui/monkey_tap_test.dart` → 37/37 pass (32 + 5, behavior unchanged);
  full regression `flutter test` → 637/637 pass (01:53, All tests passed! —
  635 baseline + 2 new). `git status --short` confirms only the two support
  files + the two track docs changed.
  Commit: `143cb1e`.
  Push **BLOCKED** (same as all prior runs): no GitHub credentials on this
  host — audited again this run (`git config --get credential.helper` empty,
  no `gh`, no SSH key, no `~/.git-credentials`, no `~/.netrc`, no token in
  env; `git push --dry-run origin main` → `could not read Username for
  'https://github.com'`); `git ls-remote origin main` still shows `e1749b3`,
  so `e1749b3..HEAD` (now 35 local commits incl. this run) remains local-only.
  Re-run the push after credentials are provisioned.
  Next: (a) re-push the queued local commits once GitHub credentials exist;
  (b) trigger the §11.3 Windows nightly / run §9.1–9.2 on a Windows
  desktop/UIA session (closes §14.1–14.2); or (c) decide the §13
  Windows-runner / safe-mode questions. The `dart` format gate still needs an
  explicit owner decision (102/127-file churn on the pinned 3.47.6); the P2
  `test/ui` coverage-artifact comparison (cp.) remains a process follow-up
  that needs ≥2 CI runs to compare.

- 2026-10-23Z — CI/PROCESS P1 §11.11 (never-executed §9.1 integration suite
  fixed + gated on Linux CI). Two independent subagent audits (FUTURE_WORK.md
  open-item audit + CI/process gap audit) both concluded the only remaining
  Linux-implementable gap was the 36-commit un-pushed queue (credential-
  blocked) and the deferred `dart format` gate (owner decision), and both
  missed a genuine dead-on-arrival suite: `integration_test/accessibility_windows_test.dart`
  (12 widget-level tests per §9.1) had NEVER executed anywhere. Bare
  `flutter test` does not discover `integration_test/`, and the windows-
  nightly job has not run — so the 12 tests compiled but ran zero times on
  every push/PR. The first-ever headless run (`flutter test
  integration_test/accessibility_windows_test.dart -d linux` under Xvfb :77)
  failed 8/12. Root causes, all platform-independent test bugs:
  (1) `_destinationLabel(4)` was `'Statistics'` but the shell's rail/More-
  sheet label is `'Stats'` — tests 2 and 6 silently no-oped on Stats via the
  `if (destFinder.evaluate().isNotEmpty)` guard, so "all 8 destinations"
  never actually visited Stats; (2) `find.text('Settings')` (and
  'Agents'/'Review') was ambiguous — the Home tab behind the modal bottom
  sheet renders same-text cards, so the More-sheet test threw "Found 2
  widgets" and the Settings-navigate test tapped the wrong node; sheet items
  are now found via `find.descendant(of: find.byType(BottomSheet).first, ...)`;
  (3) `find.bySemanticsLabel(...)` returned 0 widgets everywhere — the live
  integration binding does not build the semantics tree unless a client (or
  `tester.ensureSemantics()`) requests it; `_pumpApp` now enables semantics
  and returns the `SemanticsHandle`, disposed in `try/finally` per test
  (`addTearDown` runs AFTER flutter_test's `_verifySemanticsHandlesWereDisposed`
  and therefore leaks — the first fix attempt failed all 12 that way);
  (4) anchor texts were wrong ("AI" vs the real "AI Opponent" PlayerCard
  label, "Statistics" (doesn't exist) vs "No stats yet", missing
  "No standard games recorded yet" / "Appearance" for Review/Settings). New
  `_tapDestination` helper prefers tapping the real semantics node (Windows
  + attached UIA) and falls back to `find.text(label).first` — the repo's
  widget-suite convention — because the live binding attaches no per-render-
  object `debugSemantics` (labels live on merged ancestors); deterministic
  on both platforms. Files changed:
  `integration_test/accessibility_windows_test.dart` — all 12 tests fixed as
  above (no lib/ or test/ changes).
  `.github/workflows/ci.yaml` — new hard-gating ubuntu-gate step "Integration
  test on Linux (§11.11)" after the Xvfb smoke: starts its own Xvfb :79,
  runs `flutter test integration_test/accessibility_windows_test.dart -d
  linux`, always kills the Xvfb, fails the job on any non-zero exit.
  `docs/FUTURE_WORK.md` — §11.11 added + closed as DONE in the same run
  (open list unchanged: §11.11 not an open item), header bumped.
  `automation-track.md` — header line + §11.11 Roadmap status row + this Run
  Log entry.
  Evidence: `flutter analyze` → `No issues found! (ran in 2.3s)`; `flutter
  test integration_test/accessibility_windows_test.dart -d linux` → 12/12
  pass (00:34, All tests passed! — first-ever green run; was 4/12 at the
  first probe, 0/12 after the addTearDown fix attempt); full regression
  `flutter test` → 637/637 pass (01:48, All tests passed! — no lib/ or test/
  changes, integration_test/ is not discovered by bare `flutter test`);
  workflow re-parses clean via PyYAML (ubuntu-gate now 14 steps including
  checkout; windows-nightly still 10, untouched); new run block passes
  `bash -n`.
  Commit: 4d414e8.
  Push **BLOCKED** (same as all prior runs): no GitHub credentials on this
  host — audited again this run (`git config --get credential.helper` empty,
  no `gh`, no SSH key, no `~/.git-credentials`, no `~/.netrc`, no token in
  env; `git push --dry-run origin main` → `could not read Username for
  'https://github.com'`); `git ls-remote origin main` still shows `e1749b3`,
  so `e1749b3..HEAD` (now 36 local commits incl. this run) remains local-only.
  Re-run the push after credentials are provisioned.
  Next: (a) re-push the queued local commits once GitHub credentials exist;
  (b) trigger the §11.3 Windows nightly / run §9.1–9.2 on a Windows
  desktop/UIA session (closes §14.1–14.2; the §9.1 suite now also runs
  headless on Linux every push, so the Windows run is the only remaining
  native gap); or (c) decide the §13 Windows-runner / safe-mode questions.
  The `dart format` gate still needs an explicit owner decision
  (102/127-file churn on the pinned 3.47.6); the P2 `test/ui`
  coverage-artifact comparison (cp.) remains a process follow-up that needs
  ≥2 CI runs to compare.
- 2026-10-23Z — CI/PROCESS P1 §11.12 (Xvfb teardown dead-on-failure in the
  §11.11 step + dead GITHUB_OUTPUT writes). Three parallel subagent audits
  (code markers, CI workflow + docs, dependency hygiene) + an upstream check
  found no open FUTURE_WORK.md item that is Linux-implementable (§9.1/§9.2/
  §11.3/§14 Windows-native BLOCKED, §2.6 external — re-verified this run:
  #175041 still open, #190903 still unmerged, and even the newer stable
  3.47.7 does NOT contain the fix —, §13 un-scheduled), but surfaced one
  genuine Linux-modifiable CI defect not previously logged: the §11.11
  integration-test step ran under `set -euo pipefail` and captured
  `EXIT=$?` AFTER the failing `flutter test` line, so on a red run the shell
  aborted at the test line and the `kill -9 "$XVFB_PID"` teardown (plus the
  `exit`) was unreachable dead code — the :79 display server leaked on the
  runner exactly on the failure path where cleanup matters most. Promoted as
  §11.12 into `docs/FUTURE_WORK.md` per the §11.4–§11.11 precedent and closed
  in the same run.
  Files changed:
  `.github/workflows/ci.yaml` — (1) §11.11 step teardown fixed:
  `flutter test integration_test/accessibility_windows_test.dart -d linux || EXIT=$?`
  followed by `kill -9 "$XVFB_PID" 2>/dev/null || true` and
  `exit ${EXIT:-0}` — the job still fails on any non-zero test exit (hard
  gate unchanged), the teardown now runs on BOTH paths; (2) removed two dead
  `echo "exit_code=$($LASTEXITCODE)" >> $env:GITHUB_OUTPUT` writes in
  windows-nightly (grep proves no step consumes
  `steps.integration-test.outputs.exit_code` /
  `steps.uia-smoke.outputs.exit_code` — the gating is the explicit
  `Exit $LASTEXITCODE` in each step) and the now-unused step `id:
  integration-test` / `id: uia-smoke`; (3) added the missing
  `set -euo pipefail` to the "Install Linux desktop build deps" step so
  every ubuntu-gate run block is consistent (GHA's default shell is already
  `bash -e -o pipefail`, so this is belt-and-braces + `-u`).
  `docs/FUTURE_WORK.md` — §11.12 added + closed as DONE in the same run
  (open list unchanged: §11.12 not an open item), header bumped.
  `automation-track.md` — header line + §11.12 Roadmap status row + this Run
  Log entry.
  No Dart/test files changed.
  Evidence: `flutter analyze` → `No issues found! (ran in 2.1s)`; full
  regression `flutter test` → 637/637 pass (01:52, All tests passed! — no
  Dart changes); workflow re-parses clean via PyYAML (ubuntu-gate 14 steps,
  windows-nightly 10 steps — step counts unchanged); all 9 ubuntu-gate bash
  run-blocks pass `bash -n` (the two `bash -n` "failures" are the
  windows-nightly PowerShell blocks, Windows-only by design); the teardown
  fix is proven empirically on this host: (a) a replication of the PRE-fix
  block with a failing command leaves the :79 Xvfb alive — PID 871423
  observed surviving (`set -e` died at the failing line, cleanup dead);
  (b) the POST-fix block on the failure path propagates the exact exit code
  (3) and kills :79; (c) on the success path it exits 0 and kills :79;
  (d) the REAL `flutter test integration_test/accessibility_windows_test.dart
  -d linux` under Xvfb :79 → 12/12 pass (00:34, All tests passed!) with the
  step exiting 0 and NO :79 process left behind. (Note: two Xvfb servers
  (:77, :99) from earlier hourly smoke runs were found still alive on this
  host — the same leak class this fix removes from CI; they predate this run
  and were left untouched.)
  Commit: 658bdae.
  Push **BLOCKED** (same as all prior runs): no GitHub credentials on this
  host — `git push origin main` → `fatal: could not read Username for
  'https://github.com': No such device or address` (exit 128; no credential
  helper, `gh`, SSH key, `~/.git-credentials`, `~/.netrc`, nor token in
  env — `git config --get credential.helper` empty); `git ls-remote origin
  main` still shows `e1749b3`, so `e1749b3..HEAD` (now 38 local commits
  incl. this run's 658bdae + the hash-record commit f8035ee) remains
  local-only. Re-run the push after credentials are provisioned.
  Next: (a) re-push the queued local commits (origin/main..HEAD, still 36
  commits at e1749b3) once GitHub credentials exist; (b) trigger the §11.3
  Windows nightly / run §9.1–9.2 on a Windows desktop/UIA session (closes
  §14.1–14.2); or (c) decide the §13 Windows-runner / safe-mode questions.
  Re-audited and confirmed No other Linux-implementable candidate: code has
  zero TODO/FIXME/NotImplemented markers, no test-discovery gaps, dependency
  hygiene clean (0 unused deps), all 9 bash blocks pass `bash -n`; the
  `dart format` gate still needs an explicit owner decision (102/127-file
  churn) and the coverage-artifact comparison needs ≥2 CI runs.
- 2026-10-23Z — LINT HYGIENE P2 §11.13 (zero `// ignore` suppressions in the
  repo). All prior runs reported `flutter analyze` → `No issues found!` — but
  a fresh suppression audit (the one thing `flutter analyze` cannot report)
  found the repo was masking lints: twelve `// ignore_for_file` lines across
  test/, support/, and integration_test/. The repo's own §6.5 lint-cleanup
  had fixed `dangling_library_doc_comments` in watch_screen_test.dart the
  proper way (a `library;` directive after the library doc comment), yet
  eleven files still suppressed that same lint via `// ignore_for_file` —
  directly against the protocol's "never hide issues with `// ignore`, fix
  them properly". The integration test's `// ignore_for_file:
  dangling_library_doc_comments, camel_case_types` even suppressed a **dead**
  lint (probe-verified: removing it fires only the doc lint; no camel-case
  type exists in the file). The e2e smoke suppressed `avoid_print` for five
  intentional per-section status prints. Files changed (all test/header-only,
  no lib/ or workflow changes):
  `test/support/arena_test_harness.dart` (line 29), `test/support/
  semantics_invariants.dart` (line 37), `test/connection_tester_seam_test.dart`
  (line 8), `test/clock_seam_test.dart` (line 8), `test/ui/arena_screen_test.dart`
  (line 6), `test/ui/arena_variant_review_test.dart` (line 14), `test/ui/
  deterministic_deep_states_test.dart` (line 7), `test/ui/elo_injection_test.dart`
  (line 6), `test/ui/semantics_stability_test.dart` (line 21), `test/ui/
  stable_keys_test.dart` (line 8), `integration_test/accessibility_windows_test.dart`
  (line 15) — the suppression line is replaced by the repo-standard `library;`
  directive at the end of each library doc comment; `test/e2e_smoke_test.dart`
  — the five `print(...)` calls (lines 205/270/349/375/410) become
  `debugPrint(...)` (new `import 'package:flutter/foundation.dart'
  show debugPrint;`), and the `// ignore_for_file: avoid_print` header line is
  removed. `grep -rn "ignore_for_file" lib test integration_test tool` now
  returns **nothing** — the analyzer is clean without a single suppression, so
  a future run can never silently mask a lint (the protocol's whole point).
  Docs: `docs/FUTURE_WORK.md` — §11.13 added + closed as DONE in the same run
  (open list unchanged: §11.13 not an open item), header bumped;
  `automation-track.md` — header line + this Run Log entry.
  Evidence: `flutter analyze` → `No issues found! (ran in 2.6s)` with zero
  suppressions; touched suites `flutter test test/support/integration_test.dart
  test/e2e_smoke_test.dart test/connection_tester_seam_test.dart
  test/clock_seam_test.dart test/ui/elo_injection_test.dart test/ui/stable_keys_test.dart
  test/ui/semantics_stability_test.dart test/ui/arena_screen_test.dart
  test/ui/arena_variant_review_test.dart test/ui/deterministic_deep_states_test.dart`
  → 126/126 pass (00:36, All tests passed!); headless §9.1/§11.11 run
  `flutter test integration_test/accessibility_windows_test.dart -d linux`
  under Xvfb :79 → 12/12 pass (00:34, All tests passed!); full regression
  `flutter test` → 637/637 pass (01:58, All tests passed! — count unchanged,
  no lib/ changes, e2e smoke still prints the same status lines via
  debugPrint). `git status --short` confirms only the 12 test/support/
  integration_test files + the two track docs changed.
  Commit: 32071db.
  Push **BLOCKED** (same as all prior runs): no GitHub credentials on this
  host — re-audited this run via a subagent (`git config --get
  credential.helper` empty, no `gh`, no SSH key, no `~/.git-credentials`, no
  `~/.netrc`, no token in env; `git push --dry-run origin main` → `fatal:
  could not read Username for 'https://github.com': terminal prompts
  disabled`, exit 128); `git ls-remote origin main` still shows `e1749b3`, so
  `e1749b3..HEAD` (42 local commits incl. this run) remains local-only.
  Re-run the push after credentials are provisioned.
  Next: (a) re-push the queued local commits once GitHub credentials exist;
  (b) trigger the §11.3 Windows nightly / run §9.1–9.2 on a Windows
  desktop/UIA session (closes §14.1–14.2); or (c) decide the §13
  Windows-runner / safe-mode questions. Re-audited this run: FUTURE_WORK.md
  open items are all Windows-native (§9.1/§9.2/§11.3/§14), external (§2.6),
  or un-scheduled decisions (§13) — no other Linux-implementable item exists;
  the `dart format` gate still needs an explicit owner decision (102/127-file
  churn) and the coverage-artifact comparison needs ≥2 CI runs.
- 2026-10-23Z — CI P1 §11.14 (Xvfb startup readiness gate on both ubuntu-gate
  display steps). A fresh subagent CI-workflow audit surfaced a genuine
  Linux-implementable gap the previous runs' audits had missed (they checked
  `bash -n`, PyYAML parse, dead GITHUB_OUTPUT writes, and code markers — but
  not the Xvfb launch semantics): both ubuntu-gate steps launched a
  backgrounded `Xvfb :77 &` / `Xvfb :79 &` with NO readiness assertion. A
  dead-on-arrival Xvfb (display already occupied by a leaked server, lock
  conflict, init failure) is invisible to `set -e` — the step would fail
  LATER with a confusing `cannot open display`, or worse silently attach the
  smoke/suite to the STALE leaked server still answering on that display.
  The hazard is not hypothetical: three leaked Xvfb servers (:77/:79/:99 from
  earlier smoke/integration runs) were verified alive on this dev host right
  now (PIDs 840302/894251/499461, untouched). Files changed:
  `.github/workflows/ci.yaml` — (1) "Install Linux desktop build deps" now
  also installs `x11-utils` (provides `xdpyinfo`, the display probe); (2) the
  §11.6 smoke step and (3) the §11.11 integration-test step each gained the
  same §11.14 gate: `export DISPLAY=:N` first, then a pre-flight
  `if DISPLAY=:N xdpyinfo >/dev/null 2>&1; then echo "::error::display :N
  already in use by another X server (stale Xvfb from a prior run?); refusing
  to attach to it"; exit 1; fi` BEFORE launching Xvfb (so an occupied display
  fails cleanly with no doomed Xvfb spawned and no "Server is already active"
  noise), then launch `LIBGL_ALWAYS_SOFTWARE=1 Xvfb :N ... &`, then a bounded
  readiness loop (up to 50×100ms = 5s) that exits 1 with a clear
  `::error::` + message if the PID dies during startup or the display never
  answers; after the loop a final `xdpyinfo` check (with `kill -9` cleanup)
  covers the timeout case. The smoke step keeps openbox + app launch AFTER
  the gate; the integration step keeps the §11.12 `|| EXIT=$?` /
  `kill -9 "$XVFB_PID"` / `exit ${EXIT:-0}` teardown tail, now running only
  behind a guaranteed-live display. Step counts unchanged (ubuntu-gate 14,
  windows-nightly 10). Docs: `docs/FUTURE_WORK.md` — §11.14 added + closed as
  DONE in the same run (open list unchanged: §11.14 not an open item), header
  bumped; `automation-track.md` — header line + this Run Log entry (no
  Roadmap row exists for §11.14; per protocol the Run Log is the record).
  No Dart/test files changed.
  Evidence: `flutter analyze` → `No issues found! (ran in 2.3s)`; full
  regression `flutter test` → 637/637 pass (01:50, All tests passed! — no
  Dart changes); workflow re-parses clean via PyYAML (ubuntu-gate 14 steps,
  windows-nightly 10 — step counts unchanged, only `with:`/`run:` content
  changed); all 13 bash run-blocks pass `bash -n`. The gate is proven
  empirically on this host across all four paths: (a) NEG smoke on OCCUPIED
  :77 (real stale leaked server present) → `::error::display :77 already in
  use ... refusing to attach to it`, exit 1, no new Xvfb orphan created;
  (b) NEG integration on OCCUPIED :79 → same clean refusal, exit 1, no
  orphan; (c) POS smoke on fresh :85 → Xvfb starts, gate passes (~100ms
  ready), release binary alive after 15s, `smoke ok: release binary alive
  after 15s under Xvfb + openbox`, exit 0, NO :85 Xvfb left behind (only the
  3 pre-existing leaks remain in `ps`); (d) POS integration on fresh :88 →
  the REAL `flutter test integration_test/accessibility_windows_test.dart
  -d linux` through the gated block → 12/12 pass (00:34, All tests passed!),
  exit 0, no :88 orphan left; plus synthetic proof of the remaining two
  guard branches — "Xvfb :91 exited during startup" (dead PID in loop, exit
  1) and "Xvfb :92 did not become ready within 5s" (alive PID, display never
  answers, exit 1 + kill -9 cleanup). The pre-existing leaked :77/:79/:99
  servers were left untouched per the §11.12 note.
  Commit: a94d18c.
  Push **BLOCKED** (same as all prior runs): no GitHub credentials on this
  host — `git config --get credential.helper` empty, no `gh`, no SSH key, no
  `~/.git-credentials`, no `~/.netrc`, no token in env; `git push origin
  main` → `fatal: could not read Username for 'https://github.com'` (exit
  128). `git ls-remote origin main` still shows `e1749b3`, so
  `e1749b3..HEAD` (43 local commits incl. this run) remains local-only.
  Re-run the push after credentials are provisioned.
  Next: (a) re-push the queued local commits once GitHub credentials exist
  (43 queued at e1749b3); (b) trigger the §11.3 Windows nightly / run
  §9.1–9.2 on a Windows desktop/UIA session (closes §14.1–14.2); or (c)
  decide the §13 Windows-runner / safe-mode questions. Re-audited this run
  (two parallel explore subagents — code-marker scan over lib/test/tool/
  integration_test/.github + full ci.yaml audit): zero TODO/FIXME/HACK/XXX,
  zero commented-out code, zero empty catches, zero `// ignore:` anywhere;
  the ci.yaml audit confirmed the two remaining workflow hardenings — the
  #4 "smoke verifies only process aliveness, not window mapping" (would need
  xdotool/wmctrl, deliberately out of scope this run) and #5 (no `Timeout`/
  `timeout-minutes` on ubuntu-gate steps/jobs) — as candidate §11.15/§11.16
  items; the `dart format` gate still needs an explicit owner decision
  (102/127-file churn) and the coverage-artifact comparison needs ≥2 CI runs.
- 2026-10-23Z — CI P1 §11.15 (Linux-release smoke requires the window to
  actually map). The §11.14 run's audit candidate #4 — the §11.6 smoke
  proves only process aliveness (`kill -0` after 15 s), never that the app
  actually mapped its window — was promoted as §11.15 and closed this run.
  The failure class is real and was proven empirically here: a probe of the
  release binary under the smoke recipe showed `linux/runner/my_application.cc`
  only SHOWS the window once the FIRST Flutter frame renders
  (`first_frame_cb`), and under the smoke's software GL (llvmpipe) that
  frame took ~26-52 s on this host — well past the 15 s window. Every prior
  §11.6 smoke green was therefore also a "no window yet" green; an app that
  stays alive without ever reaching first frame (display connection failure,
  GDK_BACKEND fallback, renderer stall) would have passed the old gate.
  Files changed:
  `.github/workflows/ci.yaml` — (1) "Install Linux desktop build deps" now
  also installs `xdotool` (the window-search probe); (2) the §11.6 "Smoke
  start Linux release (Xvfb)" step gained the §11.15 gate after the 15 s
  aliveness check: a bounded loop (up to 75×1 s — first frame under
  llvmpipe is slow) searches for the app's window with an ANCHORED title
  regex `xdotool search --name "^llm_chess_arena$"` (`xdotool --name` is an
  unanchored regex, and the pre-first-frame 10x10 helper window is named
  `com.llmarena.llm_chess_arena` so it never matches), then requires
  `map_state == IsViewable` with width/height ≥ 100 via `xwininfo`. The
  window is only "mapped" once Flutter's first frame rendered — exactly the
  §11.15 signal. `xdotool --onlyvisible` is deliberately NOT used: it
  resolves visibility through the WM's `_NET_CLIENT_LIST`, which was
  observed lagging the actual mapping by tens of seconds on this setup,
  while `xwininfo` reads the server's real map state. On timeout the step
  dumps `smoke.log` and exits 1 with `::error::release binary is alive but
  no mapped window titled 'llm_chess_arena' ...`; success prints the mapped
  geometry: `smoke ok: release binary alive after 15s and window mapped
  (title llm_chess_arena, 1278x720) under Xvfb + openbox`. Step counts
  unchanged (ubuntu-gate 14, windows-nightly 10).
  Docs: `docs/FUTURE_WORK.md` — §11.15 added + closed as DONE in the same
  run (open list unchanged: §11.15 not an open item), header bumped;
  `automation-track.md` — header line + this Run Log entry (no Roadmap row
  exists for §11.15; per protocol the Run Log is the record).
  No Dart/test files changed.
  Evidence: `flutter analyze` → `No issues found! (ran in 2.3s)` (exact
  output); full regression `flutter test` → 637/637 pass (01:48, All tests
  passed! — no Dart changes); workflow re-parses clean via PyYAML
  (ubuntu-gate 14 steps, windows-nightly 10 — step counts unchanged, only
  `with:`/`run:` content changed); both changed run blocks pass `bash -n`.
  The exact §11.15 block is proven empirically on this host across both
  paths: (a) POSITIVE on fresh :97 with the freshly rebuilt release binary —
  `smoke ok: release binary alive after 15s and window mapped (title
  llm_chess_arena, 1278x720) under Xvfb + openbox`, exit 0 in ~53 s (15 s
  aliveness + ~37 s window wait; the window's map state transitioned
  IsUnMapped→IsViewable at ~51 s), with NO :97 Xvfb and no app process left
  behind; (b) NEGATIVE (`NO_APP`, no window ever appears) — the guard fires
  `::error::release binary is alive but no mapped window titled
  'llm_chess_arena' on :98 ...` and exits 1 with no orphan :98 Xvfb left.
  `git status --short` confirms only the workflow + the two track docs
  changed (release bundle build/ stays untracked).
  Commit: 715762e.
  Push **BLOCKED** (same as all prior runs): no GitHub credentials on this
  host — `git push --dry-run origin main` → `fatal: could not read Username
  for 'https://github.com': No such device or address` (`git config --get
  credential.helper` empty, no `gh`, no SSH key, no `~/.git-credentials`,
  no `~/.netrc`, no token in env); `git ls-remote origin main` still shows
  `e1749b3`, so `e1749b3..HEAD` (45 local commits incl. this run) remains
  local-only. Re-run the push after credentials are provisioned.
  Next: (a) re-push the queued local commits once GitHub credentials exist
  (45 queued at e1749b3); (b) trigger the §11.3 Windows nightly / run
  §9.1–9.2 on a Windows desktop/UIA session (closes §14.1–14.2); or (c)
  decide the §13 Windows-runner / safe-mode questions. The remaining
  audit-candidate §11.16 (no `timeout-minutes` on ubuntu-gate steps/jobs —
  a hung step could stall the gate indefinitely) is still open for a future
  run; the `dart format` gate still needs an explicit owner decision
  (102/127-file churn) and the coverage-artifact comparison needs ≥2 CI
  runs.
- 2026-10-23Z — CI P1 §11.16 (bound every gate job and step with
  `timeout-minutes`). The §11.15-run audit candidate was confirmed and
  promoted as §11.16: `grep timeout-minutes .github/workflows/ci.yaml`
  returned **zero** matches before this run, so both jobs relied on GitHub's
  default 360-minute job timeout — a hung step (pub get, the 103 MiB engine
  download, apt, a deadlocked `flutter test`, a never-exiting smoke app)
  could stall the gate for up to 6 h and overlap the next scheduled
  `windows-nightly` run. Files changed:
  `.github/workflows/ci.yaml` — (1) job-level backstops: `ubuntu-gate`
  `timeout-minutes: 90` (~4x the observed ~15-20 min green wall time incl.
  the first-run Stockfish download) and `windows-nightly`
  `timeout-minutes: 180` (the §9.1/§9.2 steps are interactive/wider), each
  with a §11.16 comment; (2) step-level bounds on ALL 26 steps across both
  jobs — checkout 5, Setup Flutter 15, pub-cache restore 5, pub get 5,
  analyze 10 (x2), engine cache restore 5, engine download 15, `flutter
  test` 30 (ubuntu-gate Test + windows Unit & widget tests), apt install 15,
  `flutter build linux --release` 30, Linux smoke step 15 (the §11.14
  readiness + §11.15 window loops are already internally bounded — this is a
  belt-and-braces backstop), Linux integration 20, coverage 30 (keeps
  `continue-on-error: true`, so a timeout still cannot redden the gate),
  coverage upload 5, `flutter build windows --release` 60, §9.1 integration
  30, §9.2 UIA smoke 20, smoke upload 5. The §9.1 and §9.2 step comments now
  explicitly note that their internal timeouts (FLUTTER_TEST_DEVICE_TIMEOUT /
  the script's -Timeout 120s) do NOT bound the whole step — the new step
  timeout does. Step counts unchanged (ubuntu-gate 14, windows-nightly 12)
  — only `timeout-minutes:` keys + comments added.
  Docs: `docs/FUTURE_WORK.md` — §11.16 added + closed as DONE in the same
  run (open list unchanged: §11.16 not an open item), header bumped;
  `automation-track.md` — header line + this Run Log entry (no Roadmap row
  exists for §11.16; per protocol the Run Log is the record).
  No Dart/test files changed.
  Evidence: workflow re-parses clean via PyYAML **with a strict
  duplicate-key loader** (`jobs: ubuntu-gate + windows-nightly`; all 28
  `timeout-minutes` keys present — 26 steps + 2 jobs — exactly one per
  step/job, zero duplicate keys anywhere in the file); all 13 bash run-blocks
  pass `bash -n` (the single "failure" is the windows-nightly §9.1
  PowerShell block, Windows-only by design — the §11.12 precedent); `flutter
  analyze` → `No issues found! (ran in 2.4s)`; full regression `flutter
  test` → 637/637 pass (01:48, All tests passed! — no Dart changes);
  `git status --short` confirms only the workflow + the two track docs
  changed.
  Commit: 5d00acb.
  Push **BLOCKED** (same as all prior runs): no GitHub credentials on this
  host — audited again this run (`git config --get credential.helper` empty,
  no `gh`, no SSH key, no `~/.git-credentials`, no `~/.netrc`, no token in
  env; `git push --dry-run origin main` → `could not read Username for
  'https://github.com'`); `git ls-remote origin main` still shows `e1749b3`,
  so `e1749b3..HEAD` (local queue incl. this run) remains local-only.
  Re-run the push after credentials are provisioned.
  Next: (a) re-push the queued local commits once GitHub credentials exist;
  (b) trigger the §11.3 Windows nightly / run §9.1–9.2 on a Windows
  desktop/UIA session (closes §14.1–14.2); or (c) decide the §13
  Windows-runner / safe-mode questions. Re-audited this run: FUTURE_WORK.md
  open items remain all Windows-native (§9.1/§9.2/§11.3/§14), external
  (§2.6), or un-scheduled decisions (§13) — with §11.16 closed, the
  `dart format` gate (102/127-file churn, needs an explicit owner decision)
  and the coverage-artifact comparison (needs ≥2 CI runs) are the only
  remaining audit candidates, neither is a code/CI defect.
- 2026-10-23Z — CI P1 §11.17 (real-engine E2E runs on the Windows gate too).
  Three parallel subagent audits (lib markers, test markers, full ci.yaml
  defect audit) found no open FUTURE_WORK.md item that is Linux-implementable
  (§9.1/§9.2/§11.3/§14 Windows-native BLOCKED, §2.6 external, §13
  un-scheduled) — consistent with every run since §11.16 — but the ci.yaml
  audit surfaced a genuine defect nobody had logged: the §11.7 real-engine
  gate was **ubuntu-only in two separate ways**. The ubuntu-gate had the
  download step, but `test/e2e_smoke_test.dart` hardcoded
  `assets/engines/linux-x86-64/stockfish` in BOTH the body and the `skip:`
  predicate — so on the windows-nightly runner the test's Stockfish section
  ALWAYS skipped (that Linux path never exists on Windows), and the Windows
  job had no engine download step at all. A `flutter_windows.dll` engine
  integration regression could never redden the nightly. Promoted as §11.17
  per the §11.4–§11.16 precedent and closed in the same run.
  Files changed:
  `test/e2e_smoke_test.dart` — removed the hardcoded Linux path. The test
  now resolves the bundled binary for the current host through the SAME
  resolver the app's runtime extraction uses
  (`EmbeddedEngine.bundledAssetPath()` — Windows →
  `windows-x86-64/stockfish.exe`, Linux → `linux-x86-64/stockfish`, macOS →
  `macos-universal/stockfish`, null for web/iOS/unshipped combos). A single
  top-level `hostEngineBinary` value is shared by the `skip:` predicate and
  the body (previously two separate existence checks that could disagree and
  skipped 100% of the time on a Windows host); the body keeps the graceful
  double-guard — null host (no bundled binary for the OS/arch) and
  binary-not-present (gitignored, fetch hint) — and the skip message names
  the host platform dir + the `dart run tool/download_stockfish.dart
  <platform>` command. New import: `package:llm_chess_arena/src/review/
  embedded_engine.dart`.
  `.github/workflows/ci.yaml` — `windows-nightly` gained (after Analyze,
  before Build Windows release) the same two-step engine pair the ubuntu-gate
  has: "Restore Stockfish engine cache (§11.17)" (`actions/cache@v4` on
  `assets/engines/windows-x86-64`, fixed key `${{ runner.os }}-stockfish-
  windows-x86-64` — the tool's size/SHA-256/`file`/UCI re-verification
  self-heals stale caches) and "Download Stockfish engine (real-engine E2E,
  §11.17)" (`dart run tool/download_stockfish.dart windows-x86-64`, exit 1
  on any failure). The Windows release asset is a `.zip`; the tool extracts
  it with `unzip`, which Git-for-Windows ships and prepends to PATH on the
  windows-latest runner image (verified via the runner-images docs +
  multiple field reports). Windows-nightly step count 10 → 12.
  `docs/FUTURE_WORK.md` — §11.17 added + closed as DONE in the same run
  (open list unchanged: §11.17 not an open item), header bumped.
  `automation-track.md` — header line + this Run Log entry (no Roadmap row
  exists for §11.17; per protocol the Run Log is the record).
  Evidence: `flutter analyze` → `No issues found! (ran in 2.3s)` (exact
  output; also confirmed the pristine test file is already part of the
  documented 102/127-file `dart format` drift — reverted a full-file
  reformat to keep the diff surgical);
  `flutter test test/e2e_smoke_test.dart` → 5/5 pass with the Stockfish test
  EXECUTING (`-- stockfish: 30 cp, best c7c5`) — unchanged on Linux, proving
  the refactor is behavior-neutral on the one platform we can run;
  the exact download command `dart run tool/download_stockfish.dart
  windows-x86-64` → `size ok / sha256 ok / file ok (PE32+ executable for MS
  Windows ...) / handshake warning (foreign-arch, cannot execute on this
  host)` + `OK present` — the strict size+sha+type verification passes and
  the cross-arch handshake degrades to the designed warning, so the SAME
  step hard-gates on a Windows runner (host arch → strict handshake);
  workflow re-parses clean via PyYAML (ubuntu-gate 14 steps unchanged,
  windows-nightly 12 = 10 + 2); all 13 bash run-blocks still pass
  `bash -n` (the only "failure" remains the Windows-only §9.1 PowerShell
  block, per the §11.12 precedent); full regression `flutter test` → 637/637
  pass (no lib/ or test/ behavior change on Linux; only the added
  resolution logic, proven by the executing engine test).
  `git status --short` confirms only the test file + the workflow + the two
  track docs changed.
  Commit: ebadbd9 (§11.17; recorded in this Run Log — the workflow-side
  steps are covered by the next line's precedent: later runs record the
  commit hash the run produced).
  Push **BLOCKED** (same as all prior runs): no GitHub credentials on this
  host — audited again this run (`git config --get credential.helper` empty,
  no `gh`, no SSH key, no `~/.git-credentials`, no `~/.netrc`, no token in
  env; `git push --dry-run origin main` → `could not read Username for
  'https://github.com'`); `git ls-remote origin main` still shows `e1749b3`,
  so the local queue (49 commits incl. this run) remains local-only.
  Re-run the push after credentials are provisioned.
  Next: (a) re-push the queued local commits once GitHub credentials exist;
  (b) trigger the §11.3 Windows nightly / run §9.1–9.2 on a Windows
  desktop/UIA session (with this fix the nightly's Stockfish E2E will now
  execute instead of skipping — one less silent gap when it first runs);
  or (c) decide the §13 Windows-runner / safe-mode questions. Re-audited
  this run: FUTURE_WORK.md open items remain all Windows-native
  (§9.1/§9.2/§11.3/§14), external (§2.6), or un-scheduled decisions (§13);
  the `dart format` gate (102/127-file churn, needs an explicit owner
  decision) and the coverage-artifact comparison (needs ≥2 CI runs) are the
  only remaining audit candidates, neither is a code/CI defect.
- 2026-10-24Z — DECISIONS §13 (Windows-runner + safe-mode resolved; no VM
  needed). Every audit since §11.16 confirmed FUTURE_WORK.md's open items are
  all Windows-native (§9.1/§9.2/§11.3/§14.1-14.2), external (§2.6), or
  un-scheduled decisions (§13) — and §13's Windows-runner question is the
  direct prerequisite for the whole remaining backlog: whether the first
  §11.3 trigger (and the §9.1/§9.2 validation) needs a dedicated Windows VM
  with an interactive desktop or can run on the GitHub-hosted
  `windows-latest` runner. This run researched and DECIDED both questions.
  Files changed:
  `docs/FUTURE_WORK.md` — §13 rewritten "resolved 2026-10-24": the Windows
  runner decision and the safe-mode decision are both DECIDED (telemetry
  isolation was already decided 2026-10-23); §11.3's "Remaining" now carries
  the first-run trigger checklist (dispatch, expected green signals, the §13
  caveats to watch in the artifacts, and the fallback criteria); header
  bumped.
  `automation-track.md` — header line + this Run Log entry (no Roadmap row
  exists for §13; per protocol the Run Log is the record).
  **Decision 1 — Windows runner: use GitHub-hosted `windows-latest`.**
  Evidence, verified this run against the hosted Windows Server 2022 image:
  (1) **interactive console session, not Session 0** — a measured diagnostic
  on `windows-latest` (pyjab `gaozhao1989/pyjab` `.github/workflows/
  windows-gui.yml`, which runs attach-to-a-launched-app GUI +
  accessibility-bridge automation on the hosted runner) reports
  `qwinsta: >console runneradmin 2 Active`, `explorer.exe` running, and the
  launched app's window in the desktop's top-level window list — fetched and
  read verbatim this run; (2) **UIA tooling preinstalled** — runner-images
  `Windows2022-Readme.md` (fetched this run) lists `WinAppDriver
  1.2.2009.02003` under Tools, so the §9.2 `UIAutomationCore` COM client needs
  no install step; (3) `flutter test integration_test/... -d windows` against
  the real Windows binary is routine on hosted runners — per the Flutter
  integration-testing docs, **xvfb is the LINUX-only virtual-display
  requirement**, Windows needs none; (4) the runner account is a local admin
  with **UAC disabled** (GitHub Docs), so UIA client registration and the
  smoke's step-7 Event Viewer `Get-WinEvent` read work. Caveats for the first
  run: default resolution 1024x768 (raise via `Set-DisplayResolution -Width
  1920 -Height 1080 -Force`; mode-limited, runner-images#2935), display scale
  fixed at 96 DPI (no DPI-scaling coverage on a hosted runner), unattended
  desktop (windows render off-screen and receive synthetic `mouse_event`
  input, nothing physically displayed). **Fallback criteria:** a dedicated VM
  only if the first hosted run hits a session-specific failure the image
  cannot reproduce — UIA attach fails, Event Viewer unreadable, or a
  Windows-11-only rendering delta matters (the image is Server 2022).
  **Decision 2 — Safe mode: no toggle.** Keep the shipped hardening
  (`ExcludeSemantics` + `IndexedStack` hidden-tab guard + stable semantics
  roots); a screen-reader-visible safe mode would itself be an accessibility
  regression. The upstream engine fix (`flutter/flutter#175041`, §2.6) is the
  only retirement path; the §9.2 UIA smoke + §14.1/§14.2 are the evidence
  gate, and the decision is reopened only if that validation or a field
  report shows the hardening insufficient in practice.
  No lib/, test/, or workflow files changed — a decisions/process deliverable
  (the §13 precedent from the 2026-10-23 telemetry-isolation run).
  Evidence: `flutter analyze` → `No issues found! (ran in 2.3s)` (exact
  output, re-run before commit); full regression `flutter test` → 637/637
  pass (01:47, All tests passed! — no Dart changes); `git status --short`
  confirms only the two track docs changed; the two decisive research sources
  fetched and read verbatim this run (pyjab windows-gui.yml session
  diagnostic; runner-images Windows2022-Readme.md WinAppDriver entry).
  Commit: 058f5d7.
  Push **BLOCKED** (same as all prior runs): no GitHub credentials on this
  host — re-audited this run (`git config --get credential.helper` empty, no
  `gh`, no SSH key, no `~/.git-credentials`, no `~/.netrc`, no token in env;
  `git push --dry-run origin main` → `fatal: could not read Username for
  'https://github.com': No such device or address`); `git ls-remote origin
  main` still shows `e1749b3`, so the local queue remains local-only. Re-run
  the push after credentials are provisioned.
  Next: (a) re-push the queued local commits once GitHub credentials exist;
  (b) trigger the §11.3 windows-nightly via `workflow_dispatch` (or wait for
  the 06:00 UTC schedule) on the hosted `windows-latest` runner per the §13
  decision + §11.3 checklist — this is now the ONLY remaining functional gap
  (§14.1-14.2); or (c) re-check §2.6 on the next Flutter upgrade / when
  `flutter/flutter#190903` lands. The `dart format` gate (102/127-file churn,
  needs an explicit owner decision) and the coverage-artifact comparison
  (needs ≥2 CI runs) remain the only audit candidates, neither a code/CI
  defect.
- 2026-10-24Z — CI P1 §11.18 (Linux-release smoke: window-size sanity check
  actually enforced). Three parallel subagent audits (code-marker scan,
  full ci.yaml defect audit, FUTURE_WORK.md/ARCHITECTURE.md open-item audit)
  confirmed the open FUTURE_WORK.md items are all Windows-native (§9.1/§9.2/
  §11.3/§14.1-14.2 — BLOCKED on this Linux host, no credentials, no Windows
  desktop/UIA session), external (§2.6 — upstream fix still unlanded), or
  already-resolved decisions (§13). The ci.yaml audit surfaced a genuine
  Linux-fixable correctness defect nobody had logged: the §11.15 smoke's
  window-size sanity check was bypassable. `WIN_ID`/`MAP_STATE` are
  re-checked by the post-loop verdict, but `WIDTH`/`HEIGHT` ≥ 100 only gated
  the `break` inside the 75×1 s window-search loop — if the window was
  `IsViewable` at a capped <100×100 size for all 75 iterations, the loop
  exhausted without breaking, the post-loop guard passed, and the step
  printed `smoke ok: ... 50x50` — greenlighting a window that never reached
  the §11.15 sane-geometry requirement (the exact class of "mapped but
  wrong" first-frame failure the gate exists to catch; ironically capped
  windows passed MORE reliably than healthy ones, because a small window
  maps faster under llvmpipe). Files changed:
  `.github/workflows/ci.yaml` — the smoke step's post-loop verdict now also
  requires `${WIDTH:-0} -ge 100` and `${HEIGHT:-0} -ge 100` (single guard:
  `[ -z "$WIN_ID" ] || [ "$MAP_STATE" != "IsViewable" ] || WIDTH < 100 ||
  HEIGHT < 100`), and the `::error::` message reports the observed
  `map_state='...'` + `${WIDTH}x${HEIGHT}` so a capped window is visible in
  the log; the success line's dimensions are now guaranteed ≥ 100×100.
  Step counts unchanged (ubuntu-gate 14, windows-nightly 10) — only the
  smoke step's post-loop `if` changed.
  `docs/FUTURE_WORK.md` — §11.18 added + closed as DONE in the same run per
  the §11.4–§11.17 precedent (open list unchanged: §11.18 not an open item),
  header bumped.
  `automation-track.md` — header line + this Run Log entry (no Roadmap row
  exists for §11.18; per protocol the Run Log is the record).
  No Dart/test files changed.
  Evidence: workflow re-parses clean via PyYAML with a strict duplicate-key
  loader (jobs: ubuntu-gate + windows-nightly; ubuntu-gate 14 steps,
  windows-nightly 10; step counts unchanged); the extracted smoke run block
  passes `bash -n`; `flutter analyze` → `No issues found! (ran in 2.4s)`
  (exact output); full regression `flutter test` → 637/637 pass (01:53, All
  tests passed! — no Dart changes). The fix is proven empirically on this
  host: (a) an 8-case synthetic probe of the verdict logic — capped 50×50
  viewable window → FAIL (`::error::... got map_state='IsViewable', 50x50`),
  real 1278×720 → PASS, empty window id → FAIL, IsUnMapped → FAIL, empty
  xwininfo dimensions → FAIL, 99×99 / 100×99 / 99×100 boundaries → FAIL,
  exact 100×100 → PASS (ALL GUARD CASES OK); (b) the FULL modified smoke
  block executed verbatim against the real Linux release bundle under a
  fresh Xvfb :91 → `smoke ok: release binary alive after 15s and window
  mapped (title llm_chess_arena, 1278x720) under Xvfb + openbox`, exit 0,
  no :91 Xvfb or release-app orphan left behind (the leaked :77/:79 servers
  from earlier hourly runs remain untouched per the §11.12/§11.14 precedent;
  a first attempt on :77 was correctly refused by the §11.14 pre-flight
  probe — `::error::display :77 already in use ... refusing to attach` —
  itself a live demonstration of that gate). `git status --short` confirms
  only the workflow + the two track docs changed (release bundle build/
  stays untracked).
  Commit: ffba037 (recorded in a follow-up track commit per the §13 precedent).
  Push **BLOCKED** (same as all prior runs): no GitHub credentials on this
  host — audited again this run (`git config --get credential.helper` empty,
  no `gh`, no SSH key, no `~/.git-credentials`, no `~/.netrc`, no token in
  env); `git ls-remote origin main` still shows `e1749b3`, so the local
  queue (50 commits through this run) remains local-only. Re-run the push
  after credentials are provisioned.
  Next: (a) re-push the queued local commits once GitHub credentials exist;
  (b) trigger the §11.3 windows-nightly via `workflow_dispatch` (or wait for
  the 06:00 UTC schedule) on the hosted `windows-latest` runner per the §13
  decision + §11.3 checklist — the ONLY remaining functional gap
  (§14.1-14.2); or (c) re-check §2.6 on the next Flutter upgrade / when
  `flutter/flutter#190903` lands. Audit candidates logged for future runs:
  §11.18-bis the fixed Stockfish cache keys never invalidate (constant key
  with no `hashFiles`/version component — correctness is saved by the
  download tool's size/SHA-256/type/UCI self-heal, but after a release bump
  the restored cache slot stays permanently frozen stale and every run
  re-downloads the ~103 MiB binary; a fix could key on the pinned SHA-256 in
  the per-platform `assets/engines/*/README.md` via `hashFiles`) and the
  stale-doc trio found by the docs audit (ARCHITECTURE.md:12 "regression
  tests pending" — perft tests exist; ARCHITECTURE.md:54 "unit/widget suite
  deferred" — 12 screen suites + 637 tests exist; ENGINE_RUNTIME.md:154
  references "§3.3" which no longer exists in RUNBOOK.md — the section is
  "Flutter upgrade gate (release block, acceptance criterion 14.8)").
- 2026-10-24Z — TOOL/PROCESS P1 §11.19 (download tool corrupt-archive
  self-heal). Three parallel subagent audits (download-tool code audit,
  fresh-eyes ci.yaml audit, repo hygiene scan) confirmed the open
  FUTURE_WORK.md items are all Windows-native (§9.1/§9.2/§11.3/§14.1-14.2 —
  BLOCKED on this Linux host), external (§2.6 — re-verified this run:
  flutter/flutter#190903 still open/unmerged, #175041 still open), or
  resolved decisions (§13), but surfaced one genuine tool defect nobody had
  logged: the §11.7/§11.17 "stale caches self-heal" promise held only for
  the extracted binary, never the cached release archive. `ensureArchive`
  trusts any existing archive file under `--archive-dir`, so a truncated
  archive (a killed download — the §11.16 CI step timeout can SIGKILL the
  tool mid-write) stuck every later run at extraction forever: `tar -tzf`/
  `-xzOf` failed, the corrupt archive was never deleted, and the run
  reported FAIL every time with no automatic recovery. Promoted as §11.19
  into `docs/FUTURE_WORK.md` per the §11.4–§11.18 precedent and closed in
  the same run. Files changed:
  `tool/download_stockfish.dart` — `fetchPlatform` now runs a bounded
  two-attempt loop: new helper `extractAndVerify` deletes the unusable
  archive + any partial binary on ANY failure (unlistable archive, failed
  member extraction, or post-extraction size/SHA-256/`file`/handshake
  verification failure) and throws; `fetchPlatform` re-downloads exactly
  once and returns `fetched (re-downloaded: cached archive was corrupt)`.
  A pure download failure (no archive obtained at all) is NOT retried — the
  same URLs would only double the hang. The helper also creates
  `dest.parent` itself (the old code relied on `fetchPlatform`'s pre-create;
  a direct call into a missing directory could hang forever in
  `File.openWrite`'s lazy-open error path — reproduced by this run's
  direct-call probe before the fix). `candidateUrls`/`FetchOptions`/`main`
  gained a `baseOverride`/`--base-url=` seam (single candidate under a given
  base; documented in `--help`) for loopback tests.
  `test/download_stockfish_test.dart` (new, 5 deterministic offline tests):
  (1) corrupt cached archive → discarded + exactly one re-download +
  recovered binary verifies; (2) re-download that is also garbage → bounded
  (exactly one retry) + no corrupt archive/partial binary left (a later run
  starts clean); (3) pure download failure → NOT retried, fails fast with
  `all download candidates failed`; (4) `baseOverride` single-candidate
  semantics (official base unchanged without it); (5) `extractAndVerify`
  happy path on a valid cached archive (no download; valid archive kept).
  Downloads hit a loopback HTTP server only (no external network); the fake
  `PlatformAsset` reports its own payload's size/SHA-256.
  `docs/FUTURE_WORK.md` — §11.19 added + closed as DONE in the same run
  (open list unchanged: §11.19 not an open item), header bumped.
  `automation-track.md` — header line + this Run Log entry (no Roadmap row
  exists for §11.19; per protocol the Run Log is the record).
  Evidence: `flutter analyze` → `No issues found! (ran in 2.4s)` (exact
  output); `flutter test test/download_stockfish_test.dart` → 5/5 pass
  (All tests passed!); full regression `flutter test` → 642/642 pass
  (02:04, All tests passed! — 637 baseline + 5 new); real happy path
  unchanged — `dart run tool/download_stockfish.dart linux-x86-64` → `OK
  present` with size/sha256/file/uciok all verified; and the REAL self-heal
  proven empirically on this host: fetch a fresh real linux archive
  (81,388,977 bytes) + extract + verify OK, then truncate the cached archive
  to 1 KiB and delete the binary, re-run the same command →
  `tar: Unexpected EOF in archive` → `re-downloading once` → `OK fetched
  (re-downloaded: cached archive was corrupt)` with the full archive restored
  and size/sha256/file/uciok re-verified. `git status --short` confirms only
  the tool + new test + the two track docs changed.
  Commit: 1a46713.
  Push **BLOCKED** (same as all prior runs): no GitHub credentials on this
  host — re-audited this run (`git config --get credential.helper` empty, no
  `gh`, no SSH key, no `~/.git-credentials`, no `~/.netrc`, no token in env;
  `git push --dry-run origin main` → `fatal: could not read Username for
  'https://github.com'`); `git ls-remote origin main` still shows `e1749b3`,
  so `e1749b3..HEAD` (57 local commits through this run) remains local-only —
  including the ENTIRE §11.3–§11.19 CI modernization: the hosted CI on the
  remote still runs the old 6-step analyze+test job, so none of the modern
  gates (§11.4–§11.19) have ever run on a hosted runner. Re-run the push
  after credentials are provisioned.
  Next: (a) re-push the queued local commits once GitHub credentials exist;
  (b) trigger the §11.3 windows-nightly via `workflow_dispatch` (or wait for
  the 06:00 UTC schedule) on the hosted `windows-latest` runner per the §13
  decision + §11.3 checklist — the ONLY remaining functional gap
  (§14.1-14.2); or (c) re-check §2.6 on the next Flutter upgrade / when
  `flutter/flutter#190903` lands. Audit candidates logged for future runs:
  §11.18-bis (Stockfish cache keys never invalidate — constant key, no
  `hashFiles`/version component; correctness saved by the download tool's
  self-heal, but after a release bump the restored cache slot is frozen
  stale and every run re-downloads the ~103 MiB binary; a fix could key on
  the pinned SHA-256 in `assets/engines/*/README.md` via `hashFiles`), the
  stale-doc trio (ARCHITECTURE.md:12 "regression tests pending",
  ARCHITECTURE.md:54 "unit/widget suite deferred", ENGINE_RUNTIME.md:154
  "§3.3"), and the ci.yaml smoke-step `xwininfo` race (the
  `MAP_STATE/WIDTH/HEIGHT=$(xwininfo ...)` substitutions are unguarded under
  `set -euo pipefail` — a window destroyed between the xdotool search and
  the xwininfo call would abort the step and skip its diagnostics + Xvfb
  teardown).
- 2026-10-24Z — CI/PROCESS P1 §11.20 (engine cache keys invalidate on the
  pinned release). All documented FUTURE_WORK.md open items remain
  Windows-native (§9.1/§9.2/§11.3/§14.1-14.2 — BLOCKED on this Linux host)
  or external (§2.6), so per the §11.18/§11.19 precedent this run took the
  highest-priority logged audit candidate: §11.18-bis — both Stockfish
  engine-restore steps used a CONSTANT cache key
  (`${{ runner.os }}-stockfish-linux-x86-64` /
  `-windows-x86-64`), so a Stockfish release bump (sf_19 → sf_20; the
  per-platform `assets/engines/*/README.md` pins size + SHA-256 the download
  tool verifies against) left the restored slot permanently frozen stale:
  every run restores 103 MiB, the §11.7/§11.17 self-heal rejects the
  mismatch and re-downloads the same 103 MiB, and the correct binary is
  never saved back (actions/cache saves only on a primary-key miss — the
  constant key never misses). Promoted as §11.20 into
  `docs/FUTURE_WORK.md` and closed in the same run. Files changed:
  `.github/workflows/ci.yaml` — both cache steps now key on the pinned
  version contract:
  `${{ runner.os }}-stockfish-<platform>-${{ hashFiles('assets/engines/<platform>/README.md') }}`;
  each step's design comment rewritten (the "fixed key" wording is
  superseded; why no `restore-keys` fallback — a version-less prefix would
  re-introduce the permanent stale restore, with no correctness upside since
  content validity is enforced on every restore by the tool's
  size/SHA-256/`file`/UCI re-verification). Step counts unchanged
  (ubuntu-gate 14, windows-nightly 12); no Dart/test files changed.
  `docs/FUTURE_WORK.md` — §11.20 added + closed as DONE in the same run per
  the §11.4–§11.19 precedent, header bumped.
  `automation-track.md` — header line + this Run Log entry (no Roadmap row
  exists for §11.20; per protocol the Run Log is the record).
  Evidence: workflow re-parses clean via PyYAML with a strict duplicate-key
  loader (jobs: ubuntu-gate + windows-nightly; step counts unchanged; both
  engine keys carry the README hashFiles component; no restore-keys on
  either); all 11 bash run blocks pass `bash -n` (the sole "failure" is the
  Windows-only §9.1 PowerShell block, Windows-only by design per §11.12);
  the invalidation property is proven empirically — `sha256sum` of the
  current linux-x86-64 README
  `c9798ef3fb62a1ac79c386c72d991b877e117b6c7beab8dfa1845d5c609e3a2f` vs a
  bumped copy `f681d999e3fae5b24c29d4336a44a1b1f3f5fca7d843cca3f0766e7ccc94b0a1`
  differ (⇒ key change on bump), and the windows-x86-64 README hashes to a
  distinct per-platform value
  `947f1e188b6eb80ecdc955d627f4d578dc9d868ba9b8e754a9584cbc1af7a444`;
  `flutter analyze` → `No issues found! (ran in 2.4s)` (exact output); full
  regression `flutter test` → 642/642 pass (All tests passed! — no Dart
  changes). `git status --short` confirms only the workflow + the two track
  docs changed.
  Commit: 58f0c2d (recorded in a follow-up track commit per the §13 precedent).
  Push **BLOCKED** (same as all prior runs): no GitHub credentials on this
  host — re-audited this run (`git config --get credential.helper` empty, no
  `gh`, no `~/.git-credentials`, no `~/.netrc`, no token in env);
  `git ls-remote origin main` still shows `e1749b3`, so `e1749b3..HEAD` (58
  local commits through this run) remains local-only — including the ENTIRE
  §11.3–§11.20 CI modernization: the hosted CI on the remote still runs the
  old 6-step analyze+test job, so none of the modern gates have ever run on
  a hosted runner. Re-run the push after credentials are provisioned.
  Next: (a) re-push the queued local commits once GitHub credentials exist;
  (b) trigger the §11.3 windows-nightly via `workflow_dispatch` (or wait for
  the 06:00 UTC schedule) on the hosted `windows-latest` runner per the §13
  decision + §11.3 checklist — the ONLY remaining functional gap
  (§14.1-14.2); or (c) re-check §2.6 on the next Flutter upgrade / when
  `flutter/flutter#190903` lands. Audit candidates logged for future runs:
  the ci.yaml smoke-step `xwininfo` race (the
  `MAP_STATE/WIDTH/HEIGHT=$(xwininfo ...)` substitutions are unguarded under
  `set -euo pipefail` — a window destroyed between the xdotool search and
  the xwininfo call would abort the step and skip its diagnostics + Xvfb
  teardown) and the stale-doc trio (ARCHITECTURE.md:12 "regression tests
  pending" — perft tests exist; ARCHITECTURE.md:54 "unit/widget suite
  deferred" — 12 screen suites + 642 tests exist; ENGINE_RUNTIME.md:154
  references "§3.3" which no longer exists in RUNBOOK.md). §11.20 itself is
  closed; the §11.7/§11.17 "fixed key" quotes above are historical records.
- 2026-10-24Z — CI/PROCESS P1 §11.21 (Linux-release smoke: xwininfo captures
  guarded against the vanishing-window abort). All documented FUTURE_WORK.md
  open items remain Windows-native (§9.1/§9.2/§11.3/§14.1-14.2 — BLOCKED on
  this Linux host) or external (§2.6), so per the §11.18/§11.19/§11.20
  precedent this run took the highest-priority logged audit candidate: the
  ci.yaml smoke-step `xwininfo` race. The §11.15/§11.18 smoke step's
  window-verdict loop reads geometry via three
  `xwininfo -id "$WIN_ID" ... | awk` command substitutions that were
  unguarded under the step's `set -euo pipefail` — the `xdotool search` line
  above already carried `|| true` (line 187), but the xwininfo trio (lines
  189/191/192) was missed. The failure mode is exactly what the gate exists
  to catch: the app crashes right after mapping its window, so the window id
  found by the search is destroyed before the next `xwininfo` call → xwininfo
  exits 1 ("No such window") → `pipefail` propagates it into the
  substitution → the failing assignment makes `set -e` abort the shell
  INSIDE the loop → the `::error::` diagnostic, `cat smoke.log`, and the
  `kill -9 "$APP_PID" "$XVFB_PID" "$WM_PID"` teardown never run → the :77
  display leaks on the runner (the §11.12/§11.14 leak class, re-introduced by
  the very gate that was hardened against it). A fresh-eyes subagent audit of
  the whole workflow independently confirmed lines 189/191/192 are the only
  unguarded-substitution defect in the file (all other bash run blocks
  either have no substitutions, use them only in `if` conditions, or are
  `|| true`-guarded). Promoted as §11.21 into `docs/FUTURE_WORK.md` and
  closed in the same run.
  Files changed:
  `.github/workflows/ci.yaml` — the three xwininfo capture lines (MAP_STATE /
  WIDTH / HEIGHT) now each end `|| true`, plus a §11.21 comment block
  explaining the abort hazard and the degrade-and-research behavior. A
  vanished window now degrades to empty values; the loop's next iteration
  re-searches, and a window that stays gone flows into the post-loop verdict
  below, which prints the full `::error::` (observed map state + geometry),
  dumps `smoke.log`, runs the teardown, and exits 1. Healthy windows behave
  unchanged (`|| true` is a no-op on success). Step counts unchanged
  (ubuntu-gate 14, windows-nightly 12); no Dart/test files changed.
  `docs/FUTURE_WORK.md` — §11.21 added + closed as DONE in the same run per
  the §11.4–§11.20 precedent (open list unchanged: §11.21 not an open item),
  header bumped.
  `automation-track.md` — header line + this Run Log entry (no Roadmap row
  exists for §11.21; per protocol the Run Log is the record).
  Evidence: workflow re-parses clean via PyYAML with a strict duplicate-key
  loader (jobs: ubuntu-gate + windows-nightly; ubuntu-gate 14 steps,
  windows-nightly 12; step counts unchanged); the extracted smoke run block
  passes `bash -n`; the smoke body now has 4 guarded substitutions (xdotool +
  3× xwininfo) vs 1 before. The abort semantics are proven empirically on
  this host (bash 5.3.9 — same set -e assignment-abort class as the runners'
  bash 5.x): `MAP_STATE=$(xwininfo -id <bad> 2>/dev/null | awk ...)` under
  `set -euo pipefail` aborts the shell (exit 1, the line after never runs),
  while the `|| true`-guarded form survives with an empty capture. The
  teardown consequence is proven with a full-block harness (extracted from
  BOTH `git show HEAD:...ci.yaml` and the working tree, verbatim, with
  Xvfb/openbox/app stubbed as long-lived PID-recording daemons, fake
  `xdotool` always finding a window id and fake `xwininfo` always exiting 1
  to simulate the vanished window): the OLD block exits 1 with ZERO output
  and leaves all three stub daemons alive (the silent leak), while the NEW
  block prints
  `::error::release binary is alive but no mapped window titled
  'llm_chess_arena' with sane geometry on :77 ... got map_state='<none>',
  0x0 ...`, exits 1, and tears all three stubs down (no leaks). The positive
  path is unchanged: the FULL modified smoke block executed verbatim against
  the real Linux release bundle on a fresh display (:93, pre-probed free) →
  `smoke ok: release binary alive after 15s and window mapped (title
  llm_chess_arena, 1278x720) under Xvfb + openbox`, exit 0, with no :93
  Xvfb and no app process left behind. `flutter analyze` → `No issues found!
  (ran in 2.3s)` (exact output); full regression `flutter test` → 642/642
  pass (01:52, All tests passed! — no Dart changes). `git status --short`
  confirms only the workflow + the two track docs changed (release bundle
  build/ stays untracked).
  Commit: ba6fc57 (recorded in a follow-up track commit per the §13 precedent).
  Push **BLOCKED** (same as all prior runs): no GitHub credentials on this
  host — re-audited this run (`git config --get credential.helper` empty, no
  `gh`, no `~/.git-credentials`, no `~/.netrc`, no token in env);
  `git ls-remote origin main` still shows e1749b3, so `e1749b3..HEAD` (59
  local commits through this run) remains local-only — including the ENTIRE
  §11.3–§11.21 CI modernization, none of which has ever run on a hosted
  runner. Re-run the push after credentials are provisioned.
  Next: (a) re-push the queued local commits once GitHub credentials exist;
  (b) trigger the §11.3 windows-nightly via `workflow_dispatch` (or wait for
  the 06:00 UTC schedule) on the hosted `windows-latest` runner per the §13
  decision + §11.3 checklist — the ONLY remaining functional gap
  (§14.1-14.2); or (c) re-check §2.6 on the next Flutter upgrade / when
  `flutter/flutter#190903` lands. Audit candidates logged for future runs:
  the stale-doc trio (ARCHITECTURE.md:12 "regression tests pending",
  ARCHITECTURE.md:54 "unit/widget suite deferred", ENGINE_RUNTIME.md:154
  "§3.3") — a docs-only P2 that can be closed in a future run; the
  coverage-artifact comparison (needs ≥2 CI runs); the `dart format` gate
  (102/127-file churn, needs an explicit owner decision). Note for the
  record: this run's first (mistakenly over-broad) block extraction re-ran
  the workflow's apt step locally, upgrading xvfb/xserver-common
  (2:21.1.22-1ubuntu1.2 → .3) — incidental dev-tooling bumps, no config
  changes; the corrected extraction used the §11.15/§11.18-style
  smoke-step-only range.

- 2026-10-24Z — DOCS-ACCURACY (stale-doc cleanup): closed the stale-doc trio
  the §11.21 run's Next: logged as "a docs-only P2 that can be closed in a
  future run". This is the highest-priority open item implementable and
  verifiable on this Linux host — every remaining open item in
  `docs/FUTURE_WORK.md` needs a Windows desktop/UIA session (§9.1/§9.2,
  §11.3, §14.1/§14.2) or is upstream-external (§2.6), so those stay BLOCKED.
  Files changed:
  `ARCHITECTURE.md:12` — the chess-rules decision row ended "(regression
  tests pending)"; the perft + FEN/SAN round-trip regression tests have
  existed since `test/chess_rules_test.dart` (groups at :59 perft counts /
  :91 SAN / :179 FEN round-trips) and pass in the 642-test suite. Now reads
  "Verified by regression tests (`test/chess_rules_test.dart`: perft node
  counts + FEN/SAN round-trips)".
  `ARCHITECTURE.md:33` — the module map said "8 screens"; the screens dir
  holds 9 (`variant_replay_screen.dart` shipped in 61d58d7). Now "9 screens".
  `ARCHITECTURE.md:53-54` — "What is intentionally deferred" claimed a
  "comprehensive unit/widget suite deferred"; the suite exists (642 tests,
  23 `test/ui/` suites, `test/support/` harness, `integration_test/`), all
  gated in `.github/workflows/ci.yaml`. Replaced with "Nothing on the test
  side is deferred: ... written and gated by CI".
  `docs/ENGINE_RUNTIME.md:154` — the release checklist cross-referenced
  "`docs/RUNBOOK.md` (§3.3)"; RUNBOOK.md uses unnumbered `##` headings, so
  §3.3 is dangling. The real gate is "## Flutter upgrade gate (release
  block, acceptance criterion 14.8)". Now cites that heading + criterion.
  `docs/RUNBOOK.md:22` + `README.md:17` — "flutter test  # boot + e2e smoke
  tests" comments stale (subagent-confirmed same-class); `flutter test` runs
  the full 642-test regression. Now "# full suite: unit + widget + smoke".
  `docs/FUTURE_WORK.md` — header bumped only (no open item touched; the
  Windows/external items are unchanged and still listed).
  `automation-track.md` — header + this Run Log entry (no Roadmap row exists
  for this item; per protocol the Run Log is the record).
  Audit method: one `explore` subagent (medium) audited the four docs for
  stale claims against the 642-test/9-screen/CI reality; every finding was
  re-fact-checked against the repo (screens dir listing, RUNBOOK headings,
  chess_rules_test groups) before editing. All six edits are documentation
  truth-reconciliation; no behavior change.
  Evidence: `flutter analyze` → `No issues found! (ran in 2.3s)` (exact
  output; Flutter 3.47.6 stable / Dart 3.13.5); full regression `flutter
  test` → 642/642 pass (01:50, All tests passed! — no Dart changes, docs
  only). `git status --short` before commit: only the four docs + the two
  track docs modified (no lib/test/workflow changes).
  Commit: c879019 (recorded in a follow-up track commit per the §13 precedent).
  Push **BLOCKED** (same as all prior runs): no GitHub credentials on this
  host (re-audited this run — `git config --get credential.helper` empty,
  no `gh`, no `~/.git-credentials`, no `~/.netrc`; `git push` under
  `GIT_TERMINAL_PROMPT=0` fails immediately with "could not read Username"
  rather than prompting); `git ls-remote origin main` still shows e1749b3,
  so the ~60 local commits through this run — including the ENTIRE
  §11.3–§11.21 CI modernization — remain local-only and have never run on a
  hosted runner. Re-run the push after credentials are provisioned.
  Next: (a) re-push the queued local commits once GitHub credentials exist;
  (b) trigger the §11.3 windows-nightly via `workflow_dispatch` (or wait for
  the 06:00 UTC schedule) on the hosted `windows-latest` runner per the §13
  decision + §11.3 checklist — the ONLY remaining functional gap
  (§14.1-§14.2); or (c) re-check §2.6 on the next Flutter upgrade / when
  `flutter/flutter#190903` lands. Remaining audit candidates for future
  runs: the `dart format` gate (102/127-file churn, needs an explicit owner
  decision); coverage-artifact comparison (needs ≥2 CI runs — blocked on the
  push).
- 2026-10-24Z — CI/PROCESS P2 §11.22 (coverage artifact upload can no
  longer redden the gate). All documented FUTURE_WORK.md open items remain
  Windows-native (§9.1/§9.2/§11.3/§14.1-14.2 — BLOCKED on this Linux host)
  or external (§2.6 — re-verified this run via the GitHub API:
  flutter/flutter#190903 still `state: open` / `merged: false`, updated
  2026-10-21; #175041 still `state: open`, updated 2026-09-26 — unchanged),
  so per the §11.18/§11.19/§11.20/§11.21 precedent this run took the
  highest-priority genuine gap surfaced by three fresh-eyes parallel
  subagent audits: the §11.4 coverage upload step could redden the gate.
  §11.4's documented contract — coverage is explicitly NOT the success
  metric and "can never redden the gate" (FUTURE_WORK.md §11.4 + the step's
  own comment at ci.yaml:280-281) — was only half-implemented: the
  "Test coverage (§11.4)" RUN step carries `continue-on-error: true`, but
  the `if: always()` "Upload coverage artifact" step that follows it
  (`ci.yaml:286-294`) did NOT. A transient `actions/upload-artifact@v4`
  backend failure (an Actions service failure mode) would therefore have
  turned the ENTIRE ubuntu-gate job red on a non-gating concern — the exact
  case §11.4 says coverage "can never redden the gate" for — while
  analyze/test/build/smoke/integration had all passed. Files changed:
  `.github/workflows/ci.yaml` — the upload step now also carries
  `continue-on-error: true` (plus a §11.22 comment explaining the symmetry:
  a failed artifact push degrades to a warning exactly like a failed
  coverage run; `if-no-files-found: warn` already covers the missing-lcov
  case). Artifact name/path/retention unchanged, so coverage trend
  reporting works identically on the success path. Step counts unchanged
  (ubuntu-gate 14, windows-nightly 12) — only the one step gained
  `continue-on-error: true` + comment.
  `docs/FUTURE_WORK.md` — §11.22 added + closed as DONE in the same run per
  the §11.4–§11.21 precedent (open list unchanged: §11.22 not an open
  item), header bumped.
  `automation-track.md` — header line + this Run Log entry (no Roadmap row
  exists for §11.22; per protocol the Run Log is the record).
  No Dart/test files changed.
  Evidence: workflow re-parses clean via strict duplicate-key PyYAML (jobs:
  ubuntu-gate + windows-nightly; ubuntu-gate 14 steps — now 2
  continue-on-error steps (coverage run + upload) — windows-nightly 12, no
  change); all five multi-command bash run blocks pass `bash -n` (the sole
  "failure" is the Windows-only §9.1 PowerShell block, Windows-only by
  design per §11.12; my change touched no run block); `flutter analyze` →
  `No issues found!`; full regression `flutter test` → 642/642 pass
  (All tests passed! — no Dart changes). `git status --short` confirms only
  the workflow + the two track docs changed.
  Audit method: three parallel subagents — (1) full ci.yaml defect audit
  (very thorough; verified paths/binary names/engine README pins/shell
  syntax; reported only 2 P2 + 3 P3, of which this is the top P2;
  additional P3 candidates logged below), (2) test/code marker audit
  (verified: zero TODO/FIXME/HACK/XXX, only the intentional e2e engine
  self-gate skip, zero dead code, board_motion/premove/scrub_shortcuts logic
  clean, only 3 P2 candidates — a latent `now.year >= 2026` wall-clock
  assertion in clock_seam_test.dart:29, and two silent secure-store error
  swallows in agent_config.dart:551 + agent_setup_screen.dart:425-427,
  logged below), (3) docs/tooling open-item audit (confirmed all open
  FUTURE_WORK items are Windows/external; found P2/P3 docs nits — stale
  "22 test/ui suites" (actual 23), §11.16 evidence "24 steps/26 keys"
  (actual 26 steps/28 keys), stale "631/631" baseline (actual 642/642),
  a dangling "docs/RUNBOOK.md 'Linux desktop'" heading ref, the
  undocumented `--direct` alias in download_stockfish --help, and a
  `0xCAFABE` vs `0xCAFEBABE` seed typo in the §9.2 ps1 track row — logged
  below).
  Commit: ebcd184 (recorded in a follow-up track commit per
  the §13 precedent).
  Push **BLOCKED** (same as all prior runs): no GitHub credentials on this
  host — re-audited this run (`git config --get credential.helper` empty,
  no `gh`, no `~/.git-credentials`, no `~/.netrc`, no token in env; `git
  push --dry-run origin main` under `GIT_TERMINAL_PROMPT=0` → `fatal: could
  not read Username for 'https://github.com': terminal prompts disabled`);
  `git ls-remote origin main` still shows e1749b3, so the local queue (~60
  commits through this run) remains local-only — including the ENTIRE
  §11.3–§11.22 CI modernization, none of which has ever run on a hosted
  runner. Re-run the push after credentials are provisioned.
  Next: (a) re-push the queued local commits once GitHub credentials exist;
  (b) trigger the §11.3 windows-nightly via `workflow_dispatch` (or wait for
  the 06:00 UTC schedule) on the hosted `windows-latest` runner per the §13
  decision + §11.3 checklist — the ONLY remaining functional gap
  (§14.1-§14.2); or (c) re-check §2.6 on the next Flutter upgrade / when
  `flutter/flutter#190903` lands. Audit candidates logged for future runs
  (all Linux-implementable, none P0/P1): CI P3 trio — the nightly cron
  (`0 6 * * *`) also fires a redundant full ubuntu-gate every night because
  ubuntu-gate has no job-level `if:` (`if: github.event_name != 'schedule'`
  would keep it on push/PR/dispatch only), the widget suite executes twice
  per push (`flutter test` + `flutter test test/ui --coverage` — a single
  `flutter test --coverage` would halve it), and `LIBGL_ALWAYS_SOFTWARE=1`
  is scoped to the Xvfb process only, not exported for the app under test
  (`export LIBGL_ALWAYS_SOFTWARE=1` next to `export DISPLAY=` at ci.yaml:127
  and :240 would make the software-GL contract explicit); code P2 trio —
  clock_seam_test.dart:29 `expect(now.year, greaterThanOrEqualTo(2026))`
  asserts against the real wall clock with an absolute year threshold (fails
  on any machine with a pre-2026 clock; a plausibility-only assertion would
  be deterministic), agent_config.dart:551 `resolveApiKey`'s `catch (_)`
  swallows a secure-store read failure silently (caller can't distinguish
  "no key" from "store failed"; log the exception), and
  agent_setup_screen.dart:425-427 `_clearApiKey`'s `catch (_)` swallows a
  secure-store delete failure while the UI already cleared the local
  indicator (surface a SnackBar on delete failure, mirroring the write path
  at :392); docs nits — the "22 test/ui suites" → 23, §11.16 "24 steps/26
  keys" → 26 steps/28 keys, FUTURE_WORK baseline "631/631" → "642/642"
  (or annotate as historical), the dangling "docs/RUNBOOK.md 'Linux
  desktop'" heading ref in FUTURE_WORK.md:346 + ci.yaml:97 (RUNBOOK's
  headless recipe lives under "## Prereqs"), the missing `--direct` alias in
  download_stockfish `--help` Options, and the `0xCAFABE` → `0xCAFEBABE`
  typo in the §9.2 track row. The `dart format` gate (102/127-file churn,
  needs an explicit owner decision) remains open; coverage-artifact
  comparison still needs ≥2 CI runs.
- 2026-10-24Z — CI-PROCESS §11.23: the nightly cron no longer re-runs the
  redundant full ubuntu-gate. The audit log from the §11.22 run flagged this
  as the top Linux-implementable candidate: `on:` in `.github/workflows/
  ci.yaml` includes `schedule` (`0 6 * * *`) — an event created solely for
  the §11.3 windows-nightly gate — but the ubuntu-gate job carried no
  job-level `if:`, so GitHub fired BOTH jobs on every nightly cron: a full
  Linux gate (analyze + test + build + smoke + integration + coverage,
  ~15-20 min) re-ran every night with zero code changes to exercise,
  wasting runner minutes and risking confusing red runs from nothing.
  Fix: the job now carries `if: github.event_name != 'schedule'` (with a
  §11.23 comment). ubuntu-gate still runs on every push to main, on every
  PR, and on manual workflow_dispatch (event_name == 'workflow_dispatch' →
  full CI, both jobs); only the schedule event is skipped, and
  windows-nightly's own `if: github.event_name == 'schedule' || github.event_name
  == 'workflow_dispatch'` is untouched, so the nightly Windows gate is
  unchanged. Job/step counts unchanged (ubuntu-gate 14, windows-nightly
  12); no Dart/test files changed.
  Evidence: strict duplicate-key PyYAML re-parse clean via a node-level
  duplicate-key scan (yaml.compose walk) with the job if-contracts asserted
  in the same script (ubuntu-gate 14 steps + `if: github.event_name !=
  'schedule'`, windows-nightly 12 steps + schedule/dispatch-only `if:`);
  all 14 bash run blocks pass `bash -n` (the sole "failure" is the
  Windows-only §9.1 PowerShell block, per the §11.12 precedent);
  `flutter analyze` → `No issues found! (ran in 2.2s)`;
  full `flutter test` → 642/642 pass (01:55, All tests passed! — no Dart
  changes).
  Push **BLOCKED** (same as every prior run since the credentials audit):
  no GitHub credentials on this host (`git config --get credential.helper`
  empty, no `gh`, no `~/.git-credentials`, no `~/.netrc`, no token in env);
  `git ls-remote origin main` still shows e1749b3, so the local queue
  (~61 commits through this run, including this §11.23 fix) remains
  local-only. Re-run the push once credentials are provisioned.
  Next: (a) re-push the queued local commits once GitHub credentials exist;
  (b) trigger the §11.3 windows-nightly via `workflow_dispatch` (or wait for
  the 06:00 UTC schedule) on the hosted `windows-latest` runner per the §13
  decision + §11.3 checklist — the ONLY remaining functional gap
  (§14.1-§14.2); or (c) re-check §2.6 on the next Flutter upgrade / when
  `flutter/flutter#190903` lands. Remaining Linux-implementable audit
  candidates (none P0/P1): CI P3 #2 — the `flutter test` +
  `flutter test test/ui --coverage` pair could merge into one full-suite
  `flutter test --coverage` (halves test execution; needs an explicit
  decision because it changes the §11.4 lcov coverage semantics from
  test/ui-only to full-suite); CI P3 #3 — `export LIBGL_ALWAYS_SOFTWARE=1`
  next to `export DISPLAY=` at ci.yaml (the software-GL contract is
  currently scoped to the Xvfb process only, not exported for the app under
  test); code P2 trio — clock_seam_test.dart:29's absolute `year >= 2026`
  wall-clock assertion (make deterministic), agent_config.dart:551
  `resolveApiKey`'s silent `catch (_)` (log the secure-store read failure),
  agent_setup_screen.dart:425-427 `_clearApiKey`'s silent `catch (_)`
  (surface a SnackBar on delete failure, mirroring the write path at :392);
  docs nits — "22 test/ui suites" → 23, §11.16 "24 steps/26 keys" →
  26 steps/28 keys, FUTURE_WORK baseline "631/631" → "642/642" (or annotate
  as historical), the dangling "docs/RUNBOOK.md 'Linux desktop'" heading ref
  in FUTURE_WORK.md:346 + ci.yaml:97, the missing `--direct` alias in
  download_stockfish `--help` Options, the `0xCAFABE` → `0xCAFEBABE` typo
  in the §9.2 track row. The `dart format` gate (102/127-file churn, needs
  an explicit owner decision) remains open; coverage-artifact comparison
  still needs ≥2 CI runs.
- 2026-10-24Z — CODE-P2 §11.24: AgentSetupScreen "Clear stored key" no longer
  silently swallows a secure-store delete failure (closes code-P2 #3 from the
  §11.22/§11.23 audit trail — the highest-value Linux-implementable open
  candidate remaining; all FUTURE_WORK.md P0/P1 items are either DONE or
  Windows/external-blocked per §9.1/§9.2/§11.3/§14/§2.6). `agent_setup_screen
  .dart` `_clearApiKey` (was :414-428) cleared the UI state FIRST, then let
  `catch (_)` swallow the `deleteApiKey` error: the screen flipped to "No key
  stored" even when the secret was still in the store — a lie to the user,
  and a later Save with a new key mints a NEW ref (writeApiKey under the new
  ref), orphaning the old secret forever. The write path (`_save`, :389-400)
  had always surfaced store failures as a SnackBar, so Clear was the lone
  silent swallow in the key lifecycle. The fix mirrors the save path: the
  delete runs first; on failure the stored indicator + Clear action are kept
  and a SnackBar `Could not clear the stored API key.` is shown (empty
  `catch (_)` removed — repo convention); on success (or when no ref exists,
  i.e. only an unsaved typed key) the local state clears exactly as before.
  Testability: the screen had a hard-coded `static const SecureKeyStore
  _keyStore` with no seam, and the Clear path had ZERO tests (grep for
  `delete_outline`/`Clear stored key` in the suite returned nothing). Added
  `AgentSetupScreen({..., keyStore})` — an injectable secure-store seam
  defaulting to the platform `SecureKeyStore` (production behavior unchanged;
  the repo's §10.5/§10.6 constructor-seam convention) — and three new tests
  in `test/ui/agent_setup_test.dart` using deterministic fake stores
  (`_StoredKeyStore`, `_FailingDeleteKeyStore`) + an `agentListProvider`
  override seeding an agent with `apiKeyRef`:
  1. edit-mode stored key renders `lock_outline` + the Clear tooltip action;
  2. successful Clear flips the indicator to `lock_open_outlined` and removes
     the action (no SnackBar);
  3. delete failure shows the SnackBar AND keeps `lock_outline` + the action
     (the UI never claims "no key stored" while the secret exists).
  Test-vs-fix correspondence proven empirically: with the OLD swallow logic
  temporarily restored (seam kept), test 3 FAILS (no SnackBar, indicator
  cleared); with the fix it passes.
  Evidence: `flutter analyze` → `No issues found! (ran in 2.3s)` (zero
  errors/warnings/infos); `flutter test test/ui/agent_setup_test.dart` →
  32/32 pass (29 baseline + 3 new); full regression `flutter test` → 645/645
  pass (642 baseline + 3 new, 01:54, All tests passed!). Files changed:
  `lib/src/ui/screens/agent_setup_screen.dart`, `test/ui/agent_setup_test.dart`,
  this track + `docs/FUTURE_WORK.md` (Last updated bumped; per the
  open-items-only rule no new completed-work section).
  Push **BLOCKED** (same as every prior run since the credentials audit):
  no GitHub credentials on this host (`git config --get credential.helper`
  empty, no `gh`, no `~/.git-credentials`, no `~/.netrc`, no token in env);
  `git ls-remote origin main` still shows e1749b3, so the local queue (~62
  commits through this run, including this §11.24 fix) remains local-only.
  Re-run the push once credentials are provisioned.
  Next: (a) re-push the queued local commits once GitHub credentials exist;
  (b) trigger the §11.3 windows-nightly via `workflow_dispatch` (or wait for
  the 06:00 UTC schedule) on the hosted `windows-latest` runner per the §13
  decision + §11.3 checklist — the ONLY remaining functional gap
  (§14.1-§14.2); or (c) re-check §2.6 on the next Flutter upgrade / when
  `flutter/flutter#190903` lands. Remaining Linux-implementable audit
  candidates (none P0/P1): code P2 #1 — clock_seam_test.dart:29's absolute
  `now.year >= 2026` wall-clock assertion (make deterministic); code P2 #2 —
  agent_config.dart:551 `resolveApiKey`'s silent `catch (_)` (log the
  secure-store read failure so callers can distinguish "no key" from "store
  failed"); CI P3 #2 — the `flutter test` + `flutter test test/ui --coverage`
  pair could merge into one full-suite `flutter test --coverage` (halves test
  execution; needs an explicit decision because it changes the §11.4 lcov
  coverage semantics from test/ui-only to full-suite); CI P3 #3 — `export
  LIBGL_ALWAYS_SOFTWARE=1` next to `export DISPLAY=` at ci.yaml (the
  software-GL contract is currently scoped to the Xvfb process only, not
  exported for the app under test); docs nits — "22 test/ui suites" → 23,
  §11.16 "24 steps/26 keys" → 26 steps/28 keys, FUTURE_WORK baseline
  "631/631" → "642/642" (or annotate as historical), the dangling
  "docs/RUNBOOK.md 'Linux desktop'" heading ref in FUTURE_WORK.md:346 +
  ci.yaml:97, the missing `--direct` alias in download_stockfish `--help`
  Options, the `0xCAFABE` → `0xCAFEBABE` typo in the §9.2 track row. The
  `dart format` gate (102/127-file churn, needs an explicit owner decision)
  remains open; coverage-artifact comparison still needs ≥2 CI runs.
- 2026-10-24Z — CODE-P2 §11.25: `resolveApiKey` no longer silently swallows
  secure-store READ failures (closes code-P2 #2 from the §11.22/§11.23 audit
  trail — the read-side sibling of the §11.24 #3 fix and the top remaining
  Linux-implementable audit candidate). `lib/src/agent/agent_config.dart`
  `resolveApiKey` (was :551) used `catch (_)` and returned `''` on any
  secure-store read failure, so an OS-keychain failure (unlock denial,
  corrupt keychain, keychain migration glitch) was indistinguishable from
  "no key stored": a configured OpenAI/Anthropic/Gemini agent with a stored
  key silently degraded to keyless — later turns 401'd with zero
  diagnostics, and Test Connection failed for the wrong reason while the
  real fault sat in the keychain layer. Following the §11.24 precedent (no
  empty catches) and the storage layer's own write-error pattern
  (`LocalAppStore` logs fire-and-forget write failures via `dart:developer`
  and offers `onWriteError`), the read path now: logs the failure via
  `dart:developer` by default (`name: 'resolveApiKey'`, error + stackTrace,
  ref named — never the secret) or hands it to a new optional `onReadError`
  sink; the resolver still never throws and returns `''` on failure, so the
  documented keyless-backend contract (`turn_provider_test.dart`'s
  "a reader that throws degrades to an empty key instead of crashing" test
  and `testAgentConnection`'s "Never throws" doc) is unchanged. New
  `test/resolve_api_key_test.dart` (6 deterministic offline tests):
  1. a valid ref resolves the stored secret; 2. no ref short-circuits to ''
  without touching the store OR invoking `onReadError`; 3. an empty ref
  short-circuits the same way; 4. a store holding no secret returns ''
  quietly without invoking `onReadError`; 5. a throwing store degrades to
  '' instead of crashing (default logging path); 6. a throwing store
  reports ref + error + stackTrace to `onReadError` and still returns ''.
  The diff is exactly the audit note: log the read failure so callers can
  distinguish "no key" from "store failed"; no API consumers changed
  (`resolveTurnProvider` / `testAgentConnection` use the default log).
  Evidence: `flutter analyze` → `No issues found! (ran in 2.1s)` (zero
  errors/warnings/infos); `flutter test test/resolve_api_key_test.dart
  test/turn_provider_test.dart test/connection_tester_seam_test.dart` →
  20/20 pass (6 new + 14 related); full regression `flutter test` → 651/651
  pass (645 baseline + 6 new, 01:57, All tests passed!). Files changed:
  `lib/src/agent/agent_config.dart`, `test/resolve_api_key_test.dart`,
  this track + `docs/FUTURE_WORK.md` (Last updated bumped; per the
  open-items-only rule no new completed-work section — no open FUTURE_WORK
  item was touched, §9.1/§9.2/§11.3/§14 remain Windows-blocked, §2.6
  upstream-external).
  Commit: f28b7a5.
  Push **BLOCKED** (same as every prior run since the credentials audit):
  no GitHub credentials on this host (`git config --get credential.helper`
  empty, no `gh`, no `~/.git-credentials`, no `~/.netrc`, no token in env);
  `git ls-remote origin main` still shows e1749b3, so the local queue (~68
  commits through this run, including this §11.25 fix) remains local-only.
  Re-run the push once credentials are provisioned.
  Next: (a) re-push the queued local commits once GitHub credentials exist;
  (b) trigger the §11.3 windows-nightly via `workflow_dispatch` (or wait
  for the 06:00 UTC schedule) on the hosted `windows-latest` runner per the
  §13 decision + §11.3 checklist — the ONLY remaining functional gap
  (§14.1-§14.2); or (c) re-check §2.6 on the next Flutter upgrade / when
  `flutter/flutter#190903` lands. Remaining Linux-implementable audit
  candidates (none P0/P1): code P2 #1 — clock_seam_test.dart:29's absolute
  `now.year >= 2026` wall-clock assertion (make deterministic); CI P3 #2 —
  the `flutter test` + `flutter test test/ui --coverage` pair could merge
  into one full-suite `flutter test --coverage` (halves test execution;
  needs an explicit decision because it changes the §11.4 lcov coverage
  semantics from test/ui-only to full-suite); CI P3 #3 — `export
  LIBGL_ALWAYS_SOFTWARE=1` next to `export DISPLAY=` at ci.yaml (the
  software-GL contract is currently scoped to the Xvfb process only, not
  exported for the app under test); docs nits — "22 test/ui suites" → 23,
  §11.16 "24 steps/26 keys" → 26 steps/28 keys, FUTURE_WORK baseline
  "631/631" → "642/642" (or annotate as historical), the dangling
  "docs/RUNBOOK.md 'Linux desktop'" heading ref in FUTURE_WORK.md:346 +
  ci.yaml:97, the missing `--direct` alias in download_stockfish `--help`
  Options, the `0xCAFABE` → `0xCAFEBABE` typo in the §9.2 track row. The
  `dart format` gate (102/127-file churn, needs an explicit owner decision)
  remains open; coverage-artifact comparison still needs ≥2 CI runs.
- 2026-10-24Z — TEST-DETERMINISM §11.26: `clock_seam_test.dart` no longer
  asserts against an absolute wall-clock year (closes code-P2 #1 from the
  §11.22/§11.23/§11.24/§11.25 audit trail — the last remaining code-P2
  candidate; all FUTURE_WORK.md P0/P1 items are DONE or Windows/external-
  blocked per §9.1/§9.2/§11.3/§14/§2.6). The "defaults to DateTime.now"
  test (clock_seam_test.dart:20-30) ended with
  `expect(now.year, greaterThanOrEqualTo(2026))` — a real wall-clock
  assertion with an ABSOLUTE year threshold, so any machine with a pre-2026
  clock fails it, and the suite is pinned to a point in time for no reason.
  The default clock's whole contract is "resolves to the real wall clock",
  which needs no absolute epoch reference at all. The assertion is now a
  relative plausibility check: `now` (the default clock's output) is
  compared to an immediately adjacent `DateTime.now()` reading —
  `expect(now.difference(reference).inSeconds.abs(), lessThanOrEqualTo(300))`.
  `DateTime.difference` normalizes the local/UTC offset (so the
  platform-dependent now/UTC question the old comment worried about is
  handled by the API itself), there is no absolute year or epoch
  dependency, and the test still proves the default resolves to the real
  wall clock exactly as before. Test-only change — no lib/ code changed;
  the other seven tests in the file (fixed-UTC override, ms-epoch, toUtc
  identity, 31-bit mask, shared default identity, nested-scope shadowing,
  non-determinism bound) are untouched, as are all clock-seam consumers.
  Evidence: `flutter analyze` → `No issues found! (ran in 2.2s)` (zero
  errors/warnings/infos); `flutter test test/clock_seam_test.dart` → 8/8
  pass; clock-seam consumers `flutter test test/ui/watch_screen_test.dart
  test/ui/arena_screen_test.dart test/ui/deterministic_deep_states_test.dart
  test/ui/scrub_shortcuts_test.dart test/ui/arena_variant_review_test.dart`
  → 84/84 pass; full regression `flutter test` → 651/651 pass (01:54, All
  tests passed! — count unchanged, test edit only). Files changed:
  `test/clock_seam_test.dart`, this track + `docs/FUTURE_WORK.md` (Last
  updated bumped; per the open-items-only rule no new completed-work section
  — no open FUTURE_WORK item was touched, §9.1/§9.2/§11.3/§14 remain
  Windows-blocked, §2.6 upstream-external).
  Commit: 2965f2e (recorded in a follow-up track commit per the §13 precedent).
  Push **BLOCKED** (same as every prior run since the credentials audit):
  no GitHub credentials on this host (`git config --get credential.helper`
  empty, no `gh`, no `~/.git-credentials`, no `~/.netrc`, no token in env);
  `git ls-remote origin main` still shows e1749b3, so the local queue (~69
  commits through this run, including this §11.26 fix) remains local-only.
  Re-run the push once credentials are provisioned.
  Next: (a) re-push the queued local commits once GitHub credentials exist;
  (b) trigger the §11.3 windows-nightly via `workflow_dispatch` (or wait
  for the 06:00 UTC schedule) on the hosted `windows-latest` runner per the
  §13 decision + §11.3 checklist — the ONLY remaining functional gap
  (§14.1-§14.2); or (c) re-check §2.6 on the next Flutter upgrade / when
  `flutter/flutter#190903` lands. Remaining Linux-implementable audit
  candidates (none P0/P1 — the code-P2 trio is now fully closed): CI P3 #2 —
  the `flutter test` + `flutter test test/ui --coverage` pair could merge
  into one full-suite `flutter test --coverage` (halves test execution;
  needs an explicit decision because it changes the §11.4 lcov coverage
  semantics from test/ui-only to full-suite); CI P3 #3 — `export
  LIBGL_ALWAYS_SOFTWARE=1` next to `export DISPLAY=` at ci.yaml (the
  software-GL contract is currently scoped to the Xvfb process only, not
  exported for the app under test); docs nits — "22 test/ui suites" → 23,
  §11.16 "24 steps/26 keys" → 26 steps/28 keys, FUTURE_WORK baseline
  "631/631" → "642/642" (or annotate as historical), the dangling
  "docs/RUNBOOK.md 'Linux desktop'" heading ref in FUTURE_WORK.md:346 +
  ci.yaml:97, the missing `--direct` alias in download_stockfish `--help`
  Options, the `0xCAFABE` → `0xCAFEBABE` typo in the §9.2 track row. The
  `dart format` gate (102/127-file churn, needs an explicit owner decision)
  remains open; coverage-artifact comparison still needs ≥2 CI runs.
- 2026-10-24Z — CI-PROCESS §11.27: the ubuntu-gate's software-GL contract
  now reaches the processes that actually render (closes audit candidate
  CI P3 #3 from the §11.23/§11.24/§11.25/§11.26 audit trail; all
  FUTURE_WORK.md P0/P1 items are DONE or Windows/external-blocked per
  §9.1/§9.2/§11.3/§14/§2.6). Both ubuntu-gate Xvfb display steps — the
  §11.6/§11.15 "Smoke start Linux release (Xvfb)" step (:77) and the
  §11.11 "Integration test on Linux" step (:79) — prefixed
  `LIBGL_ALWAYS_SOFTWARE=1` ONLY to the Xvfb launch line. An env-prefix on
  `Xvfb ... &` scopes the variable to the Xvfb process alone, so the two
  processes that actually render under that display — the release binary
  in the smoke step (`./build/linux/x64/release/bundle/llm_chess_arena`,
  the §11.15 subject) and the `flutter test integration_test/... -d
  linux` suite (whose app-under-test renders too) — inherited NOTHING. On
  a runner where a GPU driver is reachable, the app could silently pick
  hardware GL instead of llvmpipe, breaking the smoke's reproducibility:
  §11.15's window-wait budget (15s + 75×1s) was measured under software
  GL, where the first frame takes ~26-52s — and the whole gate exists to
  catch "alive but never properly rendered", which the GL backend entirely
  determines. The documented headless recipe (docs/RUNBOOK.md "##
  Prereqs": `DISPLAY=:91 LIBGL_ALWAYS_SOFTWARE=1
  ./build/linux/x64/release/bundle/llm_chess_arena`) exports the variable
  FOR THE APP; CI was the lone deviation. Files changed:
  `.github/workflows/ci.yaml` — both steps now carry
  `export LIBGL_ALWAYS_SOFTWARE=1` immediately next to
  `export DISPLAY=:77` / `export DISPLAY=:79` (with a §11.27 comment on
  each explaining the app-reachability contract and the RUNBOOK match),
  and the now-redundant `LIBGL_ALWAYS_SOFTWARE=1 ` prefix is removed from
  both Xvfb launch lines. Step counts unchanged (ubuntu-gate 14,
  windows-nightly 12); no Dart/test files changed.
  `docs/FUTURE_WORK.md` — header bumped only (no open item touched; per
  the open-items-only rule no new completed-work section — §11.27 is not
  an open item; the Windows/external items remain listed as blocked).
  `automation-track.md` — header + this Run Log entry (no Roadmap row
  exists for §11.27; per protocol the Run Log is the record).
  Evidence: strict duplicate-key PyYAML re-parse clean with the §11.27
  contract asserted programmatically (both steps contain
  `export LIBGL_ALWAYS_SOFTWARE=1`; neither contains the legacy
  `LIBGL_ALWAYS_SOFTWARE=1 Xvfb` prefix; the app-launch and
  `flutter test integration_test/...` lines are intact; ubuntu-gate 14 +
  windows-nightly 12 steps; 28 timeout-minutes keys = 26 steps + 2 jobs);
  all 14 bash run blocks pass `bash -n` (the two "failures" are the
  Windows-only §9.1/§9.2 PowerShell blocks, Windows-only by design per
  the §11.12 precedent); `flutter analyze` → `No issues found! (ran in
  2.2s)`; the FULL modified smoke block run verbatim (extracted from the
  workflow, :77 → fresh :113 since the pre-existing leaked :77 server
  still occupies the real display — itself a live §11.14 refusal demo on
  the earlier probe) against the real Linux release bundle →
  `smoke ok: release binary alive after 15s and window mapped (title
  llm_chess_arena, 1278x720) under Xvfb + openbox`, exit 0, with NO :113
  Xvfb and no release-app orphan left behind; the §11.11 headless suite
  under the exported variable (fresh :117) → 12/12 pass (00:33, All
  tests passed!), exit 0, no :117 orphan; full regression `flutter test`
  → 651/651 pass (01:54, All tests passed! — no Dart changes, workflow
  edit only). `git status --short` confirms only the workflow + the two
  track docs changed.
  Commit: fd02e7d.
  Push **BLOCKED** (same as every prior run since the credentials audit):
  no GitHub credentials on this host (`git config --get credential.helper`
  empty, no `gh`, no `~/.git-credentials`, no `~/.netrc`, no token in
  env); `git ls-remote origin main` still shows e1749b3, so the local
  queue (~70 commits through this run, including this §11.27 fix) remains
  local-only. Re-run the push once credentials are provisioned.
  Next: (a) re-push the queued local commits once GitHub credentials
  exist; (b) trigger the §11.3 windows-nightly via `workflow_dispatch`
  (or wait for the 06:00 UTC schedule) on the hosted `windows-latest`
  runner per the §13 decision + §11.3 checklist — the ONLY remaining
  functional gap (§14.1-§14.2); or (c) re-check §2.6 on the next Flutter
  upgrade / when `flutter/flutter#190903` lands. Remaining
  Linux-implementable audit candidates (none P0/P1): CI P3 #2 — the
  `flutter test` + `flutter test test/ui --coverage` pair could merge
  into one full-suite `flutter test --coverage` (halves test execution;
  needs an explicit decision because it changes the §11.4 lcov coverage
  semantics from test/ui-only to full-suite); docs nits — "22 test/ui
  suites" → 23 (automation-track.md:122), §11.16 "24 steps/26 keys" →
  26 steps/28 keys, FUTURE_WORK baseline "631/631" → "651/651"
  (re-measured this run: the live "Verified baseline" block at
  FUTURE_WORK.md:293-296 still says 631/631 while the suite is now
  651/651), the dangling "docs/RUNBOOK.md 'Linux desktop'" heading ref in
  FUTURE_WORK.md:443 + ci.yaml:106 (RUNBOOK's headless recipe lives under
  "## Prereqs"), the missing `--direct` alias in download_stockfish
  `--help` Options, and the `0xCAFABE` → `0xCAFEBABE` typo in the §9.2
  track row (automation-track.md:332). The `dart format` gate
  (102/127-file churn, needs an explicit owner decision) remains open;
  coverage-artifact comparison still needs ≥2 CI runs.
- 2026-10-24Z — DOCS-NITS §11.28: the last Linux-implementable docs-nits
  batch from the §11.22/§11.23 audit trail is closed (all FUTURE_WORK.md
  P0/P1 items are DONE or Windows/external-blocked per
  §9.1/§9.2/§11.3/§14/§2.6; CI P3 #2 — merging the `flutter test` +
  `flutter test test/ui --coverage` pair into one full-suite
  `flutter test --coverage` — stays open pending the explicit §11.4-owner
  decision the audit recorded, because it changes the lcov coverage
  semantics from test/ui-only to full-suite). Docs-accuracy pass, zero
  open-item code changes. Each flagged nit verified before fixing:
  1. **"22 `test/ui/` suites" → 23** — the two §11.21 docs-accuracy
     entries (this file: the §11.21 header summary and the full Run Log
     entry) said "the suite exists — 642 tests, 22 `test/ui/` suites".
     642 was the then-live count, but the suite count was already 23:
     `test/ui/arena_variant_review_test.dart` shipped 2026-10-23, before
     §11.21. `ls test/ui/*_test.dart | wc -l` → 23. Both instances
     corrected to 23.
  2. **§11.16 "24 steps/26 keys" → "26 steps/28 keys"** — §11.16's
     evidence (FUTURE_WORK §11.16 + this file's §11.16 Run Log entry)
     counted 24 steps (ubuntu 14 + windows 10) with 26 timeout keys
     (24 + 2 jobs) — correct AT §11.16 time, stale since §11.17 added
     the two windows engine steps (windows-nightly 10 → 12). The §11.27
     evidence programmatically asserted the current contract: 26 steps
     (14 + 12) / 28 timeout keys (26 steps + 2 jobs). All stale count
     instances fixed to 26 steps/28 keys (FUTURE_WORK §11.16 prose x2 +
     evidence line; this file's header chain, §11.16 Run Log entry's
     "ALL 24 steps" line + step-count parenthetical + evidence line).
  3. **FUTURE_WORK "Verified baseline" 631/631 → 651/651** — the live
     baseline block (FUTURE_WORK.md "Verified baseline") still said
     `flutter test` — 631/631 while the suite is now 651/651 (re-measured
     this run and every run since §11.25). Updated; the block's other
     lines (0 issues, release build + Xvfb start, §12 18/18, §6 12
     suites) were re-verified as still true.
  4. **Dangling `docs/RUNBOOK.md "Linux desktop"` refs** — two places
     cite a RUNBOOK heading that does not exist: FUTURE_WORK §11.6
     ("xvfb + openbox are the headless-start recipe from
     `docs/RUNBOOK.md` "Linux desktop"") and the ci.yaml "Install Linux
     desktop build deps" step comment. RUNBOOK.md's headings are
     `## Prereqs / Commands / Demo without keys / Adding a real model /
     Flutter upgrade gate / Troubleshooting` — both the build-deps line
     ("Linux desktop needs `clang cmake ...`") and the documented
     Xvfb + `LIBGL_ALWAYS_SOFTWARE=1` headless-start recipe live under
     `## Prereqs`. Both refs now say `docs/RUNBOOK.md` "Prereqs".
  5. **`--direct` alias undocumented in download_stockfish `--help`** —
     the CLI parser accepts `--direct` as an alias for `--no-proxy`
     (tool/download_stockfish.dart:912), but the `--help` Options block
     listed only `--no-proxy`. Help text now documents both. No behavior
     change; no test pins the help output (grep: nothing in test/
     references `--no-proxy`/`--direct`/help text).
  6. **`0xCAFABE` → `0xCAFEBABE` in the §9.2 track row** — the Roadmap
     row for `tool/windows_accessibility_smoke.ps1` said
     `-Seed (default 0xCAFABE)`; the script's actual default is
     `0xCAFEBABE` (tool/windows_accessibility_smoke.ps1:30). Corrected.
  Evidence: `flutter analyze` → `No issues found! (ran in 2.2s)` (zero
  errors/warnings/infos; the help-text string edit is Dart, everything
  else is docs/YAML comments); full regression `flutter test` → 651/651
  pass (01:55, All tests passed! — no behavior change); ci.yaml §11.28
  contract asserted programmatically (ubuntu-gate 14 + windows-nightly 12
  steps, 28 timeout-minutes keys, both RUNBOOK "Prereqs" refs present,
  zero "Linux desktop" heading refs); `dart run
  tool/download_stockfish.dart --help` prints the Options block including
  `--direct            alias for --no-proxy`; `ls test/ui/*_test.dart`
  → 23; `grep -c "timeout-minutes"` → 28; `grep -n "0xCAFEBABE"
  tool/windows_accessibility_smoke.ps1` → line 30.
  Files changed: `tool/download_stockfish.dart` (help text only),
  `.github/workflows/ci.yaml` (comment ref only), `docs/FUTURE_WORK.md`
  (header + nit fixes; Last updated bumped; per the open-items-only rule
  no new completed-work section — no open FUTURE_WORK item was touched,
  §9.1/§9.2/§11.3/§14 remain Windows-blocked, §2.6 upstream-external),
  this track (header + nit fixes + this Run Log entry).
  Commit: 575a4a6 (recorded in a follow-up track commit per the §13 precedent).
  Push **BLOCKED** (same as every prior run since the credentials audit):
  no GitHub credentials on this host (`git config --get credential.helper`
  empty, no `gh`, no `~/.git-credentials`, no `~/.netrc`, no token in
  env); `git ls-remote origin main` still shows e1749b3, so the local
  queue (~71 commits through this run, including this §11.28 pass)
  remains local-only. Re-run the push once credentials are provisioned.
  Next: (a) re-push the queued local commits once GitHub credentials
  exist; (b) trigger the §11.3 windows-nightly via `workflow_dispatch`
  (or wait for the 06:00 UTC schedule) on the hosted `windows-latest`
  runner per the §13 decision + §11.3 checklist — the ONLY remaining
  functional gap (§14.1-§14.2); or (c) re-check §2.6 on the next Flutter
  upgrade / when `flutter/flutter#190903` lands. CI P3 #2 (coverage
  merge) stays open pending the §11.4-owner decision; the `dart format`
  gate (102/127-file churn, needs an explicit owner decision) remains
  open; coverage-artifact comparison still needs ≥2 CI runs.
- 2026-10-24Z — NO-ACTIONABLE-ITEM §11.29: the hourly terminal branch —
  no open `docs/FUTURE_WORK.md` item is implementable-and-verifiable on
  this Linux host. Method: instead of guessing, an independent parallel
  subagent audit ran a full FUTURE_WORK.md section inventory (`^#{1,4}`
  grep, every section read), the automation-track.md tail (last 3
  run-log entries' "Next:"/candidate clauses), a marker grep
  (TODO/FIXME/HACK/XXX/`open`/`remaining` across lib/ test/ tool/
  integration_test/ .github/ — zero real unfinished-work markers; the
  only skips are the intentional e2e engine self-gate at
  test/e2e_smoke_test.dart:126-137), and a docs/ roadmap scan (RUNBOOK,
  ENGINE_RUNTIME, SERVER_ROADMAP, CHESS_ENGINE, VARIANT, ARCHITECTURE).
  Verdict: (a) CONFIRMED — every open item falls in the already-logged
  blocked/external/owner-decision set. §9.1/§9.2/§11.3/§14.1-§14.2 are
  Windows-native (log as blocked); §2.6 is upstream-external (local SDK
  Flutter 3.47.6, flutter/flutter#190903 still unmerged — the RUNBOOK
  upgrade gate is the sanctioned re-check point); CI P3 #2 (the
  `flutter test` + `test/ui --coverage` pair → one full-suite
  `flutter test --coverage`, halves test execution) stays open pending
  the explicit §11.4-owner decision the §11.22/§11.23 audit recorded
  (it changes lcov coverage semantics from test/ui-only to full-suite);
  the `dart format` gate (102/127-file churn) stays open pending an
  explicit owner decision; coverage-artifact comparison needs ≥2 real CI
  runs (no push creds → no runs); and the 75-commit local queue cannot
  be pushed. The audit's only additional unchecked items were
  ENGINE_RUNTIME.md:144-146/210-212 GPLv3 source-offer checkboxes
  (release-gated, no release exists) and backend/SERVER_ROADMAP.md
  (deferred by decision, ARCHITECTURE.md:49-52) — both correctly not
  open items. Zero code/test/workflow changes this run.
  Evidence: `flutter analyze` → `No issues found! (ran in 2.3s)` (zero
  errors/warnings/infos); full regression `flutter test` → 651/651 pass
  (02:06, All tests passed!); `git rev-list --count origin/main..HEAD` →
  75; working tree clean before edits (`git status --short` empty).
  Files changed: this track (header + this Run Log entry) and
  `docs/FUTURE_WORK.md` (Last updated bumped; per the open-items-only
  rule no new completed-work section — no open FUTURE_WORK item was
  touched, §9.1/§9.2/§11.3/§14 remain Windows-blocked, §2.6
  upstream-external).
  Commit: 3fca2bb (recorded in a follow-up track commit per the §13
  precedent).
  Push **BLOCKED** (same as every prior run since the credentials audit):
  no GitHub credentials on this host (`git config --get credential.helper`
  empty, no `gh`, no `~/.git-credentials`, no `~/.netrc`, no token in
  env; `git push origin main` → `fatal: could not read Username for
  'https://github.com'`); `git ls-remote origin main` still shows
  e1749b3, so the local queue (76 commits through this run) remains
  local-only. Re-run the push once credentials are provisioned.
  Next: (a) re-push the queued local commits once GitHub credentials
  exist; (b) trigger the §11.3 windows-nightly via `workflow_dispatch`
  (or wait for the 06:00 UTC schedule) on the hosted `windows-latest`
  runner per the §13 decision + §11.3 checklist — the ONLY remaining
  functional gap (§14.1-§14.2); or (c) re-check §2.6 on the next Flutter
  upgrade / when `flutter/flutter#190903` lands. CI P3 #2 (coverage
  merge) stays open pending the §11.4-owner decision; the `dart format`
  gate (102/127-file churn, needs an explicit owner decision) remains
  open; coverage-artifact comparison still needs ≥2 CI runs.
- 2026-10-24Z — CI §11.30: the windows-nightly "Upload smoke artifacts"
  step now carries `continue-on-error: true` — §11.22's defect class
  finally fixed on its twin step, found by THIS run's independent
  three-pronged audit (see below). Prior runs (§11.22–§11.29) declared
  the §11.22 fix complete but its byte-for-byte twin on the other job —
  `ci.yaml:481-490`, the `windows-nightly` "Upload smoke artifacts"
  step (`if: always()` + `actions/upload-artifact@v4`, purely
  diagnostic `uia_smoke_output.txt` / `event_viewer_excerpt.txt`) — was
  never granted `continue-on-error`, so a transient
  `actions/upload-artifact@v4` backend failure (the documented Actions
  failure mode §11.22's own comment cites) would still have failed the
  ENTIRE windows-nightly job on a non-gating concern even though every
  real gate (build, unit/widget tests, §9.1 integration, §9.2 UIA
  smoke) passed. The track records no decision to keep the nightly
  reddening — the twin was simply missed. The step now matches the
  §11.22 contract exactly: `continue-on-error: true` + a §11.30 comment
  cross-referencing §11.22, plus `if-no-files-found: warn` for the
  missing-files case (the §11.22 upload already had it). No Dart/test
  files changed — workflow only.
  Method: instead of trusting the §11.29 terminal verdict, an
  independent three-pronged parallel subagent audit ran this run:
  (1) full FUTURE_WORK.md section + checkbox + open-sounding-keyword
  inventory — confirms the two §14.1/§14.2 unchecked boxes and every
  other open §9/§11.3/§2.6 item remain Windows-native or
  upstream-external (flutter/flutter#190903 re-checked live this run:
  `merged: false`, updated 2026-10-21 — still no stable contains the
  fix; the RUNBOOK upgrade gate is the sanctioned re-check point);
  (2) a full-repo unfinished-marker scan (TODO/FIXME/HACK/XXX,
  UnimplementedError, empty catches, test skips, no-op bodies) — zero
  actionable hits; every hit is a deliberate documented design decision
  (WintrChessAdapter RESERVED, UnsupportedError platform gates, engine
  binary placeholders), the intentional e2e engine self-gate skip
  (test/e2e_smoke_test.dart), or scaffold TODOs outside lib/test; and
  (3) a ci.yaml workflow audit with strict duplicate-key PyYAML
  re-parse, step-count/timeout-key assertions, and `bash -n` on every
  run block — which surfaced the §11.30 defect above; everything else
  checked clean (14/12 step counts, 28 timeout-minutes keys, all
  §11.21–§11.27 guards present). Verdict: the §11.29 "no actionable
  item" claim was nearly right but NOT complete — this one real
  Linux-verifiable CI process fix existed and is now shipped. CI P3 #2
  (coverage merge) and the `dart format` gate still await their
  explicit owner decisions; coverage-artifact comparison needs ≥2 real
  CI runs; §9.1/§9.2/§11.3/§14.1-§14.2 remain Windows-blocked; §2.6
  upstream-external.
  Evidence: workflow re-parses clean via a strict duplicate-key loader
  (ubuntu-gate 14 steps, windows-nightly 12 — counts unchanged;
  continue-on-error steps now ubuntu-gate 2 + windows-nightly 1; 28
  timeout-minutes keys intact); all 14 bash run blocks pass `bash -n`
  (the sole "failures" are the two Windows-only §9.1/§9.2 PowerShell
  blocks, per the §11.12 precedent); `flutter analyze` → `No issues
  found! (ran in 2.4s)` (zero errors/warnings/infos); full regression
  `flutter test` → 651/651 pass (02:27, All tests passed! — no Dart
  changes). `git status --short` before edits was clean; queue count
  re-measured: `git rev-list --count origin/main..HEAD` → 77 (the
  header's "75" predates the §11.29 two-commit pair; same direction).
  Files changed: `.github/workflows/ci.yaml` (one step), this track
  (header + this Run Log entry), `docs/FUTURE_WORK.md` (Last updated
  bumped; §11.3's in-progress "Process fixes shipped" list gained the
  §11.30 bullet in place; per the open-items-only rule no new
  completed-work section — §11.3 itself stays open as Windows-awaiting).
  Commit: e9886c8 (recorded in a follow-up track commit per the §13
  precedent).
  Push **BLOCKED** (same as every prior run since the credentials audit):
  no GitHub credentials on this host (`git config --get credential.helper`
  empty, no `gh`, no `~/.git-credentials`, no `~/.netrc`, no token in
  env); `git ls-remote origin main` still shows e1749b3, so the local
  queue (~78 commits through this run) remains local-only. Re-run the
  push once credentials are provisioned.
  Next: (a) re-push the queued local commits once GitHub credentials
  exist; (b) trigger the §11.3 windows-nightly via `workflow_dispatch`
  (or wait for the 06:00 UTC schedule) on the hosted `windows-latest`
  runner per the §13 decision + §11.3 checklist — the ONLY remaining
  functional gap (§14.1-§14.2); or (c) re-check §2.6 on the next Flutter
  upgrade / when `flutter/flutter#190903` lands. CI P3 #2 (coverage
  merge) stays open pending the §11.4-owner decision; the `dart format`
  gate (102/127-file churn, needs an explicit owner decision) remains
  open; coverage-artifact comparison still needs ≥2 CI runs.
- 2026-10-24Z — CI §11.31: CI P3 #2 CLOSED — the ubuntu-gate's
  `flutter test` + `flutter test test/ui --coverage` pair is merged into
  ONE full-suite `flutter test --coverage` step, making the §11.4-owner
  decision the §11.29/§11.30 audits recorded as pending. Before: the
  interaction-matrix suite ran TWICE per push (once in the hard-gating
  `flutter test`, once again in the non-gating "Test coverage" step with
  `continue-on-error: true`), and the §11.4 lcov artifact covered only
  test/ui. After: one gating step "Test (full suite + coverage, §11.4
  CI-P3#2 merge)" runs `flutter test --coverage` — it gates on the TEST
  results and produces `coverage/lcov.info` as a byproduct, consumed by
  the unchanged §11.22 upload step (`if: always()` +
  `continue-on-error: true` + `if-no-files-found: warn`), so every
  artifact-level failure (missing lcov on a red/aborted Test run, upload
  backend) still can never redden the gate. The lcov semantics widen
  from test/ui-only to full-suite, measured on this host: the old
  test/ui-only lcov had 66 SF entries, the merged full-suite lcov has 70
  — the delta is `lib/src/chess/san.dart`, `lib/src/storage/
  local_store.dart`, `lib/src/storage/redaction.dart`,
  `lib/src/storage/storage_reports.dart`, files exercised only by
  non-test/ui unit suites. Execution-time saving measured on this host:
  old pair 01:53 (`flutter test`) + 01:45 (`flutter test test/ui
  --coverage`) ≈ 3m38s; merged `flutter test --coverage` → 02:04
  (~48% less test-execution wall time per push). Accepted residual,
  documented in the step comment: a coverage-collection failure with all
  tests green would now fail the same step that runs the tests (the old
  run step's continue-on-error is absorbed) — a class unobserved in
  practice with standard flutter tooling, surfacing as a visible step
  error; every artifact-level failure stays non-gating per §11.22.
  ubuntu-gate drops 14 → 13 steps (the "Test coverage" step is gone;
  the merged Test step replaced the plain Test step); windows-nightly
  unchanged at 12. No Dart/test files changed.
  Method: baseline re-verified first (`flutter analyze` →
  `No issues found!`; full `flutter test` → 651/651 pass), then the
  merged command was proven empirically on this host BEFORE the workflow
  edit — `flutter test --coverage` → 651/651 pass (02:04) with
  coverage/lcov.info generated (10,774 lines / 70 SF entries spanning
  all lib/ modules, not just test/ui). The §11.4 contract text in
  FUTURE_WORK.md was updated in place to the new mechanism (this run
  IS the recorded §11.4-owner decision); the historical §11.x section
  step-count narratives are unchanged.
  Evidence: `flutter analyze` → `No issues found! (ran in 2.3s)` (zero
  errors/warnings/infos); full `flutter test` → 651/651 pass (01:53, All
  tests passed!); merged `flutter test --coverage` → 651/651 pass (02:04,
  coverage/lcov.info generated); workflow re-parses clean via a strict
  duplicate-key PyYAML loader (ubuntu-gate 13 steps + windows-nightly 12
  — was 14/12; continue-on-error steps now ubuntu-gate 1 +
  windows-nightly 1; 27 timeout-minutes keys = 25 steps + 2 jobs, every
  step bounded); all 13 bash run blocks pass `bash -n` (the 2
  "failures" are the two Windows-only §9.1/§9.2 PowerShell blocks, per
  the §11.12 precedent). Files changed: `.github/workflows/ci.yaml`
  (one step merged, one step deleted, §11.22 upload comment updated),
  this track (header + this Run Log entry), `docs/FUTURE_WORK.md` (Last
  updated bumped; §11.4 mechanism updated in place; CI P3 #2 removed
  from the pending-owner list — per the open-items-only rule no new
  completed-work section).
  Commit: 0ada33c (recorded in a follow-up track commit per the §13
  precedent).
  Push **BLOCKED** (same as every prior run since the credentials
  audit): no GitHub credentials on this host (`git config --get
  credential.helper` empty, no `gh`, no `~/.git-credentials`, no
  `~/.netrc`, no token in env); `git ls-remote origin main` still shows
  e1749b3, so the local queue (~80 commits through this run) remains
  local-only. Re-run the push once credentials are provisioned.
  Next: (a) re-push the queued local commits once GitHub credentials
  exist; (b) trigger the §11.3 windows-nightly via `workflow_dispatch`
  (or wait for the 06:00 UTC schedule) on the hosted `windows-latest`
  runner per the §13 decision + §11.3 checklist — the ONLY remaining
  functional gap (§14.1-§14.2); or (c) re-check §2.6 on the next
  Flutter upgrade / when `flutter/flutter#190903` lands. The `dart
  format` gate (102/127-file churn, needs an explicit owner decision)
  remains open; coverage-artifact comparison still needs ≥2 real CI
  runs; CI P3 #2 is now closed — no Linux-implementable process items
  remain open.
- 2026-10-24Z — CI §11.31 (follow-up, docs): the §11.31 entry above
  now records its commit hash (`Commit: 0ada33c`) per the
  §13/§11.30 precedent, and the local queue count is corrected to ~80
  commits through that commit (`git rev-list --count origin/main..HEAD`
  → 80). No functional changes — pure track accuracy.
- 2026-10-24Z — CI §11.32 (UIA-smoke Event Viewer excerpt abort on the
  no-matching-events failure class). A fresh three-way subagent audit
  (CI workflow, code/test markers, docs cross-references) confirmed the
  workflow's hardening is real — this was the ONE remaining defect it
  produced, and it is on the §11.3 P0 gate's diagnostics path. The
  "Run UIA smoke (§9.2)" failure branch exports the Event Viewer
  excerpt with `Get-WinEvent -FilterHashtable @{LogName='Application';
  StartTime=...}`. On the §9.2 NON-crash failure class (control count
  < 40, uninvocable controls — everything except the 0xC0000005 crash
  path) no fresh Application-log event exists, so Get-WinEvent writes
  a `NoMatchingEventsFound` NON-terminating error. This run block does
  NOT override `$ErrorActionPreference` (the §9.1 integration block
  sets `"Continue"` at its top; the UIA block deliberately stays
  strict), so the runner wrapper's prepended `'stop'` escalated that
  error to terminating and ABORTED the script before the `::error::`
  line and before `Exit $LASTEXITCODE` — the smoke's documented §9.2
  exit-code semantics (0/1/2, "2=crash detected in Event Viewer") were
  lost at the step level (degraded to 1 from the terminating error)
  and the excerpt carried no Event Viewer data exactly when the §11.30
  diagnostic artifacts are needed. Fix: the command now ends
  `-ErrorAction SilentlyContinue` so the expected no-match case
  respects the pipeline (empty excerpt, still uploaded via the §11.30
  step's `if-no-files-found: warn`); strictness elsewhere is
  unchanged, and on the crash class the fix is inert (identical
  export). Windows-only execution path — no Linux gate impact; no
  Dart/test files changed.
  Method: baseline re-verified first (`flutter analyze` → `No issues
  found!`; full `flutter test` → 651/651 pass, 01:52, All tests
  passed!), then — because this changes a Windows-only PowerShell
  block whose syntax `bash -n` cannot check — real PowerShell 7.6.8
  was installed user-local (`~/sdk/pwsh`, from the official GitHub
  tarball, reversible; kept for future nightly-workflow runs) and the
  ACTUAL edited block (extracted from the working-tree ci.yaml) was
  syntax-verified via `[System.Management.Automation.Language.Parser]::
  ParseInput` (0 parse errors) and `[scriptblock]::Create`. The
  abort-vs-survive semantics were then proven empirically: verbatim
  failure branches from `git show HEAD:...` (OLD) vs the working tree
  (NEW), each run under the runner wrapper's prepended
  `$ErrorActionPreference='stop'` with a `[CmdletBinding()]`
  `Write-Error` stub reproducing the exact non-terminating
  NoMatchingEventsFound error class. No-match class — OLD: abort, exit
  code 1 (smoke's 2 degraded), `::error::` never printed, 0-byte
  excerpt; NEW: `::error::` printed, exit 2 preserved, empty excerpt
  file. Crash class (stub emits matching events) — OLD and NEW
  byte-identical: exit 2, `::error::` printed, 148-byte excerpt with
  the flutter_windows.dll 0xC0000005 message, proving the fix is inert
  exactly where the export already worked.
  Evidence: `flutter analyze` → `No issues found!`; full `flutter
  test` → 651/651 pass (All tests passed!, no Dart changes); strict
  duplicate-key PyYAML re-parse clean (ubuntu-gate 13 steps +
  windows-nightly 12; 27 timeout-minutes keys; continue-on-error now
  1+1, unchanged); all 11 bash run blocks pass `bash -n` (the 2
  "failures" are the Windows-only §9.1/§9.2 PowerShell blocks, per the
  §11.12 precedent); PowerShell 7.6.8 parse of the final edited block:
  0 errors; behavioral harness: OLD exit 1 / NEW exit 2, OLD no
  `::error::` / NEW `::error::` printed, crash class byte-identical
  (148-byte excerpt). Files changed: `.github/workflows/ci.yaml` (one
  `Get-WinEvent` line gained `-ErrorAction SilentlyContinue` + a
  comment documenting the failure class), this track (header + this
  Run Log entry), `docs/FUTURE_WORK.md` (Last updated bumped; header
  recap updated — per the open-items-only rule no new completed-work
  section; open-item set unchanged).
  Commit: 8f04b93 (recorded in a follow-up track commit per the §13
  precedent).
  Push **BLOCKED** (same as every prior run since the credentials
  audit): no GitHub credentials on this host (`git config --get
  credential.helper` empty, no `gh`, no `~/.git-credentials`, no
  `~/.netrc`, no token in env); `git push origin main` → `fatal: could
  not read Username for 'https://github.com'`; `git ls-remote origin
  main` still shows e1749b3, so the local queue (84 commits through
  this run's final commit, per `git rev-list --count origin/main..HEAD`)
  remains local-only. Re-run the push once credentials are provisioned.
  Next: (a) re-push the queued local commits once GitHub credentials
  exist; (b) trigger the §11.3 windows-nightly via `workflow_dispatch`
  (or wait for the 06:00 UTC schedule) on the hosted `windows-latest`
  runner per the §13 decision + §11.3 checklist — the ONLY remaining
  functional gap (§14.1-§14.2) — and this run's fix will be exercised
  for the first time on the no-match failure path; or (c) re-check
  §2.6 on the next Flutter upgrade / when `flutter/flutter#190903`
  lands. The `dart format` gate (102/127-file churn, needs an explicit
  owner decision) remains open; coverage-artifact comparison still
  needs ≥2 real CI runs; the ~80-commit local queue still cannot be
  pushed.

- 2026-10-24Z — §11.33 run: §11.16 timeout-minutes doc-contract
  reconciled with the post-§11.31 workflow (docs-accuracy / process fix;
  zero Dart, test, or workflow-file changes). A fresh four-way parallel
  subagent audit (full FUTURE_WORK.md open-item inventory + track
  "Next:" clauses; end-to-end ci.yaml defect audit with `bash -n` on
  every run block; lib/+test/ convention audit of every catch/timer/
  DateTime.now/Random/network path; §15 chessboard completeness
  verification) concluded: **zero open items are
  implementable-and-verifiable on this Linux host** (§9.1/§9.2/§11.3/§14
  Windows-native-blocked; §2.6 upstream-external — flutter/flutter
  #190903 still unmerged; `dart format` gate needs the explicit owner
  decision; coverage-artifact comparison needs ≥2 real CI runs; the
  85-commit local queue needs GitHub credentials), and **no P0 (crash)
  or P1 (correctness) code or workflow defects remain** — §15 is
  genuinely shipped (81 tests: chessboard_drag 15, board_motion 16,
  scrub_shortcuts 20, premove 30; premove wired in PlayScreen per
  design docs, scrub in 4 screens, no documented-but-missing feature).
  The one actionable P1 finding was **doc-contract drift**: the §11.31
  CI P3 #2 merge absorbed the separate coverage RUN step into the
  gating Test step (ubuntu-gate 14 → 13 steps), but the maintained-in-
  place §11.16 section still asserted the pre-merge state — "all 26
  steps", "all 28 `timeout-minutes` keys (26 steps + 2 jobs)", a
  phantom "coverage 30" step bound, and a bullet promising "the
  coverage step keeps `continue-on-error: true`" about a step that no
  longer exists — and the §11.17 header recap parenthetical carried the
  same stale 26/coverage-30 count. Re-measured this run: ubuntu-gate 13
  + windows-nightly 12 = **25 steps**, 25 + 2 = **27 timeout-minutes
  keys** (strict duplicate-key PyYAML loader: all 25 steps carry exactly
  one key; job bounds 90/180 present). Fixed in place (the §11.28
  precedent for maintained counts): §11.16 step list drops "coverage
  30" (coverage bound by the merged Test step's `timeout-minutes: 30`);
  the continue-on-error bullet now states the true post-merge contract
  — the §11.4 "coverage never reddens the gate" property holds at the
  ARTIFACT level only, via the §11.22 upload step's `continue-on-error:
  true` + `if-no-files-found: warn`, with a coverage-collection failure
  with all tests green being the documented accepted residual of the
  merge (ci.yaml step comment §11.31); evidence block + §11.17 recap
  parenthetical updated (25 steps; two `bash -n` "failures" = the
  Windows-only §9.1/§9.2 PowerShell blocks, per the §11.12 precedent).
  §11.4 was already accurate (updated in §11.31); §11.22 stays as the
  historical DONE record. Evidence: `flutter analyze` → `No issues
  found! (ran in 2.1s)`; full `flutter test` → 651/651 pass (01:54, All
  tests passed! — no Dart changes); strict duplicate-key PyYAML
  re-parse clean (ubuntu-gate 13 + windows-nightly 12 steps; 27
  timeout-minutes keys = 25 steps + 2 job bounds, exactly one per
  step/job); all 3 bash run blocks pass `bash -n` (the 2 "failures" are
  the Windows-only §9.1/§9.2 PowerShell blocks, per the §11.12
  precedent). Files changed: `docs/FUTURE_WORK.md` (header recap +
  Last updated bumped to §11.33; §11.16 section + §11.17 recap
  corrected in place — per the open-items-only rule no new
  completed-work section; open-item set unchanged), this track (header
  + this Run Log entry).
  Commit: afc80a8 (recorded in a follow-up track commit per the §13
  precedent).
  Push **BLOCKED** (same as every prior run since the credentials
  audit): no GitHub credentials on this host (`git config --get
  credential.helper` empty, no `gh`, no `~/.git-credentials`, no
  `~/.netrc`, no token in env); `git push origin main` → `fatal: could
  not read Username for 'https://github.com'`; `git ls-remote origin
  main` still shows e1749b3, so the local queue (85 commits through
  this run's final commit, per `git rev-list --count origin/main..HEAD`)
  remains local-only. Re-run the push once credentials are provisioned.
  Next: (a) re-push the queued local commits once GitHub credentials
  exist; (b) trigger the §11.3 windows-nightly via `workflow_dispatch`
  (or wait for the 06:00 UTC schedule) on the hosted `windows-latest`
  runner per the §13 decision + §11.3 checklist — the ONLY remaining
  functional gap (§14.1-§14.2); or (c) re-check §2.6 on the next
  Flutter upgrade / when `flutter/flutter#190903` lands. The `dart
  format` gate (102/127-file churn, needs an explicit owner decision)
  remains open; coverage-artifact comparison still needs ≥2 real CI
  runs; the ~85-commit local queue still cannot be pushed.

- 2026-10-24Z — §11.34 run: code-P2 audit-trail candidate closed —
  "engine failure diagnostics silently swallowed in
  lib/src/review/engine_adapter.dart". The §11.33 four-way audit's
  silent-swallow pass (9 real/borderline sites) put this file's four
  catch/stream/exit sites at the top of the code-P2 list; this run
  closes it with `dart:developer` `log()` calls (zero behavior
  change) at: (1) `HeuristicEvaluator._extractPlacement` — the
  `catch (_) { return null; }` now logs the decode error and still
  degrades to "unsupported" (FEN text, JSON-with-fen, garbage all
  covered offline); (2) the stderr drain/surface sub — every
  non-empty stderr line is logged at warning level (previously
  dropped entirely); (3) the stdout sub's onError — stream errors
  logged instead of silent; (4) the exit-code watcher — logs
  "exited unexpectedly (code N)" and fires only on the
  unexpected-exit path because dispose() nulls `_process` first, so
  the normal shutdown remains silent (no new log noise). The stale
  class doc "fen or pieces" is corrected to the true contract:
  "fen field required; boards without FEN interop out of scope".
  New deterministic offline test file `test/engine_adapter_test.dart`
  (7 tests, no real engine needed): standard FEN supported; JSON
  payload with fen supported; malformed JSON degrades to unsupported
  without throw; invalid placement unsupported; pieces-only out of
  scope; empty input unsupported; garbage input unsupported. The
  §11.33 audit's other borderline sites (backend_bridge.dart:420/1521,
  openai/anthropic/gemini provider testConnection catches,
  variant_review.dart:267, variant_projection.dart:195) were
  deliberately NOT touched — candidates for a future run. Evidence:
  `flutter analyze` → `No issues found! (ran in 2.2s)`; new suite
  7/7 pass; targeted suites over the modified connect/dispose/stream
  paths (e2e_smoke + review_evaluator_seam + variant_review) →
  18/18 pass including the real-engine "embedded stockfish evaluates
  and stays honest"; full `flutter test` → 658/658 pass (651 baseline
  + 7 new; 02:02, All tests passed! — confirmed by a fresh foreground
  run and the background run). Files changed:
  `lib/src/review/engine_adapter.dart` (log imports + 4 log sites +
  class doc), `test/engine_adapter_test.dart` (new), this track
  (header + this Run Log entry), `docs/FUTURE_WORK.md` (Last updated
  bumped to §11.34; per the open-items-only rule no new
  completed-work section; open-item set unchanged — §9.1/§9.2/§11.3/
  §14.1-§14.2 Windows-native, §2.6 upstream-external, `dart format`
  gate owner-pending, coverage comparison needs ≥2 CI runs, push
  queue credentials-blocked).
  Commit: <FILL-AFTER-COMMIT> (recorded in a follow-up track commit
  per the §13 precedent).
  Push **BLOCKED** (same as every prior run since the credentials
  audit): no GitHub credentials on this host (`git config --get
  credential.helper` empty, no `gh`, no `~/.git-credentials`, no
  `~/.netrc`, no token in env); `git push origin main` → `fatal:
  could not read Username for 'https://github.com'`; the local queue
  now counts 87 commits through this run's final commit (per `git
  rev-list --count origin/main..HEAD`). Re-run the push once
  credentials are provisioned.
  Next: (a) re-push the queued local commits once GitHub credentials
  exist; (b) extend the §11.34 diagnostics pattern to the remaining
  §11.33 borderline swallow sites (backend_bridge.dart:420/1521,
  provider testConnection catches, variant_review.dart:267,
  variant_projection.dart:195); (c) trigger the §11.3 windows-nightly
  via `workflow_dispatch` on the hosted `windows-latest` runner per
  the §13 decision + §11.3 checklist; or (d) re-check §2.6 on the
  next Flutter upgrade / when `flutter/flutter#190903` lands. The
  `dart format` gate (102/127-file churn, needs an explicit owner
  decision) remains open; coverage-artifact comparison still needs
  ≥2 real CI runs; the local commit queue still cannot be pushed.
