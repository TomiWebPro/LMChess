/// Legal projections of a chaotic [VariantBoard] for engine evaluation.
///
/// Stockfish only accepts FEN, but variant boards routinely violate FEN
/// assumptions. The projector emits zero or more *standard-legal projections*
/// without silently pretending the variant board was standard:
///
/// * exactly one king per side → one projection (the fast path);
/// * multiple kings → one projection per white×black king selection (sampled
///   deterministically when the combination count exceeds [maxProjections]);
/// * zero kings on a side → terminal, no engine call;
/// * pawns on a promotion rank → promoted to a queen (same id);
/// * pawns on their own back rank → relocated to the nearest empty legal rank,
///   or dropped if the board is full;
/// * extra pieces/pawns (>16 / >8) → kept (FEN accepts them); the issue set
///   carries the non-standard-material label.
///
/// Every emitted FEN is validated with [parseFen] before it is returned, so a
/// bad projection can never reach the engine.
library;

import '../chess/fen.dart';
import '../chess/piece.dart';
import '../chess/position.dart';
import '../chess/square.dart';
import '../variant/variant_board.dart';

/// Why a projection is not a faithful standard position.
enum VariantProjectionIssue {
  missingWhiteKing,
  missingBlackKing,
  missingBothKings,
  multipleWhiteKings,
  multipleBlackKings,
  pawnPromoted,
  pawnRelocated,
  pawnDropped,
  extraWhitePawns,
  extraBlackPawns,
  extraWhitePieces,
  extraBlackPieces,
  sampledRoyalSelections,
  unsupportedProjection,
}

/// One standard-legal position derived from a variant board.
class VariantProjectedPosition {
  /// FEN validated by [parseFen].
  final String fen;

  /// White king square selected for this projection.
  final String whiteKingSquare;

  /// Black king square selected for this projection.
  final String blackKingSquare;

  /// Human-readable transformation notes.
  final List<String> notes;

  /// Creates a projected position.
  const VariantProjectedPosition({
    required this.fen,
    required this.whiteKingSquare,
    required this.blackKingSquare,
    this.notes = const <String>[],
  });
}

/// Complete projection result for one board.
class VariantProjection {
  /// Legal FEN projections (empty when terminal/unsupported).
  final List<VariantProjectedPosition> positions;

  /// Non-standard features encountered.
  final Set<VariantProjectionIssue> issues;

  /// Human-readable transformations (`white pawn a8 -> queen`).
  final List<String> transforms;

  /// Number of white×black king combinations before sampling.
  final int totalRoyalCombinations;

  /// Number of royal combinations actually projected.
  final int sampledRoyalCombinations;

  /// `true` when a side has no king (terminal variant state).
  final bool terminal;

  /// Winner for a terminal state (`null` = draw).
  final PieceColor? terminalWinner;

  /// Why no projection could be produced, when [positions] is empty.
  final String? unsupportedReason;

  /// Creates a projection.
  const VariantProjection({
    required this.positions,
    required this.issues,
    required this.transforms,
    required this.totalRoyalCombinations,
    required this.sampledRoyalCombinations,
    this.terminal = false,
    this.terminalWinner,
    this.unsupportedReason,
  });

  /// Terminal projection (zero kings).
  factory VariantProjection.terminal({
    required PieceColor? winner,
    required Set<VariantProjectionIssue> issues,
    required int totalRoyalCombinations,
  }) =>
      VariantProjection(
        positions: const <VariantProjectedPosition>[],
        issues: issues,
        transforms: const <String>[],
        totalRoyalCombinations: totalRoyalCombinations,
        sampledRoyalCombinations: 0,
        terminal: true,
        terminalWinner: winner,
      );

  /// Fraction of royal combinations actually evaluated.
  double get coverage => totalRoyalCombinations == 0
      ? 0
      : sampledRoyalCombinations / totalRoyalCombinations;

