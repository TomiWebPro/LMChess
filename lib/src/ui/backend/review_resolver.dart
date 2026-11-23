/// Review resolution for the UI layer.
///
/// Extracted from `ui/backend_bridge.dart` without behavior change:
/// the [ReviewGame] record, the [ReviewEvaluatorFactory] seam, the
/// [ReviewEvaluatorHandle] lifecycle, and the [fensFor]/[reviewInputsFor]
/// builders that turn a stored game into evaluator inputs. Pure Dart: the
/// Riverpod factory seam (`reviewEvaluatorFactoryProvider`) lives in
/// `../providers/backend_providers.dart`.
/// Talks to: `review/` (`embedded_engine.dart`, `engine_adapter.dart`), `game/orchestrator.dart` (`standardStartFen`).
/// Never imports: `package:flutter` widgets/material, `package:flutter_riverpod`, `storage/local_store`, `hive` — the evaluator factory seam lives in `../providers/backend_providers.dart`.
library;

import 'dart:async';
import 'dart:math' as math;

import '../../game/orchestrator.dart' show standardStartFen;
import '../../review/embedded_engine.dart';
import '../../review/engine_adapter.dart';
import '../../review/quality.dart';
import '../../review/stockfish_evaluator.dart';
import '../../review/wintr_review.dart';
import 'board_mapper.dart' show fenAdvance;

/// Factory type for §10.2 review-evaluator seam.
///
/// Takes no arguments — the screen's own record id is already captured by the
/// caller. Returning a [ReviewEvaluatorHandle] lets the callee own the
/// evaluator lifecycle (resolution, use, disposal) while keeping the wiring
/// point injectable for tests: override `reviewEvaluatorFactoryProvider` (in
/// `../providers/backend_providers.dart`, defaulting to
/// [resolveReviewEvaluator]) with a heuristic-only handle so no Stockfish
/// process is ever spawned in widget tests.
typedef ReviewEvaluatorFactory = Future<ReviewEvaluatorHandle> Function();

/// One reviewable game: full move + FEN + commentary history.
///
/// FENs follow the replay convention `fens.length == ucis.length + 1`
/// (`fens[0]` is the start position). `phrases`/`fallbackFlags` are
/// parallel to `ucis` (human moves carry `null` phrases). Standard games
/// start with White to move, so ply `i`'s mover is White iff `i` is even.
class ReviewGame {
  /// Creates a review game. Length invariants are documented, not
  /// asserted, so a malformed record degrades to an empty review rather
  /// than crashing the screen.
  const ReviewGame({
    required this.id,
    required this.whiteLabel,
    required this.blackLabel,
    this.whiteAgentId,
    this.blackAgentId,
    this.mode = 'standard',
    this.ucis = const <String>[],
    this.sans = const <String>[],
    this.fens = const <String>[],
    this.phrases = const <String?>[],
    this.fallbackFlags = const <bool>[],
  });

  /// Stable id (`'play-game'`, `'watch-game'`, tournament game ids…).
  final String id;

  /// Display labels for both seats.
  final String whiteLabel;

  /// Display labels for both seats.
  final String blackLabel;

  /// Agent ids for stats attribution, when known.
  final String? whiteAgentId;

  /// Agent ids for stats attribution, when known.
  final String? blackAgentId;

  /// `'standard'` or `'chaotic'`.
  final String mode;

  /// Played moves in UCI order.
  final List<String> ucis;

  /// SAN labels parallel to [ucis].
  final List<String> sans;

  /// FEN history (`length == ucis.length + 1` when well-formed).
  final List<String> fens;

  /// Agent phrases parallel to [ucis] (`null` for human moves).
  final List<String?> phrases;

  /// Fallback flags parallel to [ucis].
  final List<bool> fallbackFlags;
}

/// Maps a [MoveQuality] tier to the UI quality mark vocabulary.
///
/// `'!!'` covers both brilliant tiers, `'!'` best/excellent, `'ok'`
/// good + unsupported (no judgment available), `'!?'` inaccuracy, `'?'`
/// mistake, `'??'` blunder/super-blunder. Icons/colors come from
/// `qualityIconFor`/`qualityColorFor` in `widgets/boards.dart`.
String qualityMarkFor(MoveQuality quality) {
  switch (quality) {
    case MoveQuality.superBrilliant:
    case MoveQuality.brilliant:
      return '!!';
    case MoveQuality.best:
    case MoveQuality.excellent:
      return '!';
    case MoveQuality.good:
    case MoveQuality.unsupported:
      return 'ok';
    case MoveQuality.inaccuracy:
      return '!?';
    case MoveQuality.mistake:
      return '?';
    case MoveQuality.blunder:
    case MoveQuality.superBlunder:
      return '??';
  }
}

/// Resolved evaluation source for one review run.
///
/// [resolvedSource] is the [EngineSources] label of [evaluator]
/// (`'stockfish-uci'` or `'heuristic'`), which the review UI must render
/// next to every score. When Stockfish could not be used, [fallbackReason]
/// carries the platform's honest explanation ([EmbeddedEngine] error or
/// connect failure) — never silently swallowed. [dispose] shuts down the
/// spawned engine process (no-op for the heuristic estimator); call it
/// once per run, when the review finishes or the screen goes away.
class ReviewEvaluatorHandle {
  /// Creates a handle (construct via [resolveReviewEvaluator]).
  ReviewEvaluatorHandle({
    required this.evaluator,
    required this.resolvedSource,
    this.fallbackReason = '',
    this.engine,
  });

