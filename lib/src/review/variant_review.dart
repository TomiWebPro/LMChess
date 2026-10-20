/// Engine-backed review for chaotic-variant games.
///
/// Evaluation truth comes from Stockfish when available. Because variant
/// boards are not always FEN-representable, each board is first projected by
/// [VariantPositionProjector] (multi-king selections, pawn normalization,
/// extra material kept), every projection is evaluated, and the scores are
/// aggregated. When no projection can be evaluated the service falls back to
/// [VariantEvaluator] and labels the result `variant-heuristic` — never
/// `stockfish-uci`.
library;

import '../chess/piece.dart';
import '../review/engine_adapter.dart';
import '../variant/evaluator.dart';
import '../variant/variant_board.dart';
import '../variant/variant_replay.dart';
import 'quality.dart';
import 'variant_projection.dart';
import 'variant_quality.dart';
import 'wintr_review.dart';

/// Review options.
class VariantReviewOptions {
  /// Maximum royal projections per board.
  final int maxProjections;

  /// Per-projection evaluation deadline.
  final Duration perEvaluationTimeout;

  /// Optional wall-clock budget for one board's projections.
  final Duration gameBudget;

  /// Creates options.
  const VariantReviewOptions({
    this.maxProjections = 8,
    this.perEvaluationTimeout = const Duration(seconds: 10),
    this.gameBudget = const Duration(seconds: 120),
  });
}

/// Aggregated evaluation of one variant board.
class VariantBoardScore {
  /// White-relative aggregate score.
  final int? scoreCp;

  /// Individual projection scores (White-relative).
  final List<int> samples;

  /// `stockfish-uci`, `heuristic`, `variant-heuristic`, `variant-rule` or
  /// `mixed`.
  final String source;

  /// Whether a score exists.
  final bool supported;

  /// Whether the board is terminal (a side has no king).
  final bool terminal;

  /// Whether the royal selections were sampled rather than exhaustive.
  final bool sampled;

  /// Whether some projections failed/timed out.
  final bool partial;

  /// Projection details.
  final VariantProjection? projection;

  /// Aggregate spread.
  final int? medianCp;
  final int? minCp;
  final int? maxCp;
  final int? spreadCp;

  /// Fraction of royal combinations evaluated.
  final double coverage;

  /// `high` / `medium` / `low`.
  final String confidence;

  /// Why the heuristic fallback was used, when applicable.
  final String? fallbackReason;

  /// Creates a board score.
  const VariantBoardScore({
    required this.scoreCp,
    required this.samples,
    required this.source,
    required this.supported,
    this.terminal = false,
    this.sampled = false,
    this.partial = false,
    this.projection,
    this.medianCp,
    this.minCp,
    this.maxCp,
    this.spreadCp,
    this.coverage = 1,
    this.confidence = 'high',
    this.fallbackReason,
  });

  /// Whether this score came from Stockfish.
  bool get isEngine => source == 'stockfish-uci';
}

/// One reviewed variant ply.
class VariantReviewedPly {
  /// 0-based ply index.
  final int ply;

  /// Mover side.
  final bool moverIsWhite;

  /// White-relative scores and mover-relative delta.
  final int? beforeCp;
  final int? afterCp;
  final int? moverBeforeCp;
  final int? moverAfterCp;
  final int? lossCp;

  /// Whether the position improved for the mover.
  final bool improvement;

  /// Assessment and evidence.
  final bool supported;
  final QualityAssessment assessment;
  final VariantBoardScore beforeScore;
  final VariantBoardScore afterScore;

  /// Flags for UI badges.
  final bool illegalAttempt;
  final bool interpreted;
  final bool kingCapture;
  final bool instantLoss;
  final bool lowConfidence;

  /// Transformation notes from the projection.
  final List<String> annotations;

  /// Per-move accuracy (0..100), when scores exist.
  final double? accuracy;

