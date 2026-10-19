/// Headless facade for the chaotic / illegal-move rules engine.
///
/// [ChaoticRules] is the single entry point for variant play. It is a static
/// facade (not instantiable) over a fixed full pipeline:
///
/// 1. Record the attempt and snapshot the board state (mover, king presence).
/// 2. Try the standard application ([tryStandardApply]): when the board is
///    exactly convertible to a [Position] and the attempt is legal there, the
///    move applies normally with piece ids preserved.
/// 3. Otherwise generate candidates ([InterpretationRegistry.generateAll]),
///    validate board invariants (≤1 piece per square, on-board squares,
///    sane counters), score each via [VariantEvaluator] from the mover's
///    perspective, and select one with [selectInterpretation].
/// 4. Return an [InterpretedResult] carrying the candidates, the winner and a
///    human-readable [InterpretedResult.events] log.
///
/// King-capture bookkeeping lives here too ([isKingCaptured], [gameOver]):
/// the board tolerates 0..n kings, so "the game ended" is an external verdict,
/// not a board property.
///
/// ## Robustness note
///
/// [tryStandardApply] treats the shared standard engine as best-effort: any
/// exception escaping it (for example while the chess module is evolving) is
/// caught and reported as `legal: false` with a detail string, so the
/// interpretation pipeline always continues. A degraded legality check only
/// ever *widens* the interpretation path; it can never corrupt a board.
library;

import '../chess/move.dart';
import '../chess/piece.dart';
import '../chess/position.dart';
import '../chess/square.dart';
import 'evaluator.dart';
import 'interpretation.dart';
import 'selection.dart';
import 'strategies.dart';
import 'variant_board.dart';

/// Outcome of attempting a standard-rules application of a move.
class StandardApplyResult {
  /// `true` when the move applied as a legal standard move.
  final bool legal;

  /// The resulting board with ids preserved (`null` when [!legal]).
  final VariantBoard? board;

  /// Human-readable verdict, e.g. why the attempt was not standard-legal.
  final String detail;

  /// Creates a result.
  const StandardApplyResult({
    required this.legal,
    this.board,
    this.detail = '',
  });
}

/// Verdict on whether a variant game has ended.
class GameOverResult {
  /// `true` when at least one side's king is missing.
  final bool over;

  /// The winner: the surviving side, or `null` for draws (both kings gone)
  /// and ongoing games.
  final PieceColor? winner;

  /// Human-readable reason, e.g. `black king captured`.
  final String reason;

  /// Creates a verdict.
  const GameOverResult({
    required this.over,
    this.winner,
    this.reason = '',
  });
}

/// Static facade for chaotic-variant rules. Not instantiable.
class ChaoticRules {
  /// Private constructor (static-only class).
  const ChaoticRules._();

  /// Tries to apply [attempt] as a standard legal move on [board].
  ///
  /// Steps: parse squares and promotion (garbage → illegal with a detail);
  /// convert via [VariantBoard.toStandardPosition] (non-convertible → illegal
  /// with a detail); check legality with the shared standard engine; apply on
  /// a throwaway [Position] with piece-id preservation (mover and castling
  /// rook keep their ids, promotion keeps the mover's id and changes its
  /// type, captures vanish).
  ///
  /// Never throws for bad input: every failure mode returns
  /// `StandardApplyResult(legal: false, detail: …)`. Promotion hints default
  /// to queen for a pawn reaching the last rank; any other use of a promotion
  /// hint is illegal.
  static StandardApplyResult tryStandardApply(
      VariantBoard board, AttemptedMove attempt) {
    final from = attempt.fromSquare;
    final to = attempt.toSquare;
    if (from == null || to == null) {
      return const StandardApplyResult(
        legal: false,
        detail: 'unparsable square names',
      );
    }
    if (from == to) {
      return const StandardApplyResult(
        legal: false,
        detail: 'from and to are the same square',
      );
    }
    final pos = board.toStandardPosition();
    if (pos == null) {
      return const StandardApplyResult(
        legal: false,
        detail: 'board is not convertible to a standard position',
      );
    }
    var promotion = attempt.promotionType;
    if (attempt.promotion != null &&
        attempt.promotion!.trim().isNotEmpty &&
        promotion == null) {
      return StandardApplyResult(
        legal: false,
        detail: 'unknown promotion piece: ${attempt.promotion}',
      );
    }
    final mover = pos.pieceAt(from);
    if (mover == null || mover.color != pos.sideToMove) {
      return StandardApplyResult(
        legal: false,
        detail: mover == null
            ? 'no piece on ${from.name}'
            : 'piece on ${from.name} belongs to ${mover.color.name}',
      );
    }
    final promoRank = to.rank == (mover.color.isWhite ? 7 : 0);
    final needsPromo = mover.type == PieceType.pawn && promoRank;
    if (needsPromo) {
      promotion ??= PieceType.queen;
      if (!isPromotionTarget(promotion)) {
        return StandardApplyResult(
          legal: false,
          detail: 'cannot promote to ${promotion.name}',
        );
      }
    } else {
      promotion = null;
    }
    final move = ChessMove(from, to, promotion: promotion);
    bool legal;
    try {
      legal = pos.isLegal(move);
    } catch (e) {
      return StandardApplyResult(
        legal: false,
        detail: 'standard legality check unavailable ($e)',
      );
    }
    if (!legal) {
      return StandardApplyResult(
        legal: false,
        detail: 'illegal under standard rules: ${from.name} to ${to.name}',
      );
    }
    AppliedMove receipt;
    try {
      receipt = pos.apply(move);
    } catch (e) {
      return StandardApplyResult(
        legal: false,
        detail: 'standard apply failed ($e)',
      );
    }
    return StandardApplyResult(
      legal: true,
      board: _rebuildPreservingIds(board, pos, move, receipt),
      detail: 'standard ${from.name} to ${to.name}',
    );
  }

