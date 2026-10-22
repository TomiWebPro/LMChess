// Widget tests for Chessboard drag-and-drop (§15.1).
//
// Exercises the additive pointer path: pick up a piece, hover legal targets,
// drop to move, cancel with Esc/right-click, orientation mapping, semantics
// stability, and the PlayScreen wiring. Uses deterministic fakes only — no
// network, engine process, or wall-clock time.
import 'package:flutter/gestures.dart' show PointerDeviceKind, kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/app.dart' show ArenaApp;
import 'package:llm_chess_arena/src/llm/mock_provider.dart';
import 'package:llm_chess_arena/src/llm/tool_schema.dart' show MoveToolCall;
import 'package:llm_chess_arena/src/theme/board_theme.dart';
import 'package:llm_chess_arena/src/theme/piece_theme.dart';
import 'package:llm_chess_arena/src/ui/backend_bridge.dart'
    show clockProvider, turnProviderFactoryProvider;
import 'package:llm_chess_arena/src/ui/screens/play_screen.dart'
    show PlayScreen;
import 'package:llm_chess_arena/src/ui/widgets/chessboard.dart';

import '../support/arena_test_harness.dart' as harness;
import '../support/semantics_invariants.dart';

// ---------------------------------------------------------------------------
// Host harness: mimics PlayScreen's select-then-move contract.
// ---------------------------------------------------------------------------

const Map<String, String> _hostBoard = <String, String>{
  'e1': 'wK',
  'e2': 'wP',
  'd2': 'wP',
  'b7': 'bP',
  'e8': 'bK',
};

class _DragHost extends StatefulWidget {
  const _DragHost({
    super.key,
    this.useMoveAttempt = true,
    this.orientationWhite = true,
  });

  final bool useMoveAttempt;
  final bool orientationWhite;

  @override
  State<_DragHost> createState() => _DragHostState();
}

class _DragHostState extends State<_DragHost> {
  String? _selected;
  List<String> _legal = const <String>[];

  /// Recorded moves as `fromTo` (for example `e2e4`).
  final List<String> moves = <String>[];

  /// Every square passed to [Chessboard.onTapSquare], in order.
  final List<String> taps = <String>[];

  bool _isWhite(String square) => (_hostBoard[square] ?? '').startsWith('w');

