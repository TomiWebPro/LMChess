// Variant engine fuzz / property tests.
//
// The chaotic engine must survive *any* well-formed attempt on *any* board:
// every from×to pair (64×64, including from == to), empty origins/destinations,
// garbage promotion hints, missing/multiple kings, back-rank pawns, and all
// selection policies. "Survive" means: no throw, a selected interpretation,
// a structurally valid resulting board, deterministic output for the same
// inputs, and JSON round-tripability.
//
// The exhaustive grids intentionally use QueryPerformance-style budgets: the
// goal is correctness under combinatorial input, not speed.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/chess/fen.dart';
import 'package:llm_chess_arena/src/chess/piece.dart';
import 'package:llm_chess_arena/src/chess/position.dart';
import 'package:llm_chess_arena/src/chess/square.dart';
import 'package:llm_chess_arena/src/review/variant_projection.dart';
import 'package:llm_chess_arena/src/variant/chaotic_engine.dart';
import 'package:llm_chess_arena/src/variant/interpretation.dart';
import 'package:llm_chess_arena/src/variant/selection.dart';
import 'package:llm_chess_arena/src/variant/variant_board.dart';

/// Builds a board with 0..64 random pieces, random kings/material, and a
/// random side/counters. Deterministic for [seed].
VariantBoard _randomBoard(math.Random random, int seed, {int? pieceCount}) {
  final squares = <Square, VariantPiece>{};
  final pool = allSquares()..shuffle(random);
  final count = pieceCount ?? random.nextInt(65);
  for (var i = 0; i < count; i++) {
    squares[pool[i]] = VariantPiece(
      id: 'fuzz_${seed}_$i',
      type: PieceType.values[random.nextInt(PieceType.values.length)],
      color: PieceColor.values[random.nextInt(PieceColor.values.length)],
    );
  }
  return VariantBoard(
    squares: squares,
    sideToMove: random.nextBool() ? PieceColor.white : PieceColor.black,
    moveNumber: 1 + random.nextInt(80),
    halfmove: random.nextInt(40),
    castlingInvalid: random.nextBool(),
    notes: 'fuzz board $seed',
  );
}

VariantBoard _multiKingBoard() {
  final base = VariantBoard.fromStandard(Position.initial());
  final squares = Map<Square, VariantPiece>.of(base.squares);
  squares[Square.fromName('c3')] = const VariantPiece(
    id: 'extra-wk',
    type: PieceType.king,
    color: PieceColor.white,
  );
  squares[Square.fromName('c6')] = const VariantPiece(
    id: 'extra-bk',
    type: PieceType.king,
    color: PieceColor.black,
  );
  squares[Square.fromName('a8')] = const VariantPiece(
    id: 'back-rank-pawn',
    type: PieceType.pawn,
    color: PieceColor.white,
  );
  return VariantBoard(squares: squares, sideToMove: PieceColor.black);
}

VariantBoard _fullBoard() {
  final random = math.Random(4242);
  return _randomBoard(random, 4242, pieceCount: 64);
}

void _assertBoardValid(VariantBoard board, VariantBoard parent) {
  expect(board.squares.length, lessThanOrEqualTo(64));
  final ids = board.squares.values.map((piece) => piece.id).toList();
  expect(ids.toSet().length, ids.length, reason: 'duplicate piece ids');
  expect(
    board.squares.keys.every(
      (square) =>
          square.file >= 0 &&
          square.file < 8 &&
          square.rank >= 0 &&
          square.rank < 8,
    ),
    isTrue,
    reason: 'piece outside the board',
  );
  expect(board.sideToMove, parent.sideToMove.opposite);
  expect(board.moveNumber, greaterThanOrEqualTo(1));
  expect(board.halfmove, greaterThanOrEqualTo(0));
  expect(() => board.boardHash(), returnsNormally);
  expect(() => ChaoticRules.gameOver(board), returnsNormally);
  expect(() => ChaoticRules.isKingCaptured(board, PieceColor.white),
      returnsNormally);
  expect(() => ChaoticRules.isKingCaptured(board, PieceColor.black),
      returnsNormally);
}

/// Interprets one attempt and returns the result after checking the contract.
InterpretedResult _interpretChecked({
  required VariantBoard board,
  required AttemptedMove attempt,
  required SelectionPolicy policy,
  required int seed,
  required bool deepCheck,
}) {
  final InterpretedResult result;
  try {
    result = ChaoticRules.interpret(
      board,
      attempt,
      policy: policy,
      seed: seed,
    );
  } catch (e, stack) {
    fail(
      'interpret threw for board=${board.boardHash()} '
      '${attempt.fromSquareName}->${attempt.toSquareName} '
      'promo=${attempt.promotion} policy=${policy.name}: $e\n$stack',
    );
  }

  expect(result.candidates, isNotEmpty);
  expect(
    result.candidates.any(
      (candidate) =>
          candidate.reproducibilityKey == result.selected.reproducibilityKey,
    ),
    isTrue,
    reason: 'selected candidate must come from the candidate list',
  );
  _assertBoardValid(result.selected.resultingBoard, board);

  if (deepCheck) {
    final roundTrip =
        VariantBoard.fromJson(result.selected.resultingBoard.toJson());
    expect(
      roundTrip.toJson(),
      result.selected.resultingBoard.toJson(),
      reason: 'resulting board must JSON round-trip',
    );
  }
  return result;
}

