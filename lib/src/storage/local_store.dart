/// Hive-backed [AppRepository] (+ [EventStore]) implementation.
///
/// # Initialization
///
/// Call [LocalAppStore.init] once at startup (it resolves the documents
/// directory via `path_provider` unless [dbPath] is given, inits Hive,
/// opens all [StorageBoxes] with per-box corruption recovery, and runs
/// [migrate]). Call [close] on app shutdown. All CRUD methods throw
/// [StateError] before [init].
///
/// Each box is opened independently: if `openBox` throws, the corrupt box
/// files are *quarantined* (renamed aside, never deleted) and a fresh empty
/// box is opened so the rest of the store still loads. Quarantined boxes and
/// skipped entries are exposed via [integrityReport].
///
/// # Pending writes
///
/// [EventStore.append] is synchronous by contract, so the store cannot await
/// its `put`. Instead every such fire-and-forget write is tracked, and
/// [flushWrites] completes once they all settle. Callers **should
/// `await store.flushWrites()` before [close]** (and in tests before
/// asserting). A write failure is reported through the [onWriteError]
/// constructor hook (or logged) and recorded in [lastWriteError].
///
/// # Redaction
///
/// **Every** persisted map (agents, games, tournaments, events, evaluations,
/// exports) is passed through [redactForStorage] — a storage variant of the
/// tournament-export [redactSecrets] that redacts secret-looking values
/// (keys like `apiKey`, `token`, `openAIKey`, case-insensitive) with
/// `'***REDACTED***'` while preserving opaque `*Ref` fields such as
/// `apiKeyRef`. The true guarantee: secrets are resolved through
/// `SecureKeyStore` (`flutter_secure_storage`) and *never* belong in Hive;
/// redaction is a defensive net, not a vault — a secret stored under an
/// unrecognized key name would still be written.
///
/// # Migration strategy
///
/// Envelopes are stored as `{'v': <schemaVersion>, 'data': {...}}`.
/// [migrate] walks **every** box and inspects each envelope's writer `v`:
///
/// * absent/legacy (bare map) → rewritten in canonical v1 envelope form;
/// * older than [storageSchemaVersion] → upgraded through version branches;
/// * equal → left untouched;
/// * newer than or unparseable → **refused**, never silently reinterpreted,
///   and listed in the returned [MigrationReport].
///
/// The report is also logged. The `meta/schemaVersion` stamp is written last.
///
/// # Retention policy hooks
///
/// [pruneEvents] and [pruneGames] delete data beyond caller-supplied bounds
/// (age and/or count). They are opt-in — nothing auto-deletes — so UI
/// settings can wire them to user-chosen retention. Each prune advances a
/// cursor in `meta` ([metaRetentionEventsCursorKey] /
/// [metaRetentionGamesCursorKey]); these are bookkeeping watermarks.
///
/// Scaling note: pruning currently performs a full scan of its box. For very
/// large stores run it during idle time (or persist richer indexes) — the
/// cursors make it possible to resume rather than re-scan from scratch.
library;

import 'dart:async';
import 'dart:developer' show log;
import 'dart:io';

import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../stats/event_log.dart';
import 'redaction.dart';
import 'repository.dart';
import 'storage_reports.dart';

/// Hive-backed application store.
class LocalAppStore implements AppRepository, EventStore {
  /// Creates the store.
  ///
  /// [onWriteError] is invoked for failures of fire-and-forget writes (only
  /// [EventStore.append] today). When omitted, the first failure is recorded
  /// in [lastWriteError] and logged via `dart:developer`.
  LocalAppStore({this.onWriteError});

  /// Optional sink for asynchronous write failures.
  final void Function(Object error, StackTrace stackTrace)? onWriteError;

  /// Subdirectory name under the documents directory.
  static const String dbDirName = 'llm_chess_arena';

  /// Schema version written by this store.
  @override
  String get schemaVersion => storageSchemaVersion;

  bool _ready = false;
  bool _boxesOpen = false;

  /// First asynchronous write failure seen ([onWriteError] or the default
  /// logging path), or `null` when none occurred.
  Object? _lastWriteError;

  /// Stack trace captured with [lastWriteError].
  StackTrace? _lastWriteStackTrace;

