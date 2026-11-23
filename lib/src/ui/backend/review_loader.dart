/// Review data-loading + computation for the review screen.
///
/// Extracted from `ui/screens/review_screen.dart` without behavior change:
/// resolving the evaluator, rebuilding FEN history, building review inputs,
/// running [WintrReviewService.reviewGame], and deriving the UI quality-mark
/// vocabulary. [ReviewLoader] has one job — given a [ReviewGame], produce a
/// ready-to-render [ReviewView] via [ReviewLoader.load] using an injected
/// [ReviewEvaluatorFactory]. It communicates out via the plain data object
/// [ReviewView] (never widgets); the screen keeps record picking, handle
/// lifecycle/disposal, and chart/list rendering.
/// Talks to: `review/` (`quality.dart`, `wintr_review.dart`) via `review_resolver.dart` (`ReviewGame` inputs); emits `ReviewView`.
/// Never imports: `package:flutter`, `game/`, `arena/`, `storage/` — data loading only, never widgets.
library;

import '../../diagnostics/backend_log.dart';
import '../../review/quality.dart' show MoveQuality;
import '../../review/wintr_review.dart';
import 'review_resolver.dart';

/// Ready-to-render review data for one [ReviewGame].
///
/// Produced by [ReviewLoader.load]; the screen renders charts/lists from
/// this object and owns [handle] disposal (the view keeps the same reference
/// for source-banner reads after suspend disposes it — never dispose via the
/// view separately, only via the screen's handle field).
class ReviewView {
  /// Creates a ready-to-render review view.
  const ReviewView({
    required this.game,
    required this.fens,
    required this.inputs,
    required this.report,
    required this.handle,
    required this.qualityMarks,
    required this.keyMomentMarks,
    required this.marksByQuality,
    required this.errorPlies,
  });

  /// The reviewed game (snapshot at load time).
  final ReviewGame game;

  /// FEN history for [game] (via [fensFor]; rebuilt defensively).
  final List<String> fens;

  /// Per-move evaluator inputs (via [reviewInputsFor]).
  final List<ReviewMoveInput> inputs;

  /// The full review report.
  final ReviewReport report;

  /// Evaluator handle for this run (owned/disposed by the screen).
  final ReviewEvaluatorHandle handle;

  /// Evaluation source label (`EngineSources` vocabulary).
  String get source => handle.resolvedSource;

  /// Honest fallback reason (`''` when Stockfish backed the run).
  String get fallbackReason => handle.fallbackReason;

  /// UI quality marks (`'!!'`…`'??'`) parallel to [report.moves].
  final List<String> qualityMarks;

  /// UI quality marks parallel to [report.keyMoments].
  final List<String> keyMomentMarks;

  /// Tier → UI mark for every [MoveQuality] (summary/key-moment lookups).
  final Map<MoveQuality, String> marksByQuality;

  /// Ply indices flagged as seeded fallbacks (from `fallbackFlags`).
  final Set<int> errorPlies;

  /// Per-ply mark map for `MoveList` (`reportIndex → mark`).
  Map<int, String> get qualityMarksByPly => <int, String>{
    for (var i = 0; i < qualityMarks.length; i++) i: qualityMarks[i],
  };
}

/// Failure of the review-computation phase carrying its evaluator handle.
///
/// The factory phase ([ReviewEvaluatorFactory]) throws bare (no handle
/// exists); once a handle is resolved, any later failure (input building or
/// [WintrReviewService.reviewGame]) wraps here so the screen can keep the
/// handle for the source banner and dispose it exactly once — matching the
/// previous inline behavior where a failed run kept its handle alive.
class ReviewLoadException implements Exception {
  /// Creates a review-phase failure carrying [handle].
  const ReviewLoadException(this.handle, this.cause);

  /// The resolved evaluator handle (screen-owned; must be disposed once).
  final ReviewEvaluatorHandle handle;

  /// The underlying failure.
  final Object cause;

  @override
  String toString() => 'ReviewLoadException($cause)';
}

/// One-job review pipeline: [ReviewGame] in, [ReviewView] out.
///
/// Construct with the §10.2 seam ([reviewEvaluatorFactoryProvider] in
/// production; heuristic-only handles in widget tests so no Stockfish
/// process is ever spawned). [load] is stateless across calls — the screen
/// disposes the previous view's handle before calling again and disposes the
/// returned view's handle on replace/suspend/dispose/stale completion.
class ReviewLoader {
  /// Creates a loader around the injected evaluator factory. [log] injects
  /// the UI-free logger (per-call override wins; defaults to
  /// [currentBackendLog]).
  const ReviewLoader({required this.evalFactory, this.log});

  /// The §10.2 evaluator factory seam.
  final ReviewEvaluatorFactory evalFactory;

  /// UI-free logger (per-call override wins; defaults to [currentBackendLog]).
  final BackendLog? log;

  /// Resolves an evaluator, builds inputs, reviews, and derives marks.
  ///
  /// Factory failures propagate bare (no handle to own). Review-phase
  /// failures throw [ReviewLoadException] carrying the resolved handle so
  /// the caller can banner + dispose it. [log]/[tournamentId] attach the
  /// logger and correlation IDs (game id comes from `game.id`).
  Future<ReviewView> load(
    ReviewGame game, {
    BackendLog? log,
    String? tournamentId,
  }) async {
    final effectiveLog = log ?? this.log ?? currentBackendLog;
    effectiveLog.debug(
      'review load start moves=${game.ucis.length}',
      tag: 'review-loader',
      gameId: game.id,
      tournamentId: tournamentId,
    );
    final handle = await evalFactory();
    try {
      final fens = fensFor(game);
      final inputs = reviewInputsFor(game);
      final report = await WintrReviewService(evaluator: handle.evaluator)
          .reviewGame(inputs);
      final view = ReviewView(
        game: game,
        fens: List<String>.of(fens),
        inputs: inputs,
        report: report,
        handle: handle,
        qualityMarks: <String>[
          for (final move in report.moves)
            qualityMarkFor(move.assessment.quality),
        ],
        keyMomentMarks: <String>[
          for (final moment in report.keyMoments)
            qualityMarkFor(moment.quality),
        ],
        marksByQuality: <MoveQuality, String>{
          for (final quality in MoveQuality.values)
            quality: qualityMarkFor(quality),
        },
        errorPlies: <int>{
          for (var i = 0; i < game.fallbackFlags.length; i++)
            if (game.fallbackFlags[i]) i,
        },
      );
      effectiveLog.debug(
        'review load end moves=${view.report.moves.length}',
        tag: 'review-loader',
        gameId: game.id,
        tournamentId: tournamentId,
      );
      return view;
    } catch (cause, stackTrace) {
      effectiveLog.error(
        'review load failed kind=reviewError moves=${game.ucis.length}',
        tag: 'review-loader',
        gameId: game.id,
        tournamentId: tournamentId,
        error: cause,
        stackTrace: stackTrace,
      );
      throw ReviewLoadException(handle, cause);
    }
  }
}
