/// AI-turn sequencing extracted from [GameOrchestrator].
///
/// Single responsibility: [TurnPump] owns only the AI-turn pipeline —
/// guard checks, prompt rendering, [AgentRunner] invocation with live
/// `aiStream` re-broadcast, timeout-vs-move race, validation branching,
/// seeded-fallback triggering and `turnSummary` emission.
///
/// State ownership stays with the orchestrator: lifecycle transitions,
/// the ordered event log, clocks, positions, move history and terminal
/// adjudication all live behind [TurnPumpHost] (implemented by the
/// orchestrator) and the [TurnPumpEventCallback] (which appends a
/// `GameEvent` of the given type/payload to the orchestrator log before
/// broadcast). The pump never imports Flutter or any UI layer.
///
/// Host/pump split:
/// * Host owns: config/position/legal/turn snapshot reads, turn-in-flight
///   and generation guards, cancel tokens, seeded-RNG index picks, clock
///   consumption, move/fallback application, flag adjudication, failure
///   recording, end-condition checks and the end-of-turn pause/backstop.
/// * Pump decides: when to start a turn, what to emit (`turnRejected`,
///   `aiTurnStarted`, `aiStream`, `aiTurnFailed`, `turnSummary`), when the
///   flag race wins, and whether a fallback resolves the turn. Mutations
///   that touch game state go through the host so ordering
///   (persist-then-broadcast, transition guards) is unchanged.
/// Talks to: `agent_runner.dart`, `llm/` (provider/prompt/validation), `game_state.dart`+`clock.dart` via `TurnPumpHost`.
/// Never imports: `package:flutter`, `ui/`, `chess/`+`variant/` engines, `arena/`, `storage/` — sequencing only.
library;

import 'package:http/http.dart' as http;

import '../agent/agent_config.dart';
import '../agent/agent_runner.dart';
import '../chess/fen.dart';
import '../diagnostics/backend_log.dart';
import '../llm/prompt_board.dart';
import '../llm/provider.dart';
import '../llm/validation.dart';
import 'clock.dart';
import 'game_state.dart';

/// Emits one game-log event: appends `[type]`/`[payload]` to the
/// orchestrator's ordered `GameEvent` log (persist-then-broadcast) before
/// fanning out to subscribers.
typedef TurnPumpEventCallback = void Function(
  String type,
  Map<String, Object?> payload,
);

/// Orchestrator-owned state and mutations the pump sequences.
///
/// Implemented by the orchestrator (same library, so it can forward to
/// private fields without widening the public API used by screens).
abstract class TurnPumpHost {
  /// Static game settings.
  GameConfig get config;

  /// Opaque position payload (FEN or variant JSON).
  String get position;

  /// Current legal UCIs (empty until the engine layer provides them).
  List<String> get legalMoves;

  /// Side to move (`w`/`b`).
  String get turn;

  /// Current lifecycle state.
  OrchestratorState get state;

  /// Participant currently to move.
  GameParticipant get participantToMove;

  /// Participant for a normalized (`w`/`b`) color.
  GameParticipant participantFor(String color);

  /// Bound agent config by id, if any.
  AgentConfig? agentFor(String? id);

  /// Whether [GameOrchestrator.dispose] ran.
  bool get isDisposed;

  /// Whether the game reached `finished`/`failed`.
  bool get isTerminal;

  /// Whether an AI turn is currently in flight (reentrancy guard).
  bool get turnInFlight;

  /// Sets the reentrancy guard.
  void setTurnInFlight(bool value);

  /// Cancellation generation: bumped on stop/resign/reportTerminal/dispose
  /// so superseded turn continuations discard their results.
  int get generation;

  /// Whether a pause was requested mid-turn (honored when it settles).
  bool get pauseRequested;

  /// Sets the deferred-pause flag.
  void setPauseRequested(bool value);

  /// Cooperative cancellation handle for the in-flight turn, if any.
  CancelToken? get turnCancel;

  /// Replaces the cooperative cancellation handle.
  void setTurnCancel(CancelToken? token);

  /// Aborts the previous provider stream, if any.
  void cancelPreviousTurn();

  /// Moves to [next], enforcing the allowed-transition table.
  void transition(OrchestratorState next);

  /// Charges [elapsedMs] to [color] with the game's increment/delay bonus.
  void consumeClock(String color, int elapsedMs);

  /// Applies [uci] for [color] (advances position, records history, flips
  /// the turn, emits `moveApplied`).
  void applyMove(
    String color,
    String uci, {
    required bool isFallback,
    String? phrase,
    String? agentConfigId,
  });

  /// Picks a seeded random-legal move, records it (unattributed) and applies
  /// it (emits `fallbackApplied` + `moveApplied`).
  void applyFallback(String color, FailureKind reason, String? agentConfigId);