  /// `true` when the board is exactly one king per side and no transformation
  /// or non-standard material was needed.
  bool get isStandard =>
      positions.length == 1 && totalRoyalCombinations == 1 && issues.isEmpty;

  /// `true` when any transformation/sampling happened.
  bool get isLossy => issues.isNotEmpty;
}

/// Builds standard-legal projections from [VariantBoard]s.
class VariantPositionProjector {
  /// Creates a projector.
  const VariantPositionProjector({this.maxProjections = 8});

  /// Upper bound on royal combinations evaluated per board.
  final int maxProjections;

  /// Projects [board].
  VariantProjection project(VariantBoard board) {
    final whiteKings = board.kingSquares(PieceColor.white)
      ..sort((a, b) => a.name.compareTo(b.name));
    final blackKings = board.kingSquares(PieceColor.black)
      ..sort((a, b) => a.name.compareTo(b.name));
    final total = whiteKings.length * blackKings.length;
    final issues = <VariantProjectionIssue>{};

    if (whiteKings.isEmpty || blackKings.isEmpty) {
      if (whiteKings.isEmpty) issues.add(VariantProjectionIssue.missingWhiteKing);
      if (blackKings.isEmpty) issues.add(VariantProjectionIssue.missingBlackKing);
      if (whiteKings.isEmpty && blackKings.isEmpty) {
        issues.add(VariantProjectionIssue.missingBothKings);
      }
      return VariantProjection.terminal(
        winner: whiteKings.isEmpty && blackKings.isEmpty
            ? null
            : (whiteKings.isEmpty ? PieceColor.black : PieceColor.white),
        issues: issues,
        totalRoyalCombinations: total,
      );
    }

    if (whiteKings.length > 1) {
      issues.add(VariantProjectionIssue.multipleWhiteKings);
    }
    if (blackKings.length > 1) {
      issues.add(VariantProjectionIssue.multipleBlackKings);
    }

    final normalized = _normalizePawns(board, issues);
    final pairs = _royalPairs(
      whiteKings,
      blackKings,
      total,
      issues,
    );
    final standard = board.toStandardPosition();
    final castling = standard?.castling ?? const <String>{};
    final positions = <VariantProjectedPosition>[];
    for (final pair in pairs) {
      final squares = Map<Square, VariantPiece>.of(normalized.squares);
      squares.removeWhere((_, piece) => piece.type == PieceType.king);
      final whiteKing = board.pieceAt(pair.$1)!;
      final blackKing = board.pieceAt(pair.$2)!;
      squares[pair.$1] = whiteKing;
      squares[pair.$2] = blackKing;
      final fen = _fenFor(squares, board, castling);
      try {
        parseFen(fen);
      } catch (_) {
        issues.add(VariantProjectionIssue.unsupportedProjection);
        continue;
      }
      positions.add(VariantProjectedPosition(
        fen: fen,
        whiteKingSquare: pair.$1.name,
        blackKingSquare: pair.$2.name,
        notes: normalized.transforms,
      ));
    }

    return VariantProjection(
      positions: positions,
      issues: issues,
      transforms: normalized.transforms,
      totalRoyalCombinations: total,
      sampledRoyalCombinations: pairs.length,
      unsupportedReason:
          positions.isEmpty ? 'no royal projection produced a valid FEN' : null,
    );
  }

  List<(Square, Square)> _royalPairs(
    List<Square> white,
    List<Square> black,
    int total,
    Set<VariantProjectionIssue> issues,
  ) {
    final all = <(Square, Square)>[
      for (final w in white)
        for (final b in black) (w, b),
    ];
    if (all.length <= maxProjections) return all;
    issues.add(VariantProjectionIssue.sampledRoyalSelections);
    // Deterministic, evenly spaced sample (sorted king lists above).
    final step = all.length / maxProjections;
    return <(Square, Square)>[
      for (var i = 0; i < maxProjections; i++) all[(i * step).floor()],
    ];
  }

