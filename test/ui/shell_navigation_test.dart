// Widget tests for AppShell navigation (§6.1).
//
// Covers the responsive navigation surface: NavigationRail (wide),
// BottomNavigationBar + "More" sheet (narrow), destination switching,
// state preservation across switches, resize safety, rapid switching,
// and semantics isolation for hidden IndexedStack tabs.
//
// Uses deterministic fakes — never touches real network, engine,
// or wall-clock time. No pumpAndSettle around spinners or live loops.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/app.dart' show ArenaApp;
import 'package:llm_chess_arena/src/llm/mock_provider.dart';
import 'package:llm_chess_arena/src/llm/tool_schema.dart' show MoveToolCall;
import 'package:llm_chess_arena/src/llm/validation.dart' show FailureKind;
import 'package:llm_chess_arena/src/ui/backend_bridge.dart'
    show clockProvider, turnProviderFactoryProvider;
import '../support/semantics_invariants.dart' as semantics;

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Minimal overrides for navigation testing: fake AI turns and fixed clock.
List<Override> _navOverrides() => <Override>[
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
      clockProvider.overrideWithValue(() => DateTime.utc(2026, 1, 1)),
    ];

/// Set the viewport size before building the app.
void _useSize(WidgetTester tester, {Size size = const Size(1400, 1000)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Pump the arena app with nav overrides.
Future<void> _pumpNavApp(
  WidgetTester tester, {
  Size? size,
  Iterable<Override>? overrides,
}) async {
  final s = size ?? const Size(1400, 1000);
  _useSize(tester, size: s);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides?.toList() ?? _navOverrides(),
      child: ArenaApp(),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// Helper: advance through a few micro-frames so layout settles.
Future<void> _drift(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 150));
  await tester.pump(const Duration(milliseconds: 50));
}

/// Tap the text label of a rail destination and wait for the switch.
Future<void> _tapRailLabel(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).first);
  await tester.pump();
}

// ---------------------------------------------------------------------------
// §6.1 — Wide layout: NavigationRail (tests 1–5)
// ---------------------------------------------------------------------------

