/// Versioned JSON export of tournament results.
///
/// # Schema
///
/// Every export is a JSON-compatible map with insertion-ordered fields:
///
/// ```
/// {
///   'schemaVersion': '1.0',
///   'exportedAt': '<UTC ISO-8601>',
///   'tournament': { ...TournamentState.toJson() },
///   'events': [ ...GameEventRecord.toJson() ],
///   'agentConfigs': { '<agentId>': {...} },
///   'versions': { 'app': '...', 'rules': '...' },
/// }
/// ```
///
/// Consumers must check [tournamentExportSchemaVersion] first and refuse
/// (with a clear error) anything else — never silently interpret a newer
/// schema with old code.
///
/// # Redaction
///
/// Agent configs may contain secrets. [redactSecrets] deep-clones maps and
/// replaces values whose key looks like a secret (`apiKey`, `api_key`,
/// `token`, `secret`, `password`, `authorization`, case-insensitive,
/// substring match) with `'***REDACTED***'`. Export always redacts; the
/// function is public so storage layers can reuse it.
library;

import '../stats/event_log.dart';
import 'tournament.dart';

/// Current export schema version. Bump on any breaking field change and
/// add a migration path in [parseTournamentExport].
const String tournamentExportSchemaVersion = '1.0';

/// Placeholder replacing secret values during export.
const String redactedPlaceholder = '***REDACTED***';

/// Builds a versioned, redacted tournament export map.
///
/// Field insertion order is fixed (see library docs) so repeated exports
/// of identical state serialize byte-identically under `jsonEncode`.
/// [agentConfigs] values must be JSON-compatible maps; they are redacted.
/// [versions] carries component versions, e.g.
/// `{'app': '0.1.0', 'rules': 'chaotic-v3'}`.
Map<String, Object?> buildTournamentExport({
  required TournamentState state,
  required List<GameEventRecord> events,
  required Map<String, Map<String, Object?>> agentConfigs,
  required Map<String, String> versions,
  DateTime? exportedAt,
}) {
  final redactedConfigs = <String, Object?>{};
  final sortedIds = agentConfigs.keys.toList()..sort();
  for (final id in sortedIds) {
    redactedConfigs[id] = redactSecrets(agentConfigs[id]!);
  }
  final sortedEvents = List<GameEventRecord>.of(events)
    ..sort((a, b) {
      final c = a.gameId.compareTo(b.gameId);
      if (c != 0) return c;
      return a.seq.compareTo(b.seq);
    });
  return <String, Object?>{
    'schemaVersion': tournamentExportSchemaVersion,
    'exportedAt':
        (exportedAt ?? DateTime.now().toUtc()).toUtc().toIso8601String(),
    'tournament': state.toJson(),
    'events': sortedEvents.map((e) => e.toJson()).toList(),
    'agentConfigs': redactedConfigs,
    'versions': Map<String, String>.of(versions),
  };
}

/// Deep-clones [value], replacing secret-looking map values with
/// [redactedPlaceholder]. Lists are traversed; all other values are
/// returned as-is.
Object? redactSecrets(Object? value) {
  if (value is Map) {
    final out = <String, Object?>{};
    for (final entry in value.entries) {
      final k = entry.key.toString();
      if (_looksLikeSecret(k)) {
        out[k] = redactedPlaceholder;
      } else {
        out[k] = redactSecrets(entry.value);
      }
    }
    return out;
  }
  if (value is List) {
    return value.map(redactSecrets).toList();
  }
  return value;
}

/// Substring, case-insensitive match against known secret key fragments.
bool _looksLikeSecret(String key) {
  final k = key.toLowerCase().replaceAll(RegExp(r'[-_\s]'), '');
  const fragments = <String>[
    'apikey',
    'apisecret',
    'accesstoken',
    'refreshtoken',
    'authtoken',
    'token',
    'secret',
    'password',
    'passwd',
    'authorization',
    'bearer',
    'privatekey',
  ];
  for (final f in fragments) {
    if (k.contains(f)) return true;
  }
  return false;
}

/// Validates a [buildTournamentExport] map and returns it cast to the
/// expected shape.
///
/// Throws [FormatException] when `schemaVersion` is missing/unsupported
/// or required top-level fields (`tournament`, `events`, `exportedAt`)
/// are absent or mistyped. Unknown extra fields are tolerated (forward
/// compatibility); unknown schema versions are not.
Map<String, Object?> parseTournamentExport(Map<String, Object?> json) {
  final version = json['schemaVersion'];
  if (version != tournamentExportSchemaVersion) {
    throw FormatException(
      'Unsupported tournament export schemaVersion: $version '
      '(expected $tournamentExportSchemaVersion)',
    );
  }
  if (json['exportedAt'] is! String) {
    throw const FormatException(
        'Tournament export is missing exportedAt (ISO-8601 String)');
  }
  final tournament = json['tournament'];
  if (tournament is! Map) {
    throw const FormatException(
        'Tournament export is missing tournament (Map)');
  }
  if (json['events'] is! List) {
    throw const FormatException(
        'Tournament export is missing events (List)');
  }
  // Validate nested shapes eagerly so corrupt files fail fast here
  // instead of deep in UI code. Every cast is guarded so malformed input
  // surfaces as FormatException, never a TypeError.
  final rawConfig = tournament['config'];
  if (rawConfig is! Map) {
    throw const FormatException(
        'Tournament export tournament.config must be a Map');
  }
  TournamentConfig.fromJson(Map<String, Object?>.from(rawConfig));
  final rawGames = tournament['games'];
  if (rawGames is! List) {
    throw const FormatException(
        'Tournament export tournament.games must be a List');
  }
  for (final g in rawGames) {
    if (g is! Map) {
      throw const FormatException(
          'Tournament export game entry must be a Map');
    }
    TournamentGameRef.fromJson(Map<String, Object?>.from(g));
  }
  for (final e in (json['events'] as List)) {
    if (e is! Map) {
      throw const FormatException(
          'Tournament export event entry must be a Map');
    }
    GameEventRecord.fromJson(Map<String, Object?>.from(e));
  }
  return Map<String, Object?>.of(json);
}
