/// ArenaScreen → VariantReviewLog recording path (§6.6 companion, §13 wired).
///
/// Pins the chaotic-games-into-[VariantReviewLog] wiring that [_concludeGame]
/// performs at `arena_screen.dart` ~1552-1566: every finished (or cancelled)
/// chaotic tournament game lands a lossless [VariantGameRecord] (initial
/// board + per-ply interpretation trail) that the review screen lists under
/// "Chaotic replays" and replays in [VariantReplayScreen]. Also pins the
/// isolation contract: FEN-shaped [ReviewLog] gets standard games only, and
/// [VariantReviewLog] gets chaotic games only.
///
/// Uses deterministic fakes (MockProvider always plays the first legal
/// attempt, fixed UTC clock, seeded tournament via `initialSeed: 42`) — never
/// touches real network, engine, or wall-clock.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/arena/elo.dart' show EloService;
import 'package:llm_chess_arena/src/ui/backend_bridge.dart'
    show ReviewLog, VariantReviewLog;
import 'package:llm_chess_arena/src/ui/screens/arena_screen.dart'
    show ArenaScreen;
import 'package:llm_chess_arena/src/ui/screens/review_screen.dart'
    show ReviewScreen;
import 'package:llm_chess_arena/src/ui/screens/variant_replay_screen.dart'
    show VariantReplayScreen;
import 'package:llm_chess_arena/src/ui/ui_models.dart'
    show AgentListStore, agentListProvider;

import '../support/arena_test_harness.dart' as harness;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

List<Override> _overrides({
  required VariantReviewLog variant,
  required ReviewLog review,
}) =>
    <Override>[
      ...harness.fakeOverrides(),
      ...harness.telemetryOverrides(variant: variant, review: review),
      agentListProvider.overrideWith((ref) => AgentListStore(seedDemos: true)),
    ];

