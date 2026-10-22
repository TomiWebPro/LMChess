// Widget + unit tests for §15.3 fast ply scrubbing.
//
// Covers the shared ScrubShortcuts widget (key mapping, focus/visibility,
// disabled state), the scrubMotionFor helper, and keyboard scrubbing on all
// four replay-capable screens: Play (arrows/Home/End + motion + read-only
// past plies + return to live), Review, Variant Replay, and Watch. Uses
// deterministic fakes — never touches real network, engine, or wall-clock
// time. No pumpAndSettle around spinners or flights.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/app.dart' show ArenaApp;
import 'package:llm_chess_arena/src/chess/position.dart';
import 'package:llm_chess_arena/src/llm/mock_provider.dart';
import 'package:llm_chess_arena/src/llm/tool_schema.dart' show MoveToolCall;
import 'package:llm_chess_arena/src/llm/validation.dart' show FailureKind;
import 'package:llm_chess_arena/src/review/engine_adapter.dart'
    show EngineSources, HeuristicEvaluator;
import 'package:llm_chess_arena/src/ui/backend_bridge.dart'
    show
        ReviewLog,
        ReviewGame,
        ReviewEvaluatorHandle,
        clockProvider,
        reviewEvaluatorFactoryProvider,
        turnProviderFactoryProvider;
import 'package:llm_chess_arena/src/ui/screens/review_screen.dart';
import 'package:llm_chess_arena/src/ui/screens/variant_replay_screen.dart';
import 'package:llm_chess_arena/src/ui/screens/watch_screen.dart';
import 'package:llm_chess_arena/src/ui/ui_models.dart';
import 'package:llm_chess_arena/src/ui/widgets/boards.dart' show MoveList;
import 'package:llm_chess_arena/src/ui/widgets/chessboard.dart';
import 'package:llm_chess_arena/src/ui/widgets/scrub_shortcuts.dart';
import 'package:llm_chess_arena/src/ui/widgets/tab_visibility.dart';
import 'package:llm_chess_arena/src/variant/chaotic_engine.dart';
import 'package:llm_chess_arena/src/variant/interpretation.dart';
import 'package:llm_chess_arena/src/variant/variant_board.dart';
import 'package:llm_chess_arena/src/variant/variant_replay.dart';

import '../support/arena_test_harness.dart' as harness;
import '../support/semantics_invariants.dart';

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

/// Overrides: fake AI turns return legal UCI moves instantly (stepDelay=0)
/// and the clock is fixed UTC. Mirrors play_screen_test's `_playOverrides`.
List<Override> _playOverrides({String? fixedBlackReply}) => <Override>[
  turnProviderFactoryProvider.overrideWithValue((
    config,
    legalUcis, {
    seed,
    phrase,
  }) async {
    if (legalUcis.isEmpty) {
      return MockProvider(
        script: const <Object>[FailureKind.incompleteResponse],
        model: config.model,
      );
    }
    final uci = fixedBlackReply ?? legalUcis.first;
    return MockProvider(
      script: <Object>[
        MoveToolCall(
          from: uci.substring(0, 2),
          to: uci.substring(2, 4),
          promotion: uci.length > 4 ? uci.substring(4, 5) : null,
          phrase: phrase,
        ),
      ],
      model: config.model,
      stepDelay: Duration.zero,
    );
  }),
  clockProvider.overrideWithValue(() => DateTime.utc(2026, 1, 1)),
];

Future<void> _pumpPlayApp(
  WidgetTester tester, {
  Size size = const Size(1400, 1000),
  Iterable<Override>? overrides,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides?.toList() ?? _playOverrides(),
      child: ArenaApp(),
    ),
  );
  // Navigate to the Play tab — pump extra frames so layout settles.
  await tester.tap(find.text('Play').first);
  await tester.pump();
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(milliseconds: 100));
}

