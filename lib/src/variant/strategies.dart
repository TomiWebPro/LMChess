/// Concrete interpretation strategies and the registry that runs them.
///
/// Twelve pure, bounded strategies, each modelling one "creative reading" of
/// an illegal move. Every strategy obeys the [Strategy] contract: pure
/// function of `(board, attempt)`, at most 3 candidates, empty list (never an
/// exception) when its preconditions fail, and deterministic ids via
/// [freshDerivedId] so repeated runs agree byte-for-byte.
///
/// ## Scope limits (apply to every strategy below)
///
/// * Each candidate performs **one** described transformation; strategies
///   never chain multiple readings together (no "teleport then duplicate").
/// * Ids: pieces that move keep their ids; genuinely new pieces get ids
///   derived as `<strategy>_<role>_<square>` (plus the board move number),
///   uniquified with [freshDerivedId].
/// * All resulting boards flip [VariantBoard.sideToMove] and increment
///   [VariantBoard.moveNumber] by one — the attempt consumes a turn even when
///   the mover's piece barely moved. Halfmove clocks reset on pawn
///   moves/captures (best-effort).
/// * Strategies never score; [UnscoredInterpretation.kingCaptureHint] is
///   advisory and recomputed by the engine.
/// * [InterpretationRegistry.generateAll] caps each strategy at 3 candidates,
///   deduplicates by [VariantBoard.boardHash] (first occurrence wins), and
///   sorts by `(strategyId, boardHash)` so ordering is deterministic.
library;

import '../chess/move.dart';
import '../chess/piece.dart';
import '../chess/position.dart';
import '../chess/square.dart';
import 'interpretation.dart';
import 'variant_board.dart';

// ---------------------------------------------------------------------------
// Shared private helpers.
// ---------------------------------------------------------------------------

/// Parsed attempt squares, or `null` when either name is malformed.
(Square, Square)? _squaresOf(AttemptedMove attempt) {
  final from = attempt.fromSquare;
  final to = attempt.toSquare;
  if (from == null || to == null) return null;
  return (from, to);
}

/// Builds the post-move board shell shared by most strategies: [squares] with
/// the turn flipped, the ply counter incremented, [notes] tagged, and the
/// halfmove clock maintained best-effort.
VariantBoard _shell(
  VariantBoard parent,
  Map<Square, VariantPiece> squares, {
  required String tag,
  required bool resetHalfmove,
}) =>
    VariantBoard(
      squares: squares,
      sideToMove: parent.sideToMove.opposite,
      moveNumber: parent.moveNumber + 1,
      halfmove: resetHalfmove ? 0 : parent.halfmove + 1,
      castlingInvalid: parent.castlingInvalid,
      notes: '${parent.notes}[$tag] ',
    );

/// Wraps a single resulting board into an [UnscoredInterpretation].
UnscoredInterpretation _one({
  required String strategyId,
  required String title,
  required String description,
  required VariantBoard board,
  bool kingCaptureHint = false,
}) =>
    UnscoredInterpretation(
      strategyId: strategyId,
      title: title,
      description: description,
      resultingBoard: board,
      kingCaptureHint: kingCaptureHint,
    );

/// Squares strictly between [from] and [to] along a rank, file or diagonal.
/// Empty when [from] and [to] are not aligned that way (knight-like geometry
/// has no "path", so path-based strategies abstain).
List<Square> _squaresBetween(Square from, Square to) {
  final df = to.file - from.file;
  final dr = to.rank - from.rank;
  if (df != 0 && dr != 0 && df.abs() != dr.abs()) return const [];
  final stepF = df == 0 ? 0 : df ~/ df.abs();
  final stepR = dr == 0 ? 0 : dr ~/ dr.abs();
  final out = <Square>[];
  var cur = from.offset(stepF, stepR);
  while (cur != null && cur != to) {
    out.add(cur);
    cur = cur.offset(stepF, stepR);
  }
  return out;
}

/// First occupied square on the path from [from] towards [to].
///
/// Returns the destination square itself when the path is clear but [to] is
/// occupied, or `null` when the whole path including [to] is empty.
Square? _firstBlocker(
    VariantBoard board, Square from, Square to) {
  for (final sq in _squaresBetween(from, to)) {
    if (board.pieceAt(sq) != null) return sq;
  }
  return board.pieceAt(to) != null ? to : null;
}

