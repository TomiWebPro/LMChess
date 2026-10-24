/// Position evaluation adapters: heuristic fallback, UCI stub, WintrChess.
///
/// # Source honesty (load-bearing rule)
///
/// Every [EvalResult] carries [EvalResult.source]: `'heuristic'`,
/// `'wintrchess'`, or `'stockfish-uci'`. The review UI must render this
/// source verbatim next to any score. A heuristic estimate must **never**
/// be presented as engine output — the [EvalResult.source] field exists
/// precisely to make that misrepresentation impossible without actively
/// discarding data.
///
/// # Score convention
///
/// [EvalResult.scoreCp] is always **White-relative** centipawns
/// (positive favors White), matching UCI `score cp` convention. Callers
/// needing mover-relative values negate when the mover is Black; see
/// `quality.dart` for the normalization helper pattern.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' show log;
import 'dart:io';

/// Evaluates a position given as FEN (standard) or variant JSON (chaotic).
///
/// [evaluate] accepts either a FEN string or a JSON-encoded variant state;
/// implementations decide what they support and report it via
/// [supportsVariant] (standard FEN is always supported).
abstract class PositionEvaluator {
  /// True when [evaluate] accepts chaotic-variant JSON positions.
  bool get supportsVariant;

  /// Human-readable evaluator name for logs and export provenance.
  String get name;

  /// Evaluates [fenOrVariantJson]. Never throws on legal input; returns
  /// `supported: false` when the position kind is unsupported.
  Future<EvalResult> evaluate(String fenOrVariantJson);
}

/// Result of one position evaluation.
///
/// [scoreCp] is **White-relative** (positive favors White). Null when
/// [supported] is false.
class EvalResult {
  /// White-relative score in centipawns. Null when unsupported.
  final int? scoreCp;

  /// Best move in UCI notation, if the evaluator produces one.
  final String? bestMoveUci;

  /// Search depth reached, if applicable (null for heuristic).
  final int? depth;

  /// Provenance: `'heuristic'`, `'wintrchess'`, or `'stockfish-uci'`.
  /// The review UI must display this next to the score.
  final String source;

  /// False when the position kind is unsupported by this evaluator.
  final bool supported;

  /// Creates a result. Asserts the source is a known value in debug.
  EvalResult({
    required this.scoreCp,
    this.bestMoveUci,
    this.depth,
    required this.source,
    this.supported = true,
  }) : assert(
          source == EngineSources.heuristic ||
              source == EngineSources.wintrChess ||
              source == EngineSources.stockfishUci,
          'EvalResult.source must be a known EngineSources value',
        );

  /// Convenience constructor for unsupported positions.
  factory EvalResult.unsupported(String source) =>
      EvalResult(scoreCp: null, source: source, supported: false);

  /// Serializes with stable field ordering.
  Map<String, Object?> toJson() => <String, Object?>{
        'scoreCp': scoreCp,
        'bestMoveUci': bestMoveUci,
        'depth': depth,
        'source': source,
        'supported': supported,
      };
}

/// Canonical [EvalResult.source] values.
abstract class EngineSources {
  /// Cheap built-in estimator. Never label as engine output.
  static const String heuristic = 'heuristic';

  /// WintrChess native engine via UCI (see [WintrChessAdapter]).
  static const String wintrChess = 'wintrchess';

  /// External Stockfish binary via UCI (see [UciEngineAdapter]).
  static const String stockfishUci = 'stockfish-uci';
}

/// Fast built-in estimator: material + light positional terms.
///
/// * Material (cp): P=100, N=320, B=330, R=500, Q=900, K=0.
/// * Positional: +2 per minor/major piece on the central 4x4 squares
///   (c3–f6), +3 per pawn on the central 16, small tempo nudge (+5 White).
///
/// Parses only the piece-placement field of FEN; anything unparseable
/// yields `supported: false` (never a fabricated 0.00). Variant JSON is
/// accepted when it contains a `fen` field; boards without FEN interop
/// are out of scope and unsupported. [source] is always `'heuristic'`.
class HeuristicEvaluator implements PositionEvaluator {
  /// Piece values in centipawns.
  static const Map<String, int> pieceValues = <String, int>{
    'p': 100,
    'n': 320,
    'b': 330,
    'r': 500,
    'q': 900,
    'k': 0,
  };

