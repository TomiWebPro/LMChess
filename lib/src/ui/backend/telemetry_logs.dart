/// Telemetry logs backing the stats and review screens.
///
/// Pure-Dart per-`ProviderScope` in-memory stores: [StatsLog] (turn/result
/// records mirrored into a real stats `EventStore`), [QualityLog]
/// (per-ply quality marks), [ReviewLog] (finished standard games) and
/// [VariantReviewLog] (chaotic-variant replay records). The Riverpod
/// providers for these stores live in
/// `../providers/backend_providers.dart` (`statsLogProvider`,
/// `qualityLogProvider`, `reviewLogProvider`, `variantReviewLogProvider`),
/// alongside the thin `ChangeNotifier` adapters (`statsLogListenable` and
/// friends) that widgets use with `ListenableBuilder`.
/// Also hosts the turn-attribution helpers ([PendingTurn],
/// [logTurnOutcome], [logGameResults]) and the stats error-category mapper
/// ([statsErrorCategory]).
///
/// [ReviewLog] stores [ReviewGame] records, which are defined alongside the
/// review plumbing in `review_resolver.dart` — this file imports that type
/// rather than redefining it.
/// Talks to: `stats/event_log.dart` (mirror store), `review_resolver.dart` (`ReviewGame`); exposes `statsLogProvider` et al.
/// Never imports: `package:flutter` widgets/material, `storage/local_store`, `hive` — in-memory per-`ProviderScope` logs.
library;

import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../agent/agent_runner.dart';
import '../../llm/validation.dart';
import '../../stats/event_log.dart' as stats_log;
import '../../variant/variant_replay.dart';
import 'review_resolver.dart';

/// In-memory stats-backend log, isolated per `ProviderScope`.
///
/// The activity panel's [ActivityEvent]s carry no `agentId`, so
/// [AgentMetrics.compute] would skip them all. Screens therefore log one
/// [stats_log.GameEventRecord] per turn here with the exact payload
/// contract `metrics.dart` consumes (`agentId`, `modelKey`, `latencyMs`,
/// `inputTokens`/`outputTokens`, `color`, `mode`, boolean flags,
/// `countAsTurn: false` on result markers). The stats screen filters these
/// records and aggregates them — the sample constants it used before are
/// gone.
///
/// Every record is also appended to a real [stats_log.InMemoryEventStore]
/// (idempotent by UUID key) — [store] — so consumers exercise the actual
/// [stats_log.EventStore] contract; [addListener] listeners and the
/// [changes] stream fire after every append so listening screens re-render
/// (via the `Listenable` adapters in `../providers/backend_providers.dart`)
/// when a game finishes. Not durable
/// (in-memory, per `ProviderScope`); persistence owns the Hive boxes.
///
/// Create one via `statsLogProvider` in
/// `../providers/backend_providers.dart`; tests may build a fresh instance
/// to seed before pumping and hand it to the same provider override.
class StatsLog {
  final List<stats_log.GameEventRecord> _records =
      <stats_log.GameEventRecord>[];
  final Map<String, int> _seqByGame = <String, int>{};
  final stats_log.InMemoryEventStore _store = stats_log.InMemoryEventStore();
  final List<void Function()> _listeners = <void Function()>[];
  final StreamController<void> _changes = StreamController<void>.broadcast();
  static const Uuid _uuid = Uuid();

  /// Upper bound on retained in-memory records (oldest evicted first).
  ///
  /// The event-store mirror is capped independently; this keeps a long
  /// session with many games/tournaments from growing without limit.
  static const int maxRetainedRecords = 20000;

  /// All logged records (unmodifiable, insertion order).
  List<stats_log.GameEventRecord> get records =>
      List<stats_log.GameEventRecord>.unmodifiable(_records);

  /// The event-store mirror every record is also appended to.
  ///
  /// Read via [stats_log.EventStore.listAll]/`listByGame`/
  /// `listByTournament`; appends are idempotent by [GameEventRecord.key]
  /// so a replayed flush can never double-count.
  stats_log.EventStore get store => _store;

  /// Broadcast bump after every append and on [clear] (see the library docs).
  ///
  /// Pure-Dart notification surface: widgets must not listen here directly
  /// but use the `statsLogListenable` adapter in
  /// `../providers/backend_providers.dart` (a `ListenableBuilder`-ready
  /// view over [addListener]).
  Stream<void> get changes => _changes.stream;

  /// Subscribes a synchronous listener, fired by [_bump] on every mutation.
  void addListener(void Function() listener) => _listeners.add(listener);

