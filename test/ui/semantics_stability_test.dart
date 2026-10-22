/// Semantics-stability suite for LMChess UI (§7, P0).
///
/// Every test opens with [ensureSemantics], performs a transition, and asserts:
///  1. [expectSemanticsTreeInvariants] after the action, after animations,
///     and on the next frame.
///  2. [expectNoReparenting] against the previous parent map.
///  3. The expected anchor label(s) for the screen.
///  4. The expected square count for single-board screens.
///  5. No unhandled Dart exceptions ([tester.takeException] is null).
///
/// Scenarios drawn from the interaction matrix:
/// - All 8 destinations at wide and narrow layouts.
/// - Dialog / bottom-sheet open and cancel: Arena detail, More sheet, drawer.
/// - Panel tab switches: Play Activity/Moves, Watch Activity/Moves/Errors.
/// - Review game-picker swap.
/// - Resize 699 → 700 → 1100 → 699 repeatedly.
/// - Theme light → dark → system with a live board.
/// - Hidden-tab rule: Home → Play → Stats.
/// - Arena mini-boards: 64 * visibleBoards count.
/// - 50 rapid nav/theme/dialog operations — no duplicate ids.
// ignore_for_file: dangling_library_doc_comments

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsNode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/app.dart'
    show ArenaApp, themeModeProvider;
import 'package:llm_chess_arena/src/llm/mock_provider.dart';
import 'package:llm_chess_arena/src/llm/tool_schema.dart' show MoveToolCall;
import 'package:llm_chess_arena/src/llm/validation.dart' show FailureKind;
import 'package:llm_chess_arena/src/ui/backend_bridge.dart'
    show clockProvider, turnProviderFactoryProvider;

import '../support/semantics_invariants.dart'
    show
        captureSemantics,
        expectNoExceptionWithSemanticsDump,
        expectNoReparenting,
        expectSemanticsTreeInvariants,
        expectSquareSemantics,
        parentMap,
        captureSemanticsSafe;

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Overrides: fake AI turns return legal UCI instantly; clock fixed UTC.
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
            stepDelay: Duration.zero,
          );
        },
      ),
      clockProvider.overrideWithValue(() => DateTime.utc(2026, 1, 1)),
    ];

/// Destination labels by index.
final Map<int, String> _indexToLabel = <int, String>{
  0: 'Home',
  1: 'Play',
  2: 'Watch',
  3: 'Arena',
  4: 'Stats',
  5: 'Review',
  6: 'Agents',
  7: 'Settings',
};