Future<void> _pumpArena(
  WidgetTester tester, {
  required VariantReviewLog variant,
  required ReviewLog review,
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ProviderScope(
          overrides: _overrides(variant: variant, review: review),
          child: ArenaScreen(elo: EloService(), initialSeed: 42),
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

/// Runs one tournament (chaotic or standard) to completion using the two
/// seeded demo agents: 1 pairing × 2 games per pairing × 1 round = 2 games,
/// concurrency 2 → both games dispatch in one batch. Pumps until both
/// records land (or a generous cap), then Stops if still running — the
/// chaotic pump records on cancellation too, so the count stays 2 either way.
Future<void> _runTournament(
  WidgetTester tester, {
  required bool chaotic,
  required VariantReviewLog variant,
  required ReviewLog review,
}) async {
  await _pumpArena(tester, variant: variant, review: review);
  if (chaotic) {
    await tester.tap(find.widgetWithText(FilterChip, 'Chaos variants').first);
    await tester.pump();
  }
  await tester.tap(find.text('Start tournament'));
  await tester.pump();
  int done() => chaotic ? variant.games.length : review.games.length;
  for (var i = 0; i < 200 && done() < 2; i++) {
    await _pumpSteps(tester);
  }
  if (find.text('Stop').evaluate().isNotEmpty) {
    await tester.tap(find.text('Stop'));
    await tester.pump();
    await _pumpSteps(tester, steps: 8);
  }
  expectNoException(tester);
}

void expectNoException(WidgetTester tester, {String context = ''}) {
  expect(tester.takeException(), isNull, reason: 'exception: $context');
}

void main() {
  group('Arena chaotic games land in VariantReviewLog (§6.6/§13 wire)', () {
    testWidgets('chaotic tournament records 2 lossless games with valid chain',
        (tester) async {
      final variant = VariantReviewLog();
      final review = ReviewLog();
      await _runTournament(
        tester,
        chaotic: true,
        variant: variant,
        review: review,
      );
      await harness.disposeApp(tester);

      expect(variant.games.length, 2, reason: '1 pairing × 2 games/pairing');
      for (final game in variant.games) {
        expect(game.mode, 'chaotic');
        // Color alternation: each pairing plays both seats across the 2 games,
        // so white/black are always the two demo agents, one each per game.
        expect(
          <String>{game.whiteLabel, game.blackLabel},
          <String>{'Demo White', 'Demo Black'},
        );
        expect(game.whiteAgentId, anyOf('demo-white', 'demo-black'));
        expect(game.blackAgentId, anyOf('demo-white', 'demo-black'));
        expect(game.whiteAgentId, isNot(game.blackAgentId));
        expect(game.id, isNotEmpty);
        expect(game.tournamentId, isNotEmpty);
        expect(game.seed, greaterThanOrEqualTo(0));
        expect(game.initialBoard, isNotNull);
        expect(game.outcome, anyOf('1-0', '0-1', '1/2-1/2', '*'));
        expect(game.reason, isNotEmpty);
        expect(game.startedAt, isNotNull);
        expect(game.finishedAt, isNotNull);
        expect(
          game.finishedAt!.isBefore(game.startedAt!),
          isFalse,
          reason: 'finish must not precede start',
        );
        for (var i = 0; i < game.plies.length; i++) {
          final ply = game.plies[i];
          expect(ply.ply, i, reason: 'ply indices sequential');
          expect(ply.mover, anyOf('w', 'b'));
          expect(ply.attempt.uci.length, greaterThanOrEqualTo(4));
        }
        expect(game.validateChain(), isEmpty,
            reason: 'board + hash chain integrity');
      }
      expect(review.games, isEmpty,
          reason: 'chaotic games must not pollute the FEN ReviewLog');
      expectNoException(tester);
    });

    testWidgets('cancelled chaotic game still records a partial trail',
        (tester) async {
      final variant = VariantReviewLog();
      final review = ReviewLog();
      await _pumpArena(tester, variant: variant, review: review);
      await tester.tap(find.widgetWithText(FilterChip, 'Chaos variants').first);
      await tester.pump();
      await tester.tap(find.text('Start tournament'));
      await tester.pump();
      // Advance a little so in-flight chaotic pumps start, then Stop
      // mid-run: the pumps see _cancelling between turns and _concludeGame
      // records the partial (possibly 0-ply) trail.
      await _pumpSteps(tester, steps: 4);
      if (find.text('Stop').evaluate().isNotEmpty) {
        await tester.tap(find.text('Stop'));
        await tester.pump();
        await _pumpSteps(tester, steps: 8);
      }
      await harness.disposeApp(tester);
      expect(variant.games.length, 2,
          reason: 'both in-flight games conclude (cancelled) on Stop');
      for (final game in variant.games) {
        expect(game.mode, 'chaotic');
        expect(game.validateChain(), isEmpty);
        expect(game.outcome, '*');
        expect(game.reason, 'cancelled');
      }
      expectNoException(tester);
    });

    testWidgets('standard tournament lands in ReviewLog, not VariantReviewLog',
        (tester) async {
      final variant = VariantReviewLog();
      final review = ReviewLog();
      await _runTournament(
        tester,
        chaotic: false,
        variant: variant,
        review: review,
      );
      await harness.disposeApp(tester);

      expect(review.games.length, 2, reason: '1 pairing × 2 games/pairing');
      for (final game in review.games) {
        expect(game.mode, 'standard');
        expect(game.id, isNotEmpty);
        expect(game.ucis.length, greaterThan(0));
      }
      expect(variant.games, isEmpty,
          reason: 'standard games must not land in VariantReviewLog');
      expectNoException(tester);
    });
  });

  group('Review screen surfaces arena chaotic replays (E2E)', () {
    testWidgets('recorded chaotic game lists under Chaotic replays and opens '
        'VariantReplayScreen', (tester) async {
      final variant = VariantReviewLog();
      final review = ReviewLog();
      await _runTournament(
        tester,
        chaotic: true,
        variant: variant,
        review: review,
      );
      expect(variant.games, isNotEmpty, reason: 'pre-condition from the run');

      // Now pump the review screen against the SAME log instance.
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: harness.telemetryOverrides(variant: variant),
          child: const MaterialApp(
            home: Scaffold(body: ReviewScreen()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Chaotic replays'), findsOneWidget);
      expect(find.text('Demo White vs Demo Black'), findsWidgets);

      await tester.tap(find.text('Demo White vs Demo Black').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(VariantReplayScreen), findsOneWidget);
      expect(find.text('Demo White vs Demo Black'), findsWidgets);
      expectNoException(tester);
      await harness.disposeApp(tester);
    });
  });
}