  /// How far the last [migrate] got (for diagnostics); null before [init].
  MigrationReport? _lastMigrationReport;

  /// In-flight fire-and-forget writes (see [flushWrites]).
  final Set<Future<void>> _pendingWrites = <Future<void>>{};

  /// Boxes quarantined at open because `openBox` threw.
  final Set<String> _quarantinedBoxes = <String>{};

  /// Box name -> keys skipped while reading/listing.
  final Map<String, List<String>> _corruptKeys = <String, List<String>>{};

  late Box _agents;
  late Box _games;
  late Box _events;
  late Box _tournaments;
  late Box _evaluations;
  late Box _exports;
  late Box _meta;

  /// True after [init] completes, false after [close].
  bool get isReady => _ready;

  /// First asynchronous write failure, or `null`. See [onWriteError].
  Object? get lastWriteError => _lastWriteError;

  /// Stack trace captured with [lastWriteError], or `null`.
  StackTrace? get lastWriteStackTrace => _lastWriteStackTrace;

  /// Number of fire-and-forget writes not yet settled. See [flushWrites].
  int get pendingWriteCount => _pendingWrites.length;

  /// Report of the most recent [migrate], or `null` before [init].
  MigrationReport? get lastMigrationReport => _lastMigrationReport;

  /// Snapshot of quarantined boxes + skipped corrupt entries.
  IntegrityReport integrityReport() => IntegrityReport(
    quarantinedBoxes: _quarantinedBoxes,
    corruptEntries: _corruptKeys,
  );

  /// Opens all boxes and runs [migrate].
  ///
  /// [dbPath]: override directory (tests). When null, uses
  /// `getApplicationDocumentsDirectory()/<dbDirName>`.
  Future<void> init({String? dbPath}) async {
    if (_ready) return;
    final dir =
        dbPath ??
        '${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}$dbDirName';
    await Directory(dir).create(recursive: true);
    await Hive.initFlutter(dir);
    _agents = await _openBoxSafe(StorageBoxes.agents, dir);
    _games = await _openBoxSafe(StorageBoxes.games, dir);
    _events = await _openBoxSafe(StorageBoxes.events, dir);
    _tournaments = await _openBoxSafe(StorageBoxes.tournaments, dir);
    _evaluations = await _openBoxSafe(StorageBoxes.evaluations, dir);
    _exports = await _openBoxSafe(StorageBoxes.exports, dir);
    _meta = await _openBoxSafe(StorageBoxes.meta, dir);
    _boxesOpen = true;
    _lastMigrationReport = await migrate();
    if (!_lastMigrationReport!.isClean) {
      log(
        'LocalAppStore.migrate: $_lastMigrationReport',
        name: 'LocalAppStore',
      );
    }
    final integrity = integrityReport();
    if (!integrity.isClean) {
      log(
        'LocalAppStore.integrity: ${integrity.quarantinedBoxCount} box(es) '
        'quarantined, ${integrity.corruptEntryCount} corrupt entry(ies): '
        '$integrity',
        name: 'LocalAppStore',
      );
    }
    _ready = true;
  }

  /// Closes all *arena* boxes individually (never the global `Hive.close`,
  /// which would close unrelated boxes owned by embedding apps/tests).
  ///
  /// Pending fire-and-forget writes are flushed first. Idempotent.
  Future<void> close() async {
    if (!_ready) return;
    await flushWrites();
    for (final name in StorageBoxes.all) {
      if (!Hive.isBoxOpen(name)) continue;
      try {
        await Hive.box(name).close();
      } on Object catch (error, stack) {
        log(
          'LocalAppStore: failed to close box "$name": $error',
          name: 'LocalAppStore',
          error: error,
          stackTrace: stack,
        );
      }
    }
    _ready = false;
    _boxesOpen = false;
  }

  /// Completes when every pending fire-and-forget write has settled.
  ///
  /// Failures are surfaced through [onWriteError]/[lastWriteError], not by
  /// throwing here. Call this before [close] (and in tests before reading).
  Future<void> flushWrites() async {
    while (_pendingWrites.isNotEmpty) {
      final pending = List<Future<void>>.of(_pendingWrites);
      await Future.wait<void>(<Future<void>>[
        for (final future in pending)
          future.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      ]);
    }
  }

