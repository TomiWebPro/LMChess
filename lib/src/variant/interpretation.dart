/// Interpretation data model for the chaotic / illegal-move variant.
///
/// Pipeline vocabulary:
///
/// 1. An [AttemptedMove] records what the mover *tried* (raw tool-call JSON
///    plus a human-readable phrase). It may be illegal, nonsensical, or
///    reference empty/off-board squares.
/// 2. Each [Strategy] proposes 0..3 [UnscoredInterpretation]s — candidate
///    boards *without* scores. Scoring is deliberately not a strategy concern;
///    it happens centrally via `VariantEvaluator` so all candidates are ranked
///    on one comparable centipawn-ish scale.
/// 3. The engine scores each raw candidate into a [CandidateInterpretation]
///    (adding [CandidateInterpretation.scoreCp],
///    [CandidateInterpretation.capturesKing] and a deterministic
///    [CandidateInterpretation.reproducibilityKey]) and selects one per the
///    active selection policy (see `selection.dart`).
/// 4. Everything is returned as an [InterpretedResult], including the
///    [InterpretedResult.events] log that makes the pipeline observable.
library;

import '../chess/piece.dart';
import '../chess/square.dart';
import 'variant_board.dart';

/// A move the mover attempted, legal or not.
///
/// Square names are kept as raw strings (not parsed [Square]s) so that
/// malformed input survives intact for logging and for strategies that want
/// to interpret garbage gracefully. Parsed accessors return `null` instead of
/// throwing.
class AttemptedMove {
  /// Raw origin square name, e.g. `e2`.
  final String fromSquareName;

  /// Raw destination square name, e.g. `e4`.
  final String toSquareName;

  /// Raw promotion hint, e.g. `q`/`queen` (may be `null` or garbage).
  final String? promotion;

  /// The verbatim tool-call JSON that produced this attempt (untrusted input).
  final Map<String, Object?> rawToolCallJson;

  /// Human-readable phrase describing the attempt, e.g. `Knight takes e5`.
  final String phrase;

  /// Creates an attempted move.
  const AttemptedMove({
    required this.fromSquareName,
    required this.toSquareName,
    this.promotion,
    this.rawToolCallJson = const {},
    this.phrase = '',
  });

  /// Parsed origin square, or `null` when [fromSquareName] is malformed.
  Square? get fromSquare => tryParseSquare(fromSquareName);

  /// Parsed destination square, or `null` when [toSquareName] is malformed.
  Square? get toSquare => tryParseSquare(toSquareName);

  /// Parsed promotion type, or `null` when absent/unrecognized.
  PieceType? get promotionType => parsePieceType(promotion);

  /// `true` when both square names parse.
  bool get hasParsableSquares => fromSquare != null && toSquare != null;

  @override
  String toString() =>
      'AttemptedMove($fromSquareName->$toSquareName${promotion ?? ''})';
}

/// A strategy proposal *before* scoring: the resulting board plus metadata.
///
/// Produced by [Strategy.generate]; turned into a scored
/// [CandidateInterpretation] by the engine. The [kingCaptureHint] is advisory
/// only — the engine recomputes king-capture facts authoritatively by diffing
/// king presence between parent and resulting board.
class UnscoredInterpretation {
  /// Id of the strategy that produced this candidate (e.g. `directTeleport`).
  final String strategyId;

  /// Short human-readable title, e.g. `Teleport strike`.
  final String title;

  /// One or two sentences explaining what the strategy did and why.
  final String description;

  /// The board that would result from accepting this interpretation.
  final VariantBoard resultingBoard;

  /// Advisory hint: the strategy believes a king was captured. The engine
  /// verifies this independently; strategies must never be trusted on this.
  final bool kingCaptureHint;

  /// Creates an unscored interpretation.
  const UnscoredInterpretation({
    required this.strategyId,
    required this.title,
    required this.description,
    required this.resultingBoard,
    this.kingCaptureHint = false,
  });
}

/// A scored, selectable interpretation of an [AttemptedMove].
///
/// Scores are always expressed **from the mover's perspective** (positive is
/// good for whoever attempted the move); the engine orients them when scoring.
class CandidateInterpretation {
  /// Id of the strategy that produced this candidate (`standard` for a
  /// legally applied move, `noopPass` for the do-nothing fallback).
  final String strategyId;

  /// Short human-readable title.
  final String title;

  /// One or two sentences explaining the interpretation.
  final String description;

  /// The resulting board.
  final VariantBoard resultingBoard;

  /// Heuristic value in centipawn-ish units from the mover's perspective.
  ///
  /// Produced by `VariantEvaluator`; a heuristic fallback, never real engine
  /// output (see evaluator docs).
  final int scoreCp;