  @override
  bool get supportsVariant => true;

  @override
  String get name => 'heuristic';

  @override
  Future<EvalResult> evaluate(String fenOrVariantJson) async {
    final placement = _extractPlacement(fenOrVariantJson);
    if (placement == null) {
      return EvalResult.unsupported(EngineSources.heuristic);
    }
    return EvalResult(
      scoreCp: _scorePlacement(placement),
      source: EngineSources.heuristic,
    );
  }

  /// Extracts the FEN piece-placement field from FEN or variant JSON.
  /// Returns null when no parseable placement is found.
  static String? _extractPlacement(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('{')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          final fen = decoded['fen'];
          if (fen is String) return _placementOf(fen);
          // Chaotic boards without FEN interop are out of scope.
          return null;
        }
        return null;
      } catch (error) {
        // Malformed variant JSON: degrade to unsupported, but log the
        // decode failure so a corrupt game record stays diagnosable
        // instead of silently yielding "no placement".
        log(
          'HeuristicEvaluator: unparseable variant JSON — treating the '
          'position as unsupported',
          name: 'heuristic-evaluator',
          error: error,
        );
        return null;
      }
    }
    return _placementOf(trimmed);
  }

  static String? _placementOf(String fen) {
    final placement = fen.trim().split(RegExp(r'\s+')).first;
    if (!placement.contains('/')) return null;
    final rows = placement.split('/');
    if (rows.length != 8) return null;
    return placement;
  }

  /// Scores a validated placement field, White-relative centipawns.
  static int _scorePlacement(String placement) {
    var score = 5; // tempo nudge for White
    final rows = placement.split('/');
    for (var r = 0; r < 8; r++) {
      var file = 0;
      for (var i = 0; i < rows[r].length; i++) {
        final ch = rows[r][i];
        final digit = int.tryParse(ch);
        if (digit != null) {
          file += digit;
          continue;
        }
        final lower = ch.toLowerCase();
        final value = pieceValues[lower];
        if (value == null) continue; // ignore unknown glyphs
        final isWhite = ch == ch.toUpperCase();
        // Central 4x4 (files c–f, ranks 3–6 => rows 2..5 in FEN order).
        final central =
            file >= 2 && file <= 5 && r >= 2 && r <= 5;
        var bonus = 0;
        if (central) bonus = lower == 'p' ? 3 : 2;
        final signed = (value + bonus) * (isWhite ? 1 : -1);
        score += signed;
        file++;
      }
    }
    return score;
  }
}

/// Mate-score anchor (White-relative centipawns) for UCI `score mate`.
///
/// Mate-in-m maps to `±(mateScoreBase − 100·|m|)`, keeping mates decisive
/// under `quality.dart` thresholds while preserving faster-mate ordering.
/// Must stay well above the `> 500` super-blunder threshold.
const int mateScoreBase = 100000;

/// Side-to-move-relative score parsed from one UCI `info` line.
class _InfoScore {
  /// Search depth the score was reported at.
  final int depth;

  /// Score in centipawns, side-to-move-relative.
  final int scoreStm;

  /// Creates a parsed score.
  const _InfoScore(this.depth, this.scoreStm);
}

