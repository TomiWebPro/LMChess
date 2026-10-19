// SPDX-License-Identifier: GPL-3.0-or-later
// WintrChess-derived game-review pipeline — ported from wintrcat/wintrchess;
// see wintrchess_notes.md and assets/engines/LICENSE.GPLv3.
/// WintrChess-derived game-review pipeline (pure Dart, GPLv3).
///
/// # Derivation statement (license-relevant — keep truthful)
///
/// This module is **inspired by / derived from** the WintrChess review
/// reporter at `wintrcat/wintrchess`, branch `master`:
///
/// * `shared/src/lib/reporter/expectedPoints.ts` — the logistic
///   win-probability model (`centipawnGradient = 0.0035`), the mate-value
///   convention, and the mover-signed expected-points loss clamped at
///   zero. Ported as [expectedPointsGradient], [whiteExpectedScore], and
///   [moverPointsLoss].
/// * `shared/src/lib/reporter/accuracy.ts` — the per-move accuracy
///   formula `103.16 * exp(-4 * pointLoss) - 3.17` and the per-side mean
///   aggregation. Ported as [moveAccuracy] and the accuracy means on
///   [ReviewReport].
/// * `shared/src/lib/reporter/report.ts` (`getGameAnalysis`) — the
///   pipeline shape this service mirrors: walk the game in order,
///   classify each move against the previous evaluation, attach a
///   per-move accuracy, and return one summary object. Ported as the
///   structure of [WintrReviewService.reviewGame] returning
///   [ReviewReport].
/// * `shared/src/lib/reporter/classify.ts`,
///   `shared/src/lib/reporter/classification/pointLoss.ts`,
///   `shared/src/lib/reporter/classification/brilliant.ts`,
///   `shared/src/lib/reporter/classification/critical.ts`,
///   `shared/src/constants/Classification.ts`,
///   `shared/src/types/game/position/Evaluation.ts`,
///   `shared/src/types/game/GameAnalysis.ts`,
///   `shared/src/lib/reporter/types/AnalysisOptions.ts` — reviewed and
///   deliberately **NOT ported** (see "What was NOT ported" below).
/// * `server/src/routes/api/analysis/analyse.ts` — the HTTP entry point
///   (`POST /analysis/analyse`, zod-validated state tree, `brilliant` /
///   `critical` / `theory` query flags). Server/transport code; not
///   portable to an in-app pipeline. The query flags are acknowledged in
///   [ReviewOptions] documentation but have no effect here.
///
/// This file (and the review pipeline as a whole) is a **modified
/// variant of GPLv3-licensed upstream logic** and therefore stays under
/// **GPLv3**: keep the license text shipped (`assets/engines/LICENSE.GPLv3`),
/// attribute `wintrcat/wintrchess`, and preserve the source offer
/// (see `lib/src/review/wintrchess_notes.md` and
/// `docs/ENGINE_RUNTIME.md`).
///
/// # What was NOT ported (and why)
///
/// * **Tier system.** Upstream classifies into `brilliant / critical /
///   best / excellent / okay / inaccuracy / mistake / blunder / theory /
///   forced / risky` (`shared/src/constants/Classification.ts`) with
///   expected-points-loss cut points at `0.01 / 0.045 / 0.08 / 0.12 /
///   0.22` (`classification/pointLoss.ts`). The local contract
///   (`quality.dart`) is authoritative instead: per-move tiers come from
///   [classify], whose mover-relative `lossCp` thresholds and
///   king-capture mechanics (`superBrilliant` / `superBlunder`,
///   `exposesOwnKing`) model the chaotic variant upstream never sees.
///   The upstream cut points are recorded in `wintrchess_notes.md` for
///   calibration reference only.
/// * **Brilliant / critical heuristics** (`brilliant.ts`, `critical.ts`).
///   Both need a live `chess.js` board (unsafe-piece tracing, trapped
///   pieces, second-top engine line). This pipeline is board-agnostic by
///   design — it consumes evaluations plus game events — so there is no
///   faithful port target. Documented, not reimplemented.
/// * **Theory / forced classifications** (`classify.ts`). These need an
///   opening book (`getOpeningName`) and legal-move counts, neither of
///   which exists in this pipeline. Not ported.
/// * **`estimatedRatings: {white: 2000, black: 1000}`** (`report.ts`).
///   Upstream hardcodes this placeholder; porting a fabricated rating
///   would be dishonest. This module reports no ratings.
/// * **Mate-type evaluations** (`Evaluation` `{type, value}`). The local
///   [EvalResult] carries a single White-relative `scoreCp` where mates
///   are anchored at `±(100000 − 100·|m|)` (see `engine_adapter.dart`).
///   Such magnitudes saturate the logistic below to ≈ 0/1, which
///   qualitatively matches upstream's mate-means-certainty handling
///   without a separate code path. Stated here so the equivalence is
///   explicit, not accidental.
///
/// # Role in the architecture (locked decision)
///
/// Stockfish (embedded UCI binary) does **position eval**; this module
/// does **game review**: it pairs before/after evaluations per move,
/// delegates tiering to `quality.dart`, adds upstream-derived accuracy
/// signals, picks the top-3 swing key moments, and emits a [ReviewReport].
/// It never spawns processes and never touches the network, so it runs
/// anywhere Flutter runs (including Web, where `dart:io` engines cannot).
library;

