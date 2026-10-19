/// Bounded-concurrency tournament scheduler with failure isolation.
///
/// # Fairness guarantees
///
/// 1. **Color balance**: with [TournamentConfig.colorAlternation] enabled,
///    consecutive games of the same agent pair swap colors, so over an even
///    number of games each agent plays White exactly half the time. Over an
///    odd number the imbalance is at most one game.
/// 2. **Pair coverage**: [generatePairings] cycles through all unordered
///    agent pairs round-robin before repeating, so no pair starves while
///    another repeats (up to the remainder when `totalGames` is not a
///    multiple of the pair count).
/// 3. **Determinism**: given the same config seed, pairing order, color
///    assignment, and per-game seeds are identical across runs. A null seed
///    draws from entropy and is explicitly non-reproducible.
/// 4. **No cross-game contamination**: each game runs through an isolated
///    [GameFactory] call; an exception fails only that game's
///    [TournamentGameRef] (marked `failed` with `error`), never its batch
///    siblings.
///
/// # Orchestrator decoupling
///
/// The scheduler never imports the orchestrator. Game execution is injected
/// as a [GameFactory] (or the equivalent [GameRunner] function type), which
/// tests replace with fakes.
library;

import 'dart:async';
import 'dart:math';

import 'tournament.dart';

/// One scheduled pairing: who plays which color in which game.
class Pairing {
  /// Stable game id (`<tournamentId>#<index>` by convention).
  final String gameId;

  /// Agent playing White / Black.
  final String whiteAgentId;
  final String blackAgentId;

  /// Zero-based index in the generated schedule.
  final int roundIndex;

  /// Creates a pairing.
  const Pairing({
    required this.gameId,
    required this.whiteAgentId,
    required this.blackAgentId,
    required this.roundIndex,
  });

  /// Serializes with stable field ordering.
  Map<String, Object?> toJson() => <String, Object?>{
        'gameId': gameId,
        'whiteAgentId': whiteAgentId,
        'blackAgentId': blackAgentId,
        'roundIndex': roundIndex,
      };
}

/// Outcome of one executed game, as reported by the injected factory.
class GameResultSummary {
  /// Matches the requesting [Pairing.gameId].
  final String gameId;
  final String whiteAgentId;
  final String blackAgentId;

  /// Terminal result, if the game completed normally.
  final TournamentGameResult? result;

  /// Non-null when the game failed at the infrastructure level
  /// (exception text). Mutually exclusive with [result].
  final String? infraFailure;

  /// Creates a summary. Exactly one of [result]/[infraFailure] should be
  /// set by convention (both null = cancelled).
  const GameResultSummary({
    required this.gameId,
    required this.whiteAgentId,
    required this.blackAgentId,
    this.result,
    this.infraFailure,
  });

  /// Serializes with stable field ordering.
  Map<String, Object?> toJson() => <String, Object?>{
        'gameId': gameId,
        'whiteAgentId': whiteAgentId,
        'blackAgentId': blackAgentId,
        'result': result?.name,
        'infraFailure': infraFailure,
      };
}

/// Abstraction over single-game execution (usually the orchestrator).
///
/// The scheduler calls [runSingleGame] once per pairing. Implementations
/// may throw; the scheduler converts throws into per-game `failed`
/// records. Implementations must be safe for concurrent use up to the
/// tournament's `maxConcurrentGames`.
abstract class GameFactory {
  /// Runs one game for [pairing] with deterministic [seed].
  Future<GameResultSummary> runSingleGame(Pairing pairing, int seed);
}

/// Function-typed equivalent of [GameFactory.runSingleGame] for callers
/// that prefer closures over classes.
typedef GameRunner = Future<GameResultSummary> Function(
    Pairing pairing, int seed);

/// Adapter turning a [GameRunner] closure into a [GameFactory].
class FunctionGameFactory implements GameFactory {
  /// Underlying closure.
  final GameRunner runner;

  /// Wraps [runner].
  const FunctionGameFactory(this.runner);

  @override
  Future<GameResultSummary> runSingleGame(Pairing pairing, int seed) =>
      runner(pairing, seed);
}

/// Progress snapshot broadcast during [ArenaScheduler.run].
class SchedulerProgress {
  /// Games in a terminal state so far.
  final int completed;

