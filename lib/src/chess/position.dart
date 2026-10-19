// Standard chess position + full move generation — pure Dart.
//
// Design decisions:
// - Board representation is `Map<Square, Piece>` (8x8 mailbox as a hash
//   map). This favors clarity over raw speed: no bitboards, no magic
//   numbers. Correctness of check evasion, pins and castling is far more
//   valuable here than nodes-per-second; `perft` in engine.dart exists to
//   regression-check the generator against known node counts.
// - [Position] is MUTABLE: [apply] mutates in place and returns an
//   [AppliedMove] receipt. Use [clone] before speculative play (search,
//   SAN probing, perft). [Piece]/[Square]/[ChessMove]/[AppliedMove] are
//   immutable, so cloning only copies the map/set/list structure.
// - Move generation is two-phase: (1) pseudo-legal generation per piece
//   (pawn pushes/captures incl. double push, en passant and all four
//   promotions; knight/king steps; slider rays; castling with rights,
//   occupancy and transit-square attack checks), then (2) a king-safety
//   filter that replays each candidate on a copied board and rejects
//   moves leaving the mover's king in check. This single filter handles
//   absolute pins, discovered checks, king moves into attack, and the
//   rare en-passant rank pin uniformly — no special cases.
// - Attack detection ([isSquareAttacked]) is independent of move
//   generation (direct geometric tests), so it stays correct even for
//   filtering simulated boards.
// - SAN text for an applied move is generated here (private [_sanBody])
//   because SAN needs both the pre-move position (disambiguation,
//   capture marks) and the post-move state (`+`/`#`). san.dart's public
//   [toSan] delegates to it via clone+apply so there is exactly one SAN
//   generator — no drift between modules.
// - This engine covers STANDARD chess only. No Chess960 (castling is
//   hardcoded to e-file kings on their home rank), no variant pieces.
//   Threefold/fivefold repetition counting belongs to the game
//   controller (use [Position.repetitionKey] per applied move —
//   [Position.history] stores SAN/capture receipts, not position keys),
//   as does fifty-move claiming; the automatic seventy-five-move draw
//   is detected via [Position.isSeventyFiveMove].

import 'move.dart';
import 'piece.dart';
import 'square.dart';

/// Mutable standard-chess position with full move generation.
///
/// Coordinate convention (see square.dart): a1 == (0, 0), White starts
/// on ranks 1-2 and moves "up" towards increasing rank indices.
///
/// Degenerate-position contract: this class tolerates (but never
/// generates from legal play) positions without kings — [kingSquare]
/// returns `null`, [isInCheck] reports `false`, and an empty board
/// therefore yields `isStalemate == true` with no legal moves.
/// [parseFen] (fen.dart) is the strict gate: it rejects FEN with a
/// wrong king count or pawns on ranks 1/8. Direct construction with
/// nonsense (negative clocks, impossible castling strings, stray
/// en-passant squares) is guarded only by asserts; callers needing
/// hard validation should round-trip through FEN.
class Position {
  /// Pieces by square. Only occupied squares are present.
  final Map<Square, Piece> board;

  /// Color to move.
  PieceColor sideToMove;

  /// Remaining castling rights, subset of `{'K', 'Q', 'k', 'q'}` in FEN
  /// meaning: `K`/`Q` White kingside/queenside, `k`/`q` Black
  /// kingside/queenside. Rights are only ever removed, never added.
  final Set<String> castling;

  /// En-passant target square (the square behind a pawn that just
  /// double-pushed), or `null` when there is none.
  Square? enPassant;

  /// Halfmove clock: plies since the last pawn move or capture. Used
  /// for the fifty-move rule ([isFiftyMove]).
  int halfmoveClock;

  /// Fullmove number, incremented after Black's move. Starts at 1.
  int fullmoveNumber;

  /// History of moves applied to this position, oldest first.
  final List<AppliedMove> history;

