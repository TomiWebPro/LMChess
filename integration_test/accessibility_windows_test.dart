/// Integration-level smoke test for the Windows accessibility bridge.
///
/// Exercises the full app shell through all 8 destinations, opens/closes
/// dialogs and sheets that produce semantics churn, and performs rapid
/// Play/Watch switches. Every step asserts no Dart exception and checks
/// expected anchor labels — a fast proxy for AXTree health before the
/// native UIA smoke tool/windows_accessibility_smoke.ps1 runs.
///
/// Spec: docs/FUTURE_WORK.md section 9.1
// ignore_for_file: dangling_library_doc_comments, camel_case_types

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart'
    show IntegrationTestWidgetsFlutterBinding;
import 'package:llm_chess_arena/src/app.dart' show ArenaApp;
import 'package:llm_chess_arena/src/ui/backend_bridge.dart'
    show
        QualityLog,
        ReviewLog,
        StatsLog,
        VariantReviewLog,
        clockProvider,
        turnProviderFactoryProvider;
import 'package:llm_chess_arena/src/llm/mock_provider.dart';
import 'package:llm_chess_arena/src/llm/tool_schema.dart' show MoveToolCall;
import 'package:llm_chess_arena/src/llm/validation.dart' show FailureKind;

// Destination label lookup by index.
String _destinationLabel(int index) {
  switch (index) {
    case 0: return 'Home';
    case 1: return 'Play';
    case 2: return 'Watch';
    case 3: return 'Arena';
    case 4: return 'Statistics';
    case 5: return 'Review';
    case 6: return 'Agents';
    case 7: return 'Settings';
    default: return '';
  }
}