/// Nearest empty square to [near] (Chebyshev distance, square order
/// tie-break), excluding [exclude]. `null` when the board is completely full.
Square? _nearestEmpty(VariantBoard board, Square near,
    {Set<Square> exclude = const {}}) {
  Square? best;
  var bestDist = 1 << 30;
  for (final sq in allSquares()) {
    if (sq == near || exclude.contains(sq)) continue;
    if (board.pieceAt(sq) != null) continue;
    final d = chebyshevDistance(sq, near);
    if (d < bestDist || (d == bestDist && (best == null || sq.compareTo(best) < 0))) {
      best = sq;
      bestDist = d;
    }
  }
  return best;
}

/// Nearest piece of [color] to [near] (Chebyshev, square-order tie-break).
/// `null` when [color] has no pieces.
(Square, VariantPiece)? _nearestPieceOf(
    VariantBoard board, Square near, PieceColor color) {
  (Square, VariantPiece)? best;
  var bestDist = 1 << 30;
  final keys = board.squares.keys.toList()..sort();
  for (final sq in keys) {
    final p = board.squares[sq]!;
    if (p.color != color) continue;
    final d = chebyshevDistance(sq, near);
    if (d < bestDist) {
      best = (sq, p);
      bestDist = d;
    }
  }
  return best;
}

// ---------------------------------------------------------------------------
// 1. directTeleport
// ---------------------------------------------------------------------------

/// Teleports the piece from `from` to `to`, ignoring path obstruction.
///
/// Preconditions: a piece on `from`; destination empty or enemy-held (an
/// enemy occupant is captured, even a king — flagged via [kingCaptureHint]).
/// Abstains when the destination holds an *own* piece (see
/// [CaptureRegardlessStrategy]) or when `from == to`.
class DirectTeleportStrategy extends Strategy {
  /// Creates the strategy.
  const DirectTeleportStrategy();

  @override
  String get id => 'directTeleport';

  @override
  String get description =>
      'Teleport the mover to the destination, capturing enemies only. '
      'Abstains on own-piece destinations and when from == to.';

  @override
  List<UnscoredInterpretation> generate(
      VariantBoard board, AttemptedMove attempt) {
    final sq = _squaresOf(attempt);
    if (sq == null) return const [];
    final (from, to) = sq;
    if (from == to) return const [];
    final mover = board.pieceAt(from);
    if (mover == null) return const [];
    final dest = board.pieceAt(to);
    if (dest != null && dest.color == mover.color) return const [];
    final next = Map<Square, VariantPiece>.from(board.squares)
      ..remove(from)
      ..remove(to)
      ..[to] = mover;
    final tookKing =
        dest != null && dest.type == PieceType.king;
    return [
      _one(
        strategyId: id,
        title: 'Teleport strike',
        description: dest == null
            ? '${mover.type.name} teleports ${from.name} to empty ${to.name}.'
            : '${mover.type.name} teleports ${from.name} to ${to.name}, '
                'capturing ${dest.type.name}.',
        board: _shell(board, next,
            tag: '$id ${from.name}${to.name}',
            resetHalfmove:
                mover.type == PieceType.pawn || dest != null),
        kingCaptureHint: tookKing,
      ),
    ];
  }
}

// ---------------------------------------------------------------------------
// 2. captureRegardless
// ---------------------------------------------------------------------------

/// Moves `from` to `to`, capturing whatever sits there — even an own piece,
/// even a king.
///
/// Preconditions: a piece on `from` and any occupant on `to` (`from != to`).
/// Abstains on empty destinations (see [DirectTeleportStrategy]).
class CaptureRegardlessStrategy extends Strategy {
  /// Creates the strategy.
  const CaptureRegardlessStrategy();

  @override
  String get id => 'captureRegardless';

  @override
  String get description =>
      'Capture the destination occupant regardless of colour, even a king. '
      'Abstains on empty destinations.';

  @override
  List<UnscoredInterpretation> generate(
      VariantBoard board, AttemptedMove attempt) {
    final sq = _squaresOf(attempt);
    if (sq == null) return const [];
    final (from, to) = sq;
    if (from == to) return const [];
    final mover = board.pieceAt(from);
    final dest = board.pieceAt(to);
    if (mover == null || dest == null) return const [];
    final next = Map<Square, VariantPiece>.from(board.squares)
      ..remove(from)
      ..remove(to)
      ..[to] = mover;
    return [
      _one(
        strategyId: id,
        title: dest.color == mover.color
            ? 'Friendly fire'
            : 'Ruthless capture',
        description:
            '${mover.type.name} ${from.name} takes the ${dest.color.name} '
            '${dest.type.name} on ${to.name}, colour and royalty ignored.',
        board: _shell(board, next,
            tag: '$id ${from.name}${to.name}', resetHalfmove: true),
        kingCaptureHint: dest.type == PieceType.king,
      ),
    ];
  }
}

