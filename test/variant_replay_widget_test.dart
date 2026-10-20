// Widget smoke for the chaotic replay screen: initial position, step controls,
// attempt/interpretation cards, and no engine dependency.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/chess/position.dart';
import 'package:llm_chess_arena/src/variant/chaotic_engine.dart';
import 'package:llm_chess_arena/src/variant/interpretation.dart';
import 'package:llm_chess_arena/src/variant/variant_board.dart';
import 'package:llm_chess_arena/src/variant/variant_replay.dart';
import 'package:llm_chess_arena/src/ui/screens/variant_replay_screen.dart';

VariantPlyRecord _ply({
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
    candidates: <VariantInterpretationRecord>[
      for (final candidate in interpreted.candidates)
        VariantInterpretationRecord.fromCandidate(candidate),
    ],
    events: interpreted.events,
    boardAfter: after,
    kingFacts: VariantKingFacts.between(before, after, mover),
    boardHashBefore: before.boardHash(),
    boardHashAfter: after.boardHash(),
    policy: interpreted.policy,
  );
}

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
    plies: <VariantPlyRecord>[
      _ply(
        index: 0,
        before: initial,
        after: afterLegal,
        attempt: legalAttempt,
        interpreted: legal,
      ),
      _ply(
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

void main() {
  testWidgets('steps through a chaotic game and shows interpretation details',
      (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final game = _game();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: VariantReplayScreen(record: game)),
      ),
    );
    await tester.pump();

    expect(find.text('Chaotic replay'), findsOneWidget);
    expect(find.bySemanticsLabel('White piece on e2'), findsOneWidget);
    expect(find.text('Initial position'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('variant-next')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Attempt e2e4'), findsOneWidget);
    expect(find.textContaining('standard'), findsWidgets);
    expect(find.text('Pipeline events (${game.plies[0].events.length})'),
        findsOneWidget);
    expect(find.bySemanticsLabel('White piece on e4'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('variant-next')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Attempt e2e7'), findsOneWidget);
    expect(
      find.textContaining(game.plies[1].selected.strategyId),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);

    semantics.dispose();
  });
}
