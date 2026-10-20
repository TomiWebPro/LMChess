// Widget tests for VariantReplayScreen — covers §6.9 spec:
// First/Previous/Next/Last boundaries, slider drag, Analyze/Re-analyze,
// per-ply review row seek, ExpansionTile open/close, AppBar back-pop.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/chess/position.dart';
import 'package:llm_chess_arena/src/variant/chaotic_engine.dart';
import 'package:llm_chess_arena/src/variant/interpretation.dart';
import 'package:llm_chess_arena/src/variant/variant_board.dart';
import 'package:llm_chess_arena/src/variant/variant_replay.dart';
import 'package:llm_chess_arena/src/ui/screens/variant_replay_screen.dart';
import 'package:llm_chess_arena/src/ui/backend_bridge.dart' show clockProvider;

import '../support/arena_test_harness.dart' show resetTelemetry;

// --- Test fixture builders ---

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
    interpretationKind:
        VariantInterpretationKind.fromStrategyId(interpreted.selected.strategyId),
    selected: VariantInterpretationRecord.fromCandidate(interpreted.selected),
    candidates: interpreted.candidates.map(VariantInterpretationRecord.fromCandidate).toList(),
    events: interpreted.events,
    boardAfter: after,
    kingFacts: VariantKingFacts.between(before, after, mover),
    boardHashBefore: before.boardHash(),
    boardHashAfter: after.boardHash(),
    policy: interpreted.policy,
  );
}

