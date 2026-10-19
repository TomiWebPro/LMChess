/// Turn orchestration: clocks, AI/human move intake, fallback, lifecycle and
/// the ordered game-event log.
///
/// This is the only file in the LLM/agent/game layers allowed to import
/// Flutter (`package:flutter/foundation.dart` for [ChangeNotifier]); the
/// providers, runner, clock and state model stay pure Dart.
///
/// Engine decoupling: the orchestrator never imports the chess/variant
/// engine. The position is an opaque [String] (FEN or variant JSON), legal
/// moves arrive explicitly via [setPosition], and position advancement after
/// a move goes through the injectable [PositionUpdater]. The engine/UI layer
/// is responsible for calling [setPosition] (new position + fresh legal list)
/// after every applied move — until then [_legalMoves] is empty and no
/// further turn may start.
///
/// Event ordering — persist-then-broadcast: [_emit] appends every [GameEvent]
/// to [eventLog] *before* adding it to the broadcast [events] stream, so a
/// subscriber that replays [eventLog] first can never miss or double-apply
/// an event. Each event carries a monotonic [GameEvent.seq] and a unique
/// [GameEvent.idempotencyKey] for exactly-once sinks.
///
/// Timeout-vs-move race: after an AI turn resolves, the mover's flag is
/// checked **before** the move touches the position; a valid move that
/// arrives after the flag still loses on time. The same check guards
/// [applyHumanMove].
///
/// Reentrancy: at most one AI turn runs at a time ([_turnInFlight] guard);
/// overlapping `requestAiTurn` calls are rejected with a `turnRejected`
/// event and return `null`.
///
/// Fallback attribution: seeded random-legal fallback moves are recorded as
/// [FallbackRecord]s (payload flag `isFallback: true` plus the failure
/// reason) and are NEVER attributed to the agent — no agent phrase or id is
/// attached to them.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../agent/agent_config.dart';
import '../agent/agent_runner.dart';
import '../llm/provider.dart';
import '../llm/validation.dart';
import 'clock.dart';
import 'game_state.dart';

/// Standard chess starting position (FEN).
const String standardStartFen =
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

/// Advances an opaque position by one UCI move, returning the new position
/// payload (FEN or variant JSON).
///
/// Provided by the engine/UI layer. When `null`, the orchestrator records
/// moves and flips the turn but leaves the position string unchanged.
typedef PositionUpdater = String Function(String position, String uci);

/// Ordered, idempotent game event.
///
/// * [seq] is the zero-based index in the orchestrator's [eventLog].
/// * [idempotencyKey] (`evt-<seq>-<microseconds>`) lets sinks dedupe
///   redeliveries.
/// * [type] is a stable string (`gameStarted`, `aiStream`, `moveApplied`,
///   `aiTurnFailed`, `fallbackApplied`, `turnRejected`, `flagFall`,
///   `gameFinished`, `paused`, `resumed`, `resigned`, `humanMoveRejected`,
///   `terminalReported`, …).
/// * [payload] is JSON-compatible event data.
/// * [timestamp] is creation wall-clock time.
class GameEvent {
  /// Zero-based index in the event log.
  final int seq;

  /// Unique key for exactly-once sinks.
  final String idempotencyKey;

  /// Stable event type string.
  final String type;

  /// JSON-compatible event data.
  final Map<String, Object?> payload;

  /// Creation wall-clock time.
  final DateTime timestamp;

  /// Creates a game event.
  const GameEvent({
    required this.seq,
    required this.idempotencyKey,
    required this.type,
    required this.payload,
    required this.timestamp,
  });

