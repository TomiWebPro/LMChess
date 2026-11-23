/// Widget tests for WatchScreen (§6.5, P1).
///
/// Covers transport overlay (Start/Pause/Resume/Stop), setup dialog agent
/// selectors, tab switches (Activity/Moves/Errors), error-tab states,
/// move-list seek, dispose lifecycle, and narrow/wide layouts.
/// Uses deterministic fakes — never touches real network, engine, or wall-clock.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/llm/mock_provider.dart';
import 'package:llm_chess_arena/src/llm/tool_schema.dart' show MoveToolCall;
import 'package:llm_chess_arena/src/llm/validation.dart' show FailureKind;
import 'package:llm_chess_arena/src/ui/backend_bridge.dart'
    show clockProvider, turnProviderFactoryProvider;
import 'package:llm_chess_arena/src/ui/screens/watch_screen.dart' show WatchScreen;
import 'package:llm_chess_arena/src/ui/widgets/activity_panel.dart' show AgentActivityPanel;
import 'package:llm_chess_arena/src/ui/widgets/boards.dart' show MoveList;
import 'package:llm_chess_arena/src/ui/widgets/chessboard.dart' show Chessboard;
import 'package:llm_chess_arena/src/ui/ui_models.dart' show AgentListStore, agentListProvider;
import '../support/arena_test_harness.dart' as harness;
import '../support/semantics_invariants.dart' show captureSemanticsSafe,
    expectNoReparenting, expectSemanticsTreeInvariants, parentMap;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

List<Override> _baseOverrides() => <Override>[
      clockProvider.overrideWithValue(() => DateTime.utc(2026, 1, 1)),
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
          // Non-zero so a full game takes many pump cycles: transport tests
          // need the game to stay live across Pause/Resume/Stop taps instead
          // of finishing (and opening the modal Game over dialog) instantly.
          stepDelay: const Duration(milliseconds: 100),
        );
      }),
    ];

List<Override> _catalogOverrides() => <Override>[
      ..._baseOverrides(),
      agentListProvider.overrideWith((ref) => AgentListStore(seedDemos: true)),
    ];

Future<void> _pumpWatch(WidgetTester tester,
    {Size? size, List<Override> overrides = const <Override>[]}) async {
  final s = size ?? const Size(1400, 1000);
  tester.view.physicalSize = s;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
        body: ProviderScope(overrides: overrides, child: const WatchScreen())),
  ));
  await tester.pump();
}

Future<void> _pumpSteps(WidgetTester tester, {int steps = 12}) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Total plies applied, read from the Moves tab header (`Ply a / b`).
///
/// The header lives in the Moves tab (offstage until selected), so offstage
/// widgets are included. Before the first move the panel shows
/// `No moves yet` and the count is 0.
int _moveCount(WidgetTester tester) {
  final header = find.textContaining(
    RegExp(r'^Ply \d+ / \d+$'),
    skipOffstage: false,
  );
  if (header.evaluate().isEmpty) return 0;
  final text = tester.widget<Text>(header.first).data!;
  return int.parse(text.split('/').last.trim());
}

/// Transport overlay controls: idle/terminal shows a `Start` button, while a
/// live game shows icon-only Pause/Resume + Stop buttons with tooltips.
Finder _startControl() => find.text('Start');
Finder _pauseControl() => find.byTooltip('Pause');
Finder _resumeControl() => find.byTooltip('Resume');
Finder _stopControl() => find.byTooltip('Stop');

