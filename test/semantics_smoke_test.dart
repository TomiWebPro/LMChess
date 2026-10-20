// Semantics regression tests.
//
// These lock in the wiring that previously produced engine-side
// "Failed to update ui::AXTree, error: … will not be in the tree and is not
// the new root" errors on Windows desktop:
//
// * Chessboard: exactly one labelled semantics node per square (the piece
//   glyph and coordinate Text are excluded), so the per-cell AnimatedSwitcher
//   can animate without adding or removing semantics nodes.
// * AppShell: hidden IndexedStack tabs contribute no semantics, and switching
//   tabs through the accessibility tree does not throw.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/app.dart';
import 'package:llm_chess_arena/src/theme/board_theme.dart';
import 'package:llm_chess_arena/src/theme/piece_theme.dart';
import 'package:llm_chess_arena/src/ui/widgets/chessboard.dart';

void main() {
  testWidgets('chessboard exposes one labelled semantics node per square', (
    tester,
  ) async {
    // Must be disposed before the test body ends (end-of-test verification
    // runs before tearDowns).
    final handle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Chessboard(
              squares: const <String, String>{'e4': 'wP', 'd5': 'bK'},
              boardTheme: BoardTheme.classic,
              pieceTheme: PieceTheme.meridian,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('White piece on e4'), findsOneWidget);
      expect(find.bySemanticsLabel('Black piece on d5'), findsOneWidget);
      expect(find.bySemanticsLabel('Empty square a1'), findsOneWidget);
      // No stray glyph/coordinate text nodes leaked into the tree.
      expect(find.bySemanticsLabel(RegExp(r'^[♔-♟]$')), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      handle.dispose();
    }
  });

  testWidgets('hidden shell tabs contribute no semantics; switching is safe', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(const ProviderScope(child: ArenaApp()));
      await tester.pumpAndSettle();

      // The board lives on the Play tab; while Home is selected its per-square
      // nodes must not be present in the accessibility tree.
      expect(find.bySemanticsLabel('White piece on e1'), findsNothing);

      await tester.tap(find.text('Play').first);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('White piece on e1'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Stats hosts no board, so the Play board's nodes must be gone again.
      await tester.tap(find.text('Stats').first);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('White piece on e1'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      handle.dispose();
    }
  });
}