  /// Runs the full interpretation pipeline for [attempt] on [board].
  ///
  /// * Legal attempts short-circuit: one `standard` candidate, [wasLegal]
  ///   true, selected immediately (still scored for observability).
  /// * Illegal attempts fan out through [InterpretationRegistry.generateAll];
  ///   every candidate is invariant-checked, scored from the mover's
  ///   perspective, and ranked by [policy] (default
  ///   [SelectionPolicy.bestStrategic]). An empty candidate set falls back to
  ///   a deterministic `noopPass` candidate (turn passes, board otherwise
  ///   unchanged) so the result always carries a selection.
  /// * Every stage appends to [events]; callers should surface these in game
  ///   review UIs.
  ///
  /// Deterministic given identical inputs (see selection docs); [seed] only
  /// affects [SelectionPolicy.random].
  static InterpretedResult interpret(
    VariantBoard board,
    AttemptedMove attempt, {
    SelectionPolicy policy = SelectionPolicy.bestStrategic,
    int seed = 0,
  }) {
    final events = <String>[];
    final mover = board.sideToMove;
    events.add(
        'attempt by ${mover.name}: ${attempt.phrase.isEmpty ? '${attempt.fromSquareName} to ${attempt.toSquareName}' : attempt.phrase}');

    final standard = tryStandardApply(board, attempt);
    if (standard.legal) {
      final result = standard.board!;
      final candidate = CandidateInterpretation.scored(
        raw: UnscoredInterpretation(
          strategyId: 'standard',
          title: 'Standard application',
          description: 'Legal under standard rules; applied normally.',
          resultingBoard: result,
        ),
        parentBoard: board,
        mover: mover,
        scoreCp: VariantEvaluator.score(result, mover),
      );
      events.add('standard legality: legal (${standard.detail})');
      events.add('selected standard application (score ${candidate.scoreCp})');
      return InterpretedResult(
        attempt: attempt,
        wasLegal: true,
        candidates: [candidate],
        selected: candidate,
        events: events,
      );
    }
    events.add('standard legality: illegal (${standard.detail})');

    final raws = InterpretationRegistry.generateAll(board, attempt);
    events.add('generated ${raws.length} raw candidate(s)');
    final candidates = <CandidateInterpretation>[];
    for (final raw in raws) {
      final problem = _validateInvariants(raw.resultingBoard);
      if (problem != null) {
        events.add('rejected ${raw.strategyId}: $problem');
        continue;
      }
      candidates.add(CandidateInterpretation.scored(
        raw: raw,
        parentBoard: board,
        mover: mover,
        scoreCp: VariantEvaluator.score(raw.resultingBoard, mover),
      ));
    }
    events.add('${candidates.length} candidate(s) survived validation');
    if (candidates.isEmpty) {
      final pass = _noopPass(board);
      final fallback = CandidateInterpretation.scored(
        raw: UnscoredInterpretation(
          strategyId: 'noopPass',
          title: 'Pass (no interpretation)',
          description:
              'No strategy could interpret the attempt; the turn passes '
              'with the board unchanged.',
          resultingBoard: pass,
        ),
        parentBoard: board,
        mover: mover,
        scoreCp: VariantEvaluator.score(pass, mover),
      );
      events.add('no candidates: fell back to noopPass');
      return InterpretedResult(
        attempt: attempt,
        wasLegal: false,
        candidates: [fallback],
        selected: fallback,
        events: events,
      );
    }
    final selected = selectInterpretation(
      candidates,
      policy,
      mover,
      seed,
      originalBoard: board,
    );
    events.add(
        'policy ${policy.name} selected ${selected.strategyId} '
        '(score ${selected.scoreCp}'
        '${selected.capturesKing ? ', KING CAPTURE' : ''}) '
        'from ${candidates.length} candidate(s)');
    return InterpretedResult(
      attempt: attempt,
      wasLegal: false,
      candidates: candidates,
      selected: selected,
      events: events,
    );
  }

  /// `true` when [color] has no king left on [board].
  ///
  /// King capture is tracked externally (the board permits 0..n kings); this
  /// is the primitive that [gameOver] and candidate scoring build on.
  ///
  /// Resolved multi-king semantics: this predicate is deliberately
  /// *empty-set* — it reports `true` only when [color] has **zero** kings,
  /// which is what makes a side terminal. Capturing one of several kings is
  /// an offensive success but not a game end; that partial credit is scored
  /// in [CandidateInterpretation.scored] (king-count decrement), not here.
  static bool isKingCaptured(VariantBoard board, PieceColor color) =>
      board.kingSquares(color).isEmpty;