  /// Creates a position. The [board], [castling] and [history] inputs
  /// are defensively copied.
  ///
  /// Compatibility aliases (used by the variant controller when it
  /// converts variant boards back to standard positions):
  /// * [pieces] is an alias for [board]; at most one may be given.
  /// * [whiteKingside], [whiteQueenside], [blackKingside],
  ///   [blackQueenside] build the [castling] set when [castling] itself
  ///   is omitted; an explicit [castling] set takes precedence.
  ///
  /// Clock ranges ([halfmoveClock] >= 0, [fullmoveNumber] >= 1) are
  /// enforced by asserts; [parseFen] enforces them strictly with
  /// [FormatException] for external input.
  Position({
    Map<Square, Piece>? board,
    Map<Square, Piece>? pieces,
    this.sideToMove = PieceColor.white,
    Set<String>? castling,
    bool? whiteKingside,
    bool? whiteQueenside,
    bool? blackKingside,
    bool? blackQueenside,
    this.enPassant,
    this.halfmoveClock = 0,
    this.fullmoveNumber = 1,
    List<AppliedMove>? history,
  })  : assert(board == null || pieces == null,
            'Pass either board or pieces, not both.'),
        assert(halfmoveClock >= 0, 'halfmoveClock must be >= 0'),
        assert(fullmoveNumber >= 1, 'fullmoveNumber must be >= 1'),
        board = Map<Square, Piece>.of(
            board ?? pieces ?? const <Square, Piece>{}),
        castling = castling != null
            ? Set<String>.of(castling)
            : <String>{
                if (whiteKingside == true) 'K',
                if (whiteQueenside == true) 'Q',
                if (blackKingside == true) 'k',
                if (blackQueenside == true) 'q',
              },
        history =
            history != null ? List<AppliedMove>.of(history) : <AppliedMove>[];

  /// Creates the standard initial chess position.
  factory Position.initial() {
    const back = <PieceType>[
      PieceType.rook,
      PieceType.knight,
      PieceType.bishop,
      PieceType.queen,
      PieceType.king,
      PieceType.bishop,
      PieceType.knight,
      PieceType.rook,
    ];
    final board = <Square, Piece>{};
    for (var f = 0; f < 8; f++) {
      board[Square(f, 0)] = Piece(back[f], PieceColor.white);
      board[Square(f, 1)] = const Piece(PieceType.pawn, PieceColor.white);
      board[Square(f, 6)] = const Piece(PieceType.pawn, PieceColor.black);
      board[Square(f, 7)] = Piece(back[f], PieceColor.black);
    }
    return Position(
      board: board,
      sideToMove: PieceColor.white,
      castling: const {'K', 'Q', 'k', 'q'},
    );
  }

  /// Returns an independent copy. Pieces/squares are immutable and
  /// shared; the maps/sets/lists are fresh.
  ///
  /// Pass `includeHistory: false` to skip copying [history] — used by
  /// `perft` (engine.dart), where per-node history copies dominate cost
  /// and the receipts are never read.
  Position clone({bool includeHistory = true}) => Position(
        board: Map<Square, Piece>.of(board),
        sideToMove: sideToMove,
        castling: Set<String>.of(castling),
        enPassant: enPassant,
        halfmoveClock: halfmoveClock,
        fullmoveNumber: fullmoveNumber,
        history:
            includeHistory ? List<AppliedMove>.of(history) : <AppliedMove>[],
      );

  /// Returns the piece on [square], or `null` when empty.
  Piece? pieceAt(Square square) => board[square];

  /// Read-only view of the board pieces by square.
  ///
  /// Compat: the variant controller reads converted positions through
  /// this alias. The view is unmodifiable; mutate via [apply].
  Map<Square, Piece> get pieces => Map<Square, Piece>.unmodifiable(board);

  /// Whether White retains kingside castling rights (`'K'`).
  bool get whiteKingside => castling.contains('K');

  /// Whether White retains queenside castling rights (`'Q'`).
  bool get whiteQueenside => castling.contains('Q');

  /// Whether Black retains kingside castling rights (`'k'`).
  bool get blackKingside => castling.contains('k');

  /// Whether Black retains queenside castling rights (`'q'`).
  bool get blackQueenside => castling.contains('q');

  /// Returns the square of [color]'s king, or `null` in a degenerate
  /// position without one (treated as "not in check" everywhere).
  Square? kingSquare(PieceColor color) {
    for (final entry in board.entries) {
      if (entry.value.type == PieceType.king &&
          entry.value.color == color) {
        return entry.key;
      }
    }
    return null;
  }

  /// Whether [square] is attacked by any piece of color [by] in the
  /// current position.
  ///
  /// Tests pawn, knight, king and sliding attacks geometrically; it
  /// does not use move generation, so it is safe to call on simulated
  /// boards during legality filtering.
  bool isSquareAttacked(Square square, PieceColor by) =>
      _isAttacked(board, square, by);

