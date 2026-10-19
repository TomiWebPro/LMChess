// FEN serialization for standard chess — pure Dart, no Flutter imports.
//
// Design decisions:
// - FEN is the interchange format between the engine, persistence and
//   (later) LLM move I/O, so parsing is strict: exactly six fields,
//   validated piece placement (row sums of 8), exactly one king per
//   side, no pawns on ranks 1/8, validated castling
//   characters, en-passant squares restricted to ranks 3/6, and
//   non-negative clocks with fullmove >= 1. Anything else throws
//   [FormatException] (including wrapped integer/square parse errors).
//   A stale en-passant square (no matching double push) is kept as
//   parsed but yields no EP capture — see [_validateBoard].
// - [toFen] always emits castling rights in canonical `KQkq` order and
//   `-` for empty rights / absent en-passant square, so
//   `toFen(parseFen(f))` round-trips for canonical input.
// - History is NOT part of FEN by definition; parsed positions start
//   with an empty history. Repetition tracking is the game
//   controller's responsibility.

import 'piece.dart';
import 'position.dart';
import 'square.dart';

/// Canonical castling-right order used by FEN.
const List<String> _fenCastlingOrder = <String>['K', 'Q', 'k', 'q'];

/// Parses a Forsyth-Edwards Notation string into a [Position].
///
/// Expects all six fields:
/// `piece-placement active-color castling en-passant halfmove fullmove`,
/// e.g. `rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1`.
///
/// Throws a [FormatException] on any malformed input.
Position parseFen(String fen) {
  final parts = fen.trim().split(RegExp(r'\s+'));
  if (parts.length != 6) {
    throw FormatException(
        'FEN must have 6 fields, found ${parts.length}: $fen');
  }

  final board = _parsePlacement(parts[0]);
  final sideToMove = _parseActiveColor(parts[1]);
  final castling = _parseCastling(parts[2]);
  final enPassant = _parseEnPassant(parts[3]);
  final halfmove = _parseCounter(parts[4], 'halfmove clock', min: 0);
  final fullmove = _parseCounter(parts[5], 'fullmove number', min: 1);
  _validateBoard(board, fen);

  return Position(
    board: board,
    sideToMove: sideToMove,
    castling: castling,
    enPassant: enPassant,
    halfmoveClock: halfmove,
    fullmoveNumber: fullmove,
  );
}

/// Serializes [position] to a FEN string (all six fields).
String toFen(Position position) => _writeFen(position);

/// Position-oriented access to FEN serialization.
///
/// Lets controllers write `position.toFen()`; identical to the top-level
/// [toFen] function.
extension PositionFen on Position {
  /// Serializes this position to a FEN string (all six fields).
  String toFen() => _writeFen(this);
}

/// Shared FEN writer behind [toFen] and [PositionFen.toFen].
String _writeFen(Position position) {
  final buf = StringBuffer();
  for (var r = 7; r >= 0; r--) {
    var empty = 0;
    for (var f = 0; f < 8; f++) {
      final piece = position.board[Square(f, r)];
      if (piece == null) {
        empty++;
      } else {
        if (empty > 0) {
          buf.write(empty);
          empty = 0;
        }
        buf.write(piece.fenChar);
      }
    }
    if (empty > 0) buf.write(empty);
    if (r > 0) buf.write('/');
  }
  buf.write(position.sideToMove.isWhite ? ' w ' : ' b ');
  if (position.castling.isEmpty) {
    buf.write('-');
  } else {
    for (final c in _fenCastlingOrder) {
      if (position.castling.contains(c)) buf.write(c);
    }
  }
  buf.write(' ');
  buf.write(position.enPassant?.name ?? '-');
  buf.write(' ${position.halfmoveClock} ${position.fullmoveNumber}');
  return buf.toString();
}

/// Parses the piece-placement field (8 slash-separated ranks, 8th first).
Map<Square, Piece> _parsePlacement(String field) {
  const validPieces = 'pnbrqkPNBRQK';
  final rows = field.split('/');
  if (rows.length != 8) {
    throw FormatException('FEN placement must have 8 ranks: $field');
  }
  final board = <Square, Piece>{};
  for (var i = 0; i < 8; i++) {
    final rank = 7 - i;
    final row = rows[i];
    var file = 0;
    for (var j = 0; j < row.length; j++) {
      final ch = row[j];
      final digit = ch.codeUnitAt(0) - 48; // '0'
      if (digit >= 1 && digit <= 8) {
        file += digit;
      } else if (validPieces.contains(ch)) {
        if (file >= 8) {
          throw FormatException('FEN rank overflows 8 files: $row');
        }
        final color =
            ch == ch.toUpperCase() ? PieceColor.white : PieceColor.black;
        board[Square(file, rank)] =
            Piece(PieceTypeX.parseLetter(ch), color);
        file++;
      } else {
        throw FormatException('Invalid FEN placement character: $ch');
      }
    }
    if (file != 8) {
      throw FormatException('FEN rank does not sum to 8 files: $row');
    }
  }
  return board;
}

/// Parses the active-color field (`w` / `b`).
PieceColor _parseActiveColor(String field) {
  if (field == 'w') return PieceColor.white;
  if (field == 'b') return PieceColor.black;
  throw FormatException('FEN active color must be "w" or "b": $field');
}

/// Parses the castling field (`-` or a subset of `KQkq` without repeats).
Set<String> _parseCastling(String field) {
  if (field == '-') return <String>{};
  if (field.isEmpty || field.length > 4) {
    throw FormatException('Invalid FEN castling field: $field');
  }
  final rights = <String>{};
  for (var i = 0; i < field.length; i++) {
    final ch = field[i];
    if (!_fenCastlingOrder.contains(ch) || !rights.add(ch)) {
      throw FormatException('Invalid FEN castling field: $field');
    }
  }
  return rights;
}

/// Parses the en-passant field (`-` or a square on rank 3/6).
Square? _parseEnPassant(String field) {
  if (field == '-') return null;
  final square = Square.fromName(field); // throws FormatException.
  if (square.rank != 2 && square.rank != 5) {
    throw FormatException(
        'FEN en-passant square must be on rank 3 or 6: $field');
  }
  return square;
}

/// Parses a non-negative integer clock field.
int _parseCounter(String field, String name, {required int min}) {
  final value = int.tryParse(field);
  if (value == null || value < min) {
    throw FormatException('Invalid FEN $name: $field');
  }
  return value;
}

/// Validates board-level legality gates: exactly one king per side and
/// no pawns on ranks 1/8 (promoted-or-illegal placements).
///
/// Clock ranges are enforced by [_parseCounter]; a stale en-passant
/// square is kept as parsed (documented behavior — [_pawnMoves] in
/// position.dart sanity-checks EP captures against the actual pawns,
/// so a stale square simply yields no EP move rather than corrupting
/// play). Throws a [FormatException] on violations.
void _validateBoard(Map<Square, Piece> board, String fen) {
  var whiteKings = 0;
  var blackKings = 0;
  for (final entry in board.entries) {
    if (entry.value.type == PieceType.king) {
      if (entry.value.color.isWhite) {
        whiteKings++;
      } else {
        blackKings++;
      }
    }
    if (entry.value.type == PieceType.pawn &&
        (entry.key.rank == 0 || entry.key.rank == 7)) {
      throw FormatException('FEN has a pawn on rank 1 or 8: $fen');
    }
  }
  if (whiteKings != 1 || blackKings != 1) {
    throw FormatException(
        'FEN must have exactly one king per side '
        '(white: $whiteKings, black: $blackKings): $fen');
  }
}
