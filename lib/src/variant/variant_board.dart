/// Chaotic-variant board model: identity-preserving pieces on a map of squares.
///
/// A [VariantBoard] is the core state object of the illegal-move variant. It
/// differs from a standard [Position] in one decisive way: every piece carries
/// a stable [VariantPiece.id], and the board explicitly permits states that
/// standard chess forbids (zero or several kings per side, up to 64 pieces,
/// pawns anywhere).
///
/// This library builds on the shared chess primitives in `lib/src/chess`
/// ([PieceType], [PieceColor], [Piece], [Square], [Position], [ChessMove]) and
/// adds variant-level helpers where those primitives are intentionally minimal:
/// [tryParseSquare], [parsePieceType], [parsePieceColor], and the geometry
/// helpers [allSquares], [squareNeighbors], [chebyshevDistance].
///
/// ## Invariants (enforced by construction, re-validated by the engine)
///
/// * **At most one piece per square.** The board is a `Map<Square,
///   VariantPiece>`, so double occupancy is unrepresentable.
/// * **Stable ids.** A piece keeps its id when it moves, is shifted, or
///   promotes. [clone] preserves ids. Genuinely *new* pieces (conjured or
///   duplicated) receive fresh ids via [freshDerivedId], which derives them
///   deterministically from the board state so pipelines stay reproducible.
/// * **0..n kings allowed.** Any number of kings per side is representable.
///   King capture is *not* tracked on the board itself; it is detected
///   externally by diffing king presence before/after an interpretation
///   (see `ChaoticRules.isKingCaptured` / `gameOver`).
/// * **Boards are effectively immutable.** [squares] is an unmodifiable map;
///   every transformation builds a new [VariantBoard].
///
/// ## Why serialization is custom JSON and NOT FEN
///
/// FEN assumes a legal-ish standard position: exactly one king per side, at
/// most 8 pawns per side, no pawns on the first/eighth rank, no piece
/// identity, and no room for annotations. Chaotic boards routinely violate all
/// of these, and FEN would silently discard piece ids, [notes], and
/// [castlingInvalid]. [toJson]/[VariantBoard.fromJson] therefore serialize the
/// full state. [canRepresentAsFen]/[tryToFen] exist only as a best-effort
/// bridge for convertible positions (export, debugging, standard legality
/// checks) and return `null` — never a misleading FEN — otherwise. The FEN
/// string itself is rendered locally (not via `chess/fen.dart`) so the variant
/// stays independent of that module's evolution.
library;

import 'dart:math';

import '../chess/move.dart';
import '../chess/piece.dart';
import '../chess/position.dart';
import '../chess/square.dart';

// ---------------------------------------------------------------------------
// Variant-level parsing helpers (accept full names as well as SAN letters).
// ---------------------------------------------------------------------------

/// Parses an algebraic square name (`e4`, case-insensitive, trimmed).
///
/// Returns `null` for malformed input instead of throwing, so attempt
/// recording and strategy preconditions can validate cheaply. (The shared
/// [Square.fromName] throws; this is its non-throwing counterpart.)
Square? tryParseSquare(String? raw) {
  if (raw == null) return null;
  final v = raw.trim().toLowerCase();
  if (v.length != 2) return null;
  try {
    return Square.fromName(v);
  } on FormatException {
    return null;
  }
}

/// Parses a piece type from a full name (`knight`), a SAN letter (`N`), or a
/// FEN letter (case-insensitive, colour ignored).
///
/// Returns `null` when [raw] is `null` or unrecognized.
PieceType? parsePieceType(String? raw) {
  if (raw == null) return null;
  final v = raw.trim().toLowerCase();
  if (v.length == 1) return PieceTypeX.fromLetter(v);
  return switch (v) {
    'pawn' => PieceType.pawn,
    'knight' => PieceType.knight,
    'bishop' => PieceType.bishop,
    'rook' => PieceType.rook,
    'queen' => PieceType.queen,
    'king' => PieceType.king,
    _ => null,
  };
}

