/// Heuristic board evaluator for the chaotic variant (NOT a chess engine).
///
/// [VariantEvaluator] assigns a centipawn-ish score to a [VariantBoard] from
/// a given perspective so that interpretation candidates can be ranked on one
/// comparable scale. It is a **hand-written heuristic fallback** built from:
///
/// * material (P100 N320 B330 R500 Q900 K20000),
/// * ±100000 when a king is missing (enemy king gone: won; own king gone: lost),
/// * pseudo-mobility (reachable squares, no check filtering),
/// * centralization (Manhattan closeness to the centre),
/// * threats against the enemy king (attackers weighted, adjacency included).
///
/// It must **never be presented as Stockfish output or any real engine
/// evaluation**: it does not search, has no opening/endgame knowledge, and its
/// king values exist to make king-capture play dominate, not to reflect real
/// chess. UI labels should read "heuristic" wherever this score surfaces.
library;

import '../chess/piece.dart';
import '../chess/square.dart';
import 'variant_board.dart';

/// Heuristic evaluator. All members are static; the class is not instantiable.
class VariantEvaluator {
  /// Private constructor (static-only class).
  const VariantEvaluator._();

  /// Standard-ish piece values in centipawn-ish units.
  static const Map<PieceType, int> pieceValues = {
    PieceType.pawn: 100,
    PieceType.knight: 320,
    PieceType.bishop: 330,
    PieceType.rook: 500,
    PieceType.queen: 900,
    PieceType.king: 20000,
  };

  /// Bonus/penalty applied when the enemy/own king is missing from the board.
  ///
  /// Chosen to dwarf any material combination so that king-capture play
  /// always dominates strategic selection.
  static const int kingCaptureBonus = 100000;

  /// Score per reachable (pseudo-legal, check-untested) square.
  static const int mobilityWeight = 2;

  /// Score per attacker threatening the enemy king.
  static const int kingThreatWeight = 150;

  /// Scores [board] from [perspective]'s point of view (positive is good for
  /// [perspective]).
  ///
  /// Breakdown: material balance, king-missing bonus/penalty, mobility edge,
  /// centralization edge, and enemy-king threats. Deterministic.
  static int score(VariantBoard board, PieceColor perspective) {
    var total = materialBalance(board, perspective);
    final ownKings = board.kingSquares(perspective).length;
    final enemyKings = board.kingSquares(perspective.opposite).length;
    if (enemyKings == 0) total += kingCaptureBonus;
    if (ownKings == 0) total -= kingCaptureBonus;
    total += _mobilityEdge(board, perspective) * mobilityWeight;
    total += _centralityEdge(board, perspective);
    if (enemyKings > 0) {
      total += _kingAttackers(board, perspective.opposite).length *
          kingThreatWeight;
    }
    return total;
  }

  /// Material balance (own piece values minus enemy piece values) from
  /// [perspective]'s point of view. Kings count at [pieceValues].
  static int materialBalance(VariantBoard board, PieceColor perspective) {
    var total = 0;
    for (final p in board.squares.values) {
      final v = pieceValues[p.type]!;
      total += p.color == perspective ? v : -v;
    }
    return total;
  }

  /// `true` when any piece of [attacker] attacks the enemy king's square.
  ///
  /// Uses full attack rules (pawn capture diagonals, knight jumps, king
  /// adjacency, sliding pieces). `false` when the enemy has no king (there is
  /// nothing to attack; missing kings are handled by the [kingCaptureBonus]).
  /// With several enemy kings, `true` when *any* of them is attacked.
  static bool attacksKing(VariantBoard board, PieceColor attacker) =>
      _kingAttackers(board, attacker.opposite).isNotEmpty;

  // ------------------------------------------------------------- internals

  /// Enemy king squares of [victim] that are attacked by `victim.opposite`'s
  /// pieces. Empty when [victim] has no kings or none are attacked.
  static List<Square> _kingAttackers(VariantBoard board, PieceColor victim) {
    final out = <Square>[];
    for (final kingSq in board.kingSquares(victim)) {
      if (_isAttacked(board, kingSq, victim.opposite)) out.add(kingSq);
    }
    return out;
  }