  /// Creates a reviewed ply.
  const VariantReviewedPly({
    required this.ply,
    required this.moverIsWhite,
    required this.beforeCp,
    required this.afterCp,
    required this.moverBeforeCp,
    required this.moverAfterCp,
    required this.lossCp,
    required this.improvement,
    required this.supported,
    required this.assessment,
    required this.beforeScore,
    required this.afterScore,
    required this.illegalAttempt,
    required this.interpreted,
    required this.kingCapture,
    required this.instantLoss,
    required this.lowConfidence,
    this.annotations = const <String>[],
    this.accuracy,
  });
}

/// Full review of one chaotic game.
class VariantReviewReport {
  /// Per-ply reviews.
  final List<VariantReviewedPly> moves;

  /// Quality counts by tier name.
  final Map<String, int> qualityCounts;

  /// Per-side mean accuracy, when scores exist.
  final double? whiteAccuracy;
  final double? blackAccuracy;

  /// Aggregate source label (`stockfish-uci`, `variant-heuristic`, `mixed`).
  final String source;

  /// Warnings (projection issues, partial evaluation, heuristic fallback).
  final List<String> warnings;

  /// Creates a report.
  const VariantReviewReport({
    required this.moves,
    required this.qualityCounts,
    required this.whiteAccuracy,
    required this.blackAccuracy,
    required this.source,
    this.warnings = const <String>[],
  });
}

/// Projects and evaluates variant boards, then classifies each ply.
class VariantReviewService {
  /// Creates a service.
  VariantReviewService({
    required this.evaluator,
    this.options = const VariantReviewOptions(),
  });

  /// Engine/evaluator used for projected FENs.
  final PositionEvaluator evaluator;

  /// Review options.
  final VariantReviewOptions options;

  final Map<String, VariantBoardScore> _cache = <String, VariantBoardScore>{};

  /// Evaluates [board], projecting non-standard states as needed.
  Future<VariantBoardScore> evaluateBoard(VariantBoard board) async {
    final key = '${board.boardHash()}|${board.sideToMove.name}';
    final cached = _cache[key];
    if (cached != null) return cached;

    final projector = VariantPositionProjector(
      maxProjections: options.maxProjections,
    );
    final projection = projector.project(board);
    if (projection.terminal) {
      final winner = projection.terminalWinner;
      final cp = winner == null
          ? 0
          : (winner.isWhite ? variantMateScore : -variantMateScore);
      final score = VariantBoardScore(
        scoreCp: cp,
        samples: <int>[cp],
        source: 'variant-rule',
        supported: true,
        terminal: true,
        projection: projection,
        medianCp: cp,
        minCp: cp,
        maxCp: cp,
        spreadCp: 0,
        confidence: 'high',
      );
      _cache[key] = score;
      return score;
    }
    if (projection.positions.isEmpty) {
      return _cache[key] = _heuristic(board, projection.unsupportedReason);
    }

    final samples = <int>[];
    final sources = <String>{};
    var partial = false;
    final stopwatch = Stopwatch()..start();
    for (final projected in projection.positions) {
      if (options.gameBudget > Duration.zero &&
          stopwatch.elapsed > options.gameBudget) {
        partial = true;
        break;
      }
      try {
        final result = await evaluator
            .evaluate(projected.fen)
            .timeout(options.perEvaluationTimeout);
        if (result.supported && result.scoreCp != null) {
          samples.add(result.scoreCp!);
          sources.add(result.source);
        } else {
          partial = true;
        }
      } catch (_) {
        partial = true;
      }
    }
    if (samples.isEmpty) {
      return _cache[key] = _heuristic(
        board,
        'no royal projection could be evaluated',
      );
    }
    final aggregate = _aggregate(samples);
    final sorted = List<int>.of(samples)..sort();
    final source = sources.length == 1 ? sources.single : 'mixed';
    final score = VariantBoardScore(
      scoreCp: aggregate,
      samples: samples,
      source: source,
      supported: true,
      sampled: projection.sampledRoyalCombinations <
          projection.totalRoyalCombinations,
      partial: partial,
      projection: projection,
      medianCp: _median(sorted),
      minCp: sorted.first,
      maxCp: sorted.last,
      spreadCp: sorted.last - sorted.first,
      coverage: projection.coverage,
      confidence: _confidenceFor(
        source: source,
        projection: projection,
        partial: partial,
        spread: sorted.last - sorted.first,
      ),
      fallbackReason: null,
    );
    _cache[key] = score;
    return score;
  }