/// Parses a colour from a `w`/`b` code or full name (case-insensitive).
///
/// Returns `null` when [raw] is `null` or unrecognized.
PieceColor? parsePieceColor(String? raw) {
  if (raw == null) return null;
  return switch (raw.trim().toLowerCase()) {
    'w' || 'white' => PieceColor.white,
    'b' || 'black' => PieceColor.black,
    _ => null,
  };
}

/// `true` for knight, bishop, rook and queen — the legal promotion targets
/// (a pawn may never promote to pawn or king).
bool isPromotionTarget(PieceType type) =>
    type == PieceType.knight ||
    type == PieceType.bishop ||
    type == PieceType.rook ||
    type == PieceType.queen;

/// Single-letter code for a colour in JSON/FEN contexts (`w` / `b`).
String colorCode(PieceColor color) => color.isWhite ? 'w' : 'b';

// ---------------------------------------------------------------------------
// Geometry helpers supplementing the minimal shared [Square] API.
// ---------------------------------------------------------------------------

/// All 64 squares in `a1 … h8` order.
List<Square> allSquares() =>
    List<Square>.generate(64, (i) => Square(i % 8, i ~/ 8));

/// On-board king-step neighbours of [sq] (3–8 squares, deterministic order).
List<Square> squareNeighbors(Square sq) {
  final out = <Square>[];
  for (var df = -1; df <= 1; df++) {
    for (var dr = -1; dr <= 1; dr++) {
      if (df == 0 && dr == 0) continue;
      final t = sq.offset(df, dr);
      if (t != null) out.add(t);
    }
  }
  return out;
}

/// Chebyshev (king-move) distance between two squares.
int chebyshevDistance(Square a, Square b) {
  final df = (a.file - b.file).abs();
  final dr = (a.rank - b.rank).abs();
  return df > dr ? df : dr;
}

// ---------------------------------------------------------------------------
// Piece ids.
// ---------------------------------------------------------------------------

/// Counter backing the non-deterministic fallback id generator.
/// Never used on engine hot paths (see [newVariantPieceId]).
int _fallbackIdCounter = 0;
final Random _fallbackRandom = Random();

/// Generates a unique-ish piece id (`vp<counter>_<base36>`).
///
/// Documented non-determinism: this uses a global counter plus randomness, so
/// two runs produce different ids. It is provided for UI/tests convenience
/// only. Engine and strategy code must use [freshDerivedId] instead so that
/// identical pipelines produce identical boards.
String newVariantPieceId() {
  _fallbackIdCounter++;
  final r = _fallbackRandom.nextInt(1 << 32).toRadixString(36);
  return 'vp${_fallbackIdCounter}_$r';
}

/// Returns [base] when no piece on [board] uses it, otherwise appends
/// `_2`, `_3`, … until the id is free.
///
/// Fully deterministic given the same board and base, which keeps
/// interpretation pipelines reproducible.
String freshDerivedId(VariantBoard board, String base) {
  if (!board.containsPieceId(base)) return base;
  var n = 2;
  while (board.containsPieceId('${base}_$n')) {
    n++;
  }
  return '${base}_$n';
}

/// A single piece on a [VariantBoard]: standard type/colour plus a stable id.
///
/// Equality and hashing use **only [id]** (identity semantics): two records
/// with the same id are the same piece even if its type changed by promotion.
class VariantPiece {
  /// Stable identity, preserved across moves, shifts and promotion.
  final String id;

  /// Piece type (shared [PieceType] vocabulary).
  final PieceType type;

  /// Piece colour (shared [PieceColor] vocabulary).
  final PieceColor color;

  /// Creates a piece. An empty [id] is rejected.
  const VariantPiece({
    required this.id,
    required this.type,
    required this.color,
  }) : assert(id != '', 'VariantPiece id must not be empty');

  /// Copy with optional replacements (id defaults to the current id).
  VariantPiece copyWith({String? id, PieceType? type, PieceColor? color}) =>
      VariantPiece(
        id: id ?? this.id,
        type: type ?? this.type,
        color: color ?? this.color,
      );