  void _requireReady() {
    if (!_ready) {
      throw StateError('LocalAppStore.init() must complete before use');
    }
  }

  // -- Corrupt-box recovery -------------------------------------------

  /// Opens [name], quarantining and recreating it if `openBox` throws.
  Future<Box> _openBoxSafe(String name, String dir) async {
    try {
      return await Hive.openBox(name);
    } on Object catch (error, stack) {
      _quarantinedBoxes.add(name);
      log(
        'LocalAppStore: box "$name" failed to open; quarantining',
        name: 'LocalAppStore',
        error: error,
        stackTrace: stack,
      );
      if (Hive.isBoxOpen(name)) {
        try {
          await Hive.box(name).close();
        } on Object {
          // Best effort; the quarantine below is what matters.
        }
      }
      await _quarantineBoxFiles(name, dir);
      // Fresh empty box so the remaining boxes still load.
      return await Hive.openBox(name);
    }
  }

  /// Renames `<dir>/<name>.{hive,hivec,lock}` aside instead of deleting.
  Future<void> _quarantineBoxFiles(String name, String dir) async {
    final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final sep = Platform.pathSeparator;
    for (final ext in const <String>['.hive', '.hivec', '.lock']) {
      final file = File('$dir$sep$name$ext');
      if (!file.existsSync()) continue;
      try {
        await file.rename('${file.path}.corrupt-$stamp');
      } on Object catch (error) {
        log(
          'LocalAppStore: could not quarantine ${file.path}: $error',
          name: 'LocalAppStore',
        );
      }
    }
  }

  /// Records [key] as skipped in [boxName] and logs it (once per key).
  void _noteCorrupt(String boxName, Object key) {
    final keys = _corruptKeys.putIfAbsent(boxName, () => <String>[]);
    final text = key.toString();
    if (keys.contains(text)) return;
    keys.add(text);
    log(
      'LocalAppStore: skipping corrupt entry $boxName/$text',
      name: 'LocalAppStore',
    );
  }

  // -- Migration ------------------------------------------------------

  /// Upgrades stored envelopes to [storageSchemaVersion] across every box.
  ///
  /// v1: envelope bare maps and canonicalize older variants. Envelopes whose
  /// writer version is newer than (or not parseable as) the current version
  /// are left untouched and reported in [MigrationReport.refused] — never
  /// silently reinterpreted. Returns the [MigrationReport] and logs it.
  Future<MigrationReport> migrate() async {
    if (!_boxesOpen) {
      throw StateError('LocalAppStore.init() must open boxes before migrate()');
    }
    final report = MigrationReport();
    final boxes = <String, Box>{
      StorageBoxes.agents: _agents,
      StorageBoxes.games: _games,
      StorageBoxes.events: _events,
      StorageBoxes.tournaments: _tournaments,
      StorageBoxes.evaluations: _evaluations,
      StorageBoxes.exports: _exports,
    };
    for (final entry in boxes.entries) {
      await _migrateBox(entry.key, entry.value, report);
    }
    await _meta.put(metaSchemaVersionKey, storageSchemaVersion);
    return report;
  }

  Future<void> _migrateBox(String name, Box box, MigrationReport report) async {
    report.scanned[name] = box.length;
    for (final key in box.keys.toList()) {
      final raw = box.get(key);
      if (raw is! Map) {
        report.corrupt.add('$name/$key');
        _noteCorrupt(name, key);
        continue;
      }
      final version = raw['v'];
      if (version == null) {
        // Legacy unenveloped entry: rewrite in canonical v1 form. A bare
        // `{'data': {...}}` map without `v` is still treated as an envelope
        // (matching _unwrap) so it is not double-wrapped.
        final data = raw['data'];
        final body = data is Map
            ? _coerceStringMap(data)
            : _coerceStringMap(raw);
        if (body == null) {
          report.corrupt.add('$name/$key');
          _noteCorrupt(name, key);
          continue;
        }
        await box.put(key, _wrap(body));
        report.upgraded[name] = (report.upgraded[name] ?? 0) + 1;
        continue;
      }
      if (version == storageSchemaVersion) continue;
      final parsed = version is int
          ? version
          : version is String
          ? int.tryParse(version)
          : null;
      final current = int.tryParse(storageSchemaVersion);
      if (parsed == null) {
        report.refused.add('$name/$key (v=$version)');
        continue;
      }
      if (current != null && parsed > current) {
        // Newer writer: refuse rather than silently reinterpret.
        report.refused.add('$name/$key (v=$parsed > $current)');
        continue;
      }
      // Older writer: canonicalize the data map under the current version.
      final data = raw['data'];
      Map<String, Object?>? canonical;
      if (data is Map) {
        canonical = _coerceStringMap(data);
      } else {
        canonical = _coerceStringMap(raw);
        canonical?.remove('v');
      }
      if (canonical == null) {
        report.corrupt.add('$name/$key');
        _noteCorrupt(name, key);
        continue;
      }
      await box.put(key, _wrap(canonical));
      report.upgraded[name] = (report.upgraded[name] ?? 0) + 1;
    }
  }