import 'dart:math' show exp;

import 'engine_adapter.dart';
import 'quality.dart';

/// Logistic gradient mapping centipawns to expected score.
///
/// Ported from `getExpectedPoints` in upstream
/// `shared/src/lib/reporter/expectedPoints.ts`
/// (`centipawnGradient: 0.0035`): `1 / (1 + exp(-0.0035 * value))`.
const double expectedPointsGradient = 0.0035;

/// Scale factor of the upstream move-accuracy formula.
///
/// From `getMoveAccuracy` in upstream
/// `shared/src/lib/reporter/accuracy.ts`:
/// `103.16 * Math.exp(-4 * pointLoss) - 3.17`.
const double moveAccuracyScale = 103.16;

/// Exponential decay rate of the upstream move-accuracy formula.
///
/// Same source as [moveAccuracyScale]: the `-4` in
/// `Math.exp(-4 * pointLoss)`.
const double moveAccuracyDecay = 4.0;

/// Subtractive offset of the upstream move-accuracy formula.
///
/// Same source as [moveAccuracyScale]: the `- 3.17`, which normalizes a
/// zero-loss move to ≈ 100 (103.16 − 3.17 = 99.99).
const double moveAccuracyOffset = 3.17;

/// White's expected score (0..1) from a White-relative centipawn score.
///
/// Direct port of upstream `getExpectedPoints` for `type == "centipawn"`
/// (`shared/src/lib/reporter/expectedPoints.ts`). Mate-anchored scores
/// (`|cp|` near 100000, see `engine_adapter.dart`) saturate this to
/// ≈ 0/1, matching upstream's mate-means-certainty behavior without a
/// separate branch (see library docs).
double whiteExpectedScore(int whiteRelativeCp) =>
    1.0 / (1.0 + exp(-expectedPointsGradient * whiteRelativeCp));

/// Mover-relative expected-points loss, clamped at zero.
///
/// Adaptation of upstream `getExpectedPointsLoss`
/// (`shared/src/lib/reporter/expectedPoints.ts`): both scores are
/// normalized to the mover's perspective (negated for Black — the Dart
/// equivalent of upstream's `flipPieceColour` handling), and a move that
/// *improves* the mover's expectation yields `0.0`, never a negative
/// loss (`Math.max(0, …)` upstream).
double moverPointsLoss({
  required int beforeCp,
  required int afterCp,
  required bool moverIsWhite,
}) {
  final before = moverIsWhite ? beforeCp : -beforeCp;
  final after = moverIsWhite ? afterCp : -afterCp;
  final loss = whiteExpectedScore(before) - whiteExpectedScore(after);
  return loss < 0.0 ? 0.0 : loss;
}

/// Per-move accuracy on a 0..100 scale from an expected-points loss.
///
/// Formula ported from upstream `getMoveAccuracy`
/// (`shared/src/lib/reporter/accuracy.ts`).
/// Deviation: upstream does not clamp, so catastrophic swings
/// (`pointLoss ≳ 0.87`) yield slightly negative values there; this port
/// clamps to `0..100` so reports never show negative accuracy. A
/// zero-loss move scores 99.99 in both implementations.
double moveAccuracy(double pointsLoss) {
  final raw =
      moveAccuracyScale * exp(-moveAccuracyDecay * pointsLoss) -
      moveAccuracyOffset;
  return raw.clamp(0.0, 100.0).toDouble();
}

