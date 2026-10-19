// Standard chess piece model — pure Dart, no Flutter imports.
//
// Design decisions:
// - Pieces are immutable value objects (`const` constructor, final fields).
//   Positions hold the mutable game state; pieces themselves never change,
//   which makes board cloning cheap (shared [Piece] instances).
// - [PieceColor] carries the coordinate-dependent helpers ([pawnStep],
//   [backRank], ...) so move generation reads naturally. These assume the
//   [Square] convention documented in square.dart: a1 == (file 0, rank 0),
//   White advances towards increasing rank.
// - Unicode symbols are display concerns but live here (rather than in UI)
//   so every consumer renders the same glyphs. SAN/FEN letters use plain
//   ASCII via [PieceType.letter]/[Piece.fenChar].
// - This file is ONLY for standard chess. Variant pieces (e.g. chaotic
//   chess) live in lib/src/variant and must not extend these enums.
// - Cross-module compatibility surface (documented inline as `Compat`):
//   the UI board and the variant controller are developed alongside this
//   engine and import this file directly. The following are load-bearing
//   contracts for them and must not be renamed/reshaped without updating
//   those callers: [PieceTypeX] (name + nullable [PieceTypeX.fromLetter]),
//   [Piece.code] (`'wK'` style), [PieceColor.code] (`'w'`/`'b'`),
//   [PieceColor.opponent], [PieceType.symbol], the static
//   `tryParse` constructors, [ChessPiece], and the [kFiles]/[kRanks]/
//   [squareName]/[parseSquare] helpers. Enum value ORDER follows the
//   engine spec (pawn first); consumers must match on names, never on
//   `.index`.

import 'package:meta/meta.dart';

/// The six standard chess piece types, in engine-spec order.
enum PieceType {
  /// Moves forward, captures diagonally, promotes on the last rank.
  pawn,

  /// Jumps in an L-shape; the only piece that can jump over others.
  knight,

  /// Slides diagonally.
  bishop,

  /// Slides orthogonally.
  rook,

  /// Slides diagonally and orthogonally.
  queen,

  /// Moves one square; must never be left in check.
  king;

  /// Single UPPERCASE English letter identifying this type (`P N B R Q
  /// K`, SAN convention; knight is `N`). Note that in SAN the pawn
  /// letter is implied (a pawn move shows no letter), but [letter] still
  /// returns `'P'` so FEN and promotion (`=Q`) logic stays uniform.
  String get letter => switch (this) {
        PieceType.pawn => 'P',
        PieceType.knight => 'N',
        PieceType.bishop => 'B',
        PieceType.rook => 'R',
        PieceType.queen => 'Q',
        PieceType.king => 'K',
      };

  /// Compact single lowercase letter for this type (`p n b r q k`).
  ///
  /// Compat: used by the variant controller for layout hashes and
  /// diagnostics (e.g. `'${color.code}${type.symbol}'`). Not parsed back
  /// by [tryParse]... (it is: [tryParse] also accepts these letters).
  String get symbol => letter.toLowerCase();

  /// Whether this piece moves along rays ([bishop], [rook], [queen]).
  bool get isSlider =>
      this == PieceType.bishop ||
      this == PieceType.rook ||
      this == PieceType.queen;

  /// Conventional material value in pawns (king has no meaningful value).
  ///
  /// Intended for ordering/evaluation heuristics, not for rules.
  int get value => switch (this) {
        PieceType.pawn => 1,
        PieceType.knight => 3,
        PieceType.bishop => 3,
        PieceType.rook => 5,
        PieceType.queen => 9,
        PieceType.king => 0,
      };

  /// Parses [input] back to a [PieceType], or returns `null`.
  ///
  /// Compat: used by the variant controller to deserialize JSON produced
  /// with [PieceType.name]. Accepts enum names (`'pawn'`, ...) and single
  /// letters (`'p'`/`'P'`, `'n'`/`'N'`, ...), case-insensitive. Returns
  /// `null` for `null` or unrecognized input instead of throwing.
  static PieceType? tryParse(String? input) {
    if (input == null) return null;
    final text = input.trim().toLowerCase();
    for (final type in PieceType.values) {
      if (type.name == text) return type;
    }
    return PieceTypeX.fromLetter(text);
  }
}

