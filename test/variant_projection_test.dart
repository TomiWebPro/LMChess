// Projection tests: every non-standard variant class must yield validated FEN
// projections (or an honest terminal/unsupported result), never invalid FEN.
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/chess/fen.dart';
import 'package:llm_chess_arena/src/chess/piece.dart';
import 'package:llm_chess_arena/src/chess/position.dart';
import 'package:llm_chess_arena/src/chess/square.dart';
import 'package:llm_chess_arena/src/review/variant_projection.dart';
import 'package:llm_chess_arena/src/variant/variant_board.dart';

VariantBoard _withPieces({
  Map<String, VariantPiece> add = const <String, VariantPiece>{},
  List<String> remove = const <String>[],
  PieceColor side = PieceColor.white,
}) {
  final base = VariantBoard.fromStandard(Position.initial());
  final squares = Map<Square, VariantPiece>.of(base.squares);
  for (final name in remove) {
    squares.remove(Square.fromName(name));
  }
  add.forEach((name, piece) {
    squares[Square.fromName(name)] = piece;
  });
  return VariantBoard(squares: squares, sideToMove: side);
}

void main() {
  const projector = VariantPositionProjector();

  test('standard initial board is one faithful projection', () {
    final board = VariantBoard.fromStandard(Position.initial());
    final projection = projector.project(board);
    expect(projection.terminal, isFalse);
    expect(projection.positions, hasLength(1));
    expect(projection.isStandard, isTrue);
    expect(projection.issues, isEmpty);
    expect(() => parseFen(projection.positions.single.fen), returnsNormally);
  });

  test('multiple kings enumerate royal selections', () {
    final board = _withPieces(
      add: <String, VariantPiece>{
        'c3': const VariantPiece(
          id: 'wk2',
          type: PieceType.king,
          color: PieceColor.white,
        ),
        'c6': const VariantPiece(
          id: 'bk2',
          type: PieceType.king,
          color: PieceColor.black,
        ),
      },
    );
    final projection = projector.project(board);
    expect(projection.positions, hasLength(4));
    expect(projection.totalRoyalCombinations, 4);
    expect(projection.issues, contains(VariantProjectionIssue.multipleWhiteKings));
    expect(projection.issues, contains(VariantProjectionIssue.multipleBlackKings));
    for (final projected in projection.positions) {
      final position = parseFen(projected.fen);
      final kings = position.board.values
          .where((piece) => piece.type == PieceType.king)
          .toList();
      expect(
        kings.where((piece) => piece.color == PieceColor.white),
        hasLength(1),
      );
      expect(
        kings.where((piece) => piece.color == PieceColor.black),
        hasLength(1),
      );
    }
  });

  test('sampling caps royal combinations deterministically', () {
    final board = _withPieces(
      add: <String, VariantPiece>{
        'c3': const VariantPiece(
          id: 'wk2',
          type: PieceType.king,
          color: PieceColor.white,
        ),
        'd3': const VariantPiece(
          id: 'wk3',
          type: PieceType.king,
          color: PieceColor.white,
        ),
        'c6': const VariantPiece(
          id: 'bk2',
          type: PieceType.king,
          color: PieceColor.black,
        ),
        'd6': const VariantPiece(
          id: 'bk3',
          type: PieceType.king,
          color: PieceColor.black,
        ),
      },
    );
    const sampled = VariantPositionProjector(maxProjections: 4);
    final first = sampled.project(board);
    final second = sampled.project(board);
    expect(first.positions, hasLength(4));
    expect(first.totalRoyalCombinations, 9);
    expect(first.issues, contains(VariantProjectionIssue.sampledRoyalSelections));
    expect(first.coverage, closeTo(4 / 9, 1e-9));
    expect(
      first.positions.map((p) => p.fen).toList(),
      second.positions.map((p) => p.fen).toList(),
    );
  });

  test('zero king is terminal and emits no FEN', () {
    final board = _withPieces(remove: <String>['e8']);
    final projection = projector.project(board);
    expect(projection.terminal, isTrue);
    expect(projection.terminalWinner, PieceColor.white);
    expect(projection.positions, isEmpty);
    expect(projection.issues, contains(VariantProjectionIssue.missingBlackKing));
  });

  test('back-rank and promotion-rank pawns are normalized', () {
    final board = _withPieces(
      add: <String, VariantPiece>{
        'a8': const VariantPiece(
          id: 'wp-promo',
          type: PieceType.pawn,
          color: PieceColor.white,
        ),
        'b1': const VariantPiece(
          id: 'wp-back',
          type: PieceType.pawn,
          color: PieceColor.white,
        ),
      },
      remove: <String>['a8', 'b1'],
    );
    final projection = projector.project(board);
    expect(projection.positions, hasLength(1));
    expect(projection.issues, contains(VariantProjectionIssue.pawnPromoted));
    expect(projection.issues, contains(VariantProjectionIssue.pawnRelocated));
    final position = parseFen(projection.positions.single.fen);
    // No pawn survived on the first or eighth rank.
    for (final entry in position.board.entries) {
      if (entry.value.type != PieceType.pawn) continue;
      expect(entry.key.rank, isNot(0));
      expect(entry.key.rank, isNot(7));
    }
  });

  test('extra material is kept and labeled, not truncated', () {
    final board = _withPieces(
      add: <String, VariantPiece>{
        'c3': const VariantPiece(
          id: 'wp-extra',
          type: PieceType.pawn,
          color: PieceColor.white,
        ),
      },
    );
    final projection = projector.project(board);
    expect(projection.positions, hasLength(1));
    expect(projection.issues, contains(VariantProjectionIssue.extraWhitePawns));
    final position = parseFen(projection.positions.single.fen);
    expect(
      position.board.values
          .where((p) => p.color.isWhite && p.type == PieceType.pawn)
          .length,
      9,
    );
  });
}
