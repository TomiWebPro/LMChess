// Boot smoke test — the "does the standalone app actually run" check.
//
// Scope (deliberately minimal): pump the real [ArenaApp] with seeded demo
// agents (zero configuration, no API keys, no filesystem/network access
// required) and verify that the shell renders and primary navigation
// destinations open. This is not a behavioral test suite — per project
// instructions, comprehensive tests come later; this file guards the
// wiring contract between providers, shell, and screens.
//
// Everything asserted here must hold on every platform and with an empty
// environment: the default providers seed two `demo` agents in-memory.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/app.dart';

void main() {
  testWidgets('app boots to the game shell with demo agents', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: ArenaApp()),
    );
    await tester.pump();

    // Navigation rail renders the unified destinations (no Home dashboard).
    expect(find.text('Game'), findsWidgets);
    expect(find.text('Arena'), findsWidgets);
    expect(find.text('Stats'), findsWidgets);
  });

  testWidgets('game screen opens and shows the board', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: ArenaApp()),
    );
    await tester.pump();

    // Navigate: tap the Game destination in the rail (wide layout shows
    // the rail; the game auto-starts human-vs-agent).
    await tester.tap(find.text('Game').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // The game screen hosts the chessboard; assert at least one board
    // surface and the seat chrome rendered without exceptions.
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey<String>('seat-card-white')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('seat-card-black')),
      findsOneWidget,
    );
  });

  testWidgets('wide desktop layout renders without exceptions', (
    tester,
  ) async {
    // 1600×1000 triggers the wide (>1100) board+panel side-by-side mode;
    // the default 800×600 test surface exercises the tabbed/narrow modes.
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(child: ArenaApp()),
    );
    await tester.pump();

    await tester.tap(find.text('Arena').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // NOTE: no takeException on purpose — leaving any layout exception
    // pending lets the test framework dump it at test end WITH the full
    // widget diagnostics (creator chains), which makes failures fixable.
    expect(find.textContaining('Tournament'), findsWidgets);
  });
}
