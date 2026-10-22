# Future Work

Status: open items only
Last updated: 2026-10-22 (UTC) — §11.3 CI process fixes (fail-fast on any non-zero exit; single UIA invocation)
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

### 11.4 Coverage (P2 — optional, not wired)

`flutter test test/ui --coverage` is documented but not run in CI. Coverage is
explicitly not the success metric (§11.4); wire it only if trend reporting is
wanted.

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

## 3.3 Upgrade and verification checklist (P1 — not in the runbook)

`docs/RUNBOOK.md` does not yet contain the Flutter upgrade gate. The checklist
must live in the release process, not only in this document.

Add to the runbook:

1. Check the Flutter engine revision against upstream issue `flutter/flutter#175041`.
2. Upgrade or pin a known-good Flutter version.
3. Run the full fast suite (`flutter analyze`, `flutter test`).
4. Run the Windows integration test (§9.1).
5. Build the Windows release and run the UIA smoke with `-RandomClicks 500` (§9.2).
6. Repeat the smoke with Narrator or Inspect.exe attached.
7. Check Event Viewer for any new `flutter_windows.dll` fault.
8. Only then remove the known-issue note from the release checklist.

**Done when:** the checklist is part of `docs/RUNBOOK.md` and referenced by the
release process (acceptance criterion 14.8).

---

## 2.6 Upstream dependency (P1 — external)

The root cause is in the Flutter Windows accessibility bridge
(`flutter/flutter#175041`); the app-level semantics hardening is a mitigation,
not a fix. On each Flutter upgrade:

- Check whether the upstream fix has landed and in which revision.
- Re-run the §9.1/§9.2 gates before removing the known-issue warning.
- Keep the `ExcludeSemantics`/`IndexedStack` hidden-tab guard and stable
  semantics roots regardless of the upstream status.

**Done when:** a Flutter revision containing the fix is validated on Windows,
or the upstream issue is closed and the workaround is formally retired.

---

## 13. Open decisions (not scheduled)

- **Windows runner:** hosted Windows runner vs. a dedicated VM with an
  interactive desktop session for UIA/Narrator. Needed for §11.3.
- **Safe mode:** should the app disable custom semantics for screen-reader
  users until the engine fix lands? Current preference is to fix/ship the tree,
  not add an accessibility regression.
- **Telemetry isolation:** should `StatsLog`, `QualityLog`, `ReviewLog`, and
  `VariantReviewLog` become injectable stores instead of process-static
  abstractions? Test hygiene is currently handled by `resetTelemetry`.

---

## 14. Remaining acceptance criteria

Only these are still open:

- [ ] **14.1** Windows UIA smoke survives 500 random clicks and ≥40 control
      invocations on a release build, with Narrator or Inspect.exe attached.
- [ ] **14.2** Event Viewer shows no new `flutter_windows.dll` `0xC0000005`
      during the smoke.
- [ ] **14.8** The §3.3 upgrade checklist is part of the release runbook.

Already met: 14.3 (`flutter test` green, zero pending timers), 14.4 (every
matrix control has an observable-behavior test), 14.5 (semantics suite reports
zero duplicate ids/null parents/reparenting), 14.6 (monkey sweeps complete
without Dart exceptions), 14.7 (`flutter analyze` clean).

---

Section numbers not present here (§5–§8, §10, §12) refer to completed work;
see the pre-2026-10-21 revision of this file in git history or
`automation-track.md`.