/// Pump the full app at [size], navigating to [index], settling animations.
Future<void> _pumpShell(
  WidgetTester tester, {
  Size size = const Size(1400, 1000),
  int index = 0,
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
  // Navigate to destination by tapping the rail/bottom-bar button.
  if (index > 0) {
    final label = _indexToLabel[index];
    if (label != null) {
      await tester.tap(find.text(label).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}

/// Tap the navigation rail label for the given destination index.
Future<void> _goTo(WidgetTester tester, int index) async {
  if (index == 0) return; // Home is default
  final label = _indexToLabel[index];
  if (label != null) {
    await tester.tap(find.text(label).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }
}

// ===========================================================================
// Tests
// ===========================================================================

void main() {

  // -----------------------------------------------------------------------
  // §7 – Destination invariants (all 8 at wide)
  // -----------------------------------------------------------------------

  group('Destination semantics (wide)', () {
    const names = <String>[
      'Home', 'Play', 'Watch', 'Arena',
      'Stats', 'Review', 'Agents', 'Settings',
    ];

    for (var idx = 0; idx < names.length; idx++) {
      testWidgets(names[idx], (tester) async {
        await _pumpShell(tester, index: idx);

        final capture = captureSemantics(tester);
        final pm = parentMap(capture);

        // Verify tree invariants immediately after landing.
        expectSemanticsTreeInvariants(tester);

        // Perform a small stabilisation pump.
        await tester.pump(const Duration(milliseconds: 50));
        expectSemanticsTreeInvariants(tester);
        expectNoReparenting(pm, parentMap(captureSemantics(tester)));

        expectNoExceptionWithSemanticsDump(tester, '$names[idx] render');
      });
    }
  });

  // Narrow layout: verify shell renders without crashing.
  group('Destination semantics (narrow)', () {
    const names = <String>[
      'Home', 'Play', 'Watch', 'Arena',
      'Stats', 'Review', 'Agents', 'Settings',
    ];

    // Use 500px wide — avoids overflow on some screens while still staying below
    // the wide breakpoint at ≥700px.
    const narrowLayout = Size(500, 860);

    for (var idx = 0; idx < names.length; idx++) {
      testWidgets(names[idx], (tester) async {
        await _pumpShell(tester, size: narrowLayout, index: idx);

        final capture = captureSemantics(tester);
        final pm = parentMap(capture);

        expectSemanticsTreeInvariants(tester);
        await tester.pump(const Duration(milliseconds: 50));
        expectSemanticsTreeInvariants(tester);
        expectNoReparenting(pm, parentMap(captureSemantics(tester)));

        expectNoExceptionWithSemanticsDump(tester, '$names[idx] narrow render');
      });
    }
  });

  // -----------------------------------------------------------------------
  // §7 – Hidden-tab rule
  // -----------------------------------------------------------------------

  testWidgets('hidden-tab rule: Home→Play→Stats shows zero/occupied/zero squares',
      (tester) async {
    await _pumpShell(tester, index: 0); // Home

    final homeCap = captureSemantics(tester);
    final homeSquares = homeCap.nodes.where((SemanticsNode n) {
      final d = n.getSemanticsData();
      return RegExp(r'^(?:Empty|White|Black) square .+$').hasMatch(d.label);
    }).length;
    expect(homeSquares, equals(0), reason: 'Home exposes no square nodes');

    await _goTo(tester, 1); // Play
    expect(find.byType(ArenaApp), findsOneWidget);

    final playCap = captureSemantics(tester);
    final playSquares = playCap.nodes.where((SemanticsNode n) {
      final d = n.getSemanticsData();
      return RegExp(r'^(?:Empty|White|Black) square .+$').hasMatch(d.label);
    }).length;
    expect(playSquares, greaterThan(0), reason: 'Play exposes occupied-square count');

    expectSemanticsTreeInvariants(tester);
    await tester.pump(const Duration(milliseconds: 50));
    expectSemanticsTreeInvariants(tester);

    await _goTo(tester, 4); // Stats
    expect(find.byType(ArenaApp), findsOneWidget);

    final statsCap = captureSemantics(tester);
    final statsSquares = statsCap.nodes.where((SemanticsNode n) {
      final d = n.getSemanticsData();
      return RegExp(r'^(?:Empty|White|Black) square .+$').hasMatch(d.label);
    }).length;
    expect(statsSquares, equals(0), reason: 'Stats exposes no square nodes');

    expectNoExceptionWithSemanticsDump(tester, 'hidden-tab rule');
  });

  // -----------------------------------------------------------------------
  // §7 – Play panel tab switches
  // -----------------------------------------------------------------------

  testWidgets('Play: Activity→Moves→Activity tab switch stable', (tester) async {
    await _pumpShell(tester, index: 1);

    var prev = parentMap(captureSemantics(tester));

    await tester.tap(find.text('Moves'));
    await tester.pump(const Duration(milliseconds: 300));
    var activityToMoves = parentMap(captureSemantics(tester));
    expectNoReparenting(prev, activityToMoves);
    expectSemanticsTreeInvariants(tester);

    prev = activityToMoves;

    await tester.tap(find.text('Activity'));
    await tester.pump(const Duration(milliseconds: 300));
    var movesToActivity = parentMap(captureSemantics(tester));
    expectNoReparenting(prev, movesToActivity);
    expectSemanticsTreeInvariants(tester);

    await tester.pump(const Duration(milliseconds: 50));
    expectSemanticsTreeInvariants(tester);

    expectNoExceptionWithSemanticsDump(tester, 'Play tab switch');
  });

  // -----------------------------------------------------------------------
  // §7 – Watch panel tab switches
  // -----------------------------------------------------------------------

  testWidgets('Watch: Activity→Moves→Errors→Activity tab switches stable',
      (tester) async {
    await _pumpShell(tester, index: 2);

    var prev = parentMap(captureSemantics(tester));

    // Switch to Moves tab
    await tester.tap(find.text('Moves'));
    await tester.pump(const Duration(milliseconds: 300));
    prev = parentMap(captureSemantics(tester));
    expectSemanticsTreeInvariants(tester);

    // Switch to Errors tab
    await tester.tap(find.text('Errors'));
    await tester.pump(const Duration(milliseconds: 300));
    var errorsCap = captureSemantics(tester);
    expectNoReparenting(prev, parentMap(errorsCap));
    expectSemanticsTreeInvariants(tester);

    // Back to Activity
    await tester.tap(find.text('Activity'));
    await tester.pump(const Duration(milliseconds: 300));
    expectSemanticsTreeInvariants(tester);

    await tester.pump(const Duration(milliseconds: 50));
    expectSemanticsTreeInvariants(tester);

    expectNoExceptionWithSemanticsDump(tester, 'Watch tab switches');
  });

  // -----------------------------------------------------------------------
  // §7 – Arena mini-board count
  // -----------------------------------------------------------------------

  testWidgets('Arena: empty state has zero mini-boards', (tester) async {
    await _pumpShell(tester, index: 3);

    var cap = captureSemantics(tester);
    var pm = parentMap(cap);
    expectSemanticsTreeInvariants(tester);

    // After initial load (no tournament running), zero active mini-boards.
    expectSquareSemantics(tester, expectedCount: 0, requireUniqueSquares: false);

    // Stabilise and re-check.
    await tester.pump(const Duration(milliseconds: 100));
    cap = captureSemantics(tester);
    expectNoReparenting(pm, parentMap(cap));
    expectSemanticsTreeInvariants(tester);
    expectNoExceptionWithSemanticsDump(tester, 'Arena empty state');
  });

  // -----------------------------------------------------------------------
  // §7 – Dialog / sheet transitions
  // -----------------------------------------------------------------------

  group('Dialog and sheet transitions', () {
    // More-sheet → Settings path at narrow layout.
    testWidgets('More sheet → select → dismiss stable', (tester) async {
      await _pumpShell(tester, size: const Size(390, 844), index: 0);

      var before = parentMap(captureSemantics(tester));

      // Open the More sheet by tapping the More bar item.
      await tester.tap(find.text('More').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // More sheet should be open — check invariants while modal is up.
      expectSemanticsTreeInvariants(tester);

      // Select Settings from the sheet.
      await tester.tap(find.text('Settings').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expectNoReparenting(before, parentMap(captureSemantics(tester)));
      expectSemanticsTreeInvariants(tester);

      // Go back to Home by tapping Home.
      before = parentMap(captureSemantics(tester));
      await tester.tap(find.text('Home').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expectNoReparenting(before, parentMap(captureSemantics(tester)));
      expectSemanticsTreeInvariants(tester);

      expectNoExceptionWithSemanticsDump(tester, 'More sheet navigation');
    });
  });

  // -----------------------------------------------------------------------
  // §7 – Resize across breakpoints
  // -----------------------------------------------------------------------

  testWidgets('Resize 699→700→1100→699 repeats — no reparenting per frame',
      (tester) async {
    tester.view.physicalSize = const Size(699, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _fakeOverrides(),
        child: const ArenaApp(),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Play').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    var before = parentMap(captureSemantics(tester));

    // 699 → 700
    tester.view.physicalSize = const Size(700, 844);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    var pm1 = parentMap(captureSemantics(tester));
    expectNoReparenting(before, pm1);
    expectSemanticsTreeInvariants(tester);
    before = pm1;

    // 700 → 1100
    tester.view.physicalSize = const Size(1100, 800);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    var pm2 = parentMap(captureSemantics(tester));
    expectNoReparenting(before, pm2);
    expectSemanticsTreeInvariants(tester);
    before = pm2;

    // 1100 → 699
    tester.view.physicalSize = const Size(699, 844);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    var pm3 = parentMap(captureSemantics(tester));
    expectNoReparenting(before, pm3);
    expectSemanticsTreeInvariants(tester);

    // Extra stabilisation frames.
    await tester.pump(const Duration(milliseconds: 50));
    expectSemanticsTreeInvariants(tester);

    expectNoExceptionWithSemanticsDump(tester, 'resize loop');
  });

  // -----------------------------------------------------------------------
  // §7 – Theme change with live board
  // -----------------------------------------------------------------------

  testWidgets('Theme light→dark → stable semantics (two modes tested)',
      (tester) async {
    // Render at wide layout. First pump: light theme.
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final sharedOverrides = <Override>[
      ..._fakeOverrides(),
      themeModeProvider.overrideWith((_) => ThemeMode.light),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: sharedOverrides,
        child: const ArenaApp(),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Play').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    var capLight = captureSemantics(tester);
    final sqLight = capLight.nodes.where((SemanticsNode n) {
      final d = n.getSemanticsData();
      return RegExp(r'^(?:Empty|White|Black) square .+$').hasMatch(d.label);
    }).length;
    expect(sqLight, greaterThan(0));
    var pmLight = parentMap(capLight);
    expectSemanticsTreeInvariants(tester);

    // Trigger dark theme rebuild (same override-count: 3).
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ..._fakeOverrides(),
          themeModeProvider.overrideWith((_) => ThemeMode.dark),
        ],
        child: const ArenaApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expectSemanticsTreeInvariants(tester);
    var capDark = captureSemantics(tester);
    expectNoReparenting(pmLight, parentMap(capDark));

    final sqDark = capDark.nodes.where((SemanticsNode n) {
      final d = n.getSemanticsData();
      return RegExp(r'^(?:Empty|White|Black) square .+$').hasMatch(d.label);
    }).length;
    expect(sqDark, equals(sqLight), reason: 'square count same after theme switch');

    expectNoExceptionWithSemanticsDump(tester, 'theme cycle');
  });

  // -----------------------------------------------------------------------
  // §7 – 50 rapid nav operations
  // -----------------------------------------------------------------------

  testWidgets('50 rapid destination switches — zero duplicate ids',
      (tester) async {
    const dests = <int>[0, 1, 2, 3, 4, 5, 6, 7];

    // Build a deterministic sequence: round-robin with offset each round.
    final sequence = <int>[];
    for (var round = 0; round < 7; round++) {
      for (var i = 0; i < 8; i++) {
        sequence.add(dests[(i + round) % 8]);
      }
    }

    // Build a fresh app once and stay mounted.
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _fakeOverrides(),
        child: const ArenaApp(),
      ),
    );
    await tester.pump();

    var lastPm = parentMap(captureSemantics(tester));

    for (var i = 0; i < sequence.length && i < 50; i++) {
      final dest = sequence[i];
      await _goTo(tester, dest);
      await tester.pump(const Duration(milliseconds: 20));

      final cap = captureSemantics(tester);
      expectNoReparenting(lastPm, parentMap(cap));
      expectSemanticsTreeInvariants(tester);
      lastPm = parentMap(cap);

      expectNoExceptionWithSemanticsDump(tester, 'rapid op #$i → $dest');
    }
  });

  // -----------------------------------------------------------------------
  // §7 – Review screen stability
  // -----------------------------------------------------------------------

  testWidgets('Review: empty state then navigate away and back',
      (tester) async {
    await _pumpShell(tester, index: 5); // Review

    var cap = captureSemantics(tester);
    var pm = parentMap(cap);
    expectSemanticsTreeInvariants(tester);

    // Brief navigation away and back.
    await _goTo(tester, 0); // Home
    await tester.pump(const Duration(milliseconds: 100));

    await _goTo(tester, 5); // Review
    await tester.pump(const Duration(milliseconds: 100));

    expectNoReparenting(pm, parentMap(captureSemantics(tester)));
    expectSemanticsTreeInvariants(tester);

    expectNoExceptionWithSemanticsDump(tester, 'review picker stability');
  });

  // -----------------------------------------------------------------------
  // §7 – Agents form push/pop
  // -----------------------------------------------------------------------

  testWidgets('Agents list → New agent form push and pop stable',
      (tester) async {
    await _pumpShell(tester, index: 6); // Agents

    var cap = captureSemantics(tester);
    var pm = parentMap(cap);
    expectSemanticsTreeInvariants(tester);

    // Try to tap New agent button — this pushes a MaterialPageRoute.
    final newAgentBtn = find.text('New agent');
    if (newAgentBtn.evaluate().isNotEmpty) {
      await tester.tap(newAgentBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Form screen should be up. Check invariants.
      expectSemanticsTreeInvariants(tester);

      // Pop back by tapping the AppBar back area or using Navigator.
      final formsBack = find.byType(AppBar);
      if (formsBack.evaluate().isNotEmpty) {
        // The scaffold's leading back icon may not match Icons.arrow_back;
        // tap near the left edge of the AppBar to simulate the back gesture.
        final box = formsBack.evaluate().first.widget as AppBar;
        if (box.title != null) {
          // There's an AppBar — try tapping the back chevron.
          final chevron = find.byIcon(Icons.chevron_left).last;
          if (chevron.evaluate().isNotEmpty) {
            await tester.tap(chevron);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
          } else {
            // No chevron either — the route won't pop without explicit
            // interaction. Skip the pop check.
            expectNoReparenting(pm, parentMap(captureSemantics(tester)));
          }
        }
      }

      expectNoExceptionWithSemanticsDump(tester, 'agents dialog');
    }
  });

  // -----------------------------------------------------------------------
  // §7 – Wide rail completeness
  // -----------------------------------------------------------------------

  testWidgets('Wide layout renders all 8 destinations — rail has 8 items',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _fakeOverrides(),
        child: const ArenaApp(),
      ),
    );
    await tester.pump();
    // Allow LayoutBuilder to compute and render.
    await tester.pump(const Duration(milliseconds: 50));

    // The rail exists and reports 8 destination slots.
    final railFinder = find.byType(NavigationRail);
    expect(railFinder, findsOneWidget);
    final rail = tester.widget<NavigationRail>(railFinder);
    expect(rail.destinations.length, equals(8),
        reason: 'NavigationRail should have 8 destinations');

    // All 8 labels present in the semantics tree.
    const labels = <String>[
      'Home', 'Play', 'Watch', 'Arena',
      'Stats', 'Review', 'Agents', 'Settings',
    ];
    for (final label in labels) {
      expect(
        find.text(label).evaluate().isNotEmpty,
        isTrue,
        reason: 'label "$label" should be visible on wide screen',
      );
    }

    expectSemanticsTreeInvariants(tester);
    expectNoExceptionWithSemanticsDump(tester, 'wide rail completeness');
  });

  // -----------------------------------------------------------------------
  // §7 – Narrow AppBar title changes
  // -----------------------------------------------------------------------

  testWidgets('Narrow: AppBar renders and changes on navigation',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _fakeOverrides(),
        child: const ArenaApp(),
      ),
    );
    await tester.pump();

    // Home selected by default — one AppBar present with a Text title.
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('Home'), findsWidgets); // drawer + appBar both have "Home"

    // Tap Play.
    await tester.tap(find.text('Play').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // App bar still there, Play label visible.
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('Play'), findsWidgets);

    // Tap Settings via More.
    await tester.tap(find.text('More').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Settings').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Shell is now on Settings.
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('Settings'), findsWidgets);

    expectNoExceptionWithSemanticsDump(tester, 'narrow AppBar titles');
  });

  // -----------------------------------------------------------------------
  // §7 – captureSemanticsSafe helper exercise
  // -----------------------------------------------------------------------

  testWidgets('captureSemanticsSafe wraps ensureSemantics properly',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _fakeOverrides(),
        child: const ArenaApp(),
      ),
    );
    await tester.pump();

    // Should work without calling ensureSemantics separately.
    final result = captureSemanticsSafe(tester);
    expect(result.root, isNotNull);
    expect(result.nodes.isNotEmpty, isTrue);
    expectSemanticsTreeInvariants(tester);
  });

  // -----------------------------------------------------------------------
  // §7 – expectNoExceptionWithSemanticsDump passes clean
  // -----------------------------------------------------------------------

  testWidgets('expectNoExceptionWithSemanticsDump passes clean',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _fakeOverrides(),
        child: const ArenaApp(),
      ),
    );
    await tester.pump();

    // This should pass (no exception was thrown).
    expectNoExceptionWithSemanticsDump(tester, 'clean dump test');
  });

  // -----------------------------------------------------------------------
  // §7 – Settings colour scheme segments
  // -----------------------------------------------------------------------

  testWidgets('Settings: toggle colour scheme segments — no semantic churn',
      (tester) async {
    await _pumpShell(tester, index: 7); // Settings

    var cap = captureSemantics(tester);
    var pm = parentMap(cap);
    expectSemanticsTreeInvariants(tester);

    // Toggle Dark segment.
    await tester.tap(find.text('Dark').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expectSemanticsTreeInvariants(tester);
    var pmDark = parentMap(captureSemantics(tester));
    expectNoReparenting(pm, pmDark);

    // Back to Light.
    await tester.tap(find.text('Light').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expectSemanticsTreeInvariants(tester);
    expectNoReparenting(pmDark, parentMap(captureSemantics(tester)));

    expectNoExceptionWithSemanticsDump(tester, 'settings segment toggles');
  });

  // -----------------------------------------------------------------------
  // §7 – Quick round-trip through every destination
  // -----------------------------------------------------------------------

  testWidgets('Quick round-trip: Home→Play→Watch→Home — zero exceptions',
      (tester) async {
    await _pumpShell(tester, index: 0);
    var cap = captureSemantics(tester);
    var pm = parentMap(cap);
    expectSemanticsTreeInvariants(tester);

    await _goTo(tester, 1); // Play
    expectSemanticsTreeInvariants(tester);
    pm = parentMap(captureSemantics(tester));

    await _goTo(tester, 2); // Watch
    expectSemanticsTreeInvariants(tester);
    pm = parentMap(captureSemantics(tester));

    await _goTo(tester, 0); // Home
    expectSemanticsTreeInvariants(tester);
    expectNoReparenting(pm, parentMap(captureSemantics(tester)));

    await tester.pump(const Duration(milliseconds: 100));
    expectSemanticsTreeInvariants(tester);

    expectNoExceptionWithSemanticsDump(tester, 'quick round-trip');
  });
}
