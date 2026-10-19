/// Game-level state model: modes, orchestrator lifecycle, participants,
/// game config, results and serializable snapshots.
///
/// Pure Dart. Snapshots are JSON-serializable by design so the storage layer
/// can persist/resume games without touching engine objects.
library;

import '../agent/agent_config.dart';
import 'clock.dart';

/// Which ruleset a game uses.
enum GameMode {
  /// Classic chess, positions carried as FEN strings.
  standard,

  /// Chaotic variant chess, positions carried as variant JSON documents.
  chaotic,
}

/// Lifecycle of a [GameOrchestrator][1].
///
/// [1]: Implemented in `lib/src/game/orchestrator.dart`.
enum OrchestratorState {
  /// Created but not started (`startGame` not yet called).
  initializing,

  /// Running; input expected from the human side to move.
  waitingHuman,

  /// Running; an AI turn was requested and has not resolved yet.
  waitingAi,

  /// An AI provider stream is in flight (sub-state of [waitingAi]).
  streaming,

  /// A streamed tool call is being validated (sub-state of [waitingAi]).
  validating,

  /// A move is being applied to the position (sub-state of either wait).
  applying,

  /// Suspended via `pause()`; no turns may start until `resume()`.
  paused,

  /// Terminal: result recorded, no further moves accepted.
  finished,

  /// Terminal: unrecoverable error, no further moves accepted.
  failed,
}

/// One seat at the board: either a human or an agent config reference.
class GameParticipant {
  /// [AgentConfig.id] of the agent occupying this seat, or `null` for
  /// humans (and for AI seats not yet bound — binding is explicit).
  final String? agentConfigId;

  /// Display label (`'You'`, agent name, `'White (AI)'`, …).
  final String label;

  /// Whether a human provides this side's moves.
  final bool isHuman;

  /// Creates a participant.
  const GameParticipant({
    this.agentConfigId,
    required this.label,
    required this.isHuman,
  });

  /// Whether this seat is driven by an AI agent.
  bool get isAi => !isHuman && agentConfigId != null;

  /// Serializes to JSON.
  Map<String, Object?> toJson() => {
        if (agentConfigId != null) 'agentConfigId': agentConfigId,
        'label': label,
        'isHuman': isHuman,
      };

  /// Parses from JSON.
  factory GameParticipant.fromJson(Map json) {
    return GameParticipant(
      agentConfigId: json['agentConfigId'] is String
          ? json['agentConfigId'] as String
          : null,
      label: json['label'] is String ? json['label'] as String : '',
      isHuman: json['isHuman'] == true,
    );
  }

  /// Copies with selectively replaced fields.
  GameParticipant copyWith({
    String? agentConfigId,
    String? label,
    bool? isHuman,
  }) {
    return GameParticipant(
      agentConfigId: agentConfigId ?? this.agentConfigId,
      label: label ?? this.label,
      isHuman: isHuman ?? this.isHuman,
    );
  }
}

/// Static settings for one game.
class GameConfig {
  /// Ruleset (drives FEN vs variant-JSON position payloads).
  final GameMode mode;

  /// Clock settings.
  final TimeControl timeControl;

  /// Move cap in plies (half-moves); game draws when reached. Null = none.
  final int? maxMoves;

  /// Wall-clock cap for the whole game in ms; checked between turns.
  /// Null = none.
  final int? maxDurationMs;

  /// Retry behavior for AI turns (forwarded to the runner).
  final RetryPolicy retryPolicy;

  /// Fallback behavior after definitive AI failure (applied by the
  /// orchestrator).
  final FallbackPolicy fallbackPolicy;

  /// Base seed for reproducible randomness (fallback picks, …).
  final int? seed;

  /// Arena pairing/selection policy label (observability only).
  final String? selectionPolicy;

  /// Creates a game config.
  const GameConfig({
    this.mode = GameMode.standard,
    this.timeControl = const TimeControl.none(),
    this.maxMoves,
    this.maxDurationMs,
    this.retryPolicy = const RetryPolicy(),
    this.fallbackPolicy = const FallbackPolicy(),
    this.seed,
    this.selectionPolicy,
  });

