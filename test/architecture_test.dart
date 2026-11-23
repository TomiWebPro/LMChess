// Layering gate for the backend/frontend split.
//
// UI (`lib/src/ui/`) must not import the durable store or Hive directly —
// it programs against `AppRepository`/`EventStore` via
// `storage/repository_provider.dart` (or the telemetry facades in
// `ui/backend_bridge.dart`). Domain layers (`chess`, `variant`, `game`,
// `arena`, `llm`, `review`, `stats`) must not import `ui`.
//
// Current status: screens still import domain modules directly
// (arena_screen.dart, game_screen.dart); that migration goes through the
// new `ui/backend_facade.dart` next. This test locks the parts already
// clean so they cannot regress:
// * no `local_store` / `hive` in UI
// * no `ui` imports in domain
// * MemoryAppRepository honors the AppRepository contract (CRUD + paging +
//   idempotent events)
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/stats/event_log.dart';
import 'package:llm_chess_arena/src/storage/memory_store.dart';

void main() {
  group('layering', () {
    test('ui never imports durable store or hive directly', () {
      final uiDir = Directory('lib/src/ui');
      final violations = <String>[];
      final importLine = RegExp(r'''^\s*import\s+['"]''', multiLine: true);
      for (final f in uiDir.listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final text = File(f.path).readAsStringSync();
        final imports = text
            .split('\n')
            .where((l) => importLine.hasMatch(l))
            .join('\n');
        if (imports.contains('storage/local_store') ||
            imports.contains('hive_ce_flutter') ||
            imports.contains('package:hive')) {
          violations.add(f.path);
        }
      }
      expect(
        violations,
        isEmpty,
        reason:
            'UI must use AppRepository via repository_provider, got: '
            '$violations',
      );
    });

    test('domain never imports ui', () {
      const domains = <String>[
        'lib/src/chess',
        'lib/src/variant',
        'lib/src/game',
        'lib/src/arena',
        'lib/src/llm',
        'lib/src/stats',
        'lib/src/review',
        'lib/src/storage',
        'lib/src/stockfish',
        'lib/src/diagnostics',
      ];
      final violations = <String>[];
      final importLine = RegExp(r'''^\s*import\s+['"]''', multiLine: true);
      for (final d in domains) {
        final dir = Directory(d);
        if (!dir.existsSync()) continue;
        for (final f in dir.listSync(recursive: true)) {
          if (f is! File || !f.path.endsWith('.dart')) continue;
          final text = File(f.path).readAsStringSync();
          // Real imports only (not doc comments): lines starting with import.
          final imports = text
              .split('\n')
              .where((l) => importLine.hasMatch(l))
              .join('\n');
          // Relative `../ui/` or package `src/ui/` imports.
          if (imports.contains('../ui/') || imports.contains('/src/ui/')) {
            violations.add(f.path);
          }
        }
      }
      expect(violations, isEmpty, reason: 'domain->ui leak: $violations');
    });

    test('backend stays Flutter-free', () {
      // Backend = pure Dart: game, ui/backend use-cases, diagnostics log
      // contract. Flutter adapters live in ui/providers + ui/screens|widgets
      // + diagnostics/app_log (AppLog implements the pure BackendLog).
      const backendDirs = <String>[
        'lib/src/game',
        'lib/src/ui/backend',
      ];
      const backendFiles = <String>[
        'lib/src/diagnostics/backend_log.dart',
      ];
      final violations = <String>[];
      final importLine = RegExp(r'''^\s*import\s+['"]''', multiLine: true);
      for (final d in backendDirs) {
        final dir = Directory(d);
        if (!dir.existsSync()) continue;
        for (final f in dir.listSync(recursive: true)) {
          if (f is! File || !f.path.endsWith('.dart')) continue;
          final text = File(f.path).readAsStringSync();
          final imports = text
              .split('\n')
              .where((l) => importLine.hasMatch(l))
              .join('\n');
          if (imports.contains('package:flutter')) {
            violations.add(f.path);
          }
        }
      }
      for (final p in backendFiles) {
        final f = File(p);
        if (!f.existsSync()) continue;
        final text = f.readAsStringSync();
        final imports = text
            .split('\n')
            .where((l) => importLine.hasMatch(l))
            .join('\n');
        if (imports.contains('package:flutter')) {
          violations.add(p);
        }
      }
      expect(
        violations,
        isEmpty,
        reason: 'backend must not import Flutter: $violations',
      );
    });

    test('backend_bridge stays importable as facade barrel', () {
      // Guards the next step (splitting backend_bridge.dart into
      // ui/backend/*.dart): the barrel must keep existing while screens
      // migrate, so this file must exist until the migration lands.
      expect(File('lib/src/ui/backend_bridge.dart').existsSync(), isTrue);
    });
  });

  group('MemoryAppRepository contract', () {
    test('crud + paging + idempotent events', () async {
      final repo = MemoryAppRepository();

      await repo.saveAgent('a1', <String, Object?>{'id': 'a1'});
      await repo.saveAgent('a2', <String, Object?>{'id': 'a2'});
      expect((await repo.getAgent('a1'))!['id'], 'a1');
      expect((await repo.listAgents()).length, 2);
      final page = await repo.listAgentsPaged(limit: 1);
      expect(page.length, 1);
      final page2 = await repo.listAgentsPaged(
        limit: 1,
        startAfter: page.keys.single,
      );
      expect(page2.length, 1);
      expect(page2.keys.single, isNot(page.keys.single));

      await repo.saveEvaluation('g1', 1, <String, Object?>{'seq': 1});
      await repo.saveEvaluation('g1', 0, <String, Object?>{'seq': 0});
      final evals = await repo.listEvaluations('g1');
      expect(evals.length, 2);

      final store = repo.events;
      final r1 = GameEventRecord(
        key: 'k1',
        gameId: 'g1',
        seq: 0,
        type: 'move.accepted',
      );
      store.append(r1);
      store.append(r1); // idempotent
      expect(store.listByGame('g1').length, 1);
    });
  });
}