/// Moves a white pawn e2→e4 (White's first turn) and lets the fixed AI reply
/// e7→e5 land, leaving the game at ply 2 (live).
Future<void> _playOpening(
  WidgetTester tester, {
  String fixedBlackReply = 'e7e5',
}) async {
  // Play white e2→e4, then wait for the fixed black reply.
  await tester.tap(find.bySemanticsLabel('White piece on e2'));
  await tester.pump();
  await tester.tap(find.bySemanticsLabel('Empty square e4'));
  await tester.pump(const Duration(milliseconds: 800));
  // Sanity: the fixed black reply landed (the view is live at ply 2).
  expect(
    find.bySemanticsLabel(
      fixedBlackReply.startsWith('e7')
          ? 'Black piece on e5'
          : 'Black piece on ${fixedBlackReply.substring(2, 4)}',
    ),
    findsOneWidget,
  );
}

/// Screen-space center of a square on the (single) chessboard on screen.
Offset _centerOf(WidgetTester tester, String square) {
  final rect = tester.getRect(find.byType(Chessboard));
  final file = 'abcdefgh'.indexOf(square[0]);
  final rank = int.parse(square[1]) - 1;
  final col = orientationWhiteDefault(tester) ? file : 7 - file;
  final row = orientationWhiteDefault(tester) ? 7 - rank : rank;
  final cell = rect.width / 8;
  return rect.topLeft + Offset((col + 0.5) * cell, (row + 0.5) * cell);
}

bool orientationWhiteDefault(WidgetTester tester) {
  final board = tester.widget<Chessboard>(find.byType(Chessboard));
  return board.orientationWhite;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 160));
  await tester.pump(const Duration(milliseconds: 160));
  await tester.pump();
}

/// Switches the shell Play/Watch tab bar to [tab] and pumps in small slices
/// until the page animation has fully ended. The TabBarView page animation
/// runs a `DrivenScrollActivity` whose viewport releases pointer events only
/// after its ticker future completes; a single `pump(300ms)` lands exactly on
/// the boundary and the buttons below stay untappable. Small deterministic
/// slices reliably settle past it (§15.3 moves-panel interactions).
Future<void> _switchTab(WidgetTester tester, String tab) async {
  await tester.tap(find.text(tab).first);
  await tester.pump();
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump();
}

/// Quick synchronous review evaluator (mirrors review_screen_test).
Future<ReviewEvaluatorHandle> _quickEval() => Future.value(
  ReviewEvaluatorHandle(
    evaluator: HeuristicEvaluator(),
    resolvedSource: EngineSources.heuristic,
  ),
);

/// Seeds one two-ply standard game and pumps ReviewScreen inside a shell.
Future<void> _pumpReview(WidgetTester tester) async {
  ReviewLog.record(
    ReviewGame(
      id: 'scrub-review',
      whiteLabel: 'W',
      blackLabel: 'B',
      mode: 'standard',
      ucis: const ['e2e4', 'e7e5'],
      sans: const ['e4', 'e5'],
      fens: const [
        'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 2',
        'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 3',
      ],
      phrases: const <String?>['Opening', null],
      fallbackFlags: const <bool>[false, false],
    ),
  );
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        reviewEvaluatorFactoryProvider.overrideWithValue(_quickEval),
      ],
      child: const MaterialApp(home: Scaffold(body: ReviewScreen())),
    ),
  );
  await tester.pump(); // didChangeDependencies → review run
  await tester.pump(); // report lands
  await tester.pump(const Duration(milliseconds: 50));
}

// --- Variant replay fixtures (mirror variant_replay_test's builders) -------