  /// Adjudicates the game: over when either side's king is missing.
  ///
  /// * One king missing → the *other* side wins (`<color> king captured`).
  /// * Both missing → over with no winner (draw, `both kings captured`).
  /// * Neither missing → not over.
  ///
  /// Only a zero-king side is terminal: on a multi-king board, losing one
  /// king of several does **not** end the game — it is rewarded during
  /// selection instead (see [isKingCaptured] and
  /// [CandidateInterpretation.scored]).
  static GameOverResult gameOver(VariantBoard board) {
    final whiteGone = isKingCaptured(board, PieceColor.white);
    final blackGone = isKingCaptured(board, PieceColor.black);
    if (whiteGone && blackGone) {
      return const GameOverResult(
          over: true, reason: 'both kings captured — draw');
    }
    if (whiteGone) {
      return const GameOverResult(
          over: true,
          winner: PieceColor.black,
          reason: 'white king captured');
    }
    if (blackGone) {
      return const GameOverResult(
          over: true,
          winner: PieceColor.white,
          reason: 'black king captured');
    }
    return const GameOverResult(over: false, reason: 'both kings on board');
  }

  // ------------------------------------------------------------- internals

  /// Rebuilds a variant board from the post-move standard [pos], preserving
  /// ids: unmoved pieces keep theirs by square+type+colour match, the mover
  /// (and a castling rook, located geometrically when [receipt] reports
  /// castling) keeps its id, and a promotion keeps the mover's id with the
  /// new type. Captures (including en passant) simply vanish.
  static VariantBoard _rebuildPreservingIds(
    VariantBoard old,
    Position pos,
    ChessMove move,
    AppliedMove receipt,
  ) {
    final mover = old.pieceAt(move.from);
    Square? rookFrom;
    Square? rookTo;
    if (receipt.isCastle) {
      final homeRank = move.from.rank;
      final kingside = move.to.file == 6;
      rookFrom = Square(kingside ? 7 : 0, homeRank);
      rookTo = Square(kingside ? 5 : 3, homeRank);
    }
    final rook = rookFrom == null ? null : old.pieceAt(rookFrom);
    final out = <Square, VariantPiece>{};
    for (final e in pos.board.entries) {
      final sq = e.key;
      final PieceType type = e.value.type;
      final PieceColor color = e.value.color;
      if (sq == move.to && mover != null && mover.color == color) {
        out[sq] = mover.copyWith(type: type); // Move (+promotion) keeps id.
      } else if (sq == rookTo && rook != null && rook.color == color) {
        out[sq] = rook; // Castling rook keeps id.
      } else {
        final staying = old.pieceAt(sq);
        if (staying != null &&
            staying.type == type &&
            staying.color == color) {
          out[sq] = staying;
        } else {
          // Defensive: standard play never materialises pieces from nowhere,
          // but never drop data — mint a deterministic derived id.
          final probe = VariantBoard(
            squares: {...old.squares, ...out},
            sideToMove: old.sideToMove,
          );
          out[sq] = VariantPiece(
            id: freshDerivedId(
                probe, 'stdx_m${old.moveNumber}_${sq.name}'),
            type: type,
            color: color,
          );
        }
      }
    }
    return VariantBoard(
      squares: out,
      sideToMove: pos.sideToMove,
      moveNumber: old.moveNumber + 1,
      halfmove: pos.halfmoveClock,
      castlingInvalid: old.castlingInvalid || pos.castling.isEmpty,
      notes: '${old.notes}[std ${move.from.name}${move.to.name}] ',
    );
  }

  /// Invariant check for strategy output; `null` means valid.
  ///
  /// The map shape already guarantees ≤1 piece per square; this re-validates
  /// the reachable corners (empty ids, duplicate ids, absurd counters)
  /// defensively — mirroring what [VariantBoard.fromJson] enforces so a
  /// strategy cannot smuggle in a board that would fail deserialization.
  static String? _validateInvariants(VariantBoard board) {
    final seenIds = <String>{};
    for (final e in board.squares.entries) {
      if (e.value.id.isEmpty) {
        return 'piece with empty id on ${e.key.name}';
      }
      if (!seenIds.add(e.value.id)) {
        return 'duplicate piece id ${e.value.id} (on ${e.key.name})';
      }
    }
    if (board.moveNumber < 1) return 'moveNumber out of range';
    if (board.squares.length > 64) return 'more than 64 pieces';
    return null;
  }

  /// Deterministic pass: same pieces, turn flipped, ply incremented.
  static VariantBoard _noopPass(VariantBoard board) => VariantBoard(
        squares: Map<Square, VariantPiece>.from(board.squares),
        sideToMove: board.sideToMove.opposite,
        moveNumber: board.moveNumber + 1,
        halfmove: board.halfmove + 1,
        castlingInvalid: board.castlingInvalid,
        notes: '${board.notes}[noopPass] ',
      );
}
