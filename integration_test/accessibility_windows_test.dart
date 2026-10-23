/// Integration-level smoke test for the Windows accessibility bridge.
///
/// Exercises the full app shell through all 8 destinations, opens/closes
/// dialogs and sheets that produce semantics churn, and performs rapid
/// Play/Watch switches. Every step asserts no Dart exception and checks
/// expected anchor labels — a fast proxy for AXTree health before the
/// native UIA smoke tool/windows_accessibility_smoke.ps1 runs.
///
/// Spec: docs/FUTURE_WORK.md section 9.1
///
/// The suite is widget-level and platform-agnostic: it runs natively on
/// Windows (`flutter test integration_test/accessibility_windows_test.dart
/// -d windows`, §9.1) and is gated headless on the ubuntu-gate Linux CI job
/// (§11.11). Deterministic fakes only — no real engine/network/wall-clock.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart'
    show IntegrationTestWidgetsFlutterBinding;
import 'package:llm_chess_arena/src/app.dart' show ArenaApp;
import 'package:llm_chess_arena/src/ui/backend_bridge.dart'
    show clockProvider, turnProviderFactoryProvider;
import 'package:llm_chess_arena/src/llm/mock_provider.dart';
import 'package:llm_chess_arena/src/llm/tool_schema.dart' show MoveToolCall;
import 'package:llm_chess_arena/src/llm/validation.dart' show FailureKind;

/// Shell destination semantics label for each index (matches the rail /
/// bottom bar / More-sheet labels in `lib/src/app.dart`).
String _destinationLabel(int index) {
  switch (index) {
    case 0: return 'Home';
    case 1: return 'Play';
    case 2: return 'Watch';
    case 3: return 'Arena';
    case 4: return 'Stats'; // shell label; the screen body says "Statistics".
    case 5: return 'Review';
    case 6: return 'Agents';
    case 7: return 'Settings';
    default: return '';
  }
}

/// Screen-specific anchor text that exists after navigating to each
/// destination (not a duplicate of the rail/sheet label, so the check proves
/// the selected screen's body rendered, not just the nav chrome).
String _anchorText(int index) {
  switch (index) {
    case 0: return 'LLM Chess Arena'; // Home hero heading
    case 1: return 'AI Opponent'; // Play player card label
    case 2: return 'White agent'; // Watch agent selector label
    case 3: return 'Autumn Invitational'; // Arena default name
    case 4: return 'No stats yet'; // Stats empty state
    case 5: return 'No standard games recorded yet'; // Review empty state
    case 6: return 'agents'; // Agents catalog count ("2 agents")
    case 7: return 'Appearance'; // Settings screen heading
    default: return '';
  }
}