// ---------------------------------------------------------------------------
// 3. pushThroughBlocker
// ---------------------------------------------------------------------------

/// Completes the move by shoving the first path blocker onto the nearest
/// empty square, then moving `from` to `to`.
///
/// Preconditions: a piece on `from`; an aligned path with a first blocker
/// strictly between `from` and `to`; destination empty or enemy-held; at least
/// one empty square for the shoved piece. Single candidate.
class PushThroughBlockerStrategy extends Strategy {
  /// Creates the strategy.
  const PushThroughBlockerStrategy();

  @override
  String get id => 'pushThroughBlocker';

  @override
  String get description =>
      'Shove the first path blocker to the nearest empty square, then '
      'complete the move. Abstains on unaligned paths and full boards.';

  @override
  List<UnscoredInterpretation> generate(
      VariantBoard board, AttemptedMove attempt) {
    final sq = _squaresOf(attempt);
    if (sq == null) return const [];
    final (from, to) = sq;
    if (from == to) return const [];
    final mover = board.pieceAt(from);
    if (mover == null) return const [];
    final between = _squaresBetween(from, to);
    Square? blocker;
    for (final s in between) {
      if (board.pieceAt(s) != null) {
        blocker = s;
        break;
      }
    }
    if (blocker == null) return const []; // Nothing to push through.
    final dest = board.pieceAt(to);
    if (dest != null && dest.color == mover.color) return const [];
    final parking = _nearestEmpty(board, blocker, exclude: {from, to});
    if (parking == null) return const [];
    final shoved = board.pieceAt(blocker)!;
    final next = Map<Square, VariantPiece>.from(board.squares)
      ..remove(from)
      ..remove(blocker)
      ..remove(to)
      ..[parking] = shoved
      ..[to] = mover;
    return [
      _one(
        strategyId: id,
        title: 'Barge through',
        description:
            '${shoved.type.name} on ${blocker.name} is shoved to empty '
            '${parking.name}; ${mover.type.name} continues to ${to.name}.',
        board: _shell(board, next,
            tag: '$id ${from.name}${to.name}',
            resetHalfmove:
                mover.type == PieceType.pawn || dest != null),
        kingCaptureHint: dest?.type == PieceType.king,
      ),
    ];
  }
}

// ---------------------------------------------------------------------------
// 4. moveBlockerInstead
// ---------------------------------------------------------------------------

/// The blocking piece moves instead of the requested one: the first occupant
/// on the path (strictly between `from` and `to`) travels to `to`, capturing
/// whatever is there.
///
/// Preconditions: a strictly-between blocker exists. The mover's own piece
/// stays put. Single candidate.
class MoveBlockerInsteadStrategy extends Strategy {
  /// Creates the strategy.
  const MoveBlockerInsteadStrategy();

  @override
  String get id => 'moveBlockerInstead';

  @override
  String get description =>
      'Move the first path blocker to the destination instead of the '
      'requested piece. Abstains without a strictly-between blocker.';

  @override
  List<UnscoredInterpretation> generate(
      VariantBoard board, AttemptedMove attempt) {
    final sq = _squaresOf(attempt);
    if (sq == null) return const [];
    final (from, to) = sq;
    if (from == to) return const [];
    Square? blocker;
    for (final s in _squaresBetween(from, to)) {
      if (board.pieceAt(s) != null) {
        blocker = s;
        break;
      }
    }
    if (blocker == null) return const [];
    final intruder = board.pieceAt(blocker)!;
    final dest = board.pieceAt(to);
    final next = Map<Square, VariantPiece>.from(board.squares)
      ..remove(blocker)
      ..remove(to)
      ..[to] = intruder;
    return [
      _one(
        strategyId: id,
        title: 'Wrong piece moved',
        description:
            'The ${intruder.color.name} ${intruder.type.name} blocking on '
            '${blocker.name} moves to ${to.name} instead of the requested '
            'piece.',
        board: _shell(board, next,
            tag: '$id ${blocker.name}${to.name}', resetHalfmove: dest != null),
        kingCaptureHint: dest?.type == PieceType.king,
      ),
    ];
  }
}