  /// `true` when [sq] is attacked by any piece of colour [by].
  static bool _isAttacked(
      VariantBoard board, Square sq, PieceColor by) {
    PieceType? at(Square s) => board.squares[s]?.type;
    PieceColor? colorAt(Square s) => board.squares[s]?.color;
    bool owned(Square s, PieceType t) =>
        colorAt(s) == by && at(s) == t;

    // Pawns capture one step diagonally forward.
    final pawnRank = sq.rank + (by.isWhite ? -1 : 1);
    for (final df in <int>[-1, 1]) {
      final f = sq.file + df;
      if (f >= 0 && f < 8 && pawnRank >= 0 && pawnRank < 8) {
        if (owned(Square(f, pawnRank), PieceType.pawn)) return true;
      }
    }
    // Knights.
    const knightOffsets = [
      (1, 2), (2, 1), (2, -1), (1, -2),
      (-1, -2), (-2, -1), (-2, 1), (-1, 2),
    ];
    for (final (df, dr) in knightOffsets) {
      final t = sq.offset(df, dr);
      if (t != null && owned(t, PieceType.knight)) return true;
    }
    // Adjacent king (covers "adjacent attackers" and royal proximity).
    for (final t in squareNeighbors(sq)) {
      if (owned(t, PieceType.king)) return true;
    }
    // Sliders.
    const rays = [
      ([(1, 1), (1, -1), (-1, 1), (-1, -1)],
          {PieceType.bishop, PieceType.queen}),
      ([(1, 0), (-1, 0), (0, 1), (0, -1)],
          {PieceType.rook, PieceType.queen}),
    ];
    for (final (dirs, types) in rays) {
      for (final (df, dr) in dirs) {
        var t = sq.offset(df, dr);
        while (t != null) {
          final p = board.squares[t];
          if (p != null) {
            if (p.color == by && types.contains(p.type)) return true;
            break;
          }
          t = t.offset(df, dr);
        }
      }
    }
    return false;
  }

  /// Pseudo-mobility edge: own reachable squares minus enemy reachable
  /// squares. Movement only (captures included, king safety ignored).
  static int _mobilityEdge(VariantBoard board, PieceColor perspective) =>
      _mobilityFor(board, perspective) -
      _mobilityFor(board, perspective.opposite);

  /// Counts reachable squares for all pieces of [color].
  static int _mobilityFor(VariantBoard board, PieceColor color) {
    var total = 0;
    for (final e in board.squares.entries) {
      if (e.value.color != color) continue;
      total += _destinations(board, e.key, e.value).length;
    }
    return total;
  }

  /// Pseudo-legal destination squares for one piece (king safety ignored).
  static List<Square> _destinations(
      VariantBoard board, Square from, VariantPiece p) {
    final out = <Square>[];
    void consider(Square t) {
      final dest = board.squares[t];
      if (dest == null || dest.color != p.color) out.add(t);
    }

    switch (p.type) {
      case PieceType.knight:
        for (final (df, dr) in [
          (1, 2), (2, 1), (2, -1), (1, -2),
          (-1, -2), (-2, -1), (-2, 1), (-1, 2),
        ]) {
          final t = from.offset(df, dr);
          if (t != null) consider(t);
        }
      case PieceType.king:
        for (final t in squareNeighbors(from)) {
          consider(t);
        }
      case PieceType.bishop:
        _ray(board, from, p, [(1, 1), (1, -1), (-1, 1), (-1, -1)], out);
      case PieceType.rook:
        _ray(board, from, p, [(1, 0), (-1, 0), (0, 1), (0, -1)], out);
      case PieceType.queen:
        _ray(board, from, p, [
          (1, 0), (-1, 0), (0, 1), (0, -1),
          (1, 1), (1, -1), (-1, 1), (-1, -1),
        ], out);
      case PieceType.pawn:
        final dir = p.color.isWhite ? 1 : -1;
        final one = from.offset(0, dir);
        if (one != null && board.squares[one] == null) {
          out.add(one);
          final start = p.color.isWhite ? 1 : 6;
          final two = from.offset(0, 2 * dir);
          if (from.rank == start &&
              two != null &&
              board.squares[two] == null) {
            out.add(two);
          }
        }
        for (final df in <int>[-1, 1]) {
          final t = from.offset(df, dir);
          if (t != null && board.squares[t] != null) consider(t);
        }
    }
    return out;
  }

  /// Adds sliding destinations along [dirs] to [out].
  static void _ray(VariantBoard board, Square from, VariantPiece p,
      List<(int, int)> dirs, List<Square> out) {
    for (final (df, dr) in dirs) {
      var t = from.offset(df, dr);
      while (t != null) {
        final dest = board.squares[t];
        if (dest == null) {
          out.add(t);
        } else {
          if (dest.color != p.color) out.add(t);
          break;
        }
        t = t.offset(df, dr);
      }
    }
  }

  /// Centralization edge: pieces nearer the centre score higher
  /// (Manhattan closeness, doubled per piece, own minus enemy).
  static int _centralityEdge(VariantBoard board, PieceColor perspective) {
    var total = 0;
    for (final e in board.squares.entries) {
      final closeness =
          7 - (e.key.file - 3.5).abs().round() - (e.key.rank - 3.5).abs().round();
      total += e.value.color == perspective ? closeness * 2 : -closeness * 2;
    }
    return total;
  }
}