  /// Reviews [record] from the recorded board chain.
  Future<VariantReviewReport> reviewGame(VariantGameRecord record) async {
    final boards = <VariantBoard>[
      record.initialBoard,
      for (final ply in record.plies) ply.boardAfter,
    ];
    final scores = <VariantBoardScore>[];
    for (final board in boards) {
      scores.add(await evaluateBoard(board));
    }

    final moves = <VariantReviewedPly>[];
    final counts = <String, int>{};
    final warnings = <String>{};
    for (var i = 0; i < record.plies.length; i++) {
      final ply = record.plies[i];
      final before = scores[i];
      final after = scores[i + 1];
      final reviewed = _reviewPly(record, i, ply, before, after);
      moves.add(reviewed);
      counts[reviewed.assessment.quality.name] =
          (counts[reviewed.assessment.quality.name] ?? 0) + 1;
      if (before.fallbackReason != null) warnings.add(before.fallbackReason!);
      if (after.fallbackReason != null) warnings.add(after.fallbackReason!);
      if (before.partial || after.partial) {
        warnings.add('Some projections could not be evaluated (ply ${i + 1}).');
      }
    }

    final sources = <String>{
      for (final score in scores)
        if (score.scoreCp != null) score.source,
    };
    final source = sources.length == 1 ? sources.single : 'mixed';

    final whiteAcc = _meanAccuracy(moves.where((m) => m.moverIsWhite));
    final blackAcc = _meanAccuracy(moves.where((m) => !m.moverIsWhite));

    return VariantReviewReport(
      moves: moves,
      qualityCounts: counts,
      whiteAccuracy: whiteAcc,
      blackAccuracy: blackAcc,
      source: source,
      warnings: warnings.toList()..sort(),
    );
  }

