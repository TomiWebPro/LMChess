/// Repository contract for app persistence.
///
/// All entities are plain JSON maps ([EntityJson]) so the domain layers
/// (arena/stats/review) keep owning their typed models without the
/// storage layer duplicating them. Repositories store, retrieve, and
/// delete; serialization lives with the models (`toJson`/`fromJson`).
///
/// # Schema versioning
///
/// [storageSchemaVersion] is the current store schema. Every persisted
/// envelope carries its writer version; [LocalAppStore.migrate] upgrades
/// older envelopes. Breaking changes bump the version and add a branch
/// in `migrate()` — never silent reinterpretation.
///
/// # Box layout (Hive)
///
/// | box name ([StorageBoxes]) | contents                              |
/// |---------------------------|---------------------------------------|
/// | `agents`                  | agent config JSON by agent id         |
/// | `games`                   | game summary JSON by game id          |
/// | `events`                  | event JSON by idempotency key         |
/// | `tournaments`             | tournament state JSON by tournament id|
/// | `evaluations`             | eval result JSON by `<game>:<seq>` key|
/// | `exports`                 | export JSON by export id              |
/// | `meta`                    | schema version + retention cursors    |
///
/// # Pagination
///
/// `list*Paged` methods page over keys in ascending order; [startAfter] is
/// an exclusive cursor (pass the last key of the previous page). The unpaged
/// `list*` methods are thin wrappers that read everything.
library;

import '../stats/event_log.dart';

/// Current storage schema version. Bump on breaking envelope changes.
const String storageSchemaVersion = '1';

/// Key in the `meta` box holding the writer schema version.
const String metaSchemaVersionKey = 'schemaVersion';

/// `meta` cursor: watermark of the last event prune (`pruneEvents`).
const String metaRetentionEventsCursorKey = 'retention.events.cursor';

/// `meta` cursor: watermark of the last game prune (`pruneGames`).
const String metaRetentionGamesCursorKey = 'retention.games.cursor';

/// Untyped JSON entitymap. All repository values use this shape.
typedef EntityJson = Map<String, Object?>;

/// Agent configuration JSON (`agentId -> config`).
typedef AgentJson = EntityJson;

/// Game summary JSON (`gameId -> summary`).
typedef GameJson = EntityJson;

/// Tournament state JSON (`tournamentId -> state`).
typedef TournamentJson = EntityJson;

/// Per-move evaluation JSON (`<gameId>:<seq> -> evaluation`).
typedef EvaluationJson = EntityJson;

/// Tournament export JSON (`exportId -> export envelope`).
typedef ExportJson = EntityJson;

/// Hive box names. Centralized so UI/debug tools open the same boxes.
abstract class StorageBoxes {
  /// Agent configs by agent id.
  static const String agents = 'agents';

  /// Game summaries by game id.
  static const String games = 'games';

  /// Events by idempotency key (also backs [EventStore]).
  static const String events = 'events';

  /// Tournament states by tournament id.
  static const String tournaments = 'tournaments';

  /// Evaluations by `<gameId>:<seq>`.
  static const String evaluations = 'evaluations';

  /// Saved exports by export id.
  static const String exports = 'exports';

  /// Schema version + retention cursors.
  static const String meta = 'meta';

  /// All data boxes (excludes transient state).
  static const List<String> all = <String>[
    agents,
    games,
    events,
    tournaments,
    evaluations,
    exports,
    meta,
  ];
}

/// Persistence contract for agents, games, tournaments, evaluations,
/// exports, plus the [EventStore] event stream.
abstract class AppRepository {
  /// Schema version this repository writes.
  String get schemaVersion;

  /// Live event stream (idempotent append; see [EventStore]).
  EventStore get events;

  // -- Agents ---------------------------------------------------------

  /// Upserts agent config JSON under [agentId].
  Future<void> saveAgent(String agentId, AgentJson json);

  /// Returns agent config JSON, or null when absent.
  Future<AgentJson?> getAgent(String agentId);

  /// All agent configs keyed by agent id.
  Future<Map<String, AgentJson>> listAgents();

  /// Paginated [listAgents]: at most [limit] configs whose key sorts
  /// strictly after [startAfter] (exclusive cursor = last key of the
  /// previous page). Ordered ascending by key for stable cursoring.
  Future<Map<String, AgentJson>> listAgentsPaged({
    int limit = 100,
    String? startAfter,
  });

  /// Deletes the agent config. No-op when absent.
  Future<void> deleteAgent(String agentId);

  // -- Games ----------------------------------------------------------

  /// Upserts game summary JSON under [gameId].
  Future<void> saveGame(String gameId, GameJson json);

  /// Returns game summary JSON, or null when absent.
  Future<GameJson?> getGame(String gameId);

  /// All game summaries keyed by game id.
  Future<Map<String, GameJson>> listGames();

  /// Paginated [listGames] (see [listAgentsPaged] for cursor semantics).
  Future<Map<String, GameJson>> listGamesPaged({
    int limit = 100,
    String? startAfter,
  });

  /// Deletes the game summary. No-op when absent.
  Future<void> deleteGame(String gameId);

  // -- Tournaments ----------------------------------------------------

  /// Upserts tournament state JSON under [tournamentId].
  Future<void> saveTournament(String tournamentId, TournamentJson json);

  /// Returns tournament state JSON, or null when absent.
  Future<TournamentJson?> getTournament(String tournamentId);

  /// All tournament states keyed by tournament id.
  Future<Map<String, TournamentJson>> listTournaments();

  /// Paginated [listTournaments] (see [listAgentsPaged] for cursor
  /// semantics).
  Future<Map<String, TournamentJson>> listTournamentsPaged({
    int limit = 100,
    String? startAfter,
  });

  /// Deletes the tournament state. No-op when absent.
  Future<void> deleteTournament(String tournamentId);

  // -- Evaluations ----------------------------------------------------

  /// Upserts evaluation JSON under `<gameId>:<seq>`.
  Future<void> saveEvaluation(String gameId, int seq, EvaluationJson json);

  /// All evaluations for [gameId] ordered by seq ascending.
  ///
  /// Backed by a per-game key index in `meta` (`evalIndex:<gameId>`), so a
  /// lookup is O(matches) rather than a full box scan; the index is rebuilt
  /// lazily when missing (legacy data written before the index existed).
  Future<List<EvaluationJson>> listEvaluations(String gameId);

  /// Alias of [listEvaluations] making the indexed lookup explicit for
  /// callers that want to document the scaling property.
  Future<List<EvaluationJson>> listEvaluationsIndexed(String gameId);

  // -- Exports --------------------------------------------------------

  /// Upserts export JSON under [exportId].
  Future<void> saveExport(String exportId, ExportJson json);

  /// Returns export JSON, or null when absent.
  Future<ExportJson?> getExport(String exportId);

  /// All export ids (sorted ascending).
  Future<List<String>> listExports();

  /// Paginated [listExports] (see [listAgentsPaged] for cursor semantics).
  Future<List<String>> listExportsPaged({int limit = 100, String? startAfter});

  /// Deletes the export. No-op when absent.
  Future<void> deleteExport(String exportId);
}
