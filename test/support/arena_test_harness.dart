/// Shared test harness for LMChess widget tests.
///
/// Provides surface-size setup, app-pumping helpers, telemetry store
/// helpers, and timer-drain utilities so individual UI tests stay fast,
/// deterministic, and leak-free.
///
/// **Conventions adopted from this repository:**
/// * No `pumpAndSettle` around spinners / live loops — use [pumpSteps].
/// * Never hit real network or spawn Stockfish in widget tests — override
///   providers via [pumpArenaApp] overrides.
/// * Telemetry stores are per-`ProviderScope` (§13 isolation): pumping a
///   fresh scope already gives fresh `StatsLog`/`QualityLog`/`ReviewLog`/
///   `VariantReviewLog` instances, so no reset between tests is needed.
///   Use [telemetryOverrides] only to seed a store before pumping.
/// * Call [disposeApp] at test end to drain timers; pending-timer failures
///   are the most common source of flaky teardowns.
/// * Use a desktop surface (`Size(1400, 1000)`) unless you explicitly need
///   narrow layout testing.
///
/// ```dart
/// void main() {
///   testWidgets('example', (tester) async {
///     await pumpArenaApp(tester);
///     // ... interact ...
///     await disposeApp(tester);
///   });
/// }
/// ```
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/app.dart' show ArenaApp;
import 'package:llm_chess_arena/src/agent/agent_config.dart';
import 'package:llm_chess_arena/src/llm/mock_provider.dart';
import 'package:llm_chess_arena/src/llm/provider.dart' show ProviderId;
import 'package:llm_chess_arena/src/llm/tool_schema.dart' show MoveToolCall;
import 'package:llm_chess_arena/src/llm/validation.dart' show FailureKind;
import 'package:llm_chess_arena/src/ui/backend_bridge.dart'
    show
        QualityLog,
        ReviewLog,
        StatsLog,
        VariantReviewLog,
        clockProvider,
        qualityLogProvider,
        reviewLogProvider,
        statsLogProvider,
        turnProviderFactoryProvider,
        variantReviewLogProvider;

// ---------------------------------------------------------------------------
// Surface size helpers
// ---------------------------------------------------------------------------

/// Set a desktop-sized view on [tester] with a tear-down to reset it.
void useDesktopSurface(
  WidgetTester tester, {
  Size size = const Size(1400, 1000),
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

// ---------------------------------------------------------------------------
// Pump helpers
// ---------------------------------------------------------------------------

/// Pump the full [ArenaApp] with optional provider overrides and an optional
/// surface size. The default size is desktop-wide (`1400 × 1000`).
Future<void> pumpArenaApp(
  WidgetTester tester, {
  Size size = const Size(1400, 1000),
  List<Override> overrides = const <Override>[],
}) async {
  useDesktopSurface(tester, size: size);
  await tester.pumpWidget(
    ProviderScope(overrides: overrides, child: const ArenaApp()),
  );
  await tester.pump();
}

/// Pump [steps] discrete frames spaced by [step] duration.
///
/// Intended for screens with animated transitions, spinner rotations, or
/// periodic timers where `pumpAndSettle` would hang. Typical call:
/// `await pumpSteps(tester, steps: 12);`
Future<void> pumpSteps(
  WidgetTester tester, {
  int steps = 12,
  Duration step = const Duration(milliseconds: 100),
}) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(step);
  }
}

/// Replace the current widget tree with a no-op widget and drain any
/// pending timers. Call at the end of every test that starts Watch/Arena/Play
/// loops so stale timers do not fail the framework assertion.
Future<void> disposeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

// ---------------------------------------------------------------------------
// Telemetry store helpers (per-scope isolation replaces process-global reset)
// ---------------------------------------------------------------------------

/// Fresh, isolated telemetry stores wired as provider overrides.
///
/// Every `ProviderScope` already builds its own store instances (see
/// `statsLogProvider`/`qualityLogProvider`/`reviewLogProvider`/
/// `variantReviewLogProvider` in `backend_bridge.dart`), so widget tests
/// need **no** reset between tests. Use this helper only when a test seeds
/// a store *before* pumping: create the store, seed it, and pass it here so
/// the scope hands that exact instance to the screen under test.
///
/// * `StatsLog` — turn/game-end records + event store mirror.
/// * `QualityLog` — per-ply quality marks.
/// * `ReviewLog` — finished games awaiting review.
/// * `VariantReviewLog` — variant replay records.
List<Override> telemetryOverrides({
  StatsLog? stats,
  QualityLog? quality,
  ReviewLog? review,
  VariantReviewLog? variant,
}) {
  return <Override>[
    statsLogProvider.overrideWithValue(stats ?? StatsLog()),
    qualityLogProvider.overrideWithValue(quality ?? QualityLog()),
    reviewLogProvider.overrideWithValue(review ?? ReviewLog()),
    variantReviewLogProvider.overrideWithValue(variant ?? VariantReviewLog()),
  ];
}

// ---------------------------------------------------------------------------
// Deterministic fakes
// ---------------------------------------------------------------------------

/// A factory-returned fake agent config (used by [fakeAgents]).
AgentConfig fakeAgent({
  String id = 'fake-agent',
  String name = 'Fake Agent',
}) {
  return AgentConfig(
    id: id,
    name: name,
    providerId: ProviderId.mock,
    model: 'test-model',
    temperature: 0.0,
    maxTokens: 256,
    timeoutMs: 30000,
    systemPrompt: '',
    customInstructions: '',
    apiKeyRef: null,
  );
}

/// Two fake agents suitable for Watch/Arena tests (both mock).
List<AgentConfig> get fakeAgents => <AgentConfig>[
      fakeAgent(id: 'agent-a', name: 'Agent A'),
      fakeAgent(id: 'agent-b', name: 'Agent B'),
];

/// An override list that replaces all production seams with deterministic
/// fakes (turn provider → always returns a legal UCI, clock → fixed UTC).
List<Override> fakeOverrides({
  DateTime? fixedClock,
}) {
  final clockFunc = fixedClock ?? DateTime.utc(2026, 1, 1);
  return <Override>[
    turnProviderFactoryProvider.overrideWithValue(
      (config, legalUcis, {seed, phrase}) async {
        if (legalUcis.isEmpty) {
          return MockProvider(
            script: const <Object>[FailureKind.incompleteResponse],
            model: config.model,
          );
        }
        final uci = legalUcis.first;
        return MockProvider(
          script: <Object>[
            MoveToolCall(
              from: uci.substring(0, 2),
              to: uci.substring(2, 4),
              promotion: uci.length > 4 ? uci.substring(4, 5) : null,
              phrase: phrase,
            ),
          ],
          model: config.model,
        );
      },
    ),
    clockProvider.overrideWithValue(() => clockFunc),
  ];
}

// ---------------------------------------------------------------------------
// Expect-no-exception helper
// ---------------------------------------------------------------------------

/// Assert that no exception was captured during the test run.
///
/// When a test fails this check, printing the semantics tree helps diagnose
/// whether the crash came from semantics churn.
void expectNoException(WidgetTester tester, {String context = ''}) {
  expect(tester.takeException(), isNull, reason: context.isNotEmpty ? 'exception: $context' : null);
}