  /// Whether [color]'s king is currently in check.
  ///
  /// Returns `false` when [color] has no king on the board.
  bool isInCheck(PieceColor color) {
    final king = kingSquare(color);
    if (king == null) return false;
    return _isAttacked(board, king, color.opposite);
  }

  /// Pseudo-legal moves for the side to move (optionally restricted to
  /// [forSquare]): piece movement rules plus castling rights/occupancy/
  /// transit checks, but WITHOUT the king-safety filter. Moves here may
  /// leave the mover in check. Useful for debugging; play only uses
  /// [legalMoves].
  List<ChessMove> pseudoLegalMoves({Square? forSquare}) =>
      _collectPseudo(forSquare);

  /// Fully legal moves for the side to move, optionally restricted to
  /// moves starting from [forSquare].
  ///
  /// Computed as pseudo-legal moves filtered by king safety: a move is
  /// legal only if the mover's king is not in check afterwards. Returns
  /// an empty list when [forSquare] is empty or holds an enemy piece.
  List<ChessMove> legalMoves({Square? forSquare}) {
    final result = <ChessMove>[];
    for (final move in _collectPseudo(forSquare)) {
      if (!_leavesKingInCheck(move)) result.add(move);
    }
    return result;
  }

  /// Whether [move] is legal for the side to move.
  bool isLegal(ChessMove move) {
    final piece = board[move.from];
    if (piece == null || piece.color != sideToMove) return false;
    return legalMoves(forSquare: move.from).contains(move);
  }

  /// Whether moving the side-to-move piece from [from] to [to] (with an
  /// optional [promotion]) is legal.
  ///
  /// Convenience over [isLegal] for callers (such as the variant
  /// controller) that work with squares rather than [ChessMove] objects.
  bool isLegalMove(Square from, Square to, {PieceType? promotion}) =>
      isLegal(ChessMove(from, to, promotion: promotion));

  /// Plays the move from [from] to [to] (with an optional [promotion])
  /// on a CLONE of this position and describes what happened.
  ///
  /// This position is not modified; the result carries the post-move
  /// [PositionApplyResult.position] plus the transit squares (including
  /// the rook's, on castling) so controllers can preserve piece identity
  /// and animate rook movement. Throws a [StateError] when the move is
  /// illegal — guard with [isLegalMove] when moves come from outside.
  PositionApplyResult applyMoveResult(Square from, Square to,
      {PieceType? promotion}) {
    final move = ChessMove(from, to, promotion: promotion);
    final next = clone();
    final applied = next.apply(move); // Throws StateError if illegal.
    Square? rookFrom;
    Square? rookTo;
    if (applied.flag.isCastle) {
      final home = from.rank;
      if (applied.flag == MoveFlag.castleKingside) {
        rookFrom = Square(7, home);
        rookTo = Square(5, home);
      } else {
        rookFrom = Square(0, home);
        rookTo = Square(3, home);
      }
    }
    return PositionApplyResult(
      move: move,
      applied: applied,
      rookFrom: rookFrom,
      rookTo: rookTo,
      position: next,
    );
  }

  /// True when the side to move is in check with no legal reply.
  bool get isCheckmate =>
      isInCheck(sideToMove) && legalMoves().isEmpty;

  /// True when the side to move is not in check but has no legal move.
  bool get isStalemate =>
      !isInCheck(sideToMove) && legalMoves().isEmpty;

  /// True when neither side can possibly checkmate with the remaining
  /// material: bare kings, king + single minor vs bare king, or
  /// king+bishop vs king+bishop with both bishops on the same square
  /// color.
  ///
  /// Positions like KNN vs K (mate possible but not forceable) return
  /// `false` here; declaring those draws is the game controller's job.
  bool get isInsufficientMaterial {
    final minors = <MapEntry<Square, Piece>>[];
    for (final entry in board.entries) {
      switch (entry.value.type) {
        case PieceType.pawn:
        case PieceType.rook:
        case PieceType.queen:
          return false;
        case PieceType.king:
          break;
        case PieceType.knight:
        case PieceType.bishop:
          minors.add(entry);
      }
    }
    if (minors.length <= 1) return true; // K vs K, or K+minor vs K.
    if (minors.length == 2) {
      final a = minors[0];
      final b = minors[1];
      if (a.value.type == PieceType.bishop &&
          b.value.type == PieceType.bishop &&
          a.value.color != b.value.color &&
          a.key.colorIsLight == b.key.colorIsLight) {
        return true; // KB vs KB, bishops on the same color.
      }
    }
    return false;
  }