  /// Unsubscribes a listener previously added via [addListener].
  void removeListener(void Function() listener) => _listeners.remove(listener);

  /// Releases the broadcast [changes] stream; the provider calls this on
  /// scope disposal. The store must not be used afterwards.
  void dispose() {
    _listeners.clear();
    _changes.close();
  }

  /// Clears the log + store (used by watch/arena restarts).
  void clear() {
    _records.clear();
    _seqByGame.clear();
    _store.clear();
    _bump();
  }

  void _bump() {
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
    if (!_changes.isClosed) {
      _changes.add(null);
    }
  }

  int _nextSeq(String gameId) {
    final next = (_seqByGame[gameId] ?? 0) + 1;
    _seqByGame[gameId] = next;
    return next - 1;
  }

  /// Appends [record] to the log and mirrors it into [store].
  void _append(stats_log.GameEventRecord record) {
    _records.add(record);
    if (_records.length > maxRetainedRecords) {
      _records.removeRange(0, _records.length - maxRetainedRecords);
    }
    _store.append(record);
    _bump();
  }

  /// Logs one turn for [agentId] with metrics flags.
  void logTurn({
    required String gameId,
    required String agentId,
    String? tournamentId,
    String modelKey = '',
    String color = 'white',
    String mode = 'standard',
    int? latencyMs,
    int? inputTokens,
    int? outputTokens,
    bool parsedMove = false,
    bool validTool = false,
    bool legal = false,
    bool illegalAttempt = false,
    bool unparseable = false,
    bool missingTool = false,
    bool providerError = false,
    bool timeout = false,
    bool fallback = false,
  }) {
    _append(
      stats_log.GameEventRecord(
        key: _uuid.v4(),
        gameId: gameId,
        tournamentId: tournamentId,
        seq: _nextSeq(gameId),
        type: fallback
            ? 'turn.fallback'
            : (legal ? 'turn.completed' : 'turn.failed'),
        payloadJson: <String, Object?>{
          'agentId': agentId,
          'modelKey': modelKey,
          'color': color,
          'mode': mode,
          'latencyMs': ?latencyMs,
          'inputTokens': ?inputTokens,
          'outputTokens': ?outputTokens,
          'parsedMove': parsedMove,
          'validTool': validTool,
          'legal': legal,
          'illegalAttempt': illegalAttempt,
          'unparseable': unparseable,
          'missingTool': missingTool,
          'providerError': providerError,
          'timeout': timeout,
          'fallback': fallback,
        },
      ),
    );
  }

  /// Logs a result-only marker for [agentId] (never counts as a turn).
  ///
  /// [result] is `'win'`, `'loss'` or `'draw'` from that agent's
  /// perspective — the only values [AgentMetrics.compute] counts.
  void logGameEnd({
    required String gameId,
    required String agentId,
    String? tournamentId,
    String modelKey = '',
    required String result,
    String color = 'white',
    String mode = 'standard',
  }) {
    _append(
      stats_log.GameEventRecord(
        key: _uuid.v4(),
        gameId: gameId,
        tournamentId: tournamentId,
        seq: _nextSeq(gameId),
        type: 'game.end',
        payloadJson: <String, Object?>{
          'agentId': agentId,
          'modelKey': modelKey,
          'result': result,
          'color': color,
          'mode': mode,
          'countAsTurn': false,
        },
      ),
    );
  }
}

/// Maps an [AgentTurnResult] to [StatsLog.logTurn] metrics flags.
///
/// Per-scope per-ply quality marks backing the stats quality chart.
///
/// Review appends the UI marks (`'!!'`…`'??'`) it derives from
/// [classify] here (overwriting per game reviewed); stats renders the
/// distribution and re-renders via its listener (see [addListener]; widgets
/// use the `qualityLogListenable` adapter). Empty until the first review
/// runs — the chart shows a wiring-point empty state meanwhile. A future
/// storage wiring will move these to the `evaluations` box keyed by
/// `<game>:<seq>`. Create one via `qualityLogProvider` in
/// `../providers/backend_providers.dart`.
class QualityLog {
  List<String> _marks = const <String>[];
  final List<void Function()> _listeners = <void Function()>[];
  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Current marks (unmodifiable).
  List<String> get marks => List<String>.unmodifiable(_marks);

  /// Broadcast bump after [setAll]/[clear] (see the library docs).
  ///
  /// Widgets use the `qualityLogListenable` adapter in
  /// `../providers/backend_providers.dart` instead of listening here.
  Stream<void> get changes => _changes.stream;

