// Rules facade + result detection + perft — pure Dart, no Flutter imports.
//
// Design decisions:
// - [ChessRules] is a stateless static facade over [Position] so game
//   controllers, arena harnesses and LLM loops share one entry point for
//   "is this move legal?" and "is the game over?". All automatic rules
//   (checkmate, stalemate, fifty-move, insufficient material) are derived
//   purely from the position — no external state needed.
// - [GameTermination] deliberately includes non-automatic endings
//   ([agreement], [resignation], [timeout], [aborted]): those are decided
//   by the game controller/arena, never by [ChessRules.resultOf], which
//   returns `null` while play continues. This keeps "position says" and
//   "humans arbitrated" cleanly separated. Repetition counting likewise
//   lives in the controller (keyed by [Position.repetitionKey]); only
//   the automatic seventy-five-move draw (reported as
//   [GameTermination.fiftyMove]) is detected here.
// - [perft] is a debugging/validation helper (counts leaf nodes), not a
//   search. Validate against known counts: startpos depths 1-4 give
//   20 / 400 / 8902 / 197281; Kiwipete
//   (`r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1`)
//   gives 48 / 2039 / 97862 at depths 1-3.
// - STANDARD CHESS ONLY. Chaotic-chess and other variants live in
//   lib/src/variant with their own rules; nothing here may special-case
//   them (e.g. no Chess960 castling).

import 'move.dart';
import 'piece.dart';
import 'position.dart';

/// How a game ended.
enum GameTermination {
  /// The side to move is checkmated; the opponent wins.
  checkmate,

  /// The side to move has no legal move and is not in check; drawn.
  stalemate,

  /// 100 halfmoves without pawn move or capture; drawn.
  ///
  /// FIDE simplification: treated as an automatic draw here (the engine
  /// has no claim protocol), and also used for the truly-automatic
  /// seventy-five-move rule ([Position.isSeventyFiveMove]) — see
  /// [ChessRules.resultOf]. A separate `seventyFiveMove` value was
  /// considered but rejected: exhaustive `switch` sites over this enum
  /// exist outside `lib/src/chess/` (UI bridge, tests) and must keep
  /// compiling, so the collapsed reason stays source-compatible.
  fiftyMove,

  /// Neither side can possibly checkmate with remaining material; drawn.
  insufficientMaterial,

  /// Players (human/LLM) agreed to a draw. Set by the game controller,
  /// never auto-detected.
  agreement,

  /// A player resigned. Set by the game controller, never auto-detected.
  resignation,

  /// A player exceeded their time budget. Set by the game controller,
  /// never auto-detected.
  timeout,

  /// Game stopped before a result (error, disconnect, user abort). Set
  /// by the game controller, never auto-detected.
  aborted,
}

/// Helpers on [GameTermination].
extension GameTerminationHelpers on GameTermination {
  /// True for the automatic drawn endings ([stalemate], [fiftyMove],
  /// [insufficientMaterial]) plus agreed draws.
  bool get isDraw =>
      this == GameTermination.stalemate ||
      this == GameTermination.fiftyMove ||
      this == GameTermination.insufficientMaterial ||
      this == GameTermination.agreement;

  /// True when the game ended decisively ([checkmate], [resignation],
  /// [timeout]); [aborted] is neither decisive nor a draw.
  bool get isDecisive =>
      this == GameTermination.checkmate ||
      this == GameTermination.resignation ||
      this == GameTermination.timeout;
}

/// The outcome of a finished game: how it ended and who won (`null`
/// for draws and [GameTermination.aborted]).
class GameResult {
  /// How the game ended.
  final GameTermination termination;

  /// The winner, or `null` for draws / aborted games.
  final PieceColor? winner;

  /// Creates a result. Asserts consistency: decisive endings need a
  /// winner, draws/aborts must not have one. (The condition is inlined
  /// rather than calling [GameTerminationHelpers.isDecisive] because
  /// extension members are not allowed in constant expressions.)
  const GameResult({required this.termination, this.winner})
      : assert(
            (winner != null) ==
                (termination == GameTermination.checkmate ||
                    termination == GameTermination.resignation ||
                    termination == GameTermination.timeout),
            'winner must be set iff the termination is decisive');

  /// True when neither side won.
  bool get isDraw => winner == null;

  @override
  String toString() =>
      'GameResult($termination, winner: ${winner?.displayName})';
}

/// Stateless standard-chess rules facade over [Position].
class ChessRules {
  ChessRules._(); // Not instantiable.

  /// Returns a fresh standard initial position.
  static Position initialPosition() => Position.initial();

  /// Whether [move] is legal for the side to move in [position].
  static bool isLegal(Position position, ChessMove move) =>
      position.isLegal(move);

  /// Returns the automatic result for [position], or `null` when play
  /// continues.
  ///
  /// Only position-derived endings are detected: checkmate, stalemate,
  /// fifty-move, seventy-five-move and insufficient material.
  /// Agreement, resignation, timeout and abort are the game
  /// controller's responsibility. Repetition (threefold/fivefold) is
  /// also the controller's job — feed it [Position.repetitionKey] after
  /// every move.
  ///
  /// FIDE nuance, simplified: fifty-move is claimable while
  /// seventy-five-move ([Position.isSeventyFiveMove]) is automatic; both
  /// are reported as [GameTermination.fiftyMove] since the engine has no
  /// claim protocol (and collapsing them keeps every external `switch`
  /// over [GameTermination] compiling).
  static GameResult? resultOf(Position position) {
    // Single legal-move generation: checkmate/stalemate both derive
    // from (in-check, has-moves) instead of via isCheckmate/isStalemate
    // (which would generate twice).
    final legal = position.legalMoves();
    final inCheck = position.isInCheck(position.sideToMove);
    if (legal.isEmpty) {
      if (inCheck) {
        return GameResult(
          termination: GameTermination.checkmate,
          winner: position.sideToMove.opposite,
        );
      }
      return const GameResult(termination: GameTermination.stalemate);
    }
    if (position.isInsufficientMaterial) {
      return const GameResult(
          termination: GameTermination.insufficientMaterial);
    }
    if (position.isFiftyMove || position.isSeventyFiveMove) {
      return const GameResult(termination: GameTermination.fiftyMove);
    }
    return null;
  }
}

/// Counts leaf nodes of the legal-move tree from [position] to [depth].
///
/// `perft(p, 0) == 1`; otherwise the sum over all legal moves of
/// `perft(child, depth - 1)`. Plays on history-free clones (receipts
/// are never read at perft scale, so skipping the per-node
/// `List.of(history)` copy is pure win), so [position] is never
/// modified. Exponential cost — keep `depth` small (<= 4-5 from the
/// startpos on typical hardware). Used to validate move generation
/// against published node counts (see file header).
int perft(Position position, int depth) {
  if (depth <= 0) return 1;
  var nodes = 0;
  for (final move in position.legalMoves()) {
    final child =
        position.clone(includeHistory: false)..apply(move);
    nodes += perft(child, depth - 1);
  }
  return nodes;
}