/// One ordered move to review: the positions around it plus game events.
///
/// [fenBefore] is the standard-FEN position before the move.
/// [fenAfterOrVariantJson] is the position after the move, either as
/// standard FEN (evaluated by Stockfish/heuristic) or as chaotic-variant
/// JSON (evaluated only by variant-capable evaluators; Stockfish reports
/// `supported: false` for it per the `engine_adapter.dart` contract).
/// The remaining flags feed [classify] unchanged; [commentary] and
/// [annotations] are opaque caller notes (e.g. LLM phrases, arbiter
/// remarks) echoed through to the report.
class ReviewMoveInput {
  /// Standard-FEN position before the move.
  final String fenBefore;

  /// Position after the move: standard FEN or variant JSON.
  final String fenAfterOrVariantJson;

  /// True when White made this move (drives score normalization).
  final bool moverIsWhite;

  /// The turn included >= 1 illegal attempt (never auto-penalizes).
  final bool wasIllegalAttempt;

  /// The move decisively captures/enables capture of the enemy king.
  final bool isKingCapture;

  /// The move exposes the mover's own king to capture.
  final bool exposesOwnKing;

  /// Free-text note attached to the move (e.g. LLM phrase).
  final String? commentary;

  /// Caller-supplied error/marker annotations, echoed verbatim.
  final List<String> annotations;

  /// Creates a move input.
  const ReviewMoveInput({
    required this.fenBefore,
    required this.fenAfterOrVariantJson,
    required this.moverIsWhite,
    this.wasIllegalAttempt = false,
    this.isKingCapture = false,
    this.exposesOwnKing = false,
    this.commentary,
    this.annotations = const <String>[],
  });

  /// Serializes with stable field ordering.
  Map<String, Object?> toJson() => <String, Object?>{
    'fenBefore': fenBefore,
    'fenAfterOrVariantJson': fenAfterOrVariantJson,
    'moverIsWhite': moverIsWhite,
    'wasIllegalAttempt': wasIllegalAttempt,
    'isKingCapture': isKingCapture,
    'exposesOwnKing': exposesOwnKing,
    'commentary': commentary,
    'annotations': annotations,
  };
}

/// A single reviewed move: local quality verdict plus upstream signals.
///
/// [assessment] (from [classify]) is the authoritative tier.
/// [moverWinProbBefore]/[moverWinProbAfter] are the mover-relative
/// expected scores, [pointsLoss] the clamped mover-relative expectation
/// drop, and [accuracy] the upstream-formula score — all null when the
/// move had no supporting evaluations.
class ReviewedMove {
  /// Zero-based ply index in the reviewed game.
  final int moveIndex;

  /// True when White made this move.
  final bool moverIsWhite;

  /// Free-text note from the input, echoed.
  final String? commentary;

  /// Caller annotations from the input, echoed verbatim.
  final List<String> annotations;

  /// White-relative before-score; null when unsupported.
  final int? beforeCp;

  /// White-relative after-score; null when unsupported.
  final int? afterCp;

  /// Evaluator source tags (see [EngineSources]), echoed for honesty.
  final String beforeSource;

  /// Evaluator source tag for the after-position.
  final String afterSource;

  /// False when no evaluation backed this move.
  final bool supported;

  /// Authoritative tier verdict from [classify].
  final QualityAssessment assessment;

  /// Mover-relative expected score before the move; null if unsupported.
  final double? moverWinProbBefore;

  /// Mover-relative expected score after the move; null if unsupported.
  final double? moverWinProbAfter;

  /// Clamped mover-relative expected-points loss; null if unsupported.
  final double? pointsLoss;

  /// Upstream-formula accuracy 0..100; null if unsupported.
  final double? accuracy;

  /// Creates a reviewed move.
  const ReviewedMove({
    required this.moveIndex,
    required this.moverIsWhite,
    this.commentary,
    this.annotations = const <String>[],
    this.beforeCp,
    this.afterCp,
    required this.beforeSource,
    required this.afterSource,
    required this.supported,
    required this.assessment,
    this.moverWinProbBefore,
    this.moverWinProbAfter,
    this.pointsLoss,
    this.accuracy,
  });

