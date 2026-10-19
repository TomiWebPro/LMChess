// Standard chess move model — pure Dart, no Flutter imports.
//
// Design decisions:
// - [ChessMove] is deliberately minimal: origin, destination, optional
//   promotion piece. Everything else (captured piece, check/mate state,
//   SAN text) is derived by [Position.apply] and stored in [AppliedMove].
//   This keeps move equality simple and makes UCI round-trips lossless.
// - [ChessMove] intentionally carries no [MoveFlag]: the flag describes
//   how a move *was applied* in a concrete position (capture? castle?),
//   so it belongs to [AppliedMove], which is only constructed for moves
//   that were actually played. Move generation classifies internally and
//   surfaces the result via [AppliedMove.flag].
// - Castling is represented as a king move of two squares (e1→g1 /
//   e1→c1), matching UCI convention.

import 'package:meta/meta.dart';

import 'piece.dart';
import 'square.dart';

/// How a move was classified when it was applied to a position.
///
/// This is descriptive metadata, not part of move identity: two equal
/// [ChessMove]s played in different contexts could in principle carry
/// different flags, so the flag lives on [AppliedMove].
enum MoveFlag {
  /// Quiet move: no capture, no pawn double push, no castling, no
  /// promotion, no en passant.
  normal,

  /// Captures an enemy piece (not en passant, not a promotion capture —
  /// those use [enPassant] / [promotion]).
  capture,

  /// Pawn advance of two squares from its starting rank. Establishes an
  /// en-passant target square.
  doublePush,

  /// En-passant capture. The captured pawn is beside the moving pawn,
  /// not on the destination square.
  enPassant,

  /// Kingside castling (O-O; king moves two squares towards the h-file).
  castleKingside,

  /// Queenside castling (O-O-O; king moves two squares towards the
  /// a-file).
  castleQueenside,

  /// Pawn promotion, with or without a capture. The promotion piece is
  /// [ChessMove.promotion]; a promotion capture also records
  /// [AppliedMove.captured].
  promotion,
}

/// Helpers on [MoveFlag].
extension MoveFlagHelpers on MoveFlag {
  /// True for [MoveFlag.castleKingside] and [MoveFlag.castleQueenside].
  bool get isCastle =>
      this == MoveFlag.castleKingside || this == MoveFlag.castleQueenside;
}

/// An immutable chess move: origin [from], destination [to], and an
/// optional [promotion] piece type.
///
/// Equality covers all three fields, so `e7e8q` and `e7e8r` are
/// different moves. Use [uci] for compact serialization and
/// [ChessMove.fromUci] to parse it back.
@immutable
class ChessMove implements Comparable<ChessMove> {
  /// Origin square of the moving piece.
  final Square from;

  /// Destination square.
  final Square to;

  /// Piece type the pawn promotes to, or `null` for non-promotions.
  ///
  /// When non-null this is always queen, rook, bishop or knight —
  /// promoting to a pawn or king is illegal and never generated.
  final PieceType? promotion;

  /// Creates a move from [from] to [to], optionally promoting to
  /// [promotion].
  const ChessMove(this.from, this.to, {this.promotion});

  /// Parses a UCI string such as `'e2e4'` or `'e7e8q'`.
  ///
  /// The promotion suffix (if present) accepts `q r b n`,
  /// case-insensitive. Throws a [FormatException] on malformed input.
  factory ChessMove.fromUci(String uci) {
    final text = uci.trim();
    if (text.length != 4 && text.length != 5) {
      throw FormatException('Invalid UCI move: $uci');
    }
    final from = Square.fromName(text.substring(0, 2));
    final to = Square.fromName(text.substring(2, 4));
    PieceType? promotion;
    if (text.length == 5) {
      promotion = PieceTypeX.parseLetter(text[4]);
      if (promotion == PieceType.pawn || promotion == PieceType.king) {
        throw FormatException('Invalid promotion piece in UCI move: $uci');
      }
    }
    return ChessMove(from, to, promotion: promotion);
  }

  /// UCI serialization, e.g. `'e2e4'` or `'e7e8q'` (lowercase piece
  /// letter for promotions).
  String get uci {
    final promo = promotion == null
        ? ''
        : promotion!.letter.toLowerCase();
    return '${from.name}${to.name}$promo';
  }

  /// True when this move promotes a pawn.
  bool get isPromotion => promotion != null;

  /// Orders moves by origin square, then destination, then promotion.
  @override
  int compareTo(ChessMove other) {
    final c = from.compareTo(other.from);
    if (c != 0) return c;
    final d = to.compareTo(other.to);
    if (d != 0) return d;
    return (promotion?.index ?? -1).compareTo(other.promotion?.index ?? -1);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChessMove &&
          other.from == from &&
          other.to == to &&
          other.promotion == promotion);

  @override
  int get hashCode => Object.hash(from, to, promotion);

  @override
  String toString() => 'ChessMove($uci)';
}

/// Record of a move that was actually played on a [Position].
///
/// Created (and only creatable in practice) by `Position.apply`, which
/// fills in the position-dependent facts: what was captured, how the
/// move classified, whether it gives check / mates / stalemates, and
/// the SAN text of the move in context.
@immutable
class AppliedMove {
  /// The move that was played.
  final ChessMove move;

  /// How the move classified in the position it was played in.
  final MoveFlag flag;

  /// The captured piece, or `null` for non-captures.
  ///
  /// For en passant this is the bypassed pawn (which stood beside the
  /// moving pawn, not on [ChessMove.to]).
  final Piece? captured;

  /// Whether the move leaves the opponent in check (includes mate).
  final bool isCheck;

  /// Whether the move checkmates the opponent.
  final bool isCheckmate;

  /// Whether the move stalemates the opponent (position after the move
  /// has no legal replies and the side to move is not in check).
  final bool isStalemate;

  /// Standard Algebraic Notation of the move, including `+`/`#`,
  /// disambiguation, `O-O`/`O-O-O` and promotion suffixes.
  final String san;

  /// Creates a record of an applied move.
  const AppliedMove({
    required this.move,
    this.flag = MoveFlag.normal,
    this.captured,
    required this.isCheck,
    required this.isCheckmate,
    required this.isStalemate,
    required this.san,
  });

  /// True when a piece was captured (any capture kind, including en
  /// passant and promotion captures).
  bool get isCapture => captured != null;

  /// True when the move was castling.
  bool get isCastle => flag.isCastle;

  @override
  String toString() => 'AppliedMove($san)';
}