  /// Adjudicates a flag fall for [color] (opponent wins on time).
  void flag(String color);

  /// Records an unrecoverable turn error for `failed` state diagnostics.
  void setFailureMessage(String message);

  /// Enforces `maxMoves`/`maxDurationMs` between turns.
  void checkEndConditions();

  /// Clears the in-flight guard and honors a deferred pause (or backstops
  /// to a stable wait state so a turn never strands the game).
  void finishTurn();
}

/// Runs AI turns against an [AgentRunner] on behalf of the orchestrator.
///
/// Constructed once per orchestrator via constructor injection of the
/// state [host], the [AgentRunner], the [ChessClock] and the
/// [onEvent] (`GameEvent`) sink. No UI imports.
class TurnPump {
  /// Orchestrator-owned state handle.
  final TurnPumpHost host;

  /// Turn executor (injectable for tests; shared with the orchestrator).
  final AgentRunner runner;

  /// Authoritative clock (shared with the orchestrator; consumed once per
  /// applied turn).
  final ChessClock clock;

  /// Game-log sink (`GameEvent` persist-then-broadcast).
  final TurnPumpEventCallback onEvent;

  /// UI-free logger (per-call override wins; defaults to [currentBackendLog]).
  final BackendLog? log;

  /// Creates a pump bound to an orchestrator host.
  TurnPump({
    required this.host,
    required this.runner,
    required this.clock,
    required this.onEvent,
    this.log,
  });

  /// Renders [position] as the shared prompt state for [color].
  ///
  /// Same format for both variants; a malformed FEN degrades to a
  /// placeholder rather than crashing the turn.
  ({String board, String castling, String enPassant}) promptStateFor(
    String position,
    String color,
  ) {
    try {
      final parsed = parseFen(position);
      final rights = <String>[
        'K',
        'Q',
        'k',
        'q',
      ].where(parsed.castling.contains).join();
      return (
        board: renderBoardForPrompt(
          squares: <String, String>{
            for (final entry in parsed.board.entries)
              entry.key.name: promptPieceLetter(
                entry.value.type.letter,
                isWhite: entry.value.color.isWhite,
              ),
          },
          sideToMove: color == 'w' ? 'white' : 'black',
        ),
        castling: rights.isEmpty ? '-' : rights,
        enPassant: parsed.enPassant?.name ?? '-',
      );
    } catch (_) {
      return (board: '(board unavailable)', castling: '-', enPassant: '-');
    }
  }