  /// Validates settings, returning human-readable problems (empty = valid).
  List<String> validate() {
    final problems = <String>[...timeControl.validate()];
    if (maxMoves != null && maxMoves! <= 0) {
      problems.add('maxMoves must be positive.');
    }
    if (maxDurationMs != null && maxDurationMs! <= 0) {
      problems.add('maxDurationMs must be positive.');
    }
    if (retryPolicy.maxRetries < 0) {
      problems.add('retryPolicy.maxRetries must be >= 0.');
    }
    if (fallbackPolicy.enabled &&
        fallbackPolicy.mode != FallbackPolicy.modeRandomLegal) {
      problems.add(
          'fallbackPolicy.mode "${fallbackPolicy.mode}" is not supported.');
    }
    return problems;
  }

  /// Serializes to JSON.
  Map<String, Object?> toJson() => {
        'mode': mode.name,
        'timeControl': timeControl.toJson(),
        if (maxMoves != null) 'maxMoves': maxMoves,
        if (maxDurationMs != null) 'maxDurationMs': maxDurationMs,
        'retryPolicy': retryPolicy.toJson(),
        'fallbackPolicy': fallbackPolicy.toJson(),
        if (seed != null) 'seed': seed,
        if (selectionPolicy != null) 'selectionPolicy': selectionPolicy,
      };

  /// Parses from JSON; unknown modes fall back to [GameMode.standard].
  factory GameConfig.fromJson(Map json) {
    var mode = GameMode.standard;
    for (final candidate in GameMode.values) {
      if (candidate.name == '${json['mode']}') {
        mode = candidate;
        break;
      }
    }
    int? asOptInt(Object? value) {
      if (value == null) return null;
      if (value is int) return value;
      return int.tryParse('$value');
    }

    final timeRaw = json['timeControl'];
    final retryRaw = json['retryPolicy'];
    final fallbackRaw = json['fallbackPolicy'];
    return GameConfig(
      mode: mode,
      timeControl: timeRaw is Map
          ? TimeControl.fromJson(timeRaw)
          : const TimeControl.none(),
      maxMoves: asOptInt(json['maxMoves']),
      maxDurationMs: asOptInt(json['maxDurationMs']),
      retryPolicy: retryRaw is Map
          ? RetryPolicy.fromJson(retryRaw)
          : const RetryPolicy(),
      fallbackPolicy: fallbackRaw is Map
          ? FallbackPolicy.fromJson(fallbackRaw)
          : const FallbackPolicy(),
      seed: asOptInt(json['seed']),
      selectionPolicy: json['selectionPolicy'] is String
          ? json['selectionPolicy'] as String
          : null,
    );
  }

  /// Copies with selectively replaced fields.
  GameConfig copyWith({
    GameMode? mode,
    TimeControl? timeControl,
    int? maxMoves,
    int? maxDurationMs,
    RetryPolicy? retryPolicy,
    FallbackPolicy? fallbackPolicy,
    int? seed,
    String? selectionPolicy,
  }) {
    return GameConfig(
      mode: mode ?? this.mode,
      timeControl: timeControl ?? this.timeControl,
      maxMoves: maxMoves ?? this.maxMoves,
      maxDurationMs: maxDurationMs ?? this.maxDurationMs,
      retryPolicy: retryPolicy ?? this.retryPolicy,
      fallbackPolicy: fallbackPolicy ?? this.fallbackPolicy,
      seed: seed ?? this.seed,
      selectionPolicy: selectionPolicy ?? this.selectionPolicy,
    );
  }
}

/// Terminal (or adjudicated) outcome of a game.
class GameResult {
  /// Score string: `'1-0'`, `'0-1'`, `'1/2-1/2'` or `'*'` (undecided/aborted).
  final String outcome;

  /// Machine-readable reason: `checkmate`, `resignation`, `timeout`,
  /// `maxMoves`, `maxDurationExceeded`, `stopped`, `engine`, `agreement`, …
  ///
  /// Move-limit endings are draws (`'1/2-1/2'`); wall-clock/operator aborts
  /// are undecided (`'*'`). The two must never be conflated: downstream
  /// standings and Elo updates treat them differently.
  final String reason;

  /// Winning side (`'w'`/`'b'`), or `null` for draws/undecided.
  final String? winnerColor;