  /// Converts to the shared identity-only [Piece] (drops the variant id).
  Piece toPiece() => Piece(type, color);

  /// Serializes to `{id, type, color}` with the type name and `w`/`b` code.
  Map<String, Object?> toJson() => {
        'id': id,
        'type': type.name,
        'color': colorCode(color),
      };

  /// Deserializes; throws [FormatException] on missing/unknown fields.
  factory VariantPiece.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final type = parsePieceType(json['type'] as String?);
    final color = parsePieceColor(json['color'] as String?);
    if (id is! String || id.isEmpty) {
      throw const FormatException('VariantPiece needs a non-empty id');
    }
    if (type == null) {
      throw FormatException('Unknown piece type: ${json['type']}');
    }
    if (color == null) {
      throw FormatException('Unknown piece color: ${json['color']}');
    }
    return VariantPiece(id: id, type: type, color: color);
  }

  @override
  bool operator ==(Object other) => other is VariantPiece && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => '$id(${colorCode(color)}${type.letter.toUpperCase()})';
}

/// Chaotic-variant board state.
class VariantBoard {
  /// Pieces by square (unmodifiable; at most one piece per square by
  /// construction of a [Map]).
  final Map<Square, VariantPiece> squares;

  /// Side to move (the "mover" for the next interpretation).
  final PieceColor sideToMove;

  /// Variant ply counter: copied from the standard fullmove number by
  /// [VariantBoard.fromStandard] and incremented by 1 for every applied
  /// interpretation afterwards. It is *not* a standard fullmove number;
  /// [tryToFen] maps it back on a best-effort basis only.
  final int moveNumber;

  /// Halfmove clock (best-effort: reset on pawn moves/captures by the
  /// helpers in this library).
  final int halfmove;

  /// When `true`, castling is considered meaningless/invalid in this position
  /// (e.g. no usable king/rook geometry survived chaotic play). Standard
  /// conversions treat it as "no castling rights".
  final bool castlingInvalid;

  /// Free-text annotation trail (strategies/engines may append tags).
  final String notes;

  /// Creates a board. The [squares] map is copied into an unmodifiable map.
  VariantBoard({
    required Map<Square, VariantPiece> squares,
    this.sideToMove = PieceColor.white,
    this.moveNumber = 1,
    this.halfmove = 0,
    this.castlingInvalid = false,
    this.notes = '',
  }) : squares = Map<Square, VariantPiece>.unmodifiable(squares);

  /// Builds a variant board from a standard [Position].
  ///
  /// Piece ids are derived deterministically as `std_<square>` (one piece per
  /// square, so no collision is possible). [castlingInvalid] is `true` when
  /// the position holds no castling rights.
  factory VariantBoard.fromStandard(Position pos) {
    final m = <Square, VariantPiece>{};
    for (final e in pos.board.entries) {
      m[e.key] = VariantPiece(
        id: 'std_${e.key.name}',
        type: e.value.type,
        color: e.value.color,
      );
    }
    return VariantBoard(
      squares: m,
      sideToMove: pos.sideToMove,
      moveNumber: pos.fullmoveNumber,
      halfmove: pos.halfmoveClock,
      castlingInvalid: pos.castling.isEmpty,
      notes: 'fromStandard ',
    );
  }

  /// Deep-ish copy: the map is duplicated (pieces are immutable and shared),
  /// so ids and everything else are preserved.
  VariantBoard clone() => VariantBoard(
        squares: Map<Square, VariantPiece>.from(squares),
        sideToMove: sideToMove,
        moveNumber: moveNumber,
        halfmove: halfmove,
        castlingInvalid: castlingInvalid,
        notes: notes,
      );

  /// Piece on [sq], or `null` when empty.
  VariantPiece? pieceAt(Square sq) => squares[sq];

  /// `true` when any piece on the board already uses [id].
  bool containsPieceId(String id) {
    for (final p in squares.values) {
      if (p.id == id) return true;
    }
    return false;
  }