// ---------------------------------------------------------------------------
// 5. moveOpponentPiece
// ---------------------------------------------------------------------------

/// Grabs the opponent's piece nearest to `from` and moves *it* to `to`,
/// capturing whatever is there.
///
/// Models the "played the wrong army" misreading. Preconditions: at least one
/// enemy piece exists. Single candidate; ties broken by square order.
class MoveOpponentPieceStrategy extends Strategy {
  /// Creates the strategy.
  const MoveOpponentPieceStrategy();

  @override
  String get id => 'moveOpponentPiece';

  @override
  String get description =>
      'Move the nearest enemy piece to the destination, capturing there. '
      'Abstains when the enemy has no pieces.';

  @override
  List<UnscoredInterpretation> generate(
      VariantBoard board, AttemptedMove attempt) {
    final sq = _squaresOf(attempt);
    if (sq == null) return const [];
    final (from, to) = sq;
    final enemy = board.sideToMove.opposite;
    final found = _nearestPieceOf(board, from, enemy);
    if (found == null) return const [];
    final (grabbedAt, piece) = found;
    if (grabbedAt == to) return const [];
    final dest = board.pieceAt(to);
    final next = Map<Square, VariantPiece>.from(board.squares)
      ..remove(grabbedAt)
      ..remove(to)
      ..[to] = piece;
    return [
      _one(
        strategyId: id,
        title: 'Enemy hijack',
        description:
            'The enemy ${piece.type.name} on ${grabbedAt.name} is marched '
            'to ${to.name}.',
        board: _shell(board, next,
            tag: '$id ${grabbedAt.name}${to.name}',
            resetHalfmove:
                piece.type == PieceType.pawn || dest != null),
        kingCaptureHint: dest?.type == PieceType.king,
      ),
    ];
  }
}

// ---------------------------------------------------------------------------
// 6. addPieceAtDestination
// ---------------------------------------------------------------------------

/// Conjures a new pawn of the mover's colour on an empty destination; the
/// requested piece stays where it is.
///
/// Preconditions: destination empty. The new id derives deterministically
/// (`add_m<moveNumber>_pawn_<square>`). Single candidate.
class AddPieceAtDestinationStrategy extends Strategy {
  /// Creates the strategy.
  const AddPieceAtDestinationStrategy();

  @override
  String get id => 'addPieceAtDestination';

  @override
  String get description =>
      'Conjure a new mover-coloured pawn on an empty destination; the '
      'requested piece stays. Abstains on occupied destinations.';

  @override
  List<UnscoredInterpretation> generate(
      VariantBoard board, AttemptedMove attempt) {
    final sq = _squaresOf(attempt);
    if (sq == null) return const [];
    final (_, to) = sq;
    if (board.pieceAt(to) != null) return const [];
    final next = Map<Square, VariantPiece>.from(board.squares);
    final idBase = 'add_m${board.moveNumber}_pawn_${to.name}';
    final fresh = VariantPiece(
      id: freshDerivedId(board, idBase),
      type: PieceType.pawn,
      color: board.sideToMove,
    );
    next[to] = fresh;
    return [
      _one(
        strategyId: id,
        title: 'Conjured pawn',
        description:
            'A new ${board.sideToMove.name} pawn materialises on ${to.name}; '
            'nothing else moves.',
        board: _shell(board, next,
            tag: '$id ${to.name}', resetHalfmove: true),
      ),
    ];
  }
}

// ---------------------------------------------------------------------------
// 7. duplicateMover
// ---------------------------------------------------------------------------

/// The piece stays on `from` *and* a copy appears on `to`, capturing an enemy
/// occupant there if present.
///
/// Preconditions: a piece on `from`; destination empty or enemy-held; `from
/// != to`. The copy keeps the mover's type/colour with a deterministic fresh
/// id. Single candidate.
class DuplicateMoverStrategy extends Strategy {
  /// Creates the strategy.
  const DuplicateMoverStrategy();

  @override
  String get id => 'duplicateMover';

  @override
  String get description =>
      'Duplicate the mover onto the destination (capturing enemies); the '
      'original stays. Abstains on own-piece destinations.';

