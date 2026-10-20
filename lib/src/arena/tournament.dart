/// Tournament configuration, per-game references, and overall state.
///
/// A tournament is a fixed list of scheduled games ([TournamentState.games])
/// generated up-front from [TournamentConfig] by `scheduler.dart`. The
/// scheduler then executes them with bounded concurrency and updates each
/// [TournamentGameRef] in place. This file holds data only — no execution.
library;

/// Lifecycle status of a single scheduled tournament game.
enum TournamentGameStatus {
  /// Scheduled but not started.
  pending,

  /// Currently executing.
  running,

  /// Finished with a recorded result (win/loss/draw).
  completed,

  /// Failed due to an infrastructure error (isolated; never fails siblings).
  failed,

  /// Cancelled via [ArenaScheduler.cancel] or `failFast` abort.
  cancelled,
}

/// Terminal result of a finished game, from White's perspective.
enum TournamentGameResult {
  /// White won.
  whiteWin,

  /// Black won.
  blackWin,

  /// Draw (agreement, stalemate, repetition, material, move limit).
  draw,
}

/// Static configuration for one tournament.
class TournamentConfig {
  /// Stable tournament id (UUID recommended).
  final String id;

  /// Human-readable name.
  final String name;

  /// Agent ids participating. Must contain >= 2 distinct entries.
  final List<String> agentIds;

  /// Total number of games to schedule across all pairings.
  final int games;

  /// Time-control descriptor, e.g. `{'kind': 'perMoveMs', 'ms': 30000}`.
  /// Untyped so future clocks (increment, per-game) need no migration.
  final Map<String, Object?> timeControlJson;

  /// Game mode: `'standard'` or `'chaotic'`.
  final String mode;

  /// Maximum games running concurrently. Must be >= 1.
  final int maxConcurrentGames;

  /// When true, repeat pairings swap colors to balance White advantage.
  final bool colorAlternation;

  /// Seed for deterministic pairing order and per-game seeds. Null means
  /// non-deterministic (scheduler seeds from entropy).
  final int? seed;

  /// Retry policy descriptor, e.g. `{'maxRetries': 1, 'retryOn': [...]}`.
  final Map<String, Object?> retryJson;

  /// Fallback policy descriptor, e.g. `{'enabled': true, 'strategy': ...}`.
  final Map<String, Object?> fallbackJson;

  /// Retain per-turn logs after the tournament (else only summaries).
  final bool retainLogs;

  /// Write a versioned JSON export on completion (see `export.dart`).
  final bool exportResults;

  /// Abort remaining pending games on the first infrastructure failure.
  final bool failFast;

  /// Creates a config. Asserts basic invariants in debug builds.
  TournamentConfig({
    required this.id,
    required this.name,
    required List<String> agentIds,
    required this.games,
    Map<String, Object?>? timeControlJson,
    this.mode = 'standard',
    this.maxConcurrentGames = 1,
    this.colorAlternation = true,
    this.seed,
    Map<String, Object?>? retryJson,
    Map<String, Object?>? fallbackJson,
    this.retainLogs = true,
    this.exportResults = true,
    this.failFast = false,
  })  : agentIds = List<String>.unmodifiable(agentIds),
        timeControlJson =
            Map<String, Object?>.unmodifiable(timeControlJson ?? const {}),
        retryJson = Map<String, Object?>.unmodifiable(retryJson ?? const {}),
        fallbackJson =
            Map<String, Object?>.unmodifiable(fallbackJson ?? const {}) {
    assert(id.isNotEmpty, 'TournamentConfig.id must be non-empty');
    assert(Set<String>.of(agentIds).length >= 2,
        'TournamentConfig needs >= 2 distinct agentIds');
    assert(games >= 1, 'TournamentConfig.games must be >= 1');
    assert(maxConcurrentGames >= 1, 'maxConcurrentGames must be >= 1');
    assert(mode == 'standard' || mode == 'chaotic',
        'mode must be standard or chaotic');
  }

