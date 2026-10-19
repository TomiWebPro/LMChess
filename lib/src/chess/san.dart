// SAN (Standard Algebraic Notation) for standard chess — pure Dart.
//
// Design decisions:
// - There is exactly ONE SAN generator: the private routine inside
//   position.dart used by `Position.apply`. [toSan] delegates to it via
//   `clone() + apply()`, so generated SAN can never drift from what the
//   engine itself records, and `+`/`#` suffixes always reflect the true
//   post-move state.
// - [parseSan] works primarily by generating the SAN of every legal move
//   and comparing (after normalizing annotations and castling zeros).
//   This makes the parser correct *by construction* for everything the
//   generator emits — disambiguation, promotions, en passant (no special
//   `e.p.` marker, per standard), `O-O`/`O-O-O` — at the cost of O(n)
//   clone+apply cycles, which is irrelevant at game-input scale.
// - Two pragmatic fallbacks keep casual/LLM input working: long
//   algebraic (`e2e4`, `e7e8q`) and promotion SAN without `=` (`e8Q`).
//   Anything else throws [FormatException]. Move-number prefixes
//   (`1. e4`) and `!`/`?` annotations are stripped, not interpreted.

import 'move.dart';
import 'piece.dart';
import 'position.dart';
import 'square.dart';

/// Returns the SAN text of [move] in the context of [before].
///
/// [before] is not modified (the move is played on a clone).
/// Throws a [StateError] when [move] is illegal in [before].
String toSan(Position before, ChessMove move) {
  final probe = before.clone();
  return probe.apply(move).san;
}

/// Parses [san] into the matching legal move in [position].
///
/// Accepts standard SAN (including `O-O`/`O-O-O`, disambiguation like
/// `Nbd7`/`R1e2`, captures, promotions `=Q`, and `+`/`#`/`!`/`?`
/// suffixes), plus long algebraic (`e2e4`, `e7e8q`) and `=`-less
/// promotions (`e8Q`) as conveniences.
///
/// Throws a [FormatException] when the text cannot be parsed, and a
/// [StateError] when it parses but matches no legal move.
ChessMove parseSan(Position position, String san) {
  var text = san.trim();
  if (text.isEmpty) throw FormatException('Cannot parse empty SAN');

  // Drop move numbers ("1. e4", "1...e5") and surrounding whitespace.
  text = text.replaceAll(RegExp(r'^\d+\s*\.+\s*'), '').trim();
  // Annotations carry no move identity; strip them and stray spaces.
  text = text.replaceAll(' ', '');
  text = text.replaceAll(RegExp(r'[+#?!]+$'), '');
  // Tolerate a trailing en-passant marker ("e.p.", "ep", "e.p" in any
  // case). Anchored to the end so piece letters are never touched: the
  // old unanchored pattern deleted every `e` (`e4` -> `4`).
  text = text.replaceAll(
      RegExp(r'\s*e\.?\s*p\.?\s*$', caseSensitive: false), '');

  // Castling also arrives as 0-0 / 0-0-0 from some sources.
  final castle = text.replaceAll('0', 'O');
  if (castle == 'O-O' || castle == 'O-O-O') {
    final targetFile = castle == 'O-O' ? 6 : 2;
    for (final m in position.legalMoves()) {
      final piece = position.board[m.from];
      if (piece != null &&
          piece.type == PieceType.king &&
          piece.color == position.sideToMove &&
          m.to.file == targetFile &&
          m.to.rank == piece.color.backRank) {
        return m;
      }
    }
    throw StateError('No legal castling move for SAN: $san');
  }

  // Tolerate missing '=' in promotions: e8Q -> e8=Q, exd8Q -> exd8=Q.
  // Case-insensitive so lowercase `e8q` also normalizes (square part
  // lowercased, promo letter uppercased to match generated SAN).
  text = text.replaceAllMapped(
    RegExp(r'^([a-h]x[a-h][18]|[a-h][18])([QRBN])$',
        caseSensitive: false),
    (m) => '${m[1]!.toLowerCase()}=${m[2]!.toUpperCase()}',
  );

  final legal = position.legalMoves();
  for (final m in legal) {
    final generated =
        toSan(position, m).replaceAll(RegExp(r'[+#]+$'), '');
    if (generated == text) return m;
  }

  // Long-algebraic fallback: e2e4, e7e8q (case-insensitive promo).
  final uci = RegExp(r'^([a-h][1-8])([a-h][1-8])([qrbnQRBN])?$');
  final match = uci.firstMatch(text);
  if (match != null) {
    final from = Square.fromName(match[1]!);
    final to = Square.fromName(match[2]!);
    PieceType? promotion;
    if (match[3] != null) {
      promotion = PieceTypeX.parseLetter(match[3]!);
    }
    final candidate = ChessMove(from, to, promotion: promotion);
    if (legal.contains(candidate)) return candidate;
    throw StateError('Illegal move for SAN/long-algebraic: $san');
  }

  throw FormatException('Cannot parse SAN: $san');
}
