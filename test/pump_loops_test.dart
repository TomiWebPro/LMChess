// Behavior locks for the play and watch turn loops themselves (as opposed to
// the shared replay core in `game_mirror_test.dart`).
//
// These drive the real screens with the seeded demo agents and the in-process
// mock provider, so they pin the observable contract:
//   * play: human move → mirror advance → one AI reply, then wait for input;
//   * watch: Start runs turns sequentially; Pause stops scheduling new turns
//     once the in-flight one settles (no runaway loop).
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/ui/screens/play_screen.dart';
import 'package:llm_chess_arena/src/ui/screens/watch_screen.dart';
import 'package:llm_chess_arena/src/ui/widgets/chessboard.dart';

/// Total plies applied, read from the Moves tab header (`Ply a / b`).
///
/// The header lives in the Moves tab (offstage until selected), so offstage
/// widgets are included. Before the first move the panel shows
/// `No moves yet` and the count is 0.
int _moveCount(WidgetTester tester) {
  final header = find.textContaining(
    RegExp(r'^Ply \d+ / \d+$'),
    skipOffstage: false,
  );
  if (header.evaluate().isEmpty) return 0;
  final text = tester.widget<Text>(header.first).data!;
  return int.parse(text.split('/').last.trim());
}

/// Transport overlay controls: idle/terminal shows a `Start` button, while a
/// live game shows icon-only Pause/Resume + Stop buttons with tooltips.
Finder _startControl() => find.text('Start');
Finder _pauseControl() => find.byTooltip('Pause');
Finder _resumeControl() => find.byTooltip('Resume');

/// Selects a panel tab and waits for the page animation to settle.
///
/// Tab pages are built lazily, so content (e.g. the Moves `Ply a / b`
/// header) only exists once the controller stops changing.
Future<void> _selectTab(WidgetTester tester, String name) async {
  await tester.tap(find.text(name));
  final controller =
      DefaultTabController.of(tester.element(find.byType(TabBar)));
  for (var i = 0; i < 20 && controller.indexIsChanging; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
  await tester.pump(const Duration(milliseconds: 100));
}

/// Selects the Moves tab (see [_selectTab]).
Future<void> _showMovesTab(WidgetTester tester) => _selectTab(tester, 'Moves');

/// Pumps until at least [min] plies are applied (or [maxSteps] is hit).
///
/// Move count is read from the Moves tab header, so call [_showMovesTab]
/// first. Each mock turn takes several pump cycles.
Future<void> _waitForMoves(WidgetTester tester, int min,
    {int maxSteps = 80}) async {
  for (var i = 0; i < maxSteps && _moveCount(tester) < min; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Taps the centre of [square] on the first chessboard.
///
/// Coordinate taps avoid relying on semantics hit-testing (the per-cell
/// Semantics node is larger than the gesture surface in some layouts).
Future<void> _tapSquare(
  WidgetTester tester,
  String square,
) async {
  final rect = tester.getRect(find.byType(Chessboard).first);
  // The board fills min(width, height) and is centred inside its box.
  final size = math.min(rect.width, rect.height);
  final left = rect.left + (rect.width - size) / 2;
  final top = rect.top + (rect.height - size) / 2;
  final cell = size / 8;
  final file = square.codeUnitAt(0) - 'a'.codeUnitAt(0);
  final rank = int.parse(square.substring(1));
  // White orientation: rank 1 is the bottom row.
  final row = 8 - rank;
  await tester.tapAt(
    Offset(
      left + (file + 0.5) * cell,
      top + (row + 0.5) * cell,
    ),
  );
}

/// Advances time in small steps so chained streaming delays can run (a single
/// large `pump` only fires the timers that existed when it started).
Future<void> _pumpSteps(
  WidgetTester tester, {
  int steps = 12,
  Duration step = const Duration(milliseconds: 100),
}) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(step);
  }
}

void main() {
  testWidgets('play loop: human move advances the board, AI replies once',
      (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: PlayScreen())),
      ),
    );
    await tester.pump();

    // White pawn e2 → e4 through the real orchestrator.
    await _tapSquare(tester, 'e2');
    await tester.pump();
    await _tapSquare(tester, 'e4');
    await _pumpSteps(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // The mirror replayed the human move and the scripted AI answered.
    expect(find.bySemanticsLabel('White piece on e4'), findsOneWidget);
    expect(find.bySemanticsLabel('Empty square e2'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('watch loop: Start advances turns and Pause stops scheduling',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: WatchScreen())),
      ),
    );
    await tester.pump();

    await tester.tap(_startControl());
    await tester.pump();
    await _showMovesTab(tester);
    await _waitForMoves(tester, 1);

    final afterStart = _moveCount(tester);
    expect(afterStart, greaterThan(0),
        reason: 'the pump must sequence at least one AI turn');

    await tester.tap(_pauseControl());
    await tester.pump();
    expect(_resumeControl(), findsOneWidget);

    // Let any in-flight turn settle, then verify no new turns are scheduled.
    await _pumpSteps(tester, steps: 10);
    final pausedAt = _moveCount(tester);
    await _pumpSteps(tester, steps: 20);
    expect(_moveCount(tester), pausedAt,
        reason: 'a paused watch loop must not schedule more turns');
    expect(tester.takeException(), isNull);
  });
}