  /// Subscribes a synchronous listener, fired by [_bump] on every mutation.
  void addListener(void Function() listener) => _listeners.add(listener);

  /// Unsubscribes a listener previously added via [addListener].
  void removeListener(void Function() listener) => _listeners.remove(listener);

  /// Releases the broadcast [changes] stream; the provider calls this on
  /// scope disposal. The store must not be used afterwards.
  void dispose() {
    _listeners.clear();
    _changes.close();
  }

  /// Replaces the marks with [marks] (one review's distribution).
  void setAll(List<String> marks) {
    _marks = List<String>.of(marks);
    _bump();
  }

  /// Clears the marks.
  void clear() {
    _marks = const <String>[];
    _bump();
  }

  void _bump() {
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
    if (!_changes.isClosed) {
      _changes.add(null);
    }
  }
}

/// Per-scope review-game log (latest-finished-first, capped).
///
/// Play/watch record their finished games here; arena records each
/// completed standard tournament game; review reads the latest (or a
/// picked) entry and re-renders via its listener (see [ReviewLog.addListener];
/// widgets use the `reviewLogListenable` adapter). Cap of 20 keeps memory
/// bounded; re-recording an id replaces it. Create one via
/// `reviewLogProvider` in `../providers/backend_providers.dart`.
class ReviewLog {
  final List<ReviewGame> _games = <ReviewGame>[];
  final List<void Function()> _listeners = <void Function()>[];
  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Logged games, latest first (unmodifiable).
  List<ReviewGame> get games => List<ReviewGame>.unmodifiable(_games);

  /// Latest game, or `null` when nothing has been recorded yet.
  ReviewGame? get latest => _games.isEmpty ? null : _games.first;

  /// Broadcast bump after [record]/[clear] (see the library docs).
  ///
  /// Widgets use the `reviewLogListenable` adapter in
  /// `../providers/backend_providers.dart` instead of listening here.
  Stream<void> get changes => _changes.stream;

  /// Subscribes a synchronous listener, fired by [_bump] on every mutation.
  void addListener(void Function() listener) => _listeners.add(listener);

  /// Unsubscribes a listener previously added via [addListener].
  void removeListener(void Function() listener) => _listeners.remove(listener);

  /// Releases the broadcast [changes] stream; the provider calls this on
  /// scope disposal. The store must not be used afterwards.
  void dispose() {
    _listeners.clear();
    _changes.close();
  }

  /// Records [game], replacing any same-id entry and capping at 20.
  void record(ReviewGame game) {
    _games.removeWhere((g) => g.id == game.id);
    _games.insert(0, game);
    if (_games.length > 20) {
      _games.removeRange(20, _games.length);
    }
    _bump();
  }

  /// Clears the log.
  void clear() {
    _games.clear();
    _bump();
  }

  void _bump() {
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
    if (!_changes.isClosed) {
      _changes.add(null);
    }
  }
}

/// Per-scope log of chaotic-variant replay records (latest first, capped).
///
/// Kept separate from [ReviewLog] because variant records are JSON/board-chain
/// shaped and must not be forced into the FEN-based standard review model.
/// Create one via `variantReviewLogProvider` in
/// `../providers/backend_providers.dart`.
class VariantReviewLog {
  final List<VariantGameRecord> _games = <VariantGameRecord>[];
  final List<void Function()> _listeners = <void Function()>[];
  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Maximum retained games (memory bound).
  static const int maxGames = 20;

  /// Logged games, latest first (unmodifiable).
  List<VariantGameRecord> get games =>
      List<VariantGameRecord>.unmodifiable(_games);

  /// Latest game, or `null` when nothing has been recorded yet.
  VariantGameRecord? get latest => _games.isEmpty ? null : _games.first;

  /// Looks up a game by id, or `null`.
  VariantGameRecord? byId(String id) {
    for (final game in _games) {
      if (game.id == id) return game;
    }
    return null;
  }

  /// Broadcast bump after [record]/[clear].
  ///
  /// Widgets use the `variantReviewLogListenable` adapter in
  /// `../providers/backend_providers.dart` instead of listening here.
  Stream<void> get changes => _changes.stream;

  /// Subscribes a synchronous listener, fired by [_bump] on every mutation.
  void addListener(void Function() listener) => _listeners.add(listener);

  /// Unsubscribes a listener previously added via [addListener].
  void removeListener(void Function() listener) => _listeners.remove(listener);