  /// Serializes with stable field ordering.
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'agentIds': agentIds,
        'games': games,
        'timeControlJson': timeControlJson,
        'mode': mode,
        'maxConcurrentGames': maxConcurrentGames,
        'colorAlternation': colorAlternation,
        'seed': seed,
        'retryJson': retryJson,
        'fallbackJson': fallbackJson,
        'retainLogs': retainLogs,
        'exportResults': exportResults,
        'failFast': failFast,
      };

  /// Parses [toJson] output. Throws [FormatException] on invalid input.
  factory TournamentConfig.fromJson(Map<String, Object?> json) {
    String str(String k) {
      final v = json[k];
      if (v is! String || v.isEmpty) {
        throw FormatException('TournamentConfig.$k must be a non-empty String');
      }
      return v;
    }

    final rawAgents = json['agentIds'];
    if (rawAgents is! List || rawAgents.length < 2) {
      throw const FormatException('TournamentConfig.agentIds needs >= 2 entries');
    }
    final agents = rawAgents.map((e) => e.toString()).toList();
    final games = json['games'];
    if (games is! int || games < 1) {
      throw const FormatException('TournamentConfig.games must be an int >= 1');
    }
    Map<String, Object?> mapOf(String k) {
      final v = json[k];
      if (v == null) return const <String, Object?>{};
      if (v is Map) return Map<String, Object?>.from(v);
      throw FormatException('TournamentConfig.$k must be a Map');
    }

    return TournamentConfig(
      id: str('id'),
      name: str('name'),
      agentIds: agents,
      games: games,
      timeControlJson: mapOf('timeControlJson'),
      mode: json['mode'] is String ? json['mode'] as String : 'standard',
      maxConcurrentGames:
          json['maxConcurrentGames'] is int ? json['maxConcurrentGames'] as int : 1,
      colorAlternation: json['colorAlternation'] is bool
          ? json['colorAlternation'] as bool
          : true,
      seed: json['seed'] is int ? json['seed'] as int : null,
      retryJson: mapOf('retryJson'),
      fallbackJson: mapOf('fallbackJson'),
      retainLogs: json['retainLogs'] is bool ? json['retainLogs'] as bool : true,
      exportResults:
          json['exportResults'] is bool ? json['exportResults'] as bool : true,
      failFast: json['failFast'] is bool ? json['failFast'] as bool : false,
    );
  }
}

/// Mutable reference to one scheduled game within a tournament.
///
/// The scheduler owns these: it flips [status] pending -> running ->
/// completed/failed/cancelled and sets [result]/[error] exactly once at
/// terminal transition.
class TournamentGameRef {
  /// Stable game id (unique within the tournament).
  final String gameId;

  /// Agent playing White / Black.
  final String whiteAgentId;
  final String blackAgentId;

  /// Current lifecycle status.
  TournamentGameStatus status;

  /// Terminal result; non-null iff [status] is completed.
  TournamentGameResult? result;

  /// Infrastructure failure description; non-null iff [status] is failed.
  String? error;

  /// Creates a pending game reference.
  TournamentGameRef({
    required this.gameId,
    required this.whiteAgentId,
    required this.blackAgentId,
    this.status = TournamentGameStatus.pending,
    this.result,
    this.error,
  });

  /// Serializes with stable field ordering.
  Map<String, Object?> toJson() => <String, Object?>{
        'gameId': gameId,
        'whiteAgentId': whiteAgentId,
        'blackAgentId': blackAgentId,
        'status': status.name,
        'result': result?.name,
        'error': error,
      };

  /// Parses [toJson] output. Throws [FormatException] on invalid input.
  factory TournamentGameRef.fromJson(Map<String, Object?> json) {
    String requireString(String key) {
      final value = json[key];
      if (value is String) return value;
      throw FormatException('TournamentGameRef.$key must be a String');
    }

    TournamentGameStatus status;
    try {
      status = TournamentGameStatus.values.byName(requireString('status'));
    } catch (_) {
      throw const FormatException('TournamentGameRef.status is invalid');
    }
    TournamentGameResult? result;
    if (json['result'] != null) {
      try {
        result = TournamentGameResult.values.byName(requireString('result'));
      } catch (_) {
        throw const FormatException('TournamentGameRef.result is invalid');
      }
    }
    return TournamentGameRef(
      gameId: requireString('gameId'),
      whiteAgentId: requireString('whiteAgentId'),
      blackAgentId: requireString('blackAgentId'),
      status: status,
      result: result,
      error: json['error'] is String ? json['error'] as String : null,
    );
  }

  @override
  String toString() =>
      'TournamentGameRef($gameId $whiteAgentId vs $blackAgentId $status)';
}

/// Live state of one tournament run.
class TournamentState {
  /// Config this run was generated from.
  final TournamentConfig config;

  /// All scheduled games (fixed length once generated).
  final List<TournamentGameRef> games;

  /// Wall-clock start (UTC).
  final DateTime startedAt;

  /// Wall-clock end (UTC), once all games are terminal.
  DateTime? finishedAt;

  /// Creates a state. [games] is kept as a mutable list so the scheduler
  /// can update refs in place.
  TournamentState({
    required this.config,
    required this.games,
    DateTime? startedAt,
    this.finishedAt,
  }) : startedAt = (startedAt ?? DateTime.now().toUtc()).toUtc();

  /// Number of games in a terminal status.
  int get completedCount => games
      .where((g) =>
          g.status == TournamentGameStatus.completed ||
          g.status == TournamentGameStatus.failed ||
          g.status == TournamentGameStatus.cancelled)
      .length;

  /// True when every game is terminal.
  bool get isFinished => finishedAt != null;

  /// Serializes with stable field ordering.
  Map<String, Object?> toJson() => <String, Object?>{
        'config': config.toJson(),
        'games': games.map((g) => g.toJson()).toList(),
        'startedAt': startedAt.toIso8601String(),
        'finishedAt': finishedAt?.toIso8601String(),
      };
}
