/// Immutable, idempotency-keyed game event records and [EventStore] contract.
///
/// # Event model
///
/// Every observable thing that happens during a game (turn started, move
/// parsed, tool call failed, game ended, ...) is appended as a
/// [GameEventRecord]. Consumers ([AgentMetrics], tournament exports, UI)
/// derive all statistics from these records, so the record schema is the
/// single source of truth for observability.
///
/// # Idempotency
///
/// [GameEventRecord.key] is a client-generated idempotency key
/// (typically a UUID). [EventStore.append] must ignore a record whose key
/// has already been stored, so retries of the orchestrator never
/// double-count turns.
///
/// # Ordering
///
/// [seq] is a per-game monotonic sequence number assigned by the producer.
/// Stores return records sorted ascending by [seq]. Gaps are tolerated
/// (a crashed-then-retried turn may leave a hole); consumers must not
/// assume contiguity.
///
/// # Payload contract
///
/// [payloadJson] is an untyped JSON map so producers (orchestrator,
/// providers) do not need to depend on stats. Well-known keys consumed by
/// `metrics.dart` are documented there; unknown keys are preserved and
/// ignored.
library;

/// A single observable event within a game.
///
/// Immutable. Use [copyWith] to derive variants (e.g. assigning [seq]).
class GameEventRecord {
  /// Client-generated idempotency key (UUID recommended).
  ///
  /// Two records with the same [key] are the same logical event; the
  /// second append is a no-op.
  final String key;

  /// Game this event belongs to.
  final String gameId;

  /// Tournament this game belongs to, if any.
  final String? tournamentId;

  /// Per-game monotonic sequence number (0-based). Assigned by producer.
  final int seq;

  /// Event type, e.g. `'turn.completed'`, `'move.illegal'`,
  /// `'provider.error'`. See `metrics.dart` for the well-known set.
  final String type;

  /// Untyped JSON payload. Must be JSON-encodable (no DateTime, no
  /// binary). API keys must never be placed here; export redacts
  /// suspicious keys defensively, but producers must not rely on that.
  final Map<String, Object?> payloadJson;

  /// Wall-clock time the event was created (UTC).
  final DateTime createdAt;

  /// Creates a record. [createdAt] defaults to `DateTime.now().toUtc()`.
  GameEventRecord({
    required this.key,
    required this.gameId,
    this.tournamentId,
    required this.seq,
    required this.type,
    Map<String, Object?>? payloadJson,
    DateTime? createdAt,
  })  : payloadJson = Map<String, Object?>.unmodifiable(payloadJson ?? const {}),
        createdAt = createdAt ?? DateTime.now().toUtc();