  /// Releases the broadcast [changes] stream; the provider calls this on
  /// scope disposal. The store must not be used afterwards.
  void dispose() {
    _listeners.clear();
    _changes.close();
  }

  /// Records [game], replacing any same-id entry and capping at [maxGames].
  void record(VariantGameRecord game) {
    _games.removeWhere((g) => g.id == game.id);
    _games.insert(0, game);
    if (_games.length > maxGames) {
      _games.removeRange(maxGames, _games.length);
    }
    _bump();
  }

  /// Clears the log.
  void clear() {
    _games.clear();
    _bump();
  }

  void _bump() {
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
    if (!_changes.isClosed) {
      _changes.add(null);
    }
  }
}

/// Maps an [AgentTurnResult] to [StatsLog.logTurn] metrics flags.
///
/// NOTE: the Riverpod providers for these stores
/// (`statsLogProvider`, `qualityLogProvider`, `reviewLogProvider`,
/// `variantReviewLogProvider`) live in
/// `../providers/backend_providers.dart` so this file stays pure Dart.
///
/// Success → `parsedMove`/`validTool`/`legal`. Failure kinds map to their
/// metrics flags: `illegalMove` → `illegalAttempt`, `timeout` → `timeout`,
/// `providerError`/`rateLimit` → `providerError`,
/// `unparseableResponse`/`malformedArgs` → `unparseable`,
/// `missingToolCall`/`incompleteResponse`/`cancelled`/`internal` →
/// `missingTool`. [fallback] marks orchestrator-applied seeded fallbacks
/// explicitly (the move is legal but unattributed — see `fallbackRate`).
/// Token counts come from the runner's last usage event ([MockProvider]
/// scripted turns report 128 in / 16 out).
void logTurnOutcome({
  required StatsLog log,
  required String gameId,
  required String agentId,
  String? tournamentId,
  String modelKey = '',
  String color = 'white',
  String mode = 'standard',
  required AgentTurnResult result,
  bool fallback = false,
}) {
  final legal = result.isSuccess;
  var illegalAttempt = false;
  var unparseable = false;
  var missingTool = false;
  var providerError = false;
  var timeout = false;
  final kind = result.outcome.kind;
  if (!legal) {
    switch (kind) {
      case FailureKind.illegalMove:
        illegalAttempt = true;
      case FailureKind.timeout:
        timeout = true;
      case FailureKind.providerError:
      case FailureKind.rateLimit:
      case FailureKind.authError:
        providerError = true;
      case FailureKind.unparseableResponse:
      case FailureKind.malformedArgs:
        unparseable = true;
      case FailureKind.missingToolCall:
      case FailureKind.incompleteResponse:
      case FailureKind.cancelled:
      case FailureKind.internal:
      case FailureKind.valid:
        missingTool = true;
    }
  }
  log.logTurn(
    gameId: gameId,
    agentId: agentId,
    tournamentId: tournamentId,
    modelKey: modelKey,
    color: color,
    mode: mode,
    latencyMs: result.latencyMs,
    inputTokens: result.usage?.inputTokens,
    outputTokens: result.usage?.outputTokens,
    parsedMove: legal,
    validTool: legal,
    legal: legal,
    illegalAttempt: illegalAttempt,
    unparseable: unparseable,
    missingTool: missingTool,
    providerError: providerError,
    timeout: timeout,
    fallback: fallback,
  );
}