  /// All pieces of [color] (deterministic square order).
  List<VariantPiece> piecesOf(PieceColor color) {
    final keys = squares.keys.toList()..sort();
    return [for (final k in keys) if (squares[k]!.color == color) squares[k]!];
  }

  /// Squares holding a king of [color] (0..n entries; deterministic order).
  List<Square> kingSquares(PieceColor color) {
    final out = <Square>[];
    for (final e in squares.entries) {
      if (e.value.type == PieceType.king && e.value.color == color) {
        out.add(e.key);
      }
    }
    out.sort();
    return out;
  }

  /// Number of pieces on the board.
  int get pieceCount => squares.length;

  /// Converts to a standard [Position] when exactly representable, else `null`.
  ///
  /// Representability requires: exactly one king per side, at most 16 pieces
  /// per side, at most 8 pawns per side. Pawn placement is *not* restricted;
  /// legality of play from odd-but-representable positions is the standard
  /// engine's concern, not this method's.
  ///
  /// Castling rights are granted on home-square king+rook geometry unless
  /// [castlingInvalid] is set. En passant is always `null`: chaotic boards do
  /// not track the double-push history an en-passant target requires.
  Position? toStandardPosition() {
    var whiteKings = 0;
    var blackKings = 0;
    var whiteCount = 0;
    var blackCount = 0;
    var whitePawns = 0;
    var blackPawns = 0;
    final m = <Square, Piece>{};
    for (final e in squares.entries) {
      final p = e.value;
      m[e.key] = Piece(p.type, p.color);
      if (p.color.isWhite) {
        whiteCount++;
        if (p.type == PieceType.king) whiteKings++;
        if (p.type == PieceType.pawn) whitePawns++;
      } else {
        blackCount++;
        if (p.type == PieceType.king) blackKings++;
        if (p.type == PieceType.pawn) blackPawns++;
      }
    }
    if (whiteKings != 1 || blackKings != 1) return null;
    if (whiteCount > 16 || blackCount > 16) return null;
    if (whitePawns > 8 || blackPawns > 8) return null;
    // `castlingInvalid` means "no usable king/rook geometry survived":
    // grant no rights even when the pieces happen to sit on home squares.
    return Position(
      board: m,
      sideToMove: sideToMove,
      castling: castlingInvalid ? const <String>{} : _rightsFromGeometry(m),
      halfmoveClock: halfmove,
      fullmoveNumber: moveNumber < 1 ? 1 : moveNumber,
    );
  }

  /// `true` when this board can be represented as FEN (equivalent to
  /// `toStandardPosition() != null`).
  bool canRepresentAsFen() => toStandardPosition() != null;

  /// Best-effort FEN export; `null` when the board is not representable.
  ///
  /// Rendered locally (not via `chess/fen.dart`): piece placement, side to
  /// move, castling rights from king/rook home geometry, `-` for en passant
  /// (variant boards carry no double-push history), then the stored clocks
  /// with [moveNumber] mapped best-effort onto the fullmove field. Never
  /// invents a misleading FEN: non-convertible boards yield `null`.
  String? tryToFen() {
    final pos = toStandardPosition();
    if (pos == null) return null;
    final buf = StringBuffer();
    for (var r = 7; r >= 0; r--) {
      var empty = 0;
      for (var f = 0; f < 8; f++) {
        final p = pos.board[Square(f, r)];
        if (p == null) {
          empty++;
        } else {
          if (empty > 0) {
            buf.write(empty);
            empty = 0;
          }
          // Shared `letter` is canonical uppercase; normalize explicitly so
          // this renderer never depends on another module's casing choice.
          final base = p.type.letter.toLowerCase();
          buf.write(p.color.isWhite ? base.toUpperCase() : base);
        }
      }
      if (empty > 0) buf.write(empty);
      if (r > 0) buf.write('/');
    }
    buf.write(pos.sideToMove.isWhite ? ' w ' : ' b ');
    // Rights come from the converted position (geometry-derived, already
    // emptied when `castlingInvalid` is set) — never recomputed here, so the
    // FEN bridge cannot re-grant rights the flag revoked.
    final rights = pos.castling;
    const order = ['K', 'Q', 'k', 'q'];
    final castle = order.where(rights.contains).join();
    buf.write(castle.isEmpty ? '-' : castle);
    buf.write(' - ${pos.halfmoveClock} ${pos.fullmoveNumber}');
    return buf.toString();
  }