  @override
  List<UnscoredInterpretation> generate(
      VariantBoard board, AttemptedMove attempt) {
    final sq = _squaresOf(attempt);
    if (sq == null) return const [];
    final (from, to) = sq;
    if (from == to) return const [];
    final mover = board.pieceAt(from);
    if (mover == null) return const [];
    final dest = board.pieceAt(to);
    if (dest != null && dest.color == mover.color) return const [];
    final next = Map<Square, VariantPiece>.from(board.squares)..remove(to);
    final idBase =
        'dup_m${board.moveNumber}_${mover.type.name}_${from.name}_${to.name}';
    next[to] = VariantPiece(
      id: freshDerivedId(board, idBase),
      type: mover.type,
      color: mover.color,
    );
    return [
      _one(
        strategyId: id,
        title: 'Mitotic move',
        description:
            '${mover.type.name} on ${from.name} splits, leaving a copy on '
            '${to.name}.',
        board: _shell(board, next,
            tag: '$id ${from.name}${to.name}', resetHalfmove: dest != null),
        kingCaptureHint: dest?.type == PieceType.king,
      ),
    ];
  }
}

// ---------------------------------------------------------------------------
// 8. removeBlocker
// ---------------------------------------------------------------------------

/// Vaporizes the first path blocker, then either completes the move
/// (candidate A) or leaves the mover in place (candidate B).
///
/// Preconditions: a blocker strictly between `from` and `to` (or on `to`
/// itself when adjacent/diagonal-adjacent with no between-squares). Up to 2
/// candidates.
class RemoveBlockerStrategy extends Strategy {
  /// Creates the strategy.
  const RemoveBlockerStrategy();

  @override
  String get id => 'removeBlocker';

  @override
  String get description =>
      'Vaporize the first path blocker; either complete the move or hold '
      'position. Up to 2 candidates.';

  @override
  List<UnscoredInterpretation> generate(
      VariantBoard board, AttemptedMove attempt) {
    final sq = _squaresOf(attempt);
    if (sq == null) return const [];
    final (from, to) = sq;
    if (from == to) return const [];
    final mover = board.pieceAt(from);
    if (mover == null) return const [];
    final blocker = _firstBlocker(board, from, to);
    if (blocker == null) return const [];
    final vaporized = board.pieceAt(blocker)!;
    final out = <UnscoredInterpretation>[];
    // Candidate A: remove the blocker and complete the move (destination must
    // then be empty or enemy-held — it is, since the only occupant was the
    // blocker itself when blocker == to).
    if (blocker == to ||
        board.pieceAt(to) == null ||
        board.pieceAt(to)!.color != mover.color) {
      final next = Map<Square, VariantPiece>.from(board.squares)
        ..remove(from)
        ..remove(blocker)
        ..remove(to)
        ..[to] = mover;
      out.add(_one(
        strategyId: id,
        title: 'Vaporize and advance',
        description:
            '${vaporized.type.name} on ${blocker.name} is vaporized and '
            '${mover.type.name} advances ${from.name} to ${to.name}.',
        board: _shell(board, next,
            tag: '$id ${from.name}${to.name}a', resetHalfmove: true),
        kingCaptureHint: vaporized.type == PieceType.king,
      ));
    }
    // Candidate B: remove the blocker; the mover holds position.
    {
      final next = Map<Square, VariantPiece>.from(board.squares)
        ..remove(blocker);
      out.add(_one(
        strategyId: id,
        title: 'Vaporize and hold',
        description:
            '${vaporized.type.name} on ${blocker.name} is vaporized; '
            '${mover.type.name} holds ${from.name}.',
        board: _shell(board, next,
            tag: '$id ${from.name}${to.name}b', resetHalfmove: true),
        kingCaptureHint: vaporized.type == PieceType.king,
      ));
    }
    return out;
  }
}

// ---------------------------------------------------------------------------
// 9. removeDestination
// ---------------------------------------------------------------------------

/// Vaporizes the destination occupant; the mover stays put.
///
/// Preconditions: destination occupied. Single candidate — the "no, that piece
/// is gone now" reading.
class RemoveDestinationStrategy extends Strategy {
  /// Creates the strategy.
  const RemoveDestinationStrategy();

  @override
  String get id => 'removeDestination';

  @override
  String get description =>
      'Vaporize the destination occupant; the mover holds. Abstains on '
      'empty destinations.';