  /// True once 100 halfmoves (50 full moves by each side) have passed
  /// without a pawn move or capture.
  ///
  /// FIDE nuance (simplified here): fifty moves is *claimable* on
  /// request; seventy-five moves ([isSeventyFiveMove]) ends the game
  /// automatically. [ChessRules.resultOf] (engine.dart) reports both as
  /// a terminal [GameTermination.fiftyMove] draw — collapsing them keeps
  /// every external `switch` over [GameTermination] compiling.
  bool get isFiftyMove => halfmoveClock >= 100;

  /// True once 150 halfmoves (75 full moves) have passed without a pawn
  /// move or capture — an automatic-draw trigger under FIDE Laws
  /// (Article 9.6.2), no claim needed. See [isFiftyMove] for the
  /// claimable-vs-automatic distinction.
  bool get isSeventyFiveMove => halfmoveClock >= 150;

  /// Canonical key identifying this position for repetition tracking.
  ///
  /// Covers board layout + side to move + castling rights + en-passant
  /// square (halfmove/fullmove clocks excluded, per FIDE: repetitions
  /// compare positions, not move counters). The game controller owns
  /// threefold/fivefold counting — `history` stores [AppliedMove]
  /// receipts (SAN/capture data), not position keys, so it cannot serve
  /// this purpose; record `repetitionKey` after every applied move
  /// instead. Threefold is claimable, fivefold automatic (both draws).
  String get repetitionKey {
    // Canonical KQkq order; '-' when no rights remain.
    const order = ['K', 'Q', 'k', 'q'];
    final rights = order.where(castling.contains).join();
    final buf = StringBuffer(sideToMove.isWhite ? 'w' : 'b');
    buf.write(' ');
    buf.write(rights.isEmpty ? '-' : rights);
    buf.write(' ');
    buf.write(enPassant?.name ?? '-');
    buf.write(' ');
    final squares = board.keys.toList()..sort();
    for (final sq in squares) {
      final piece = board[sq]!;
      buf.write(sq.name);
      buf.write(piece.fenChar);
    }
    return buf.toString();
  }

  /// Plays [move] on this position, mutating it in place.
  ///
  /// Validates legality first and throws a [StateError] without
  /// mutating anything when [move] is not legal for the side to move.
  /// On success updates castling rights, the en-passant square, both
  /// clocks, the side to move and [history], and returns the
  /// [AppliedMove] receipt (including SAN).
  AppliedMove apply(ChessMove move) {
    final legal = legalMoves();
    if (!legal.contains(move)) {
      throw StateError(
          'Illegal move ${move.uci} for ${sideToMove.displayName}');
    }
    final moving = board[move.from]!;

    // Classify before mutating.
    Piece? captured;
    var flag = MoveFlag.normal;
    final fileDelta = move.to.file - move.from.file;
    final isCastleKingside =
        moving.type == PieceType.king && fileDelta == 2;
    final isCastleQueenside =
        moving.type == PieceType.king && fileDelta == -2;
    if (isCastleKingside) {
      flag = MoveFlag.castleKingside;
    } else if (isCastleQueenside) {
      flag = MoveFlag.castleQueenside;
    } else if (moving.type == PieceType.pawn &&
        move.to == enPassant &&
        board[move.to] == null) {
      captured = board[Square(move.to.file, move.from.rank)];
      flag = MoveFlag.enPassant;
    } else if (move.promotion != null) {
      captured = board[move.to];
      flag = MoveFlag.promotion;
    } else if (board[move.to] != null) {
      captured = board[move.to];
      flag = MoveFlag.capture;
    } else if (moving.type == PieceType.pawn &&
        (move.to.rank - move.from.rank).abs() == 2) {
      flag = MoveFlag.doublePush;
    }

    // SAN body needs the pre-move position (disambiguation, captures).
    final body = _sanBody(move, legal, captured != null);

    // Move the piece (promoting, and removing the en-passant victim).
    board.remove(move.from);
    if (flag == MoveFlag.enPassant) {
      board.remove(Square(move.to.file, move.from.rank));
    }
    board[move.to] = move.promotion != null
        ? Piece(move.promotion!, moving.color)
        : moving;
    // Relocate the rook on castling.
    if (isCastleKingside || isCastleQueenside) {
      final home = move.from.rank;
      final rookFrom =
          Square(isCastleKingside ? 7 : 0, home);
      final rookTo = Square(isCastleKingside ? 5 : 3, home);
      final rook = board.remove(rookFrom);
      if (rook != null) board[rookTo] = rook;
    }

    _revokeRights(move.from, move.to, moving);
    enPassant = flag == MoveFlag.doublePush
        ? Square(move.from.file, move.from.rank + moving.color.pawnStep)
        : null;
    if (moving.type == PieceType.pawn || captured != null) {
      halfmoveClock = 0;
    } else {
      halfmoveClock++;
    }
    if (sideToMove == PieceColor.black) fullmoveNumber++;
    sideToMove = sideToMove.opposite;

    // Exactly ONE post-move generation: `legal` (pre-move) cannot serve
    // here since the side to move, board, rights and EP square all
    // changed. `givesCheck` is a cheap geometric test; only the reply
    // check needs the fresh move list.
    final givesCheck = isInCheck(sideToMove);
    final hasReply = legalMoves().isNotEmpty;
    final mate = givesCheck && !hasReply;
    final stale = !givesCheck && !hasReply;
    final san = mate ? '$body#' : (givesCheck ? '$body+' : body);

    final applied = AppliedMove(
      move: move,
      flag: flag,
      captured: captured,
      isCheck: givesCheck,
      isCheckmate: mate,
      isStalemate: stale,
      san: san,
    );
    history.add(applied);
    return applied;
  }