  /// Evaluator for both positions of every reviewed move.
  final PositionEvaluator evaluator;

  /// [EngineSources] label of [evaluator] (render verbatim in the UI).
  final String resolvedSource;

  /// Human-readable reason the heuristic fallback was chosen; `''` when
  /// the embedded Stockfish binary connected.
  final String fallbackReason;

  /// Connected UCI engine adapter to shut down, or `null` when the run
  /// uses the built-in heuristic estimator.
  final UciEngineAdapter? engine;

  /// Whether the heuristic estimator (not an engine) backs this run.
  bool get isFallback => resolvedSource != EngineSources.stockfishUci;

  /// Shuts down the spawned engine process, if any. Idempotent.
  Future<void> dispose() async {
    await engine?.dispose();
  }
}

/// Resolves the best available reviewer: embedded Stockfish when the
/// platform can spawn it, else the honest [HeuristicEvaluator] fallback.
///
/// Flow: [EmbeddedEngine.isAvailable] performs the same first-run
/// extraction [StockfishEvaluator] would (so a `true` probe leaves the
/// binary ready); on success a `StockfishEvaluator` is constructed and
/// [UciEngineAdapter.connect]ed — a connect failure (AV sandbox, broken
/// binary) is caught, the half-connected adapter disposed, and the
/// heuristic fallback applies. On unavailable platforms
/// ([EmbeddedEngine.explanatoryError] carries the iOS/Web/no-binary
/// reason verbatim). The returned handle's [ReviewEvaluatorHandle
/// .resolvedSource]/[ReviewEvaluatorHandle.fallbackReason] must be shown
/// in the UI — heuristic numbers are estimates, never engine output.
Future<ReviewEvaluatorHandle> resolveReviewEvaluator() async {
  if (await EmbeddedEngine.isAvailable()) {
    final engine = StockfishEvaluator();
    try {
      await engine.connect();
      return ReviewEvaluatorHandle(
        evaluator: engine,
        resolvedSource: EngineSources.stockfishUci,
        engine: engine,
      );
    } catch (e) {
      await engine.dispose();
      return ReviewEvaluatorHandle(
        evaluator: HeuristicEvaluator(),
        resolvedSource: EngineSources.heuristic,
        fallbackReason:
            'Stockfish was found but failed to start ($e); using the '
            'heuristic estimator instead.',
      );
    }
  }
  return ReviewEvaluatorHandle(
    evaluator: HeuristicEvaluator(),
    resolvedSource: EngineSources.heuristic,
    fallbackReason: await EmbeddedEngine.explanatoryError(),
  );
}

/// FEN history for [game], rebuilt by replay when the record is malformed.
///
/// Stored records follow the replay convention
/// `fens.length == ucis.length + 1`. When a caller (or an interrupted
/// recorder) produced a short history, this replays [ReviewGame.ucis]
/// from [standardStartFen] via [fenAdvance] to reconstruct it; if replay
/// fails (chaotic UCI list, corrupt records) the stored list is returned
/// unchanged so callers can degrade honestly instead of crashing.
List<String> fensFor(ReviewGame game) {
  if (game.fens.length == game.ucis.length + 1) {
    return List<String>.of(game.fens);
  }
  try {
    final rebuilt = <String>[standardStartFen];
    for (final uci in game.ucis) {
      rebuilt.add(fenAdvance(rebuilt.last, uci));
    }
    return rebuilt;
  } catch (_) {
    return List<String>.of(game.fens);
  }
}

/// Turns a stored [ReviewGame] into the [ReviewMoveInput] list
/// [WintrReviewService.reviewGame] consumes.
///
/// One input per stored UCI: `fenBefore`/`fenAfterOrVariantJson` come
/// from [fensFor] (standard FEN for standard games; variant JSON passes
/// through to variant-capable evaluators — Stockfish reports
/// `supported: false` for it, per the `engine_adapter.dart` contract).
/// `moverIsWhite` follows the standard-game convention (White starts, so
/// even plies are White's). Commentary is the stored agent phrase, or
/// `null` on seeded fallbacks (fallbacks are never attributed); the
/// fallback also lands as an annotation. `wasIllegalAttempt` is not part
/// of [ReviewGame] — illegal attempts never auto-penalize in [classify],
/// so its absence cannot skew a tier; a future recorder that tracks it
/// should extend the record (**Wiring point**).
///
/// Plies without a supporting FEN pair (malformed record that replay
/// could not repair) are skipped rather than fabricated; an empty result
/// is a valid empty review.
List<ReviewMoveInput> reviewInputsFor(ReviewGame game) {
  final fens = fensFor(game);
  final usable = fens.isEmpty ? 0 : math.min(game.ucis.length, fens.length - 1);
  final out = <ReviewMoveInput>[];
  for (var i = 0; i < usable; i++) {
    final fallback = i < game.fallbackFlags.length && game.fallbackFlags[i];
    final phrase = i < game.phrases.length ? game.phrases[i] : null;
    out.add(
      ReviewMoveInput(
        fenBefore: fens[i],
        fenAfterOrVariantJson: fens[i + 1],
        moverIsWhite: i.isEven,
        commentary: fallback ? null : phrase,
        annotations: fallback
            ? const <String>['seeded fallback move (unattributed)']
            : const <String>[],
      ),
    );
  }
  return out;
}
