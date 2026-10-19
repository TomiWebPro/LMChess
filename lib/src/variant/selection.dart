/// Candidate selection policies for the chaotic variant engine.
///
/// Selection answers "which interpretation wins?" once candidates are scored.
/// All policies except [SelectionPolicy.random] are fully deterministic;
/// [SelectionPolicy.random] is deterministic *given the seed*.
///
/// ## Determinism contract
///
/// Same `(candidates, policy, moverColor, seed, originalBoard)` inputs always
/// produce the same output. Tie-breaks use
/// [CandidateInterpretation.reproducibilityKey] ordering, so even equal-scored
/// candidates resolve identically across runs, devices and processes.
library;

import 'dart:math';

import '../chess/piece.dart';
import '../chess/square.dart';
import 'interpretation.dart';
import 'variant_board.dart';

/// How the engine picks one candidate out of many.
enum SelectionPolicy {
  /// Prefer king captures, then the highest mover-perspective score.
  ///
  /// The competitive default: winning by king capture dominates everything,
  /// otherwise the heuristically strongest board wins.
  bestStrategic,

  /// Prefer the smallest board change (most faithful to the attempt).
  ///
  /// Requires [originalBoard] in [selectInterpretation]; throws
  /// [ArgumentError] without it.
  mostLiteral,

  /// Prefer the largest board change (maximum chaos).
  ///
  /// Requires [originalBoard] in [selectInterpretation]; throws
  /// [ArgumentError] without it.
  mostChaotic,

  /// Uniform pick via `Random(seed)`. Deterministic for a fixed seed.
  random,

  /// Reserved for a human reviewer choosing in the UI.
  ///
  /// The headless engine cannot ask a human, so it deterministically falls
  /// back to [bestStrategic]. UI layers should intercept this policy *before*
  /// calling [selectInterpretation] and present [candidates] to the user.
  humanSelected;

  /// One-line description of the policy for UI labels and logs.
  String get description => switch (this) {
        bestStrategic => 'King capture first, then highest heuristic score.',
        mostLiteral =>
          'Smallest board change; the most faithful reading of the attempt.',
        mostChaotic => 'Largest board change; the most chaotic reading.',
        random => 'Seeded uniform pick (deterministic for a fixed seed).',
        humanSelected =>
          'Human picks in the UI; headless runs fall back to bestStrategic.',
      };
}

/// Counts changed squares between [a] and [b]: squares where occupancy
/// differs (present vs absent) or the piece type/colour differs.
///
/// Piece ids and side-to-move are deliberately excluded: the diff measures
/// *visible board change*, which is what literal/chaotic policies rank on.
int boardDiff(VariantBoard a, VariantBoard b) {
  final keys = <Square>{...a.squares.keys, ...b.squares.keys};
  var diff = 0;
  for (final sq in keys) {
    final pa = a.squares[sq];
    final pb = b.squares[sq];
    if (pa == null || pb == null) {
      diff++; // Appeared or disappeared.
    } else if (pa.type != pb.type || pa.color != pb.color) {
      diff++; // Replaced or promoted.
    }
  }
  return diff;
}

/// Picks the winning candidate under [policy].
///
/// * [candidates] must be non-empty (the engine guarantees this via its
///   `noopPass` fallback); an empty list throws [StateError].
/// * [moverColor] orients documentation only: scores are already expressed
///   from the mover's perspective when the engine builds candidates, so every
///   policy ranks them directly. It is kept in the signature so future
///   mover-relative policies do not break callers.
/// * [seed] drives [SelectionPolicy.random] only (`Random(seed)`); other
///   policies ignore it.
/// * [originalBoard] is required by [SelectionPolicy.mostLiteral] and
///   [SelectionPolicy.mostChaotic] (they rank by change relative to it) and
///   ignored otherwise.
///
/// Ordering within equal ranks always falls back to
/// [CandidateInterpretation.reproducibilityKey] comparison, honouring the
/// determinism contract above.
CandidateInterpretation selectInterpretation(
  List<CandidateInterpretation> candidates,
  SelectionPolicy policy,
  PieceColor moverColor,
  int seed, {
  VariantBoard? originalBoard,
}) {
  if (candidates.isEmpty) {
    throw StateError('selectInterpretation called with no candidates');
  }
  // Reference the parameter intentionally: scores arrive pre-oriented to the
  // mover; the parameter documents whose perspective that is and reserves
  // mover-relative ranking for future policies.
  assert(moverColor == PieceColor.white || moverColor == PieceColor.black);
  int byKey(CandidateInterpretation a, CandidateInterpretation b) =>
      a.reproducibilityKey.compareTo(b.reproducibilityKey);

  switch (policy) {
    case SelectionPolicy.humanSelected:
      // Headless fallback (documented on the enum): behave as bestStrategic.
      return selectInterpretation(
        candidates,
        SelectionPolicy.bestStrategic,
        moverColor,
        seed,
        originalBoard: originalBoard,
      );
    case SelectionPolicy.bestStrategic:
      final sorted = candidates.toList()
        ..sort((a, b) {
          if (a.capturesKing != b.capturesKing) {
            return a.capturesKing ? -1 : 1;
          }
          if (a.scoreCp != b.scoreCp) {
            return b.scoreCp.compareTo(a.scoreCp);
          }
          return byKey(a, b);
        });
      return sorted.first;
    case SelectionPolicy.mostLiteral:
      if (originalBoard == null) {
        throw ArgumentError(
            'mostLiteral requires originalBoard for boardDiff ranking');
      }
      final sorted = candidates.toList()
        ..sort((a, b) {
          final d = boardDiff(originalBoard, a.resultingBoard)
              .compareTo(boardDiff(originalBoard, b.resultingBoard));
          if (d != 0) return d;
          return byKey(a, b);
        });
      return sorted.first;
    case SelectionPolicy.mostChaotic:
      if (originalBoard == null) {
        throw ArgumentError(
            'mostChaotic requires originalBoard for boardDiff ranking');
      }
      final sorted = candidates.toList()
        ..sort((a, b) {
          final d = boardDiff(originalBoard, b.resultingBoard)
              .compareTo(boardDiff(originalBoard, a.resultingBoard));
          if (d != 0) return d;
          return byKey(a, b);
        });
      return sorted.first;
    case SelectionPolicy.random:
      return candidates[Random(seed).nextInt(candidates.length)];
  }
}
