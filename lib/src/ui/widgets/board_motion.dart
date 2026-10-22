/// Small from→to transition value for the chessboard motion layer (§15.2).
///
/// Hosts that retain `AppliedMove` receipts (Play/Watch) build one with
/// [BoardMove.fromApplied]; snapshot-based hosts (Review, Variant Replay)
/// derive `from`/`to` straight from their UCI/journals. The board renders
/// from its own old→new square diff — the moving piece, a fading captured
/// glyph (capture / en passant), a castling rook and the promotion swap are
/// all derived from the two snapshots — so a plain `from`/`to` is always
/// enough; [flag], [captured] and [promotion] are descriptive metadata for
/// hosts that want to annotate the transition explicitly.
library;

import 'package:flutter/foundation.dart';

import '../../chess/move.dart';
import '../../chess/piece.dart';
import '../../chess/square.dart';

/// A from→to transition for the board motion layer.
@immutable
class BoardMove {
  /// Creates a transition from [from] to [to], optionally annotated with
  /// [flag], the [captured] piece and the [promotion] piece type.
  const BoardMove({
    required this.from,
    required this.to,
    this.flag = MoveFlag.normal,
    this.captured,
    this.promotion,
  });

  /// Builds a transition from an [AppliedMove] receipt.
  factory BoardMove.fromApplied(AppliedMove receipt) => BoardMove(
        from: receipt.move.from,
        to: receipt.move.to,
        flag: receipt.flag,
        captured: receipt.captured,
        promotion: receipt.move.promotion,
      );

  /// Origin square of the moving piece.
  final Square from;

  /// Destination square.
  final Square to;

  /// How the move was classified (descriptive; the board may derive the
  /// same facts from its snapshot diff).
  final MoveFlag flag;

  /// The captured piece, or `null` for quiet moves.
  final Piece? captured;

  /// Piece the pawn promoted to, or `null`.
  final PieceType? promotion;

  @override
  bool operator ==(Object other) =>
      other is BoardMove &&
      other.from == from &&
      other.to == to &&
      other.flag == flag &&
      other.captured == captured &&
      other.promotion == promotion;

  @override
  int get hashCode => Object.hash(from, to, flag, captured, promotion);

  @override
  String toString() =>
      'BoardMove(${from.name}→${to.name}, $flag${promotion == null ? '' : ', →${promotion!.name}'})';
}