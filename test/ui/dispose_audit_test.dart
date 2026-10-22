// §10.8 Dispose audit — ReviewEvaluatorHandle disposal-counting tests
//
// Verifies that every evaluator handle is disposed exactly once across the
// full lifecycle: leave mid-run, re-run supersede, and stale-completion guard.
//
// Uses _SpyHandle (extends ReviewEvaluatorHandle) injected via
// reviewEvaluatorFactoryProvider.overrideWithValue(...) so we can count
// .dispose() calls per instance.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/chess/position.dart';
import 'package:llm_chess_arena/src/review/engine_adapter.dart'
    show EngineSources, HeuristicEvaluator;
import 'package:llm_chess_arena/src/variant/chaotic_engine.dart';
import 'package:llm_chess_arena/src/variant/interpretation.dart';
import 'package:llm_chess_arena/src/variant/variant_board.dart';
import 'package:llm_chess_arena/src/variant/variant_replay.dart';
import 'package:llm_chess_arena/src/ui/backend_bridge.dart'
    show ReviewLog, ReviewGame, reviewEvaluatorFactoryProvider,
        ReviewEvaluatorHandle;
import 'package:llm_chess_arena/src/ui/screens/review_screen.dart'
    show ReviewScreen;
import 'package:llm_chess_arena/src/ui/screens/variant_replay_screen.dart';
import '../support/arena_test_harness.dart' as harness;

// ─── Test spy handle ────────────────────────────────────────────────
class _SpyHandle extends ReviewEvaluatorHandle {
  _SpyHandle()
      : super(
          evaluator: HeuristicEvaluator(),
          resolvedSource: EngineSources.heuristic,
        );

  /// Number of times [dispose] was called on this instance.
  int disposals = 0;

  @override
  Future<void> dispose() async {
    disposals++;
    await super.dispose();
  }
}

// ─── Helpers ────────────────────────────────────────────────────────

/// Pump a minimal app shell wrapping [ReviewScreen]. Games must be seeded
/// *before* calling this function, since ReviewScreen auto-triggers review
/// via didChangeDependencies when ReviewLog.games is non-empty.
Future<void> _pumpReviewApp(
  WidgetTester tester, {
  List<Override> overrides = const <Override>[],
}) async {
  harness.useDesktopSurface(tester, size: const Size(1400, 1000));

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        home: Scaffold(
          body: IndexedStack(
            index: 5, // Reviews tab
            children: const <Widget>[
              SizedBox(),
              SizedBox(),
              SizedBox(),
              SizedBox(),
              SizedBox(),
              ReviewScreen(),
              SizedBox(),
              SizedBox(),
            ],
          ),
        ),
      ),
    ),
  );
  // didChangeDependencies → TabVisibility.visible → _ensureSelected(run:true) →
  // ReviewLog.games non-empty → _selectGame(games.first) → _runReview()
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
}

// ─── Tests ──────────────────────────────────────────────────────────

