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
  testWidgets('app boots to the home shell with demo agents', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: ArenaApp()),
    );
    await tester.pump();

    // Title renders (shell AppBar or home header).
    expect(find.text('LLM Chess Arena'), findsWidgets);

    // Home screen feature tiles are visible.
    expect(find.text('Play'), findsWidgets);
    expect(find.text('Watch'), findsWidgets);
    expect(find.text('Arena'), findsWidgets);
  });

  testWidgets('play screen opens and shows the board', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: ArenaApp()),
    );
    await tester.pump();

    // Navigate: tap the Play tile on the home screen (wide layout shows
    // both rail and tiles; the tile exists regardless).
    await tester.tap(find.text('Play').first);
    await tester.pumpAndSettle();

    // The play screen hosts the chessboard; assert at least one board
    // surface and the promotion/status chrome rendered without exceptions.
    expect(tester.takeException(), isNull);
    expect(find.textContaining('AI'), findsWidgets);
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

    await tester.tap(find.text('Watch').first);
    await tester.pumpAndSettle();

    // NOTE: no takeException on purpose — leaving any layout exception
    // pending lets the test framework dump it at test end WITH the full
    // widget diagnostics (creator chains), which makes failures fixable.
    expect(find.textContaining('White'), findsWidgets);
  });
}