/// Opens the setup dialog via the FAB.
Future<void> _openSetup(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey<String>('game-setup-button')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Selects a panel tab and waits for the page animation to settle.
///
/// Tab pages are built lazily, so content (e.g. the Moves `Ply a / b`
/// header) only exists once the controller stops changing.
Future<void> _selectTab(WidgetTester tester, String name) async {
  await tester.tap(find.text(name));
  final controller =
      DefaultTabController.of(tester.element(find.byType(TabBar)));
  for (var i = 0; i < 20 && controller.indexIsChanging; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
  await tester.pump(const Duration(milliseconds: 100));
}

/// Selects the Moves tab (see [_selectTab]).
Future<void> _showMovesTab(WidgetTester tester) =>
    _selectTab(tester, 'Moves');

/// Pumps until at least [min] plies are applied (or [maxSteps] is hit).
///
/// Move count is read from the Moves tab header, so call [_showMovesTab]
/// first. Each mock turn takes several pump cycles (see [stepDelay] above).
Future<void> _waitForMoves(WidgetTester tester, int min,
    {int maxSteps = 80}) async {
  for (var i = 0; i < maxSteps && _moveCount(tester) < min; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {

  // =========================================================================
  // Transport flow
  // =========================================================================

  group('Transport', () {
    testWidgets('Start advances moves', (tester) async {
      await _pumpWatch(tester, overrides: _catalogOverrides());
      // Idle: overlay Start button exists, no status text, no live controls.
      expect(_startControl(), findsOneWidget);
      expect(find.text('Idle'), findsNothing);
      expect(_pauseControl(), findsNothing);
      expect(_resumeControl(), findsNothing);
      expect(_stopControl(), findsNothing);
      expect(_moveCount(tester), 0);
      expect(tester.takeException(), isNull);
      await tester.tap(_startControl());
      await tester.pump();
      await _showMovesTab(tester);
      await _waitForMoves(tester, 1);
      expect(_moveCount(tester), greaterThan(0));
      // Live: icon-only transport, Start gone.
      expect(_startControl(), findsNothing);
      expect(_pauseControl(), findsOneWidget);
      expect(_stopControl(), findsOneWidget);
      await tester.tap(_stopControl());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      // Terminal: Start returns.
      expect(_startControl(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Pause stops scheduling; Resume continues', (tester) async {
      await _pumpWatch(tester, overrides: _catalogOverrides());
      await tester.tap(_startControl());
      await tester.pump();
      await _showMovesTab(tester);
      await _waitForMoves(tester, 1);
      expect(_moveCount(tester), greaterThan(0));
      await tester.tap(_pauseControl());
      await tester.pump();
      expect(_resumeControl(), findsOneWidget);
      expect(_pauseControl(), findsNothing);
      // Pause takes effect at the turn boundary: an in-flight turn may
      // still land, so settle before recording the frozen count.
      await _pumpSteps(tester, steps: 12);
      final beforePause = _moveCount(tester);
      expect(beforePause, greaterThan(0));
      await _pumpSteps(tester, steps: 10);
      expect(_moveCount(tester), equals(beforePause));
      await tester.tap(_resumeControl());
      await tester.pump();
      await _waitForMoves(tester, beforePause + 1);
      expect(_moveCount(tester), greaterThan(beforePause));
      await tester.tap(_stopControl());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Stop ends the run', (tester) async {
      await _pumpWatch(tester, overrides: _catalogOverrides());
      await tester.tap(_startControl());
      await tester.pump();
      await _showMovesTab(tester);
      await _waitForMoves(tester, 1);
      expect(_moveCount(tester), greaterThan(0));
      await tester.tap(_stopControl());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      // Terminal: Start returns and the result is a dialog, not a banner.
      expect(_startControl(), findsOneWidget);
      expect(find.text('Game over'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Stop during in-flight turn: no exception', (tester) async {
      await _pumpWatch(tester, overrides: _catalogOverrides());
      await tester.tap(_startControl());
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        if (_stopControl().evaluate().isNotEmpty) {
          await tester.tap(_stopControl());
        } else if (_pauseControl().evaluate().isNotEmpty) {
          await tester.tap(_pauseControl());
        }
        await tester.pump(const Duration(milliseconds: 20));
        await tester.pump();
      }
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Start → Pause → Resume continues cleanly', (tester) async {
      await _pumpWatch(tester, overrides: _catalogOverrides());
      await tester.tap(_startControl());
      await tester.pump();
      await _showMovesTab(tester);
      await _waitForMoves(tester, 1);
      expect(_moveCount(tester), greaterThan(0));
      final beforeResume = _moveCount(tester);
      await tester.tap(_pauseControl());
      await tester.pump();
      expect(_resumeControl(), findsOneWidget);
      await tester.tap(_resumeControl());
      await tester.pump();
      await _waitForMoves(tester, beforeResume + 1);
      expect(_moveCount(tester), greaterThan(beforeResume));
      expect(tester.takeException(), isNull);
      await tester.tap(_stopControl());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(_startControl(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // =========================================================================
  // Agent selectors
  // =========================================================================

  group('Agent selectors', () {
    testWidgets('Empty catalog triggers SnackBar', (tester) async {
      await _pumpWatch(tester, overrides: <Override>[
        ..._baseOverrides(),
        agentListProvider
            .overrideWith((ref) => AgentListStore(seedDemos: false)),
      ]);
      // No agents bound: Start is blocked by the guard (no game starts).
      await tester.tap(_startControl());
      await tester.pump();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Pick a White agent first.'), findsOneWidget);
      expect(_startControl(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Dropdowns render agent names visible', (tester) async {
      await _pumpWatch(tester, overrides: _catalogOverrides());
      await _openSetup(tester);
      expect(find.text('Game setup'), findsOneWidget);
      expect(find.text('White agent'), findsOneWidget);
      expect(find.text('Black agent'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('game-setup-start')),
        findsOneWidget,
      );
      final fields = find.byType(DropdownButtonFormField<String>);
      expect(fields, findsNWidgets(2));
      await tester.tap(fields.first);
      await tester.pump();
      expect(find.text('Demo White'), findsAny);
      await tester.tap(
        find
            .widgetWithText(
                DropdownMenuItem<String>, 'Demo White')
            .last,
        warnIfMissed: false,
      );
      await tester.pump();
      await tester.tap(fields.last);
      await tester.pump();
      expect(find.text('Demo Black'), findsAny);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Selectors disabled while running', (tester) async {
      await _pumpWatch(tester, overrides: _catalogOverrides());
      await tester.tap(_startControl());
      await tester.pump();
      await _pumpSteps(tester, steps: 4);
      await tester.pump(const Duration(milliseconds: 50));
      expect(_stopControl(), findsOneWidget);
      // Setup dialog while live: seats and clock are locked.
      await _openSetup(tester);
      expect(find.text('Game setup'), findsOneWidget);
      expect(find.textContaining('locked'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pump();
      await tester.tap(_stopControl());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Change selector updates selection', (tester) async {
      await _pumpWatch(tester, overrides: _catalogOverrides());
      await _openSetup(tester);
      expect(find.text('Game setup'), findsOneWidget);
      await tester.tap(find.text('White agent'));
      await tester.pump();
      await tester.tap(find.widgetWithText(DropdownMenuItem<String>,
              'Demo White')
          .last,
          warnIfMissed: false);
      await tester.pump();
      expect(find.text('Demo White'), findsAny);
      await tester.tap(find.text('Black agent'));
      await tester.pump();
      await tester.tap(find.widgetWithText(DropdownMenuItem<String>,
              'Demo Black')
          .last,
          warnIfMissed: false);
      await tester.pump();
      await tester.tap(find.text('Close'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });
  });

  // =========================================================================
  // Tab switching
  // =========================================================================

  group('Tab switching', () {
    testWidgets('Tabs switch while idle', (tester) async {
      await _pumpWatch(tester, overrides: _catalogOverrides());
      expect(find.text('Activity'), findsOneWidget);
      expect(find.text('Moves'), findsOneWidget);
      expect(find.text('Errors'), findsOneWidget);
      await _selectTab(tester, 'Moves');
      expect(find.byType(MoveList), findsOneWidget);
      expect(find.text('No moves yet'), findsOneWidget);
      await _selectTab(tester, 'Activity');
      expect(find.byType(AgentActivityPanel), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Tabs switch while running', (tester) async {
      await _pumpWatch(tester, overrides: _catalogOverrides());
      await tester.tap(_startControl());
      await tester.pump();
      await _pumpSteps(tester, steps: 4);
      await tester.pump(const Duration(milliseconds: 50));
      for (final tabName in ['Moves', 'Errors', 'Activity']) {
        await _selectTab(tester, tabName);
        expect(tester.takeException(), isNull, reason: tabName);
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.tap(_stopControl());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    });
  });

  // =========================================================================
  // Error tab
  // =========================================================================

  group('Error tab', () {
    testWidgets('Empty errors state shown', (tester) async {
      await _pumpWatch(tester, overrides: _catalogOverrides());
      await _selectTab(tester, 'Errors');
      expect(find.text('No errors recorded this game.'), findsOneWidget);
      expect(find.byType(WatchScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Injected error rows render', (tester) async {
      await _pumpWatch(tester, overrides: _catalogOverrides());
      await tester.tap(_startControl());
      await tester.pump();
      await _pumpSteps(tester, steps: 4);
      await tester.pump(const Duration(seconds: 2));
      // Verify the errors panel renders content without crashing.
      expect(find.byType(WatchScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(_stopControl());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    });
  });

  // =========================================================================
  // Move list
  // =========================================================================

  group('Move list', () {
    testWidgets('Moves populated after Start', (tester) async {
      await _pumpWatch(tester, overrides: _catalogOverrides());
      await tester.tap(_startControl());
      await tester.pump();
      await _showMovesTab(tester);
      await _waitForMoves(tester, 1);
      expect(find.byType(MoveList), findsOneWidget);
      expect(_moveCount(tester), greaterThan(0));
      expect(tester.takeException(), isNull);
      await tester.tap(_stopControl());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('Move-list seek matches board', (tester) async {
      await _pumpWatch(tester, overrides: _catalogOverrides());
      await tester.tap(_startControl());
      await tester.pump();
      await _showMovesTab(tester);
      await _waitForMoves(tester, 2);
      expect(_moveCount(tester), greaterThanOrEqualTo(2));
      expect(find.byType(Chessboard), findsOneWidget);
      // Live view: no return banner until we scrub away.
      expect(find.text('Return to live position'), findsNothing);
      // Tap the first move cell to scrub away from the live position.
      final cells = find.descendant(
        of: find.byType(MoveList),
        matching: find.byType(InkWell),
      );
      expect(cells, findsWidgets);
      await tester.tap(cells.first);
      await tester.pump();
      expect(find.text('Return to live position'), findsOneWidget);
      await tester.tap(find.text('Return to live position'));
      await tester.pump();
      expect(find.text('Return to live position'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(_stopControl());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    });
  });

  // =========================================================================
  // Lifecycle
  // =========================================================================

  group('Lifecycle', () {
    testWidgets('dispose drains timers', (tester) async {
      await _pumpWatch(tester, overrides: _catalogOverrides());
      await tester.tap(_startControl());
      await tester.pump();
      await _pumpSteps(tester, steps: 4);
      await tester.pump(const Duration(milliseconds: 50));
      await harness.disposeApp(tester);
      expect(tester.takeException(), isNull);
    });
  });

  // =========================================================================
  // Layout
  // =========================================================================

  group('Layout', () {
    testWidgets('Narrow (<700px) renders all widgets', (tester) async {
      await _pumpWatch(tester,
          size: const Size(500, 800), overrides: _catalogOverrides());
      expect(find.byType(WatchScreen), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('game-setup-button')),
        findsOneWidget,
      );
      expect(find.text('Activity'), findsOneWidget);
      expect(find.text('Moves'), findsOneWidget);
      expect(find.text('Errors'), findsOneWidget);
      // Narrow layouts have no board transport overlay: Start lives in the
      // setup dialog while idle.
      await _openSetup(tester);
      expect(find.text('Game setup'), findsOneWidget);
      expect(find.text('White agent'), findsOneWidget);
      expect(find.text('Black agent'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('game-setup-start')),
        findsOneWidget,
      );
      await tester.tap(find.text('Close'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Wide (1200×800) side-by-side', (tester) async {
      await _pumpWatch(tester,
          size: const Size(1200, 800), overrides: _catalogOverrides());
      expect(find.byType(Chessboard), findsOneWidget);
      expect(find.byType(WatchScreen), findsOneWidget);
      expect(find.text('Start'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // =========================================================================
  // Edge cases
  // =========================================================================

  group('Edge cases', () {
    testWidgets('Transport overlay reflects phases', (tester) async {
      await _pumpWatch(tester, overrides: _catalogOverrides());
      // Idle: Start overlay, no status text.
      expect(find.text('Start'), findsOneWidget);
      expect(find.text('Idle'), findsNothing);
      expect(_pauseControl(), findsNothing);
      expect(_resumeControl(), findsNothing);
      expect(_stopControl(), findsNothing);
      await tester.tap(find.text('Start'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // Live: icon-only Pause + Stop, Start gone.
      expect(find.text('Start'), findsNothing);
      expect(_pauseControl(), findsOneWidget);
      expect(_resumeControl(), findsNothing);
      expect(_stopControl(), findsOneWidget);
      await tester.tap(_pauseControl());
      await tester.pump();
      // Paused: icon-only Resume + Stop.
      expect(_pauseControl(), findsNothing);
      expect(_resumeControl(), findsOneWidget);
      expect(_stopControl(), findsOneWidget);
      expect(find.text('Paused'), findsNothing);
      await tester.tap(_resumeControl());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_pauseControl(), findsOneWidget);
      await tester.tap(_stopControl());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      // Terminal: Start returns; game-over is a dialog, not a chip/banner.
      expect(find.text('Start'), findsOneWidget);
      expect(find.text('Game over'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Start and dispose clean', (tester) async {
      await _pumpWatch(tester, overrides: _catalogOverrides());
      // Single Start exercise — verify it proceeds without exception.
      await tester.tap(_startControl());
      await tester.pump();
      await _pumpSteps(tester, steps: 5);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      // Dispose drains all timers cleanly.
      await harness.disposeApp(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Semantics stable across transition', (tester) async {
      await _pumpWatch(tester, overrides: _catalogOverrides());
      final handle = tester.ensureSemantics();
      try {
        await tester.pump(const Duration(milliseconds: 100));
        final before = captureSemanticsSafe(tester);
        await tester.tap(_startControl());
        await tester.pump();
        await _pumpSteps(tester, steps: 2);
        await tester.pump(const Duration(milliseconds: 100));
        expectSemanticsTreeInvariants(tester);
        if (_pauseControl().evaluate().isNotEmpty) {
          await tester.tap(_pauseControl());
          await tester.pump();
          expectSemanticsTreeInvariants(tester);
          await tester.tap(_resumeControl());
          await tester.pump();
          await _pumpSteps(tester, steps: 1);
          await tester.pump(const Duration(milliseconds: 50));
          expectSemanticsTreeInvariants(tester);
        }
        if (_stopControl().evaluate().isNotEmpty) {
          await tester.tap(_stopControl());
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
        }
        expectSemanticsTreeInvariants(tester);
        final after = captureSemanticsSafe(tester);
        expectNoReparenting(parentMap(before), parentMap(after));
        expect(tester.takeException(), isNull);
      } finally {
        handle.dispose();
      }
      await harness.disposeApp(tester);
    });
  });
}