  /// Total scheduled games.
  final int total;

  /// Game id most recently transitioned, if any.
  final String? currentGameId;

  /// Creates a snapshot.
  const SchedulerProgress({
    required this.completed,
    required this.total,
    this.currentGameId,
  });

  /// Fraction in `[0, 1]` (1 when [total] is 0).
  double get fraction => total == 0 ? 1.0 : completed / total;
}

/// Executes a tournament's games with bounded concurrency.
///
/// Usage: build [TournamentState] via [generateSchedule] (or
/// [generatePairings]), construct with a [GameFactory], then `await run()`.
class ArenaScheduler {
  /// State whose [TournamentState.games] are executed in place.
  final TournamentState state;

  /// Game executor (orchestrator behind the abstraction).
  final GameFactory gameFactory;

  /// Broadcast progress stream.
  Stream<SchedulerProgress> get progress => _progress.stream;
  final StreamController<SchedulerProgress> _progress =
      StreamController<SchedulerProgress>.broadcast();

  bool _cancelled = false;
  bool _running = false;

  /// Creates a scheduler for [state] using [gameFactory].
  ArenaScheduler({required this.state, required this.gameFactory});

  /// Requests cancellation. Running games finish; pending games are
  /// marked `cancelled`. Safe to call multiple times.
  void cancel() {
    _cancelled = true;
  }

  /// Whether [cancel] has been requested.
  bool get isCancelled => _cancelled;

  /// Generates pairings for [agentIds] covering [totalGames] games.
  ///
  /// Cycles round-robin over all unordered pairs `(i, j)`; with
  /// [alternateColors] each repeat of a pair swaps White/Black,
  /// otherwise colors are drawn from [seed]. Game order is shuffled
  /// deterministically by [seed] (Fisher-Yates with `Random(seed)`).
  /// A null [seed] uses entropy (non-reproducible).
  static List<Pairing> generatePairings({
    required List<String> agentIds,
    required int totalGames,
    required bool alternateColors,
    int? seed,
    String gameIdPrefix = 'game',
  }) {
    assert(agentIds.length >= 2, 'need >= 2 agents');
    assert(totalGames >= 1, 'need >= 1 game');
    final random = seed == null ? Random() : Random(seed);

    // All unordered pairs, lexicographically ordered for determinism.
    final pairs = <List<String>>[];
    final sorted = List<String>.of(agentIds)..sort();
    for (var i = 0; i < sorted.length; i++) {
      for (var j = i + 1; j < sorted.length; j++) {
        pairs.add(<String>[sorted[i], sorted[j]]);
      }
    }

    // Round-robin over pairs; per-pair occurrence count drives color swap.
    final occurrences = <String, int>{};
    final raw = <Pairing>[];
    for (var g = 0; g < totalGames; g++) {
      final pair = pairs[g % pairs.length];
      final pairKey = '${pair[0]}|${pair[1]}';
      final occ = occurrences[pairKey] ?? 0;
      occurrences[pairKey] = occ + 1;
      String white;
      String black;
      if (alternateColors) {
        white = occ.isEven ? pair[0] : pair[1];
        black = occ.isEven ? pair[1] : pair[0];
      } else {
        final swap = random.nextBool();
        white = swap ? pair[1] : pair[0];
        black = swap ? pair[0] : pair[1];
      }
      raw.add(Pairing(
        gameId: '$gameIdPrefix#${g + 1}',
        whiteAgentId: white,
        blackAgentId: black,
        roundIndex: g,
      ));
    }

    // Deterministic shuffle so schedule order does not favor early pairs.
    for (var i = raw.length - 1; i > 0; i--) {
      final j = random.nextInt(i + 1);
      final tmp = raw[i];
      raw[i] = raw[j];
      raw[j] = tmp;
    }
    return List<Pairing>.unmodifiable(raw);
  }

  /// Builds a [TournamentState] for [config] with generated game refs.
  static TournamentState generateSchedule(TournamentConfig config) {
    final pairings = generatePairings(
      agentIds: config.agentIds,
      totalGames: config.games,
      alternateColors: config.colorAlternation,
      seed: config.seed,
      gameIdPrefix: '${config.id}#game',
    );
    return TournamentState(
      config: config,
      games: pairings
          .map((p) => TournamentGameRef(
                gameId: p.gameId,
                whiteAgentId: p.whiteAgentId,
                blackAgentId: p.blackAgentId,
              ))
          .toList(),
    );
  }

