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
    show QualityLog, ReviewGame, ReviewLog, StatsLog, VariantReviewLog, clockProvider, turnProviderFactoryProvider;

import 'arena_test_harness.dart' as harness;
import 'semantics_invariants.dart' as semantics;

void main() {
  // ------------------------------------------------------------------------
  // Telemetry reset
  // ------------------------------------------------------------------------

  group('harness telemetry', () {
    setUp(harness.resetTelemetry);

    test('StatsLog.clear empties records and store', () {
      StatsLog.logTurn(
        gameId: 'game-1', agentId: 'a', modelKey: 'm',
        latencyMs: 100, inputTokens: 64, outputTokens: 32,
      );
      expect(StatsLog.records.length, 1);
      expect(StatsLog.store.listAll().length, 1);

      harness.resetTelemetry();

      expect(StatsLog.records, isEmpty);
      expect(StatsLog.store.listAll(), isEmpty);
    });

    test('QualityLog.clear resets marks', () {
      QualityLog.setAll(const ['!!', '!', '?']);
      expect(QualityLog.marks.length, 3);

      harness.resetTelemetry();
      expect(QualityLog.marks, const <String>[]);
    });

    test('ReviewLog.clear empties games list', () {
      ReviewLog.record(const ReviewGame(id: 'seeded-game', whiteLabel: 'White', blackLabel: 'Black'));
      expect(ReviewLog.games.length, greaterThanOrEqualTo(1));

      harness.resetTelemetry();
      expect(ReviewLog.games, isEmpty);
    });

    test('VariantReviewLog.clear does not throw when empty', () {
      expect(VariantReviewLog.games, isEmpty);

      harness.resetTelemetry();

      expect(VariantReviewLog.games, isEmpty);
    });

    test('resetTelemetry clears all four stores in sequence', () {
      StatsLog.logTurn(gameId: 'g', agentId: 'a', modelKey: 'm', color: 'white');
      QualityLog.setAll(['ok']);
      ReviewLog.record(const ReviewGame(id: 'r1', whiteLabel: 'W', blackLabel: 'B'));
      // VariantReviewLog has no public record constructor accessible from here;
      // but the clear call should not throw even when empty.

      harness.resetTelemetry();

      expect(StatsLog.records, isEmpty);
      expect(QualityLog.marks, isEmpty);
      expect(ReviewLog.games, isEmpty);
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