  // -- Envelope helpers -----------------------------------------------

  /// Wraps [data] in a versioned envelope for forward migration.
  static Map<String, Object?> _wrap(Map<String, Object?> data) =>
      <String, Object?>{'v': storageSchemaVersion, 'data': data};

  /// Unwraps a versioned envelope; returns null for corrupt entries.
  static Map<String, Object?>? _unwrap(Object? raw) {
    if (raw is Map) {
      final data = raw['data'];
      if (data is Map) return _coerceStringMap(data);
      // Unenveloped legacy entry: accept bare maps as v1.
      return _coerceStringMap(raw);
    }
    return null;
  }

  /// Best-effort `Map<String, Object?>` coercion for persisted maps.
  ///
  /// Returns null when [map] has non-String keys (a corrupt/foreign entry), so
  /// callers treat it as corrupt instead of throwing a `TypeError` mid-migration.
  static Map<String, Object?>? _coerceStringMap(Map<Object?, Object?> map) {
    final result = <String, Object?>{};
    for (final entry in map.entries) {
      final key = entry.key;
      if (key is! String) return null;
      result[key] = entry.value;
    }
    return result;
  }

  /// Coerces a redacted value to the entity-map type.
  static Map<String, Object?> _asJsonMap(Object? value) =>
      value is Map<String, Object?>
      ? value
      : Map<String, Object?>.from(value! as Map);

  /// Reads `box[key]`, noting it as corrupt when it is not a map.
  Map<String, Object?>? _readEnvelope(String boxName, Box box, Object key) {
    final raw = box.get(key);
    if (raw == null) return null;
    final value = _unwrap(raw);
    if (value == null) _noteCorrupt(boxName, key);
    return value;
  }

  /// Shared pagination for keyed maps. [startAfter] is exclusive.
  Map<String, EntityJson> _pagedMap(
    Box box,
    String boxName, {
    int? limit,
    String? startAfter,
  }) {
    final keys = box.keys.map((k) => k.toString()).toList()..sort();
    final out = <String, EntityJson>{};
    for (final key in keys) {
      if (startAfter != null && key.compareTo(startAfter) <= 0) continue;
      final value = _readEnvelope(boxName, box, key);
      if (value != null) out[key] = value;
      if (limit != null && out.length >= limit) break;
    }
    return out;
  }

  // -- AppRepository: agents ------------------------------------------

  @override
  Future<void> saveAgent(String agentId, AgentJson json) async {
    _requireReady();
    await _agents.put(agentId, _wrap(_asJsonMap(redactForStorage(json))));
  }

  @override
  Future<AgentJson?> getAgent(String agentId) async {
    _requireReady();
    return _readEnvelope(StorageBoxes.agents, _agents, agentId);
  }

  @override
  Future<Map<String, AgentJson>> listAgents() async {
    _requireReady();
    return _pagedMap(_agents, StorageBoxes.agents);
  }

  @override
  Future<Map<String, AgentJson>> listAgentsPaged({
    int limit = 100,
    String? startAfter,
  }) async {
    _requireReady();
    return _pagedMap(
      _agents,
      StorageBoxes.agents,
      limit: limit,
      startAfter: startAfter,
    );
  }

  @override
  Future<void> deleteAgent(String agentId) async {
    _requireReady();
    await _agents.delete(agentId);
  }

  // -- AppRepository: games -------------------------------------------