  /// Simple ASCII rendering for debugging (White pieces uppercase).
  String toAscii() {
    final buf = StringBuffer();
    for (var r = 7; r >= 0; r--) {
      buf.write('${r + 1} ');
      for (var f = 0; f < 8; f++) {
        final piece = board[Square(f, r)];
        buf.write(piece == null ? '. ' : '${piece.fenChar} ');
      }
      buf.writeln();
    }
    buf.writeln('  a b c d e f g h');
    buf.write('${sideToMove.displayName} to move');
    return buf.toString();
  }

  // -----------------------------------------------------------------
  // Move generation internals.
  // -----------------------------------------------------------------

  static const List<(int, int)> _knightDeltas = [
    (1, 2), (2, 1), (2, -1), (1, -2),
    (-1, -2), (-2, -1), (-2, 1), (-1, 2),
  ];

  static const List<(int, int)> _kingDeltas = [
    (1, 0), (1, 1), (0, 1), (-1, 1),
    (-1, 0), (-1, -1), (0, -1), (1, -1),
  ];

  static const List<(int, int)> _diagonalDeltas = [
    (1, 1), (1, -1), (-1, 1), (-1, -1),
  ];

  static const List<(int, int)> _orthogonalDeltas = [
    (1, 0), (-1, 0), (0, 1), (0, -1),
  ];

  static const List<(int, int)> _queenDeltas = [
    (1, 0), (-1, 0), (0, 1), (0, -1),
    (1, 1), (1, -1), (-1, 1), (-1, -1),
  ];

  /// Pseudo-legal moves, optionally restricted to [forSquare].
  List<ChessMove> _collectPseudo(Square? forSquare) {
    final result = <ChessMove>[];
    if (forSquare != null) {
      final piece = board[forSquare];
      if (piece == null || piece.color != sideToMove) return result;
      result.addAll(_pseudoFor(forSquare, piece));
      if (piece.type == PieceType.king) result.addAll(_castlingMoves());
      return result;
    }
    var castleAdded = false;
    for (final entry in board.entries) {
      if (entry.value.color != sideToMove) continue;
      result.addAll(_pseudoFor(entry.key, entry.value));
      if (entry.value.type == PieceType.king && !castleAdded) {
        result.addAll(_castlingMoves());
        castleAdded = true;
      }
    }
    return result;
  }

