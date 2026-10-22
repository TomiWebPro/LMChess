// Monkey / "tap anywhere" suite — §8 from `docs/FUTURE_WORK.md`.
//
// Four deterministic tests that exercise random or grid-based taps across
// the shell, ensuring no Dart exception, no reparenting, and stable semantics
// invariants under chaotic interaction.
//
// Rules:
// * Never `pumpAndSettle`; use small `pump` slices.
// * `disposeApp(tester)` at the end so AI timers do not fail the test.
// * Per-test `Timeout(Duration(minutes: 2))`.
// * Print seed, action index, offset, and semantics dump on failure.
// * One fresh `ProviderScope` per test.
// * Cap sweeps by `maxTaps`.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction, SemanticsNode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/app.dart' show ArenaApp;
import 'package:llm_chess_arena/src/llm/mock_provider.dart';
import 'package:llm_chess_arena/src/llm/tool_schema.dart' show MoveToolCall;
import 'package:llm_chess_arena/src/llm/validation.dart' show FailureKind;
import 'package:llm_chess_arena/src/ui/backend_bridge.dart'
    show clockProvider, turnProviderFactoryProvider;

import '../support/arena_test_harness.dart' as harness;
import '../support/semantics_invariants.dart'
    show
        captureSemanticsSafe,
        expectNoExceptionWithSemanticsDump,
        expectNoReparenting,
        expectSemanticsTreeInvariants,
        parentMap;

// ---------------------------------------------------------------------------
// Deterministic RNG wrapper (no external `Random()` leaks)
// ---------------------------------------------------------------------------

class SeedRng {
  SeedRng(this._seed) : _rng = math.Random(_seed);

  final int _seed;
  math.Random _rng;

  void reseed(int s) => _rng = math.Random(s);

  double nextDouble() => _rng.nextDouble();
  int nextInt(int max) => _rng.nextInt(max);

  /// Reset to initial seed (for reproducibility).
  void reset() => _rng = math.Random(_seed);
}

// ---------------------------------------------------------------------------
// Helper: tap every labelled control on screen
// ---------------------------------------------------------------------------