  /// Returns a copy with the given fields replaced.
  GameEventRecord copyWith({
    String? key,
    String? gameId,
    String? tournamentId,
    int? seq,
    String? type,
    Map<String, Object?>? payloadJson,
    DateTime? createdAt,
  }) {
    return GameEventRecord(
      key: key ?? this.key,
      gameId: gameId ?? this.gameId,
      tournamentId: tournamentId ?? this.tournamentId,
      seq: seq ?? this.seq,
      type: type ?? this.type,
      payloadJson: payloadJson ?? this.payloadJson,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Serializes to a JSON-compatible map with stable field ordering.
  Map<String, Object?> toJson() => <String, Object?>{
        'key': key,
        'gameId': gameId,
        'tournamentId': tournamentId,
        'seq': seq,
        'type': type,
        'payloadJson': payloadJson,
        'createdAt': createdAt.toIso8601String(),
      };

  /// Parses a record produced by [toJson]. Throws [FormatException] on
  /// missing/invalid required fields.
  factory GameEventRecord.fromJson(Map<String, Object?> json) {
    final key = json['key'];
    final gameId = json['gameId'];
    final seq = json['seq'];
    final type = json['type'];
    final createdAt = json['createdAt'];
    if (key is! String || key.isEmpty) {
      throw const FormatException('GameEventRecord.key must be a non-empty String');
    }
    if (gameId is! String || gameId.isEmpty) {
      throw const FormatException('GameEventRecord.gameId must be a non-empty String');
    }
    if (seq is! int) {
      throw const FormatException('GameEventRecord.seq must be an int');
    }
    if (type is! String || type.isEmpty) {
      throw const FormatException('GameEventRecord.type must be a non-empty String');
    }
    DateTime parsedAt;
    if (createdAt is String) {
      parsedAt = DateTime.parse(createdAt);
    } else {
      throw const FormatException('GameEventRecord.createdAt must be an ISO-8601 String');
    }
    final tournamentId = json['tournamentId'];
    final payload = json['payloadJson'];
    return GameEventRecord(
      key: key,
      gameId: gameId,
      tournamentId: tournamentId is String ? tournamentId : null,
      seq: seq,
      type: type,
      payloadJson: payload is Map
          ? Map<String, Object?>.from(payload)
          : const <String, Object?>{},
      createdAt: parsedAt.toUtc(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GameEventRecord && other.key == key);

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() =>
      'GameEventRecord(key=$key, game=$gameId, seq=$seq, type=$type)';
}

/// Append/read contract for [GameEventRecord]s.
///
/// Implementations must guarantee:
///
/// * **Idempotent append**: appending a record whose [GameEventRecord.key]
///   already exists is a no-op (first write wins).
/// * **Sorted reads**: [listByGame] and [listByTournament] return records
///   sorted ascending by ([gameId], [seq]).
abstract class EventStore {
  /// Appends [record]. If a record with the same key exists, does nothing.
  void append(GameEventRecord record);

  /// Returns `true` if a record with [key] is already stored.
  bool containsKey(String key);

  /// All records for [gameId], sorted ascending by [seq].
  List<GameEventRecord> listByGame(String gameId);

  /// All records for [tournamentId], sorted by ([gameId], [seq]).
  List<GameEventRecord> listByTournament(String tournamentId);

  /// All stored records (insertion order is unspecified; sorts by key).
  List<GameEventRecord> listAll();
}

/// In-memory [EventStore] for tests, previews, and non-persisted runs.
///
/// Not durable: everything is lost on process exit. For persistence use
/// `LocalAppStore` (which also implements [EventStore]).
///
/// Bounded retention: at most [maxEvents] records are kept; when an append
/// would exceed the cap, the oldest records (by insertion order) are
/// evicted first. The default (10000) bounds memory for long tournaments
/// while keeping enough history for metrics and recent-game views.
class InMemoryEventStore implements EventStore {
  /// Maximum retained records (oldest-first eviction past the cap).
  final int maxEvents;

  /// Creates a store with an optional retention cap.
  InMemoryEventStore({this.maxEvents = 10000});

  final Map<String, GameEventRecord> _byKey = <String, GameEventRecord>{};

  @override
  void append(GameEventRecord record) {
    // Idempotent by key: first write wins.
    if (_byKey.containsKey(record.key)) return;
    _byKey[record.key] = record;
    while (_byKey.length > maxEvents) {
      _byKey.remove(_byKey.keys.first);
    }
  }

  @override
  bool containsKey(String key) => _byKey.containsKey(key);

  @override
  List<GameEventRecord> listByGame(String gameId) {
    final out = _byKey.values.where((r) => r.gameId == gameId).toList()
      ..sort((a, b) => a.seq.compareTo(b.seq));
    return List<GameEventRecord>.unmodifiable(out);
  }

  @override
  List<GameEventRecord> listByTournament(String tournamentId) {
    final out = _byKey.values
        .where((r) => r.tournamentId == tournamentId)
        .toList()
      ..sort((a, b) {
        final c = a.gameId.compareTo(b.gameId);
        if (c != 0) return c;
        return a.seq.compareTo(b.seq);
      });
    return List<GameEventRecord>.unmodifiable(out);
  }

  @override
  List<GameEventRecord> listAll() {
    final out = _byKey.values.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return List<GameEventRecord>.unmodifiable(out);
  }

  /// Removes all records. Primarily for tests.
  void clear() => _byKey.clear();

  /// Number of stored records.
  int get length => _byKey.length;
}