  @override
  Future<void> saveGame(String gameId, GameJson json) async {
    _requireReady();
    await _games.put(gameId, _wrap(_asJsonMap(redactForStorage(json))));
  }

  @override
  Future<GameJson?> getGame(String gameId) async {
    _requireReady();
    return _readEnvelope(StorageBoxes.games, _games, gameId);
  }

  @override
  Future<Map<String, GameJson>> listGames() async {
    _requireReady();
    return _pagedMap(_games, StorageBoxes.games);
  }

  @override
  Future<Map<String, GameJson>> listGamesPaged({
    int limit = 100,
    String? startAfter,
  }) async {
    _requireReady();
    return _pagedMap(
      _games,
      StorageBoxes.games,
      limit: limit,
      startAfter: startAfter,
    );
  }

  @override
  Future<void> deleteGame(String gameId) async {
    _requireReady();
    await _games.delete(gameId);
  }

  // -- AppRepository: tournaments -------------------------------------

  @override
  Future<void> saveTournament(String tournamentId, TournamentJson json) async {
    _requireReady();
    await _tournaments.put(
      tournamentId,
      _wrap(_asJsonMap(redactForStorage(json))),
    );
  }

  @override
  Future<TournamentJson?> getTournament(String tournamentId) async {
    _requireReady();
    return _readEnvelope(StorageBoxes.tournaments, _tournaments, tournamentId);
  }

  @override
  Future<Map<String, TournamentJson>> listTournaments() async {
    _requireReady();
    return _pagedMap(_tournaments, StorageBoxes.tournaments);
  }

  @override
  Future<Map<String, TournamentJson>> listTournamentsPaged({
    int limit = 100,
    String? startAfter,
  }) async {
    _requireReady();
    return _pagedMap(
      _tournaments,
      StorageBoxes.tournaments,
      limit: limit,
      startAfter: startAfter,
    );
  }

  @override
  Future<void> deleteTournament(String tournamentId) async {
    _requireReady();
    await _tournaments.delete(tournamentId);
  }

  // -- AppRepository: evaluations -------------------------------------

  /// Storage key for one evaluation.
  static String evaluationKey(String gameId, int seq) => '$gameId:$seq';

  /// `meta` key holding the per-game evaluation seq index.
  static String evaluationIndexKey(String gameId) => 'evalIndex:$gameId';

  @override
  Future<void> saveEvaluation(
    String gameId,
    int seq,
    EvaluationJson json,
  ) async {
    _requireReady();
    await _evaluations.put(
      evaluationKey(gameId, seq),
      _wrap(_asJsonMap(redactForStorage(json))),
    );
    await _indexEvaluation(gameId, seq);
  }

  /// Adds [seq] to the per-game index (no-op when already present).
  Future<void> _indexEvaluation(String gameId, int seq) async {
    final index = _readEvaluationIndex(gameId) ?? <int>[];
    if (index.contains(seq)) return;
    index.add(seq);
    index.sort();
    await _meta.put(evaluationIndexKey(gameId), index);
  }

  /// Reads the per-game index, or null when it has not been built yet.
  List<int>? _readEvaluationIndex(String gameId) {
    final raw = _meta.get(evaluationIndexKey(gameId));
    if (raw is! List) return null;
    final out = <int>[];
    for (final value in raw) {
      if (value is int) {
        out.add(value);
      } else if (value is num) {
        out.add(value.toInt());
      } else {
        final parsed = int.tryParse('$value');
        if (parsed != null) out.add(parsed);
      }
    }
    return out;
  }

  @override
  Future<List<EvaluationJson>> listEvaluations(String gameId) =>
      listEvaluationsIndexed(gameId);

  @override
  Future<List<EvaluationJson>> listEvaluationsIndexed(String gameId) async {
    _requireReady();
    final index =
        _readEvaluationIndex(gameId) ?? await _rebuildEvaluationIndex(gameId);
    final pairs = <int, EvaluationJson>{};
    for (final seq in index) {
      final value = _readEnvelope(
        StorageBoxes.evaluations,
        _evaluations,
        evaluationKey(gameId, seq),
      );
      if (value != null) pairs[seq] = value;
    }
    final seqs = pairs.keys.toList()..sort();
    return <EvaluationJson>[for (final s in seqs) pairs[s]!];
  }

