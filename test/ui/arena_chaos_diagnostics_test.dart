/// ArenaScreen chaotic-pump runner-failure diagnostics (§11.40).
///
/// Pins the degradation contract of the chaotic turn pump at
/// `arena_screen.dart` `_runGame`: when [AgentRunner.runTurn] throws (a
/// genuine runner-internal bug, as opposed to a documented provider outage,
/// which is returned as a failure outcome), the game must NOT crash or abort
/// the tournament — the exception is contained, the turn is treated as a
/// provider error, and the same seeded fallback attempt the provider-error
/// path uses is played. The failure is surfaced via a `dart:developer`
/// `log()` (the §11.35 diagnostics pattern) so it is distinguishable from a
/// provider outage in the stats trail.
///
/// Uses the [ArenaScreen.chaosRunner] test seam (default null → the shared
/// stateless runner) with a throwing [AgentRunner] subclass. Deterministic
/// fakes only — never touches real network, engine, or wall-clock.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:llm_chess_arena/src/agent/agent_config.dart'
    show AgentConfig, ApiKeyResolver;
import 'package:llm_chess_arena/src/agent/agent_runner.dart'
    show AgentRunner, AgentTurnRequest, AgentTurnResult;
import 'package:llm_chess_arena/src/llm/provider.dart'
    show CancelToken, LlmProvider, LlmStreamEvent;
import 'package:llm_chess_arena/src/ui/backend_bridge.dart'
    show ReviewLog, StatsLog, VariantReviewLog;
import 'package:llm_chess_arena/src/ui/screens/arena_screen.dart'
    show ArenaScreen;
import 'package:llm_chess_arena/src/ui/ui_models.dart'
    show AgentListStore, agentListProvider;

import '../support/arena_test_harness.dart' as harness;

/// A chaos runner whose [runTurn] always throws — simulates a genuine
/// runner-internal bug (the catch-all the pump degrades from).
class _ThrowingRunner extends AgentRunner {
  const _ThrowingRunner();

  @override
  Future<AgentTurnResult> runTurn(
    AgentConfig config,
    AgentTurnRequest turn, {
    int? seed,
    LlmProvider? providerOverride,
    void Function(LlmStreamEvent event)? onEvent,
    ApiKeyResolver? apiKeyResolver,
    http.Client? httpClient,
    CancelToken? cancelToken,
  }) async {
    throw StateError('forced runner failure (test seam)');
  }
}

List<Override> _overrides({
  required VariantReviewLog variant,
  required ReviewLog review,
  required StatsLog stats,
}) =>
    <Override>[
      ...harness.fakeOverrides(),
      ...harness.telemetryOverrides(
        variant: variant,
        review: review,
        stats: stats,
      ),
      agentListProvider.overrideWith((ref) => AgentListStore(seedDemos: true)),
    ];

Future<void> _pumpArena(
  WidgetTester tester, {
  required List<Override> overrides,
  AgentRunner? chaosRunner,
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ProviderScope(
          overrides: overrides,
          child: ArenaScreen(
            initialSeed: 42,
            chaosRunner: chaosRunner,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpSteps(WidgetTester tester, {int steps = 6}) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Runs a chaotic tournament to (near) completion: taps Chaos variants,
/// starts, pumps until both games recorded or a generous cap, and Stops if
/// still running (cancelled games still record, so the count stays 2 either
/// way, mirroring the arena_variant_review suite's helper).
Future<void> _runChaoticTournament(
  WidgetTester tester, {
  required List<Override> overrides,
  AgentRunner? chaosRunner,
}) async {
  await _pumpArena(tester, overrides: overrides, chaosRunner: chaosRunner);
  await tester.tap(find.widgetWithText(FilterChip, 'Chaos variants').first);
  await tester.pump();
  await tester.tap(find.text('Start tournament'));
  await tester.pump();
  for (var i = 0; i < 200; i++) {
    await _pumpSteps(tester);
    if (find.text('Stop').evaluate().isNotEmpty == false) break;
  }
  if (find.text('Stop').evaluate().isNotEmpty) {
    await tester.tap(find.text('Stop'));
    await tester.pump();
    await _pumpSteps(tester, steps: 8);
  }
  expect(tester.takeException(), isNull, reason: 'tournament loop exception');
}

void main() {
  group('ArenaScreen chaotic pump: runner failure diagnostics (§11.40)', () {
    testWidgets('throwing runner degrades to seeded fallback, records '
        'providerError, and never crashes the tournament', (tester) async {
      final variant = VariantReviewLog();
      final review = ReviewLog();
      final stats = StatsLog();
      await _runChaoticTournament(
        tester,
        overrides: _overrides(variant: variant, review: review, stats: stats),
        chaosRunner: const _ThrowingRunner(),
      );
      await harness.disposeApp(tester);

      // The failure was contained: the tournament concluded (or cancelled)
      // both games and every chaotic turn played the seeded fallback.
      expect(variant.games.length, 2,
          reason: '1 pairing × 2 games/pairing conclude even with a '
              'throwing runner');
      for (final game in variant.games) {
        expect(game.mode, 'chaotic');
        expect(game.validateChain(), isEmpty,
            reason: 'board + hash chain integrity survives fallback plies');
        for (final ply in game.plies) {
          expect(ply.fallback, isTrue,
              reason: 'every turn from a throwing runner degrades to the '
                  'seeded fallback attempt');
        }
      }
      expect(review.games, isEmpty,
          reason: 'chaotic games must not pollute the FEN ReviewLog');

      // The degrade path is recorded as a provider error in the stats trail
      // (a genuine runner bug is now distinguishable from a provider outage).
      expect(
        stats.records.any(
          (r) => r.payloadJson['providerError'] == true,
        ),
        isTrue,
        reason: 'the throwing turn must be stats-logged with '
            'providerError: true',
      );
      expectNoException(tester);
    });

    testWidgets('default runner (no seam) records model-sourced plies with '
        'zero providerError', (tester) async {
      final variant = VariantReviewLog();
      final review = ReviewLog();
      final stats = StatsLog();
      await _runChaoticTournament(
        tester,
        overrides: _overrides(variant: variant, review: review, stats: stats),
      );
      await harness.disposeApp(tester);

      // Production default is unchanged: the mock provider's model attempt
      // lands as a model-sourced ply, never flagged as provider error.
      expect(variant.games.length, 2,
          reason: 'healthy tournament still concludes both games');
      var sawModelPly = false;
      for (final game in variant.games) {
        for (final ply in game.plies) {
          if (!ply.fallback) sawModelPly = true;
        }
      }
      expect(sawModelPly, isTrue,
          reason: 'a healthy runner must record at least one model ply');
      expect(
        stats.records.any((r) => r.payloadJson['providerError'] == true),
        isFalse,
        reason: 'no providerError on the healthy default path',
      );
      expectNoException(tester);
    });
  });
}

void expectNoException(WidgetTester tester, {String context = ''}) {
  expect(tester.takeException(), isNull, reason: 'exception: $context');
}