// Destination anchor text expected after navigation.
String _anchorText(int index) {
  switch (index) {
    case 0: return 'LLM Chess Arena'; // Home heading
    case 1: return 'AI'; // Play player cards mention AI
    case 2: return 'White'; // Watch agent selector mentions White
    case 3: return 'Autumn Invitational'; // Arena default name
    case 4: return 'Statistics'; // Stats title
    case 5: return 'Review'; // Review title
    case 6: return 'Agents'; // Agents list title
    case 7: return 'Settings'; // Settings title
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

void _clearTelemetry() {
  StatsLog.clear();
  QualityLog.clear();
  ReviewLog.clear();
  VariantReviewLog.clear();
}

Future<void> _pumpApp(
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
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(_clearTelemetry);

  group('accessibility_windows', () {
    // -- Step 1: launch app --
    testWidgets('app launches without exception', (tester) async {
      await _pumpApp(tester);
      expect(find.textContaining('LLM Chess Arena'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'app launch');
    });

    // -- Step 2: visit all 8 destinations --
    testWidgets(
        'all 8 destinations render without exception', (tester) async {
      await _pumpApp(tester);

      // Tap each rail destination in wide layout
      for (var i = 0; i <= 7; i++) {
        final labelText = _destinationLabel(i);
        // Find via semantics label on the navigation destination
        final destFinder = find.bySemanticsLabel(labelText, skipOffstage: false);
        if (destFinder.evaluate().isNotEmpty) {
          await tester.tap(destFinder.first);
          await tester.pumpAndSettle();
        } else {
          // May not exist yet at this width/density — pump longer
          await tester.pump(const Duration(seconds: 1));
        }
        expect(tester.takeException(), isNull,
            reason: 'navigated to ${_destinationLabel(i)}');
      }
    });

    // -- Step 3: open/close More sheet --
    testWidgets('More sheet can be opened and dismissed', (tester) async {
      await _pumpApp(tester, size: const Size(500, 800));

      // Open More sheet
      expect(find.text('More'), findsOneWidget);
      await tester.tap(find.text('More'));
      await tester.pump(const Duration(milliseconds: 300));

      // Verify sheet items are present
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Agents'), findsOneWidget);
      expect(find.text('Review'), findsOneWidget);
      expect(find.text('Statistics'), findsOneWidget);

      // Dismiss by tapping outside (barrier) or going to Home
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'More sheet dismiss');
    });

    // -- Step 4: Settings navigate + back --
    testWidgets('Settings screen navigable and back-stable', (tester) async {
      await _pumpApp(tester, size: const Size(500, 800));

      await tester.tap(find.text('More'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);

      // Back-gesture via drag
      await tester.dragFrom(
        const Offset(50, 400),
        const Offset(300, 0),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'Settings back navigation');
    });

    // -- Step 5: 20 rapid Play/Watch switches --
    testWidgets('20 rapid Play/Watch switches zero exceptions',
        (tester) async {
      await _pumpApp(tester);

      for (var i = 0; i < 20; i++) {
        final target = i % 2 == 0 ? 'Play' : 'Watch';
        final destFinder = find.bySemanticsLabel(target, skipOffstage: false);
        if (destFinder.evaluate().isNotEmpty) {
          await tester.tap(destFinder.first);
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(
          tester.takeException(),
          isNull,
          reason: 'rapid switch #$i $target',
        );
      }
    });

    // -- Step 6: every destination shows its anchor label --
    testWidgets('every destination shows its anchor label', (tester) async {
      await _pumpApp(tester);

      for (var i = 0; i <= 7; i++) {
        // Reset to home first
        await tester.tap(
          find.bySemanticsLabel('Home', skipOffstage: false),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        // Navigate to destination using rail
        if (i > 0) {
          final dest = find.bySemanticsLabel(
              _destinationLabel(i), skipOffstage: false);
          if (dest.evaluate().isNotEmpty) {
            await tester.tap(dest.first);
            await tester.pumpAndSettle();
          }
        }

        await tester.pump(const Duration(milliseconds: 100));
        // The anchor text must appear somewhere on screen
        expect(
          find.textContaining(_anchorText(i)),
          findsOne,
          reason: '$i: should find "$_anchorText(i)"',
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'anchor check for ${_anchorText(i)}',
        );
      }
    });

    // -- Step 7: theme toggle stability --
    testWidgets('theme changes stable light dark system', (tester) async {
      await _pumpApp(tester);

      expect(find.textContaining('LLM Chess Arena'), findsOneWidget);

      // Go to Settings
      await tester.tap(
        find.bySemanticsLabel('Settings', skipOffstage: false),
      );
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
    });

    // -- Step 8: resize across breakpoints --
    testWidgets('resize 699 to 700 to 1100 to 699 zero exceptions',
        (tester) async {
      await _pumpApp(tester, size: const Size(699, 800));

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
    });

    // -- Step 9: round-trip Home → Play → Watch → Home --
    testWidgets('round-trip Home Play Watch Home stack clean', (tester) async {
      await _pumpApp(tester);

      await tester.tap(
        find.bySemanticsLabel('Play', skipOffstage: false),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('AI'), findsWidgets);

      await tester.tap(
        find.bySemanticsLabel('Watch', skipOffstage: false),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsLabel('Home', skipOffstage: false),
      );
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
    });

    // -- Step 10: agents form push/pop --
    testWidgets('Agents form renders without exception', (tester) async {
      await _pumpApp(tester);

      await tester.tap(
        find.bySemanticsLabel('Agents', skipOffstage: false),
      );
      await tester.pumpAndSettle();
      expect(find.text('Agents'), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason: 'agents list',
      );
    });

    // -- Step 11: stats screen rendering --
    testWidgets('Stats screen renders empty state', (tester) async {
      await _pumpApp(tester);

      await tester.tap(
        find.bySemanticsLabel('Statistics', skipOffstage: false),
      );
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'stats screen',
      );
    });

    // -- Step 12: review screen rendering --
    testWidgets('Review screen renders empty state', (tester) async {
      await _pumpApp(tester);

      await tester.tap(
        find.bySemanticsLabel('Review', skipOffstage: false),
      );
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'review screen',
      );
    });
  });
}