/// Extra helpers for [PieceType].
///
/// Compat: the UI board references this extension BY NAME
/// ([PieceTypeX.fromLetter]); do not rename it.
extension PieceTypeX on PieceType {
  /// Piece types a pawn may promote to, in the conventional preference
  /// order used when expanding promotion moves.
  static const List<PieceType> promotionChoices = <PieceType>[
    PieceType.queen,
    PieceType.rook,
    PieceType.bishop,
    PieceType.knight,
  ];

  /// Parses a single piece letter (`P N B R Q K`, case-insensitive).
  ///
  /// Compat: the UI board cell parser calls this with arbitrary user
  /// input and null-checks the result, so this returns `null` (never
  /// throws) for unrecognized input.
  static PieceType? fromLetter(String letter) {
    switch (letter.toLowerCase()) {
      case 'p':
        return PieceType.pawn;
      case 'n':
        return PieceType.knight;
      case 'b':
        return PieceType.bishop;
      case 'r':
        return PieceType.rook;
      case 'q':
        return PieceType.queen;
      case 'k':
        return PieceType.king;
      default:
        return null;
    }
  }

  /// Parses a single piece letter, throwing a [FormatException] on
  /// unknown input. Engine-internal counterpart of [fromLetter] for
  /// contexts (UCI, FEN) where malformed input is a hard error.
  static PieceType parseLetter(String letter) {
    final type = fromLetter(letter);
    if (type == null) {
      throw FormatException('Unknown piece letter: $letter');
    }
    return type;
  }
}

/// The side a piece belongs to / the side to move.
enum PieceColor {
  /// Moves first; starts on ranks 1-2 and advances towards rank 8.
  white,

  /// Moves second; starts on ranks 7-8 and advances towards rank 1.
  black;

  /// The opposing color.
  PieceColor get opposite =>
      this == PieceColor.white ? PieceColor.black : PieceColor.white;

  /// Alias of [opposite].
  ///
  /// Compat: the variant controller/evaluator use `.opponent`
  /// throughout; both spellings are supported so neither caller churns.
  PieceColor get opponent => opposite;

  /// True when this is [white].
  bool get isWhite => this == PieceColor.white;

  /// True when this is [black].
  bool get isBlack => !isWhite;

  /// Compact single-letter code: `'w'` for White, `'b'` for Black.
  ///
  /// Compat: the variant controller serializes colors with this (JSON,
  /// layout hashes) and parses them back with [tryParse]; the two must
  /// round-trip.
  String get code => isWhite ? 'w' : 'b';

  /// Rank index delta of one forward pawn step: `+1` for White, `-1`
  /// for Black (ranks increase from White's side).
  int get pawnStep => isWhite ? 1 : -1;

  /// Rank index of this color's home (back) rank: `0` for White, `7`
  /// for Black.
  int get backRank => isWhite ? 0 : 7;

  /// Rank index on which this color's pawns start: `1` (rank 2) for
  /// White, `6` (rank 7) for Black.
  int get pawnStartRank => isWhite ? 1 : 6;

  /// Rank index on which this color's pawns promote: `7` for White,
  /// `0` for Black.
  int get promotionRank => isWhite ? 7 : 0;

  /// Rank index a pawn of this color must stand on to capture en
  /// passant: `4` (rank 5) for White, `3` (rank 4) for Black.
  int get enPassantCaptureRank => isWhite ? 4 : 3;

  /// Parses [input] back to a [PieceColor], or returns `null`.
  ///
  /// Compat: the variant controller deserializes JSON produced with
  /// [code]. Accepts `'w'`/`'b'` and the full names
  /// (`'white'`/`'black'`), case-insensitive. Returns `null` for `null`
  /// or unrecognized input instead of throwing.
  static PieceColor? tryParse(String? input) {
    if (input == null) return null;
    switch (input.trim().toLowerCase()) {
      case 'w':
      case 'white':
        return PieceColor.white;
      case 'b':
      case 'black':
        return PieceColor.black;
      default:
        return null;
    }
  }
}