  @override
  List<UnscoredInterpretation> generate(
      VariantBoard board, AttemptedMove attempt) {
    final sq = _squaresOf(attempt);
    if (sq == null) return const [];
    final (_, to) = sq;
    final dest = board.pieceAt(to);
    if (dest == null) return const [];
    final next = Map<Square, VariantPiece>.from(board.squares)..remove(to);
    return [
      _one(
        strategyId: id,
        title: 'Hexed square',
        description:
            '${dest.color.name} ${dest.type.name} on ${to.name} is vaporized '
            'from afar; nothing moves.',
        board: _shell(board, next,
            tag: '$id ${to.name}', resetHalfmove: true),
        kingCaptureHint: dest.type == PieceType.king,
      ),
    ];
  }
}

// ---------------------------------------------------------------------------
// 10. castleLikeDisplacement
// ---------------------------------------------------------------------------

/// King-and-rook displacement in the spirit of castling: when the requested
/// piece is an own king, the king goes to `to` while the nearest own rook
/// swings onto `from` (and symmetrically when the requested piece is an own
/// rook and an own king exists).
///
/// Preconditions: requester is an own king or rook with a living counterpart;
/// destination empty or enemy-held. Up to 2 candidates (king-led and
/// rook-led), fewer when roles coincide or are missing.
class CastleLikeDisplacementStrategy extends Strategy {
  /// Creates the strategy.
  const CastleLikeDisplacementStrategy();

  @override
  String get id => 'castleLikeDisplacement';

  @override
  String get description =>
      'King and nearest own rook swap roles castle-style around the '
      'requested move. Up to 2 candidates (king-led, rook-led).';

  @override
  List<UnscoredInterpretation> generate(
      VariantBoard board, AttemptedMove attempt) {
    final sq = _squaresOf(attempt);
    if (sq == null) return const [];
    final (from, to) = sq;
    if (from == to) return const [];
    final requester = board.pieceAt(from);
    if (requester == null || requester.color != board.sideToMove) {
      return const [];
    }
    final dest = board.pieceAt(to);
    if (dest != null && dest.color == board.sideToMove) return const [];
    final out = <UnscoredInterpretation>[];
    void kingLed(Square kingAt, Square rookAt) {
      final king = board.pieceAt(kingAt)!;
      final rook = board.pieceAt(rookAt)!;
      final next = Map<Square, VariantPiece>.from(board.squares)
        ..remove(kingAt)
        ..remove(rookAt)
        ..remove(to)
        ..[to] = king
        ..[from] = rook;
      out.add(_one(
        strategyId: id,
        title: 'Castle-like shuffle',
        description:
            '${king.color.name} king ${kingAt.name} to ${to.name} while the '
            'rook ${rookAt.name} swings to ${from.name}.',
        board: _shell(board, next,
            tag: '$id ${kingAt.name}${to.name}', resetHalfmove: dest != null),
        kingCaptureHint: dest?.type == PieceType.king,
      ));
    }
    // King-led: requester is the king; pair with the nearest own rook.
    if (requester.type == PieceType.king) {
      final rook = _nearestOwnRook(board, from, requester.color);
      if (rook != null && rook.$1 != to) kingLed(from, rook.$1);
    }
    // Rook-led: requester is a rook; pair with the nearest own king.
    if (requester.type == PieceType.rook) {
      final king = _nearestOwnKing(board, from, requester.color);
      if (king != null && king.$1 != to) {
        final kingPiece = king.$2;
        final next = Map<Square, VariantPiece>.from(board.squares)
          ..remove(king.$1)
          ..remove(from)
          ..remove(to)
          ..[to] = requester
          ..[from] = kingPiece;
        out.add(_one(
          strategyId: id,
          title: 'Rook-led shuffle',
          description:
              '${requester.color.name} rook ${from.name} to ${to.name} '
              'while the king ${king.$1.name} retreats to ${from.name}.',
          board: _shell(board, next,
              tag: '$id r${from.name}${to.name}',
              resetHalfmove: dest != null),
          kingCaptureHint: dest?.type == PieceType.king,
        ));
      }
    }
    return out;
  }

  /// Nearest own rook to [near] (excludes [near] itself implicitly by type).
  (Square, VariantPiece)? _nearestOwnRook(
      VariantBoard board, Square near, PieceColor color) {
    (Square, VariantPiece)? best;
    var bestDist = 1 << 30;
    final keys = board.squares.keys.toList()..sort();
    for (final s in keys) {
      final p = board.squares[s]!;
      if (p.color != color || p.type != PieceType.rook || s == near) continue;
      final d = chebyshevDistance(s, near);
      if (d < bestDist) {
        best = (s, p);
        bestDist = d;
      }
    }
    return best;
  }