Future<int> _tapEveryLabelledControl(
  WidgetTester tester, {
  required SeedRng rng,
  int maxTaps = 120,
}) async {
  var taps = 0;
  final exercised = <String>{};

  while (taps < maxTaps) {
    final snapshot = captureSemanticsSafe(tester);
    SemanticsNode? next;

    for (final node in snapshot.nodes) {
      final data = node.getSemanticsData();
      if (!data.hasAction(SemanticsAction.tap)) continue;
      final key =
          '${data.label}@${node.rect.center.dx.round()},${node.rect.center.dy.round()}';
      if (!exercised.add(key)) continue;
      next = node;
      break;
    }

    if (next == null) break;
    final target = next;
    tester.semantics.tap(
      find.semantics.byPredicate((n) => n.id == target.id),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expectNoExceptionWithSemanticsDump(tester, 'tap "${target.label}"');
    expectSemanticsTreeInvariants(tester);
    taps++;
  }
  return taps;
}

// ---------------------------------------------------------------------------
// Helper: tap a specific offset inside the view
// ---------------------------------------------------------------------------

Future<void> _tapOffset(WidgetTester tester, Offset offset, {Duration after = const Duration(milliseconds: 8)}) async {
  await tester.tapAt(offset);
  await tester.pump(after);
}

// ---------------------------------------------------------------------------
// Helper: drain routes that may have been pushed by taps
// ---------------------------------------------------------------------------

Future<void> _drainRoutes(WidgetTester tester) async {
  try {
    await tester.pump(const Duration(milliseconds: 200));
    // Try popping anything left via a back gesture.
    await tester.dragFrom(const Offset(100, 0), const Offset(-300, 0));
    await tester.pump();
  } catch (_) {
    // Ignore drain failures; we dispose anyway.
  }
}

// ---------------------------------------------------------------------------
// Test helper: pump a fresh app shell at the given size
// ---------------------------------------------------------------------------

Future<void> _pumpShell(
  WidgetTester tester, {
  Size size = const Size(1400, 1000),
  List<Override> overrides = const <Override>[],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(overrides: overrides, child: const ArenaApp()),
  );
  await tester.pump();
}

/// Fake provider overrides identical to the harness but with zero-delay mocks.
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

/// Grid-sweep utility: tap points on a regular grid within the viewport.
Future<int> _gridSweep(
  WidgetTester tester,
  Size gridSize,
  double spacing, {
  int maxTaps = 9999,
}) async {
  var taps = 0;
  final width = screenSizePx(tester).width;
  final height = screenSizePx(tester).height;
  final halfW = gridSize.width / 2;
  final halfH = gridSize.height / 2;
  final effectiveMinX = halfW;
  final effectiveMaxX = (width - halfW).clamp(halfW, width - halfW);
  final effectiveMaxY = (height - halfH).clamp(halfH, height - halfH);

  for (double x = effectiveMinX; x < effectiveMaxX && taps < maxTaps; x += spacing) {
    for (double y = halfH; y < effectiveMaxY && taps < maxTaps; y += spacing) {
      await _tapOffset(tester, Offset(x, y));
      taps++;
    }
  }
  return taps;
}

Size screenSizePx(WidgetTester tester) => tester.view.physicalSize;

/// Random-tap utility with optional reparenting checks.
Future<void> _randomTapSweep(
  WidgetTester tester,
  SeedRng rng,
  int count, {
  bool checkReparenting = false,
  Function(int index, dynamic error)? onFailure,
}) async {
  final width = screenSizePx(tester).width;
  final height = screenSizePx(tester).height;

  Map<int, int?> prevPm = const {};

  if (checkReparenting) {
    final snap = captureSemanticsSafe(tester);
    prevPm = parentMap(snap);
  }

  for (var i = 0; i < count; i++) {
    final x = rng.nextDouble() * width;
    final y = rng.nextDouble() * height;

    try {
      await _tapOffset(tester, Offset(x, y));

      if (checkReparenting) {
        final snap = captureSemanticsSafe(tester);
        final pmAfter = parentMap(snap);
        if (prevPm.isNotEmpty) {
          expectNoReparenting(prevPm, pmAfter);
        }
        prevPm = pmAfter;
      }
      expectSemanticsTreeInvariants(tester);
    } catch (e, st) {
      final msg =
          'FAIL at tap #$i, offset=($x, $y)\n$e\n$st\n${_semanticsSummary(tester)}';
      if (onFailure != null) {
        onFailure(i, e);
      } else {
        fail(msg);
      }
    }
  }
}

/// Quick summary of the current semantics tree for diagnostics.
String _semanticsSummary(WidgetTester tester) {
  final owner =
      tester.binding.renderViews.first.owner?.semanticsOwner;
  final root = owner?.rootSemanticsNode;
  if (root == null) return '(no semantics root)';

  final lines = <String>[];
  int count = 0;

  void visit(SemanticsNode node) {
    if (count < 20) {
      final data = node.getSemanticsData();
      lines.add('[${node.id}] "${data.label}"');
    }
    count++;
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(root);
  lines.add('...(total=$count nodes)');
  return lines.join('\n');
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {

  // -----------------------------------------------------------------------
  // Test 1: Narrow-layout grid sweep (600 × 800, 48 px spacing)
  // -----------------------------------------------------------------------
  testWidgets(
    '§8.1 narrow grid sweep — 600×800 @ 48px',
    (tester) async {
      const size = Size(600, 800);
      await _pumpShell(tester, size: size, overrides: _fakeOverrides());

      final tapped = await _gridSweep(tester, const Size(48, 48), 48, maxTaps: 500);

      expectSemanticsTreeInvariants(tester);
      expectNoExceptionWithSemanticsDump(tester, 'after narrow grid $tapped taps');

      await _drainRoutes(tester);
      harness.disposeApp(tester);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  // -----------------------------------------------------------------------
  // Test 2: Wide layout grid sweep with Play mounted (1600 × 1000, 48px)
  // -----------------------------------------------------------------------
  testWidgets(
    '§8.2 wide grid sweep with Play — 1600×1000 @ 48px',
    (tester) async {
      const size = Size(1600, 1000);
      await _pumpShell(tester, size: size, overrides: _fakeOverrides());

      // Tap "Play" to mount the Play tab.
      await tester.tap(find.text('Play').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expectSemanticsTreeInvariants(tester);

      final tapped =
          await _gridSweep(tester, const Size(48, 48), 48, maxTaps: 800);

      expectSemanticsTreeInvariants(tester);
      expectNoExceptionWithSemanticsDump(
          tester, 'after wide-play grid $tapped taps');

      await _drainRoutes(tester);
      harness.disposeApp(tester);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  // -----------------------------------------------------------------------
  // Test 3: 1500 random taps, seed 0xC0FFEE
  // -----------------------------------------------------------------------
  testWidgets(
    '§8.3 1500 random taps — seed 0xC0FFEE',
    (tester) async {
      final rng = SeedRng(0xC0FFEE);

      await _pumpShell(tester, overrides: _fakeOverrides());

      await _randomTapSweep(tester, rng, 1500);

      expectSemanticsTreeInvariants(tester);
      expectNoExceptionWithSemanticsDump(
          tester, 'after 1500 random taps (seed 0xC0FFEE)');

      await _drainRoutes(tester);
      harness.disposeApp(tester);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  // -----------------------------------------------------------------------
  // Test 4: 300 random taps with reparenting check at every step
  // -----------------------------------------------------------------------
  testWidgets(
    '§8.4 300 random taps + reparenting guard every step',
    (tester) async {
      final rng = SeedRng(0xCAFEBABE);

      await _pumpShell(tester, overrides: _fakeOverrides());

      await _randomTapSweep(
        tester,
        rng,
        300,
        checkReparenting: true,
      );

      expectNoExceptionWithSemanticsDump(
          tester, 'after 300 safe random taps (seed 0xCAFEBABE)');

      await _drainRoutes(tester);
      harness.disposeApp(tester);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  // -----------------------------------------------------------------------
  // Bonus: Exercise tapEveryLabelledControl on Home → then Play
  // -----------------------------------------------------------------------
  testWidgets(
    '§8.bonus — tapEveryLabelledControl on Home',
    (tester) async {
      await _pumpShell(tester, overrides: _fakeOverrides());

      final rng = SeedRng(0x1234);
      final count = await _tapEveryLabelledControl(tester, rng: rng);

      expect(count > 0, isTrue, reason: 'at least one labelled control was tapped');
      expectSemanticsTreeInvariants(tester);
      expectNoExceptionWithSemanticsDump(
          tester, 'after $count labelled-control taps on Home');

      harness.disposeApp(tester);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