  VariantReviewedPly _reviewPly(
    VariantGameRecord record,
    int index,
    VariantPlyRecord ply,
    VariantBoardScore before,
    VariantBoardScore after,
  ) {
    final moverIsWhite = ply.mover == 'w';
    final beforeCp = before.scoreCp;
    final afterCp = after.scoreCp;
    final supported = before.supported && after.supported;
    final moverBefore = beforeCp == null
        ? null
        : (moverIsWhite ? beforeCp : -beforeCp);
    final moverAfter =
        afterCp == null ? null : (moverIsWhite ? afterCp : -afterCp);
    final loss = moverBefore == null || moverAfter == null
        ? null
        : moverBefore - moverAfter;
    final facts = ply.kingFacts;
    final moverKingsAfter = facts.moverKingsAfter;
    final enemyKingsAfter = facts.enemyKingsAfter;
    final afterBoard = record.boardAt(index + 1);
    final kingCapturableNext = moverKingsAfter == 1 &&
        VariantEvaluator.attacksKing(afterBoard, moverIsWhite
            ? PieceColor.black
            : PieceColor.white);
    final mateAgainstMover = afterCp != null &&
        (moverIsWhite
            ? afterCp <= -variantMateScore
            : afterCp >= variantMateScore);
    final wasAlreadyLost = facts.moverKingsBefore == 0 ||
        (moverBefore != null && moverBefore <= -variantMateScore);
    final wasAlreadyWinning = moverBefore != null &&
        (moverBefore >= alreadyWinningCp || moverBefore >= variantMateScore);

    final assessment = classifyVariantMove(
      beforeCp: beforeCp,
      afterCp: afterCp,
      moverIsWhite: moverIsWhite,
      supported: supported,
      attemptWasStandardLegal: ply.wasLegal,
      interpretationIsNonStandard:
          ply.interpretationKind == VariantInterpretationKind.interpreted,
      capturesKing: facts.capturesEnemyKing,
      enemyKingTerminalLoss: enemyKingsAfter == 0,
      moverKingTerminalLoss: moverKingsAfter == 0,
      kingCapturableNext: kingCapturableNext,
      mateAgainstMover: mateAgainstMover,
      wasAlreadyLost: wasAlreadyLost,
      wasAlreadyWinning: wasAlreadyWinning,
      moverKingsAfter: moverKingsAfter,
      source: after.source,
    );

    final annotations = <String>[
      ...?after.projection?.transforms,
      ...?before.projection?.transforms,
    ];

    final accuracy = beforeCp == null || afterCp == null
        ? null
        : moveAccuracy(
            moverPointsLoss(
              beforeCp: beforeCp,
              afterCp: afterCp,
              moverIsWhite: moverIsWhite,
            ),
          );

    return VariantReviewedPly(
      ply: index,
      moverIsWhite: moverIsWhite,
      beforeCp: beforeCp,
      afterCp: afterCp,
      moverBeforeCp: moverBefore,
      moverAfterCp: moverAfter,
      lossCp: loss,
      improvement: loss != null && loss < 0,
      supported: supported,
      assessment: assessment,
      beforeScore: before,
      afterScore: after,
      illegalAttempt: !ply.wasLegal,
      interpreted: ply.interpretationKind == VariantInterpretationKind.interpreted,
      kingCapture: facts.capturesEnemyKing,
      instantLoss: assessment.quality == MoveQuality.superBlunder &&
          assessment.tags.contains('instant-loss'),
      lowConfidence: after.source == 'variant-heuristic' ||
          after.sampled ||
          after.partial,
      annotations: annotations,
      accuracy: accuracy,
    );
  }

  int _aggregate(List<int> samples) {
    final sorted = List<int>.of(samples)..sort();
    if (sorted.length == 1) return sorted.single;
    final mates = sorted.where((cp) => cp.abs() >= variantMateScore).toList();
    if (mates.isNotEmpty && mates.length * 2 >= sorted.length) {
      return mates.reduce((a, b) => a.abs() >= b.abs() ? a : b);
    }
    if (sorted.length == 2) {
      return ((sorted[0] + sorted[1]) / 2).round();
    }
    return _median(sorted);
  }

  int _median(List<int> sorted) {
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : ((sorted[mid - 1] + sorted[mid]) / 2).round();
  }

  String _confidenceFor({
    required String source,
    required VariantProjection projection,
    required bool partial,
    required int spread,
  }) {
    if (source != 'stockfish-uci' ||
        partial ||
        projection.sampledRoyalCombinations <
            projection.totalRoyalCombinations ||
        spread > 300) {
      return 'low';
    }
    if (projection.isStandard) return 'high';
    return 'medium';
  }

  double? _meanAccuracy(Iterable<VariantReviewedPly> moves) {
    final values = <double>[
      for (final move in moves)
        if (move.accuracy != null) move.accuracy!,
    ];
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  VariantBoardScore _heuristic(VariantBoard board, String? reason) {
    final cp = VariantEvaluator.score(board, PieceColor.white);
    return VariantBoardScore(
      scoreCp: cp,
      samples: <int>[cp],
      source: 'variant-heuristic',
      supported: true,
      partial: true,
      medianCp: cp,
      minCp: cp,
      maxCp: cp,
      spreadCp: 0,
      confidence: 'low',
      fallbackReason: reason ?? 'variant heuristic fallback',
    );
  }
}
