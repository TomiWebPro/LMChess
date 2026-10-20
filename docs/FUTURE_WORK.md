# Future Work

Status: living document
Last updated: 2026-10-20 (UTC) — §10.7 stable keys + test/ui/stable_keys_test.dart
Related: [Runbook](RUNBOOK.md), [Engine runtime](ENGINE_RUNTIME.md),
[Variant rules](VARIANT.md), [Chess engine notes](CHESS_ENGINE.md)

This document records the work that is intentionally **not** done yet, with
enough detail that it can be picked up without re-investigating the original
failure. The trigger was a Windows desktop crash that happened after clicking
around the app for a short time. The crash exposed two gaps:

1. The app can be killed by a native Flutter accessibility bug even when every
   Dart callback is correct.
2. The current test suite cannot detect that class of regression, and does not
   even exercise most of the app's buttons, dialogs, or navigation paths.

The first gap is an upstream engine issue. The second gap is ours and is the
main body of this document.

---

## 0. How to use this document

- Sections 1-3 are the incident record, current mitigations, and upgrade gate.
- Sections 4-11 are the test-coverage program. They are written as an
  implementation plan, not as a wish list: each test file has a scope, each
  behavior has an assertion, and each phase has an exit criterion.
- Section 12 is the recommended order of work.
- Sections 13-14 are risks and acceptance criteria.
- The appendices contain the exact crash signature and commands.

Nothing in this document should be treated as implemented until the test files
exist and pass in CI. The current suite is described in section 4.1.

---

## 1. Executive summary

### P0 - keep the app alive on Windows

1. Track the upstream Flutter accessibility crash (flutter/flutter#175041 and
   related issues) and upgrade as soon as a fixed engine is available.
2. Add an app-level "semantics hardening" pass: keep the semantics root stable,
   avoid reparenting whole subtrees between frames, and audit every
   `AnimatedSwitcher`, `OverlayPortal`, `Tooltip`, `Slider`, route transition,
   and `IndexedStack` visibility change for semantics churn.
3. Add a Windows UIA process smoke test that fails on `0xC0000005` in
   `flutter_windows.dll`. This is the only automated layer that can catch the
   native crash.

### P0 - make interactions testable

4. Introduce four small dependency-injection seams: turn provider, review
   evaluator, clock, and connection tester. Without them, UI tests hit real
   HTTP, real Stockfish, real secure storage, and real wall-clock time.
5. Remove the static `ArenaScreen._elo` singleton so Elo state does not leak
   between tests.
6. Add stable keys for duplicate controls (`New game`, `Resign`, `Replay`,
   `Refresh`) so tests do not silently tap the wrong one.

### P0 - cover the "click anywhere" surface

7. Add ~250-300 widget tests across shell navigation, chessboard, Play, Watch,
   Arena, Stats, Review, Agents, Settings, shared widgets, and variant replay.
8. Add a semantics-stability suite that asserts the invariants the Windows
   embedder assumes: one root, unique ids, non-null parents, no reparenting,
   64 square nodes per board, hidden tabs contribute no nodes.
9. Add deterministic monkey tests: grid sweeps plus seeded random taps with a
   tree dump and the failing offset on failure.

### P1 - make the failures diagnosable

10. Add a global Flutter error handler and structured logging for async UI
    failures. A crash after a tap should leave a breadcrumb even when the
    native process dies.
11. Add crash reporting/collection instructions for Windows and a release-build
    verification checklist.
12. Add CI jobs for the fast widget gate and the nightly Windows UIA gate.

---

## 2. Incident record

### 2.1 Symptoms

`flutter run` on Windows produced repeated engine errors and then lost the
device:

```text
[ERROR:flutter/shell/platform/common/accessibility_bridge.cc(114)]
Failed to update ui::AXTree, error: 0 will not be in the tree and is not the new root

[ERROR:flutter/shell/platform/common/accessibility_bridge.cc(114)]
Failed to update ui::AXTree, error: 6 will not be in the tree and is not the new root

[ERROR:flutter/shell/platform/common/accessibility_bridge.cc(114)]
Failed to update ui::AXTree, error: 114 will not be in the tree and is not the new root

[ERROR:flutter/shell/platform/common/accessibility_bridge.cc(114)]
Failed to update ui::AXTree, error: Nodes left pending by the update: 116 117 ...
...
Lost connection to device.
```

The bare numbers between the errors (`4`, `5`, `39`, ...) are not produced by
this repository's Dart code. They are most likely other process output
interleaved with the engine log; they are not needed for the diagnosis.

### 2.2 Evidence

Windows Event Viewer (`Application` log) recorded multiple `APPCRASH` entries
for `llm_chess_arena.exe` in the same minute range:

| Field | Value |
|---|---|
| Faulting module | `flutter_windows.dll` |
| Module timestamp | `6ac6894b` (matches the Flutter 3.47.7 engine cache) |
| Exception code | `0xC0000005` (access violation) |
| RVA | `0x3c1ea` |
| Secondary code | `0xC000041D` (unhandled exception in a user callback) |

The Flutter SDK is 3.47.7 stable, engine revision `deb287481e`, built
2026-10-08. The installed engine's PDB resolves `0x3c1ea` to:

```text
flutter::AccessibilityBridge::CreateRemoveReparentedNodesUpdate()
engine/src/flutter/shell/platform/common/accessibility_bridge.cc:229
```

The line is:

```cpp
// Skip nodes whose parents are unchanged.
if (child->parent()->id() == node_update.second.id) {
```

The preceding guard is:

```cpp
// Flutter's root node should never be reparented.
assert(child->parent());
```

`assert` is compiled out of the release engine, so a child with a null parent
is dereferenced. The first `Failed to update ui::AXTree` error leaves the tree
in a state where a later update contains a child whose parent is gone; the next
`CommitUpdates` then walks that child and crashes.

### 2.3 Root cause

This is a native embedder bug, not a Dart exception:

- A semantics update references a node that is no longer in the AX tree, or
  whose node id was reused after a reparent.