  /// Pseudo-legal moves for the piece on [from] (never includes
  /// castling; captures of the enemy king are excluded since a position
  /// where the king hangs is unreachable from legal play).
  List<ChessMove> _pseudoFor(Square from, Piece piece) {
    switch (piece.type) {
      case PieceType.pawn:
        return _pawnMoves(from, piece);
      case PieceType.knight:
        return _stepMoves(from, piece, _knightDeltas);
      case PieceType.king:
        return _stepMoves(from, piece, _kingDeltas);
      case PieceType.bishop:
        return _rayMoves(from, piece, _diagonalDeltas);
      case PieceType.rook:
        return _rayMoves(from, piece, _orthogonalDeltas);
      case PieceType.queen:
        return _rayMoves(from, piece, _queenDeltas);
    }
  }

  List<ChessMove> _stepMoves(
      Square from, Piece piece, List<(int, int)> deltas) {
    final moves = <ChessMove>[];
    for (final d in deltas) {
      final target = from.offset(d.$1, d.$2);
      if (target == null) continue;
      final occupant = board[target];
      if (occupant == null) {
        moves.add(ChessMove(from, target));
      } else if (occupant.color != piece.color &&
          occupant.type != PieceType.king) {
        moves.add(ChessMove(from, target));
      }
    }
    return moves;
  }

  List<ChessMove> _rayMoves(
      Square from, Piece piece, List<(int, int)> deltas) {
    final moves = <ChessMove>[];
    for (final d in deltas) {
      var target = from.offset(d.$1, d.$2);
      while (target != null) {
        final occupant = board[target];
        if (occupant == null) {
          moves.add(ChessMove(from, target));
        } else {
          if (occupant.color != piece.color &&
              occupant.type != PieceType.king) {
            moves.add(ChessMove(from, target));
          }
          break;
        }
        target = target.offset(d.$1, d.$2);
      }
    }
    return moves;
  }

  List<ChessMove> _pawnMoves(Square from, Piece piece) {
    final moves = <ChessMove>[];
    final step = piece.color.pawnStep;
    final oneRank = from.rank + step;
    if (oneRank < 0 || oneRank > 7) return moves;
    final one = Square(from.file, oneRank);
    if (board[one] == null) {
      if (oneRank == piece.color.promotionRank) {
        for (final promo in PieceTypeX.promotionChoices) {
          moves.add(ChessMove(from, one, promotion: promo));
        }
      } else {
        moves.add(ChessMove(from, one));
        if (from.rank == piece.color.pawnStartRank) {
          final two = Square(from.file, from.rank + 2 * step);
          if (board[two] == null) moves.add(ChessMove(from, two));
        }
      }
    }
    for (final df in <int>[-1, 1]) {
      final f = from.file + df;
      if (f < 0 || f > 7) continue;
      final target = Square(f, oneRank);
      final occupant = board[target];
      if (occupant != null &&
          occupant.color != piece.color &&
          occupant.type != PieceType.king) {
        if (oneRank == piece.color.promotionRank) {
          for (final promo in PieceTypeX.promotionChoices) {
            moves.add(ChessMove(from, target, promotion: promo));
          }
        } else {
          moves.add(ChessMove(from, target));
        }
      } else if (occupant == null &&
          target == enPassant &&
          from.rank == piece.color.enPassantCaptureRank) {
        // Sanity-check the pushed pawn is really beside us; guards
        // against stale/hand-built en-passant squares.
        final pushed = board[Square(f, from.rank)];
        if (pushed != null &&
            pushed.type == PieceType.pawn &&
            pushed.color == piece.color.opposite) {
          moves.add(ChessMove(from, target));
        }
      }
    }
    return moves;
  }