/// Logs per-agent result markers for a finished game.
///
/// [outcome] is the `1-0`/`0-1`/`1/2-1/2` score string; each side gets the
/// `'win'`/`'loss'`/`'draw'` value [AgentMetrics.compute] counts (from
/// that agent's perspective). `'*'` (aborted/undecided) logs nothing — an
/// abandoned game is not evidence of skill.
void logGameResults({
  required StatsLog log,
  required String gameId,
  required String whiteAgentId,
  required String blackAgentId,
  String? tournamentId,
  String whiteModelKey = '',
  String blackModelKey = '',
  String mode = 'standard',
  required String outcome,
}) {
  switch (outcome) {
    case '1-0':
      log.logGameEnd(
        gameId: gameId,
        agentId: whiteAgentId,
        tournamentId: tournamentId,
        modelKey: whiteModelKey,
        result: 'win',
        color: 'white',
        mode: mode,
      );
      log.logGameEnd(
        gameId: gameId,
        agentId: blackAgentId,
        tournamentId: tournamentId,
        modelKey: blackModelKey,
        result: 'loss',
        color: 'black',
        mode: mode,
      );
    case '0-1':
      log.logGameEnd(
        gameId: gameId,
        agentId: whiteAgentId,
        tournamentId: tournamentId,
        modelKey: whiteModelKey,
        result: 'loss',
        color: 'white',
        mode: mode,
      );
      log.logGameEnd(
        gameId: gameId,
        agentId: blackAgentId,
        tournamentId: tournamentId,
        modelKey: blackModelKey,
        result: 'win',
        color: 'black',
        mode: mode,
      );
    case '1/2-1/2':
      log.logGameEnd(
        gameId: gameId,
        agentId: whiteAgentId,
        tournamentId: tournamentId,
        modelKey: whiteModelKey,
        result: 'draw',
        color: 'white',
        mode: mode,
      );
      log.logGameEnd(
        gameId: gameId,
        agentId: blackAgentId,
        tournamentId: tournamentId,
        modelKey: blackModelKey,
        result: 'draw',
        color: 'black',
        mode: mode,
      );
    default:
      break;
  }
}

/// Maps one [stats_log.GameEventRecord] to the stats error vocabulary.
///
/// Returns one of `'none'`, `'illegal'`, `'timeout'`, `'parse'` or
/// `'engine'` — the exact label set the stats screen's error-category
/// chart renders. Precedence when a turn carries several flags: `timeout`
/// (a flagged turn is the clearest terminal fault), then `illegalAttempt`
/// → `illegal`, then `unparseable`/`missingTool` → `parse` (the model
/// output was unusable), then `providerError` → `engine`. Result markers
/// and clean turns map to `'none'`.
String statsErrorCategory(stats_log.GameEventRecord record) {
  final payload = record.payloadJson;
  bool flag(String key) => payload[key] == true;
  if (flag('timeout')) return 'timeout';
  if (flag('illegalAttempt')) return 'illegal';
  if (flag('unparseable') || flag('missingTool')) return 'parse';
  if (flag('providerError')) return 'engine';
  return 'none';
}

/// One turn's stats-backend attribution, buffered per game and flushed at
/// game end (so undone or abandoned moves never pollute aggregates).
///
/// Human moves carry no runner result and are logged as clean legal turns;
/// AI moves carry their [AgentTurnResult] and go through [logTurnOutcome]
/// (failure-kind → metrics-flag mapping plus the explicit fallback mark).
class PendingTurn {
  /// Creates a pending turn record.
  const PendingTurn({
    required this.agentId,
    required this.modelKey,
    required this.color,
    required this.mode,
    this.result,
    this.fallback = false,
    this.human = false,
  });

  /// Agent id for metrics attribution (`'human'` for human moves).
  final String agentId;

  /// Model key for cost estimation (`'human'` for human moves).
  final String modelKey;

  /// `'white'` or `'black'` (metrics vocabulary).
  final String color;

  /// `'standard'` or `'chaotic'`.
  final String mode;

  /// Runner result for AI turns; `null` for human moves.
  final AgentTurnResult? result;

  /// Whether the orchestrator applied a seeded fallback this turn.
  final bool fallback;

  /// Whether this is a human move (logged as a clean legal turn).
  final bool human;

  /// Creates a human-move record.
  factory PendingTurn.human({String mode = 'standard'}) => PendingTurn(
    agentId: 'human',
    modelKey: 'human',
    color: 'white',
    mode: mode,
  );

  /// Creates an AI-turn record.
  factory PendingTurn.ai({
    required String agentId,
    required String modelKey,
    required String color,
    required String mode,
    required AgentTurnResult result,
    bool fallback = false,
  }) => PendingTurn(
    agentId: agentId,
    modelKey: modelKey,
    color: color,
    mode: mode,
    result: result,
    fallback: fallback,
  );

  /// Writes this turn to [log].
  void flush({
    required StatsLog log,
    required String gameId,
    String? tournamentId,
  }) {
    if (human || result == null) {
      log.logTurn(
        gameId: gameId,
        agentId: agentId,
        tournamentId: tournamentId,
        modelKey: modelKey,
        color: color,
        mode: mode,
        parsedMove: true,
        validTool: true,
        legal: true,
      );
      return;
    }
    logTurnOutcome(
      log: log,
      gameId: gameId,
      agentId: agentId,
      tournamentId: tournamentId,
      modelKey: modelKey,
      color: color,
      mode: mode,
      result: result!,
      fallback: fallback,
    );
  }
}
