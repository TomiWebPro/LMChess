// Premove queue helpers (§15.4) — pure Dart so the queue semantics are
// unit-testable without widgets.
//
// A premove is a human move queued while the opponent is thinking. Each
// entry is validated "in sequence": against a clone of the current position
// with the earlier queued premoves already applied. Because the opponent's
// reply between two premoves cannot be predicted, the simulation treats the
// queued premoves as consecutive moves by the same side (the side to move is
// reset to the mover after every application) — exactly the guarantee the
// UI needs to know a premove chain is "legal in sequence". Legal moves for
// that same side can then be read off the simulation, and execution
// re-validates the leading premove against the real position once the
// opponent's reply has landed.
library;

import '../chess/move.dart';
import '../chess/piece.dart';
import '../chess/position.dart';
import '../chess/square.dart';

/// Maximum number of queued premoves.
const int kMaxPremoves = 5;

/// One queued premove: a human move to be played on the next human turn.
class PremoveAttempt {
  /// Creates a premove.
  const PremoveAttempt({required this.from, required this.to, this.promotion});

  /// Origin square, e.g. `'d2'`.
  final String from;

  /// Destination square, e.g. `'d4'`.
  final String to;

  /// Lowercase promotion letter (`'q' | 'r' | 'b' | 'n'`); `null` for
  /// non-promotion moves. Premoves default to queen and never open a dialog
  /// while the opponent is thinking (§15.4).
  final String? promotion;

  /// UCI form of the premove (`'d2d4'`, `'a7a8q'`).
  String get uci => '$from$to${promotion ?? ''}';

  @override
  bool operator ==(Object other) =>
      other is PremoveAttempt &&
      other.from == from &&
      other.to == to &&
      other.promotion == promotion;

  @override
  int get hashCode => Object.hash(from, to, promotion);

  @override
  String toString() => 'PremoveAttempt($uci)';
}

/// Maps a lowercase promotion letter to its [PieceType]; `null` for `null`
/// or unrecognized input.
PieceType? promotionTypeFor(String? letter) {
  if (letter == null) return null;
  return PieceTypeX.fromLetter(letter);
}

/// Whether moving the [color] piece at [from] to [to] in [position] is a
/// pawn promotion (the piece is a pawn and [to] is on the promotion rank).
bool isPromotionMove(
  Position position,
  String from,
  String to,
  PieceColor color,
) {
  final sqFrom = Square.tryParse(from);
  final sqTo = Square.tryParse(to);
  if (sqFrom == null || sqTo == null) return false;
  final piece = position.pieceAt(sqFrom);
  return piece != null &&
      piece.color == color &&
      piece.type == PieceType.pawn &&
      sqTo.rank == color.promotionRank;
}

/// Applies [premoves] (as [color]'s moves) onto a clone of [base].
///
/// The side to move is forced to [color] before each application — and again
/// after it — so consecutive same-side premoves validate and apply in
/// sequence. The returned position therefore always has [color] to move and
/// is safe to hand to [isLegalPremove] or `legalMoves(forSquare:)` when
/// listing next-premove targets.
///
/// Stops (and silently drops the rest) at the first malformed or illegal
/// premove; callers validate before queueing so this only reflects a stale
/// queue that execution will clean up anyway.
Position premoveSimulation(
  Position base,
  List<PremoveAttempt> premoves, {
  required PieceColor color,
}) {
  var pos = base.clone();
  pos.sideToMove = color;
  for (final premove in premoves) {
    final from = Square.tryParse(premove.from);
    final to = Square.tryParse(premove.to);
    if (from == null || to == null) break;
    final move = ChessMove(
      from,
      to,
      promotion: promotionTypeFor(premove.promotion),
    );
    if (!pos.isLegal(move)) break;
    pos.apply(move);
    pos.sideToMove = color;
  }
  return pos;
}

/// Whether [from]→[to] (with optional [promotion]) is a legal move for
/// [color] from the already-simulated [simulation] position.
///
/// [simulation] is produced by [premoveSimulation] (or the live engine at
/// execution time); the side to move is forced to [color] on a throwaway
/// clone so the same helper covers both queue-time and execution-time
/// validation.
bool isLegalPremove(
  Position simulation,
  String from,
  String to, {
  String? promotion,
  required PieceColor color,
}) {
  final sqFrom = Square.tryParse(from);
  final sqTo = Square.tryParse(to);
  if (sqFrom == null || sqTo == null) return false;
  final probe = simulation.clone()..sideToMove = color;
  return probe.isLegalMove(
    sqFrom,
    sqTo,
    promotion: promotionTypeFor(promotion),
  );
}