void main() {
  const promotions = <String?>[
    null,
    'q',
    'r',
    'b',
    'n',
    'x', // unknown
    'king', // nonsense
    '', // empty
  ];

  test('exhaustive 64x64 from/to grid survives on arbitrary boards', () {
    final boards = <VariantBoard>[
      VariantBoard.fromStandard(Position.initial()),
      _multiKingBoard(),
      _fullBoard(),
      _randomBoard(math.Random(1), 1),
      _randomBoard(math.Random(2), 2),
    ];
    final policies = SelectionPolicy.values;
    var checked = 0;
    var deepChecked = 0;

    for (var boardIndex = 0; boardIndex < boards.length; boardIndex++) {
      final board = boards[boardIndex];
      var moveIndex = 0;
      for (final from in allSquares()) {
        for (final to in allSquares()) {
          final promotion = promotions[moveIndex % promotions.length];
          final attempt = AttemptedMove(
            fromSquareName: from.name,
            toSquareName: to.name,
            promotion: promotion,
            phrase: 'fuzz $boardIndex/$moveIndex',
            rawToolCallJson: <String, Object?>{
              'from': from.name,
              'to': to.name,
              'promotion': promotion,
              'junk': moveIndex,
            },
          );
          final policy = policies[moveIndex % policies.length];
          final result = _interpretChecked(
            board: board,
            attempt: attempt,
            policy: policy,
            seed: boardIndex * 10000 + moveIndex,
            deepCheck: moveIndex % 64 == 0,
          );
          checked++;
          if (moveIndex % 64 == 0) {
            deepChecked++;
            // Determinism contract: same inputs → same selected reading/board.
            final again = ChaoticRules.interpret(
              board,
              attempt,
              policy: policy,
              seed: boardIndex * 10000 + moveIndex,
            );
            expect(again.selected.strategyId, result.selected.strategyId);
            expect(
              again.selected.resultingBoard.toJson(),
              result.selected.resultingBoard.toJson(),
            );
          }
          moveIndex++;
        }
      }
    }

    // 5 boards × 4096 from×to moves.
    expect(checked, 5 * 64 * 64);
    expect(deepChecked, greaterThan(250));
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('random boards and random attempts never throw', () {
    final random = math.Random(2026);
    for (var boardIndex = 0; boardIndex < 40; boardIndex++) {
      final board = _randomBoard(random, boardIndex);
      for (var i = 0; i < 64; i++) {
        final from = allSquares()[random.nextInt(64)];
        final to = allSquares()[random.nextInt(64)];
        final attempt = AttemptedMove(
          fromSquareName: from.name,
          toSquareName: to.name,
          promotion: promotions[random.nextInt(promotions.length)],
          phrase: '',
        );
        _interpretChecked(
          board: board,
          attempt: attempt,
          policy: SelectionPolicy
              .values[random.nextInt(SelectionPolicy.values.length)],
          seed: random.nextInt(1 << 31),
          deepCheck: i % 8 == 0,
        );
      }
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('random JSON never leaks a non-FormatException', () {
    final random = math.Random(77);
    const colors = <Object?>[null, 'w', 'b', 'x', 42];
    const types = <Object?>[null, 'pawn', 'king', 'x', 42];
    for (var i = 0; i < 600; i++) {
      final pieces = <Object?>[
        for (var j = 0; j < random.nextInt(10); j++)
          <String, Object?>{
            'square': <Object?>[null, 'a1', 'z9', 'e4', 42][random.nextInt(5)],
            'id': <Object?>[null, '', 'p$j', 42][random.nextInt(4)],
            'type': types[random.nextInt(types.length)],
            'color': colors[random.nextInt(colors.length)],
          },
      ];
      final json = <String, Object?>{
        'sideToMove': <Object?>[null, 'w', 'b', 'x', 42][random.nextInt(5)],
        'moveNumber': <Object?>[null, 1, -3, 'x', 2.5][random.nextInt(5)],
        'halfmove': <Object?>[null, 0, -1, 'x'][random.nextInt(4)],
        'castlingInvalid': <Object?>[null, true, false, 'x'][random.nextInt(4)],
        'notes': <Object?>[null, '', 'note', 42][random.nextInt(4)],
        'pieces': pieces,
      };
      try {
        VariantBoard.fromJson(json);
      } on FormatException {
        // The documented failure mode for malformed input.
      } catch (e) {
        fail('VariantBoard.fromJson leaked ${e.runtimeType}: $e for $json');
      }
    }
  });

  test('projector never throws and emits only parseable FENs', () {
    final random = math.Random(99);
    const projector = VariantPositionProjector(maxProjections: 8);
    for (var i = 0; i < 120; i++) {
      final board = i < 40
          ? VariantBoard.fromStandard(Position.initial())
          : _randomBoard(random, i);
      final VariantProjection projection;
      try {
        projection = projector.project(board);
      } catch (e, stack) {
        fail('projector threw for ${board.boardHash()}: $e\n$stack');
      }
      for (final projected in projection.positions) {
        expect(
          () => parseFen(projected.fen),
          returnsNormally,
          reason: 'projected FEN must parse: ${projected.fen}',
        );
      }
      expect(
        projection.sampledRoyalCombinations,
        lessThanOrEqualTo(projection.totalRoyalCombinations),
      );
    }
  });
}