  /// Serializes with stable field ordering.
  Map<String, Object?> toJson() => <String, Object?>{
    'moveIndex': moveIndex,
    'moverIsWhite': moverIsWhite,
    'commentary': commentary,
    'annotations': annotations,
    'beforeCp': beforeCp,
    'afterCp': afterCp,
    'beforeSource': beforeSource,
    'afterSource': afterSource,
    'supported': supported,
    'assessment': assessment.toJson(),
    'moverWinProbBefore': moverWinProbBefore,
    'moverWinProbAfter': moverWinProbAfter,
    'pointsLoss': pointsLoss,
    'accuracy': accuracy,
  };
}

/// One of the top-3 swing moments of the game.
///
/// Selection is newly implemented for this module (upstream annotates
/// every node instead of picking moments): supported moves rank by
/// absolute mover-relative `lossCp` (large gains count as swings too),
/// the top three win, and output restores chronological order.
class KeyMoment {
  /// Zero-based ply index of the moment.
  final int moveIndex;

  /// True when White made the move.
  final bool moverIsWhite;

  /// Tier assigned to the move.
  final MoveQuality quality;

  /// Mover-relative centipawn swing (signed; never null here).
  final int lossCp;

  /// Expected-points loss of the move, when computable.
  final double? pointsLoss;

  /// One-line human-readable description.
  final String note;

  /// Creates a key moment.
  const KeyMoment({
    required this.moveIndex,
    required this.moverIsWhite,
    required this.quality,
    required this.lossCp,
    this.pointsLoss,
    required this.note,
  });

  /// Serializes with stable field ordering.
  Map<String, Object?> toJson() => <String, Object?>{
    'moveIndex': moveIndex,
    'moverIsWhite': moverIsWhite,
    'quality': quality.name,
    'lossCp': lossCp,
    'pointsLoss': pointsLoss,
    'note': note,
  };
}

/// Whole-game review output.
///
/// [moves] is chronological; [keyMoments] holds up to three swings in
/// chronological order; [qualityCounts] maps tier names to frequencies
/// (zero-count tiers omitted); [whiteAccuracy]/[blackAccuracy] are the
/// per-side accuracy means (upstream `getGameAccuracy` semantics —
/// mean over supported moves of that side; null when the side has no
/// supported moves); [summary] is a one-paragraph human-readable
/// rendering of the same data.
class ReviewReport {
  /// Per-move results in game order.
  final List<ReviewedMove> moves;

  /// Top-3 swings in chronological order (fewer when data is short).
  final List<KeyMoment> keyMoments;

  /// Tier-name → count, zero-count tiers omitted.
  final Map<String, int> qualityCounts;

  /// Mean accuracy over White's supported moves; null when none.
  final double? whiteAccuracy;

  /// Mean accuracy over Black's supported moves; null when none.
  final double? blackAccuracy;

  /// Human-readable one-paragraph summary.
  final String summary;

  /// Creates a report.
  const ReviewReport({
    this.moves = const <ReviewedMove>[],
    this.keyMoments = const <KeyMoment>[],
    this.qualityCounts = const <String, int>{},
    this.whiteAccuracy,
    this.blackAccuracy,
    this.summary = '',
  });

  /// Serializes with stable field ordering.
  Map<String, Object?> toJson() => <String, Object?>{
    'moves': moves.map((m) => m.toJson()).toList(),
    'keyMoments': keyMoments.map((k) => k.toJson()).toList(),
    'qualityCounts': Map<String, int>.of(qualityCounts),
    'whiteAccuracy': whiteAccuracy,
    'blackAccuracy': blackAccuracy,
    'summary': summary,
  };
}