  /// Castling rights implied by home-square king+rook geometry.
  static Set<String> _rightsFromGeometry(Map<Square, Piece> m) {
    final rights = <String>{};
    final wkHome = m[const Square(4, 0)] ==
        const ChessPiece(PieceType.king, PieceColor.white);
    final bkHome = m[const Square(4, 7)] ==
        const ChessPiece(PieceType.king, PieceColor.black);
    if (wkHome &&
        m[const Square(7, 0)] ==
            const ChessPiece(PieceType.rook, PieceColor.white)) {
      rights.add('K');
    }
    if (wkHome &&
        m[const Square(0, 0)] ==
            const ChessPiece(PieceType.rook, PieceColor.white)) {
      rights.add('Q');
    }
    if (bkHome &&
        m[const Square(7, 7)] ==
            const ChessPiece(PieceType.rook, PieceColor.black)) {
      rights.add('k');
    }
    if (bkHome &&
        m[const Square(0, 7)] ==
            const ChessPiece(PieceType.rook, PieceColor.black)) {
      rights.add('q');
    }
    return rights;
  }

  /// Deterministic layout hash for candidate deduplication.
  ///
  /// Covers square occupancy (type + colour) and the side to move, but
  /// deliberately *excludes* piece ids and notes: two boards that look
  /// identical deduplicate even if their pieces carry different ids.
  String boardHash() {
    final keys = squares.keys.toList()..sort();
    final buf = StringBuffer(colorCode(sideToMove));
    buf.write('|');
    for (final k in keys) {
      final p = squares[k]!;
      buf.write('${k.name}:${colorCode(p.color)}'
          '${p.type.letter.toUpperCase()};');
    }
    return buf.toString();
  }

  /// Full-fidelity JSON (ids, counters, flags, notes, pieces by square).
  ///
  /// This — not FEN — is the canonical serialization: it round-trips every
  /// field including 0..n kings and piece identity.
  Map<String, Object?> toJson() => {
        'sideToMove': colorCode(sideToMove),
        'moveNumber': moveNumber,
        'halfmove': halfmove,
        'castlingInvalid': castlingInvalid,
        'notes': notes,
        'pieces': [
          for (final e in (squares.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key))))
            {
              'square': e.key.name,
              ...e.value.toJson(),
            },
        ],
      };

  /// Deserializes [toJson] output; throws [FormatException] on bad input.
  ///
  /// Duplicate squares or duplicate piece ids are rejected to protect the
  /// board invariants.
  factory VariantBoard.fromJson(Map<String, Object?> json) {
    final side = parsePieceColor(json['sideToMove'] as String?);
    if (side == null) {
      throw FormatException('Unknown sideToMove: ${json['sideToMove']}');
    }
    final pieces = json['pieces'];
    if (pieces is! List) {
      throw const FormatException('VariantBoard needs a pieces list');
    }
    final m = <Square, VariantPiece>{};
    final seenIds = <String>{};
    for (final raw in pieces) {
      if (raw is! Map) {
        throw const FormatException('Piece entry must be a map');
      }
      final entry = Map<String, Object?>.from(raw);
      final sq = tryParseSquare(entry.remove('square') as String?);
      if (sq == null) {
        throw FormatException('Unknown square: ${raw['square']}');
      }
      if (m.containsKey(sq)) {
        throw FormatException('Duplicate piece on square ${sq.name}');
      }
      final piece = VariantPiece.fromJson(entry);
      if (!seenIds.add(piece.id)) {
        throw FormatException('Duplicate piece id ${piece.id}');
      }
      m[sq] = piece;
    }
    final moveNumber = (json['moveNumber'] as num?)?.toInt() ?? 1;
    final halfmove = (json['halfmove'] as num?)?.toInt() ?? 0;
    if (moveNumber < 1) {
      throw FormatException('moveNumber out of range: $moveNumber');
    }
    if (halfmove < 0) {
      throw FormatException('halfmove out of range: $halfmove');
    }
    return VariantBoard(
      squares: m,
      sideToMove: side,
      moveNumber: moveNumber,
      halfmove: halfmove,
      castlingInvalid: json['castlingInvalid'] as bool? ?? false,
      notes: json['notes'] as String? ?? '',
    );
  }

  @override
  String toString() =>
      'VariantBoard(${squares.length} pieces, ${colorCode(sideToMove)} to move)';
}

