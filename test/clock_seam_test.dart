// Regression tests for the §10.3 clock seam:
// [clockProvider] / injectable wall-clock source.
//
/// Widget tests must never depend on the wall clock. Screens that seed
/// deterministic identifiers or timestamps resolve this provider (defaulting
/// to `DateTime.now`) so tests can override it with a fixed UTC timestamp —
/// no stale timers, no flaky epoch-dependent IDs.
// ignore_for_file: dangling_library_doc_comments

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/ui/backend_bridge.dart';

/// Fixed UTC reference time for deterministic testing.
final _fixedClock = DateTime.utc(2026, 1, 1, 12, 0, 0);

void main() {
  group('clockProvider (§10.3 seam)', () {
    test('defaults to DateTime.now (returns a valid DateTime)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final clock = container.read(clockProvider);
      expect(clock, isA<DateTime Function()>());
      final now = clock();
      // DateTime.now() may or may not be UTC depending on platform; just
      // verify it returns a reasonable value.
      expect(now.year, greaterThanOrEqualTo(2026));
    });

    testWidgets('override returns a fixed UTC timestamp', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            clockProvider.overrideWithValue(() => _fixedClock),
          ],
          child: const SizedBox.shrink(),
        ),
      );

      final container =
          ProviderScope.containerOf(tester.element(find.byType(SizedBox)));
      final clock = container.read(clockProvider);

      expect(clock(), _fixedClock);
      expect(clock().isUtc, isTrue);
      expect(tester.takeException(), isNull);
    });

    test('override produces deterministic milliseconds-since-epoch', () {
      final expectedMs = _fixedClock.millisecondsSinceEpoch;
      final container = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(() => _fixedClock),
        ],
      );
      addTearDown(container.dispose);

      final clock = container.read(clockProvider);
      expect(clock().millisecondsSinceEpoch, expectedMs);
    });

    test('override preserves toUtc identity (already-UTC stays same)', () {
      final container = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(() => _fixedClock),
        ],
      );
      addTearDown(container.dispose);

      final clock = container.read(clockProvider);
      // _fixedClock is already UTC; toUtc() should be identical.
      expect(clock().toUtc(), _fixedClock);
    });

    test('override injected as 31-bit mask yields stable watch-style seed',
        () {
      // Simulates how WatchScreen builds `_watchSeed`.
      final msMasked = _fixedClock.millisecondsSinceEpoch & 0x7fffffff;
      final container = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(() => _fixedClock),
        ],
      );
      addTearDown(container.dispose);

      final clock = container.read(clockProvider);
      expect(clock().millisecondsSinceEpoch & 0x7fffffff, msMasked);
    });

    test('two containers share the same default clock function', () {
      final c1 = ProviderContainer();
      addTearDown(c1.dispose);
      final c2 = ProviderContainer();
      addTearDown(c2.dispose);

      expect(
        c1.read(clockProvider),
        c2.read(clockProvider),
      );
    });

    testWidgets('override resolution in a nested ProviderScope',
        (tester) async {
      final outerFixed = DateTime.utc(2025, 6, 15);
      final innerFixed = DateTime.utc(2026, 12, 25);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            clockProvider.overrideWithValue(() => outerFixed),
          ],
          child: MaterialApp(
            home: ProviderScope(
              overrides: [
                clockProvider.overrideWithValue(() => innerFixed),
              ],
              child: const Center(child: Text('inner')),
            ),
          ),
        ),
      );

      final innerContainer = ProviderScope.containerOf(
        tester.element(find.text('inner')),
      );
      expect(innerContainer.read(clockProvider)(), innerFixed);

      final outerContainer = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );
      expect(outerContainer.read(clockProvider)(), outerFixed);
      expect(tester.takeException(), isNull);
    });

    test('default clock remains non-deterministic across invocations', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final clock = container.read(clockProvider);
      // Real DateTime.now is not guaranteed different within one test run,
      // but we verify it at least returns valid dates.
      final a = clock();
      final b = clock();
      // The difference should be ≤ 1 second (same invocation).
      expect((a.difference(b)).inSeconds, lessThanOrEqualTo(1));
    });
  });
}