/// Extra helpers for [PieceColor] kept in an extension so the enum body
/// stays focused on the core model.
extension PieceColorX on PieceColor {
  /// Lowercase FEN-style name (`'white'` / `'black'`).
  String get displayName => isWhite ? 'white' : 'black';

  /// FEN castling-right letters owned by this color, in canonical
  /// `KQkq` order subset (`['K', 'Q']` for White, `['k', 'q']` for Black).
  List<String> get castlingLetters =>
      isWhite ? const <String>['K', 'Q'] : const <String>['k', 'q'];
}

/// An immutable pairing of [PieceType] and [PieceColor].
@immutable
class Piece {
  /// What kind of piece this is.
  final PieceType type;

  /// Which side this piece belongs to.
  final PieceColor color;

  /// Creates a piece of [type] belonging to [color].
  const Piece(this.type, this.color);

  /// Uppercase SAN-style letter of this piece (see [PieceType.letter]).
  String get letter => type.letter;

  /// FEN character for this piece: uppercase for White, lowercase
  /// for Black (e.g. `'N'` vs `'n'`).
  String get fenChar =>
      color.isWhite ? type.letter : type.letter.toLowerCase();

  /// Unicode chess glyph for this piece, e.g. `♘` / `♞`.
  ///
  /// Uses the filled/outline convention: White gets the outline glyphs
  /// (♔♕♖♗♘♙), Black the filled ones (♚♛♜♝♞♟).
  String get symbol {
    if (color.isWhite) {
      return switch (type) {
        PieceType.king => '♔',
        PieceType.queen => '♕',
        PieceType.rook => '♖',
        PieceType.bishop => '♗',
        PieceType.knight => '♘',
        PieceType.pawn => '♙',
      };
    }
    return switch (type) {
      PieceType.king => '♚',
      PieceType.queen => '♛',
      PieceType.rook => '♜',
      PieceType.bishop => '♝',
      PieceType.knight => '♞',
      PieceType.pawn => '♟',
    };
  }

  /// Compact two-character code, e.g. `'wK'` (white king) or `'bP'`.
  ///
  /// Compat: part of the UI `Chessboard` cell-encoding contract (side
  /// letter + uppercase type letter).
  String get code =>
      '${color.isWhite ? 'w' : 'b'}${type.letter.toUpperCase()}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Piece && other.type == type && other.color == color);

  @override
  int get hashCode => Object.hash(type, color);

  @override
  String toString() => 'Piece($code)';
}

/// Alias of [Piece] under the name the variant controller uses when it
/// converts variant pieces back to standard pieces.
///
/// A typedef (not a subclass) so `Map<Square, ChessPiece>` is identical
/// to `Map<Square, Piece>` and `const ChessPiece(...)` construction,
/// equality and hashing behave exactly like [Piece].
typedef ChessPiece = Piece;

/// File labels from White's perspective (`a` on White's left).
///
/// Compat: used by the UI board for rank/file headers and square names.
const List<String> kFiles = <String>['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];

/// Rank labels from White's perspective (`1` is White's home rank).
///
/// Compat: used by the UI board for rank/file headers and square names.
const List<String> kRanks = <String>['1', '2', '3', '4', '5', '6', '7', '8'];

/// Returns the algebraic square name for zero-based [file] and [rank].
///
/// Compat: used by the UI board to key its `squares` map.
/// Throws [RangeError] when out of bounds.
String squareName(int file, int rank) {
  RangeError.checkValueInInterval(file, 0, 7, 'file');
  RangeError.checkValueInInterval(rank, 0, 7, 'rank');
  return '${kFiles[file]}${kRanks[rank]}';
}

/// Parses an algebraic square name (`'e4'`) into a `(file, rank)` record.
///
/// Compat: UI tap handling / text fields use this for cheap validation.
/// Returns `null` for malformed input instead of throwing.
(int, int)? parseSquare(String square) {
  if (square.length != 2) return null;
  final file = kFiles.indexOf(square[0].toLowerCase());
  final rank = kRanks.indexOf(square[1]);
  if (file < 0 || rank < 0) return null;
  return (file, rank);
}