  /// Creates a game result.
  ///
  /// Outcome/winner consistency is asserted in debug builds and
  /// re-validated in release builds by `reportTerminal` via [isConsistent]:
  /// `'1-0'` requires `winnerColor == 'w'`, `'0-1'` requires `'b'`, and
  /// `'1/2-1/2'`/`'*'` require `null`. [reportTerminal][1] relies on this
  /// instead of re-validating arbitrary results.
  ///
  /// [1]: Implemented in `lib/src/game/orchestrator.dart`.
  const GameResult({
    required this.outcome,
    required this.reason,
    this.winnerColor,
  }) : assert(
          (outcome == '1-0' && winnerColor == 'w') ||
              (outcome == '0-1' && winnerColor == 'b') ||
              ((outcome == '1/2-1/2' || outcome == '*') &&
                  winnerColor == null),
          'GameResult outcome/winner mismatch: $outcome / $winnerColor',
        );

  /// Consistency rule enforced by the constructor assert (debug) and by
  /// `reportTerminal` (release): decisive outcomes require their winner,
  /// draws and undecided/aborted outcomes require none, and the outcome
  /// must be a known score string.
  static bool isConsistent(String outcome, String? winnerColor) {
    switch (outcome) {
      case '1-0':
        return winnerColor == 'w';
      case '0-1':
        return winnerColor == 'b';
      case '1/2-1/2':
      case '*':
        return winnerColor == null;
      default:
        return false;
    }
  }

  /// Serializes to JSON.
  Map<String, Object?> toJson() => {
        'outcome': outcome,
        'reason': reason,
        if (winnerColor != null) 'winnerColor': winnerColor,
      };

  /// Parses from JSON.
  factory GameResult.fromJson(Map json) {
    return GameResult(
      outcome:
          json['outcome'] is String ? json['outcome'] as String : '*',
      reason: json['reason'] is String ? json['reason'] as String : '',
      winnerColor: json['winnerColor'] is String
          ? json['winnerColor'] as String
          : null,
    );
  }
}

/// Serializable point-in-time view of a game.
///
/// [position] is the opaque payload (FEN for standard, variant JSON for
/// chaotic — see [isVariant]); clocks are flattened to remaining-ms ints so
/// snapshots never reference engine objects.
class GameSnapshot {
  /// Opaque position payload (FEN or variant JSON).
  final String position;

  /// Whether [position] is variant JSON (`true`) or FEN (`false`).
  final bool isVariant;

  /// Side to move (`w`/`b`).
  final String turn;

  /// Played moves in UCI order.
  final List<String> moveHistory;

  /// Remaining clock for White in ms.
  final int remainingW;

  /// Remaining clock for Black in ms.
  final int remainingB;

  /// Orchestrator lifecycle state at snapshot time.
  final OrchestratorState state;

  /// Terminal result, when the game has one.
  final GameResult? result;

  /// Event-log sequence number (resumable consumers restart after this).
  final int eventSeq;

  /// Creates a snapshot.
  const GameSnapshot({
    required this.position,
    required this.isVariant,
    required this.turn,
    required this.moveHistory,
    required this.remainingW,
    required this.remainingB,
    required this.state,
    this.result,
    this.eventSeq = 0,
  });

  /// Serializes to JSON.
  Map<String, Object?> toJson() => {
        'position': position,
        'isVariant': isVariant,
        'turn': turn,
        'moveHistory': moveHistory,
        'remainingW': remainingW,
        'remainingB': remainingB,
        'state': state.name,
        if (result != null) 'result': result!.toJson(),
        'eventSeq': eventSeq,
      };

  /// Parses from JSON; unknown states fall back to
  /// [OrchestratorState.initializing].
  factory GameSnapshot.fromJson(Map json) {
    var state = OrchestratorState.initializing;
    for (final candidate in OrchestratorState.values) {
      if (candidate.name == '${json['state']}') {
        state = candidate;
        break;
      }
    }

    int asInt(Object? value) =>
        value is int ? value : int.tryParse('$value') ?? 0;
    final rawHistory = json['moveHistory'];
    final resultRaw = json['result'];
    return GameSnapshot(
      position: '${json['position'] ?? ''}',
      isVariant: json['isVariant'] == true,
      turn: json['turn'] is String ? json['turn'] as String : 'w',
      moveHistory:
          rawHistory is List ? [for (final e in rawHistory) '$e'] : <String>[],
      remainingW: asInt(json['remainingW']),
      remainingB: asInt(json['remainingB']),
      state: state,
      result: resultRaw is Map ? GameResult.fromJson(resultRaw) : null,
      eventSeq: asInt(json['eventSeq']),
    );
  }
}