  /// Nearest own king to [near].
  (Square, VariantPiece)? _nearestOwnKing(
      VariantBoard board, Square near, PieceColor color) {
    (Square, VariantPiece)? best;
    var bestDist = 1 << 30;
    final keys = board.squares.keys.toList()..sort();
    for (final s in keys) {
      final p = board.squares[s]!;
      if (p.color != color || p.type != PieceType.king || s == near) continue;
      final d = chebyshevDistance(s, near);
      if (d < bestDist) {
        best = (s, p);
        bestDist = d;
      }
    }
    return best;
  }
}

// ---------------------------------------------------------------------------
// 11. closestLegalMove
// ---------------------------------------------------------------------------

/// Replaces the attempt with the nearest legal move.
///
/// *Convertible boards* (see [VariantBoard.toStandardPosition]): enumerates
/// every legal move in the equivalent [Position], ranks by Chebyshev
/// displacement of origin plus destination against the attempt, and applies
/// the winner with id preservation ([applyStandardMove]).
/// *Non-convertible boards*: geometric fallback — the `from` piece slides to
/// the empty square nearest to `to` (mover keeps its id).
/// Single candidate; abstains when `from` is empty or nothing is reachable.
class ClosestLegalMoveStrategy extends Strategy {
  /// Creates the strategy.
  const ClosestLegalMoveStrategy();

  @override
  String get id => 'closestLegalMove';

  @override
  String get description =>
      'Apply the legal move nearest to the attempt; geometric nearest-empty '
      'fallback when the board is not convertible to standard.';

  @override
  List<UnscoredInterpretation> generate(
      VariantBoard board, AttemptedMove attempt) {
    final sq = _squaresOf(attempt);
    if (sq == null) return const [];
    final (from, to) = sq;
    final mover = board.pieceAt(from);
    if (mover == null) return const [];
    final pos = board.toStandardPosition();
    if (pos != null) {
      final legal = pos.legalMoves();
      if (legal.isEmpty) return const [];
      ChessMove? best;
      var bestCost = 1 << 30;
      for (final m in legal) {
        final cost = chebyshevDistance(m.from, from) * 2 +
            chebyshevDistance(m.to, to);
        if (best == null || cost < bestCost) {
          best = m;
          bestCost = cost;
        }
      }
      final chosen = best!;
      // The promotion override must inspect the piece that actually moves
      // ([chosen.from]), which need not be the attempted-from piece: the
      // nearest legal move can originate elsewhere entirely.
      final chosenMover = pos.pieceAt(chosen.from);
      final promo = attempt.promotionType;
      final applied = (chosenMover != null &&
              chosenMover.type == PieceType.pawn &&
              chosen.to.rank ==
                  (chosenMover.color.isWhite ? 7 : 0) &&
              promo != null &&
              isPromotionTarget(promo))
          ? ChessMove(chosen.from, chosen.to, promotion: promo)
          : chosen;
      return [
        _one(
          strategyId: id,
          title: 'Nearest legal move',
          description:
              'Attempt reinterpreted as legal ${applied.from.name} to '
              '${applied.to.name}'
              '${applied.promotion == null ? '' : ' promoting to ${applied.promotion!.name}'}.',
          board: applyStandardMove(board, applied),
        ),
      ];
    }
    // Geometric fallback for non-convertible boards.
    if (from == to) return const [];
    if (board.pieceAt(to) == null) {
      final next = Map<Square, VariantPiece>.from(board.squares)
        ..remove(from)
        ..[to] = mover;
      return [
        _one(
          strategyId: id,
          title: 'Nearest empty slide',
          description:
              'Board is not convertible; ${mover.type.name} slides '
              '${from.name} to empty ${to.name}.',
          board: _shell(board, next,
              tag: '$id ${from.name}${to.name}',
              resetHalfmove: mover.type == PieceType.pawn),
        ),
      ];
    }
    final landing = _nearestEmpty(board, to, exclude: {from});
    if (landing == null) return const [];
    final next = Map<Square, VariantPiece>.from(board.squares)
      ..remove(from)
      ..[landing] = mover;
    return [
      _one(
        strategyId: id,
        title: 'Nearest empty slide',
        description:
            'Board is not convertible; ${mover.type.name} slides '
            '${from.name} to ${landing.name}, nearest empty to ${to.name}.',
        board: _shell(board, next,
            tag: '$id ${from.name}${landing.name}',
            resetHalfmove: mover.type == PieceType.pawn),
      ),
    ];
  }
}