  /// Runs one AI turn for [participantColor] (`w`/`b`).
  ///
  /// Guards reject (return `null` + `turnRejected` event) when a turn is
  /// already in flight, the game is paused/finished/failed, it is not that
  /// side's turn, the seat is human or has no bound agent config, or no
  /// legal moves are known. See the orchestrator's `requestAiTurn` docs for
  /// the stale-completion, timeout-vs-move, metrics and fallback contracts
  /// (unchanged by this extraction).
  ///
  /// [log] overrides the pump's [log] and the shared [currentBackendLog]
  /// for this call; [gameId]/[tournamentId]/[seq] attach correlation IDs to
  /// the entry/exit/failure records.
  Future<AgentTurnResult?> requestAiTurn(
    String participantColor, {
    LlmProvider? providerOverride,
    http.Client? httpClient,
    ApiKeyResolver? apiKeyResolver,
    int? seed,
    BackendLog? log,
    String? gameId,
    String? tournamentId,
    int? seq,
  }) async {
    final effectiveLog = log ?? this.log ?? currentBackendLog;
    final color = _normalizeColor(participantColor);
    final seqSuffix = seq == null ? '' : ' seq=$seq';
    effectiveLog.debug(
      'turn start color=$color$seqSuffix',
      tag: 'turn-pump',
      gameId: gameId,
      tournamentId: tournamentId,
    );
    AgentTurnResult? rejected(BackendLog log, String reason) {
      log.debug(
        'turn rejected reason=$reason color=$color$seqSuffix',
        tag: 'turn-pump',
        gameId: gameId,
        tournamentId: tournamentId,
      );
      onEvent('turnRejected', {
        'reason': reason,
        'color': color,
        'colorName': _colorName(color),
        'countAsTurn': false,
      });
      return null;
    }

    if (host.isDisposed) return null;
    if (host.turnInFlight) {
      rejected(effectiveLog, 'overlapping turn in flight');
      return null;
    }
    if (host.state == OrchestratorState.paused) {
      rejected(effectiveLog, 'game paused');
      return null;
    }
    if (host.isTerminal) {
      rejected(effectiveLog, 'game already over');
      return null;
    }
    if (color != host.turn) {
      onEvent('turnRejected', {
        'reason': 'not that side to move',
        'color': color,
        'colorName': _colorName(color),
        'turn': host.turn,
        'countAsTurn': false,
      });
      effectiveLog.debug(
        'turn rejected reason=not that side to move color=$color$seqSuffix',
        tag: 'turn-pump',
        gameId: gameId,
        tournamentId: tournamentId,
      );
      return null;
    }
    final participant = host.participantFor(color);
    if (!participant.isAi) {
      rejected(effectiveLog, 'seat is not a bound AI agent');
      return null;
    }
    final agent = host.agentFor(participant.agentConfigId);
    if (agent == null) {
      onEvent('turnRejected', {
        'reason': 'no agent config bound',
        'color': color,
        'colorName': _colorName(color),
        'agentId': participant.agentConfigId,
        // Deprecated alias for consumers on the old contract.
        'agentConfigId': participant.agentConfigId,
        'countAsTurn': false,
      });
      effectiveLog.debug(
        'turn rejected reason=no agent config bound color=$color$seqSuffix',
        tag: 'turn-pump',
        gameId: gameId,
        tournamentId: tournamentId,
      );
      return null;
    }
    if (host.legalMoves.isEmpty) {
      onEvent('turnRejected', {
        'reason': 'no legal moves known; engine must call setPosition',
        'color': color,
        'colorName': _colorName(color),
        'countAsTurn': false,
      });
      effectiveLog.debug(
        'turn rejected reason=no legal moves color=$color$seqSuffix',
        tag: 'turn-pump',
        gameId: gameId,
        tournamentId: tournamentId,
      );
      return null;
    }

    host.setTurnInFlight(true);
    final generation = host.generation;
    // Abort any superseded provider stream and arm a fresh token so a later
    // stop/resign/reportTerminal can cancel this turn cooperatively.
    host.cancelPreviousTurn();
    final turnCancel = CancelToken();
    host.setTurnCancel(turnCancel);
    host.transition(OrchestratorState.waitingAi);
    onEvent('aiTurnStarted', {
      'color': color,
      'colorName': _colorName(color),
      'agentId': agent.id,
      // Deprecated alias for consumers on the old contract.
      'agentConfigId': agent.id,
      'model': agent.model,
      'countAsTurn': false,
    });

    final turnStopwatch = Stopwatch()..start();
    final prompt = promptStateFor(host.position, color);
    AgentTurnResult? turnResult;
    try {
      host.transition(OrchestratorState.streaming);
      turnResult = await runner.runTurn(
        agent.copyWith(
          retry: host.config.retryPolicy,
          fallback: host.config.fallbackPolicy,
        ),
        AgentTurnRequest(
          positionFenOrJson: host.position,
          legalMovesUci: List.of(host.legalMoves),
          boardText: prompt.board,
          castlingRights: prompt.castling,
          enPassantTarget: prompt.enPassant,
          mode: host.config.mode.name,
          color: color,
          timersMs: {'white': clock.remainingW, 'black': clock.remainingB},
        ),
        seed: seed ?? host.config.seed,
        providerOverride: providerOverride,
        apiKeyResolver: apiKeyResolver,
        httpClient: httpClient,
        cancelToken: turnCancel,
        onEvent: (streamEvent) {
          // Drop late stream events once this turn is superseded or the game
          // is over, so a stopped game stops emitting aiStream rows.
          if (host.isDisposed ||
              host.isTerminal ||
              generation != host.generation) {
            return;
          }
          onEvent('aiStream', {
            'color': color,
            'colorName': _colorName(color),
            'agentId': agent.id,
            // Deprecated alias for consumers on the old contract.
            'agentConfigId': agent.id,
            'kind': streamEvent.kind.name,
            if (streamEvent.message != null) 'message': streamEvent.message,
            if (streamEvent.text != null) 'text': streamEvent.text,
            if (streamEvent.toolName != null) 'toolName': streamEvent.toolName,
            if (streamEvent.toolArgsJson != null)
              'toolArgsJson': streamEvent.toolArgsJson,
            if (streamEvent.tokensIn != null) 'tokensIn': streamEvent.tokensIn,
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
      host.consumeClock(color, turnStopwatch.elapsedMilliseconds);
      host.setTurnInFlight(false);
      if (host.isTerminal || host.isDisposed || generation != host.generation) {
        effectiveLog.debug(
          'turn discarded stale color=$color$seqSuffix',
          tag: 'turn-pump',
          gameId: gameId,
          tournamentId: tournamentId,
        );
        return null;
      }
      effectiveLog.error(
        'turn failed kind=internal color=$color$seqSuffix',
        tag: 'turn-pump',
        gameId: gameId,
        tournamentId: tournamentId,
        error: e,
      );
      host.setFailureMessage('Agent turn crashed: $e');
      host.transition(OrchestratorState.failed);
      onEvent('aiTurnFailed', {
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
    host.consumeClock(color, turnStopwatch.elapsedMilliseconds);

    // Stale-completion guard: stop()/resign()/reportTerminal()/dispose()
    // during the flight wins — the resolved turn is discarded, never
    // applied and never emitted.
    if (host.isTerminal || host.isDisposed || generation != host.generation) {
      host.setTurnInFlight(false);
      effectiveLog.debug(
        'turn discarded stale color=$color$seqSuffix',
        tag: 'turn-pump',
        gameId: gameId,
        tournamentId: tournamentId,
      );
      return null;
    }

    // Timeout-vs-move race: the flag is authoritative and checked BEFORE
    // anything touches the position — even a valid move loses on time.
    // Untimed games (`TimeControl.none`) never flag: `isFlagged` is false
    // by construction, so this path is unreachable for them. The explicit
    // type check below documents the invariant for readers.
    if (host.config.timeControl.type != TimeControlType.none &&
        clock.isFlagged(color)) {
      _emitTurnSummary(
        agentId: agent.id,
        color: color,
        turnResult: turnResult,
        isFallback: false,
        timedOut: true,
      );
      host.setTurnInFlight(false);
      host.flag(color);
      effectiveLog.debug(
        'turn end kind=timeout color=$color$seqSuffix',
        tag: 'turn-pump',
        gameId: gameId,
        tournamentId: tournamentId,
      );
      return turnResult;
    }

    host.transition(OrchestratorState.validating);
    final outcome = turnResult.outcome;
    if (outcome.isValid && outcome.toolCall != null) {
      host.applyMove(
        color,
        outcome.toolCall!.uci,
        isFallback: false,
        phrase: outcome.toolCall!.phrase,
        agentConfigId: agent.id,
      );
      effectiveLog.debug(
        'turn end kind=valid uci=${outcome.toolCall!.uci} color=$color'
        '$seqSuffix',
        tag: 'turn-pump',
        gameId: gameId,
        tournamentId: tournamentId,
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
      effectiveLog.warning(
        'turn failed kind=${outcome.kind.name} color=$color$seqSuffix',
        tag: 'turn-pump',
        gameId: gameId,
        tournamentId: tournamentId,
        error: outcome.error,
      );
      onEvent('aiTurnFailed', {
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
      if (host.config.fallbackPolicy.enabled && host.legalMoves.isNotEmpty) {
        effectiveLog.debug(
          'turn end kind=${outcome.kind.name} fallback=true color=$color'
          '$seqSuffix',
          tag: 'turn-pump',
          gameId: gameId,
          tournamentId: tournamentId,
        );
        host.applyFallback(color, outcome.kind, agent.id);
        _emitTurnSummary(
          agentId: agent.id,
          modelKey: agent.model,
          color: color,
          turnResult: turnResult,
          isFallback: true,
          timedOut: false,
        );
      } else {
        effectiveLog.debug(
          'turn end kind=${outcome.kind.name} fallback=false color=$color'
          '$seqSuffix',
          tag: 'turn-pump',
          gameId: gameId,
          tournamentId: tournamentId,
        );
        _emitTurnSummary(
          agentId: agent.id,
          modelKey: agent.model,
          color: color,
          turnResult: turnResult,
          isFallback: false,
          timedOut: false,
        );
        // Game continues: the side to move must retry, resign or stop.
        host.transition(
          host.participantToMove.isHuman
              ? OrchestratorState.waitingHuman
              : OrchestratorState.waitingAi,
        );
      }
    }

    host.checkEndConditions();
    host.finishTurn();
    return turnResult;
  }

  /// Emits the single `turnSummary` event for an executed AI turn — the
  /// only pump event with `countAsTurn: true`.
  ///
  /// Flags mirror the `AgentMetrics.compute` payload contract (see the
  /// orchestrator's `requestAiTurn` docs).
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
      'mode': host.config.mode.name,
      'latencyMs': turnResult.latencyMs,
      'parsedMove': valid || kind == FailureKind.illegalMove,
      'validTool': valid,
      'legal': valid && !isFallback,
      'illegalAttempt': kind == FailureKind.illegalMove,
      'unparseable':
          kind == FailureKind.unparseableResponse ||
          kind == FailureKind.malformedArgs,
      'missingTool':
          kind == FailureKind.missingToolCall ||
          kind == FailureKind.incompleteResponse ||
          kind == FailureKind.cancelled ||
          kind == FailureKind.internal,
      'providerError':
          kind == FailureKind.providerError ||
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
    onEvent('turnSummary', payload);
  }

  /// Metrics color vocabulary: compact internal `'w'`/`'b'` to the full
  /// `'white'`/`'black'` names `AgentMetrics.compute` aggregates on.
  static String _colorName(String color) => color == 'b' ? 'black' : 'white';

  static String _normalizeColor(String color) =>
      color.trim().toLowerCase().startsWith('b') ? 'b' : 'w';
}