  /// Rebuilds and persists the per-game index by filtering box keys.
  Future<List<int>> _rebuildEvaluationIndex(String gameId) async {
    final prefix = '$gameId:';
    final seqs = <int>[];
    for (final rawKey in _evaluations.keys) {
      final key = rawKey.toString();
      if (!key.startsWith(prefix)) continue;
      final seq = int.tryParse(key.substring(prefix.length));
      if (seq != null) seqs.add(seq);
    }
    seqs.sort();
    await _meta.put(evaluationIndexKey(gameId), seqs);
    return seqs;
  }

  // -- AppRepository: exports -----------------------------------------

  @override
  Future<void> saveExport(String exportId, ExportJson json) async {
    _requireReady();
    await _exports.put(exportId, _wrap(_asJsonMap(redactForStorage(json))));
  }

  @override
  Future<ExportJson?> getExport(String exportId) async {
    _requireReady();
    return _readEnvelope(StorageBoxes.exports, _exports, exportId);
  }

  @override
  Future<List<String>> listExports() async {
    _requireReady();
    return _exports.keys.map((k) => k.toString()).toList()..sort();
  }

  @override
  Future<List<String>> listExportsPaged({
    int limit = 100,
    String? startAfter,
  }) async {
    _requireReady();
    final keys = _exports.keys.map((k) => k.toString()).toList()..sort();
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
    _requireReady();
    await _exports.delete(exportId);
  }

  // -- AppRepository.events / EventStore -------------------------------

  @override
  EventStore get events => this;

  @override
  void append(GameEventRecord record) {
    _requireReady();
    if (_events.containsKey(record.key)) return; // idempotent by key
    final wrapped = _wrap(_asJsonMap(redactForStorage(record.toJson())));
    // Interface is sync `void`; track the future so flushWrites() can await it.
    _trackWrite(_events.put(record.key, wrapped));
  }

