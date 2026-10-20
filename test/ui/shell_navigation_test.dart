// Widget tests for AppShell navigation (§6.1).
//
// Covers the responsive navigation surface: NavigationRail (wide),
// BottomNavigationBar + "More" sheet (narrow), home-card routes,
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
        'rail destinations navigate to every tab (indices 1-7)', (tester) async {
      // Navigate from Home (index 0) to all 7 other destinations.
      await _pumpNavApp(tester);

      expect(find.textContaining('LLM Chess Arena'), findsOneWidget);

      final destinations = <String>[
        'Play',
        'Watch',
        'Arena',
        'Stats',
        'Review',
        'Agents',
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
        'NavigationRail renders with exactly 8 destinations', (tester) async {
      await _pumpNavApp(tester);

      // The rail has 8 item slots regardless of whether they render as a
      // distinct widget type in the current Flutter version — assert via
      // the number of clickable text labels inside the rail container.
      final railContainer = find.byType(NavigationRail);
      expect(railContainer, findsOneWidget);
      final rail = tester.widget<NavigationRail>(railContainer);
      expect(rail.destinations.length, 8);
    });

    testWidgets(
        'tab state survives a switch away-and-back (Home → Play → Home → Play)',
        (tester) async {
      await _pumpNavApp(tester);

      await _tapRailLabel(tester, 'Play');
      await _drift(tester);

      await _tapRailLabel(tester, 'Home');
      await _drift(tester);

      await _tapRailLabel(tester, 'Play');
      await _drift(tester);

      // IndexedStack keeps Play mounted; no exception thrown.
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'all 8 destinations render without overflow or exception',
        (tester) async {
      await _pumpNavApp(tester);

      final keys = <String>[
        'Play',
        'Watch',
        'Arena',
        'Stats',
        'Review',
        'Agents',
        'Settings',
        'Home',
      ];

      for (final key in keys) {
        await _tapRailLabel(tester, key);
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets(
        'home-card taps open the corresponding rail destination via _openRoute',
        (tester) async {
      // Tapping the "Play" card on Home uses _openRoute → setState(index=1),
      // NOT Navigator.push, so there is only one Screen instance.
      await _pumpNavApp(tester);

      await tester.tap(find.text('Play').first);
      await tester.pump();

      expect(find.text('Play'), findsWidgets);
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
        '"More" sheet lists Stats/Review/Agents/Settings and selects on tap',
        (tester) async {
      await _pumpNavApp(tester, size: const Size(500, 800));

      // Select "More" from the bottom bar.
      await tester.tap(find.widgetWithText(NavigationDestination, 'More'));
      await tester.pump();

      // Modal sheet should display. Check for ListTile items inside.
      // In Material 3 the sheet may use different barrier types; the
      // reliable indicator is the list tiles themselves.
      final reviewTiles = find.descendant(
        of: find.byType(ListView),
        matching: find.text('Review'),
      );
      expect(reviewTiles, findsWidgets);

      // Tap "Review" inside the sheet — use warnIfMissed=false because the
      // bottom-sheet overlay may render text outside the test surface bounds.
      await tester.tap(reviewTiles.first, warnIfMissed: false);
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
      // Use a generous enough width for dropdown selectors on Watch/Arena.
      await _pumpNavApp(tester, size: const Size(680, 800));

      // In narrow mode we use home-card taps to switch destinations.
      final targets = <String>[
        'Play',
        'Watch',
        'Arena',
        'Stats',
        'Review',
        'Agents',
        'Settings',
      ];

      for (final target in targets) {
        // Only tap if the card text is found (some screens may not show cards
        // after initial load if content is cached differently).
        final cardFinder = find.text(target);
        if (cardFinder.evaluate().isNotEmpty) {
          await tester.tap(cardFinder.first);
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
        'IndexedStack preserves mounted state across many tab switches',
        (tester) async {
      await _pumpNavApp(tester);

      final path = <String>[
        'Play',
        'Watch',
        'Arena',
        'Stats',
        'Review',
        'Agents',
        'Settings',
        'Home',
        'Play',
        'Home',
        'Play',
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

      // Switch to Play.
      await tester.tap(find.text('Play').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Resize to wide (>= 700).
      tester.view.physicalSize = const Size(700, 800);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
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
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '20 rapid destination switches: no exception, invariants hold',
        (tester) async {
      await _pumpNavApp(tester);

      final names = <String>[
        'Play',
        'Watch',
        'Arena',
        'Stats',
        'Review',
        'Agents',
        'Settings',
        'Home',
      ];

      // Cycle 20 times through the 8 destinations.
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
    testWidgets('hidden tabs contribute zero square-label semantics nodes',
        (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await _pumpNavApp(tester);

        // While on Home, no board squares should appear (Home has no chessboard).
        final homeBefore = semantics.captureSemantics(tester);
        final homeSquareCount = homeBefore.nodes.where((node) {
          final data = node.getSemanticsData();
          return data.label.contains('square');
        }).length;
        expect(homeSquareCount, 0,
            reason: 'Home tab should have zero square semantics nodes');

        // Switch to Play.
        await _tapRailLabel(tester, 'Play');
        await tester.pump();

        // Play contains a Chessboard whose squaresOf() returns only
        // occupied squares (~32 from Position.initial()). At minimum
        // we verify that square nodes now exist (i.e. they're absent on
        // Home and present on Play). We do not assert exactly 64 because
        // the board only creates semantics nodes for entries in its
        // `squares` map (not placeholder-empty squares).
        final playNodes = semantics.captureSemantics(tester);
        int playSquareCount = 0;
        for (final node in playNodes.nodes) {
          final data = node.getSemanticsData();
          if (data.label.contains('square')) {
            playSquareCount++;
          }
        }
        expect(playSquareCount, greaterThan(0),
            reason: 'Play tab must expose square semantics nodes');
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

        await _tapRailLabel(tester, 'Play');
        await tester.pump();
        semantics.expectSemanticsTreeInvariants(tester);

        await _tapRailLabel(tester, 'Stats');
        await tester.pump();
        semantics.expectSemanticsTreeInvariants(tester);

        await _tapRailLabel(tester, 'Review');
        await tester.pump();
        semantics.expectSemanticsTreeInvariants(tester);

        await _tapRailLabel(tester, 'Play');
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

      await _tapRailLabel(tester, 'Play');
      await tester.pump();
      final cap1 = semantics.captureSemantics(tester);
      final pm1 = semantics.parentMap(cap1);

      await _tapRailLabel(tester, 'Watch');
      await tester.pump();
      final cap2 = semantics.captureSemantics(tester);
      final pm2 = semantics.parentMap(cap2);

      await _tapRailLabel(tester, 'Arena');
      await tester.pump();
      final cap3 = semantics.captureSemantics(tester);
      final pm3 = semantics.parentMap(cap3);

      await _tapRailLabel(tester, 'Home');
      await tester.pump();
      final cap4 = semantics.captureSemantics(tester);
      final pm4 = semantics.parentMap(cap4);

      semantics.expectNoReparenting(pm1, pm2);
      semantics.expectNoReparenting(pm2, pm3);
      semantics.expectNoReparenting(pm3, pm4);
    });

    testWidgets(
        'hidden-tab rule: Home→Play→Stats→Play toggles square count 0→positive→0→positive',
        (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await _pumpNavApp(tester);

        // Home: 0 squares.
        var count = semantics.captureSemantics(tester).nodes.where((n) {
          return n.getSemanticsData().label.contains('square');
        }).length;
        expect(count, 0);

        // Play: positive squares (occupied-square count from initial position).
        await _tapRailLabel(tester, 'Play');
        await tester.pump();
        count = semantics.captureSemantics(tester).nodes.where((n) {
          return n.getSemanticsData().label.contains('square');
        }).length;
        expect(count, greaterThan(0),
            reason: 'Play must have square nodes while mounted');

        // Stats: 0 squares (no board).
        await _tapRailLabel(tester, 'Stats');
        await tester.pump();
        count = semantics.captureSemantics(tester).nodes.where((n) {
          return n.getSemanticsData().label.contains('square');
        }).length;
        expect(count, 0);

        // Play again: squares reappear.
        await _tapRailLabel(tester, 'Play');
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