  /// Castling options for the side to move (standard chess only: king
  /// starts on the e-file of its home rank).
  ///
  /// Enforces rights, king/rook presence, empty squares between them,
  /// and that the king is not in check and does not pass through an
  /// attacked square. Final king safety is additionally covered by the
  /// generic legality filter.
  List<ChessMove> _castlingMoves() {
    final moves = <ChessMove>[];
    final us = sideToMove;
    final foe = us.opposite;
    final home = us.backRank;
    final kingFrom = Square(4, home);
    final king = board[kingFrom];
    if (king == null ||
        king.type != PieceType.king ||
        king.color != us) {
      return moves;
    }
    if (_isAttacked(board, kingFrom, foe)) return moves;
    final kingside = us.isWhite ? 'K' : 'k';
    final queenside = us.isWhite ? 'Q' : 'q';
    if (castling.contains(kingside)) {
      final f = Square(5, home);
      final g = Square(6, home);
      final rook = board[Square(7, home)];
      if (board[f] == null &&
          board[g] == null &&
          rook != null &&
          rook.type == PieceType.rook &&
          rook.color == us &&
          !_isAttacked(board, f, foe) &&
          !_isAttacked(board, g, foe)) {
        moves.add(ChessMove(kingFrom, g));
      }
    }
    if (castling.contains(queenside)) {
      final d = Square(3, home);
      final c = Square(2, home);
      final b = Square(1, home);
      final rook = board[Square(0, home)];
      // FIDE 3.8.2.2.1: *every* square between king and rook must be
      // empty, so queenside castling needs b, c and d clear (the king
      // only steps over d and c, but the rook also passes b).
      if (board[d] == null &&
          board[c] == null &&
          board[b] == null &&
          rook != null &&
          rook.type == PieceType.rook &&
          rook.color == us &&
          !_isAttacked(board, d, foe) &&
          !_isAttacked(board, c, foe)) {
        moves.add(ChessMove(kingFrom, c));
      }
    }
    return moves;
  }

  /// Whether [move] (assumed pseudo-legal) would leave the mover's king
  /// in check. Replays the move — including en-passant victim removal
  /// and rook relocation — on a copied board, so pins, discovered
  /// checks and the en-passant rank pin are all handled uniformly.
  bool _leavesKingInCheck(ChessMove move) {
    final moving = board[move.from];
    if (moving == null) return true;
    final sim = Map<Square, Piece>.of(board);
    sim.remove(move.from);
    if (moving.type == PieceType.pawn &&
        move.to == enPassant &&
        board[move.to] == null) {
      sim.remove(Square(move.to.file, move.from.rank));
    }
    sim[move.to] = move.promotion != null
        ? Piece(move.promotion!, moving.color)
        : moving;
    if (moving.type == PieceType.king &&
        (move.to.file - move.from.file).abs() == 2) {
      final home = move.from.rank;
      if (move.to.file == 6) {
        final rook = sim.remove(Square(7, home));
        if (rook != null) sim[Square(5, home)] = rook;
      } else if (move.to.file == 2) {
        final rook = sim.remove(Square(0, home));
        if (rook != null) sim[Square(3, home)] = rook;
      }
    }
    final Square? kingSq;
    if (moving.type == PieceType.king) {
      kingSq = move.to;
    } else {
      kingSq = _kingOn(sim, moving.color);
    }
    if (kingSq == null) return false;
    return _isAttacked(sim, kingSq, moving.color.opposite);
  }

  /// Geometric attack test on an arbitrary [board] mapping.
  static bool _isAttacked(
      Map<Square, Piece> board, Square square, PieceColor by) {
    // Pawns: an attacker sits one step *behind* the target square from
    // its own perspective, i.e. at rank - pawnStep.
    final pawnRank = square.rank - by.pawnStep;
    if (pawnRank >= 0 && pawnRank <= 7) {
      for (final df in <int>[-1, 1]) {
        final f = square.file + df;
        if (f < 0 || f > 7) continue;
        final p = board[Square(f, pawnRank)];
        if (p != null && p.color == by && p.type == PieceType.pawn) {
          return true;
        }
      }
    }
    // Knights.
    for (final d in _knightDeltas) {
      final t = square.offset(d.$1, d.$2);
      if (t == null) continue;
      final p = board[t];
      if (p != null && p.color == by && p.type == PieceType.knight) {
        return true;
      }
    }
    // King.
    for (final d in _kingDeltas) {
      final t = square.offset(d.$1, d.$2);
      if (t == null) continue;
      final p = board[t];
      if (p != null && p.color == by && p.type == PieceType.king) {
        return true;
      }
    }
    // Sliders: walk each ray; the first piece decides.
    for (final d in _diagonalDeltas) {
      var t = square.offset(d.$1, d.$2);
      while (t != null) {
        final p = board[t];
        if (p != null) {
          if (p.color == by &&
              (p.type == PieceType.bishop || p.type == PieceType.queen)) {
            return true;
          }
          break;
        }
        t = t.offset(d.$1, d.$2);
      }
    }
    for (final d in _orthogonalDeltas) {
      var t = square.offset(d.$1, d.$2);
      while (t != null) {
        final p = board[t];
        if (p != null) {
          if (p.color == by &&
              (p.type == PieceType.rook || p.type == PieceType.queen)) {
            return true;
          }
          break;
        }
        t = t.offset(d.$1, d.$2);
      }
    }
    return false;
  }

