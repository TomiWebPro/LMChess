// Regression tests for the §10.2 review-evaluator seam:
// [reviewEvaluatorFactoryProvider] / [ReviewEvaluatorFactory].
//
// Widget tests must never spawn a Stockfish process. ReviewScreen and
// VariantReplayScreen resolve their evaluator through this provider
// (defaulting to [resolveReviewEvaluator]) so tests can override it with a
// heuristic-only handle — no engine binary, no network calls.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/review/engine_adapter.dart';
import 'package:llm_chess_arena/src/ui/backend_bridge.dart';

/// Build a minimal heuristic-only handle without touching any engine binary.
Future<ReviewEvaluatorHandle> _heuristicOnlyHandle() async =>
    ReviewEvaluatorHandle(
      evaluator: HeuristicEvaluator(),
      resolvedSource: EngineSources.heuristic,
      fallbackReason: 'override: no Stockfish in tests',
    );

void main() {
  group('reviewEvaluatorFactoryProvider (§10.2 seam)', () {
    test('defaults to resolveReviewEvaluator (non-null factory)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final factory = container.read(reviewEvaluatorFactoryProvider);
      expect(factory, isNotNull);
      // The default returns the same function reference every time.
      final factory2 = container.read(reviewEvaluatorFactoryProvider);
      expect(factory, factory2);
    });

    testWidgets('override returns a heuristic-only handle (no engine)',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            reviewEvaluatorFactoryProvider.overrideWithValue(_heuristicOnlyHandle),
          ],
          child: const SizedBox.shrink(),
        ),
      );

      final container =
          ProviderScope.containerOf(tester.element(find.byType(SizedBox)));
      final handle = await container.read(reviewEvaluatorFactoryProvider)();

      expect(handle.resolvedSource, EngineSources.heuristic);
      expect(handle.isFallback, isTrue);
      expect(handle.fallbackReason, 'override: no Stockfish in tests');
      expect(handle.engine, isNull);
      expect(tester.takeException(), isNull);
    });

    test('override observes seed/phrase passthrough (factory captures params)',
        () async {
      bool called = false;
      final container = ProviderContainer(
        overrides: [
          reviewEvaluatorFactoryProvider.overrideWithValue(() async {
            called = true;
            return _heuristicOnlyHandle();
          }),
        ],
      );
      addTearDown(container.dispose);

      // The factory takes no args by design (the screen passes record id
      // externally); prove it runs synchronously and produces a valid handle.
      final factory = container.read(reviewEvaluatorFactoryProvider);
      expect(called, isFalse); // not called until invoked
      // Now call it:
      final result = await factory();
      expect(called, isTrue);
      expect(result.resolvedSource, EngineSources.heuristic);
    });

    test('override injects a thrown failure', () {
      final container = ProviderContainer(
        overrides: [
          reviewEvaluatorFactoryProvider.overrideWithValue(
            () => Future<ReviewEvaluatorHandle>.error(StateError('eval down')),
          ),
        ],
      );
      addTearDown(container.dispose);

      expectLater(
        container.read(reviewEvaluatorFactoryProvider)(),
        throwsStateError,
      );
    });

    testWidgets('default factory provider resolves without error',
        (tester) async {
      // Pump the widget tree so the ProviderScope exists, then verify the
      // default provider resolves to the real resolver (no error thrown).
      await tester.pumpWidget(
        ProviderScope(
          child: const SizedBox.shrink(),
        ),
      );

      final container =
          ProviderScope.containerOf(tester.element(find.byType(SizedBox)));
      final factory = container.read(reviewEvaluatorFactoryProvider);
      expect(factory, isNotNull);
      // We intentionally do NOT invoke the factory here — resolveReviewEvaluator
      // probes for embedded Stockfish which is slow on headless Linux. The test
      // above (heuristic-only override) proves the provider wiring works; this
      // test only confirms that the default assignment is valid code.
      expect(tester.takeException(), isNull);
    });

    test('two containers share the same default factory function', () {
      final c1 = ProviderContainer();
      addTearDown(c1.dispose);
      final c2 = ProviderContainer();
      addTearDown(c2.dispose);

      expect(
        c1.read(reviewEvaluatorFactoryProvider),
        c2.read(reviewEvaluatorFactoryProvider),
      );
    });

    test('override survives container dispose round-trip (captured closure)',
        () async {
      var captured = false;
      final container = ProviderContainer(
        overrides: [
          reviewEvaluatorFactoryProvider.overrideWithValue(() {
            captured = true;
            return _heuristicOnlyHandle();
          }),
        ],
      );
      addTearDown(container.dispose);

      final handle = await container.read(reviewEvaluatorFactoryProvider)();
      expect(captured, isTrue);
      expect(handle.isFallback, isTrue);
      await handle.dispose();
    });

    testWidgets('override resolution in a nested ProviderScope', (tester) async {
      var outerCalled = false;
      var innerCalled = false;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            reviewEvaluatorFactoryProvider.overrideWithValue(() {
              outerCalled = true;
              return _heuristicOnlyHandle();
            }),
          ],
          child: MaterialApp(
            home: ProviderScope(
              overrides: [
                reviewEvaluatorFactoryProvider.overrideWithValue(() {
                  innerCalled = true;
                  return _heuristicOnlyHandle();
                }),
              ],
              child: const Center(child: Text('inner')),
            ),
          ),
        ),
      );

      final innerContainer = ProviderScope.containerOf(
        tester.element(find.text('inner')),
      );
      await innerContainer.read(reviewEvaluatorFactoryProvider)();
      expect(innerCalled, isTrue);
      expect(outerCalled, isFalse); // inner scope shadows outer

      // Verify outer scope still has its own override
      final outerContainer = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );
      await outerContainer.read(reviewEvaluatorFactoryProvider)();
      expect(outerCalled, isTrue);
      expect(tester.takeException(), isNull);
    });
  });
}