/// Pure-Dart game-review pipeline: evaluations in, report out.
///
/// Construction takes the [PositionEvaluator] used for both sides of
/// every move (typically [StockfishEvaluator] with a
/// [HeuristicEvaluator] fallback). [reviewGame] evaluates the two
/// positions around each move, classifies via [classify], attaches the
/// upstream-derived accuracy signals, selects key moments, and builds
/// the summary. It performs no I/O besides evaluator calls, holds no
/// mutable state, and is safe for sequential reuse.
///
/// Reviews of different games must not interleave on one service
/// instance when the underlying evaluator is sequential per process
/// (see `UciEngineAdapter.evaluate`); concurrent games need one service
/// (or evaluator) each.
class WintrReviewService {
  /// Evaluator used for the before/after position of every move.
  final PositionEvaluator evaluator;

  /// Creates a review service around [evaluator].
  const WintrReviewService({required this.evaluator});

  /// Reviews [moves] in order and returns the full report.
  ///
  /// An empty input yields an empty report whose summary says so; it is
  /// not an error. Moves whose positions the evaluator cannot score
  /// produce `supported: false` assessments (never fabricated numbers),
  /// and are excluded from accuracy means and key-moment selection.
  Future<ReviewReport> reviewGame(List<ReviewMoveInput> moves) async {
    final reviewed = <ReviewedMove>[];
    for (var i = 0; i < moves.length; i++) {
      reviewed.add(await _reviewMove(i, moves[i]));
    }
    return ReviewReport(
      moves: reviewed,
      keyMoments: _keyMoments(reviewed),
      qualityCounts: _qualityCounts(reviewed),
      whiteAccuracy: _sideAccuracy(reviewed, true),
      blackAccuracy: _sideAccuracy(reviewed, false),
      summary: _summarize(reviewed),
    );
  }

  /// Reviews one move: evaluates both positions, classifies, scores.
  ///
  /// A single evaluator failure (engine crash, timeout, I/O error) must not
  /// abort the whole report: the ply degrades to an `unsupported`
  /// assessment and the rest of the game is still reviewed.
  Future<ReviewedMove> _reviewMove(int index, ReviewMoveInput move) async {
    EvalResult before;
    EvalResult after;
    try {
      before = await evaluator.evaluate(move.fenBefore);
      after = await evaluator.evaluate(move.fenAfterOrVariantJson);
    } on Object {
      return _unsupportedMove(index, move);
    }
    final supported =
        before.supported &&
        after.supported &&
        before.scoreCp != null &&
        after.scoreCp != null;

    final assessment = classify(
      beforeCp: before.scoreCp,
      afterCp: after.scoreCp,
      moverIsWhite: move.moverIsWhite,
      wasIllegalAttempt: move.wasIllegalAttempt,
      isKingCapture: move.isKingCapture,
      supported: supported,
      exposesOwnKing: move.exposesOwnKing,
    );

    double? winBefore;
    double? winAfter;
    double? loss;
    double? accuracy;
    if (supported) {
      final beforeCp = before.scoreCp!;
      final afterCp = after.scoreCp!;
      final moverBefore = move.moverIsWhite ? beforeCp : -beforeCp;
      final moverAfter = move.moverIsWhite ? afterCp : -afterCp;
      winBefore = whiteExpectedScore(moverBefore);
      winAfter = whiteExpectedScore(moverAfter);
      loss = moverPointsLoss(
        beforeCp: beforeCp,
        afterCp: afterCp,
        moverIsWhite: move.moverIsWhite,
      );
      accuracy = moveAccuracy(loss);
    }

    return ReviewedMove(
      moveIndex: index,
      moverIsWhite: move.moverIsWhite,
      commentary: move.commentary,
      annotations: List<String>.of(move.annotations),
      beforeCp: before.scoreCp,
      afterCp: after.scoreCp,
      beforeSource: before.source,
      afterSource: after.source,
      supported: supported,
      assessment: assessment,
      moverWinProbBefore: winBefore,
      moverWinProbAfter: winAfter,
      pointsLoss: loss,
      accuracy: accuracy,
    );
  }

  /// Degraded ply used when the evaluator throws mid-review.
  ///
  /// Prefers an honest "unsupported" verdict over aborting the report; the
  /// caller's commentary/annotations are preserved so nothing is lost. The
  /// source tags fall back to the evaluator's own [PositionEvaluator.name]
  /// because no [EvalResult] was produced.
  ReviewedMove _unsupportedMove(int index, ReviewMoveInput move) {
    final assessment = classify(
      beforeCp: null,
      afterCp: null,
      moverIsWhite: move.moverIsWhite,
      wasIllegalAttempt: move.wasIllegalAttempt,
      isKingCapture: move.isKingCapture,
      supported: false,
      exposesOwnKing: move.exposesOwnKing,
    );
    return ReviewedMove(
      moveIndex: index,
      moverIsWhite: move.moverIsWhite,
      commentary: move.commentary,
      annotations: List<String>.of(move.annotations),
      beforeSource: evaluator.name,
      afterSource: evaluator.name,
      supported: false,
      assessment: assessment,
    );
  }