  /// King lookup on an arbitrary board mapping.
  static Square? _kingOn(Map<Square, Piece> board, PieceColor color) {
    for (final entry in board.entries) {
      if (entry.value.type == PieceType.king &&
          entry.value.color == color) {
        return entry.key;
      }
    }
    return null;
  }

  /// Removes castling rights invalidated by a move from [from] to [to].
  ///
  /// A king move forfeits both rights of its color; any move starting
  /// from, or capture landing on, an original rook corner forfeits the
  /// matching right. Set removal is idempotent for already-lost rights.
  void _revokeRights(Square from, Square to, Piece moving) {
    if (moving.type == PieceType.king) {
      if (moving.color.isWhite) {
        castling.remove('K');
        castling.remove('Q');
      } else {
        castling.remove('k');
        castling.remove('q');
      }
    }
    for (final sq in <Square>[from, to]) {
      if (sq == const Square(0, 0)) {
        castling.remove('Q');
      } else if (sq == const Square(7, 0)) {
        castling.remove('K');
      } else if (sq == const Square(0, 7)) {
        castling.remove('q');
      } else if (sq == const Square(7, 7)) {
        castling.remove('k');
      }
    }
  }

  /// SAN body (without `+`/`#`) for [move] in the current (pre-move)
  /// position. [legal] is the full legal move list for disambiguation;
  /// [isCapture] is passed in to avoid recomputation.
  String _sanBody(ChessMove move, List<ChessMove> legal, bool isCapture) {
    final moving = board[move.from]!;
    final fileDelta = move.to.file - move.from.file;
    if (moving.type == PieceType.king && fileDelta.abs() == 2) {
      return fileDelta == 2 ? 'O-O' : 'O-O-O';
    }
    final buf = StringBuffer();
    if (moving.type == PieceType.pawn) {
      if (isCapture) {
        buf.write(move.from.fileName);
        buf.write('x');
      }
      buf.write(move.to.name);
      if (move.promotion != null) {
        buf.write('=');
        buf.write(move.promotion!.letter);
      }
      return buf.toString();
    }
    buf.write(moving.type.letter);
    final others = legal
        .where((m) =>
            m.from != move.from &&
            m.to == move.to &&
            board[m.from]?.type == moving.type &&
            board[m.from]?.color == moving.color)
        .toList();
    if (others.isNotEmpty) {
      final sameFile =
          others.any((m) => m.from.file == move.from.file);
      final sameRank =
          others.any((m) => m.from.rank == move.from.rank);
      if (!sameFile) {
        buf.write(move.from.fileName);
      } else if (!sameRank) {
        buf.write(move.from.rankName);
      } else {
        buf.write(move.from.name);
      }
    }
    if (isCapture) buf.write('x');
    buf.write(move.to.name);
    return buf.toString();
  }
}

/// Result of [Position.applyMoveResult]: a move played on a cloned
/// position, with everything a game controller needs to mirror it.
///
/// [position] is the post-move position (a fresh clone owned by this
/// result). The mover transit is [movedFrom]→[movedTo]; on castling,
/// [rookFrom]→[rookTo] locates the rook's transit so callers can
/// preserve piece identity (variant piece ids) or animate it.
class PositionApplyResult {
  /// The move that was played.
  final ChessMove move;

  /// The engine receipt for the move (SAN, capture, check/mate state).
  final AppliedMove applied;

  /// Rook origin on castling, `null` otherwise.
  final Square? rookFrom;

  /// Rook destination on castling, `null` otherwise.
  final Square? rookTo;

  /// The position after the move.
  final Position position;

  /// Creates a result. At most the castling fields are null together:
  /// either both are set (castling) or both are null.
  const PositionApplyResult({
    required this.move,
    required this.applied,
    required this.rookFrom,
    required this.rookTo,
    required this.position,
  }) : assert((rookFrom == null) == (rookTo == null),
            'rookFrom and rookTo must be set together');

  /// Origin square of the moving piece.
  Square get movedFrom => move.from;

  /// Destination square of the moving piece.
  Square get movedTo => move.to;

  /// True when the move was castling.
  bool get isCastle => applied.flag.isCastle;

  @override
  String toString() => 'PositionApplyResult(${applied.san})';
}
