# Future Work

Status: open items only
Last updated: 2026-10-22 (UTC) — §15.2 move animation layer shipped
Related: [Runbook](RUNBOOK.md), [Engine runtime](ENGINE_RUNTIME.md),
[Variant rules](VARIANT.md), [Chess engine notes](CHESS_ENGINE.md)

All planned implementation, test coverage, and testability work is complete.
The remaining items are release validation, CI automation, and process
integration that cannot be closed on Linux. Completed work and the crash
investigation history are preserved in `automation-track.md` and git history.

Verified baseline (2026-10-22):

- `flutter analyze` — 0 issues.
- `flutter test` — 581/581 pass.
- `flutter build linux --release` — succeeds; release binary starts under Xvfb.
- Roadmap §12 — 18/18 deliverables present; §10.1–10.8 refactors complete.
- Interaction matrix §6 — all 12 screen/widget suites present.
- §15.1 drag-and-drop and §15.2 move-animation layer shipped.

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

### 11.3 Nightly Windows gate (P0 — workflow added, awaiting first run)

`.github/workflows/ci.yaml` now defines a scheduled `windows-nightly` job
(nightly + `workflow_dispatch`) that builds the Windows release, runs the
§9.1 integration test, invokes the §9.2 UIA smoke, and uploads output
artifacts. It has not completed a run yet, so the gate is not proven.

Remaining:

- Trigger the workflow and confirm all steps actually pass on a Windows
  runner. The UIA smoke needs an interactive desktop/UIA session; GitHub's
  hosted `windows-latest` runner may not provide one, so a dedicated VM may be
  required (see §13).
- Make the integration-test and smoke steps fail the job on any non-zero exit,
  not only on smoke exit code 2.
- Confirm the UIA script is invoked once (the job currently starts the app and
  the script starts it again) and that artifacts contain the Event Viewer
  excerpt on failure.

**Done when:** a green scheduled Windows run is linked from the repository and
its artifacts prove the native gate passed.

### 11.4 Coverage (P2 — optional, not wired)

`flutter test test/ui --coverage` is documented but not run in CI. Coverage is
explicitly not the success metric (§11.4); wire it only if trend reporting is
wanted.

---

## 15. Chessboard interaction and motion (P1 — in progress)

The board supports drag-and-drop (§15.1, shipped 2026-10-22) and an explicit
from→to move-animation layer (§15.2, shipped 2026-10-22) on top of the
click-click tap path. It is still not scrub-friendly: ply seeking swaps
snapshots, and there is no premove queue. Those gaps are the remaining UX
work versus chess.com.

Target feel: scrub back/forth through the game with pieces sliding across the
board, and queue premoves while the opponent thinks.

### 15.3 Fast ply scrubbing (P1)

- Play: Left/Right arrows step one ply, Home/End jump to start/live; move-list
  taps seek; every step uses the motion layer so pieces visibly slide.
- Review, Variant Replay, and Watch share the same seek behavior for their
  move-list/slider navigation.
- Rapid key repeat must coalesce to the latest target and retarget the current
  animation, not queue dozens of controllers. Holding an arrow should feel
  continuous, with no timer leaks or exceptions.
- While reviewing a past ply, the board is read-only and AI input is disabled;
  “Return to live position” restores input and clears any selection.
- Define large jumps (for example, move-list jump of 20 plies): animate the
  final transition only, or cap the animation budget; never animate all
  intermediate plies synchronously.

### 15.4 Premove and multipremove (P1 single / P2 multi)

Premove is a UI-level queue until the human turn actually arrives; it must
never bypass the orchestrator.

- Active during the opponent's turn / while the AI is thinking. Click-click or
  drag can add a premove; show a translucent ghost piece and a numbered
  destination marker, plus a “N premoves” status chip.
- Queue up to five premoves. Validate each against a clone of the current
  position with earlier queued premoves applied, so multiple queued moves are
  legal in sequence.
- On the opponent's move, execute leading legal premoves one at a time through
  the normal human-move path. The first illegal premove is discarded together
  with everything queued after it, with a brief visual explanation.
- Cancel with right-click (last premove), Esc (clear all), or a
  “Clear premoves” control. Clear the queue on new game, terminal state, and
  screen dispose.
- Promotion premoves default to queen (with a visible indicator) or use an
  explicitly chosen piece; do not open a blocking dialog while the opponent is
  thinking.
- Do not request an extra AI turn, double-apply a premove, or leave stale
  queue state if the game ends mid-queue.

### 15.5 Verification and files

Likely touch points:

- `lib/src/ui/widgets/chessboard.dart` — motion overlay (shipped §15.2),
  keyboard seeking.
- `lib/src/ui/screens/play_screen.dart` — premove queue, ply shortcuts,
  `AppliedMove` retention.
- `lib/src/ui/screens/watch_screen.dart`,
  `lib/src/ui/screens/review_screen.dart`,
  `lib/src/ui/screens/variant_replay_screen.dart` — shared seek/motion.
- New tests: `test/ui/premove_test.dart`; extend the existing play/review/
  variant/watch suites. (`test/ui/board_motion_test.dart` shipped with §15.2.)

Acceptance:

- A single premove and a multi-premove chain execute after the AI move; an
  illegal premove is discarded cleanly; cancel/new-game/terminal clears it.
- Arrow-key scrub forward and backward animates pieces; 20 rapid presses cause
  no exceptions, pending timers, or duplicate AI turns.
- Semantics tree keeps 64 unique square nodes with zero reparenting through
  drag, animation (§15.2 verified), and rapid seeking.
- `flutter analyze` clean; full `flutter test` green; reduced-motion mode
  passes without animation.

Suggested order: ply scrubbing (15.3) → single premove → multipremove (15.4) →
polish.

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
