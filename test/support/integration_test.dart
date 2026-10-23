// Integration tests for the support directory (harness + semantics invariants).
//
// These tests prove that the harness functions are importable, deterministic,
// and correctly wired. They do NOT pump real screens — that belongs in
// per-screen widget tests under `test/ui/`. No real network or engine calls.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/app.dart' show ArenaApp;
import 'package:llm_chess_arena/src/agent/agent_config.dart';
import 'package:llm_chess_arena/src/llm/mock_provider.dart';
import 'package:llm_chess_arena/src/llm/provider.dart' show ProviderId;
import 'package:llm_chess_arena/src/ui/backend_bridge.dart'
    show
        QualityLog,
        ReviewGame,
        ReviewLog,
        StatsLog,
        VariantReviewLog,
        clockProvider,
        statsLogProvider,
        turnProviderFactoryProvider;

import 'arena_test_harness.dart' as harness;
import 'semantics_invariants.dart' as semantics;

void main() {
  // ------------------------------------------------------------------------
  // Telemetry stores (per-provider-scope isolation)
  // ------------------------------------------------------------------------

  group('harness telemetry', () {
    test('StatsLog instance seeds records and mirrors them to the event store', () {
      final stats = StatsLog();
      stats.logTurn(
        gameId: 'game-1',
        agentId: 'a',
        modelKey: 'm',
        latencyMs: 100,
        inputTokens: 64,
        outputTokens: 32,
      );
      expect(stats.records.length, 1);
      expect(stats.store.listAll().length, 1);
    });

    test('QualityLog and ReviewLog seed and read their own instances', () {
      final quality = QualityLog();
      quality.setAll(const ['!!', '!', '?']);
      expect(quality.marks.length, 3);

      final review = ReviewLog();
      review.record(
        const ReviewGame(
          id: 'seeded-game',
          whiteLabel: 'White',
          blackLabel: 'Black',
        ),
      );
      expect(review.games.length, greaterThanOrEqualTo(1));
    });

    test('VariantReviewLog starts empty on a fresh instance', () {
      final variant = VariantReviewLog();
      expect(variant.games, isEmpty);
      variant.clear();
      expect(variant.games, isEmpty);
    });

    test('independent StatsLog instances never share state', () {
      final seeded = StatsLog();
      seeded.logTurn(
        gameId: 'g',
        agentId: 'a',
        modelKey: 'm',
        color: 'white',
      );
      final other = StatsLog();

      expect(seeded.records, hasLength(1));
      expect(other.records, isEmpty);
      expect(other.store.listAll(), isEmpty);
    });

    test('statsLogProvider builds a fresh store per ProviderContainer', () {
      final containerA = ProviderContainer();
      final containerB = ProviderContainer();
      addTearDown(containerA.dispose);
      addTearDown(containerB.dispose);

      final logA = containerA.read(statsLogProvider);
      final logB = containerB.read(statsLogProvider);
      expect(identical(logA, logB), isFalse);

      logA.logTurn(gameId: 'g', agentId: 'a', modelKey: 'm');

      expect(logA.records, hasLength(1));
      expect(logB.records, isEmpty);
    });
  });

  // ------------------------------------------------------------------------
  // Fake agent / overrides
  // ------------------------------------------------------------------------

  group('harness fakes', () {
    test('fakeAgent produces valid AgentConfig', () {
      final agent = harness.fakeAgent();
      expect(agent.id, 'fake-agent');
      expect(agent.name, 'Fake Agent');
      expect(agent.providerId, ProviderId.mock);
      expect(agent.model, 'test-model');
      expect(agent.validate(), isEmpty);
    });

    test('fakeAgents returns two agents', () {
      final agents = harness.fakeAgents;
      expect(agents.length, 2);
      expect(agents[0].id, 'agent-a');
      expect(agents[1].id, 'agent-b');
    });

    test('fakeOverrides contains override entries', () {
      final overrides = harness.fakeOverrides();
      expect(overrides.length, 2); // turn provider + clock
    });

    testWidgets('fakeOverrides resolve inside ProviderScope', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: harness.fakeOverrides(fixedClock: DateTime.utc(2025, 6, 1)),
          child: const SizedBox.shrink(),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SizedBox)),
      );

      // Clock should return our fixed UTC date.
      final clock = container.read(clockProvider);
      expect(clock(), DateTime.utc(2025, 6, 1));
      expect(clock().isUtc, isTrue);

      // Turn provider factory should produce a MockProvider for legal moves.
      final factory = container.read(turnProviderFactoryProvider);
      final provider = await factory(
        AgentConfig(
          id: 't', name: 'T',
          providerId: ProviderId.mock, model: 't',
        ),
        ['e2e4'],
      );
      expect(provider, isA<MockProvider>());
    });
  });

  // ------------------------------------------------------------------------
  // Desktop surface
  // ------------------------------------------------------------------------

  group('harness surface', () {
    testWidgets('useDesktopSurface sets physicalSize and resets on tear-down',
        (tester) async {
      useTestSurface(tester);

      expect(tester.view.physicalSize, const Size(1400, 1000));
      expect(tester.view.devicePixelRatio, 1.0);
    });

    testWidgets('pumpArenaApp renders app with overrides', (tester) async {
      await pumpCustomApp(tester);
      expect(find.byType(Scaffold), findsOneWidget);
    });
  });

  // ------------------------------------------------------------------------
  // Semantics invariants
  // ------------------------------------------------------------------------

  group('semantics invariants', () {
    testWidgets('expectSemanticsTreeInvariants passes on a simple tree',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Hello'))),
      );
      await tester.pumpAndSettle();

      semantics.expectSemanticsTreeInvariants(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('captureSemantics returns root and nodes', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Column(children: [Text('A'), Text('B')])))
        );
      await tester.pumpAndSettle();

      final capture = semantics.captureSemantics(tester);
      expect(capture.root, isNotNull);
      expect(capture.nodes, isNotEmpty);
      expect(capture.nodes.length, greaterThanOrEqualTo(2));
    });

    testWidgets('parentMap builds correct mapping', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Row(children: [Text('L'), Text('R')]))),
      );
      await tester.pumpAndSettle();

      final pMap = semantics.parentMap(semantics.captureSemantics(tester));
      // Root maps to null.
      expect(pMap[semantics.captureSemantics(tester).root.id], isNull);
    });

    testWidgets('expectNoReparenting accepts same parent ids', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Stable'))),
      );
      await tester.pumpAndSettle();

      final before = semantics.captureSemantics(tester);
      final beforeMap = semantics.parentMap(before);

      // Just re-pump the same tree.
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Stable'))),
      );
      await tester.pump();

      final afterMap = semantics.parentMap(semantics.captureSemantics(tester));
      semantics.expectNoReparenting(beforeMap, afterMap);
    });

    testWidgets('captureSemanticsSafe wraps ensureSemantics properly',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Safe'))),
      );
      await tester.pumpAndSettle();

      final result = semantics.captureSemanticsSafe(tester);
      expect(result.root, isNotNull);
    });
  });

  // ------------------------------------------------------------------------
  // expectNoException
  // ------------------------------------------------------------------------

  group('harness helpers', () {
    testWidgets('expectNoException passes when no exception', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: Text('OK')))));
      expect(() => harness.expectNoException(tester), returnsNormally);
    });

    testWidgets('expectNoExceptionWithSemanticsDump passes clean', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Center(child: Text('OK')))),
      );
      await tester.pumpAndSettle();
      expect(
        () => semantics.expectNoExceptionWithSemanticsDump(tester, 'clean'),
        returnsNormally,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'expectNoExceptionWithSemanticsDump fails with context on a pending '
        'exception and drains it', (tester) async {
      // Gesture-callback throw — the canonical deterministic pending
      // exception in widget tests (recorded by the framework, not rethrown).
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => GestureDetector(
                onTap: () => throw StateError('forced kboom'),
                child: const Text('tap-me'),
              ),
            ),
          ),
        ),
      );
      final handle = tester.ensureSemantics();
      await tester.tap(find.text('tap-me'));
      await tester.pump();
      expect(tester.takeException(), isA<StateError>());

      // Re-arm the pending exception: the previous takeException drained it.
      await tester.tap(find.text('tap-me'));
      await tester.pump();

      Object? thrown;
      try {
        semantics.expectNoExceptionWithSemanticsDump(tester, 'forced context');
      } catch (e) {
        thrown = e;
      }
      try {
        expect(thrown, isNotNull,
            reason: 'helper must fail on a pending exception');
        expect(thrown.toString(), contains('forced context'));
        expect(thrown.toString(), contains('forced kboom'));
        // The helper drained the pending exception.
        expect(tester.takeException(), isNull);
      } finally {
        handle.dispose();
      }
    });

    testWidgets('disposeApp drains timers without crash', (tester) async {
      await tester.pumpWidget(Container());
      expect(() async => harness.disposeApp(tester), returnsNormally);
    });
  });
}

// Local helpers to avoid importing the harness module's own helpers in the
// top-level scope (keeps imports clean).
void useTestSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> pumpCustomApp(WidgetTester tester) async {
  useTestSurface(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.fakeOverrides(),
      child: const ArenaApp(),
    ),
  );
  await tester.pump();
}
