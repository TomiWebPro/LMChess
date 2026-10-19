// Regression tests for [LocalAppStore] (Hive-backed persistence).
//
// Hive is initialized against a fresh temp directory per test, so the tests
// exercise the real on-disk backend (envelopes, migration, redaction,
// pagination, retention cursors) without touching the user's data.
//
// If Hive initialization ever proves flaky in a given environment, the
// Hive-specific groups below can be skipped; the `InMemoryEventStore`
// contract tests remain meaningful on their own.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:llm_chess_arena/src/arena/export.dart' show redactedPlaceholder;
import 'package:llm_chess_arena/src/stats/event_log.dart';
import 'package:llm_chess_arena/src/storage/local_store.dart';
import 'package:llm_chess_arena/src/storage/repository.dart';
import 'package:llm_chess_arena/src/storage/storage_reports.dart';

void main() {
  late Directory dir;
  late LocalAppStore store;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('llm_chess_store_test_');
    store = LocalAppStore();
    await store.init(dbPath: dir.path);
  });

  tearDown(() async {
    await store.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('agents', () {
    test('saveAgent round-trips through a versioned envelope', () async {
      await store.saveAgent('a1', <String, Object?>{
        'name': 'Agent One',
        'apiKeyRef': 'vault:openai',
        'apiKey': 'sk-secret-value',
      });

      final loaded = await store.getAgent('a1');
      expect(loaded, isNotNull);
      expect(loaded!['name'], 'Agent One');
      // `*Ref` survives verbatim...
      expect(loaded['apiKeyRef'], 'vault:openai');
      // ...but the secret itself is redacted on write.
      expect(loaded['apiKey'], redactedPlaceholder);
      expect(loaded['apiKey'], isNot('sk-secret-value'));

      // The raw stored value is a `{v, data}` envelope with the schema version.
      final raw = Hive.box(StorageBoxes.agents).get('a1');
      expect(raw, isA<Map>());
      final rawMap = raw! as Map;
      expect(rawMap['v'], storageSchemaVersion);
      expect((rawMap['data'] as Map)['name'], 'Agent One');
      expect((rawMap['data'] as Map)['apiKey'], redactedPlaceholder);
    });

    test('legacy bare maps still load and are upgraded by migrate()',
        () async {
      final box = Hive.box(StorageBoxes.agents);
      // Simulate data written before envelopes existed.
      await box.put('legacy', <String, Object?>{
        'name': 'Legacy',
        'apiKeyRef': 'ref-9',
      });

      final loaded = await store.getAgent('legacy');
      expect(loaded!['name'], 'Legacy');
      expect(loaded['apiKeyRef'], 'ref-9');

      final report = await store.migrate();
      expect(report.upgraded['agents'], greaterThanOrEqualTo(1));
      final upgraded = box.get('legacy')! as Map;
      expect(upgraded['v'], storageSchemaVersion);
      expect((upgraded['data'] as Map)['name'], 'Legacy');
    });

    test('listAgentsPaged returns the expected pages with an exclusive cursor',
        () async {
      for (final id in <String>['a', 'b', 'c', 'd', 'e']) {
        await store.saveAgent(id, <String, Object?>{'name': id});
      }

      final page1 = await store.listAgentsPaged(limit: 2);
      expect(page1.keys.toList(), <String>['a', 'b']);

      final page2 = await store.listAgentsPaged(limit: 2, startAfter: 'b');
      expect(page2.keys.toList(), <String>['c', 'd']);

      final page3 = await store.listAgentsPaged(limit: 2, startAfter: 'd');
      expect(page3.keys.toList(), <String>['e']);
    });
  });

  group('events', () {
    test('append is fire-and-forget; flushWrites() settles it', () async {
      store.append(GameEventRecord(
        key: 'e1',
        gameId: 'g1',
        seq: 0,
        type: 'turn.completed',
        payloadJson: const <String, Object?>{'agentId': 'a'},
        createdAt: DateTime.utc(2026, 1, 1),
      ));
      await store.flushWrites();

      expect(store.pendingWriteCount, 0);
      expect(store.containsKey('e1'), isTrue);
      expect(store.listByGame('g1'), hasLength(1));

      // Idempotent by key: a second append with the same key is a no-op.
      store.append(GameEventRecord(
        key: 'e1',
        gameId: 'g1',
        seq: 0,
        type: 'duplicate',
        createdAt: DateTime.utc(2026, 1, 1),
      ));
      await store.flushWrites();
      expect(store.listByGame('g1'), hasLength(1));
    });

    test('listAllPaged honors the exclusive key cursor', () async {
      for (final key in <String>['k1', 'k2', 'k3', 'k4']) {
        store.append(GameEventRecord(
          key: key,
          gameId: 'g',
          seq: int.parse(key.substring(1)),
          type: 't',
          createdAt: DateTime.utc(2026, 1, 1),
        ));
      }
      await store.flushWrites();

      final first = store.listAllPaged(limit: 2).map((r) => r.key).toList();
      expect(first, <String>['k1', 'k2']);
      final second =
          store.listAllPaged(limit: 2, startAfter: 'k2').map((r) => r.key).toList();
      expect(second, <String>['k3', 'k4']);
    });
  });

  group('exports pagination', () {
    test('listExportsPaged pages ascending with startAfter', () async {
      for (final id in <String>['x1', 'x2', 'x3']) {
        await store.saveExport(id, <String, Object?>{'name': id});
      }
      expect(await store.listExportsPaged(limit: 2), <String>['x1', 'x2']);
      expect(await store.listExportsPaged(limit: 2, startAfter: 'x2'),
          <String>['x3']);
    });
  });

  group('reports', () {
    test('integrityReport() and MigrationReport are produced', () async {
      final integrity = store.integrityReport();
      expect(integrity, isA<IntegrityReport>());
      expect(integrity.isClean, isTrue);
      expect(integrity.quarantinedBoxes, isEmpty);

      final last = store.lastMigrationReport;
      expect(last, isA<MigrationReport>());
      expect(last!.scanned, contains(StorageBoxes.agents));
      expect(last.isClean, isTrue);

      final fresh = await store.migrate();
      expect(fresh, isA<MigrationReport>());
      expect(fresh.scanned[StorageBoxes.events], isA<int>());
    });
  });

  group('retention', () {
    test('pruneEvents removes old events and advances the cursor', () async {
      final old = DateTime.now().toUtc().subtract(const Duration(days: 10));
      final recent = DateTime.now().toUtc();
      for (final key in <String>['old1', 'old2']) {
        store.append(GameEventRecord(
          key: key,
          gameId: 'g',
          seq: key == 'old1' ? 0 : 1,
          type: 't',
          createdAt: old,
        ));
      }
      store.append(GameEventRecord(
        key: 'new1',
        gameId: 'g',
        seq: 2,
        type: 't',
        createdAt: recent,
      ));
      await store.flushWrites();

      final removed =
          await store.pruneEvents(olderThan: const Duration(days: 7));
      expect(removed, 2);
      expect(store.containsKey('old1'), isFalse);
      expect(store.containsKey('new1'), isTrue);

      final cursor1 =
          await store.readRetentionCursor(metaRetentionEventsCursorKey);
      expect(cursor1, isNotNull);

      // A tighter window advances the watermark further.
      await store.pruneEvents(olderThan: const Duration(days: 1));
      final cursor2 =
          await store.readRetentionCursor(metaRetentionEventsCursorKey);
      expect(cursor2, isNotNull);
      expect(cursor2!.isAfter(cursor1!), isTrue);
    });

    test('pruneEvents keepLastN retains the newest records per game',
        () async {
      final now = DateTime.now().toUtc();
      for (var i = 0; i < 3; i++) {
        store.append(GameEventRecord(
          key: 'keep$i',
          gameId: 'k',
          seq: i,
          type: 't',
          createdAt: now,
        ));
      }
      await store.flushWrites();

      final removed = await store.pruneEvents(keepLastN: 1);
      expect(removed, 2);
      expect(store.listByGame('k'), hasLength(1));
      expect(store.listByGame('k').single.key, 'keep2');
    });

    test('pruneGames removes old summaries and advances its cursor',
        () async {
      final old = DateTime.now().toUtc().subtract(const Duration(days: 10));
      final recent = DateTime.now().toUtc();
      await store.saveGame('g-old', <String, Object?>{
        'startedAt': old.toIso8601String(),
      });
      await store.saveGame('g-new', <String, Object?>{
        'startedAt': recent.toIso8601String(),
      });

      final removed =
          await store.pruneGames(olderThan: const Duration(days: 7));
      expect(removed, 1);
      expect(await store.getGame('g-old'), isNull);
      expect(await store.getGame('g-new'), isNotNull);

      final cursor =
          await store.readRetentionCursor(metaRetentionGamesCursorKey);
      expect(cursor, isNotNull);
    });
  });
}