VariantPlyRecord _buildPly({
  required int index,
  required VariantBoard before,
  required VariantBoard after,
  required AttemptedMove attempt,
  required InterpretedResult interpreted,
}) {
  final mover = before.sideToMove;
  final uci =
      '${attempt.fromSquareName}${attempt.toSquareName}${attempt.promotion ?? ''}';
  return VariantPlyRecord(
    ply: index,
    mover: mover.isWhite ? 'w' : 'b',
    agentId: 'agent-a',
    modelKey: 'mock-a',
    seed: 10 + index,
    fallback: false,
    attempt: VariantAttemptRecord(
      uci: uci,
      fromSquareName: attempt.fromSquareName,
      toSquareName: attempt.toSquareName,
      promotion: attempt.promotion,
      phrase: attempt.phrase,
      rawToolArgsJson:
          '{"from":"${attempt.fromSquareName}","to":"${attempt.toSquareName}"}',
      rawToolCallJson: <String, Object?>{
        'from': attempt.fromSquareName,
        'to': attempt.toSquareName,
      },
    ),
    wasLegal: interpreted.wasLegal,
    standardDetail: interpreted.standardDetail,
    interpretationKind: VariantInterpretationKind.fromStrategyId(
      interpreted.selected.strategyId,
    ),
    selected: VariantInterpretationRecord.fromCandidate(interpreted.selected),
    candidates: interpreted.candidates
        .map(VariantInterpretationRecord.fromCandidate)
        .toList(),
    events: interpreted.events,
    boardAfter: after,
    kingFacts: VariantKingFacts.between(before, after, mover),
    boardHashBefore: before.boardHash(),
    boardHashAfter: after.boardHash(),
    policy: interpreted.policy,
  );
}

/// A chaotic game with two plies (one legal e2e4, one illegal e2e7).
VariantGameRecord _variantGame() {
  final initial = VariantBoard.fromStandard(Position.initial());
  const legalAttempt = AttemptedMove(
    fromSquareName: 'e2',
    toSquareName: 'e4',
    phrase: 'Opening',
  );
  final legal = ChaoticRules.interpret(initial, legalAttempt, seed: 1);
  final afterLegal = legal.selected.resultingBoard;
  const illegalAttempt = AttemptedMove(
    fromSquareName: 'e2',
    toSquareName: 'e7',
    phrase: 'Long-range pawn',
  );
  final illegal = ChaoticRules.interpret(afterLegal, illegalAttempt, seed: 2);
  final afterIllegal = illegal.selected.resultingBoard;
  return VariantGameRecord(
    id: 'widget-replay',
    whiteLabel: 'White',
    blackLabel: 'Black',
    seed: 7,
    initialBoard: initial,
    plies: [
      _buildPly(
        index: 0,
        before: initial,
        after: afterLegal,
        attempt: legalAttempt,
        interpreted: legal,
      ),
      _buildPly(
        index: 1,
        before: afterLegal,
        after: afterIllegal,
        attempt: illegalAttempt,
        interpreted: illegal,
      ),
    ],
    outcome: '*',
    reason: 'test',
  );
}

Future<void> _pumpVariant(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(home: VariantReplayScreen(record: _variantGame())),
    ),
  );
  await tester.pump();
}

int _watchMoveCount(WidgetTester tester) {
  final text = tester
      .widget<Text>(find.textContaining(RegExp(r'^Move \d+$')).first)
      .data!;
  return int.parse(text.split(' ').last);
}

