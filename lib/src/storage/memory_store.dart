/// In-memory [AppRepository] implementation (no Hive, no I/O).
///
/// Reference implementation for the backend/frontend split: UI and the
/// future Dart Frog server both program against [AppRepository], and this
/// class is the swappable default behind `appRepositoryProvider`
/// (see `repository_provider.dart`). [LocalAppStore] remains the durable
/// implementation; this one is for tests, previews, and the HTTP-server
/// transition period where persistence is not yet wired.
///
/// Semantics mirror `LocalAppStore`:
/// * keyed maps, sorted paginated reads (`startAfter` exclusive cursor)
/// * evaluations indexed per game (`<gameId>:<seq>`)
/// * events via a real [InMemoryEventStore] (idempotent by key)
library;

import '../stats/event_log.dart';
import 'repository.dart';

/// In-memory app store. Not durable; everything is lost on process exit.
class MemoryAppRepository implements AppRepository {
  /// Creates an empty store.
  MemoryAppRepository({InMemoryEventStore? eventStore})
    : _events = eventStore ?? InMemoryEventStore();

  final InMemoryEventStore _events;

  final Map<String, AgentJson> _agents = <String, AgentJson>{};
  final Map<String, GameJson> _games = <String, GameJson>{};
  final Map<String, TournamentJson> _tournaments = <String, TournamentJson>{};
  final Map<String, EvaluationJson> _evaluations = <String, EvaluationJson>{};
  final Map<String, ExportJson> _exports = <String, ExportJson>{};

  @override
  String get schemaVersion => storageSchemaVersion;

  @override
  EventStore get events => _events;

  Map<String, T> _paged<T>(
    Map<String, T> box, {
    int? limit,
    String? startAfter,
  }) {
    final keys = box.keys.toList()..sort();
    final out = <String, T>{};
    for (final key in keys) {
      if (startAfter != null && key.compareTo(startAfter) <= 0) continue;
      out[key] = box[key] as T;
      if (limit != null && out.length >= limit) break;
    }
    return out;
  }

  // -- Agents ---------------------------------------------------------

  @override
  Future<void> saveAgent(String agentId, AgentJson json) async {
    _agents[agentId] = Map<String, Object?>.of(json);
  }

  @override
  Future<AgentJson?> getAgent(String agentId) async => _agents[agentId];

  @override
  Future<Map<String, AgentJson>> listAgents() async =>
      Map<String, AgentJson>.of(_agents);

  @override
  Future<Map<String, AgentJson>> listAgentsPaged({
    int limit = 100,
    String? startAfter,
  }) async => _paged(_agents, limit: limit, startAfter: startAfter);

  @override
  Future<void> deleteAgent(String agentId) async {
    _agents.remove(agentId);
  }

  // -- Games ----------------------------------------------------------

  @override
  Future<void> saveGame(String gameId, GameJson json) async {
    _games[gameId] = Map<String, Object?>.of(json);
  }

  @override
  Future<GameJson?> getGame(String gameId) async => _games[gameId];

  @override
  Future<Map<String, GameJson>> listGames() async =>
      Map<String, GameJson>.of(_games);

  @override
  Future<Map<String, GameJson>> listGamesPaged({
    int limit = 100,
    String? startAfter,
  }) async => _paged(_games, limit: limit, startAfter: startAfter);

  @override
  Future<void> deleteGame(String gameId) async {
    _games.remove(gameId);
  }

  // -- Tournaments ----------------------------------------------------

  @override
  Future<void> saveTournament(String tournamentId, TournamentJson json) async {
    _tournaments[tournamentId] = Map<String, Object?>.of(json);
  }

  @override
  Future<TournamentJson?> getTournament(String tournamentId) async =>
      _tournaments[tournamentId];

  @override
  Future<Map<String, TournamentJson>> listTournaments() async =>
      Map<String, TournamentJson>.of(_tournaments);

  @override
  Future<Map<String, TournamentJson>> listTournamentsPaged({
    int limit = 100,
    String? startAfter,
  }) async => _paged(_tournaments, limit: limit, startAfter: startAfter);

  @override
  Future<void> deleteTournament(String tournamentId) async {
    _tournaments.remove(tournamentId);
  }

  // -- Evaluations ----------------------------------------------------

  static String evaluationKey(String gameId, int seq) => '$gameId:$seq';

  @override
  Future<void> saveEvaluation(
    String gameId,
    int seq,
    EvaluationJson json,
  ) async {
    _evaluations[evaluationKey(gameId, seq)] = Map<String, Object?>.of(json);
  }

  @override
  Future<List<EvaluationJson>> listEvaluations(String gameId) =>
      listEvaluationsIndexed(gameId);

  @override
  Future<List<EvaluationJson>> listEvaluationsIndexed(String gameId) async {
    final prefix = '$gameId:';
    final pairs = <int, EvaluationJson>{};
    for (final entry in _evaluations.entries) {
      if (!entry.key.startsWith(prefix)) continue;
      final seq = int.tryParse(entry.key.substring(prefix.length));
      if (seq != null) pairs[seq] = entry.value;
    }
    final seqs = pairs.keys.toList()..sort();
    return <EvaluationJson>[for (final s in seqs) pairs[s]!];
  }

  // -- Exports --------------------------------------------------------

  @override
  Future<void> saveExport(String exportId, ExportJson json) async {
    _exports[exportId] = Map<String, Object?>.of(json);
  }

  @override
  Future<ExportJson?> getExport(String exportId) async => _exports[exportId];

  @override
  Future<List<String>> listExports() async => (_exports.keys.toList()..sort());

  @override
  Future<List<String>> listExportsPaged({
    int limit = 100,
    String? startAfter,
  }) async {
    final keys = _exports.keys.toList()..sort();
    final out = <String>[];
    for (final key in keys) {
      if (startAfter != null && key.compareTo(startAfter) <= 0) continue;
      out.add(key);
      if (out.length >= limit) break;
    }
    return out;
  }

  @override
  Future<void> deleteExport(String exportId) async {
    _exports.remove(exportId);
  }

  /// Clears all boxes + events. Primarily for tests.
  void clear() {
    _agents.clear();
    _games.clear();
    _tournaments.clear();
    _evaluations.clear();
    _exports.clear();
    _events.clear();
  }
}