/// Generic UCI engine child-process adapter.
///
/// Implements the public UCI protocol (well-documented open standard —
/// no upstream-specific behavior is assumed):
///
/// 1. Spawn: `Process.start(executablePath, args)`.
/// 2. Handshake: send `uci`, await `uciok` (reject lines before timeout).
/// 3. Options: `setoption name <k> value <v>` for [options], then
///    `isready` / `readyok`.
/// 4. Evaluate: `position fen <fen>` then `go depth <N>`; parse
///    `info depth <d> ... score cp <v> ...` (keep latest at max depth) and
///    terminal `bestmove <uci>`.
/// 5. Shutdown: send `quit`, cancel subscriptions, kill on timeout.
///
/// Score convention: UCI `score` is side-to-move-relative; this adapter
/// converts to the White-relative [EvalResult.scoreCp] using the FEN
/// side field. `score mate <m>` maps to `±(100000 − 100·|m|)` (sign favors
/// the mating side), keeping mates decisive under `quality.dart`
/// thresholds while preserving faster-mate ordering.
///
/// Variant JSON input yields `supported: false` — a standard engine must
/// never silently score a mutated position as if it were legal chess.
///
/// Desktop-only: `dart:io` processes are unavailable on Flutter Web;
/// callers must fall back to [HeuristicEvaluator] there.
class UciEngineAdapter implements PositionEvaluator {
  /// Engine binary path (e.g. `/usr/bin/stockfish`).
  ///
  /// When [executablePathResolver] is set, [connect] calls it first and
  /// spawns the resolved path instead (lazy first-run extraction, see
  /// `embedded_engine.dart`). An explicit non-empty [executablePath] plus
  /// a resolver is a programmer error only when both disagree — the
  /// resolver wins and the static path is kept for logs.
  final String executablePath;

  /// Optional lazy resolver for the engine binary, consulted by [connect].
  ///
  /// Null means [executablePath] is used directly. Subclasses such as
  /// `StockfishEvaluator` pass `EmbeddedEngine.resolveBinary` here so the
  /// bundled asset is extracted on first run instead of at construction.
  final Future<String> Function()? executablePathResolver;

  /// Extra argv for the engine process.
  final List<String> args;

  /// UCI options applied at connect (`name -> value`).
  final Map<String, String> options;

  /// Search depth per evaluation.
  final int defaultDepth;

  /// Engine greeting name used for logs.
  final String engineName;

  /// Source tag reported on results (configurable per subclass).
  final String source;

  Process? _process;
  StreamSubscription<String>? _stderrSub;
  StreamSubscription<String>? _stdoutSub;

  /// In-flight [connect] future, shared by concurrent callers so two
  /// overlapping connects cannot spawn (and leak) two processes.
  Future<void>? _connecting;

  /// Lines received from the engine (broadcast internally).
  ///
  /// Recreated by [connect] when a previous [dispose] closed it, so an
  /// adapter may be disposed and reconnected.
  StreamController<String> _lines = StreamController<String>.broadcast();

  /// Guards against overlapping evaluations on one process.
  bool _evaluating = false;

  /// Creates an adapter. Does not spawn anything until [connect].
  UciEngineAdapter({
    required this.executablePath,
    this.executablePathResolver,
    this.args = const <String>[],
    this.options = const <String, String>{},
    this.defaultDepth = 12,
    this.engineName = 'uci-engine',
    this.source = EngineSources.stockfishUci,
  });

  @override
  bool get supportsVariant => false;

  @override
  String get name => engineName;

  /// True after [connect] until the process exits or [dispose] is called.
  bool get isConnected => _process != null;

  /// Spawns the engine process and performs the UCI handshake.
  ///
  /// The spawned binary is `await executablePathResolver()` when a
  /// resolver was provided, else [executablePath].
  ///
  /// Throws [ProcessException] when the binary cannot start and
  /// [TimeoutException] when `uciok`/`readyok` never arrive. Either way
  /// no half-connected state is left behind ([dispose] runs on failure).
  Future<void> connect({Duration timeout = const Duration(seconds: 10)}) {
    if (isConnected) return Future<void>.value();
    final pending = _connecting;
    if (pending != null) return pending;
    late final Future<void> tracked;
    tracked = _connect(timeout).whenComplete(() {
      if (identical(_connecting, tracked)) _connecting = null;
    });
    _connecting = tracked;
    return tracked;
  }