Future<void> _pumpWatch(
  WidgetTester tester, {
  Size size = const Size(1400, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ProviderScope(
          overrides: <Override>[
            ..._playOverrides(),
            agentListProvider.overrideWith(
              (ref) => AgentListStore(seedDemos: true),
            ),
          ],
          child: const WatchScreen(initialSeed: 42),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('Start'));
  await tester.pump();
  // Pump until at least two moves are on the board.
  for (var i = 0; i < 20 && _watchMoveCount(tester) < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(milliseconds: 50));
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

void main() {
  setUp(harness.resetTelemetry);

  group('scrubMotionFor helper', () {
    test('forward +1 returns a forward BoardMove', () {
      final motion = scrubMotionFor('e2e4', 1);
      expect(motion, isNotNull);
      expect(motion!.from.name, 'e2');
      expect(motion.to.name, 'e4');
    });

    test('backward -1 reverses the from/to pair', () {
      final motion = scrubMotionFor('e2e4', -1);
      expect(motion, isNotNull);
      expect(motion!.from.name, 'e4');
      expect(motion.to.name, 'e2');
    });

    test('multi-ply jumps, null and malformed UCI snap', () {
      expect(scrubMotionFor('e2e4', 3), isNull);
      expect(scrubMotionFor('e2e4', -5), isNull);
      expect(scrubMotionFor(null, 1), isNull);
      expect(scrubMotionFor('12', 1), isNull);
      expect(scrubMotionFor('e2zz', 1), isNull);
      expect(scrubMotionFor('e2e4', 0), isNull);
    });
  });

  group('ScrubShortcuts widget', () {
    testWidgets('arrows/Home/End map to the four actions', (tester) async {
      final seen = <ScrubAction>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ScrubShortcuts(
            enabled: true,
            onAction: seen.add,
            child: const SizedBox(width: 400, height: 400),
          ),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      expect(seen, <ScrubAction>[
        ScrubAction.stepBack,
        ScrubAction.stepForward,
        ScrubAction.toStart,
        ScrubAction.toEnd,
      ]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('disabled ignores arrow keys', (tester) async {
      final seen = <ScrubAction>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ScrubShortcuts(
            enabled: false,
            onAction: seen.add,
            child: const SizedBox(width: 400, height: 400),
          ),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(seen, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hidden tab ignores keys and releases focus', (tester) async {
      final seen = <ScrubAction>[];
      var visible = true;
      late StateSetter hostSetState;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              hostSetState = setState;
              return TabVisibility(
                isVisible: visible,
                child: ScrubShortcuts(
                  enabled: true,
                  onAction: seen.add,
                  child: const SizedBox(width: 400, height: 400),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();
      // First key while visible lands.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(seen, <ScrubAction>[ScrubAction.stepBack]);
      // Hide the tab: keys are ignored and the node no longer holds focus.
      hostSetState(() => visible = false);
      await tester.pump();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(seen, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  });

  group('Play keyboard scrubbing (§15.3)', () {
    testWidgets('arrow keys step one ply back and forward through the game', (
      tester,
    ) async {
      await _pumpPlayApp(
        tester,
        overrides: _playOverrides(fixedBlackReply: 'e7e5'),
      );
      await _playOpening(tester);
      // Live: ply 2 — e4/e5, e7 empty.
      expect(find.bySemanticsLabel('White piece on e4'), findsOneWidget);
      expect(find.bySemanticsLabel('Black piece on e5'), findsOneWidget);
      expect(find.bySemanticsLabel('Empty square e7'), findsOneWidget);
      // One Left → ply 1: black pawn back on e7.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      await _settle(tester);
      expect(find.bySemanticsLabel('Black piece on e7'), findsOneWidget);
      expect(find.bySemanticsLabel('Empty square e5'), findsOneWidget);
      // Left again → ply 0: start position.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      await _settle(tester);
      expect(find.bySemanticsLabel('White piece on e2'), findsOneWidget);
      expect(find.bySemanticsLabel('Empty square e4'), findsOneWidget);
      // Right → back to ply 1.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await _settle(tester);
      expect(find.bySemanticsLabel('Black piece on e7'), findsOneWidget);
      // End → live again.
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      await _settle(tester);
      expect(find.bySemanticsLabel('White piece on e4'), findsOneWidget);
      expect(find.bySemanticsLabel('Black piece on e5'), findsOneWidget);
      // Home → start.
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      await _settle(tester);
      expect(find.bySemanticsLabel('White piece on e2'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await harness.disposeApp(tester);
    });

    testWidgets(
      'adjacent forward and backward steps animate via the motion layer',
      (tester) async {
        await _pumpPlayApp(
          tester,
          overrides: _playOverrides(fixedBlackReply: 'e7e5'),
        );
        await _playOpening(tester);
        // Home → ply 0.
        await tester.sendKeyEvent(LogicalKeyboardKey.home);
        await tester.pump();
        await _settle(tester);
        // Forward step into ply 1 slides e2→e4.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump(const Duration(milliseconds: 40));
        expect(
          find.byKey(const ValueKey<String>('chessboard-motion-overlay')),
          findsOneWidget,
        );
        await _settle(tester);
        expect(
          find.byKey(const ValueKey<String>('chessboard-motion-overlay')),
          findsNothing,
        );
        // Backward step from ply 1 slides e4→e2 (reversed motion).
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump(const Duration(milliseconds: 40));
        expect(
          find.byKey(const ValueKey<String>('chessboard-motion-overlay')),
          findsOneWidget,
        );
        await _settle(tester);
        expect(
          find.byKey(const ValueKey<String>('chessboard-motion-overlay')),
          findsNothing,
        );
        // End jumps straight to live. The FINAL transition (e7→e5) may
        // animate — §15.3 "animate the final transition only" — but the
        // intermediate plies never do, and one settle clears the flight.
        await tester.sendKeyEvent(LogicalKeyboardKey.end);
        await tester.pump(const Duration(milliseconds: 40));
        expect(
          find.byKey(const ValueKey<String>('chessboard-motion-overlay')),
          findsOneWidget,
        );
        await _settle(tester);
        expect(
          find.byKey(const ValueKey<String>('chessboard-motion-overlay')),
          findsNothing,
        );
        // Landing on the live position is correct.
        expect(find.bySemanticsLabel('White piece on e4'), findsOneWidget);
        expect(find.bySemanticsLabel('Black piece on e5'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await harness.disposeApp(tester);
      },
    );

    testWidgets('while reviewing a past ply the board is read-only', (
      tester,
    ) async {
      await _pumpPlayApp(
        tester,
        overrides: _playOverrides(fixedBlackReply: 'e7e5'),
      );
      await _playOpening(tester);
      // Scrub back to the start position.
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      await _settle(tester);
      // The return control lives in the Moves tab (Play's moves panel).
      await _switchTab(tester, 'Moves');
      expect(find.text('Return to live position'), findsOneWidget);
      // Click-click on e2→e4 while scrubbed must NOT move (board read-only).
      await tester.tap(find.bySemanticsLabel('White piece on e2'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Empty square e4'));
      await tester.pump(const Duration(milliseconds: 800));
      // View is still the start position — no move was applied.
      expect(find.bySemanticsLabel('White piece on e2'), findsOneWidget);
      expect(find.bySemanticsLabel('Empty square e4'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await harness.disposeApp(tester);
    });

    testWidgets('drag is disabled on a scrubbed (past) ply', (tester) async {
      await _pumpPlayApp(
        tester,
        overrides: _playOverrides(fixedBlackReply: 'e7e5'),
      );
      await _playOpening(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      await _settle(tester);
      // Attempt a drag from e2 to e4 — it must not apply a move.
      final gesture = await tester.startGesture(_centerOf(tester, 'e2'));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveTo(_centerOf(tester, 'e4'));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.bySemanticsLabel('White piece on e2'), findsOneWidget);
      expect(find.bySemanticsLabel('Empty square e4'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await harness.disposeApp(tester);
    });

    testWidgets('Return to live position restores input and clears the scrub', (
      tester,
    ) async {
      await _pumpPlayApp(
        tester,
        overrides: _playOverrides(fixedBlackReply: 'e7e5'),
      );
      await _playOpening(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      await _settle(tester);
      await _switchTab(tester, 'Moves');
      expect(find.text('Return to live position'), findsOneWidget);
      await tester.tap(find.text('Return to live position'));
      await tester.pump();
      await _settle(tester);
      expect(find.text('Return to live position'), findsNothing);
      // Input restored: play a real move and watch it apply.
      await tester.tap(find.bySemanticsLabel('White piece on g1'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Empty square f3'));
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.bySemanticsLabel('White piece on f3'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await harness.disposeApp(tester);
    });

    testWidgets(
      '20 rapid arrow presses coalesce with no exceptions or timers',
      (tester) async {
        await _pumpPlayApp(
          tester,
          overrides: _playOverrides(fixedBlackReply: 'e7e5'),
        );
        await _playOpening(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.home);
        await tester.pump();
        await _settle(tester);
        // Rapid repeat toward live: only the last target wins per frame and the
        // single board controller retargets; no per-press controllers queue.
        for (var i = 0; i < 20; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pump(const Duration(milliseconds: 4));
        }
        await _settle(tester);
        expect(find.bySemanticsLabel('White piece on e4'), findsOneWidget);
        expect(find.bySemanticsLabel('Black piece on e5'), findsOneWidget);
        expect(tester.takeException(), isNull);
        // Backward burst.
        for (var i = 0; i < 20; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          await tester.pump(const Duration(milliseconds: 4));
        }
        await _settle(tester);
        expect(find.bySemanticsLabel('White piece on e2'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await harness.disposeApp(tester);
      },
    );

    testWidgets('semantics stays at 64 square nodes with zero reparenting '
        'through rapid seeking', (tester) async {
      await _pumpPlayApp(
        tester,
        overrides: _playOverrides(fixedBlackReply: 'e7e5'),
      );
      await _playOpening(tester);
      final semanticsHandle = tester.ensureSemantics();
      try {
        final before = captureSemantics(tester);
        expectSemanticsTreeInvariants(tester);
        // Scrub end-to-end and back through the motion layer.
        await tester.sendKeyEvent(LogicalKeyboardKey.home);
        await tester.pump();
        for (var i = 0; i < 10; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pump(const Duration(milliseconds: 8));
        }
        await _settle(tester);
        final after = captureSemantics(tester);
        expectSemanticsTreeInvariants(tester);
        expectNoReparenting(parentMap(before), parentMap(after));
        expectSquareSemantics(
          tester,
          expectedCount: 64,
          requireUniqueSquares: true,
        );
        expect(tester.takeException(), isNull);
      } finally {
        semanticsHandle.dispose();
      }
      await harness.disposeApp(tester);
    });
  });

  group('Review keyboard scrubbing (§15.3)', () {
    testWidgets('arrows/Home/End move the replay cursor', (tester) async {
      await _pumpReview(tester);
      expect(find.text('Ply 0 / 2'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(find.text('Ply 1 / 2'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(find.text('Ply 2 / 2'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(find.text('Ply 1 / 2'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(find.text('Ply 0 / 2'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      expect(find.text('Ply 2 / 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await harness.disposeApp(tester);
    });

    testWidgets('forward and backward one-ply scrubs animate the after board', (
      tester,
    ) async {
      await _pumpReview(tester);
      // Forward into ply 1: e2→e4 slides on the after board.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 40));
      expect(
        find.byKey(const ValueKey<String>('chessboard-motion-overlay')),
        findsOneWidget,
      );
      await _settle(tester);
      expect(
        find.byKey(const ValueKey<String>('chessboard-motion-overlay')),
        findsNothing,
      );
      // Backward to ply 0: reversed e4→e2 slides back.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(milliseconds: 40));
      expect(
        find.byKey(const ValueKey<String>('chessboard-motion-overlay')),
        findsOneWidget,
      );
      await _settle(tester);
      // End (two-ply jump) snaps: no flight.
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump(const Duration(milliseconds: 40));
      expect(
        find.byKey(const ValueKey<String>('chessboard-motion-overlay')),
        findsNothing,
      );
      await _settle(tester);
      expect(tester.takeException(), isNull);
      await harness.disposeApp(tester);
    });
  });

  group('Variant Replay keyboard scrubbing (§15.3)', () {
    testWidgets('arrows/Home/End move the replay cursor and clamp at bounds', (
      tester,
    ) async {
      await _pumpVariant(tester);
      expect(find.text('Ply 0 / 2'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(find.text('Ply 1 / 2'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(find.text('Ply 2 / 2'), findsOneWidget);
      // Extra Right at the end clamps.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(find.text('Ply 2 / 2'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(find.text('Ply 1 / 2'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(find.text('Ply 0 / 2'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      expect(find.text('Ply 2 / 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await harness.disposeApp(tester);
    });

    testWidgets(
      'forward legal scrub animates; backward legal scrub slides back',
      (tester) async {
        await _pumpVariant(tester);
        // Ply 0 → 1: the legal e2e4 attempt animates.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump(const Duration(milliseconds: 40));
        expect(
          find.byKey(const ValueKey<String>('chessboard-motion-overlay')),
          findsOneWidget,
        );
        await _settle(tester);
        expect(
          find.byKey(const ValueKey<String>('chessboard-motion-overlay')),
          findsNothing,
        );
        // Back to 0: reversed e4→e2 slides back.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump(const Duration(milliseconds: 40));
        expect(
          find.byKey(const ValueKey<String>('chessboard-motion-overlay')),
          findsOneWidget,
        );
        await _settle(tester);
        expect(tester.takeException(), isNull);
        await harness.disposeApp(tester);
      },
    );
  });

  group('Watch keyboard scrubbing (§15.3)', () {
    testWidgets(
      'arrows scrub back to a past position and End returns to live',
      (tester) async {
        await _pumpWatch(tester);
        expect(find.text('Return to live position'), findsNothing);
        final liveSquares = tester
            .widget<Chessboard>(find.byType(Chessboard))
            .squares;
        // One Left → scrubbed back one ply: board snapshot changes.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        await _settle(tester);
        expect(find.text('Return to live position'), findsOneWidget);
        final backSquares = tester
            .widget<Chessboard>(find.byType(Chessboard))
            .squares;
        expect(backSquares, isNot(equals(liveSquares)));
        // Two more Lefts keep changing the snapshot (adjacent plies differ).
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        final back2 = tester
            .widget<Chessboard>(find.byType(Chessboard))
            .squares;
        expect(back2, isNot(equals(backSquares)));
        // End → live: button disappears.
        await tester.sendKeyEvent(LogicalKeyboardKey.end);
        await tester.pump();
        expect(find.text('Return to live position'), findsNothing);
        expect(tester.takeException(), isNull);
        await harness.disposeApp(tester);
      },
    );

    testWidgets('backward scrub animates via the motion layer', (tester) async {
      await _pumpWatch(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(milliseconds: 40));
      expect(
        find.byKey(const ValueKey<String>('chessboard-motion-overlay')),
        findsOneWidget,
      );
      await _settle(tester);
      expect(
        find.byKey(const ValueKey<String>('chessboard-motion-overlay')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await harness.disposeApp(tester);
    });

    testWidgets('move-list tap seeks and shows Return to live', (tester) async {
      await _pumpWatch(tester);
      // Switch to the Moves tab.
      await _switchTab(tester, 'Moves');
      // Tap the first move entry.
      final firstEntry = find.descendant(
        of: find.byType(MoveList),
        matching: find.byType(InkWell),
      );
      expect(firstEntry, findsWidgets);
      await tester.tap(firstEntry.first);
      await tester.pump();
      expect(find.text('Return to live position'), findsOneWidget);
      // Return to live clears the scrub.
      await tester.tap(find.text('Return to live position'));
      await tester.pump();
      expect(find.text('Return to live position'), findsNothing);
      expect(tester.takeException(), isNull);
      await harness.disposeApp(tester);
    });
  });
}
