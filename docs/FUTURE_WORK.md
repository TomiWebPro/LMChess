# Future Work

Status: open items only
Last updated: 2026-10-23 (UTC) — §11.16 bounds every ubuntu-gate and
windows-nightly job and step with `timeout-minutes`: the workflow previously
relied on GitHub's default 360-minute job timeout, so a hung step (pub get,
engine download, apt, build, smoke, integration test) could stall the gate for
up to 6 hours and overlap the next scheduled run. Both jobs now carry a job
level backstop (ubuntu-gate 90 min — ~4x the observed ~15-20 min green wall
time — windows-nightly 180 min) and every one of the 24 steps carries its own
tighter bound (checkout 5, Setup Flutter 15, pub-cache restore 5, pub get 5,
analyze 10, engine cache 5, engine download 15, flutter test 30, apt install
15, build linux 30, smoke 15, linux integration 20, coverage 30, upload 5,
build windows 60, windows integration 30, UIA smoke 20). The §11.14 §11.15
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
- **Step-level bounds (all 24 steps across both jobs)** — checkout 5,
  Setup Flutter 15, pub-cache restore 5, pub get 5, analyze 10, engine
  cache restore 5, engine download 15, `flutter test` 30, apt install 15,
  `flutter build linux --release` 30, Linux smoke 15 (the §11.14/§11.15
  internal loops are already bounded — this is a belt-and-braces backstop),
  Linux integration 20, coverage 30, coverage upload 5, `flutter build
  windows --release` 60, Windows unit/widget tests 30, §9.1 integration 30,
  §9.2 UIA smoke 20, smoke artifacts upload 5.
- The coverage step keeps `continue-on-error: true` — a timed-out coverage
  step still cannot redden the gate.

Evidence: workflow re-parses clean via PyYAML **with a strict
duplicate-key loader** (ubuntu-gate 14 steps, windows-nightly 10 — step
counts unchanged, only `timeout-minutes:` keys added); all 26
`timeout-minutes` keys present (24 steps + 2 jobs) and exactly one per
step/job; every bash run-block passes `bash -n` (the sole "failure" is the
Windows-only §9.1 PowerShell block — Windows-only by design, per §11.12);
`flutter analyze` → `No issues found! (ran in 2.4s)`; full regression
`flutter test` → 637/637 pass (01:48, All tests passed! — no Dart changes).
See `automation-track.md` for the run log.

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