void main() {
  // ── §10.8 ReviewScreen: navigate away mid-review disposes exactly once ──
  // Pattern: seed game first, then pump with spy factory override. The
  // ReviewScreen auto-triggers review on mount via didChangeDependencies.
  testWidgets(
    '§10.8 ReviewScreen — navigate away mid-review disposes handle exactly once',
    (tester) async {
      final handle = _SpyHandle();

      // Seed game FIRST (before pump — required for auto-trigger path)
      final review = ReviewLog();
      review.record(
        ReviewGame(
          id: 'game-1',
          whiteLabel: 'White Agent',
          blackLabel: 'Black Agent',
          mode: 'standard',
          ucis: const ['e2e4'],
          sans: const ['e4'],
        ),
      );

      // Pump with spy factory — handle created automatically by ReviewScreen
      await _pumpReviewApp(tester, overrides: [
        reviewEvaluatorFactoryProvider.overrideWithValue(() async => handle),
        ...harness.telemetryOverrides(review: review),
      ]);

      expect(handle.disposals, 0); // Handle still active

      // Navigate away by replacing the widget
      await tester.pumpWidget(Container());
      await tester.pump(const Duration(milliseconds: 500));

      // After navigation, the handle should have been disposed exactly once
      expect(handle.disposals, 1);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  // ── §10.8 ReviewScreen: re-run supersedes previous handle ──
  // Pressing "Re-run review" triggers another _runReview(), disposing the prior handle.
  testWidgets(
    '§10.8 ReviewScreen — Re-run review supersedes previous handle exactly once',
    (tester) async {
      final handle = _SpyHandle();

      final review = ReviewLog();
      review.record(
        ReviewGame(
          id: 'rerun-test',
          whiteLabel: 'W',
          blackLabel: 'B',
          mode: 'standard',
          ucis: const ['e2e4'],
          sans: const ['e4'],
        ),
      );

      await _pumpReviewApp(tester, overrides: [
        reviewEvaluatorFactoryProvider.overrideWithValue(() async => handle),
        ...harness.telemetryOverrides(review: review),
      ]);

      expect(handle.disposals, 0); // Handle active from initial review

      // Press "Re-run review" — triggers _runReview() which disposes previous
      // and creates a new handle (factory called again).
      await tester.tap(find.textContaining('Re-run review'));
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      // The old handle was disposed exactly once during the supersedence
      expect(handle.disposals, 1);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  // ── §10.8 VariantReplayScreen: dispose during async review ──
  testWidgets(
    '§10.8 VariantReplayScreen — dispose during async review disposes handle exactly once',
    (tester) async {
      final handle = _SpyHandle();

      harness.useDesktopSurface(tester, size: const Size(1400, 1000));

      final record = _buildVariantGame();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            reviewEvaluatorFactoryProvider.overrideWithValue(() async => handle),
          ],
          child: MaterialApp(
            home: Scaffold(body: VariantReplayScreen(record: record)),
          ),
        ),
      );
      await tester.pump();

      // Start analysis
      await tester.tap(find.text('Analyze'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(handle.disposals, 0); // Just created

      // Replace immediately — triggers dispose in screen's dispose method
      await tester.pumpWidget(Container());
      await tester.pump(const Duration(milliseconds: 500));

      expect(handle.disposals, 1); // Exactly one disposal
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  // ── §10.8 ReviewScreen: stale completion guard prevents extra disposal ──
  testWidgets(
    '§10.8 ReviewScreen — stale completion guard disposes but no exception',
    (tester) async {
      final handle = _SpyHandle();

      final review = ReviewLog();
      review.record(
        ReviewGame(
          id: 'stale-game',
          whiteLabel: 'W',
          blackLabel: 'B',
          mode: 'standard',
          ucis: const ['e2e4'],
          sans: const ['e4'],
        ),
      );

      await _pumpReviewApp(tester, overrides: [
        reviewEvaluatorFactoryProvider.overrideWithValue(() async => handle),
        ...harness.telemetryOverrides(review: review),
      ]);

      expect(handle.disposals, 0); // Still active

      // Replace widget mid-review — token increment invalidates future resolution
      await tester.pumpWidget(Container());
      await tester.pump(const Duration(milliseconds: 100));

      // Wait for any pending resolution to complete
      await tester.pump(const Duration(milliseconds: 500));

      // Handle should be disposed exactly once
      expect(handle.disposals, 1);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  // ── §10.8 SpyHandle: basic property verification ──
  testWidgets('§10.8 SpyHandle constructs with correct properties',
      (tester) async {
    final spy = _SpyHandle();
    expect(spy.resolvedSource, EngineSources.heuristic);
    expect(spy.isFallback, isTrue);
    expect(spy.fallbackReason, '');
    expect(spy.evaluator, isA<HeuristicEvaluator>());
    expect(spy.disposals, 0);
    await spy.dispose();
    expect(spy.disposals, 1);
    // Verify dispose increments on repeated calls
    await spy.dispose();
    expect(spy.disposals, 2);
  }, timeout: const Timeout(Duration(seconds: 10)));

  // ── §10.8 ReviewScreen: single navigate-away disposes handle exactly once ──
  testWidgets(
    '§10.8 ReviewScreen — single navigate-away disposes handle exactly once',
    (tester) async {
      final handle = _SpyHandle();

      final review = ReviewLog();
      review.record(
        ReviewGame(
          id: 'nav-test',
          whiteLabel: 'W',
          blackLabel: 'B',
          mode: 'standard',
          ucis: const ['e2e4'],
          sans: const ['e4'],
        ),
      );

      await _pumpReviewApp(tester, overrides: [
        reviewEvaluatorFactoryProvider.overrideWithValue(() async => handle),
        ...harness.telemetryOverrides(review: review),
      ]);

      // Navigate away
      await tester.pumpWidget(Container());
      await tester.pump(const Duration(milliseconds: 500));

      // Each transition chain disposes at most once
      expect(handle.disposals, 1);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  // ── §10.8 VariantReplayScreen: dispose without running review ──
  testWidgets(
    '§10.8 VariantReplayScreen — dispose without starting analysis causes no crash',
    (tester) async {
      final handle = _SpyHandle();

      harness.useDesktopSurface(tester, size: const Size(1400, 1000));

      final record = _buildVariantGame();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            reviewEvaluatorFactoryProvider.overrideWithValue(() async => handle),
          ],
          child: MaterialApp(
            home: Scaffold(body: VariantReplayScreen(record: record)),
          ),
        ),
      );
      await tester.pump();

      // Don't start analysis — just dispose the widget
      await tester.pumpWidget(Container());
      await tester.pump(const Duration(milliseconds: 500));

      // No exception — key invariant verified
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  // ── §10.8 VariantReplayScreen: sequential analyses each dispose properly ──
  testWidgets(
    '§10.8 VariantReplayScreen — second Analyze disposes first handle exactly once',
    (tester) async {
      final handles = [_SpyHandle(), _SpyHandle()];
      var idx = 0;

      harness.useDesktopSurface(tester, size: const Size(1400, 1000));

      final record = _buildVariantGame();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            reviewEvaluatorFactoryProvider.overrideWithValue(() async => handles[idx++ % 2]),
          ],
          child: MaterialApp(
            home: Scaffold(body: VariantReplayScreen(record: record)),
          ),
        ),
      );
      await tester.pump();

      // First analysis
      await tester.tap(find.text('Analyze'));
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      expect(handles[0].disposals, 0); // Still active

      // Second analysis — should dispose the first
      await tester.tap(find.textContaining('Re-analyze'));
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      expect(handles[0].disposals, 1); // First disposed once

      // Verify second is now active
      expect(handles[1].disposals, 0);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

// ─── Fixture builders ───────────────────────────────────────────────

/// Construct a minimal VariantGameRecord for testing.
VariantGameRecord _buildVariantGame() {
  final initialBoard = VariantBoard.fromStandard(Position.initial());
  const legalAttempt = AttemptedMove(
    fromSquareName: 'e2',
    toSquareName: 'e4',
    phrase: 'Opening',
  );
  final interpreted = ChaoticRules.interpret(initialBoard, legalAttempt, seed: 1);
  final afterLegal = interpreted.selected.resultingBoard;

  return VariantGameRecord(
    id: 'dispose-audit-game',
    whiteLabel: 'White',
    blackLabel: 'Black',
    seed: 42,
    initialBoard: initialBoard,
    plies: [_buildPlyRecord(
      index: 0,
      before: initialBoard,
      after: afterLegal,
      attempt: legalAttempt,
      interpreted: interpreted,
    )],
    outcome: '*',
    reason: 'test',
    startedAt: DateTime.utc(2026),
  );
}

VariantPlyRecord _buildPlyRecord({
  required int index,
  required VariantBoard before,
  required VariantBoard after,
  required AttemptedMove attempt,
  required InterpretedResult interpreted,
}) {
  final mover = before.sideToMove;
  final uci = '${attempt.fromSquareName}${attempt.toSquareName}${attempt.promotion ?? ''}';
  return VariantPlyRecord(
    ply: index,
    mover: mover.isWhite ? 'w' : 'b',
    agentId: 'agent-spy',
    modelKey: 'spy-mock',
    seed: 10 + index,
    fallback: false,
    attempt: VariantAttemptRecord(
      uci: uci,
      fromSquareName: attempt.fromSquareName,
      toSquareName: attempt.toSquareName,
      promotion: attempt.promotion,
      phrase: attempt.phrase,
      rawToolArgsJson:
          '{"from":"${attempt.fromSquareName}","to":"${attempt.toSquareName}"}',
      rawToolCallJson: <String, Object?>{
        'from': attempt.fromSquareName,
        'to': attempt.toSquareName,
      },
    ),
    wasLegal: interpreted.wasLegal,
    standardDetail: interpreted.standardDetail,
    interpretationKind:
        VariantInterpretationKind.fromStrategyId(interpreted.selected.strategyId),
    selected: VariantInterpretationRecord.fromCandidate(interpreted.selected),
    candidates: interpreted.candidates.map(VariantInterpretationRecord.fromCandidate).toList(),
    events: interpreted.events,
    boardAfter: after,
    kingFacts: VariantKingFacts.between(before, after, mover),
    boardHashBefore: before.boardHash(),
    boardHashAfter: after.boardHash(),
    policy: interpreted.policy,
  );
}