  _Normalized _normalizePawns(
    VariantBoard board,
    Set<VariantProjectionIssue> issues,
  ) {
    final squares = Map<Square, VariantPiece>.of(board.squares);
    final transforms = <String>[];
    for (final entry in board.squares.entries.toList()) {
      final piece = entry.value;
      if (piece.type != PieceType.pawn) continue;
      final promotionRank = piece.color.isWhite ? 7 : 0;
      final ownBackRank = piece.color.isWhite ? 0 : 7;
      if (entry.key.rank == promotionRank) {
        squares[entry.key] = piece.copyWith(type: PieceType.queen);
        issues.add(VariantProjectionIssue.pawnPromoted);
        transforms.add(
          '${piece.color.name} pawn ${entry.key.name} promoted to queen',
        );
        continue;
      }
      if (entry.key.rank == ownBackRank) {
        final target = _nearestLegalPawnSquare(squares, entry.key);
        squares.remove(entry.key);
        if (target == null) {
          issues.add(VariantProjectionIssue.pawnDropped);
          transforms.add(
            '${piece.color.name} pawn ${entry.key.name} dropped '
            '(no legal empty square)',
          );
        } else {
          squares[target] = piece;
          issues.add(VariantProjectionIssue.pawnRelocated);
          transforms.add(
            '${piece.color.name} pawn ${entry.key.name} relocated to '
            '${target.name}',
          );
        }
      }
    }

    final white = squares.values.where((p) => p.color.isWhite).toList();
    final black = squares.values.where((p) => p.color.isBlack).toList();
    if (white.where((p) => p.type == PieceType.pawn).length > 8) {
      issues.add(VariantProjectionIssue.extraWhitePawns);
    }
    if (black.where((p) => p.type == PieceType.pawn).length > 8) {
      issues.add(VariantProjectionIssue.extraBlackPawns);
    }
    if (white.length > 16) {
      issues.add(VariantProjectionIssue.extraWhitePieces);
    }
    if (black.length > 16) {
      issues.add(VariantProjectionIssue.extraBlackPieces);
    }
    return _Normalized(squares, transforms);
  }

  Square? _nearestLegalPawnSquare(
    Map<Square, VariantPiece> squares,
    Square from,
  ) {
    Square? best;
    var bestKey = (1 << 30, 1 << 30, 1 << 30, '');
    for (final square in allSquares()) {
      if (square.rank < 1 || square.rank > 6) continue;
      if (squares.containsKey(square)) continue;
      final key = (
        chebyshevDistance(from, square),
        (square.rank - from.rank).abs(),
        (square.file - from.file).abs(),
        square.name,
      );
      if (_tupleLess(key, bestKey)) {
        best = square;
        bestKey = key;
      }
    }
    return best;
  }

  String _fenFor(
    Map<Square, VariantPiece> squares,
    VariantBoard source,
    Set<String> castling,
  ) {
    final pieces = <Square, Piece>{
      for (final entry in squares.entries)
        entry.key: Piece(entry.value.type, entry.value.color),
    };
    final position = Position(
      board: pieces,
      sideToMove: source.sideToMove,
      castling: castling,
      halfmoveClock: 0,
      fullmoveNumber: source.moveNumber < 1 ? 1 : source.moveNumber,
    );
    return toFen(position);
  }
}

class _Normalized {
  const _Normalized(this.squares, this.transforms);

  final Map<Square, VariantPiece> squares;
  final List<String> transforms;
}

bool _tupleLess(
  (int, int, int, String) a,
  (int, int, int, String) b,
) {
  if (a.$1 != b.$1) return a.$1 < b.$1;
  if (a.$2 != b.$2) return a.$2 < b.$2;
  if (a.$3 != b.$3) return a.$3 < b.$3;
  return a.$4.compareTo(b.$4) < 0;
}