/// Override all production seams so widget tests stay deterministic:
/// turn provider returns a legal UCI move immediately (no network/engine),
/// clock is fixed UTC (deterministic game IDs).
List<Override> _fakeOverrides() => <Override>[
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

/// Pump the app with deterministic overrides and return the semantics handle.
///
/// The caller MUST dispose the returned handle in a `finally` block (the
/// repo's `captureSemanticsSafe` pattern) — `addTearDown` runs after
/// flutter_test's `_verifySemanticsHandlesWereDisposed`, so it would leak.
Future<SemanticsHandle> _pumpApp(
  WidgetTester tester, {
  Size size = const Size(1400, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: _fakeOverrides(),
      child: const ArenaApp(),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));

  // The live integration binding does not build the semantics tree unless a
  // client (or the test harness) requests it. Without this, every
  // `find.bySemanticsLabel` below returns zero and the destination taps
  // silently no-op — exactly how this suite rotted unexecuted (§11.11).
  final semanticsHandle = tester.ensureSemantics();
  await tester.pump();
  return semanticsHandle;
}

/// Tap a shell destination by its rail/bar/More-sheet label.
///
/// Prefers tapping the real semantics node (matches the Windows UIA surface,
/// where an accessibility client enables per-node semantics). On headless
/// Linux the live integration binding does not attach per-render-object
/// `debugSemantics` (labels live on merged ancestors), so
/// `find.bySemanticsLabel` yields nothing — fall back to the text label of
/// the same widget (the repo's widget suites tap this way; `.first` picks the
/// rail/bar item ahead of any same-text Home card in tree order).
Future<void> _tapDestination(WidgetTester tester, String label) async {
  final semantics = find.bySemanticsLabel(label, skipOffstage: false);
  if (semantics.evaluate().isNotEmpty) {
    await tester.tap(semantics.first, warnIfMissed: false);
  } else {
    await tester.tap(find.text(label).first, warnIfMissed: false);
  }
  await tester.pump(const Duration(milliseconds: 100));
}

/// The "More" modal bottom sheet (scoped by type — hidden IndexedStack tabs
/// can contain other ListViews, so a ListView finder cannot be trusted).
final Finder _sheetItems = find.byType(BottomSheet);

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('accessibility_windows', () {
    // -- Step 1: launch app --
    testWidgets('app launches without exception', (tester) async {
      final semantics = await _pumpApp(tester);
      try {
        expect(find.textContaining('LLM Chess Arena'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'app launch');
      } finally {
        semantics.dispose();
      }
    });

    // -- Step 2: visit all 8 destinations --
    testWidgets(
        'all 8 destinations render without exception', (tester) async {
      final semantics = await _pumpApp(tester);
      try {
        // Tap each rail destination in wide layout
        for (var i = 0; i <= 7; i++) {
          await _tapDestination(tester, _destinationLabel(i));
          expect(tester.takeException(), isNull,
              reason: 'navigated to ${_destinationLabel(i)}');
        }
      } finally {
        semantics.dispose();
      }
    });

    // -- Step 3: open/close More sheet --
    testWidgets('More sheet can be opened and dismissed', (tester) async {
      final semantics = await _pumpApp(tester, size: const Size(500, 800));
      try {
        // Open More sheet
        expect(find.text('More'), findsOneWidget);
        await tester.tap(find.text('More'));
        await tester.pump(const Duration(milliseconds: 300));

        // Verify sheet items are present (scoped to the sheet — the Home tab
        // behind the modal still has same-text cards for Stats/Review/Agents/
        // Settings).
        for (final label in <String>[
          'Stats',
          'Review',
          'Agents',
          'Settings',
        ]) {
          expect(
            find.descendant(of: _sheetItems.first, matching: find.text(label)),
            findsOneWidget,
            reason: 'More sheet lists "$label"',
          );
        }

        // Dismiss by tapping outside (barrier) or going to Home
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason: 'More sheet dismiss');
      } finally {
        semantics.dispose();
      }
    });

    // -- Step 4: Settings navigate + back --
    testWidgets('Settings screen navigable and back-stable', (tester) async {
      final semantics = await _pumpApp(tester, size: const Size(500, 800));
      try {
        await tester.tap(find.text('More'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(
          find
              .descendant(
                  of: _sheetItems.first, matching: find.text('Settings'))
              .first,
        );
        await tester.pumpAndSettle();

        // Settings body rendered (not just the rail/AppBar label).
        expect(find.text('Appearance'), findsOneWidget);

        // Navigate away and back — the shell tab must survive the round-trip.
        await _tapDestination(tester, 'Home');
        await tester.pumpAndSettle();
        expect(find.textContaining('LLM Chess Arena'), findsOneWidget);

        await tester.tap(find.text('More'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(
          find
              .descendant(
                  of: _sheetItems.first, matching: find.text('Settings'))
              .first,
        );
        await tester.pumpAndSettle();
        expect(find.text('Appearance'), findsOneWidget);

        expect(tester.takeException(), isNull,
            reason: 'Settings navigation');
      } finally {
        semantics.dispose();
      }
    });

    // -- Step 5: 20 rapid Play/Watch switches --
    testWidgets('20 rapid Play/Watch switches zero exceptions',
        (tester) async {
      final semantics = await _pumpApp(tester);
      try {
        for (var i = 0; i < 20; i++) {
          await _tapDestination(tester, i % 2 == 0 ? 'Play' : 'Watch');
          expect(
            tester.takeException(),
            isNull,
            reason: 'rapid switch #$i ${i % 2 == 0 ? 'Play' : 'Watch'}',
          );
        }
      } finally {
        semantics.dispose();
      }
    });

    // -- Step 6: every destination shows its anchor label --
    testWidgets('every destination shows its anchor label', (tester) async {
      final semantics = await _pumpApp(tester);
      try {
        for (var i = 0; i <= 7; i++) {
          // Reset to home first
          await _tapDestination(tester, 'Home');
          await tester.pumpAndSettle();

          // Navigate to destination using the rail
          if (i > 0) {
            await _tapDestination(tester, _destinationLabel(i));
            await tester.pumpAndSettle();
          }

          await tester.pump(const Duration(milliseconds: 100));
          // The anchor text must appear somewhere on screen
          expect(
            find.textContaining(_anchorText(i)),
            findsOneWidget,
            reason: '$i: should find "${_anchorText(i)}"',
          );
          expect(
            tester.takeException(),
            isNull,
            reason: 'anchor check for ${_anchorText(i)}',
          );
        }
      } finally {
        semantics.dispose();
      }
    });

    // -- Step 7: theme toggle stability --
    testWidgets('theme changes stable light dark system', (tester) async {
      final semantics = await _pumpApp(tester);
      try {
        expect(find.textContaining('LLM Chess Arena'), findsOneWidget);

        // Go to Settings
        await _tapDestination(tester, 'Settings');
        await tester.pumpAndSettle();

        // Toggle to dark mode
        expect(find.text('Dark'), findsOneWidget);
        await tester.tap(find.text('Dark'));
        await tester.pumpAndSettle();

        // Toggle to system mode
        expect(find.text('System'), findsOneWidget);
        await tester.tap(find.text('System'));
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'theme toggle chain',
        );
      } finally {
        semantics.dispose();
      }
    });

    // -- Step 8: resize across breakpoints --
    testWidgets('resize 699 to 700 to 1100 to 699 zero exceptions',
        (tester) async {
      final semantics = await _pumpApp(tester, size: const Size(699, 800));
      try {
        tester.view.physicalSize = const Size(700, 800);
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'resize 699 to 700',
        );

        tester.view.physicalSize = const Size(1100, 800);
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'resize 700 to 1100',
        );

        tester.view.physicalSize = const Size(699, 800);
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'resize 1100 to 699',
        );
      } finally {
        semantics.dispose();
      }
    });

    // -- Step 9: round-trip Home → Play → Watch → Home --
    testWidgets('round-trip Home Play Watch Home stack clean', (tester) async {
      final semantics = await _pumpApp(tester);
      try {
        await _tapDestination(tester, 'Play');
        await tester.pumpAndSettle();
        expect(find.textContaining('AI Opponent'), findsWidgets);

        await _tapDestination(tester, 'Watch');
        await tester.pumpAndSettle();

        await _tapDestination(tester, 'Home');
        await tester.pumpAndSettle();
        expect(
          find.textContaining('LLM Chess Arena'),
          findsOneWidget,
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'round-trip Home-Play-Watch-Home',
        );
      } finally {
        semantics.dispose();
      }
    });

    // -- Step 10: agents form push/pop --
    testWidgets('Agents form renders without exception', (tester) async {
      final semantics = await _pumpApp(tester);
      try {
        await _tapDestination(tester, 'Agents');
        await tester.pumpAndSettle();
        // Catalog count ("2 agents" with the seeded demo store).
        expect(find.textContaining('agents'), findsWidgets);
        expect(
          tester.takeException(),
          isNull,
          reason: 'agents list',
        );
      } finally {
        semantics.dispose();
      }
    });

    // -- Step 11: stats screen rendering --
    testWidgets('Stats screen renders empty state', (tester) async {
      final semantics = await _pumpApp(tester);
      try {
        await _tapDestination(tester, 'Stats');
        await tester.pumpAndSettle();
        expect(find.text('No stats yet'), findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason: 'stats screen',
        );
      } finally {
        semantics.dispose();
      }
    });

    // -- Step 12: review screen rendering --
    testWidgets('Review screen renders empty state', (tester) async {
      final semantics = await _pumpApp(tester);
      try {
        await _tapDestination(tester, 'Review');
        await tester.pumpAndSettle();
        expect(
          find.text('No standard games recorded yet'),
          findsOneWidget,
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'review screen',
        );
      } finally {
        semantics.dispose();
      }
    });
  });
}
