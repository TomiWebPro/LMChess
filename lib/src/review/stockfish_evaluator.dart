/// Stockfish position evaluator over the embedded UCI binary.
///
/// [StockfishEvaluator] wires the generic [UciEngineAdapter] to the
/// first-run extracted Stockfish binary ([EmbeddedEngine]): unless an
/// explicit [executablePath] override is given (dev machines, tests),
/// the binary is resolved at [UciEngineAdapter.connect] time, so
/// constructing the evaluator never touches the filesystem.
///
/// Review-friendly defaults: single thread and a 64 MB hash keep
/// background game review from starving the UI isolate; bump them via
/// [UciEngineAdapter.options] on machines where review runs detached.
/// Scores are White-relative centipawns with `source == 'stockfish-uci'`
/// ([EngineSources.stockfishUci]); variant JSON yields
/// `supported: false` per the base-class contract — Stockfish only ever
/// sees standard FEN.
///
/// On platforms where Stockfish cannot run (web, iOS, unshipped arch),
/// [UciEngineAdapter.connect] throws ([UnsupportedError]/[StateError]
/// from [EmbeddedEngine.resolveBinary]); callers must catch that and
/// fall back to [HeuristicEvaluator]. Use [EmbeddedEngine.isAvailable]
/// to probe beforehand and [EmbeddedEngine.explanatoryError] for the
/// user-facing reason.
library;

import 'engine_adapter.dart';
import 'embedded_engine.dart';

/// Evaluates standard-chess positions with embedded Stockfish 19 (UCI).
class StockfishEvaluator extends UciEngineAdapter {
  /// Creates an evaluator with review-conservative defaults.
  ///
  /// * [executablePath]: explicit binary override. Null (default)
  ///   resolves the embedded binary lazily at connect time via
  ///   [EmbeddedEngine.resolveBinary] (or [executableResolver] when
  ///   given, e.g. a test double).
  /// * [executableResolver]: custom lazy resolver; defaults to
  ///   [EmbeddedEngine.resolveBinary] when no explicit path is set.
  /// * [options]: UCI options; defaults to single-threaded review
  ///   (`Threads=1`, `Hash=64`).
  /// * [defaultDepth]/[args]/[engineName]: passed through to
  ///   [UciEngineAdapter].
  StockfishEvaluator({
    String? executablePath,
    Future<String> Function()? executableResolver,
    super.options = const <String, String>{
      'Threads': '1',
      'Hash': '64',
    },
    super.args,
    super.defaultDepth = 12,
    super.engineName = 'stockfish',
  }) : super(
          executablePath: executablePath ?? '',
          executablePathResolver: executablePath != null
              ? null
              : (executableResolver ?? EmbeddedEngine.resolveBinary),
          source: EngineSources.stockfishUci,
        );
}
