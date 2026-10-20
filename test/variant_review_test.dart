// Variant review: projection aggregation, terminal rules, heuristic fallback,
// and super-brilliant/super-blunder integration.
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/chess/piece.dart';
import 'package:llm_chess_arena/src/chess/position.dart';
import 'package:llm_chess_arena/src/chess/square.dart';
import 'package:llm_chess_arena/src/review/engine_adapter.dart';
import 'package:llm_chess_arena/src/review/quality.dart';
import 'package:llm_chess_arena/src/review/variant_review.dart';
import 'package:llm_chess_arena/src/variant/chaotic_engine.dart';
import 'package:llm_chess_arena/src/variant/interpretation.dart';
import 'package:llm_chess_arena/src/variant/variant_board.dart';
import 'package:llm_chess_arena/src/variant/variant_replay.dart';

class _SequenceEvaluator implements PositionEvaluator {
  _SequenceEvaluator(this.scores);
  final List<int> scores;
  int calls = 0;

  @override
  bool get supportsVariant => false;

  @override
  String get name => 'sequence';

  @override
  Future<EvalResult> evaluate(String fenOrVariantJson) async {
    final cp = scores[calls.clamp(0, scores.length - 1)];
    calls++;
    return EvalResult(
      scoreCp: cp,
      source: EngineSources.stockfishUci,
    );
  }
}

class _ThrowingEvaluator implements PositionEvaluator {
  @override
  bool get supportsVariant => false;

  @override
  String get name => 'throwing';

  @override
  Future<EvalResult> evaluate(String fenOrVariantJson) async {
    throw StateError('engine unavailable');
  }
}