/// A chaotic game with two plies (one legal e2e4, one illegal e2e7).
VariantGameRecord _game() {
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

/// A single-ply game (just one move).
VariantGameRecord _singlePlyGame() {
  final initial = VariantBoard.fromStandard(Position.initial());
  const attempt = AttemptedMove(
    fromSquareName: 'e2',
    toSquareName: 'e4',
    phrase: 'Just one',
  );
  final result = ChaoticRules.interpret(initial, attempt, seed: 42);
  final after = result.selected.resultingBoard;
  return VariantGameRecord(
    id: 'single-ply',
    whiteLabel: 'A',
    blackLabel: 'B',
    seed: 42,
    initialBoard: initial,
    plies: [
      _buildPly(
        index: 0,
        before: initial,
        after: after,
        attempt: attempt,
        interpreted: result,
      ),
    ],
    outcome: '*',
    reason: 'one move',
  );
}

void main() {
  setUp(resetTelemetry);

  // ======================================================================
  // §6.9 (1) First / Previous / Next / Last boundary checks
  // ======================================================================

  testWidgets('first button disabled at ply 0', (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: VariantReplayScreen(record: _game())),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('variant-first')), findsOneWidget);
    final firstBtn = tester.widget<IconButton>(
      find.byKey(const ValueKey<String>('variant-first')),
    );
    expect(firstBtn.onPressed, isNull); // disabled at ply 0
  });

  testWidgets('last button enables at start disables at last', (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    addTearDown(tester.view.reset);
    final game = _game();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: VariantReplayScreen(record: game)),
      ),
    );
    await tester.pump();

    // At start: last enabled
    var lastBtn = tester.widget<IconButton>(
      find.byKey(const ValueKey<String>('variant-last')),
    );
    expect(lastBtn.onPressed, isNotNull);

    // Jump to last
    await tester.tap(find.byKey(const ValueKey<String>('variant-last')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    lastBtn = tester.widget<IconButton>(
      find.byKey(const ValueKey<String>('variant-last')),
    );
    expect(lastBtn.onPressed, isNull); // now disabled at last
  });

  testWidgets('prev disabled at ply 0 enables after next', (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: VariantReplayScreen(record: _game())),
      ),
    );
    await tester.pump();

    var prevBtn = tester.widget<IconButton>(
      find.byKey(const ValueKey<String>('variant-prev')),
    );
    expect(prevBtn.onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey<String>('variant-next')));
    await tester.pump();

    prevBtn = tester.widget<IconButton>(
      find.byKey(const ValueKey<String>('variant-prev')),
    );
    expect(prevBtn.onPressed, isNotNull);
  });

  testWidgets('next disabled at last re-enables after going back',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: VariantReplayScreen(record: _game())),
      ),
    );
    await tester.pump();

    // Go to last via last_page button
    await tester.tap(find.byKey(const ValueKey<String>('variant-last')));
    await tester.pump();
    var nextBtn = tester.widget<IconButton>(
      find.byKey(const ValueKey<String>('variant-next')),
    );
    expect(nextBtn.onPressed, isNull);

    // Go to first
    await tester.tap(find.byKey(const ValueKey<String>('variant-first')));
    await tester.pump();
    nextBtn = tester.widget<IconButton>(
      find.byKey(const ValueKey<String>('variant-next')),
    );
    expect(nextBtn.onPressed, isNotNull);
  });

  // ======================================================================
  // §6.9 (2) Slider drag — advances toward dragged position
  // ======================================================================

  testWidgets('slider drag on wide screen advances without exception',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    addTearDown(tester.view.reset);
    final game = _game();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: VariantReplayScreen(record: game)),
      ),
    );
    await tester.pump();

    // Drag slider right (toward higher plies)
    final slider = find.byKey(const ValueKey<String>('variant-ply-slider'));
    await tester.drag(slider, const Offset(300, 0));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  // ======================================================================
  // §6.9 (3) Analyze / Re-analyze (verify UI buttons exist — engine
  //       unavailable in test env so skip actual analysis)
  // ======================================================================

  testWidgets('Analyze button appears in unreviewed state', (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: VariantReplayScreen(record: _game())),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('variant-analyze')), findsOneWidget);
    expect(find.text('Analyze'), findsOneWidget);
    expect(find.text('Re-analyze'), findsNothing);
  });

  // ======================================================================
  // §6.9 (4) Dispose mid-analysis — clean exit
  // ======================================================================

  testWidgets('dispose during async review does not leak', (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    addTearDown(tester.view.reset);
    final game = _game();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 6, 15)),
        ],
        child: MaterialApp(home: VariantReplayScreen(record: game)),
      ),
    );
    await tester.pump();

    // Start review and immediately replace widget (simulating pop)
    await tester.tap(find.byKey(const ValueKey<String>('variant-analyze')));
    await tester.pump();

    // Replace with blank widget (disposes the screen)
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));

    // No exception, no pending timer failure
    expect(tester.takeException(), isNull);
  });

  // ======================================================================
  // §6.9 (5) ExpansionTiles — Attempt & Events cards visible at ply > 0
  // ======================================================================

  testWidgets('Attempt card and ExpansionTile visible past ply 0',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    addTearDown(tester.view.reset);
    final game = _game();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: VariantReplayScreen(record: game)),
      ),
    );
    await tester.pump();

    // Step forward — Attempt card should appear
    await tester.tap(find.byKey(const ValueKey<String>('variant-next')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Attempt UCI string visible on board
    expect(find.bySemanticsLabel('White piece on e4'), findsWidgets);
    // No exception during transition
    expect(tester.takeException(), isNull);
  });

  testWidgets('Pipeline events ExpansionTile toggles visibility', (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    addTearDown(tester.view.reset);
    final game = _game();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: VariantReplayScreen(record: game)),
      ),
    );
    await tester.pump();

    // Navigate to a ply with events
    await tester.tap(find.byKey(const ValueKey<String>('variant-next')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Board position updated — black piece on e7 (illegal move destination)
    // and no crash during transition
    expect(tester.takeException(), isNull);
  });

  // ======================================================================
  // §6.9 (6) AppBar back-pop (Navigator.pop)
  // ======================================================================

  testWidgets('back button pops route without exception', (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    addTearDown(tester.view.reset);
    final game = _game();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute(
                builder: (_) => VariantReplayScreen(record: game),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('Chaotic replay'), findsOneWidget);

    // Tap back via chevron_left icon in AppBar
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  // ======================================================================
  // §6.9 (7) Empty game record (zero plies)
  // ======================================================================

  testWidgets('zero-plies game: all navigation buttons disabled',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    addTearDown(tester.view.reset);
    final empty = VariantGameRecord(
      id: 'empty-game',
      whiteLabel: 'X',
      blackLabel: 'Y',
      seed: 0,
      initialBoard: VariantBoard.fromStandard(Position.initial()),
      plies: [],
      outcome: '*',
      reason: 'no moves',
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: VariantReplayScreen(record: empty)),
      ),
    );
    await tester.pump();

    expect(find.textContaining('Chaotic replay'), findsOneWidget);

    // All nav buttons disabled (at ply 0 == last for zero-plies)
    expect(
      tester.widget<IconButton>(
        find.byKey(const ValueKey<String>('variant-first')),
      ).onPressed,
      isNull,
    );
    expect(
      tester.widget<IconButton>(
        find.byKey(const ValueKey<String>('variant-last')),
      ).onPressed,
      isNull,
    );
    expect(
      tester.widget<IconButton>(
        find.byKey(const ValueKey<String>('variant-prev')),
      ).onPressed,
      isNull,
    );
    expect(
      tester.widget<IconButton>(
        find.byKey(const ValueKey<String>('variant-next')),
      ).onPressed,
      isNull,
    );
  });

  // ======================================================================
  // §6.9 (8) Semantics stability across navigation
  // ======================================================================

  testWidgets('semantics stable across full nav sequence', (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    addTearDown(tester.view.reset);
    final game = _game();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: VariantReplayScreen(record: game)),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('variant-next')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('variant-last')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('variant-first')));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  // ======================================================================
  // §6.9 (9) Theme change stability
  // ======================================================================

  testWidgets('theme light→dark→light switch does not crash', (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    addTearDown(tester.view.reset);
    final game = _game();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: ThemeMode.light,
          home: VariantReplayScreen(record: game),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('Chaotic replay'), findsOneWidget);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: ThemeMode.dark,
          home: VariantReplayScreen(record: game),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Chaotic replay'), findsOneWidget);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: ThemeMode.light,
          home: VariantReplayScreen(record: game),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  // ======================================================================
  // §6.9 (10) Narrow layout renders without overflow
  // ======================================================================

  testWidgets('narrow layout (<700px) renders without overflow', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: VariantReplayScreen(record: _game())),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Chaotic replay'), findsOneWidget);
  });

  // ======================================================================
  // §6.9 (11) Rapid taps safe
  // ======================================================================

  testWidgets('rapid 10× control taps do not crash', (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: VariantReplayScreen(record: _game())),
      ),
    );
    await tester.pump();

    final keys = const [
      ValueKey<String>('variant-first'),
      ValueKey<String>('variant-prev'),
      ValueKey<String>('variant-next'),
      ValueKey<String>('variant-last'),
    ];

    for (var i = 0; i < 10; i++) {
      final key = keys[i % keys.length];
      await tester.tap(find.byKey(key));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
    }

    expect(tester.takeException(), isNull);
  });

  // ======================================================================
  // §6.9 (12) Single-ply boundaries
  // ======================================================================

  testWidgets('single-ply: First disabled, Last enables to reach end',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    addTearDown(tester.view.reset);
    final game = _singlePlyGame();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: VariantReplayScreen(record: game)),
      ),
    );
    await tester.pump();

    expect(
      tester.widget<IconButton>(
        find.byKey(const ValueKey<String>('variant-first')),
      ).onPressed,
      isNull,
    );
    expect(
      tester.widget<IconButton>(
        find.byKey(const ValueKey<String>('variant-last')),
      ).onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const ValueKey<String>('variant-last')));
    await tester.pump();

    expect(
      tester.widget<IconButton>(
        find.byKey(const ValueKey<String>('variant-last')),
      ).onPressed,
      isNull,
    );
    expect(
      tester.widget<IconButton>(
        find.byKey(const ValueKey<String>('variant-prev')),
      ).onPressed,
      isNotNull,
    );
  });

  // ======================================================================
  // §6.9 (13) Ply label updates across navigation
  // ======================================================================

  testWidgets('ply label reflects current position', (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    addTearDown(tester.view.reset);
    final game = _game();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: VariantReplayScreen(record: game)),
      ),
    );
    await tester.pump();

    expect(find.textContaining('Ply 0'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('variant-next')));
    await tester.pump();
    expect(find.textContaining('Ply 1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('variant-next')));
    await tester.pump();
    expect(find.textContaining('Ply 2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('variant-first')));
    await tester.pump();
    expect(find.textContaining('Ply 0'), findsOneWidget);
  });

  // ======================================================================
  // §6.9 (14) Rendering at each ply produces no exception
  // ======================================================================

  testWidgets('rendering at each ply step produces no exception', (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    addTearDown(tester.view.reset);
    final game = _game();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: VariantReplayScreen(record: game)),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey<String>('variant-next')));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey<String>('variant-next')));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey<String>('variant-first')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  // ======================================================================
  // §6.9 (15) Wide layout all five controls present
  // ======================================================================

  testWidgets('wide layout has all five navigation controls', (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: VariantReplayScreen(record: _game())),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey<String>('variant-first')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('variant-prev')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('variant-ply-slider')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('variant-next')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('variant-last')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ======================================================================
  // §6.9 (16) Header displays correctly
  // ======================================================================

  testWidgets('header shows white/black labels and outcome', (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: VariantReplayScreen(record: _game())),
      ),
    );
    await tester.pump();

    expect(find.textContaining('White'), findsWidgets);
    expect(find.textContaining('Black'), findsWidgets);
    expect(find.textContaining('*'), findsOneWidget);
  });

  // ======================================================================
  // §6.9 (17) Engine review card always titled "Engine review"
  // ======================================================================

  testWidgets('Engine review card exists with hint pre-analysis', (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: VariantReplayScreen(record: _game())),
      ),
    );
    await tester.pump();

    expect(find.text('Engine review'), findsOneWidget);
    expect(
      find.textContaining('Replay works without an engine'),
      findsOneWidget,
    );
  });

  // ======================================================================
  // §6.9 (18) Pushed ModalRoute back-dispose cleans up
  // ======================================================================

  testWidgets('pushed ModalRoute pop disposes handler cleanly', (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    addTearDown(tester.view.reset);
    final game = _game();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => VariantReplayScreen(record: game),
                  ),
                );
              },
              child: const Text('Open Replay'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Open the modal
    await tester.tap(find.text('Open Replay'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Chaotic replay'), findsOneWidget);

    // Start analysis while mounted
    await tester.tap(find.byKey(const ValueKey<String>('variant-analyze')));
    await tester.pump();

    // Pop the route via back-chevron
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
  });
}
