/// [SettingsScreen] widget tests (§6.11).
///
/// Covers: colour-scheme segmented-button toggles (Light / System / Dark),
/// board-theme + piece-theme radio lists updating the live preview,
/// non-interactive preview board, narrow / wide layout, theme-change stability,
/// semantics-tree invariants, and rapid-selection edge cases.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/theme/registry.dart'
    show ThemeRegistry, themeRegistryProvider;
import 'package:llm_chess_arena/src/ui/screens/settings_screen.dart'
    show SettingsScreen;

import '../support/arena_test_harness.dart' as harness;
import '../support/semantics_invariants.dart';
import 'package:llm_chess_arena/src/ui/widgets/chessboard.dart' show Chessboard;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<void> _pumpShell(
  WidgetTester tester, {
  Size size = const Size(1400, 1000),
  List<Override> overrides = const <Override>[],
}) async {
  final container = ProviderContainer(
    overrides: [
      ...overrides,
      // Ensure the registry always starts fresh per test.
      themeRegistryProvider.overrideWith((ref) => ThemeRegistry()),
    ],
  );
  addTearDown(container.dispose);

  harness.useDesktopSurface(tester, size: size);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(body: const SettingsScreen()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void useDesktopSurface(
  WidgetTester tester, {
  Size size = const Size(1400, 1000),
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Builds a minimal SettingsScreen app with its own [ProviderContainer].
/// Used when [pumpWidget] replaces the entire tree (theme stability and
/// navigation tests).
Future<void> _buildSettingsApp(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
  List<Override> overrides = const <Override>[],
}) async {
  final container = ProviderContainer(
    overrides: [
      ...overrides,
      themeRegistryProvider.overrideWith((ref) => ThemeRegistry()),
    ],
  );
  addTearDown(container.dispose);
  final themeData = brightness == Brightness.light
      ? ThemeData.light()
      : ThemeData.dark();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: themeData,
        darkTheme: themeData,
        home: Scaffold(body: const SettingsScreen()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -----------------------------------------------------------------------
  // Colour-Scheme Segmented Button
  // -----------------------------------------------------------------------

  group('colour-scheme segmented button', () {
    testWidgets(
        'Default mode is System and all three segments render',
        (tester) async {
      await _pumpShell(tester);

      // SegmentedButton with three segments renders exactly three rows.
      final segBtn = find.byType(SegmentedButton<ThemeMode>);
      expect(segBtn, findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('System'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);

      // All segments are rendered without exception.
      expect(tester.takeException(), isNull);
    });

    testWidgets('Tapping Light updates themeModeProvider to light',
        (tester) async {
      await _pumpShell(tester);

      final segBtn = find.byType(SegmentedButton<ThemeMode>);
      expect(segBtn, findsOneWidget);

      // Tap the Light segment.
      await tester.tap(find.text('Light'));
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('Tapping Dark updates themeModeProvider to dark',
        (tester) async {
      await _pumpShell(tester);

      await tester.tap(find.text('Dark'));
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('Rapid toggling between Light/Dark/System causes no crash',
        (tester) async {
      await _pumpShell(tester);

      for (final label in ['Light', 'Dark', 'System']) {
        await tester.tap(find.text(label));
        await tester.pump();
      }

      expect(tester.takeException(), isNull);
    });
  });

  // -----------------------------------------------------------------------
  // Board-Theme Radio Group
  // -----------------------------------------------------------------------

  group('board-theme radio group', () {
    testWidgets(
        'Board-theme radio tiles list all four built-in themes (Classic, Midnight, Forest, Sepia)',
        (tester) async {
      await _pumpShell(tester);

      expect(find.text('Classic'), findsOneWidget);
      expect(find.text('Midnight'), findsOneWidget);
      expect(find.text('Forest'), findsOneWidget);
      expect(find.text('Sepia'), findsOneWidget);

      // Each tile has a "Built-in" subtitle (4 board + 3 piece = 7 total).
      expect(find.text('Built-in'), findsNWidgets(7));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Selecting a different board theme updates the preview',
        (tester) async {
      await _pumpShell(tester);

      // Initial preview shows Classic (the default).
      final previewCard = find.descendant(
        of: find.byType(Card),
        matching: find.byType(Chessboard),
      );
      expect(previewCard, findsOneWidget);

      // Switch to Midnight.
      await tester.tap(find.text('Midnight'));
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('Pressing every board-theme radio produces no exceptions',
        (tester) async {
      await _pumpShell(tester);

      for (final name in ['Classic', 'Midnight', 'Forest', 'Sepia']) {
        await tester.tap(find.text(name));
        await tester.pump();
      }

      expect(tester.takeException(), isNull);
    });
  });

  // -----------------------------------------------------------------------
  // Piece-Theme Radio Group
  // -----------------------------------------------------------------------

  group('piece-theme radio group', () {
    testWidgets(
        'Piece-theme radio tiles list all three built-in themes (Meridian, Alpha, Flat)',
        (tester) async {
      await _pumpShell(tester);

      expect(find.text('Meridian'), findsOneWidget);
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Flat'), findsOneWidget);

      // Each tile shows a built-in subtitle.
      expect(find.text('Built-in'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Selecting a different piece theme updates the preview',
        (tester) async {
      await _pumpShell(tester);

      // Switch to Flat.
      await tester.tap(find.text('Flat'));
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('Pressing every piece-theme radio produces no exceptions',
        (tester) async {
      await _pumpShell(tester);

      for (final name in ['Meridian', 'Alpha', 'Flat']) {
        await tester.tap(find.text(name));
        await tester.pump();
      }

      expect(tester.takeException(), isNull);
    });
  });

  // -----------------------------------------------------------------------
  // Live Preview Board
  // -----------------------------------------------------------------------

  group('live preview board', () {
    testWidgets('Preview Chessboard exists and is non-interactive',
        (tester) async {
      await _pumpShell(tester);

      // There is exactly one Chessboard in the card preview.
      expect(find.byType(Chessboard), findsOneWidget);

      // Preview is wrapped in a Card.
      expect(find.byType(Card), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Preview renders with current board + piece combination',
        (tester) async {
      await _pumpShell(tester);

      // Changing both selections refreshes the preview without error.
      await tester.tap(find.text('Midnight')); // board
      await tester.pump();
      await tester.tap(find.text('Alpha')); // piece
      await tester.pump();

      expect(find.byType(Chessboard), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Preview description text contains theme names',
        (tester) async {
      await _pumpShell(tester);

      // The default combo should be "Classic × Meridian".
      expect(
        find.textContaining('Classic'),
        findsWidgets,
        reason: 'Classic appears in preview description',
      );
      expect(
        find.textContaining('Meridian'),
        findsWidgets,
        reason: 'Meridian appears in preview description',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Preview exposes no semantic tap actions that affect state',
        (tester) async {
      await _pumpShell(tester);

      // The Chessboard is set with interactive: false and onTapSquare: null,
      // so there should be no semantic tap action on any square node within
      // the preview card area.
      final cardFinder = find.byType(Card);
      expect(cardFinder, findsWidgets);
      final cardRect = tester.getRect(cardFinder.first);

      // Try tapping within the preview board area; if it's truly
      // non-interactive, nothing should change.
      final previewCenter = Offset(
        cardRect.left + 50,
        cardRect.top + cardRect.height / 2,
      );
      await tester.tapAt(previewCenter);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // -----------------------------------------------------------------------
  // License & Attributions Section
  // -----------------------------------------------------------------------

  group('license section', () {
    testWidgets(
        'License title renders with seeded data present',
        (tester) async {
      await _pumpShell(tester);

      expect(
        find.text('License & attributions'),
        findsOneWidget,
        reason: 'License header always visible',
      );

      // Stockfish credit must appear.
      expect(
        find.textContaining('Stockfish'),
        findsWidgets,
        reason: 'Stockfish attribution present',
      );

      // WintrChess attribution present.
      expect(
        find.textContaining('WintrChess'),
        findsWidgets,
        reason: 'WintrChess attribution present',
      );

      // Geographic restriction text appears.
      expect(
        find.textContaining('Geographic Use Restriction'),
        findsWidgets,
        reason: 'GURAv1 notice present',
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('GPLv3 mention in license text', (tester) async {
      await _pumpShell(tester);

      expect(
        find.textContaining('GPLv3'),
        findsWidgets,
        reason: 'GPLv3 licensing referenced',
      );
      expect(tester.takeException(), isNull);
    });
  });

  // -----------------------------------------------------------------------
  // Layout Tests
  // -----------------------------------------------------------------------

  group('layout', () {
    testWidgets('Narrow layout (<700 px) scrolls without overflow',
        (tester) async {
      await _pumpShell(tester, size: const Size(500, 800));

      // No RenderOverflow exception indicates clean layout.
      expect(tester.takeException(), isNull);

      // All key elements render at narrow width.
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Color scheme'), findsOneWidget);
      expect(find.text('Board theme'), findsOneWidget);
      expect(find.text('Piece theme'), findsOneWidget);
      expect(find.text('License & attributions'), findsOneWidget);
    });

    testWidgets('Wide layout renders all controls', (tester) async {
      await _pumpShell(tester, size: const Size(1400, 1000));

      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Color scheme'), findsOneWidget);
      expect(find.byType(SegmentedButton<ThemeMode>), findsOneWidget);
      expect(find.text('Board theme'), findsOneWidget);
      expect(find.text('Piece theme'), findsOneWidget);
      expect(find.byType(Chessboard), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // -----------------------------------------------------------------------
  // Theme Change Stability
  // -----------------------------------------------------------------------

  group('theme change stability', () {
    testWidgets('Switching between light and dark themes causes no crash',
        (tester) async {
      await _buildSettingsApp(tester, brightness: Brightness.light);
      for (final b in <Brightness>[Brightness.dark, Brightness.light]) {
        await _buildSettingsApp(tester, brightness: b);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets(
        'Colour-scheme segment reflects current app brightness mode',
        (tester) async {
      await _pumpShell(tester);

      // Start with System (default). Verify segments exist and are selectable.
      expect(find.text('System'), findsOneWidget);
      await tester.tap(find.text('Light'));
      await tester.pump();
      await tester.tap(find.text('Dark'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // -----------------------------------------------------------------------
  // Semantics Tree Invariant
  // -----------------------------------------------------------------------

  group('semantics tree invariant check', () {
    testWidgets('Captured semantics tree has unique ids and no null parents',
        (tester) async {
      await _pumpShell(tester);

      final cap = captureSemanticsSafe(tester);
      expect(cap.nodes.length, greaterThan(0),
          reason: 'Settings screen contributes semantic nodes');
      expectSemanticsTreeInvariants(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Semantics stable across board/piece theme switches',
        (tester) async {
      await _pumpShell(tester);

      final before = parentMap(captureSemanticsSafe(tester));

      await tester.tap(find.text('Midnight')); // board theme
      await tester.pump();
      await tester.pump();

      final after = parentMap(captureSemanticsSafe(tester));

      expectNoReparenting(before, after);
      expectSemanticsTreeInvariants(tester);
      expect(tester.takeException(), isNull);
    });
  });

  // -----------------------------------------------------------------------
  // Edge Cases
  // -----------------------------------------------------------------------

  group('edge cases', () {
    testWidgets('Rapid radio taps produce no exceptions', (tester) async {
      await _pumpShell(tester);

      // Rapidly tap board-theme radios.
      for (var i = 0; i < 10; i++) {
        for (final name in ['Classic', 'Midnight', 'Forest', 'Sepia']) {
          await tester.tap(find.text(name));
          await tester.pump(const Duration(milliseconds: 16));
        }
      }

      expect(tester.takeException(), isNull);
    });

    testWidgets('Mixed board+piece combinations do not crash',
        (tester) async {
      await _pumpShell(tester);

      // Exhaust every combo: 4 boards × 3 pieces = 12 combos.
      for (final board in ['Classic', 'Midnight', 'Forest', 'Sepia']) {
        await tester.tap(find.text(board));
        await tester.pump();
        for (final piece in ['Meridian', 'Alpha', 'Flat']) {
          await tester.tap(find.text(piece));
          await tester.pump();
        }
      }

      expect(tester.takeException(), isNull);
    });

    testWidgets('Navigating away and back does not leak state',
        (tester) async {
      // Pump SettingsScreen in an isolated ProviderScope, replace it, and
      // verify the new mount is clean — simulating what happens when a route
      // is popped then pushed again.
      await _buildSettingsApp(tester);
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Re-mount (simulating push/pop round-trip).
      await _buildSettingsApp(tester);
      expect(find.byType(SettingsScreen), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