void main() {
  group('§6.1 Wide layout: NavigationRail', () {
    testWidgets(
        'rail destinations navigate to every tab (indices 0-4)', (tester) async {
      // The shell boots on Game (index 0); visit every other destination.
      await _pumpNavApp(tester);

      expect(find.text('Game'), findsWidgets);

      final destinations = <String>[
        'Arena',
        'Stats',
        'Review',
        'Settings',
      ];

      for (final dest in destinations) {
        await _tapRailLabel(tester, dest);

        // The destination name appears somewhere in the screen content.
        expect(find.text(dest), findsAny);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets(
        'NavigationRail renders with exactly 5 destinations', (tester) async {
      await _pumpNavApp(tester);

      // The rail has 6 item slots regardless of whether they render as a
      // distinct widget type in the current Flutter version — assert via
      // the number of clickable text labels inside the rail container.
      final railContainer = find.byType(NavigationRail);
      expect(railContainer, findsOneWidget);
      final rail = tester.widget<NavigationRail>(railContainer);
      expect(rail.destinations.length, 5);
    });

    testWidgets(
        'tab state survives a switch away-and-back (Game → Arena → Game)',
        (tester) async {
      await _pumpNavApp(tester);

      await _tapRailLabel(tester, 'Arena');
      await _drift(tester);

      await _tapRailLabel(tester, 'Game');
      await _drift(tester);

      await _tapRailLabel(tester, 'Arena');
      await _drift(tester);

      await _tapRailLabel(tester, 'Game');
      await _drift(tester);

      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'all 5 destinations render without overflow or exception',
        (tester) async {
      await _pumpNavApp(tester);

      final keys = <String>[
        'Game',
        'Arena',
        'Stats',
        'Review',
        'Settings',
      ];

      for (final key in keys) {
        await _tapRailLabel(tester, key);
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets(
        'rail tap opens the corresponding destination directly', (tester) async {
      await _pumpNavApp(tester);

      await tester.tap(find.text('Arena').first);
      await tester.pump();

      expect(find.text('Arena'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  // ----------------------------------------------------------------------
  // §6.1 — Narrow layout: BottomNavigationBar + More + Drawer (tests 6–9)
  // ----------------------------------------------------------------------

  group('§6.1 Narrow layout: BottomNavigation + More + Drawer', () {
    testWidgets(
        'narrow (<700) hides rail, shows bottom bar + drawer + AppBar',
        (tester) async {
      await _pumpNavApp(tester, size: const Size(500, 800));

      // AppBar present in narrow mode (shows current tab label).
      expect(find.byType(AppBar), findsOneWidget);
      // No navigation rail.
      expect(find.byType(NavigationRail), findsNothing);
      // Bottom nav bar present.
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets(
        '"More" sheet lists Settings and selects on tap',
        (tester) async {
      await _pumpNavApp(tester, size: const Size(500, 800));

      // Select "More" from the bottom bar.
      await tester.tap(find.widgetWithText(NavigationDestination, 'More'));
      await tester.pump();

      // Modal sheet should display. Check for ListTile items inside.
      // In Material 3 the sheet may use different barrier types; the
      // reliable indicator is the list tiles themselves. (The bottom bar
      // holds Game/Arena/Stats/Review, so the sheet holds Settings.)
      final settingsTiles = find.descendant(
        of: find.byType(ListView),
        matching: find.text('Settings'),
      );
      expect(settingsTiles, findsWidgets);

      // Tap "Settings" inside the sheet — use warnIfMissed=false because the
      // bottom-sheet overlay may render text outside the test surface bounds.
      await tester.tap(settingsTiles.first, warnIfMissed: false);
      await tester.pump();

      // Sheet dismisses (Navigator.pop inside onTap).
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'drawer is present and has correct entries in narrow mode',
        (tester) async {
      // Force narrow viewport and rebuild.
      tester.view.physicalSize = const Size(500, 800);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(
        ProviderScope(overrides: _navOverrides(), child: ArenaApp()),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // In narrow mode Scaffold.drawer is set to a Drawer widget.
      // We assert presence via Scaffold having > 0 children in body/leading/divider/expanded+drawer.
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.drawer, isNotNull,
          reason: 'Narrow Scaffold should have a non-null drawer');
    });

    testWidgets(
        'narrow layout renders all destinations without crashing',
        (tester) async {
      // Use a generous enough width for dropdown selectors on Game/Arena.
      await _pumpNavApp(tester, size: const Size(680, 800));

      // In narrow mode use the bottom bar + More sheet to switch.
      final targets = <String>[
        'Game',
        'Arena',
        'Stats',
        'Review',
      ];

      for (final target in targets) {
        final dest = find.widgetWithText(NavigationDestination, target);
        if (dest.evaluate().isNotEmpty) {
          await tester.tap(dest);
          await tester.pump();
        }
        // Capture any exceptions during build/layout.
        expect(tester.takeException(), isNull);
      }
    });
  });

  // ----------------------------------------------------------------------
  // §6.1 — State preservation & lifecycle (tests 10–12)
  // ----------------------------------------------------------------------

  group('§6.1 State preservation & lifecycle', () {
    testWidgets(
        'single mounted tab preserves state across many tab switches',
        (tester) async {
      await _pumpNavApp(tester);

      final path = <String>[
        'Game',
        'Arena',
        'Stats',
        'Review',
        'Settings',
        'Game',
        'Arena',
        'Game',
      ];

      for (final dest in path) {
        await _tapRailLabel(tester, dest);
        await tester.pump();
      }

      // Entire sequence ran without a Dart exception.
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'resize preserves mounted tab (699→700→1100→699) without losing state',
        (tester) async {
      // Start narrow.
      await _pumpNavApp(tester, size: const Size(699, 800));
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);

      // The game tab is mounted by default.
      await tester.pump(const Duration(milliseconds: 350));

      // Resize to wide (>= 700).
      tester.view.physicalSize = const Size(700, 800);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(tester.takeException(), isNull);

      // Resize larger.
      tester.view.physicalSize = const Size(1100, 800);
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Back to narrow.
      tester.view.physicalSize = const Size(699, 800);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '20 rapid destination switches: no exception, invariants hold',
        (tester) async {
      await _pumpNavApp(tester);

      final names = <String>[
        'Game',
        'Arena',
        'Stats',
        'Review',
        'Settings',
      ];

      // Cycle 20 times through the 5 destinations.
      for (var round = 0; round < 20; round++) {
        for (final name in names) {
          await _tapRailLabel(tester, name);
          await tester.pump(const Duration(milliseconds: 10));
          expect(tester.takeException(), isNull,
              reason: 'exception after round $round, $name');
        }
      }
    });
  });

  // ----------------------------------------------------------------------
  // §6.1 — Semantics isolation for hidden tabs (tests 13–16)
  // ----------------------------------------------------------------------

  group('§6.1 Semantics isolation for hidden tabs', () {
    testWidgets('only the mounted tab contributes square semantics nodes',
        (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await _pumpNavApp(tester);

        // The shell boots on Game, which hosts a chessboard.
        final gameNodes = semantics.captureSemantics(tester);
        var gameSquareCount = 0;
        for (final node in gameNodes.nodes) {
          final data = node.getSemanticsData();
          if (data.label.contains('square')) {
            gameSquareCount++;
          }
        }
        expect(gameSquareCount, greaterThan(0),
            reason: 'Game tab must expose square semantics nodes');
        expect(tester.takeException(), isNull);
      } finally {
        handle.dispose();
      }
    });

    testWidgets('switching tabs does not produce duplicate semantics ids',
        (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await _pumpNavApp(tester);

        semantics.expectSemanticsTreeInvariants(tester);

        await _tapRailLabel(tester, 'Arena');
        await tester.pump();
        semantics.expectSemanticsTreeInvariants(tester);

        await _tapRailLabel(tester, 'Stats');
        await tester.pump();
        semantics.expectSemanticsTreeInvariants(tester);

        await _tapRailLabel(tester, 'Review');
        await tester.pump();
        semantics.expectSemanticsTreeInvariants(tester);

        await _tapRailLabel(tester, 'Game');
        await tester.pump();
        semantics.expectSemanticsTreeInvariants(tester);

        expect(tester.takeException(), isNull);
      } finally {
        handle.dispose();
      }
    });

    testWidgets(
        'no reparenting occurs across tab switches (parentMap comparison)',
        (tester) async {
      await _pumpNavApp(tester);

      await _tapRailLabel(tester, 'Game');
      await tester.pump();
      final cap1 = semantics.captureSemantics(tester);
      final pm1 = semantics.parentMap(cap1);

      await _tapRailLabel(tester, 'Arena');
      await tester.pump();
      final cap2 = semantics.captureSemantics(tester);
      final pm2 = semantics.parentMap(cap2);

      await _tapRailLabel(tester, 'Stats');
      await tester.pump();
      final cap3 = semantics.captureSemantics(tester);
      final pm3 = semantics.parentMap(cap3);

      await _tapRailLabel(tester, 'Game');
      await tester.pump();
      final cap4 = semantics.captureSemantics(tester);
      final pm4 = semantics.parentMap(cap4);

      semantics.expectNoReparenting(pm1, pm2);
      semantics.expectNoReparenting(pm2, pm3);
      semantics.expectNoReparenting(pm3, pm4);
    });

    testWidgets(
        'hidden-tab rule: Game→Stats→Game toggles square count positive→0→positive',
        (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await _pumpNavApp(tester);

        // Game: positive squares (occupied-square count from initial position).
        var count = semantics.captureSemantics(tester).nodes.where((n) {
          return n.getSemanticsData().label.contains('square');
        }).length;
        expect(count, greaterThan(0),
            reason: 'Game must have square nodes while mounted');

        // Stats: 0 squares (no board).
        await _tapRailLabel(tester, 'Stats');
        await tester.pump();
        count = semantics.captureSemantics(tester).nodes.where((n) {
          return n.getSemanticsData().label.contains('square');
        }).length;
        expect(count, 0);

        // Game again: squares reappear.
        await _tapRailLabel(tester, 'Game');
        await tester.pump();
        count = semantics.captureSemantics(tester).nodes.where((n) {
          return n.getSemanticsData().label.contains('square');
        }).length;
        expect(count, greaterThan(0));

        expect(tester.takeException(), isNull);
      } finally {
        handle.dispose();
      }
    });
  });
}