// ---------------------------------------------------------------------------
// 12. multiPieceRipple
// ---------------------------------------------------------------------------

/// The mover takes `to` and the occupant ripples to the nearest empty square
/// (a one-link displacement chain; both pieces keep their ids).
///
/// Preconditions: a piece on `from`, an occupant on `to`, `from != to`, and at
/// least one empty square for the ripple. Single candidate.
class MultiPieceRippleStrategy extends Strategy {
  /// Creates the strategy.
  const MultiPieceRippleStrategy();

  @override
  String get id => 'multiPieceRipple';

  @override
  String get description =>
      'Mover takes the destination; the occupant ripples to the nearest '
      'empty square. Abstains on empty destinations and full boards.';

  @override
  List<UnscoredInterpretation> generate(
      VariantBoard board, AttemptedMove attempt) {
    final sq = _squaresOf(attempt);
    if (sq == null) return const [];
    final (from, to) = sq;
    if (from == to) return const [];
    final mover = board.pieceAt(from);
    final occupant = board.pieceAt(to);
    if (mover == null || occupant == null) return const [];
    final ripple = _nearestEmpty(board, to, exclude: {from});
    if (ripple == null) return const [];
    final next = Map<Square, VariantPiece>.from(board.squares)
      ..remove(from)
      ..remove(to)
      ..[to] = mover
      ..[ripple] = occupant;
    return [
      _one(
        strategyId: id,
        title: 'Ripple displacement',
        description:
            '${mover.type.name} ${from.name} to ${to.name}; displaced '
            '${occupant.type.name} ripples to ${ripple.name}.',
        board: _shell(board, next,
            tag: '$id ${from.name}${to.name}',
            resetHalfmove:
                mover.type == PieceType.pawn ||
                    occupant.color != mover.color),
      ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Registry
// ---------------------------------------------------------------------------

/// Runs every known strategy over one attempt and merges the proposals.
///
/// [strategies] order is fixed and part of the determinism contract.
/// [generateAll] never throws: per-strategy errors are swallowed (a strategy
/// that crashes on an input simply contributes nothing), each strategy is
/// capped at 3 candidates, duplicates (by [VariantBoard.boardHash], first
/// occurrence wins) are dropped, and the survivors are sorted by
/// `(strategyId, boardHash)`.
class InterpretationRegistry {
  /// All strategies in fixed evaluation order.
  static List<Strategy> get strategies => const [
        DirectTeleportStrategy(),
        CaptureRegardlessStrategy(),
        PushThroughBlockerStrategy(),
        MoveBlockerInsteadStrategy(),
        MoveOpponentPieceStrategy(),
        AddPieceAtDestinationStrategy(),
        DuplicateMoverStrategy(),
        RemoveBlockerStrategy(),
        RemoveDestinationStrategy(),
        CastleLikeDisplacementStrategy(),
        ClosestLegalMoveStrategy(),
        MultiPieceRippleStrategy(),
      ];

  /// Generates, dedupes and deterministically orders all candidates.
  static List<UnscoredInterpretation> generateAll(
      VariantBoard board, AttemptedMove attempt) {
    // Fail fast on garbage input: no strategy can do anything sensible.
    if (!attempt.hasParsableSquares) return const [];
    final out = <UnscoredInterpretation>[];
    final seen = <String>{};
    for (final strategy in strategies) {
      List<UnscoredInterpretation> raws;
      try {
        raws = strategy.generate(board, attempt);
      } catch (_) {
        continue; // A crashing strategy contributes nothing.
      }
      var count = 0;
      for (final raw in raws) {
        if (count >= 3) break; // Per-strategy cap (defensive).
        if (raw.strategyId != strategy.id) continue; // Mislabeled output.
        final hash = raw.resultingBoard.boardHash();
        if (!seen.add(hash)) continue; // Duplicate layout.
        out.add(raw);
        count++;
      }
    }
    out.sort((a, b) {
      final c = a.strategyId.compareTo(b.strategyId);
      if (c != 0) return c;
      return a.resultingBoard.boardHash().compareTo(
            b.resultingBoard.boardHash(),
          );
    });
    return out;
  }
}
