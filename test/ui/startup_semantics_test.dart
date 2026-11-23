// Startup semantics coverage for the Game-first shell
// (flutter/flutter#175041).
//
// On Windows, runs of the Game-first shell logged
// `Failed to update ui::AXTree ... Nodes left pending` from the engine on
// every clock tick, followed once by a fatal bridge abort ("Lost connection
// to device"). The engine log proved two things: the bridge can be enabled
// with no screen reader attached (enumeration reaches the engine child view
// directly), and the framework then re-sends updates that reference
// already-dropped nodes on every tick.
//
// Widget tests cannot observe the engine-side update stream, so this suite
// pins the framework-side contract instead, through the exact startup
// sequence that crashed: boot the real [ArenaApp] (Game tab first,
// autostart on) with semantics enabled, flush the post-frame focus work,
// advance the 200 ms clock ticker, and tour the destinations — asserting the
// semantics invariants, no reparenting, no clock-format labels, and no Dart
// exceptions at every step.
//
// Deterministic fakes only: instant mock AI moves, fixed UTC clock.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/app.dart' show ArenaApp;
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
        parentMap;

/// Overrides: fake AI turns return legal UCI instantly; clock fixed UTC.
List<Override> _startupOverrides() => <Override>[
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

/// Boot the real app shell with semantics enabled.
///
/// Returns the semantics handle; the caller MUST dispose it in a `finally`
/// block (never in `addTearDown` — end-of-test verification runs first).
Future<SemanticsHandle> _bootShell(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: _startupOverrides(),
      child: const ArenaApp(),
    ),
  );
  final handle = tester.ensureSemantics();
  // First frame + autostart microtask + post-frame focus sync.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 100));
  return handle;
}

/// Clock countdown labels (`m:ss`, `h:mm:ss`) must never reach the AX tree.
final RegExp _clockLabel = RegExp(r'^\d+:\d{2}(:\d{2})?$');

void _expectNoClockLabels(WidgetTester tester) {
  final capture = captureSemantics(tester);
  final hits = <String>[
    for (final node in capture.nodes)
      node.getSemanticsData().label,
    ].where((label) => _clockLabel.hasMatch(label)).toList();
  expect(hits, isEmpty, reason: 'clock labels leaked into semantics: $hits');
}

void main() {
  testWidgets('startup frames hold semantics invariants', (tester) async {
    final handle = await _bootShell(tester);
    try {
      // The shell boots on the unified Game room with the board mounted.
      expect(find.bySemanticsLabel('White piece on e2'), findsOneWidget);
      // Flush the 200 ms clock ticker and the autostart stream setup.
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      expectSemanticsTreeInvariants(tester);
      _expectNoClockLabels(tester);
      expectNoExceptionWithSemanticsDump(tester, 'startup frames');
    } finally {
      handle.dispose();
    }
  });

  testWidgets('clock ticker advances without reparenting', (tester) async {
    final handle = await _bootShell(tester);
    try {
      var before = parentMap(captureSemantics(tester));
      // Three macroscopic time steps: each fires the 200 ms ticker several
      // times and flushes any timer/stream/ _activity work they schedule.
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 1));
        expectSemanticsTreeInvariants(tester);
        expectNoReparenting(before, parentMap(captureSemantics(tester)));
        _expectNoClockLabels(tester);
        expectNoExceptionWithSemanticsDump(tester, 'ticker step $i');
        before = parentMap(captureSemantics(tester));
      }
    } finally {
      handle.dispose();
    }
  });

  testWidgets('destination tour after startup holds invariants', (tester) async {
    final handle = await _bootShell(tester);
    try {
      const tour = <String>[
        'Arena',
        'Stats',
        'Review',
        'Settings',
        'Game',
      ];
      var before = parentMap(captureSemantics(tester));
      for (final label in tour) {
        await tester.tap(find.text(label).first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expectSemanticsTreeInvariants(tester);
        expectNoReparenting(before, parentMap(captureSemantics(tester)));
        expectNoExceptionWithSemanticsDump(tester, 'tour stop $label');
        before = parentMap(captureSemantics(tester));
      }
      // Back on Game: board squares are back, clocks still excluded.
      expect(find.bySemanticsLabel('White piece on e2'), findsOneWidget);
      _expectNoClockLabels(tester);
    } finally {
      handle.dispose();
    }
  });
}