- `AXTree::Unserialize` rejects the update ("will not be in the tree and is not
  the new root"), logs the error, and returns.
- The pending-node map is cleared only after the next update; the tree is now
  inconsistent.
- On a subsequent `CommitUpdates`, `CreateRemoveReparentedNodesUpdate` sees a
  child whose `parent()` is null and dereferences it.

The duplicate ids and "nodes left pending" lines show that the Flutter
semantics tree and the native AXTree disagreed about which nodes exist. The
native root can change in `CommitUpdates` when `results.back().front()` is not
the actual root; upstream issue #175041 describes this "crowning" defect.

### 2.4 Why the current tests did not catch it

The suite has 21 files, but only five widget tests touch the UI:

| File | What it actually does |
|---|---|
| `test/boot_smoke_test.dart` | Pumps the app, taps the rail's Play/Watch, checks a text label. |
| `test/semantics_smoke_test.dart` | Checks two square labels and that hidden tabs do not expose the Play board. |
| `test/pump_loops_test.dart` | Taps e2/e4 once and Watch Start/Pause. |
| `test/variant_replay_widget_test.dart` | Taps Next twice. |

Everything else is unit-level (chess rules, Elo, storage, parsing, scheduler,
metrics, variant fuzzing). The suite never:

- taps Home cards, the drawer, the bottom bar, or the "More" sheet;
- opens Resign, promotion, Arena detail, or any bottom sheet;
- exercises the Arena form, agents form, stats filters, review controls,
  settings radios, or replay transport;
- resizes across 700/1100 px breakpoints;
- switches themes with a live board;
- asserts that semantics nodes keep their parent across transitions;
- runs against a real Windows accessibility client.

Even a perfect Dart test suite cannot catch the native access violation, but it
can catch the conditions that create the corrupt update. That is the gap this
plan addresses.

### 2.5 What is not the cause

- Not a missing `setState` guard or an unhandled Dart exception in a button
  handler. The process dies inside `flutter_windows.dll`.
- Not a Stockfish crash. The faulting module is the Flutter engine, not the
  extracted engine binary.
- Not a missing plugin. The DLL is present and the app runs until the AX tree
  update fails.
- Not necessarily the specific button. Any control that changes the semantics
  tree can trigger it; the reported "clicked anywhere" is consistent with a
  stale tree rather than a single widget.

### 2.6 Upstream tracking

Primary issue:

- flutter/flutter#175041 - `AccessibilityBridge::CreateRemoveReparentedNodesUpdate`
  crash (0xC0000005, accessibility_bridge.cc:229).

Related:

- flutter/flutter#182444 - ListView + Tooltip triggers "will not be in the
  tree and is not the new root".
- flutter/flutter#190357 - Slider in a pushed route serializes an orphan
  semantics node and freezes the Windows AX tree.
- flutter/flutter#192689 - duplicate of #175041, same crash site.
- flutter/flutter#190903 - proposed null guard for `child->parent()`.
- flutter/flutter#98099, #118221, #103808 - earlier Windows AXTree/reorder
  crashes.

Issue #175041 notes a proposed fix direction: do not crown
`results.back().front()` as the root unless it really is the root, and keep a
null guard so a bad tree degrades to a rejected update instead of a segfault.
A commit in the issue thread ("Fix Windows accessibility root init") may be a
lead, but it must be verified against the exact engine revision before relying
on it.

---

## 3. Mitigations and upgrade gate

### 3.1 Developer workaround

The crash requires the Windows accessibility bridge to be producing updates.
If a UIA client (Narrator, Inspect.exe, a screen reader, some automation tools)
is attached, the bridge is active. For day-to-day development you can reduce
exposure by closing accessibility clients, but **do not treat that as a fix**:
real users with a screen reader will still hit it.

### 3.2 App-level semantics hardening

These do not fix the engine but reduce the chance of producing the bad update:

1. Keep a stable semantics root. Do not replace the root widget or the shell
   subtree between frames when a child-only change would do.
2. Do not move a whole semantics subtree from one parent to another in a
   single frame. If a layout must move, keep the node ids and parent stable and
   move the visual content instead.
3. Audit `AnimatedSwitcher` around semantic content. The chessboard already
   excludes the piece glyph and coordinate text so the per-square
   `AnimatedSwitcher` cannot add/remove nodes; keep that invariant.
4. Audit `OverlayPortal`, `Tooltip`, `Slider`, `DropdownMenu`, `showDialog`,
   `showModalBottomSheet`, and route transitions. Upstream reports show these
   can create orphan nodes, especially inside pushed routes.
5. Keep the hidden-tab guard: `IndexedStack` children are wrapped in
   `ExcludeSemantics(excluding: i != _index)` plus `TickerMode(enabled: false)`.
   Do not remove it, and extend it to any new multi-page container.
6. Prefer stable `ValueKey`s on semantics containers and navigation
   destinations.
7. Avoid nesting a manual `Semantics(textField: true)` around `TextField`;
   `EditableText` already publishes one node (the agent form deliberately does
   not do this).
8. When adding a board or a repeated grid, give each square one `Semantics`
   container with `excludeSemantics: true` and a stable label. Do not let
   glyphs or coordinate text leak in.

### 3.3 Upgrade and verification checklist

Before upgrading Flutter:

1. Check the engine revision against the upstream issue's fix commit.
2. `flutter upgrade` (or pin a known-good version).
3. Run the full fast widget suite.
4. Run the Windows integration test.
5. Build release and run `tool/windows_accessibility_smoke.ps1` with
   `-RandomClicks 500`.
6. Run the same smoke once with Narrator or Inspect.exe attached.
7. Check Event Viewer for any new `flutter_windows.dll` fault.
8. Only then remove the known-issue note from the release checklist.

Do not upgrade and ship based only on "the widget tests pass"; they cannot
observe the native crash.

---

## 4. Test strategy

### 4.1 Three layers

| Layer | Runs | Catches | Cannot catch |
|---|---|---|---|
| Widget interaction | every PR | broken onPressed/onTap, disabled states, dialogs, validation, async races, Dart exceptions | native AXTree crash |
| Semantics invariants | every PR | duplicate ids, null parents, reparenting, hidden-tab leaks, missing square nodes | the engine dereference |
| Windows integration + UIA smoke | nightly / pre-release | `Failed to update ui::AXTree`, `0xC0000005` process exit | fine-grained UI behavior |

The layers are complementary. A test that only pumps a screen adds runtime but
no regression value; every action must assert an observable behavior, and every
semantics transition must assert the tree invariants.

### 4.2 Definition of done

- Every `onPressed`/`onTap` in the interaction matrix is exercised.
- Every semantics transition is checked with `expectSemanticsTreeInvariants`.
- The monkey tests complete without a Dart exception.
- The UIA smoke completes without the process exiting.
- The suite is green with zero pending-timer failures.
- `flutter analyze` is clean.

---

## 5. Test infrastructure

### 5.1 New layout

```text
test/
  support/
    arena_test_harness.dart
    semantics_invariants.dart
  ui/
    chessboard_test.dart
    shell_navigation_test.dart
    home_screen_test.dart
    play_screen_test.dart
    watch_screen_test.dart
    arena_screen_test.dart
    stats_screen_test.dart
    review_screen_test.dart
    variant_replay_test.dart
    agent_setup_test.dart
    settings_screen_test.dart
    shared_widgets_test.dart
    semantics_stability_test.dart
    monkey_tap_test.dart
integration_test/
  accessibility_windows_test.dart
tool/
  windows_accessibility_smoke.ps1
```

Keep `boot_smoke_test.dart`, `semantics_smoke_test.dart`, and
`pump_loops_test.dart`; the new suites extend them rather than duplicate them.

### 5.2 Harness

`test/support/arena_test_harness.dart` owns:

- desktop surface size and reset;
- `pumpArenaApp` with provider overrides;
- `pumpScreen` for isolated screens;
- `pumpSteps` (never `pumpAndSettle` around spinners or live loops);
- telemetry reset (`StatsLog`, `QualityLog`, `ReviewLog`, `VariantReviewLog`);
- `disposeApp` to drain timers and avoid pending-timer failures;
- fake agents/providers and a shared "expect no exception" helper.

Sketch:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/app.dart';
import 'package:llm_chess_arena/src/ui/backend_bridge.dart';

void resetTelemetry() {
  StatsLog.clear();
  QualityLog.clear();
  ReviewLog.clear();
  VariantReviewLog.clear();
}

void useDesktopSurface(
  WidgetTester tester, {
  Size size = const Size(1400, 1000),
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> pumpArenaApp(
  WidgetTester tester, {
  Size size = const Size(1400, 1000),
  List<Override> overrides = const <Override>[],
}) async {
  useDesktopSurface(tester, size: size);
  await tester.pumpWidget(
    ProviderScope(overrides: overrides, child: const ArenaApp()),
  );
  await tester.pump();
}

Future<void> pumpSteps(
  WidgetTester tester, {
  int steps = 12,
  Duration step = const Duration(milliseconds: 100),
}) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(step);
  }
}

Future<void> disposeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}
```

Every UI test starts with `setUp(resetTelemetry);`. Any test that opens a
review or replay screen must override the evaluator factory so it cannot spawn
Stockfish. Any test that starts a game must override the turn provider so it
cannot hit the network or wait on wall-clock timers.

### 5.3 Semantics invariants

`test/support/semantics_invariants.dart` walks the tree reachable from the
root and asserts the assumptions the Windows embedder makes:

```dart
void expectSemanticsTreeInvariants(WidgetTester tester) {
  final owner = tester.binding.renderViews.first.owner!.semanticsOwner;
  final root = owner?.rootSemanticsNode;
  expect(root, isNotNull);

  final ids = <int>{};
  final nodes = <SemanticsNode>[];

  void visit(SemanticsNode node) {
    nodes.add(node);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(root!);

  for (final node in nodes) {
    expect(ids.add(node.id), isTrue,
        reason: 'duplicate semantics id ${node.id} "${node.label}"');
    expect(node.owner, same(root.owner));
    if (!identical(node, root)) {
      expect(node.parent, isNotNull,
          reason: 'node ${node.id} "${node.label}" has a null parent');
    }
  }

  void check(SemanticsNode parent) {
    parent.visitChildren((child) {
      expect(identical(child.parent, parent), isTrue,
          reason: 'node ${child.id} reports parent ${child.parent?.id}, '
                  'expected ${parent.id}');
      check(child);
      return true;
    });
  }

  check(root);
}
```

Also provide:

- `captureSemantics(tester)` returning root + reachable nodes;
- `parentMap(tester)` returning `Map<int, int?>`;
- `expectNoReparenting(before, after)`;
- `expectSquareSemantics(expectedCount, requireUniqueSquares)` with the labels
  `Empty square <sq>`, `White piece on <sq>`, `Black piece on <sq>`;
- `expectNoExceptionWithSemanticsDump(context)` which prints
  `debugDumpSemanticsTree(DebugSemanticsDumpOrder.traversalOrder)` before
  failing.

Important details:

- Call `tester.ensureSemantics()` and dispose the handle in `try/finally`, not
  in `addTearDown`; end-of-test semantics verification runs before tear-downs.
- `SemanticsOwner` does not expose an enumeration API, so this checks nodes
  reachable from the root. True unreachable-node detection needs an engine hook
  and is out of scope; the UIA smoke covers the native side.
- Arena's mini-board grid legitimately repeats square labels. Scope uniqueness
  to single-board screens; use `expectedCount = 64 * visibleBoards` and
  `requireUniqueSquares: false` for Arena.

### 5.4 Deterministic fakes

Use the existing `MockProvider` and storage abstractions rather than
hand-rolled closures where possible. The key rule is: a widget test must never
open a socket, spawn a process, or read the real secure store.

- Turn provider: returns a legal UCI move immediately; can inject timeout,
  malformed response, no-move, and thrown failure.
- Review evaluator: `HeuristicEvaluator` with a synthetic source label; no
  Stockfish extraction.
- Secure storage: `FlutterSecureStorage.setMockInitialValues({})` plus an
  injectable `SecureKeyStore` for save/clear assertions.
- Clock: fixed `DateTime.utc(2026, 1, 1)` for Watch/Arena/review ids.
- Random: fixed seeds in tests; never `Random()` without a seed.

---

## 6. Interaction coverage matrix

The matrix is the contract for the interaction suite. Each bullet is one or
more tests with an observable assertion. Tests use `find.byKey` for duplicate
labels and `ensureSemantics` when the widget exposes actions.

### 6.1 Shell and navigation (`shell_navigation_test.dart`, 16 tests)

- Wide (`>=700`): all 8 `NavigationRail` destinations open the expected screen
  and preserve the previous tab's state.
- Narrow (`<700`): 4 bottom destinations plus the `More` sheet; all 4 sheet
  items (`Stats`, `Review`, `Agents`, `Settings`) select the right screen and
  dismiss the sheet.
- Drawer: open, tap all 8 items, verify close and selection.
- All 7 Home cards fire the correct route; the shell switches index instead of
  pushing a duplicate live screen.
- Resize 699 -> 700 -> 1100 -> 699 while Play is mounted; no state loss, no
  rebuild of a running game.
- 20 rapid destination switches; `takeException()` null and invariants hold
  after each.
- Navigate away from a running Watch/Play loop and back; move count does not
  reset or double-schedule.
- Hidden tabs contribute zero square labels; selected tab contributes exactly
  64 (single-board screens).

### 6.2 Home (`home_screen_test.dart`, 6 tests)

- Each of the 7 feature cards calls `onOpen` with the exact route.
- All capability chips render.
- Narrow and wide layouts render without overflow.
- A standalone Home (no `onOpen`) uses `Navigator.pushNamed` and reaches the
  intended route.

### 6.3 Chessboard (`chessboard_test.dart`, ~20 tests)

- Tap each of the 64 squares; callback receives the correct name. Use a
  parameterized loop or 8 file/rank loops.
- White and black orientation map a tap to the same logical square.
- `interactive: false` and `onTapSquare: null` expose no tap action.
- Selection, legal-target, capture, check, terminal, and last-move overlays do
  not change labels or node counts.
- Variant badges/annotations do not change semantics.
- Rapid content swaps (empty -> piece -> empty) across all squares keep 64
  nodes, unique labels, no exception.
- `showCoordinates: false` still exposes the same 64 nodes.
- Both activation paths (gesture and `Semantics.onTap`) call the handler once;
  no double move.

### 6.4 Play (`play_screen_test.dart`, ~30 tests)

Board and game flow:

- Select own piece, deselect, reselect.
- Tap an opponent piece with nothing selected: no selection.
- Tap an empty square with nothing selected: no selection.
- Legal move via coordinate tap; board updates and AI replies exactly once.
- Illegal destination: position unchanged, no snackbar crash.
- Second tap while AI is thinking is ignored.
- `New game` during AI thinking: old turn settles without touching the new
  game, no setState-after-dispose.
- Promotion dialog appears on a7-a8; Q/R/B/N each produce the right piece;
  barrier/back dismiss leaves the pawn on a7.
- Resign: cancel leaves the game running; confirm shows `Game over · 0-1`.
- Result state: board taps ignored, New game/Resign disabled, banner New game
  restarts.
- Move list: tap an earlier ply, board seeks, `Return to live position`
  restores, selection clears.
- Fallback plies render the error marker; eval bar updates after a capture.

Panels and failures:

- Activity/Moves tabs switch both directions.
- Fake provider timeout -> inline error banner + `Retry`.
- Fake provider throws -> `AI turn crashed: ...`, app remains alive.
- Fake provider returns no move -> `AI turn produced no move`, no infinite
  spinner.
- Retry with a subsequent legal move clears the banner.
- Different error kinds map to the expected `FailureKind` copy.

Lifecycle:

- Pump a replacement widget mid-turn; no setState-after-dispose.
- Dispose with a pending provider future; no pending timer.
- Terminal FEN injection (test-only) -> correct banner and disabled controls.

### 6.5 Watch (`watch_screen_test.dart`, ~22 tests)

- Start with both demo agents; move count increases.
- Pause stops new turns; Resume continues; Stop ends the run.
- Empty catalog -> `Pick two agents first.`
- Change either selector while running: either disabled or safe restart.
- Stop during an in-flight turn: no new schedule, no exception.
- Start -> Pause -> Start resets cleanly.
- Activity/Moves/Errors tabs switch while running.
- Error tab: empty state and injected rows.
- Move-list seek matches the board.
- Dispose while running: no pending timers.
- Narrow tabs vs wide board+panel layout.

### 6.6 Arena (`arena_screen_test.dart`, ~26 tests)

- Name field, rounds, games/pairing, chaos chip, concurrency slider: bounds,
  labels, disabled while running.
- Start tournament with defaults; Stop shows `Cancelling...`.
- Start twice is rejected; zero/one agent is explained without a crash.
- Standings table with zero and multiple rows.
- Seed chip renders the injected seed.
- Every mini-board card opens the detail dialog; `Close` and `Replay` work.
- `Replay` pushes `VariantReplayScreen` and returns.
- Resize while running; finish a small tournament with a fixed seed and assert
  standings/Elo.
- Concurrency and scheduler cancellation do not leave orchestrators running.

### 6.7 Stats (`stats_screen_test.dart`, ~18 tests)

- Empty states: `No finished games to chart.`, `No latency samples yet.`
- Seed `StatsLog`/`QualityLog`: table rows and values.
- Agent/variant filters; `Reset filters` appears only when filtered.
- Tap pie slices, error bars, latency bars, quality bars; no exceptions.
- Dropdowns list `All` plus every seeded agent/variant.
- Narrow layout scrolls the table without overflow.

### 6.8 Review (`review_screen_test.dart`, ~22 tests)

- Empty `ReviewLog` -> prompt + `Refresh`.
- Seed two games; picker lists both; switching updates the move list.
- Re-run review with a fake evaluator; runs once and renders.
- Evaluator throws -> error card + `Retry`.
- Key moments: filter chips and empty state.
- Replay slider and move-list seek.
- Chaotic replay tile pushes `VariantReplayScreen`.
- Navigate away mid-evaluation: handle disposed exactly once.
- Re-run while active: previous handle disposed, no double process.

### 6.9 Variant replay (`variant_replay_test.dart`, ~18 tests)

- First/Previous/Next/Last at both boundaries.
- Slider drag to every ply; board position matches.
- Analyze/Re-analyze with a fake evaluator; dispose mid-analysis.
- Per-ply review rows seek.
- Both `ExpansionTile`s open/close.
- AppBar back pops and disposes the evaluator.

### 6.10 Agents (`agent_setup_test.dart`, ~26 tests)

- List: count, New agent, Edit, Delete, empty state.
- Form: display name, provider, model id, temperature slider, max tokens,
  system prompt, user prompt template.
- Provider switch updates the model field/list.
- Validation: empty name/provider/model blocks save and shows messages.
- Save new -> catalog grows + snackbar; edit -> same id updated.
- API key: enter, save, clear (`Clear stored key`), never displayed after save.
- `Test connection`: success/failure, disabled while probing, spinner clears.
- Cancel/back leaves the catalog untouched.
- Narrow layout scrolls without overflow.

### 6.11 Settings (`settings_screen_test.dart`, ~14 tests)

- Light/System/Dark segments update `themeModeProvider` and rendered
  brightness.
- Every board theme radio updates `themeRegistryProvider` and the preview.
- Every piece theme radio updates the preview glyphs.
- Preview board is non-interactive and exposes no tap actions.
- Selection survives a shell tab switch and a rebuild.
- Narrow layout.

### 6.12 Shared widgets (`shared_widgets_test.dart`, ~20 tests)

- `MoveList`: empty, one move, many moves, error plies, current index, tap.
- `EvalBar`: positive/negative/zero, heuristic watermark.
- `ActivityPanel`: empty, streaming row, thinking spinner, error row.
- `PlayerCard`: active/inactive, human/AI, null clock, long names.
- `BoardPanelLayout`: `<700` tabs, `700-1100`, `>1100` side-by-side; tab switch
  preserves child state.
- `StatChip` variants.

---

## 7. Semantics stability suite

`test/ui/semantics_stability_test.dart` (~32 tests). Every test opens with
`ensureSemantics`, performs a transition, and asserts:

1. `expectSemanticsTreeInvariants` after the open, after the transition
   animation, and again on the next frame.
2. `expectNoReparenting` against the previous `parentMap`.
3. The expected anchor label(s) for the screen.
4. The expected square count for single-board screens.
5. `tester.takeException()` is null.

Scenarios:

- All 8 destinations at wide and narrow.
- Open and cancel every dialog/sheet: Resign, promotion, Arena detail, More,
  drawer. Check after open, after close animation, and next frame.
- Play Activity/Moves, Watch Activity/Moves/Errors, variant ExpansionTiles.
- Review game-picker swap: old move nodes removed, new ones added, no
  reparenting.
- Resize 699 -> 700 -> 1100 -> 699 repeatedly; check at each step.
- Theme light -> dark -> system with a live board; labels/count unchanged.
- Hidden-tab rule: Home -> Play -> Stats.
- Arena mini-boards: `64 * visibleBoards`, duplicate square names allowed.
- 50 rapid nav/theme/dialog operations: no duplicate ids.

Optional negative check after triage: `expectNoUnlabelledTapNodes`. Start it as
a reporting check on Stats/charts, promote to an assertion once false positives
are understood.

Why this matters: a node that changes parent is exactly the input that makes
`CreateRemoveReparentedNodesUpdate` run. A node with a null parent is exactly
the crash. These assertions turn the native precondition into a fast,
actionable test failure.

---

## 8. Monkey / "tap anywhere" suite

`test/ui/monkey_tap_test.dart`, four deterministic tests:

1. 600x800 grid sweep every 48 px (narrow layout + drawer + bottom bar).
2. 1600x1000 grid sweep with Play mounted.
3. 1500 random taps, seed `0xC0FFEE`.
4. 300 random taps while checking `expectNoReparenting` every step.

Rules:

- Never `pumpAndSettle`; use 8-16 ms `pump` slices.
- Allow dialogs/sheets to be dismissed by their barriers; pop any route stack
  at the end of each row.
- `disposeApp(tester)` at the end so AI timers do not fail the test.
- Per-test `Timeout(Duration(minutes: 2))`.
- On failure, print the seed, the action index, the offset, and a semantics
  tree dump.
- Do not reuse a `ProviderContainer` across tests; destructive taps are
  test-scoped.
- Cap the sweep by `maxTaps` so a new screen cannot make the test run forever.

Add a "press every labelled control" helper:

```dart
Future<int> tapEveryLabelledControl(
  WidgetTester tester, {
  int maxTaps = 120,
}) async {
  var taps = 0;
  final exercised = <String>{};

  while (taps < maxTaps) {
    final snapshot = captureSemantics(tester);
    SemanticsNode? next;

    for (final node in snapshot.nodes) {
      final data = node.getSemanticsData();
      if (!data.hasAction(SemanticsAction.tap)) continue;
      final key = '${data.label}@'
          '${node.rect.center.dx.round()},${node.rect.center.dy.round()}';
      if (!exercised.add(key)) continue;
      next = node;
      break;
    }

    if (next == null) break;
    final target = next;
    await tester.semantics.tap(
      find.semantics.byPredicate((node) => node.id == target.id),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expectNoExceptionWithSemanticsDump(tester, 'tap "${target.label}"');
    expectSemanticsTreeInvariants(tester);
    taps++;
  }
  return taps;
}
```

Run this per destination on a fresh app. It reaches icon-only controls via
their tooltips and directly covers "the button exists but crashes when
pressed".

---

## 9. Windows integration and native smoke

### 9.1 Integration test

Add to `pubspec.yaml`:

```yaml
dev_dependencies:
  integration_test:
    sdk: flutter
```

`integration_test/accessibility_windows_test.dart` should:

- call `IntegrationTestWidgetsFlutterBinding.ensureInitialized()`;
- launch `app.main()`;
- enable semantics;
- visit all 8 destinations;
- open/close Resign, promotion, Arena detail, and the More sheet;
- perform 20 rapid Play/Watch switches;
- assert no Dart exception and the expected labels after each step.

Caveat: `ensureSemantics()` forces framework semantics, but it does not
guarantee the same native AXTree churn as a real UIA client. It is a
bridge-level check, not the native crash gate.

### 9.2 UIA process smoke

`tool/windows_accessibility_smoke.ps1` is the only automated layer that can
see the native crash. It should:

1. Launch the release exe with `Start-Process -PassThru`.
2. Attach with `UIAutomationClient`.
3. Find the window by process id.
4. Invoke every UIA button (`InvokePattern`, fall back to
   `LegacyIAccessiblePattern.DoDefaultAction`), target >= 40.
5. Walk the UIA tree repeatedly. This is the operation that crashed.
6. Perform 500 random clicks inside the window with a fixed seed.
7. Fail if the process exits, or if Event Viewer records a fresh
   `flutter_windows.dll` `0xC0000005` after the run.
8. Always kill the process in `finally`.

Run nightly and before release:

```powershell
flutter build windows --release
powershell -ExecutionPolicy Bypass -File tool/windows_accessibility_smoke.ps1 `
  -Exe build\windows\x64\runner\Release\llm_chess_arena.exe `
  -RandomClicks 500
```

Also run once with Narrator (`%WINDIR%\System32\Narrator.exe`) or
`Inspect.exe` attached. That is the closest reproduction of the reported
crash. Until the engine bug is fixed, this test is expected to reproduce the
crash; keep it as a known-issue gate, not a silently ignored test.

Optional CI enhancement: fail if Event Viewer contains an `Application Error`
entry for `flutter_windows.dll` with RVA `0x3c1ea` or exception
`0xC0000005` after the smoke run.

---

## 10. Testability refactors

These are small, behavior-preserving, and should land before the bulk of the
interaction tests. Without them the suite is slow and flaky.

### 10.1 Turn provider seam

Screens call `resolveTurnProvider` directly today. Add to
`lib/src/ui/backend_bridge.dart`:

```dart
typedef TurnProviderFactory = Future<LlmProvider> Function(
  AgentConfig config,
  List<String> legalUcis, {
  int? seed,
  String? phrase,
});

final turnProviderFactoryProvider = Provider<TurnProviderFactory>(
  (ref) => resolveTurnProvider,
);
```

Use it in Play, Watch, and Arena. Tests override it with `MockProvider` that
returns immediately and can inject timeout, malformed response, no-move, and
thrown failures.

> Note (2026-10-20): implemented. `TurnProviderFactory` +
> `turnProviderFactoryProvider` (default `resolveTurnProvider`) live in
> `lib/src/ui/backend_bridge.dart`; Play/Watch/Arena (4 call sites) resolve
> via `ref.read(turnProviderFactoryProvider)`. Pinned by
> `test/turn_provider_seam_test.dart` (8 tests: default legal mock move,
> seed/phrase passthrough, timeout/malformed/no-move/thrown injection,
> end-to-end mock stream). 10.2 now implemented separately; 10.3-10.4 and 10.7
> still open.

### 10.2 Review evaluator seam

Add:

```dart
typedef ReviewEvaluatorFactory = Future<ReviewEvaluatorHandle> Function();

final reviewEvaluatorFactoryProvider = Provider<ReviewEvaluatorFactory>(
  (ref) => resolveReviewEvaluator,
);
```

Use it in `ReviewScreen` and `VariantReplayScreen`. Tests override it with
`HeuristicEvaluator` wrapped in a handle so no Stockfish process is spawned.

> Note (2026-10-20): implemented. `ReviewEvaluatorFactory` +
> `reviewEvaluatorFactoryProvider` (default `resolveReviewEvaluator`) live in
> `lib/src/ui/backend_bridge.dart`; both ReviewScreen and VariantReplayScreen
> capture the factory via `ref.read(reviewEvaluatorFactoryProvider)` in initState
> and invoke `_evalFactory()` inside their review methods. Pinned by
> `test/review_evaluator_seam_test.dart` (8 tests: default provider resolves,
> heuristic-only override, factory invocation timing, thrown failure injection,
> nested ProviderScope shadowing, container lifecycle). 10.3-10.4 and 10.7 still
> open.

### 10.3 Clock seam

Add:

```dart
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
```

Replace `DateTime.now()` in Watch seeds, Arena ids/timestamps, and review ids.
Tests override with a fixed UTC timestamp.

> Note (2026-10-20): implemented. `clockProvider` added to
> `lib/src/ui/backend_bridge.dart`; WatchScreen wired (`_clock` in `initState`,
> `_watchSeed` + review id use `_clock()`), ArenaScreen wired (`_clock` in
> `initState`, chaos seed + startedAt/finishedAt use `_clock()`). Pinned by
> `test/clock_seam_test.dart` (8 tests: default valid DateTime, override fixes
> UTC, deterministic ms-epoch, masked seed stable, nested scope shadowing,
> shared reference, full regression 173/173). 10.4 + 10.7 still open.

### 10.4 Connection tester seam

Add:

```dart
typedef ConnectionTester = Future<bool> Function(
  AgentConfig agent, {
  String? inlineSecret,
});

final connectionTesterProvider = Provider<ConnectionTester>((ref) {
  return (agent, {inlineSecret}) => testAgentConnection(
        agent, const SecureKeyStore(), inlineSecret: inlineSecret,
      );
});
```

`AgentSetupScreen` reads this instead of calling `testAgentConnection`
directly. Tests override with a success or failure lambda. Also allow an
optional `SecureKeyStore` constructor parameter so save/clear can be asserted
without platform channels.

> Note (2026-10-20): implemented. `ConnectionTester` typedef +
> `connectionTesterProvider` (default wraps `testAgentConnection` with internal
> `const SecureKeyStore()`) live in `lib/src/ui/backend_bridge.dart`;
> AgentSetupScreen wired (`_tester` captured via `ref.read` in initState, call
> site uses `_tester(probe, inlineSecret: ...)`, no longer passes `_keyStore`
> directly). Pinned by `test/connection_tester_seam_test.dart` (8 tests: default
> factory resolves, override fixed-success/fixed-false, inlineSecret passthrough
> verification, thrown failure injection, nested scope shadowing, per-container
> independence, real-network timeout bounded; full regression 181/183 pass). 10.7
> still open.

### 10.5 Arena Elo injection

`ArenaScreen._elo` is `static final` and leaks across tests. Replace with:

```dart
class ArenaScreen extends ConsumerStatefulWidget {
  const ArenaScreen({super.key, this.elo});
  final EloService? elo;
}

class _ArenaScreenState extends ConsumerState<ArenaScreen> {
  late final EloService _elo = widget.elo ?? EloService();
}
```

### 10.6 Deterministic deep states

Add `@visibleForTesting` parameters:

- `PlayScreen({this.initialFen})` - test promotion/checkmate without 40 moves.
- `WatchScreen({this.initialSeed, this.initialAgents})`.
- `ArenaScreen({this.initialSeed, this.elo})`.
- `AppShell({this.initialIndex = 0})` - test one destination without tapping.

### 10.7 Stable keys

Duplicate labels exist after a game ends (`New game` in the banner and in the
Moves tab) and in dialogs (`Resign`, `Replay`, `Refresh`). Add keys:

```dart
const ValueKey<String>('play-new-game-banner');
const ValueKey<String>('play-new-game-button');
const ValueKey<String>('play-resign-button');
const ValueKey<String>('play-retry-ai');
```

Use `find.byKey` in new tests. `find.text(...).first` silently hides
duplicate-control bugs.

> Note (2026-10-20): implemented. Five `ValueKey<String>` constants added to
> play_screen.dart controls: `'play-new-game-banner'` (result-banner TextButton,
> ~line 408), `'play-retry-ai'` (AI error banner TextButton, ~line 448),
> `'play-new-game-button'` (moves-panel OutlinedButton.icon, ~line 486),
> `'play-resign-button'` (moves-panel OutlinedButton.icon, ~line 494),
> `'play-resign-confirm'` (resign-dialog FilledButton, ~line 758). All five
> strings are unique and do not collide with planned Watch/Arena keys. Pinned
> by `test/ui/stable_keys_test.dart` (4 tests: uniqueness, non-collision across
> screens, ValueKey parse integrity with overridden providers; full regression
> 185/185). Next: §5.1 harness + §5.3 semantics invariants.

### 10.8 Dispose audit

`ReviewScreen` and `VariantReplayScreen` must dispose evaluator handles exactly
once, including when a run is superseded or the screen is popped. Add a spy
handle in tests:

```dart
class _SpyHandle extends ReviewEvaluatorHandle {
  _SpyHandle()
      : super(
          evaluator: HeuristicEvaluator(),
          resolvedSource: EngineSources.heuristic,
        );

  int disposals = 0;

  @override
  Future<void> dispose() async {
    disposals++;
    await super.dispose();
  }
}
```

Assert `disposals == 1` after leaving mid-run and after a re-run supersedes a
previous handle.

---

## 11. CI/CD

### 11.1 Fast PR gate

```powershell
flutter analyze
flutter test test/ui --reporter expanded
```

### 11.2 Semantics and monkey gate

```powershell
flutter test test/ui/semantics_stability_test.dart --reporter expanded
flutter test test/ui/monkey_tap_test.dart --reporter expanded
```

### 11.3 Nightly Windows gate

```powershell
flutter test integration_test/accessibility_windows_test.dart -d windows
flutter build windows --release
powershell -ExecutionPolicy Bypass -File tool/windows_accessibility_smoke.ps1 `
  -Exe build\windows\x64\runner\Release\llm_chess_arena.exe `
  -RandomClicks 500
```

### 11.4 Coverage

```powershell
flutter test test/ui --coverage
```

Coverage percentage is not the goal. The goal is that every control in the
interaction matrix is exercised and every transition asserts the semantics
invariants. A high line-coverage number with no tap tests is not acceptable.

### 11.5 Flake policy

- A test that uses `pumpAndSettle` around a spinner, stream, or live game is a
  bug in the test.
- A test that depends on wall-clock time must inject the clock.
- A test that spawns a process must override the evaluator/turn factory.
- A test that leaves timers pending must call `disposeApp`.
- Any flaky test is quarantined with an issue link, not silently retried.

---

## 12. Prioritized roadmap

Approximate target: 250-300 widget tests plus 2 process-level checks.

| Priority | Deliverable | Tests |
|---|---|---:|
| P0 | `test/support/arena_test_harness.dart` | - |
| P0 | `test/support/semantics_invariants.dart` | - |
| P0 | `test/ui/chessboard_test.dart` | ~20 |
| P0 | `test/ui/shell_navigation_test.dart` | 16 |
| P0 | `test/ui/play_screen_test.dart` | ~30 |
| P0 | `test/ui/semantics_stability_test.dart` | ~32 |
| P0 | `test/ui/monkey_tap_test.dart` | 4 |
| P0 | `integration_test/accessibility_windows_test.dart` | 5 |
| P0 | `tool/windows_accessibility_smoke.ps1` | 2 checks |
| P1 | `test/ui/watch_screen_test.dart` | ~22 |
| P1 | `test/ui/arena_screen_test.dart` | ~26 |
| P1 | `test/ui/agent_setup_test.dart` | ~26 |
| P1 | `test/ui/review_screen_test.dart` | ~22 |
| P1 | `test/ui/variant_replay_test.dart` | ~18 |
| P2 | `test/ui/stats_screen_test.dart` | ~18 |
| P2 | `test/ui/settings_screen_test.dart` | ~14 |
| P2 | `test/ui/shared_widgets_test.dart` | ~20 |
| P2 | `test/ui/home_screen_test.dart` | 6 |

Implementation order:

1. Refactors 10.1-10.4 and 10.7.
2. Harness + semantics checker.
3. Chessboard, shell, semantics stability.
4. Play interaction + monkey tests (the reported repro).
5. Windows integration + UIA smoke + CI job.
6. Watch and Arena.
7. Agents, Review, Variant replay.
8. Stats, Settings, Home, shared widgets.

Why this order: it front-loads the highest-risk surface (semantics + Play),
gets a native crash gate in place early, then fills breadth. Stats/Settings/
Home are mostly rendering and are safe to do later.

---

## 13. Risks and open questions

### Risks

1. **Upstream fix timing.** The native crash may remain until Flutter ships a
   fixed engine. The UIA smoke will keep failing, which is the correct signal.
2. **Semantics tests can be brittle.** Labels and counts change when UI copy
   changes. Use semantic anchors (board labels, tooltips) and key-based
   finders; keep exact copy assertions to a minimum.
3. **Widget tests cannot prove the crash is gone.** Only the UIA smoke can.
   Do not remove the crash gate because "all tests pass".
4. **Process-static telemetry.** `StatsLog`, `QualityLog`, `ReviewLog`, and
   `VariantReviewLog` leak between tests unless cleared. A finished game in one
   test can spawn Stockfish or pollute another.
5. **Real engine/network in tests.** Review and AI turns must be faked, or the
   suite becomes slow, flaky, and environment-dependent.
6. **Timer leaks.** Watch/Play loops schedule timers; `disposeApp` must drain
   them or the framework fails the test.
7. **Arena mini-boards repeat labels.** Uniqueness assertions must be scoped.
8. **Static Elo.** `ArenaScreen._elo` leaks across tests until refactored.
9. **Accessibility automation availability.** The UIA smoke requires a Windows
   session with UIAutomationClient; it cannot run on Linux/macOS CI. Run it on
   a Windows runner or a dedicated VM.
10. **Random monkey tests.** They are deterministic only with fixed seeds and
    no `pumpAndSettle`; otherwise they become flaky and get disabled.

### Open questions

- Which Flutter release contains the #175041 fix, and does it cover the
  `results.back().front()` root-crowning case or only the null guard?
- Does the app's `IndexedStack` + `ExcludeSemantics` workaround fully prevent
  reparenting, or are there remaining transitions (theme switch, resize,
  route push) that still move nodes?
- Should the app ship a "safe mode" that disables custom semantics for users
  with a screen reader until the engine fix lands? This would be an
  accessibility regression; prefer fixing the tree.
- Do we need a Windows CI runner with Narrator/UIA, or is a scheduled manual
  run on a dev VM acceptable?
- Should `StatsLog` etc. become injectable stores instead of process-static
  abstractions? This would improve isolation but is a larger refactor.

---

## 14. Acceptance criteria

The future work is complete when:

1. The Windows UIA smoke survives 500 random clicks and >= 40 control
   invocations on a release build, with Narrator or Inspect.exe attached.
2. Event Viewer shows no new `flutter_windows.dll` `0xC0000005` during the
   smoke.
3. `flutter test test/ui` is green with zero pending-timer failures.
4. Every control in the interaction matrix has at least one test that asserts
   an observable behavior.
5. The semantics stability suite reports zero duplicate ids, zero null
   parents, and zero reparenting events across 50 rapid transitions.
6. Monkey tests complete ~2 x 350 grid taps and 2 x 1500 random taps without a
   Dart exception.
7. `flutter analyze` is clean.
8. The upgrade checklist in section 3.3 is part of the release runbook.

---

## Appendix A - Crash signature

```text
Exception:      0xC0000005 (access violation)
Module:         flutter_windows.dll
RVA:            0x3c1ea
Engine:         Flutter 3.47.7 stable, revision deb287481e
Source:         engine/src/flutter/shell/platform/common/accessibility_bridge.cc:229
Function:       flutter::AccessibilityBridge::CreateRemoveReparentedNodesUpdate
Faulting line:  if (child->parent()->id() == node_update.second.id)
Preceding guard: assert(child->parent())  // compiled out in release
Upstream:       flutter/flutter#175041
```

A secondary `0xC000041D` (unhandled exception in a user callback) was recorded
immediately after the access violation; treat it as a consequence, not a
separate root cause.

## Appendix B - Commands

```powershell
# Fast suite
flutter analyze
flutter test test/ui

# Specific gates
flutter test test/ui/semantics_stability_test.dart
flutter test test/ui/monkey_tap_test.dart

# Windows integration
flutter test integration_test/accessibility_windows_test.dart -d windows

# Release + native smoke
flutter build windows --release
powershell -ExecutionPolicy Bypass -File tool/windows_accessibility_smoke.ps1 `
  -Exe build\windows\x64\runner\Release\llm_chess_arena.exe `
  -RandomClicks 500

# Reproduce the report manually
flutter run -d windows
# Then attach Narrator or Inspect.exe and click through every destination.
```

## Appendix C - References

- flutter/flutter#175041 - AccessibilityBridge::CreateRemoveReparentedNodesUpdate
  crash.
- flutter/flutter#182444 - ListView + Tooltip AXTree error.
- flutter/flutter#190357 - Slider in a pushed route freezes the AX tree.
- flutter/flutter#192689 - duplicate of #175041.
- flutter/flutter#190903 - proposed null guard.
- flutter/flutter#98099, #118221, #103808 - earlier Windows AXTree crashes.
- Flutter engine source:
  `engine/src/flutter/shell/platform/common/accessibility_bridge.cc`.
- Flutter embedder API:
  `FlutterSemanticsUpdate`, `FlutterSemanticsNode2`,
  `FlutterSemanticsCustomAction2`.