VariantPlyRecord _ply({
  required int index,
  required VariantBoard before,
  required VariantBoard after,
  required AttemptedMove attempt,
  required InterpretedResult interpreted,
  VariantInterpretationKind? kind,
}) {
  final mover = before.sideToMove;
  return VariantPlyRecord(
    ply: index,
    mover: mover.isWhite ? 'w' : 'b',
    agentId: 'agent-a',
    modelKey: 'mock-a',
    seed: 1,
    fallback: false,
    attempt: VariantAttemptRecord(
      uci: '${attempt.fromSquareName}${attempt.toSquareName}',
      fromSquareName: attempt.fromSquareName,
      toSquareName: attempt.toSquareName,
      phrase: attempt.phrase,
    ),
    wasLegal: interpreted.wasLegal,
    standardDetail: interpreted.standardDetail,
    interpretationKind: kind ??
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

VariantGameRecord _game(List<VariantPlyRecord> plies) {
  return VariantGameRecord(
    id: 'review-test',
    whiteLabel: 'White',
    blackLabel: 'Black',
    seed: 1,
    initialBoard: plies.isEmpty
        ? VariantBoard.fromStandard(Position.initial())
        : VariantBoard.fromStandard(Position.initial()),
    plies: plies,
    outcome: '*',
    reason: 'test',
  );
}

void main() {
  test('standard chain evaluates before/after and classifies the move', () async {
    final initial = VariantBoard.fromStandard(Position.initial());
    const attempt = AttemptedMove(
      fromSquareName: 'e2',
      toSquareName: 'e4',
      phrase: 'Opening',
    );
    final interpreted = ChaoticRules.interpret(initial, attempt, seed: 1);
    final after = interpreted.selected.resultingBoard;
    final record = _game(<VariantPlyRecord>[
      _ply(
        index: 0,
        before: initial,
        after: after,
        attempt: attempt,
        interpreted: interpreted,
      ),
    ]);

    final evaluator = _SequenceEvaluator(<int>[20, 50]);
    final report = await VariantReviewService(evaluator: evaluator)
        .reviewGame(record);

    expect(evaluator.calls, 2);
    expect(report.moves, hasLength(1));
    final move = report.moves.single;
    expect(move.beforeCp, 20);
    expect(move.afterCp, 50);
    expect(move.lossCp, -30);
    expect(move.improvement, isTrue);
    expect(move.assessment.quality, MoveQuality.best);
    expect(report.source, 'stockfish-uci');
  });

  test('an illegal decisive interpretation is super brilliant', () async {
    final initial = VariantBoard.fromStandard(Position.initial());
    const attempt = AttemptedMove(
      fromSquareName: 'e2',
      toSquareName: 'e7',
      phrase: 'Long-range pawn',
    );
    final interpreted = ChaoticRules.interpret(initial, attempt, seed: 1);
    final after = interpreted.selected.resultingBoard;
    final record = _game(<VariantPlyRecord>[
      _ply(
        index: 0,
        before: initial,
        after: after,
        attempt: attempt,
        interpreted: interpreted,
        kind: VariantInterpretationKind.interpreted,
      ),
    ]);

    final report = await VariantReviewService(
      evaluator: _SequenceEvaluator(<int>[0, 400]),
    ).reviewGame(record);

    final move = report.moves.single;
    expect(move.lossCp, -400);
    expect(move.assessment.quality, MoveQuality.superBrilliant);
    expect(move.assessment.tags, contains('illegal-attempt'));
    expect(move.assessment.tags, contains('super-brilliant'));
  });

  test('a terminal board uses the variant rule and calls no engine', () async {
    final initial = VariantBoard.fromStandard(Position.initial());
    final squares = Map<Square, VariantPiece>.of(initial.squares);
    squares.remove(Square.fromName('e8'));
    final terminal = VariantBoard(
      squares: squares,
      sideToMove: PieceColor.black,
    );
    const attempt = AttemptedMove(
      fromSquareName: 'e2',
      toSquareName: 'e8',
      phrase: 'King capture',
    );
    final interpreted = ChaoticRules.interpret(initial, attempt, seed: 1);
    final record = _game(<VariantPlyRecord>[
      _ply(
        index: 0,
        before: initial,
        after: terminal,
        attempt: attempt,
        interpreted: interpreted,
      ),
    ]);

    final evaluator = _SequenceEvaluator(<int>[30]);
    final report = await VariantReviewService(evaluator: evaluator)
        .reviewGame(record);

    expect(evaluator.calls, 1, reason: 'terminal board must not be evaluated');
    final move = report.moves.single;
    expect(move.afterScore.terminal, isTrue);
    expect(move.afterScore.source, 'variant-rule');
    expect(move.assessment.quality, MoveQuality.superBrilliant);
    expect(move.assessment.tags, contains('terminal-win'));
  });

  test('multi-king boards aggregate all royal projections', () async {
    final base = VariantBoard.fromStandard(Position.initial());
    final squares = Map<Square, VariantPiece>.of(base.squares);
    squares[Square.fromName('c3')] = const VariantPiece(
      id: 'wk2',
      type: PieceType.king,
      color: PieceColor.white,
    );
    squares[Square.fromName('c6')] = const VariantPiece(
      id: 'bk2',
      type: PieceType.king,
      color: PieceColor.black,
    );
    final board = VariantBoard(squares: squares);

    final score = await VariantReviewService(
      evaluator: _SequenceEvaluator(<int>[42]),
    ).evaluateBoard(board);

    expect(score.supported, isTrue);
    expect(score.samples, hasLength(4));
    expect(score.medianCp, 42);
    expect(score.projection?.totalRoyalCombinations, 4);
    expect(score.source, 'stockfish-uci');
  });

  test('engine failure falls back to the variant heuristic honestly', () async {
    final board = VariantBoard.fromStandard(Position.initial());
    final score = await VariantReviewService(
      evaluator: _ThrowingEvaluator(),
    ).evaluateBoard(board);

    expect(score.source, 'variant-heuristic');
    expect(score.supported, isTrue);
    expect(score.fallbackReason, isNotNull);
    expect(score.scoreCp, isNotNull);
  });
}