  /// `true` when *any* side holds fewer kings here than on the parent board
  /// (a king-count decrement — includes self-inflicted king losses, and
  /// includes taking 1 of several kings on multi-king boards).
  final bool isKingCapture;

  /// `true` when the *mover* captured an *enemy* king, i.e. the enemy holds
  /// fewer kings here than on the parent board (offensive success, even
  /// when other enemy kings remain).
  final bool capturesKing;

  /// Deterministic key identifying this interpretation, of the form
  /// `strategyId|layout-hash`. Equal inputs produce equal keys, which is what
  /// makes selection tie-breaks reproducible. Piece ids are excluded via
  /// [VariantBoard.boardHash].
  final String reproducibilityKey;

  /// Creates a candidate. Prefer [CandidateInterpretation.scored].
  const CandidateInterpretation({
    required this.strategyId,
    required this.title,
    required this.description,
    required this.resultingBoard,
    required this.scoreCp,
    required this.isKingCapture,
    required this.capturesKing,
    required this.reproducibilityKey,
  });

  /// Scores [raw] from the mover's perspective, deriving king-capture facts
  /// by diffing king *counts* between [parentBoard] and the result.
  ///
  /// Resolved multi-king semantics: capturing *any* king counts — even when
  /// other kings of that colour remain — so a king-count decrement (not just
  /// an emptied king set) sets [isKingCapture], and an enemy-side decrement
  /// sets [capturesKing], which is what `bestStrategic` selection prefers.
  /// NOTE (docs agent): docs/VARIANT.md "Game over" still describes
  /// empty-set-only capture; sync it with this decrement semantics.
  factory CandidateInterpretation.scored({
    required UnscoredInterpretation raw,
    required VariantBoard parentBoard,
    required PieceColor mover,
    required int scoreCp,
  }) {
    var kingGone = false;
    var enemyKingTaken = false;
    for (final color in PieceColor.values) {
      final before = parentBoard.kingSquares(color).length;
      final after = raw.resultingBoard.kingSquares(color).length;
      if (after < before) {
        kingGone = true;
        if (color != mover) enemyKingTaken = true;
      }
    }
    return CandidateInterpretation(
      strategyId: raw.strategyId,
      title: raw.title,
      description: raw.description,
      resultingBoard: raw.resultingBoard,
      scoreCp: scoreCp,
      isKingCapture: kingGone,
      capturesKing: enemyKingTaken,
      reproducibilityKey:
          '${raw.strategyId}|${raw.resultingBoard.boardHash()}',
    );
  }

  @override
  String toString() =>
      'Candidate($strategyId, scoreCp=$scoreCp, king=$capturesKing)';
}

/// The full outcome of interpreting one [AttemptedMove].
class InterpretedResult {
  /// The original attempt.
  final AttemptedMove attempt;

  /// `true` when the attempt was applicable as a standard legal move (in
  /// which case [candidates] holds exactly that one candidate).
  final bool wasLegal;

  /// All scored candidates considered (unmodifiable, deterministic order).
  final List<CandidateInterpretation> candidates;

  /// The candidate chosen by the selection policy.
  final CandidateInterpretation selected;

  /// Human-readable pipeline log (legality verdict, candidate counts,
  /// scoring notes, selection reason).
  final List<String> events;

  /// Creates a result. Lists are copied into unmodifiable lists.
  InterpretedResult({
    required this.attempt,
    required this.wasLegal,
    required List<CandidateInterpretation> candidates,
    required this.selected,
    List<String> events = const [],
  })  : candidates = List<CandidateInterpretation>.unmodifiable(candidates),
        events = List<String>.unmodifiable(events);
}

/// Abstract interpretation strategy: one creative reading of an illegal move.
///
/// A strategy is a pure, bounded function of `(board, attempt)`:
/// * **Pure** — no randomness, no I/O, no global state. Same inputs always
///   yield the same candidate list (ids derive via [freshDerivedId]).
/// * **Bounded** — returns at most 3 candidates; each candidate performs one
///   clearly described transformation (see `strategies.dart` scope notes).
/// * **Defensive** — returns an empty list (never throws) when its
///   preconditions are unmet, e.g. unparsable squares or a missing piece.
///
/// Scoring is *not* part of this interface; it is applied centrally so that
/// candidates from different strategies remain comparable.
abstract class Strategy {
  /// Stable id, e.g. `directTeleport`. Used in logs and reproducibility keys.
  String get id;

  /// One-line description of the strategy's scope and limits.
  String get description;

  /// Proposes 0..3 unscored interpretations of [attempt] on [board].
  List<UnscoredInterpretation> generate(
      VariantBoard board, AttemptedMove attempt);

  /// Const-capable base constructor so concrete strategies can be `const`.
  const Strategy();
}
