// Replay record integrity: a chaotic game must round-trip losslessly and its
// board chain must be verifiable without any engine.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/chess/piece.dart';
import 'package:llm_chess_arena/src/chess/position.dart';
import 'package:llm_chess_arena/src/chess/square.dart';
import 'package:llm_chess_arena/src/variant/chaotic_engine.dart';
import 'package:llm_chess_arena/src/variant/interpretation.dart';
import 'package:llm_chess_arena/src/variant/variant_board.dart';
import 'package:llm_chess_arena/src/variant/variant_replay.dart';

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
    seed: 100 + index,
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
    latencyMs: 12,
    inputTokens: 100,
    outputTokens: 20,
  );
}

VariantGameRecord _game() {
  final initial = VariantBoard.fromStandard(Position.initial());

  final legalAttempt = const AttemptedMove(
    fromSquareName: 'e2',
    toSquareName: 'e4',
    phrase: 'Opening',
  );
  final legal = ChaoticRules.interpret(initial, legalAttempt, seed: 1);
  final afterLegal = legal.selected.resultingBoard;

  final illegalAttempt = const AttemptedMove(
    fromSquareName: 'e2',
    toSquareName: 'e7',
    phrase: 'Long-range pawn',
  );
  final illegal = ChaoticRules.interpret(afterLegal, illegalAttempt, seed: 2);
  final afterIllegal = illegal.selected.resultingBoard;

  return VariantGameRecord(
    id: 'replay-test',
    whiteLabel: 'White',
    blackLabel: 'Black',
    whiteAgentId: 'agent-a',
    blackAgentId: 'agent-b',
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
    outcome: '1/2-1/2',
    reason: 'test',
    startedAt: DateTime.utc(2026, 1, 1),
    finishedAt: DateTime.utc(2026, 1, 1, 0, 1),
  );
}

void main() {
  group('VariantGameRecord', () {
    test('round-trips through JSON losslessly', () {
      final game = _game();
      final decoded = VariantGameRecord.fromJson(
        Map<String, Object?>.from(
          jsonDecode(jsonEncode(game.toJson())) as Map,
        ),
      );

      expect(decoded.toJson(), game.toJson());
      expect(decoded.validateChain(), isEmpty);
      expect(decoded.plies, hasLength(2));
      expect(decoded.plies[0].wasLegal, isTrue);
      expect(decoded.plies[1].wasLegal, isFalse);
      expect(decoded.plies[1].attempt.rawToolArgsJson, isNotNull);
      expect(decoded.plies[1].events, isNotEmpty);
      expect(decoded.plies[1].candidates, isNotEmpty);
      expect(decoded.boardAt(0).boardHash(), game.initialBoard.boardHash());
      expect(decoded.boardAt(1).boardHash(), game.plies[0].boardAfter.boardHash());
      expect(decoded.boardAt(2).boardHash(), game.plies[1].boardAfter.boardHash());
    });

    test('validateChain reports a tampered hash', () {
      final game = _game();
      final brokenPly = VariantPlyRecord(
        ply: game.plies[1].ply,
        mover: game.plies[1].mover,
        agentId: game.plies[1].agentId,
        modelKey: game.plies[1].modelKey,
        seed: game.plies[1].seed,
        fallback: game.plies[1].fallback,
        attempt: game.plies[1].attempt,
        wasLegal: game.plies[1].wasLegal,
        standardDetail: game.plies[1].standardDetail,
        interpretationKind: game.plies[1].interpretationKind,
        selected: game.plies[1].selected,
        candidates: game.plies[1].candidates,
        events: game.plies[1].events,
        boardAfter: game.plies[1].boardAfter,
        kingFacts: game.plies[1].kingFacts,
        boardHashBefore: 'tampered',
        boardHashAfter: game.plies[1].boardHashAfter,
        policy: game.plies[1].policy,
      );
      final broken = VariantGameRecord(
        id: game.id,
        whiteLabel: game.whiteLabel,
        blackLabel: game.blackLabel,
        seed: game.seed,
        initialBoard: game.initialBoard,
        plies: <VariantPlyRecord>[game.plies[0], brokenPly],
        outcome: game.outcome,
        reason: game.reason,
      );
      expect(broken.validateChain(), isNotEmpty);
    });

    test('rejects unknown schema and mistyped fields', () {
      expect(
        () => VariantGameRecord.fromJson(<String, Object?>{
          'schemaVersion': '9.9',
          'id': 'x',
        }),
        throwsFormatException,
      );
      expect(
        () => VariantGameRecord.fromJson(<String, Object?>{
          'schemaVersion': variantReplaySchemaVersion,
          'id': 'x',
          'whiteLabel': 'W',
          'blackLabel': 'B',
          'seed': 'not-an-int',
          'initialBoard': VariantBoard.fromStandard(Position.initial()).toJson(),
          'plies': <Object?>[],
        }),
        throwsFormatException,
      );
    });

    test('king facts detect enemy king capture by piece id', () {
      final before = VariantBoard.fromStandard(Position.initial());
      final squares = Map<Square, VariantPiece>.of(before.squares);
      squares.remove(tryParseSquare('e8'));
      final after = VariantBoard(
        squares: squares,
        sideToMove: PieceColor.black,
      );
      final facts = VariantKingFacts.between(
        before,
        after,
        PieceColor.white,
      );
      expect(facts.blackKingsBefore, 1);
      expect(facts.blackKingsAfter, 0);
      expect(facts.blackKingsLost, hasLength(1));
      expect(facts.capturesEnemyKing, isTrue);
    });
  });
}
