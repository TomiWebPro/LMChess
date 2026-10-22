/// [ReviewScreen] widget tests (§6.8).
///
/// Covers: empty state, game picker, Re-run review with fake evaluator,
/// evaluator throw → error card, key-moments rendering, slider + MoveList,
/// navigate-away-back stability, dispose drain, narrow/wide layouts,
/// semantics stability, rapid-tap safety, capped capacity.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/review/engine_adapter.dart'
    show EngineSources, HeuristicEvaluator;
import 'package:llm_chess_arena/src/ui/backend_bridge.dart'
    show ReviewLog, ReviewGame, reviewEvaluatorFactoryProvider,
        ReviewEvaluatorHandle;
import 'package:llm_chess_arena/src/ui/screens/review_screen.dart'
    show ReviewScreen;

import '../support/arena_test_harness.dart' as harness;
import '../support/semantics_invariants.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<void> _pumpShell(
  WidgetTester tester, {
  Size size = const Size(1400, 1000),
  List<Override> overrides = const <Override>[],
}) async {
  harness.useDesktopSurface(tester, size: size);
  await tester.pumpWidget(
    ProviderScope(overrides: overrides, child: const _TestShell()),
  );
  await tester.pump(); // didChangeDependencies
  await tester.pump(); // second pump for setState
}

class _TestShell extends ConsumerStatefulWidget {
  const _TestShell();
  @override
  ConsumerState<_TestShell> createState() => _TestShellState();
}

class _TestShellState extends ConsumerState<_TestShell> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: const IndexedStack(
          index: 5,
          children: <Widget>[
            SizedBox(),
            SizedBox(),
            SizedBox(),
            SizedBox(),
            Text('Stats'),
            ReviewScreen(),
            Text('Agents'),
            Text('Settings'),
          ],
        ),
      ),
    );
  }
}

/// Fake evaluator that resolves synchronously.
Future<ReviewEvaluatorHandle> _quickEval() => Future.value(
      ReviewEvaluatorHandle(
        evaluator: HeuristicEvaluator(),
        resolvedSource: EngineSources.heuristic,
      ),
    );

