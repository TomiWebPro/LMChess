// Leveled application log: severity filtering, bounded buffer, sinks,
// tag/level queries, record formatting, and the provider-scope seam.
//
// Pure Dart (no I/O, no widgets); the default sink forwards to
// `dart:developer`, which tests ignore by asserting on the buffer.
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/diagnostics/app_log.dart';

void main() {
  group('AppLogLevel', () {
    test('is ordered quiet to loud', () {
      final levels = AppLogLevel.values;
      expect(levels, orderedEquals(<AppLogLevel>[
        AppLogLevel.verbose,
        AppLogLevel.debug,
        AppLogLevel.info,
        AppLogLevel.warning,
        AppLogLevel.error,
      ]));
      for (var i = 0; i + 1 < levels.length; i++) {
        expect(
          levels[i].index < levels[i + 1].index,
          isTrue,
          reason: '${levels[i]} before ${levels[i + 1]}',
        );
      }
    });
  });

  group('AppLogRecord', () {
    test('toString carries time, level, tag, and message', () {
      final record = AppLogRecord(
        level: AppLogLevel.warning,
        tag: 'engine-adapter',
        message: 'falling back',
        timestamp: DateTime(2026, 11, 5, 23, 14, 7, 42),
      );
      expect(
        record.toString(),
        '[23:14:07.042] WARNING engine-adapter: falling back',
      );
    });

    test('toString appends error and stack lines when present', () {
      final record = AppLogRecord.now(
        level: AppLogLevel.error,
        tag: 't',
        message: 'boom',
        error: StateError('bad'),
        stackTrace: StackTrace.empty,
      );
      final text = record.toString();
      expect(text, contains('ERROR t: boom'));
      expect(text, contains('error: Bad state: bad'));
      expect(text, contains('stack: '));
    });
  });

  group('AppLog', () {
    test('drops records below minLevel before buffering or sinking', () {
      final seen = <AppLogRecord>[];
      final log = AppLog(minLevel: AppLogLevel.warning)
        ..addSink(seen.add);
      log.info('quiet milestone', tag: 't');
      log.debug(' quiet debug', tag: 't');
      expect(log.records, isEmpty, reason: 'nothing buffered');
      expect(seen, isEmpty, reason: 'nothing sunk');
      log.warning('loud fallback', tag: 't');
      expect(log.records, hasLength(1));
      expect(seen, hasLength(1));
    });

    test('evicts oldest records past maxRecords', () {
      final log = AppLog(maxRecords: 3, minLevel: AppLogLevel.verbose);
      for (var i = 0; i < 5; i++) {
        log.info('m$i', tag: 't');
      }
      expect(
        log.records.map((r) => r.message),
        orderedEquals(<String>['m2', 'm3', 'm4']),
      );
    });

    test('recent filters by floor level, tag, and newest limit', () {
      final log = AppLog(minLevel: AppLogLevel.verbose);
      log.info('a-info', tag: 'a');
      log.warning('a-warn', tag: 'a');
      log.error('b-error', tag: 'b');
      expect(
        log.recent(minLevel: AppLogLevel.warning).map((r) => r.message),
        orderedEquals(<String>['a-warn', 'b-error']),
      );
      expect(
        log.recent(tag: 'a').map((r) => r.message),
        orderedEquals(<String>['a-info', 'a-warn']),
      );
      expect(
        log.recent(limit: 2).map((r) => r.message),
        orderedEquals(<String>['a-warn', 'b-error']),
      );
    });

    test('a throwing sink never breaks logging', () {
      final log = AppLog(minLevel: AppLogLevel.verbose)
        ..addSink((_) => throw StateError('sink bug'));
      log.error('still recorded', tag: 't');
      expect(log.records, hasLength(1));
    });

    test('clear empties the buffer but keeps sinks', () {
      final seen = <AppLogRecord>[];
      final log = AppLog()..addSink(seen.add);
      log.info('one', tag: 't');
      log.clear();
      expect(log.records, isEmpty);
      log.info('two', tag: 't');
      expect(seen.map((r) => r.message), orderedEquals(<String>['one', 'two']));
    });

    test('level helpers route to the right severity', () {
      final log = AppLog(minLevel: AppLogLevel.verbose);
      log.verbose('v', tag: 't');
      log.debug('d', tag: 't');
      log.info('i', tag: 't');
      log.warning('w', tag: 't');
      log.error('e', tag: 't');
      expect(
        log.records.map((r) => r.level),
        orderedEquals(AppLogLevel.values),
      );
    });
  });
}