  void _onTap(String square) {
    setState(() {
      taps.add(square);
      if (_selected != null && _legal.contains(square)) {
        moves.add('$_selected$square');
        _selected = null;
        _legal = const <String>[];
        return;
      }
      if (_isWhite(square)) {
        if (_selected == square) {
          _selected = null;
          _legal = const <String>[];
          return;
        }
        _selected = square;
        _legal = switch (square) {
          'e2' => const <String>['e3', 'e4'],
          'd2' => const <String>['d3', 'd4'],
          _ => const <String>[],
        };
        return;
      }
      _selected = null;
      _legal = const <String>[];
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            height: 400,
            child: Chessboard(
              squares: _hostBoard,
              orientationWhite: widget.orientationWhite,
              selected: _selected,
              legalTargets: _legal,
              boardTheme: BoardTheme.classic,
              pieceTheme: PieceTheme.meridian,
              onTapSquare: _onTap,
              canDragSquare: _isWhite,
              onMoveAttempt: widget.useMoveAttempt
                  ? (from, to) => setState(() {
                      moves.add('$from$to');
                      _selected = null;
                      _legal = const <String>[];
                    })
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// Screen-space center of a square for the 400×400 harness board.
Offset _centerOf(
  WidgetTester tester,
  String square, {
  bool orientationWhite = true,
}) {
  final rect = tester.getRect(find.byType(Chessboard));
  final file = 'abcdefgh'.indexOf(square[0]);
  final rank = int.parse(square[1]) - 1;
  final col = orientationWhite ? file : 7 - file;
  final row = orientationWhite ? 7 - rank : rank;
  final cell = rect.width / 8;
  return rect.topLeft + Offset((col + 0.5) * cell, (row + 0.5) * cell);
}

Future<void> _pumpHost(WidgetTester tester, _DragHost host) async {
  await tester.pumpWidget(host);
  await tester.pump();
}

/// Drags from [from] to [to] and pumps between move/drop so the host can
/// rebuild legal targets after drag-start selection.
Future<void> _dragBetween(
  WidgetTester tester, {
  required String from,
  required String to,
  PointerDeviceKind kind = PointerDeviceKind.mouse,
  bool orientationWhite = true,
}) async {
  final gesture = await tester.startGesture(
    _centerOf(tester, from, orientationWhite: orientationWhite),
    kind: kind,
  );
  await gesture.moveTo(
    _centerOf(tester, to, orientationWhite: orientationWhite),
  );
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

// ---------------------------------------------------------------------------
// PlayScreen drag integration helpers (real board wiring + mock AI).
// ---------------------------------------------------------------------------

List<Override> _playOverrides() => <Override>[
  turnProviderFactoryProvider.overrideWithValue((
    config,
    legalUcis, {
    seed,
    phrase,
  }) async {
    if (legalUcis.isEmpty) {
      return MockProvider(script: const <Object>[], model: config.model);
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
  }),
  clockProvider.overrideWithValue(() => DateTime.utc(2026, 1, 1)),
];

Future<void> _pumpPlayApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(overrides: _playOverrides(), child: ArenaApp()),
  );
  await tester.tap(find.text('Play').first);
  await tester.pump();
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(milliseconds: 100));
}

/// White pawn on a7, kings on h1/h8, White to move — one drag from promotion.
const String _promotionFen = '7k/P7/8/8/8/8/8/7K w - - 0 1';

Future<void> _pumpPlayFen(WidgetTester tester, String fen) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: _playOverrides(),
      child: MaterialApp(
        home: Scaffold(body: PlayScreen(initialFen: fen)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// Drags between two semantically labelled squares on the Play board.
Future<void> _dragSemanticSquares(
  WidgetTester tester, {
  required String from,
  required String to,
  PointerDeviceKind kind = PointerDeviceKind.mouse,
}) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.bySemanticsLabel(from)),
    kind: kind,
  );
  await gesture.moveTo(tester.getCenter(find.bySemanticsLabel(to)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await gesture.up();
  await tester.pump();
}

void main() {
  setUp(harness.resetTelemetry);

  group('§15.1 drag and drop', () {
    testWidgets('mouse drag e2→e4 selects, lifts, and calls onMoveAttempt', (
      tester,
    ) async {
      final host = _DragHost(key: UniqueKey());
      await _pumpHost(tester, host);
      final state = tester.state<_DragHostState>(find.byType(_DragHost));

      final gesture = await tester.startGesture(
        _centerOf(tester, 'e2'),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(_centerOf(tester, 'e4'));
      await tester.pump();

      // Drag-start selection ran through the host's tap contract.
      expect(state.taps, <String>['e2']);
      expect(
        find.byKey(const ValueKey<String>('chessboard-drag-overlay')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('drag-hover-e4')),
        findsOneWidget,
      );
      // Source glyph is transparent while the lifted piece follows the pointer.
      expect(
        tester
            .widgetList<Opacity>(find.byType(Opacity))
            .where((w) => w.opacity == 0),
        isNotEmpty,
      );

      await gesture.up();
      await tester.pump();

      expect(state.moves, <String>['e2e4']);
      expect(
        find.byKey(const ValueKey<String>('chessboard-drag-overlay')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey<String>('drag-hover-e4')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('touch drag e2→e4 works without a long press', (tester) async {
      final host = _DragHost(key: UniqueKey());
      await _pumpHost(tester, host);
      final state = tester.state<_DragHostState>(find.byType(_DragHost));

      await _dragBetween(tester, from: 'e2', to: 'e4');
      expect(state.moves, <String>['e2e4']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('drop on an illegal square snaps back without a move', (
      tester,
    ) async {
      final host = _DragHost(key: UniqueKey());
      await _pumpHost(tester, host);
      final state = tester.state<_DragHostState>(find.byType(_DragHost));

      await _dragBetween(tester, from: 'e2', to: 'e5');
      expect(state.moves, isEmpty);
      expect(state.taps, <String>['e2']);
      expect(
        find.byKey(const ValueKey<String>('chessboard-drag-overlay')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('drop outside the board snaps back without a move', (
      tester,
    ) async {
      final host = _DragHost(key: UniqueKey());
      await _pumpHost(tester, host);
      final state = tester.state<_DragHostState>(find.byType(_DragHost));

      final gesture = await tester.startGesture(
        _centerOf(tester, 'e2'),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(const Offset(5, 5));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(state.moves, isEmpty);
      expect(
        find.byKey(const ValueKey<String>('chessboard-drag-overlay')),
        findsNothing,
      );
    });

    testWidgets('drag cannot start on an empty square', (tester) async {
      final host = _DragHost(key: UniqueKey());
      await _pumpHost(tester, host);
      final state = tester.state<_DragHostState>(find.byType(_DragHost));

      await _dragBetween(tester, from: 'e4', to: 'e5');
      expect(state.taps, isEmpty);
      expect(state.moves, isEmpty);
    });

    testWidgets('drag cannot start on an opponent piece when filtered', (
      tester,
    ) async {
      final host = _DragHost(key: UniqueKey());
      await _pumpHost(tester, host);
      final state = tester.state<_DragHostState>(find.byType(_DragHost));

      await _dragBetween(tester, from: 'b7', to: 'b5');
      expect(state.taps, isEmpty);
      expect(state.moves, isEmpty);
    });

    testWidgets(
      'without onMoveAttempt a legal drop falls back to onTapSquare',
      (tester) async {
        final host = _DragHost(key: UniqueKey(), useMoveAttempt: false);
        await _pumpHost(tester, host);
        final state = tester.state<_DragHostState>(find.byType(_DragHost));

        await _dragBetween(tester, from: 'e2', to: 'e4');
        expect(state.moves, <String>['e2e4']);
        expect(state.taps, <String>['e2', 'e4']);
      },
    );

    testWidgets('right-click cancels an in-flight drag', (tester) async {
      final host = _DragHost(key: UniqueKey());
      await _pumpHost(tester, host);
      final state = tester.state<_DragHostState>(find.byType(_DragHost));

      final gesture = await tester.startGesture(
        _centerOf(tester, 'e2'),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(_centerOf(tester, 'e4'));
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('chessboard-drag-overlay')),
        findsOneWidget,
      );

      await tester.tapAt(_centerOf(tester, 'e4'), buttons: kSecondaryButton);
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('chessboard-drag-overlay')),
        findsNothing,
      );

      await gesture.up();
      await tester.pump();
      expect(state.moves, isEmpty);
    });

    testWidgets('Escape cancels an in-flight drag', (tester) async {
      final host = _DragHost(key: UniqueKey());
      await _pumpHost(tester, host);
      final state = tester.state<_DragHostState>(find.byType(_DragHost));

      final gesture = await tester.startGesture(
        _centerOf(tester, 'e2'),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(_centerOf(tester, 'e4'));
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('chessboard-drag-overlay')),
        findsOneWidget,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('chessboard-drag-overlay')),
        findsNothing,
      );

      await gesture.up();
      await tester.pump();
      expect(state.moves, isEmpty);
    });

    testWidgets('black orientation maps drag positions correctly', (
      tester,
    ) async {
      final host = _DragHost(key: UniqueKey(), orientationWhite: false);
      await _pumpHost(tester, host);
      final state = tester.state<_DragHostState>(find.byType(_DragHost));

      await _dragBetween(tester, from: 'e2', to: 'e4', orientationWhite: false);
      expect(state.moves, <String>['e2e4']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('drag keeps 64 stable square semantics nodes', (tester) async {
      final handle = tester.ensureSemantics();
      final host = _DragHost(key: UniqueKey());
      await _pumpHost(tester, host);

      final before = captureSemantics(tester);
      expectSquareSemantics(tester, expectedCount: 64);

      final gesture = await tester.startGesture(
        _centerOf(tester, 'e2'),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(_centerOf(tester, 'e4'));
      await tester.pump();

      // Mid-drag the overlay is excluded from semantics: still 64 nodes.
      expectSquareSemantics(tester, expectedCount: 64);
      expectSemanticsTreeInvariants(tester);
      final afterMove = captureSemantics(tester);
      expectNoReparenting(parentMap(before), parentMap(afterMove));

      await gesture.up();
      await tester.pump();

      expectSquareSemantics(tester, expectedCount: 64);
      expectSemanticsTreeInvariants(tester);
      final afterDrop = captureSemantics(tester);
      expectNoReparenting(parentMap(before), parentMap(afterDrop));
      handle.dispose();
    });
  });

  group('§15.1 PlayScreen wiring', () {
    testWidgets('mouse drag e2→e4 plays the human move', (tester) async {
      await _pumpPlayApp(tester);
      expect(find.bySemanticsLabel('White piece on e2'), findsOneWidget);

      final start = tester.getCenter(
        find.bySemanticsLabel('White piece on e2'),
      );
      final destination = tester.getCenter(
        find.bySemanticsLabel('Empty square e4'),
      );
      final gesture = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(destination);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.bySemanticsLabel('White piece on e4'), findsOneWidget);
      expect(find.bySemanticsLabel('White piece on e2'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('touch drag d2→d4 plays the human move', (tester) async {
      await _pumpPlayApp(tester);
      expect(find.bySemanticsLabel('White piece on d2'), findsOneWidget);

      final start = tester.getCenter(
        find.bySemanticsLabel('White piece on d2'),
      );
      final destination = tester.getCenter(
        find.bySemanticsLabel('Empty square d4'),
      );
      final gesture = await tester.startGesture(start);
      await gesture.moveTo(destination);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.bySemanticsLabel('White piece on d4'), findsOneWidget);
      expect(find.bySemanticsLabel('White piece on d2'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'promotion drag opens the dialog and cancel restores the pawn',
      (tester) async {
        await _pumpPlayFen(tester, _promotionFen);
        expect(find.bySemanticsLabel('White piece on a7'), findsOneWidget);

        await _dragSemanticSquares(
          tester,
          from: 'White piece on a7',
          to: 'Empty square a8',
        );
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('Promote to'), findsOneWidget);

        // Dismiss the dialog by tapping the barrier; the pawn must stay put.
        await tester.tapAt(const Offset(5, 5));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Promote to'), findsNothing);
        final board = tester.widget<Chessboard>(find.byType(Chessboard).first);
        expect(board.squares['a7'], 'wP');
        expect(board.squares['a8'], isNull);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('promotion drag applies the chosen piece', (tester) async {
      await _pumpPlayFen(tester, _promotionFen);

      await _dragSemanticSquares(
        tester,
        from: 'White piece on a7',
        to: 'Empty square a8',
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Promote to'), findsOneWidget);

      await tester.tap(find.byTooltip('Q'));
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final board = tester.widget<Chessboard>(find.byType(Chessboard).first);
      expect(board.squares['a8'], 'wQ');
      expect(board.squares['a7'], isNull);
      expect(tester.takeException(), isNull);
    });
  });
}