  /// Serializes to JSON.
  Map<String, Object?> toJson() => {
        'seq': seq,
        'idempotencyKey': idempotencyKey,
        'type': type,
        'payload': payload,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Record of one orchestrator-applied fallback move.
///
/// [isFallback] is always `true` by construction; [reason] is the runner's
/// terminal [FailureKind] that triggered the fallback. The agent's phrase is
/// deliberately absent: fallbacks are never attributed to the agent.
class FallbackRecord {
  /// Runner failure kind that triggered the fallback.
  final FailureKind reason;

  /// UCI move the orchestrator picked.
  final String chosenUci;

  /// Always `true`; marks move-history entries originating from fallback.
  final bool isFallback = true;

  /// Agent whose failure triggered the fallback, if any.
  final String? agentConfigId;

  /// Wall-clock time of application.
  final DateTime timestamp;

  /// Creates a fallback record.
  FallbackRecord({
    required this.reason,
    required this.chosenUci,
    this.agentConfigId,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Serializes to JSON.
  Map<String, Object?> toJson() => {
        'reason': reason.name,
        'chosenUci': chosenUci,
        'isFallback': isFallback,
        if (agentConfigId != null) 'agentConfigId': agentConfigId,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Owns the clock, position bookkeeping, turn flow and event log for one
/// game. UI layers listen via [ChangeNotifier] and subscribe to [events].
class GameOrchestrator extends ChangeNotifier {
  /// Static game settings (mutable to allow arena overrides pre-start).
  GameConfig config;

  /// White seat.
  GameParticipant white;

  /// Black seat.
  GameParticipant black;

  /// Bound agent configs by [AgentConfig.id]; mutated via [bindAgent].
  final Map<String, AgentConfig> agents;

  /// Computes successor positions; injected by the engine/UI layer.
  PositionUpdater? positionUpdater;

  /// Turn executor (injectable for tests).
  final AgentRunner runner;

  /// Authoritative clock; consumed once per applied turn.
  final ChessClock clock;

  /// Maximum retained events in [_eventLog] (oldest-first eviction).
  ///
  /// Bounded retention: long games/streams cannot grow memory without
  /// limit. Broadcast delivery is unaffected — eviction only trims the
  /// persisted replay log.
  final int maxEvents;

  /// Seeded RNG for fallback picks (seeded from [GameConfig.seed]).
  final Random _random;

  String _position;
  List<String> _legalMoves;
  String _turn;
  dynamic _boardHandle;
  OrchestratorState _state = OrchestratorState.initializing;
  final List<String> _moveHistory = [];
  final List<FallbackRecord> _fallbackRecords = [];
  final List<GameEvent> _eventLog = [];
  final StreamController<GameEvent> _events =
      StreamController<GameEvent>.broadcast();
  int _seq = 0;
  bool _turnInFlight = false;
  bool _pauseRequested = false;
  GameResult? _result;
  String? _failureMessage;
  final Stopwatch _gameStopwatch = Stopwatch();
  OrchestratorState _stateBeforePause = OrchestratorState.initializing;

  /// Cancellation generation: incremented on stop/resign/reportTerminal/
  /// dispose so continuations of a superseded `runTurn` future discard
  /// their results instead of applying them to a finished game.
  ///
  /// Orchestrator-side discard only — [AgentRunner]'s signature is owned
  /// by another agent and left unchanged.
  int _generation = 0;

  /// Set by [dispose]; [emit], [_transition] and [setPosition] become
  /// no-ops afterwards so post-dispose completions cannot fire listeners
  /// or touch the closed stream.
  bool _disposed = false;

  /// Creates an orchestrator.
  ///
  /// * [initialPosition] defaults to [standardStartFen]; chaotic games pass
  ///   their variant JSON document.
  /// * [initialLegalMoves] should list the legal UCIs for [initialTurn];
  ///   pass empty when unknown (no turn may start until [setPosition]
  ///   provides them).
  /// * [random] overrides the [GameConfig.seed]-derived RNG (tests).
  /// * [clock] overrides the [TimeControl]-derived clock (resumed games).
  /// * [maxEvents] caps the retained [eventLog] (oldest-first eviction,
  ///   default 10000).
  GameOrchestrator({
    required this.config,
    required this.white,
    required this.black,
    String initialPosition = standardStartFen,
    String initialTurn = 'w',
    List<String> initialLegalMoves = const [],
    Map<String, AgentConfig>? agents,
    this.positionUpdater,
    AgentRunner? runner,
    Random? random,
    ChessClock? clock,
    this.maxEvents = 10000,
  })  : _position = initialPosition,
        _turn = _normalizeColor(initialTurn),
        _legalMoves = List.of(initialLegalMoves),
        agents = agents ?? {},
        runner = runner ?? const AgentRunner(),
        _random = random ?? Random(config.seed),
        clock = clock ?? ChessClock.fromTimeControl(config.timeControl);

  // -- Read-only views -------------------------------------------------------

  /// Current lifecycle state.
  OrchestratorState get state => _state;

  /// Side to move (`w`/`b`).
  String get turn => _turn;

  /// Opaque position payload (FEN or variant JSON).
  String get position => _position;

  /// Current legal UCIs (empty until the engine layer provides them).
  List<String> get legalMoves => List.unmodifiable(_legalMoves);

  /// Played moves in UCI order (fallback moves included; see
  /// [fallbackRecords] to distinguish them).
  List<String> get moveHistory => List.unmodifiable(_moveHistory);

  /// Applied fallback records in order.
  List<FallbackRecord> get fallbackRecords =>
      List.unmodifiable(_fallbackRecords);

  /// Persisted event log in seq order (replay source for late subscribers).
  List<GameEvent> get eventLog => List.unmodifiable(_eventLog);

  /// Broadcast stream of [GameEvent]s (persisted before broadcast).
  Stream<GameEvent> get events => _events.stream;

  /// Whether an AI turn is currently in flight.
  bool get isBusy => _turnInFlight;

  /// Terminal result, when the game has ended.
  GameResult? get result => _result;

  /// Unrecoverable error detail when [state] is [OrchestratorState.failed].
  String? get failureMessage => _failureMessage;

  /// Number of events emitted so far (next event's seq).
  int get eventSeq => _seq;

  /// Opaque engine board handle, if the engine layer attached one.
  ///
  /// Stored as `dynamic` but never interrogated here — use [boardAs] with an
  /// explicit type at the call site. Attach via [setBoardHandle].
  dynamic get boardHandle => _boardHandle;

  /// Typed view of [boardHandle]: returns it when it is a [T], else `null`.
  T? boardAs<T>() => _boardHandle is T ? _boardHandle as T : null;

  /// Attaches an opaque engine board handle (owned by the engine layer).
  void setBoardHandle(dynamic handle) {
    _boardHandle = handle;
  }

  /// Participant currently to move.
  GameParticipant get participantToMove => _turn == 'b' ? black : white;

  /// Binds (or rebinds) an agent config for AI seats to resolve.
  void bindAgent(AgentConfig agent) {
    agents[agent.id] = agent;
  }

  // -- Event log -------------------------------------------------------------

  /// Appends [type]/[payload] to [eventLog], then broadcasts it.
  ///
  /// Persist-then-broadcast: the log write always precedes the stream add,
  /// so replay-then-subscribe consumers observe every event exactly once.
  /// After [dispose] (or when closed) this is a no-op returning a
  /// synthetic event with seq -1 that is neither logged nor broadcast.
  @protected
  GameEvent emit(String type, [Map<String, Object?> payload = const {}]) {
    if (_disposed || _events.isClosed) {
      return GameEvent(
        seq: -1,
        idempotencyKey: 'evt-disposed',
        type: type,
        payload: Map<String, Object?>.of(payload),
        timestamp: DateTime.now(),
      );
    }
    final event = GameEvent(
      seq: _seq,
      idempotencyKey: 'evt-$_seq-${DateTime.now().microsecondsSinceEpoch}',
      type: type,
      payload: Map<String, Object?>.of(payload),
      timestamp: DateTime.now(),
    );
    _seq++;
    _eventLog.add(event);
    while (_eventLog.length > maxEvents) {
      _eventLog.removeAt(0);
    }
    _events.add(event);
    return event;
  }

  // -- Lifecycle ---------------------------------------------------------------

  /// Allowed lifecycle transitions (including self-transitions).
  ///
  /// Terminal states ([OrchestratorState.finished]/[failed]) have no
  /// outgoing edges: once terminal the game only leaves via a fresh
  /// orchestrator ([startGame] refuses re-entry). [paused] only resumes to
  /// stable wait states, never to transient AI-turn sub-states.
  static const Map<OrchestratorState, Set<OrchestratorState>> _allowedTransitions =
      <OrchestratorState, Set<OrchestratorState>>{
    OrchestratorState.initializing: {
      OrchestratorState.waitingHuman,
      OrchestratorState.waitingAi,
      OrchestratorState.failed,
    },
    OrchestratorState.waitingHuman: {
      OrchestratorState.waitingHuman,
      OrchestratorState.waitingAi,
      OrchestratorState.applying,
      OrchestratorState.paused,
      OrchestratorState.finished,
      OrchestratorState.failed,
    },
    OrchestratorState.waitingAi: {
      OrchestratorState.waitingHuman,
      OrchestratorState.waitingAi,
      OrchestratorState.streaming,
      OrchestratorState.validating,
      OrchestratorState.applying,
      OrchestratorState.paused,
      OrchestratorState.finished,
      OrchestratorState.failed,
    },
    OrchestratorState.streaming: {
      OrchestratorState.validating,
      OrchestratorState.paused,
      OrchestratorState.finished,
      OrchestratorState.failed,
    },
    OrchestratorState.validating: {
      OrchestratorState.applying,
      OrchestratorState.waitingHuman,
      OrchestratorState.waitingAi,
      OrchestratorState.paused,
      OrchestratorState.finished,
      OrchestratorState.failed,
    },
    OrchestratorState.applying: {
      OrchestratorState.waitingHuman,
      OrchestratorState.waitingAi,
      OrchestratorState.paused,
      OrchestratorState.finished,
      OrchestratorState.failed,
    },
    OrchestratorState.paused: {
      OrchestratorState.waitingHuman,
      OrchestratorState.waitingAi,
      OrchestratorState.finished,
      OrchestratorState.failed,
    },
    OrchestratorState.finished: {},
    OrchestratorState.failed: {},
  };

  /// Starts the game: validates config, starts the clock, and moves to the
  /// waiting state matching the side to move.
  ///
  /// Returns `false` (emitting `startRejected`) when validation fails or the
  /// game already started.
  bool startGame({int? nowMs}) {
    if (_disposed) return false;
    if (_state != OrchestratorState.initializing) {
      emit('startRejected', {'reason': 'already started'});
      return false;
    }
    final problems = config.validate();
    if (problems.isNotEmpty) {
      _failureMessage = problems.join(' ');
      _transition(OrchestratorState.failed);
      emit('gameFinished', {
        'reason': 'invalidConfig',
        'problems': problems,
      });
      return false;
    }
    _gameStopwatch
      ..reset()
      ..start();
    clock.start(color: _turn, nowMs: nowMs);
    emit('gameStarted', {
      'mode': config.mode.name,
      'turn': _turn,
      'position': _position,
    });
    _transition(participantToMove.isHuman
        ? OrchestratorState.waitingHuman
        : OrchestratorState.waitingAi);
    return true;
  }

  /// Suspends turn intake. An in-flight AI turn still completes (pause takes
  /// effect between turns): [pause] records the intent in [_pauseRequested]
  /// and the turn's completion restores the paused state.
  ///
  /// Only stable wait states ([OrchestratorState.waitingHuman]/
  /// [waitingAi]) and [initializing] may pause; transient AI-turn
  /// sub-states (`streaming`/`validating`/`applying`) are captured as
  /// their enclosing `waitingAi` so [resume] is always well-defined.
  void pause() {
    if (_disposed) return;
    if (_state == OrchestratorState.finished ||
        _state == OrchestratorState.failed ||
        _state == OrchestratorState.paused ||
        _state == OrchestratorState.initializing) {
      return;
    }
    if (_turnInFlight) {
      _pauseRequested = true;
    }
    _stateBeforePause = _stableWaitFor(_state);
    _transition(OrchestratorState.paused);
    emit('paused', {});
  }

  /// Resumes a paused game, restoring the stable wait state captured by
  /// [pause]. Never restores transient `streaming`/`validating`/`applying`
  /// states (no stream exists to resume); a turn in flight re-enters
  /// `waitingAi`.
  void resume() {
    if (_disposed) return;
    if (_state != OrchestratorState.paused) return;
    _pauseRequested = false;
    emit('resumed', {});
    if (_turnInFlight) {
      _transition(OrchestratorState.waitingAi);
    } else {
      // `_stateBeforePause` is always a stable wait state (see [pause]),
      // but `initializing`/`paused` values — possible only if pause/resume
      // were reordered by a future edit — fall back to the side to move
      // rather than stranding the game.
      final restore = _stateBeforePause == OrchestratorState.paused ||
              _stateBeforePause == OrchestratorState.initializing
          ? (participantToMove.isHuman
              ? OrchestratorState.waitingHuman
              : OrchestratorState.waitingAi)
          : _stateBeforePause;
      _transition(restore);
    }
  }

  /// Aborts the game without a winner.
  ///
  /// Bumps the cancellation generation so an in-flight `runTurn`
  /// continuation discards its result instead of applying it.
  void stop({String reason = 'stopped'}) {
    if (_disposed || _isTerminal) return;
    _generation++;
    _turnInFlight = false;
    _pauseRequested = false;
    _gameStopwatch.stop();
    _result = GameResult(outcome: '*', reason: reason);
    clock.stop();
    _transition(OrchestratorState.finished);
    emit('gameFinished', {'outcome': '*', 'reason': reason});
  }

  /// Records resignation by [color]; the other side wins.
  ///
  /// Bumps the cancellation generation (see [stop]).
  void resign(String color) {
    if (_disposed || _isTerminal) return;
    final loser = _normalizeColor(color);
    final winner = loser == 'w' ? 'b' : 'w';
    _generation++;
    _turnInFlight = false;
    _pauseRequested = false;
    _gameStopwatch.stop();
    _result = GameResult(
      outcome: winner == 'w' ? '1-0' : '0-1',
      reason: 'resignation',
      winnerColor: winner,
    );
    clock.stop();
    _transition(OrchestratorState.finished);
    emit('resigned', {'color': loser, 'winner': winner});
    emit('gameFinished', {
      'outcome': _result!.outcome,
      'reason': 'resignation',
      'winner': winner,
    });
  }

  /// Records an engine-adjudicated terminal position (checkmate, stalemate,
  /// variant end conditions) that the orchestrator cannot detect itself.
  ///
  /// Outcome/winner consistency is enforced by the [GameResult]
  /// constructor assert in debug builds and re-validated here in release
  /// builds (`reportTerminal` trusts arbitrary results otherwise).
  /// Inconsistent results are rejected (no state change) with a
  /// `terminalRejected` event. Bumps the cancellation generation (see
  /// [stop]).
  void reportTerminal(GameResult terminalResult) {
    if (_disposed || _isTerminal) return;
    if (!GameResult.isConsistent(
        terminalResult.outcome, terminalResult.winnerColor)) {
      emit('terminalRejected', {
        'reason': 'outcome/winner mismatch',
        'outcome': terminalResult.outcome,
        if (terminalResult.winnerColor != null)
          'winnerColor': terminalResult.winnerColor,
        'countAsTurn': false,
      });
      return;
    }
    _generation++;
    _turnInFlight = false;
    _pauseRequested = false;
    _gameStopwatch.stop();
    _result = terminalResult;
    clock.stop();
    _transition(OrchestratorState.finished);
    emit('terminalReported', terminalResult.toJson());
    emit('gameFinished', {
      'outcome': terminalResult.outcome,
      'reason': terminalResult.reason,
      if (terminalResult.winnerColor != null)
        'winner': terminalResult.winnerColor,
    });
  }

  // -- Position intake ---------------------------------------------------------

  /// Publishes a new position with its fresh legal-move list and side to
  /// move. Called by the engine/UI layer on game start and — because the
  /// orchestrator cannot compute moves itself — after every applied move.
  ///
  /// Rejected (no state change) while an AI turn is in flight (the turn
  /// owns a position snapshot — mutating mid-flight would race it), once
  /// terminal, or after [dispose].
  void setPosition(
    String position, {
    required String turn,
    required List<String> legalMoves,
    dynamic boardHandle,
  }) {
    if (_disposed) return;
    if (_turnInFlight) {
      emit('positionSetRejected', {'reason': 'AI turn in flight'});
      return;
    }
    if (_isTerminal) {
      emit('positionSetRejected', {'reason': 'game already over'});
      return;
    }
    _position = position;
    _turn = _normalizeColor(turn);
    _legalMoves = List.of(legalMoves);
    if (boardHandle != null) _boardHandle = boardHandle;
    emit('positionSet', {
      'turn': _turn,
      'legalMoveCount': _legalMoves.length,
    });
    notifyListeners();
  }

  // -- AI turns ------------------------------------------------------------------

  /// Runs one AI turn for [participantColor] (`w`/`b`).
  ///
  /// Guards: rejects (returns `null` + `turnRejected` event) when a turn is
  /// already in flight, the game is paused/finished/failed, it is not that
  /// side's turn, the seat is human or has no bound agent config, or no
  /// legal moves are known.
  ///
  /// On success the validated move is applied (after the pre-apply flag
  /// check). On definitive failure a seeded random-legal fallback applies
  /// when [FallbackPolicy.enabled] (recorded, unattributed); otherwise the
  /// game continues and the side to move must retry or resign.
  ///
  /// Stale-completion discard: the runner future is captured with the
  /// current cancellation generation; when `stop`/`resign`/
  /// `reportTerminal`/`dispose` intervene mid-turn, the continuation
  /// discards the result (never applied, never emitted) and returns `null`.
  /// [AgentRunner]'s signature is untouched — discard is orchestrator-side.
  ///
  /// Metrics contract: `aiTurnStarted`/`aiStream`/`moveApplied` carry
  /// `agentId` plus the deprecated `agentConfigId` alias, and full color
  /// names (`colorName`: `'white'`/`'black'`) alongside the compact
  /// `color` (`'w'`/`'b'`). A single `turnSummary` event per executed turn
  /// carries the metrics flags and is the only event with
  /// `countAsTurn: true`; auxiliary events set `countAsTurn: false` so
  /// multi-event turns count once in `AgentMetrics.compute`.
  ///
  /// Live provider events are re-broadcast as `aiStream` game events via the
  /// runner's `onEvent` hook. [providerOverride]/[httpClient]/[seed] are
  /// forwarded to [AgentRunner.runTurn] (tests, shared clients,
  /// reproducible sampling).
  Future<AgentTurnResult?> requestAiTurn(
    String participantColor, {
    LlmProvider? providerOverride,
    http.Client? httpClient,
    ApiKeyResolver? apiKeyResolver,
    int? seed,
  }) async {
    final color = _normalizeColor(participantColor);
    if (_disposed) return null;
    if (_turnInFlight) {
      emit('turnRejected', {
        'reason': 'overlapping turn in flight',
        'color': color,
        'colorName': _colorName(color),
        'countAsTurn': false,
      });
      return null;
    }
    if (_state == OrchestratorState.paused) {
      emit('turnRejected', {
        'reason': 'game paused',
        'color': color,
        'colorName': _colorName(color),
        'countAsTurn': false,
      });
      return null;
    }
    if (_isTerminal) {
      emit('turnRejected', {
        'reason': 'game already over',
        'color': color,
        'colorName': _colorName(color),
        'countAsTurn': false,
      });
      return null;
    }
    if (color != _turn) {
      emit('turnRejected', {
        'reason': 'not that side to move',
        'color': color,
        'colorName': _colorName(color),
        'turn': _turn,
        'countAsTurn': false,
      });
      return null;
    }
    final participant = color == 'b' ? black : white;
    if (!participant.isAi) {
      emit('turnRejected', {
        'reason': 'seat is not a bound AI agent',
        'color': color,
        'colorName': _colorName(color),
        'countAsTurn': false,
      });
      return null;
    }
    final agent = agents[participant.agentConfigId];
    if (agent == null) {
      emit('turnRejected', {
        'reason': 'no agent config bound',
        'color': color,
        'colorName': _colorName(color),
        'agentId': participant.agentConfigId,
        // Deprecated alias for consumers on the old contract.
        'agentConfigId': participant.agentConfigId,
        'countAsTurn': false,
      });
      return null;
    }
    if (_legalMoves.isEmpty) {
      emit('turnRejected', {
        'reason': 'no legal moves known; engine must call setPosition',
        'color': color,
        'colorName': _colorName(color),
        'countAsTurn': false,
      });
      return null;
    }

    _turnInFlight = true;
    final generation = _generation;
    _transition(OrchestratorState.waitingAi);
    emit('aiTurnStarted', {
      'color': color,
      'colorName': _colorName(color),
      'agentId': agent.id,
      // Deprecated alias for consumers on the old contract.
      'agentConfigId': agent.id,
      'model': agent.model,
      'countAsTurn': false,
    });

    final turnStopwatch = Stopwatch()..start();
    AgentTurnResult? turnResult;
    try {
      _transition(OrchestratorState.streaming);
      turnResult = await runner.runTurn(
        agent.copyWith(retry: config.retryPolicy, fallback: config.fallbackPolicy),
        AgentTurnRequest(
          positionFenOrJson: _position,
          legalMovesUci: List.of(_legalMoves),
          mode: config.mode.name,
          color: color,
          timersMs: {'white': clock.remainingW, 'black': clock.remainingB},
        ),
        seed: seed ?? config.seed,
        providerOverride: providerOverride,
        apiKeyResolver: apiKeyResolver,
        httpClient: httpClient,
        onEvent: (streamEvent) {
          emit('aiStream', {
            'color': color,
            'colorName': _colorName(color),
            'agentId': agent.id,
            // Deprecated alias for consumers on the old contract.
            'agentConfigId': agent.id,
            'kind': streamEvent.kind.name,
            if (streamEvent.message != null) 'message': streamEvent.message,
            if (streamEvent.text != null) 'text': streamEvent.text,
            if (streamEvent.toolName != null)
              'toolName': streamEvent.toolName,
            if (streamEvent.toolArgsJson != null)
              'toolArgsJson': streamEvent.toolArgsJson,
            if (streamEvent.tokensIn != null)
              'tokensIn': streamEvent.tokensIn,
            if (streamEvent.tokensOut != null)
              'tokensOut': streamEvent.tokensOut,
            if (streamEvent.latencyMs != null)
              'latencyMs': streamEvent.latencyMs,
            'countAsTurn': false,
          });
        },
      );
    } catch (e) {
      turnStopwatch.stop();
      _consumeClock(color, turnStopwatch.elapsedMilliseconds);
      _turnInFlight = false;
      if (_isTerminal || _disposed || generation != _generation) return null;
      _failureMessage = 'Agent turn crashed: $e';
      _transition(OrchestratorState.failed);
      emit('aiTurnFailed', {
        'color': color,
        'colorName': _colorName(color),
        'agentId': agent.id,
        // Deprecated alias for consumers on the old contract.
        'agentConfigId': agent.id,
        'kind': FailureKind.internal.name,
        'error': '$e',
        'countAsTurn': false,
      });
      return null;
    }
    turnStopwatch.stop();
    _consumeClock(color, turnStopwatch.elapsedMilliseconds);

    // Stale-completion guard: stop()/resign()/reportTerminal()/dispose()
    // during the flight wins — the resolved turn is discarded, never
    // applied and never emitted.
    if (_isTerminal || _disposed || generation != _generation) {
      _turnInFlight = false;
      return null;
    }

    // Timeout-vs-move race: the flag is authoritative and checked BEFORE
    // anything touches the position — even a valid move loses on time.
    // Untimed games (`TimeControl.none`) never flag: `isFlagged` is false
    // by construction, so this path is unreachable for them. The explicit
    // type check below documents the invariant for readers.
    if (config.timeControl.type != TimeControlType.none &&
        clock.isFlagged(color)) {
      _emitTurnSummary(
        agentId: agent.id,
        color: color,
        turnResult: turnResult,
        isFallback: false,
        timedOut: true,
      );
      _turnInFlight = false;
      _onFlag(color);
      return turnResult;
    }

    _transition(OrchestratorState.validating);
    final outcome = turnResult.outcome;
    if (outcome.isValid && outcome.toolCall != null) {
      _applyMove(
        color,
        outcome.toolCall!.uci,
        isFallback: false,
        phrase: outcome.toolCall!.phrase,
        agentConfigId: agent.id,
      );
      _emitTurnSummary(
        agentId: agent.id,
        modelKey: agent.model,
        color: color,
        turnResult: turnResult,
        isFallback: false,
        timedOut: false,
      );
    } else {
      emit('aiTurnFailed', {
        'color': color,
        'colorName': _colorName(color),
        'agentId': agent.id,
        // Deprecated alias for consumers on the old contract.
        'agentConfigId': agent.id,
        'kind': outcome.kind.name,
        if (outcome.error != null) 'error': outcome.error,
        'attempts': turnResult.failure?.attempts ?? 1,
        'countAsTurn': false,
      });
      if (config.fallbackPolicy.enabled && _legalMoves.isNotEmpty) {
        _applySeededFallback(color, outcome.kind, agent.id);
        _emitTurnSummary(
          agentId: agent.id,
          modelKey: agent.model,
          color: color,
          turnResult: turnResult,
          isFallback: true,
          timedOut: false,
        );
      } else {
        _emitTurnSummary(
          agentId: agent.id,
          modelKey: agent.model,
          color: color,
          turnResult: turnResult,
          isFallback: false,
          timedOut: false,
        );
        // Game continues: the side to move must retry, resign or stop.
        _transition(participantToMove.isHuman
            ? OrchestratorState.waitingHuman
            : OrchestratorState.waitingAi);
      }
    }

    _checkEndConditions();
    _turnInFlight = false;
    if (!_isTerminal && _pauseRequested) {
      // A pause arrived mid-turn: honor it now that the turn settled.
      _pauseRequested = false;
      _transition(OrchestratorState.paused);
    } else if (!_isTerminal && !_stateIsWait()) {
      // Backstop: every path above already lands on a wait state, but a
      // future edit must never strand the game between turns.
      _transition(participantToMove.isHuman
          ? OrchestratorState.waitingHuman
          : OrchestratorState.waitingAi);
    }
    return turnResult;
  }

  // -- Human moves ---------------------------------------------------------------

  /// Applies a human move for the side to move.
  ///
  /// Returns `true` when applied. Returns `false` (emitting
  /// `humanMoveRejected`) when the game is paused/over, the side to move is
  /// AI-driven, [uci] is not in the known legal list, or the mover already
  /// flagged (checked before applying; unreachable for `TimeControl.none`
  /// games which never flag — see [ChessClock.isFlagged]). When
  /// [elapsedMs] is given, it is consumed from the mover's clock first.
  bool applyHumanMove(String uci, {int? elapsedMs}) {
    if (_disposed) return false;
    if (_state == OrchestratorState.paused) {
      emit('humanMoveRejected', {
        'reason': 'game paused',
        'uci': uci,
        'countAsTurn': false,
      });
      return false;
    }
    if (_isTerminal || _turnInFlight) {
      emit('humanMoveRejected', {
        'reason': _isTerminal ? 'game already over' : 'AI turn in flight',
        'uci': uci,
        'countAsTurn': false,
      });
      return false;
    }
    if (!participantToMove.isHuman) {
      emit('humanMoveRejected', {
        'reason': 'side to move is AI-driven',
        'uci': uci,
        'turn': _turn,
        'countAsTurn': false,
      });
      return false;
    }
    final normalized =
        _legalMoves.firstWhereOrNull(_foldCaseEquals(uci));
    if (normalized == null) {
      emit('humanMoveRejected', {
        'reason': 'illegal move',
        'uci': uci,
        'turn': _turn,
        'countAsTurn': false,
      });
      return false;
    }
    if (elapsedMs != null) {
      _consumeClock(_turn, elapsedMs);
    }
    if (config.timeControl.type != TimeControlType.none &&
        clock.isFlagged(_turn)) {
      _onFlag(_turn);
      return false;
    }
    _applyMove(_turn, normalized, isFallback: false);
    _checkEndConditions();
    return true;
  }

  // -- Snapshots -------------------------------------------------------------------

  /// Captures a serializable snapshot of the current game.
  GameSnapshot snapshot() {
    return GameSnapshot(
      position: _position,
      isVariant: config.mode == GameMode.chaotic,
      turn: _turn,
      moveHistory: List.of(_moveHistory),
      remainingW: clock.remainingW,
      remainingB: clock.remainingB,
      state: _state,
      result: _result,
      eventSeq: _seq,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _turnInFlight = false;
    _pauseRequested = false;
    if (!_events.isClosed) {
      _events.close();
    }
    super.dispose();
  }

  // -- Internals ---------------------------------------------------------------------

  bool get _isTerminal =>
      _state == OrchestratorState.finished ||
      _state == OrchestratorState.failed;

  bool _stateIsWait() =>
      _state == OrchestratorState.waitingHuman ||
      _state == OrchestratorState.waitingAi;

  /// Moves to [next], enforcing [_allowedTransitions].
  ///
  /// Illegal transitions (including any attempt to leave a terminal state)
  /// are ignored with a diagnostic `transitionRejected` event — they never
  /// mutate state. No-op after [dispose] (ChangeNotifier is dead).
  void _transition(OrchestratorState next) {
    if (_disposed) return;
    if (next != _state &&
        !(_allowedTransitions[_state]?.contains(next) ?? false)) {
      emit('transitionRejected', {
        'from': _state.name,
        'to': next.name,
        'countAsTurn': false,
      });
      return;
    }
    _state = next;
    notifyListeners();
  }

  /// Stable wait state corresponding to [state]: transient AI-turn
  /// sub-states (`streaming`/`validating`/`applying`) fold to their
  /// enclosing `waitingAi` so a pause captured mid-turn resumes to a state
  /// with a well-defined meaning. `paused` itself falls back to the side
  /// to move (defensive; pause-during-pause is rejected before this).
  OrchestratorState _stableWaitFor(OrchestratorState state) {
    switch (state) {
      case OrchestratorState.streaming:
      case OrchestratorState.validating:
      case OrchestratorState.applying:
        return OrchestratorState.waitingAi;
      case OrchestratorState.waitingHuman:
      case OrchestratorState.waitingAi:
      case OrchestratorState.initializing:
        return state;
      case OrchestratorState.paused:
      case OrchestratorState.finished:
      case OrchestratorState.failed:
        return participantToMove.isHuman
            ? OrchestratorState.waitingHuman
            : OrchestratorState.waitingAi;
    }
  }

  /// Metrics color vocabulary: compact internal `'w'`/`'b'` to the full
  /// `'white'`/`'black'` names `AgentMetrics.compute` aggregates on.
  static String _colorName(String color) => color == 'b' ? 'black' : 'white';

  /// Emits the single `turnSummary` event for an executed AI turn — the
  /// only orchestrator event with `countAsTurn: true` (see [requestAiTurn]).
  ///
  /// Flags mirror the `AgentMetrics.compute` payload contract: `parsedMove`
  /// (a candidate move was parsed), `validTool`/`legal` (a legal move was
  /// produced and applied), `illegalAttempt` (illegal tool-call failure),
  /// `unparseable` (malformed/unparseable output), `missingTool` (no usable
  /// tool call), `providerError` (transport/auth/rate-limit failures),
  /// `timeout` (the turn — or the clock — timed out), `fallback` (a seeded
  /// random-legal move resolved the turn, unattributed to the agent).
  void _emitTurnSummary({
    required String agentId,
    String? modelKey,
    required String color,
    required AgentTurnResult turnResult,
    required bool isFallback,
    required bool timedOut,
  }) {
    final kind = turnResult.outcome.kind;
    final valid = turnResult.outcome.isValid;
    final payload = <String, Object?>{
      'agentId': agentId,
      // Deprecated alias for consumers on the old contract.
      'agentConfigId': agentId,
      'color': color,
      'colorName': _colorName(color),
      'mode': config.mode.name,
      'latencyMs': turnResult.latencyMs,
      'parsedMove': valid || kind == FailureKind.illegalMove,
      'validTool': valid,
      'legal': valid && !isFallback,
      'illegalAttempt': kind == FailureKind.illegalMove,
      'unparseable': kind == FailureKind.unparseableResponse ||
          kind == FailureKind.malformedArgs,
      'missingTool': kind == FailureKind.missingToolCall ||
          kind == FailureKind.incompleteResponse ||
          kind == FailureKind.cancelled ||
          kind == FailureKind.internal,
      'providerError': kind == FailureKind.providerError ||
          kind == FailureKind.rateLimit ||
          kind == FailureKind.authError,
      'timeout': timedOut || kind == FailureKind.timeout,
      'fallback': isFallback,
      'attempts': turnResult.failure?.attempts ?? 1,
      'countAsTurn': true,
    };
    final key = modelKey;
    if (key != null) payload['modelKey'] = key;
    final usage = turnResult.usage;
    if (usage != null) {
      payload['inputTokens'] = usage.inputTokens;
      payload['outputTokens'] = usage.outputTokens;
    }
    emit('turnSummary', payload);
  }

  /// Charges [elapsedMs] to [color] with the game's increment/delay bonus.
  void _consumeClock(String color, int elapsedMs) {
    final control = config.timeControl;
    clock.consume(
      color,
      elapsedMs,
      incrementMs: control.type == TimeControlType.increment
          ? (control.incrementMs ?? 0)
          : 0,
      delayMs: control.type == TimeControlType.delay
          ? (control.delayMs ?? 0)
          : 0,
    );
  }

  /// Adjudicates a flag fall for [color]: opponent wins on time.
  void _onFlag(String color) {
    final winner = color == 'w' ? 'b' : 'w';
    _result = GameResult(
      outcome: winner == 'w' ? '1-0' : '0-1',
      reason: 'timeout',
      winnerColor: winner,
    );
    clock.stop();
    _transition(OrchestratorState.finished);
    emit('flagFall', {'color': color, 'winner': winner});
    emit('gameFinished', {
      'outcome': _result!.outcome,
      'reason': 'timeout',
      'winner': winner,
    });
  }

  /// Applies [uci] for [color]: advances the position (when a
  /// [positionUpdater] is bound), records history, flips the turn, clears
  /// the now-stale legal list (the engine layer must [setPosition] fresh
  /// moves), and emits `moveApplied`.
  void _applyMove(
    String color,
    String uci, {
    required bool isFallback,
    String? phrase,
    String? agentConfigId,
  }) {
    _transition(OrchestratorState.applying);
    if (positionUpdater != null) {
      try {
        _position = positionUpdater!(_position, uci);
      } catch (e) {
        _failureMessage = 'Position update failed for $uci: $e';
        _transition(OrchestratorState.failed);
        emit('gameFinished', {'reason': 'positionUpdateFailed'});
        return;
      }
    }
    _moveHistory.add(uci);
    _turn = color == 'w' ? 'b' : 'w';
    _legalMoves = [];
    emit('moveApplied', {
      'uci': uci,
      'color': color,
      'colorName': _colorName(color),
      'isFallback': isFallback,
      if (!isFallback && phrase != null) 'phrase': phrase,
      if (!isFallback && agentConfigId != null) 'agentId': agentConfigId,
      if (!isFallback && agentConfigId != null)
        // Deprecated alias for consumers on the old contract.
        'agentConfigId': agentConfigId,
      'moveIndex': _moveHistory.length,
      'countAsTurn': false,
    });
    _transition(participantToMove.isHuman
        ? OrchestratorState.waitingHuman
        : OrchestratorState.waitingAi);
  }

  /// Picks a uniform random legal move with the seeded RNG, records a
  /// [FallbackRecord] (unattributed to any agent), and applies it.
  void _applySeededFallback(
    String color,
    FailureKind reason,
    String? agentConfigId,
  ) {
    final choice = _legalMoves[_random.nextInt(_legalMoves.length)];
    final record = FallbackRecord(
      reason: reason,
      chosenUci: choice,
      agentConfigId: agentConfigId,
    );
    _fallbackRecords.add(record);
    emit('fallbackApplied', {
      ...record.toJson(),
      // Timestamp serialized for sinks; Domain object keeps DateTime.
    });
    _applyMove(color, choice, isFallback: true);
  }

  /// Enforces [GameConfig.maxMoves] and [GameConfig.maxDurationMs] between
  /// turns (best-effort: checked after each applied move, not preemptively).
  ///
  /// A move-limit ending is a draw (`'1/2-1/2'`) — the game ran its course
  /// with no winner. A wall-clock abort (`maxDurationExceeded`) is
  /// undecided (`'*'`): the two outcomes feed standings/Elo differently
  /// and must not be conflated. Duration uses the monotonic [_gameStopwatch]
  /// (started in [startGame]), immune to wall-clock jumps.
  void _checkEndConditions() {
    if (_isTerminal) return;
    if (config.maxMoves != null && _moveHistory.length >= config.maxMoves!) {
      _result = const GameResult(outcome: '1/2-1/2', reason: 'maxMoves');
      clock.stop();
      _transition(OrchestratorState.finished);
      emit('gameFinished', {'outcome': '1/2-1/2', 'reason': 'maxMoves'});
      return;
    }
    if (config.maxDurationMs != null) {
      final elapsed = _gameStopwatch.elapsedMilliseconds;
      if (elapsed >= config.maxDurationMs!) {
        _result =
            const GameResult(outcome: '*', reason: 'maxDurationExceeded');
        clock.stop();
        _transition(OrchestratorState.finished);
        emit('gameFinished', {
          'outcome': '*',
          'reason': 'maxDurationExceeded',
        });
      }
    }
  }

  static String _normalizeColor(String color) =>
      color.trim().toLowerCase().startsWith('b') ? 'b' : 'w';

  static bool Function(String) _foldCaseEquals(String uci) {
    final want = uci.trim().toLowerCase();
    return (candidate) => candidate.toLowerCase() == want;
  }
}

/// Case-insensitive exact-match helper over iterables (local to avoid a
/// collection-package dependency in the game layer).
extension _FirstWhereOrNull on List<String> {
  String? firstWhereOrNull(bool Function(String) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