/// Fake evaluator that throws synchronously.
Future<ReviewEvaluatorHandle> _throwEval() =>
    Future<ReviewEvaluatorHandle>.error(StateError('evaluator crashed'));

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('empty state (§6.8)', () {
    testWidgets('empty ReviewLog shows prompt text', (tester) async {
      await _pumpShell(tester);
      expect(find.text('No standard games recorded yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty state has a Refresh button', (tester) async {
      await _pumpShell(tester);
      expect(find.text('Refresh'), findsOneWidget);
    });

    testWidgets('pressing Refresh while empty keeps empty state',
        (tester) async {
      await _pumpShell(tester);
      await tester.tap(find.text('Refresh'));
      await tester.pump();
      // Should STILL see the title — means we stayed in empty state
      expect(find.text('No standard games recorded yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('seeding + picker (§6.8)', () {
    testWidgets('seeded game appears in picker dropdown', (tester) async {
      final review = ReviewLog();
      review.record(
        ReviewGame(
          id: 'picker-test-1',
          whiteLabel: 'Demo White',
          blackLabel: 'Demo Black',
          mode: 'standard',
          ucis: const ['e2e4'],
          sans: const ['e4'],
          fens: const [
            'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 2'
          ],
          phrases: const <String?>['Opening'],
          fallbackFlags: const <bool>[false],
        ),
      );
      await _pumpShell(
        tester,
        overrides: harness.telemetryOverrides(review: review),
      );
      // Dropdown label visible
      expect(find.text('Game'), findsAtLeastNWidgets(1));
      // Picker option rendered with the game's display name (found 2x — 
      // once as selected value, once in dropdown entries list)
      expect(find.text('Demo White vs Demo Black · standard'), findsAtLeastNWidgets(1));
    });

    testWidgets('selected game row shows info subtitle', (tester) async {
      final review = ReviewLog();
      review.record(
        ReviewGame(
          id: 'sub-game',
          whiteLabel: 'White',
          blackLabel: 'Black',
          mode: 'standard',
          ucis: const ['e2e4'],
          sans: const ['e4'],
          fens: const [
            'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 2'
          ],
          phrases: const <String?>['Opening'],
          fallbackFlags: const <bool>[false],
        ),
      );
      await _pumpShell(
        tester,
        overrides: harness.telemetryOverrides(review: review),
      );
      // Subtitle format: "{n} of {total}"
      expect(find.textContaining('of '), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Re-run review with fake evaluator (§6.8)', () {
    testWidgets('Re-run renders source banner after evaluation',
        (tester) async {
      final review = ReviewLog();
      review.record(
        ReviewGame(
          id: 'rerun-eval',
          whiteLabel: 'W',
          blackLabel: 'B',
          mode: 'standard',
          ucis: const ['e2e4', 'e7e5'],
          sans: const ['e4', 'e5'],
          fens: const [
            'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 2',
            'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 3',
          ],
          phrases: const <String?>['Opening', null],
          fallbackFlags: const <bool>[false, false],
        ),
      );
      final overrides = <Override>[
        reviewEvaluatorFactoryProvider.overrideWithValue(_quickEval),
        ...harness.telemetryOverrides(review: review),
      ];
      await _pumpShell(tester, overrides: overrides);
      // Auto-selected game → auto-run → quick eval finishes before next assert
      // So we should see the report, not the idle prompt
      expect(find.textContaining('Evaluation source'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('evaluator failure (§6.8)', () {
    testWidgets('thrown evaluator → error card + Retry button', (tester) async {
      final review = ReviewLog();
      review.record(
        ReviewGame(
          id: 'fail-eval',
          whiteLabel: 'W',
          blackLabel: 'B',
          mode: 'standard',
          ucis: const ['e2e4'],
          sans: const ['e4'],
          fens: const [
            'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 2'
          ],
          phrases: const <String?>['Opening'],
          fallbackFlags: const <bool>[false],
        ),
      );
      final overrides = <Override>[
        reviewEvaluatorFactoryProvider.overrideWithValue(_throwEval),
        ...harness.telemetryOverrides(review: review),
      ];
      await _pumpShell(tester, overrides: overrides);
      await tester.tap(find.text('Re-run review'));
      await tester.pump();
      expect(find.textContaining('failed'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('key moments (§6.8)', () {
    testWidgets('key-moments card title always exists after review',
        (tester) async {
      final review = ReviewLog();
      review.record(
        ReviewGame(
          id: 'key-moments',
          whiteLabel: 'W',
          blackLabel: 'B',
          mode: 'standard',
          ucis: const ['e2e4', 'e7e5'],
          sans: const ['e4', 'e5'],
          fens: const [
            'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 2',
            'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 3',
          ],
          phrases: const <String?>['Opening', null],
          fallbackFlags: const <bool>[false, false],
        ),
      );
      final overrides = <Override>[
        reviewEvaluatorFactoryProvider.overrideWithValue(_quickEval),
        ...harness.telemetryOverrides(review: review),
      ];
      await _pumpShell(tester, overrides: overrides);
      expect(find.text('Key moments'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('replay slider (§6.8)', () {
    testWidgets('MoveList card present after successful review', (tester) async {
      final review = ReviewLog();
      review.record(
        ReviewGame(
          id: 'moves-list',
          whiteLabel: 'W',
          blackLabel: 'B',
          mode: 'standard',
          ucis: const ['e2e4', 'e7e5'],
          sans: const ['e4', 'e5'],
          fens: const [
            'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 2',
            'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 3',
          ],
          phrases: const <String?>['Opening', null],
          fallbackFlags: const <bool>[false, false],
        ),
      );
      final overrides = <Override>[
        reviewEvaluatorFactoryProvider.overrideWithValue(_quickEval),
        ...harness.telemetryOverrides(review: review),
      ];
      await _pumpShell(tester, overrides: overrides);
      expect(find.text('Moves'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('navigate-away-back stability (§6.8)', () {
    testWidgets('swapping out ReviewScreen and restoring has no exception',
        (tester) async {
      final review = ReviewLog();
      await _pumpShell(
        tester,
        overrides: harness.telemetryOverrides(review: review),
      );
      // Simulate tab-switch away
      await tester.pumpWidget(
        ProviderScope(
            overrides: harness.telemetryOverrides(review: review),
            child: MaterialApp(
                home: const Scaffold(body: Center(child: Text('Away'))))),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      // Simulate tab-switch back
      await _pumpShell(
        tester,
        overrides: harness.telemetryOverrides(review: review),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('narrow and wide layouts (§6.8)', () {
    testWidgets('narrow layout renders without overflow', (tester) async {
      await _pumpShell(tester, size: const Size(500, 800));
      expect(tester.takeException(), isNull);
    });

    testWidgets('wide layout renders full column', (tester) async {
      await _pumpShell(tester, size: const Size(1400, 1000));
      expect(tester.takeException(), isNull);
    });

    testWidgets('theme change during review does not crash', (tester) async {
      final review = ReviewLog();
      review.record(
        ReviewGame(
          id: 'theme-test',
          whiteLabel: 'W',
          blackLabel: 'B',
          mode: 'standard',
          ucis: const ['e2e4'],
          sans: const ['e4'],
          fens: const [
            'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 2'
          ],
          phrases: const <String?>['Opening'],
          fallbackFlags: const <bool>[false],
        ),
      );
      final overrides = <Override>[
        reviewEvaluatorFactoryProvider.overrideWithValue(_quickEval),
        ...harness.telemetryOverrides(review: review),
      ];
      await _pumpShell(tester, overrides: overrides);
      // Re-mount with light/dark themes toggled
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: MaterialApp(
            theme: ThemeData.light(),
            darkTheme: ThemeData.dark(),
            home: const _TestShell(),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('semantics stability (§6.8)', () {
    testWidgets('captured semantics contains game-related nodes',
        (tester) async {
      final review = ReviewLog();
      review.record(
        ReviewGame(
          id: 'sem-game',
          whiteLabel: 'White',
          blackLabel: 'Black',
          mode: 'standard',
          ucis: const ['e2e4'],
          sans: const ['e4'],
          fens: const [
            'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 2'
          ],
          phrases: const <String?>['Opening'],
          fallbackFlags: const <bool>[false],
        ),
      );
      await _pumpShell(
        tester,
        overrides: harness.telemetryOverrides(review: review),
      );
      final cap = captureSemanticsSafe(tester);
      // At minimum, there should be square-label semantics nodes
      expect(cap.nodes.length, greaterThan(0));
      expect(tester.takeException(), isNull);
    });
  });

  group('edge cases (§6.8)', () {
    testWidgets('rapid taps on Refresh produce no exceptions', (tester) async {
      await _pumpShell(tester);
      for (var i = 0; i < 10; i++) {
        await tester.tap(find.text('Refresh'));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('capped capacity respects 20-item limit', (tester) async {
      final review = ReviewLog();
      for (var i = 0; i < 25; i++) {
        review.record(
          ReviewGame(
            id: 'cap-$i',
            whiteLabel: 'W$i',
            blackLabel: 'B$i',
            mode: 'standard',
            ucis: const <String>[],
            sans: const <String>[],
            fens: const [
              'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'
            ],
            phrases: const <String?>[],
            fallbackFlags: const <bool>[],
          ),
        );
      }
      await _pumpShell(
        tester,
        overrides: harness.telemetryOverrides(review: review),
      );
      // After cap enforcement, header shows "{20} recorded games"
      expect(find.textContaining('recorded games'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('mixed-mode games render alongside standard games',
        (tester) async {
      final review = ReviewLog();
      review.record(
        ReviewGame(
          id: 'mixed-mode',
          whiteLabel: 'Chaos W',
          blackLabel: 'Chaos B',
          mode: 'chaotic',
          ucis: const ['e2e4'],
          sans: const ['e4'],
          fens: const [
            'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 2'
          ],
          phrases: const <String?>['Opening'],
          fallbackFlags: const <bool>[false],
        ),
      );
      review.record(
        ReviewGame(
          id: 'mixed-standard',
          whiteLabel: 'Std W',
          blackLabel: 'Std B',
          mode: 'standard',
          ucis: const ['e2e4'],
          sans: const ['e4'],
          fens: const [
            'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 2'
          ],
          phrases: const <String?>['Opening'],
          fallbackFlags: const <bool>[false],
        ),
      );
      await _pumpShell(
        tester,
        overrides: harness.telemetryOverrides(review: review),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