  /// Body of [connect]; memoized through [_connecting] so concurrent callers
  /// await the same process instead of spawning a second one.
  Future<void> _connect(Duration timeout) async {
    if (isConnected) return;
    if (_lines.isClosed) {
      _lines = StreamController<String>.broadcast();
    }
    final executable = executablePathResolver != null
        ? await executablePathResolver!()
        : executablePath;
    final process = await Process.start(executable, args);
    _process = process;
    final lines = _lines;
    _stderrSub = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            final trimmed = line.trimRight();
            if (trimmed.isEmpty) return;
            // Engine stderr carries warnings and errors: drain the pipe
            // (a full stderr pipe would deadlock the child) AND surface
            // the content instead of discarding it silently.
            log('$engineName: $trimmed', name: 'engine-stderr');
          },
          onError: (Object error) {
            log(
              '$engineName stderr stream error',
              name: 'engine-stderr',
              error: error,
            );
          },
        );
    _stdoutSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          lines.add,
          onError: (Object error) {
            log(
              '$engineName stdout stream error',
              name: 'engine-stdout',
              error: error,
            );
          },
          // Closing the line controller on stdout EOF makes any in-flight
          // `evaluate` finish immediately instead of waiting out its timer.
          onDone: () {
            if (!lines.isClosed) unawaited(lines.close());
          },
        );
    // Detect an engine that dies on its own (mismatched binary, OOM, killed,
    // AV quarantine). Without this the adapter would stay "connected" forever
    // and every evaluate would write into a dead stdin, then wait out the
    // whole search timeout before reporting a silent `unsupported`.
    unawaited(process.exitCode.then((code) {
      if (!identical(_process, process)) return;
      // The engine died on its own (a mismatched binary, OOM, kill, or
      // AV quarantine). [dispose] nulls [_process] before killing, so an
      // intentional teardown never reaches this branch. Surface the exit
      // code — previously the only trace of this event was a silent
      // `unsupported` on the next evaluate.
      log(
        '$engineName exited unexpectedly (code $code)',
        name: 'engine-adapter',
      );
      _process = null;
      final stderrSub = _stderrSub;
      final stdoutSub = _stdoutSub;
      _stderrSub = null;
      _stdoutSub = null;
      unawaited(stderrSub?.cancel());
      unawaited(stdoutSub?.cancel());
      if (!lines.isClosed) unawaited(lines.close());
    }));
    try {
      _send('uci');
      await _waitFor((l) => l.trim() == 'uciok', timeout, 'uciok');
      for (final entry in options.entries) {
        _send('setoption name ${entry.key} value ${entry.value}');
      }
      _send('isready');
      await _waitFor((l) => l.trim() == 'readyok', timeout, 'readyok');
    } catch (_) {
      await dispose();
      rethrow;
    }
  }

  @override
  Future<EvalResult> evaluate(
    String fenOrVariantJson, {
    int? depth,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!isConnected) {
      throw StateError('$engineName is not connected; call connect() first');
    }
    final fen = _extractFen(fenOrVariantJson);
    if (fen == null) {
      // Variant JSON or garbage: a standard engine must not score it.
      return EvalResult.unsupported(source);
    }
    if (_evaluating) {
      throw StateError('$engineName is already evaluating; '
          'evaluations are sequential per process');
    }
    _evaluating = true;
    try {
      final searchDepth = depth ?? defaultDepth;
      final whiteToMove = _whiteToMove(fen);
      _send('position fen $fen');
      _send('go depth $searchDepth');
      var bestCp = 0;
      var bestDepth = -1;
      String? bestMove;
      var sawScore = false;
      var sawBestmove = false;

      // Total wall-clock deadline for the whole search. A per-gap stream
      // timeout never fires while `info` output keeps trickling in, so a
      // hard timer (raced against the terminal `bestmove`) is the only
      // reliable budget.
      final finished = Completer<void>();
      final timer = Timer(timeout, () {
        if (!finished.isCompleted) finished.complete();
      });
      final subscription = _lines.stream.listen(
        (line) {
          final trimmed = line.trim();
          if (trimmed.startsWith('info ')) {
            final parsed = _parseInfoScore(trimmed);
            if (parsed != null && parsed.depth >= bestDepth) {
              bestDepth = parsed.depth;
              bestCp = parsed.scoreStm;
              sawScore = true;
            }
          } else if (trimmed.startsWith('bestmove ')) {
            final parts = trimmed.split(RegExp(r'\s+'));
            if (parts.length > 1 && parts[1] != '(none)') {
              bestMove = parts[1];
            }
            sawBestmove = true;
            if (!finished.isCompleted) finished.complete();
          }
        },
        onError: (Object _) {
          if (!finished.isCompleted) finished.complete();
        },
        onDone: () {
          if (!finished.isCompleted) finished.complete();
        },
      );
      try {
        await finished.future;
      } finally {
        timer.cancel();
        await subscription.cancel();
      }

      if (_process == null) {
        // The process exited mid-search (see the exitCode watcher in
        // [connect]); fail loudly rather than returning a stale half score.
        throw StateError('$engineName exited during evaluation');
      }

      if (!sawBestmove) {
        // Deadline hit (or the engine died) mid-search. Stop the search and
        // re-synchronize with `isready`/`readyok` so late `info`/`bestmove`
        // lines from the aborted search cannot poison the next evaluation.
        await _stopAndResync();
      }

      if (!sawScore) {
        // Engine stayed silent: report unsupported, never a fake 0.00.
        return EvalResult.unsupported(source);
      }
      final whiteCp = whiteToMove ? bestCp : -bestCp;
      return EvalResult(
        scoreCp: whiteCp,
        bestMoveUci: bestMove,
        depth: bestDepth,
        source: source,
      );
    } finally {
      _evaluating = false;
    }
  }

  /// Aborts an in-flight search and blocks until the engine is idle again.
  ///
  /// Sends `stop` then `isready`, and waits for `readyok` (skipping any late
  /// `bestmove`/`info` lines from the aborted search). Never throws; an
  /// unresponsive engine is left for [dispose] to reap.
  Future<void> _stopAndResync() async {
    if (_process == null) return;
    try {
      _send('stop');
      _send('isready');
    } on Object {
      // Broken pipe / already-exiting process: nothing to resync.
      return;
    }
    try {
      await _waitFor(
        (l) => l.trim() == 'readyok',
        const Duration(seconds: 5),
        'readyok (post-stop resync)',
      );
    } on Object {
      // Engine unresponsive after stop; dispose()/kill handles teardown.
    }
  }

  /// Sends `quit`, tears down the process, and releases resources.
  ///
  /// Idempotent. Closes stdin, waits (bounded) for the process to exit,
  /// escalates to SIGKILL when it does not die promptly, cancels the
  /// stdout/stderr subscriptions, and closes the line controller. [connect]
  /// recreates the controller, so an adapter may be reused after dispose.
  Future<void> dispose() async {
    final process = _process;
    final stderrSub = _stderrSub;
    final stdoutSub = _stdoutSub;
    _process = null;
    _stderrSub = null;
    _stdoutSub = null;
    await stderrSub?.cancel();
    await stdoutSub?.cancel();
    if (!_lines.isClosed) {
      await _lines.close();
    }
    if (process == null) return;
    try {
      process.stdin.writeln('quit');
      await process.stdin.flush();
      await process.stdin.close();
    } catch (_) {
      // Process already gone; fall through to the kill/escalation below.
    }
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      // SIGTERM ignored: escalate, then give the OS one bounded grace period.
      process.kill(ProcessSignal.sigkill);
      try {
        await process.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        // Reaping is now up to the OS; nothing further we can do.
      }
    }
  }

  /// Writes one command line to the engine.
  ///
  /// Swallows broken-pipe/closed-stdin errors; the exitCode watcher installed
  /// by [connect] tears the connection down and surfaces the exit.
  void _send(String command) {
    final process = _process;
    if (process == null) return;
    try {
      process.stdin.writeln(command);
    } on Object {
      // Process already gone; the watcher handles teardown.
    }
  }

  /// Waits until a line satisfies [test], rejecting on [timeout].
  Future<void> _waitFor(
    bool Function(String) test,
    Duration timeout,
    String what,
  ) async {
    await _lines.stream
        .timeout(timeout,
            onTimeout: (sink) => sink.addError(
                TimeoutException('Timed out waiting for $what', timeout)))
        .firstWhere(test);
  }

  /// Returns the input when it is a standard FEN string, else null.
  ///
  /// Variant JSON (starts with `{`) is never forwarded to the engine.
  static String? _extractFen(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty || trimmed.startsWith('{')) return null;
    // Minimal FEN shape check: placement + side-to-move fields.
    final fields = trimmed.split(RegExp(r'\s+'));
    if (fields.length < 2) return null;
    if (!fields[0].contains('/') || fields[0].split('/').length != 8) {
      return null;
    }
    if (fields[1] != 'w' && fields[1] != 'b') return null;
    return trimmed;
  }

  /// Reads the side-to-move field of a validated FEN.
  static bool _whiteToMove(String fen) =>
      fen.split(RegExp(r'\s+'))[1] == 'w';

  /// Parses `score cp|mate` plus `depth` from an `info` line.
  ///
  /// Tokenizes the whole line before deciding, so `depth` is picked up
  /// wherever it appears (UCI does not guarantee `depth` precedes `score`).
  /// Bound-only scores (`... score cp X upperbound|lowerbound`) are not
  /// exact and are skipped rather than reported as if decisive. Returns the
  /// score side-to-move-relative with its depth, or null when the line
  /// carries no usable exact score.
  static _InfoScore? _parseInfoScore(String line) {
    final tokens = line.split(RegExp(r'\s+'));
    var depth = 0;
    int? cpScore;
    int? mateScore;
    for (var i = 0; i < tokens.length; i++) {
      if (tokens[i] == 'depth' && i + 1 < tokens.length) {
        depth = int.tryParse(tokens[i + 1]) ?? depth;
      } else if (tokens[i] == 'score' && i + 2 < tokens.length) {
        final kind = tokens[i + 1];
        final value = int.tryParse(tokens[i + 2]);
        if (value == null) continue;
        // A bounded score is not exact; ignore it instead of presenting a
        // bound as the search result.
        final bound = i + 3 < tokens.length ? tokens[i + 3] : null;
        if (bound == 'upperbound' || bound == 'lowerbound') continue;
        if (kind == 'cp') {
          cpScore = value;
        } else if (kind == 'mate') {
          mateScore = value;
        }
      }
    }
    if (cpScore != null) return _InfoScore(depth, cpScore);
    if (mateScore != null) {
      // Mate-in-m favors the side to move when m > 0. Clamp the magnitude
      // at 0: absurd mate distances (|m| > 1000) must never flip the sign
      // of the anchor. The sign still tracks the mating side.
      final magnitude = (mateScoreBase - 100 * mateScore.abs())
          .clamp(0, mateScoreBase);
      final signed = mateScore > 0 ? magnitude : -magnitude;
      return _InfoScore(depth, signed);
    }
    return null;
  }
}