/// Applies a standard [ChessMove] to a [VariantBoard] with id preservation.
///
/// Used by the `closestLegalMove` strategy for boards that are exactly
/// representable (and mirrored by the engine's standard-apply path). The mover
/// keeps its id (promotion changes only its type); a castling rook keeps its
/// id; captured pieces (including best-effort en-passant victims: a pawn
/// moving diagonally onto an empty square removes the enemy pawn beside it)
/// simply disappear. Side to move flips and [VariantBoard.moveNumber]
/// increments by one.
///
/// This is best-effort geometry, not a rules engine: callers must only pass
/// moves already validated against the equivalent [Position].
VariantBoard applyStandardMove(VariantBoard board, ChessMove move) {
  final mover = board.pieceAt(move.from);
  if (mover == null) {
    throw StateError(
        'applyStandardMove: no piece on ${move.from.name} (${board.notes})');
  }
  final next = Map<Square, VariantPiece>.from(board.squares);
  next.remove(move.from);
  // En-passant heuristic: diagonal pawn move onto an empty square captures
  // the enemy pawn on the adjacent file/rank.
  if (mover.type == PieceType.pawn &&
      move.from.file != move.to.file &&
      board.pieceAt(move.to) == null) {
    final victim = Square(move.to.file, move.from.rank);
    final victimPiece = next[victim];
    // Only an enemy *pawn* beside the mover is an en-passant victim; any
    // other piece there is left alone (the destination itself is handled
    // as a normal capture below).
    if (victimPiece != null &&
        victimPiece.color != mover.color &&
        victimPiece.type == PieceType.pawn) {
      next.remove(victim);
    }
  }
  next.remove(move.to); // Normal capture, if any.
  next[move.to] = move.promotion == null
      ? mover
      : mover.copyWith(type: move.promotion);
  // Castling heuristic: king moving two squares drags the home-corner rook.
  if (mover.type == PieceType.king &&
      (move.from.file - move.to.file).abs() == 2) {
    final homeRank = move.from.rank;
    final rookFrom =
        Square(move.to.file == 6 ? 7 : 0, homeRank);
    final rookTo = Square(move.to.file == 6 ? 5 : 3, homeRank);
    final rook = next.remove(rookFrom);
    if (rook != null &&
        rook.type == PieceType.rook &&
        rook.color == mover.color) {
      next[rookTo] = rook;
    }
  }
  final isPawn = mover.type == PieceType.pawn;
  final isCapture = board.pieceAt(move.to) != null;
  return VariantBoard(
    squares: next,
    sideToMove: board.sideToMove.opposite,
    moveNumber: board.moveNumber + 1,
    halfmove: (isPawn || isCapture) ? 0 : board.halfmove + 1,
    castlingInvalid: board.castlingInvalid ||
        mover.type == PieceType.king ||
        _touchedRookHome(board, move.from) ||
        _touchedRookHome(board, move.to),
    notes: '${board.notes}[std ${move.from.name}${move.to.name}] ',
  );
}

/// `true` when [sq] is a rook home square holding a rook on [board].
bool _touchedRookHome(VariantBoard board, Square sq) {
  const homes = [
    Square(0, 0),
    Square(7, 0),
    Square(0, 7),
    Square(7, 7),
  ];
  if (!homes.contains(sq)) return false;
  return board.pieceAt(sq)?.type == PieceType.rook;
}