  /// Deterministic per-game seed derived from the tournament seed and the
  /// game's index, so re-runs reproduce identical game randomness.
  static int gameSeed(int? tournamentSeed, int index) {
    if (tournamentSeed == null) return Random().nextInt(1 << 31);
    // SplitMix-style avalanche without extra Random instances.
    var z = (tournamentSeed + 0x9E3779B9 + index * 0x85EBCA6B) & 0x7FFFFFFF;
    z ^= z >> 15;
    z = (z * 0x2C1B3C6D) & 0x7FFFFFFF;
    z ^= z >> 12;
    return z;
  }

  /// Runs all scheduled games to completion (or cancellation).
  ///
  /// Games execute in batches of `maxConcurrentGames` via `Future.wait`.
  /// Each game is isolated: throws from [gameFactory] (or a returned
  /// [GameResultSummary.infraFailure]) mark only that game `failed`.
  /// With `failFast`, the first failure cancels all pending games.
  /// Emits [SchedulerProgress] after every game transition and sets
  /// [TournamentState.finishedAt] on return.
  Future<TournamentState> run() async {
    if (_running) {
      throw StateError('ArenaScheduler.run() is already in progress');
    }
    _running = true;
    try {
      final games = state.games;
      final maxConcurrent = state.config.maxConcurrentGames < 1
          ? 1
          : state.config.maxConcurrentGames;
      var done = 0;
      _emit(done, games.length, null);

      for (var i = 0; i < games.length; i += maxConcurrent) {
        if (_cancelled) {
          _cancelFrom(i);
          break;
        }
        final batch = games.sublist(
            i, (i + maxConcurrent).clamp(0, games.length));
        await Future.wait(batch.map((ref) => _runOne(ref).then((_) {
              done++;
              _emit(done, games.length, ref.gameId);
              if (ref.status == TournamentGameStatus.failed &&
                  state.config.failFast) {
                cancel();
              }
            })));
        if (_cancelled) {
          _cancelFrom(i + batch.length);
          break;
        }
      }
      state.finishedAt ??= DateTime.now().toUtc();
      return state;
    } finally {
      _running = false;
      await _progress.close();
    }
  }

  /// Executes one game ref with failure isolation. Never throws.
  Future<void> _runOne(TournamentGameRef ref) async {
    if (_cancelled || ref.status != TournamentGameStatus.pending) return;
    ref.status = TournamentGameStatus.running;
    try {
      final index = state.games.indexOf(ref);
      final pairing = Pairing(
        gameId: ref.gameId,
        whiteAgentId: ref.whiteAgentId,
        blackAgentId: ref.blackAgentId,
        roundIndex: index,
      );
      final summary = await gameFactory.runSingleGame(
        pairing,
        gameSeed(state.config.seed, index < 0 ? 0 : index),
      );
      if (summary.infraFailure != null) {
        ref
          ..status = TournamentGameStatus.failed
          ..error = summary.infraFailure;
      } else if (summary.result != null) {
        ref
          ..status = TournamentGameStatus.completed
          ..result = summary.result;
      } else {
        // Factory returned neither result nor failure: treat as cancelled.
        ref.status = TournamentGameStatus.cancelled;
      }
    } catch (e) {
      // Failure isolation: record and continue with siblings.
      ref
        ..status = TournamentGameStatus.failed
        ..error = e.toString();
    }
  }

  /// Marks games from [fromIndex] onward as cancelled (pending only).
  void _cancelFrom(int fromIndex) {
    for (var i = fromIndex; i < state.games.length; i++) {
      final ref = state.games[i];
      if (ref.status == TournamentGameStatus.pending) {
        ref.status = TournamentGameStatus.cancelled;
      }
    }
  }

  void _emit(int done, int total, String? gameId) {
    if (!_progress.isClosed) {
      _progress.add(SchedulerProgress(
          completed: done, total: total, currentGameId: gameId));
    }
  }
}
