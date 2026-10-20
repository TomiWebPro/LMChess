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

/// Current "Move N" chip from the watch transport bar.
int _moveCount(WidgetTester tester) {
  final finder = find.textContaining(RegExp(r'^Move \d+$')).first;
  final text = tester.widget<Text>(finder).data!;
  return int.parse(text.split(' ').last);
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

    await tester.tap(find.text('Start'));
    await tester.pump();
    await _pumpSteps(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final afterStart = _moveCount(tester);
    expect(afterStart, greaterThan(0),
        reason: 'the pump must sequence at least one AI turn');

    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(find.text('Resume'), findsOneWidget);

    // Let any in-flight turn settle, then verify no new turns are scheduled.
    await _pumpSteps(tester, steps: 10);
    final pausedAt = _moveCount(tester);
    await _pumpSteps(tester, steps: 20);
    expect(_moveCount(tester), pausedAt,
        reason: 'a paused watch loop must not schedule more turns');
    expect(tester.takeException(), isNull);
  });
}