  /// Selects up to three top-swing moments, chronological on output.
  ///
  /// Ranking key is absolute mover-relative `lossCp`, so decisive gains
  /// (negative loss) compete with blunders; unsupported moves (null
  /// loss) never qualify.
  List<KeyMoment> _keyMoments(List<ReviewedMove> reviewed) {
    final candidates =
        reviewed.where((m) => m.assessment.lossCp != null).toList();
    candidates.sort(
      (a, b) => a.assessment.lossCp!.abs().compareTo(
        b.assessment.lossCp!.abs(),
      ),
    );
    final top = candidates.reversed.take(3).toList();
    top.sort((a, b) => a.moveIndex.compareTo(b.moveIndex));
    return top
        .map(
          (m) => KeyMoment(
            moveIndex: m.moveIndex,
            moverIsWhite: m.moverIsWhite,
            quality: m.assessment.quality,
            lossCp: m.assessment.lossCp!,
            pointsLoss: m.pointsLoss,
            note:
                'Ply ${m.moveIndex + 1} '
                '(${m.moverIsWhite ? 'White' : 'Black'}): '
                '${m.assessment.quality.name}, '
                '${m.assessment.lossCp!.abs()} cp swing.',
          ),
        )
        .toList();
  }

  /// Counts assessments per tier, omitting zero-count tiers.
  Map<String, int> _qualityCounts(List<ReviewedMove> reviewed) {
    final counts = <String, int>{
      for (final quality in MoveQuality.values) quality.name: 0,
    };
    for (final move in reviewed) {
      final key = move.assessment.quality.name;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    counts.removeWhere((_, count) => count == 0);
    return counts;
  }

  /// Mean upstream-formula accuracy over one side's supported moves.
  ///
  /// Mirrors upstream `getGameAccuracy`
  /// (`shared/src/lib/reporter/accuracy.ts`): arithmetic mean per color
  /// over moves that have an accuracy; null when the side has none.
  double? _sideAccuracy(List<ReviewedMove> reviewed, bool white) {
    final values = reviewed
        .where((m) => m.moverIsWhite == white && m.accuracy != null)
        .map((m) => m.accuracy!);
    if (values.isEmpty) return null;
    var sum = 0.0;
    var count = 0;
    for (final value in values) {
      sum += value;
      count++;
    }
    return sum / count;
  }

  /// Builds the one-paragraph human-readable summary.
  String _summarize(List<ReviewedMove> reviewed) {
    if (reviewed.isEmpty) return 'No moves to review.';
    final supportedCount = reviewed.where((m) => m.supported).length;
    final buffer = StringBuffer(
      'Reviewed ${reviewed.length} '
      '${reviewed.length == 1 ? 'ply' : 'plies'} '
      '($supportedCount supported). ',
    );
    final counts = _qualityCounts(reviewed);
    buffer.write(
      counts.entries.map((e) => '${e.key}: ${e.value}').join(', '),
    );
    buffer.write('. ');
    final white = _sideAccuracy(reviewed, true);
    final black = _sideAccuracy(reviewed, false);
    buffer.write(
      'Accuracy — White: ${_formatAccuracy(white)}, '
      'Black: ${_formatAccuracy(black)}. ',
    );
    final moments = _keyMoments(reviewed);
    if (moments.isEmpty) {
      buffer.write('No key moments (no supported swings).');
    } else {
      buffer.write(
        'Key moments: ${moments.map((k) => 'ply ${k.moveIndex + 1} (${k.quality.name})').join(', ')}.',
      );
    }
    return buffer.toString();
  }

  /// Formats an accuracy mean, or `n/a` when null.
  String _formatAccuracy(double? value) =>
      value == null ? 'n/a' : value.toStringAsFixed(1);
}
