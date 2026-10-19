// Standard chess board square — pure Dart, no Flutter imports.
//
// Design decisions:
// - A [Square] is an immutable value object with 0-based coordinates:
//   `file` 0..7 maps to a..h, `rank` 0..7 maps to ranks 1..8, and
//   **a1 == (file 0, rank 0)**. Zero-based indexing keeps array-style
//   arithmetic (`rank + pawnStep`) branch-free; the `+1` only appears at
//   the display/FEN boundary.
// - Squares are usable as `Map` keys (board representation in
//   position.dart), hence the explicit `==`/`hashCode`.
// - [offset] returns `null` instead of throwing for off-board targets so
//   move generation can use it in a filter style without try/catch.
// - Out-of-range construction via the const constructor is guarded by
//   asserts; named factories parsing external input throw descriptive
//   errors ([FormatException]/[RangeError]) instead.

import 'package:meta/meta.dart';

/// An immutable board square with 0-based [file] (a=0..h=7) and [rank]
/// (1st rank=0..8th rank=7). **a1 == `Square(0, 0)`**, h8 == (7, 7).
@immutable
class Square implements Comparable<Square> {
  /// 0-based file: 0 == `a`, ..., 7 == `h`.
  final int file;

  /// 0-based rank: 0 == 1st rank, ..., 7 == 8th rank.
  final int rank;

  /// Creates the square at ([file], [rank]).
  ///
  /// Asserts 0..7 for both coordinates in checked mode.
  const Square(this.file, this.rank)
      : assert(file >= 0 && file <= 7, 'file must be 0..7'),
        assert(rank >= 0 && rank <= 7, 'rank must be 0..7');

  /// Parses algebraic notation such as `'e2'` or `'a8'`.
  ///
  /// The file letter is case-insensitive (`'E2'` works) and surrounding
  /// whitespace is ignored, matching [parseSquare] in piece.dart.
  /// Throws a [FormatException] if [name] is not exactly `<a-h><1-8>`
  /// (after trimming).
  factory Square.fromName(String name) {
    final text = name.trim();
    if (text.length != 2) {
      throw FormatException('Invalid square name: $name');
    }
    final file = text[0].toLowerCase().codeUnitAt(0) - _aCode;
    final rank = text.codeUnitAt(1) - _oneCode;
    if (file < 0 || file > 7 || rank < 0 || rank > 7) {
      throw FormatException('Invalid square name: $name');
    }
    return Square(file, rank);
  }

  /// Creates the square for a 0-based [index] in a1=0 … h8=63 order,
  /// i.e. `index == rank * 8 + file`.
  ///
  /// Throws a [RangeError] when [index] is outside 0..63.
  factory Square.fromIndex(int index) {
    if (index < 0 || index > 63) {
      throw RangeError.range(index, 0, 63, 'index');
    }
    return Square(index % 8, index ~/ 8);
  }

  /// Parses algebraic notation such as `'e2'`, returning `null` instead
  /// of throwing for `null` or malformed input.
  ///
  /// Compat: the variant controller parses user/LLM-supplied square
  /// names with this; engine code that wants hard errors uses
  /// [Square.fromName].
  static Square? tryParse(String? name) {
    if (name == null) return null;
    try {
      return Square.fromName(name.trim());
    } on FormatException {
      return null;
    }
  }

  static const int _aCode = 97; // 'a'
  static const int _oneCode = 49; // '1'

  /// 0-based board index in a1=0 … h8=63 order (`rank * 8 + file`).
  int get index => rank * 8 + file;

  /// Algebraic notation for this square, e.g. `'e2'`.
  String get name =>
      '${String.fromCharCode(_aCode + file)}${String.fromCharCode(_oneCode + rank)}';

  /// File letter of this square (`'a'`..`'h'`).
  String get fileName => String.fromCharCode(_aCode + file);

  /// Rank digit of this square (`'1'`..`'8'`).
  String get rankName => (rank + 1).toString();

  /// True when this is a light-colored square.
  ///
  /// Follows from a1 being dark: light squares satisfy
  /// `(file + rank).isOdd`.
  bool get colorIsLight => (file + rank).isOdd;

  /// True when this is a dark-colored square (a1 is dark).
  bool get isDark => !colorIsLight;

  /// Returns the square [dx] files and [dy] ranks away, or `null` when
  /// that target lies off the board.
  Square? offset(int dx, int dy) {
    final f = file + dx;
    final r = rank + dy;
    if (f < 0 || f > 7 || r < 0 || r > 7) return null;
    return Square(f, r);
  }

  /// Orders squares by [index] (a1 first, h8 last).
  @override
  int compareTo(Square other) => index.compareTo(other.index);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Square && other.file == file && other.rank == rank);

  @override
  int get hashCode => Object.hash(file, rank);

  @override
  String toString() => 'Square($name)';
}