  /// Tracks a fire-and-forget write; failures go to [onWriteError].
  void _trackWrite(Future<void> future) {
    late final Future<void> guarded;
    guarded = future.whenComplete(() {
      _pendingWrites.remove(guarded);
    });
    unawaited(
      guarded.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) =>
            _recordWriteError(error, stack),
      ),
    );
  }

  void _recordWriteError(Object error, StackTrace stack) {
    _lastWriteError ??= error;
    _lastWriteStackTrace ??= stack;
    final hook = onWriteError;
    if (hook != null) {
      hook(error, stack);
    } else {
      log(
        'LocalAppStore write failed: $error',
        name: 'LocalAppStore',
        error: error,
        stackTrace: stack,
      );
    }
  }

  @override
  bool containsKey(String key) {
    _requireReady();
    return _events.containsKey(key);
  }

  List<GameEventRecord> _readAllRecords() {
    final out = <GameEventRecord>[];
    for (final key in _events.keys) {
      final v = _readEnvelope(StorageBoxes.events, _events, key);
      if (v == null) continue;
      try {
        out.add(GameEventRecord.fromJson(v));
      } on Object catch (error, stack) {
        // Skip corrupt entries; never fail a whole listing.
        _noteCorrupt(StorageBoxes.events, key);
        log(
          'LocalAppStore: corrupt event $key: $error',
          name: 'LocalAppStore',
          error: error,
          stackTrace: stack,
        );
      }
    }
    return out;
  }

  @override
  List<GameEventRecord> listByGame(String gameId) {
    _requireReady();
    final out = _readAllRecords().where((r) => r.gameId == gameId).toList()
      ..sort((a, b) => a.seq.compareTo(b.seq));
    return out;
  }

  @override
  List<GameEventRecord> listByTournament(String tournamentId) {
    _requireReady();
    final out =
        _readAllRecords().where((r) => r.tournamentId == tournamentId).toList()
          ..sort((a, b) {
            final c = a.gameId.compareTo(b.gameId);
            return c != 0 ? c : a.seq.compareTo(b.seq);
          });
    return out;
  }

  @override
  List<GameEventRecord> listAll() {
    _requireReady();
    final out = _readAllRecords()..sort((a, b) => a.key.compareTo(b.key));
    return out;
  }

  /// Paginated [listAll]: at most [limit] records whose key sorts strictly
  /// after [startAfter] (exclusive cursor = last key of the previous page).
  List<GameEventRecord> listAllPaged({int limit = 100, String? startAfter}) {
    _requireReady();
    final sorted = _readAllRecords()..sort((a, b) => a.key.compareTo(b.key));
    final out = <GameEventRecord>[];
    for (final record in sorted) {
      if (startAfter != null && record.key.compareTo(startAfter) <= 0) {
        continue;
      }
      out.add(record);
      if (out.length >= limit) break;
    }
    return out;
  }

  // -- meta (retention cursors + generic access) -----------------------

  /// Reads a raw `meta` value (used for cursors/indexes and diagnostics).
  Future<Object?> getMeta(String key) async {
    _requireReady();
    return _meta.get(key);
  }

  /// Writes a raw `meta` value.
  Future<void> putMeta(String key, Object? value) async {
    _requireReady();
    await _meta.put(key, value);
  }

  /// Reads a retention cursor stored under [key], or null when unset.
  Future<DateTime?> readRetentionCursor(String key) async {
    _requireReady();
    final raw = _meta.get(key);
    return raw is String ? DateTime.tryParse(raw)?.toUtc() : null;
  }

  /// Persists a retention cursor under [key] (UTC ISO-8601).
  Future<void> writeRetentionCursor(String key, DateTime value) async {
    _requireReady();
    await _meta.put(key, value.toUtc().toIso8601String());
  }

  // -- Retention policy hooks ------------------------------------------

  /// Deletes events older than [olderThan] and/or beyond [keepLastN] per
  /// game. Returns the number removed. Opt-in; never called automatically.
  ///
  /// Performs a full scan of the `events` box; advances
  /// [metaRetentionEventsCursorKey] to the age cutoff when supplied.
  Future<int> pruneEvents({Duration? olderThan, int? keepLastN}) async {
    _requireReady();
    if (olderThan == null && keepLastN == null) return 0;
    // A negative retention count is nonsensical and would underflow the
    // `list.length - keepLastN` bound below into a RangeError.
    if (keepLastN != null && keepLastN < 0) {
      throw ArgumentError.value(
        keepLastN,
        'keepLastN',
        'must be >= 0',
      );
    }
    final cutoff = olderThan == null
        ? null
        : DateTime.now().toUtc().subtract(olderThan);
    final all = _readAllRecords();
    final doomed = <String>{};
    if (cutoff != null) {
      for (final r in all) {
        if (r.createdAt.isBefore(cutoff)) doomed.add(r.key);
      }
    }
    if (keepLastN != null) {
      final byGame = <String, List<GameEventRecord>>{};
      for (final r in all) {
        byGame.putIfAbsent(r.gameId, () => <GameEventRecord>[]).add(r);
      }
      for (final list in byGame.values) {
        list.sort((a, b) => a.seq.compareTo(b.seq));
        if (list.length > keepLastN) {
          for (var i = 0; i < list.length - keepLastN; i++) {
            doomed.add(list[i].key);
          }
        }
      }
    }
    for (final k in doomed) {
      await _events.delete(k);
    }
    if (cutoff != null) {
      await writeRetentionCursor(metaRetentionEventsCursorKey, cutoff);
    }
    return doomed.length;
  }

  /// Deletes game summaries older than [olderThan] (by `finishedAt` /
  /// `startedAt` payload fields when present). Returns count removed.
  /// Opt-in; never called automatically.
  ///
  /// Performs a full scan of the `games` box; advances
  /// [metaRetentionGamesCursorKey] to the age cutoff.
  Future<int> pruneGames({required Duration olderThan}) async {
    _requireReady();
    final cutoff = DateTime.now().toUtc().subtract(olderThan);
    var removed = 0;
    for (final key in List<Object?>.of(_games.keys)) {
      final v = _readEnvelope(StorageBoxes.games, _games, key!);
      DateTime? stamp;
      final raw = v?['finishedAt'] ?? v?['startedAt'];
      if (raw is String) stamp = DateTime.tryParse(raw)?.toUtc();
      if (stamp != null && stamp.isBefore(cutoff)) {
        await _games.delete(key);
        removed++;
      }
    }
    await writeRetentionCursor(metaRetentionGamesCursorKey, cutoff);
    return removed;
  }
}