/// WintrChess native-engine adapter (RESERVED, not the review path).
///
/// WintrChess (github.com/wintrcat/wintrchess, branch `master`) is a
/// TypeScript chess **web app** (Express + MongoDB + chess.js server,
/// React + react-chessboard client) — it ships **no UCI engine binary**.
/// Game review therefore does NOT go through this class; it goes through
/// [StockfishEvaluator] (position evals) + `WintrReviewService`
/// (`wintr_review.dart`, WintrChess-inspired review pipeline).
///
/// This subclass is reserved for a future WintrChess-native UCI binary
/// **if upstream ever ships one**. Do not wire it into the review flow
/// until `wintrchess_notes.md` confirms a UCI-speaking binary exists.
/// [HeuristicEvaluator] remains the fallback meanwhile.
class WintrChessAdapter extends UciEngineAdapter {
  /// Default binary name to look for on PATH / in the bundle directory.
  static const String defaultBinaryName = 'wintrchess';

  /// Human build instructions hook (summary; full notes in markdown).
  ///
  /// Expected to produce a UCI-speaking binary named [defaultBinaryName].
  /// Until upstream confirms the protocol, treat WintrChess output as
  /// provisional and keep [HeuristicEvaluator] as the fallback.
  static const String buildInstructions =
      'See lib/src/review/wintrchess_notes.md for build requirements. '
      'Expected output: a UCI-speaking `wintrchess` binary.';

  /// Creates an adapter pointing at a WintrChess binary.
  WintrChessAdapter({
    super.executablePath = defaultBinaryName,
    super.args,
    super.options,
    super.defaultDepth,
    super.engineName = 'wintrchess',
  }) : super(source: EngineSources.wintrChess);
}
