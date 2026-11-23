/// §10.6 Deterministic deep states — `@visibleForTesting` constructor params.
///
/// PlayScreen({this.initialFen}) — test promotion/checkmate without 40 moves.
/// WatchScreen({this.initialSeed}) — deterministic mock runs without wall-clock.
/// ArenaScreen({this.initialSeed, this.elo}) — deterministic tournaments.
/// AppShell({this.initialIndex = 0}) — test one destination without tapping.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/app.dart' show ArenaApp, AppShell;
import 'package:llm_chess_arena/src/ui/screens/play_screen.dart' show PlayScreen;
import 'package:llm_chess_arena/src/ui/screens/watch_screen.dart' show WatchScreen;
import 'package:llm_chess_arena/src/ui/widgets/chessboard.dart' show Chessboard;
import '../support/arena_test_harness.dart' as harness;

// FEN where White has a pawn on e5 (pawn push in opening).
const String _pawnOnE5Fen =
    'rnbqkbnr/pppp1ppp/8/4P3/8/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';

// Minimal position: two isolated kings only.
const String _twoKingsFen = '8/8/8/3K4/8/k7/8/8 w - - 0 1';

void main() {

  group('PlayScreen initialFen', () {
    testWidgets(
        'initialFen overrides starting position — engine parses it without crash',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: harness.fakeOverrides(),
          child: MaterialApp(
            home: Scaffold(
              body: PlayScreen(initialFen: _pawnOnE5Fen),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Board should render pieces from the custom FEN.
      final board = tester.widget<Chessboard>(find.byType(Chessboard).first);
      expect(board.squares, isNotNull);
      final squares = board.squares;
      // Square e5 should have a white pawn.
      expect(squares['e5'], equals('wP'));
    });

    testWidgets(
        'initialFen different from default — custom piece placement confirmed',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: harness.fakeOverrides(),
          child: MaterialApp(
            home: Scaffold(
              body: PlayScreen(initialFen: _pawnOnE5Fen),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final board = tester.widget<Chessboard>(find.byType(Chessboard).first);
      // Custom FEN: white pawn on e5 confirms initialFen was applied.
      expect(board.squares['e5'], equals('wP'));
    });

    testWidgets(
        'initialFen minimal king-only FEN — renders two kings without crash',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: harness.fakeOverrides(),
          child: MaterialApp(
            home: Scaffold(
              body: PlayScreen(initialFen: _twoKingsFen),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final board = tester.widget<Chessboard>(find.byType(Chessboard).first);
      final squares = board.squares;
      expect(squares['d5'], equals('wK'));
      expect(squares['a3'], equals('bK'));
    });

    testWidgets(
        'PlayScreen without initialFen uses standard starting position',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: harness.fakeOverrides(),
          child: MaterialApp(
            home: Scaffold(body: const PlayScreen()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final board = tester.widget<Chessboard>(find.byType(Chessboard).first);
      final squares = board.squares;
      expect(squares['e2'], equals('wP'));
      expect(squares['e7'], equals('bP'));
      expect(squares['e1'], equals('wK'));
      expect(squares['e8'], equals('bK'));
      expect(squares['e5'], isNull);
    });
  });

  group('AppShell initialIndex', () {
    testWidgets(
        'default AppShell starts at index 0 (Game)',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(child: const ArenaApp()),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Unified game room is the default tab.
      expect(find.text('Game'), findsWidgets);
      expect(find.byType(Chessboard), findsOneWidget);
    });

    testWidgets(
        'initialIndex=0 shows Game directly without navigation',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: harness.fakeOverrides(),
          child: MaterialApp(
            home: Builder(
              builder: (context) => AppShell(initialIndex: 0),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Game content visible — seat card labels.
      expect(find.text('You · White'), findsOneWidget);
      expect(find.text('Demo Black'), findsWidgets);
    });

    testWidgets(
        'initialIndex=4 shows Settings directly',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: harness.fakeOverrides(),
          child: MaterialApp(
            home: Builder(
              builder: (context) => AppShell(initialIndex: 4),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Settings'), findsOneWidget);
    });
  });

  group('WatchScreen initialSeed', () {
    testWidgets(
        'WatchScreen with initialSeed=42 renders stably',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: harness.fakeOverrides(),
          child: MaterialApp(
            home: Scaffold(
              body: WatchScreen(initialSeed: 42),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(WatchScreen), findsOneWidget);
      expect(find.byType(Chessboard), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('game-setup-button')),
        findsOneWidget,
      );
    });

    testWidgets(
        'two WatchScreens with same initialSeed both render',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: harness.fakeOverrides(),
          child: MaterialApp(
            home: Scaffold(
              body: Column(children: [
                Expanded(child: WatchScreen(initialSeed: 123)),
                Expanded(child: WatchScreen(initialSeed: 123)),
              ]),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(Chessboard), findsNWidgets(2));
      expect(
        find.byKey(const ValueKey<String>('game-setup-button')),
        findsNWidgets(2),
      );
    });
  });

  group('Backward compatibility — no-parameter constructors', () {
    testWidgets('const PlayScreen() compiles and renders', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: harness.fakeOverrides(),
          child: MaterialApp(
            home: Scaffold(body: const PlayScreen()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(PlayScreen), findsOneWidget);
    });

    testWidgets('const WatchScreen() compiles and renders', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: harness.fakeOverrides(),
          child: MaterialApp(
            home: Scaffold(body: const WatchScreen()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(WatchScreen), findsOneWidget);
    });

    testWidgets('const AppShell() compiles and renders', (tester) async {
      await tester.pumpWidget(
        ProviderScope(child: const ArenaApp()),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(AppShell), findsOneWidget);
    });
  });
}
