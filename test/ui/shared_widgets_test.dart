// Widget tests for shared UI components (§6.12).
//
// Covers MoveList, EvalBar, AgentActivityPanel, PlayerCard, BoardPanelLayout,
// and StatChip. Uses deterministic data — never touches real network, engine,
// or wall-clock time. No pumpAndSettle around spinners.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/ui/widgets/boards.dart'
    show
        ArenaLayoutMode,
        BoardPanelLayout,
        EvalBar,
        PlayerCard,
        MoveList,
        StatChip,
        formatClock,
        layoutModeFor,
        qualityColorFor,
        qualityIconFor;
import 'package:llm_chess_arena/src/ui/widgets/activity_panel.dart'
    show
        ActivityEvent,
        ActivityEventKind,
        AgentActivityPanel,
        redactSecrets;

/// Minimal theme wrapper that provides both MaterialApp-level Material and
/// an extra Material node for widgets using InkWell (MoveList).
Widget wrapWidget(Widget child) => MaterialApp(
      home: Material(child: child),
    );

// San plies for move-list tests.
const movesList = ['e4', 'e5', 'Nf3', 'Nc6', 'Bb5'];

// ===========================================================================
// MoveList (§6.12 – first row)
// ===========================================================================

void main() {
  group('MoveList', () {
    testWidgets('empty list shows "No moves yet."', (tester) async {
      await tester.pumpWidget(wrapWidget(const MoveList(moves: <String>[])));
      expect(find.text('No moves yet.'), findsOneWidget);
    });

    testWidgets('one move renders a single cell.', (tester) async {
      await tester.pumpWidget(wrapWidget(const MoveList(moves: ['e4'])));
      await tester.pump();
      expect(find.text('e4'), findsOneWidget);
      expect(find.text('1.'), findsOneWidget);
    });

    testWidgets('many moves render in rows of two columns.', (tester) async {
      await tester.pumpWidget(
        wrapWidget(const MoveList(moves: ['e4', 'e5', 'Nf3', 'Nc6'])),
      );
      await tester.pump();
      expect(find.text('1.'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
      expect(find.text('e4'), findsOneWidget);
      expect(find.text('e5'), findsOneWidget);
      expect(find.text('Nf3'), findsOneWidget);
      expect(find.text('Nc6'), findsOneWidget);
    });

    testWidgets('error plies show warning icon.', (tester) async {
      await tester.pumpWidget(
        wrapWidget(MoveList(
          moves: movesList,
          errorPlies: const <int>{2},
        )),
      );
      await tester.pump();
      // ⚠ text lives inside a Semantics node whose label is "error".
      expect(find.bySemanticsLabel('error'), findsOneWidget);
    });

    testWidgets('quality marks render with correct semantics label.', (tester) async {
      await tester.pumpWidget(
        wrapWidget(MoveList(
          moves: movesList,
          qualityMarks: const <int, String>{0: '!!', 3: '?'},
        )),
      );
      await tester.pump();
      expect(find.bySemanticsLabel('move quality !!'), findsOneWidget);
      expect(find.bySemanticsLabel('move quality ?'), findsOneWidget);
    });

    testWidgets('current index highlights the current ply.', (tester) async {
      await tester.pumpWidget(
        wrapWidget(const MoveList(moves: ['e4', 'e5'], currentIndex: 0)),
      );
      await tester.pump();
      final textFinder = find.text('e4');
      expect(textFinder, findsOneWidget);
      final textWidget = tester.widget<Text>(textFinder);
      expect(textWidget.style?.fontWeight, FontWeight.w700);
    });

    testWidgets('tap-to-seek calls callback with ply index.', (tester) async {
      int? tappedPly;
      void onMove(int p) => tappedPly = p;
      await tester.pumpWidget(
        wrapWidget(MoveList(
          moves: movesList,
          onTapMove: onMove,
        )),
      );
      await tester.pump();
      // Find the InkWell in the first move cell and tap it.
      final inkWell = find.byType(InkWell).first;
      await tester.tap(inkWell);
      await tester.pump();
      expect(tappedPly, equals(0));
    });

    testWidgets('null onTapMove does not throw on tap.', (tester) async {
      await tester.pumpWidget(wrapWidget(const MoveList(moves: ['e4'])));
      await tester.pump();
      final inkWell = find.byType(InkWell).first;
      await tester.tap(inkWell);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    // ===========================================================================
    // EvalBar (§6.12 – second row)
    // ===========================================================================

    group('EvalBar', () {
      testWidgets('positive score shows white-fraction bar.', (tester) async {
        await tester.pumpWidget(wrapWidget(const EvalBar(score: 1.5)));
        // Score >= 0 uses '+'.
        expect(find.text('Eval +1.5 (White-relative)'), findsOneWidget);
        expect(find.text('heuristic'), findsOneWidget);
      });

      testWidgets('negative score renders negative label.', (tester) async {
        await tester.pumpWidget(wrapWidget(const EvalBar(score: -2.0)));
        expect(find.textContaining('-2.0'), findsOneWidget);
      });

      testWidgets('zero score shows plus-zero label.', (tester) async {
        await tester.pumpWidget(wrapWidget(const EvalBar(score: 0.0)));
        // 0.0 >= 0, so prints '+0.0'.
        expect(find.text('Eval +0.0 (White-relative)'), findsOneWidget);
      });

      testWidgets('isHeuristic=false hides watermark.', (tester) async {
        await tester.pumpWidget(
          wrapWidget(const EvalBar(score: 1.0, isHeuristic: false)),
        );
        expect(find.text('heuristic'), findsNothing);
      });

      testWidgets('fractionFor maps extreme scores toward 0 or 1.', (tester) async {
        expect(EvalBar.fractionFor(10.0), greaterThan(0.99));
        expect(EvalBar.fractionFor(-10.0), lessThan(0.01));
        expect(EvalBar.fractionFor(0.0), closeTo(0.5, 0.001));
        // +2 pawns → logistic(0.5) ≈ 0.62; not yet >0.8.
        expect(EvalBar.fractionFor(2.0), greaterThan(0.6));
      });
    });

    // ===========================================================================
    // AgentActivityPanel (§6.12 – third row)
    // ===========================================================================

    group('AgentActivityPanel', () {
      testWidgets('empty state shows placeholder.', (tester) async {
        await tester.pumpWidget(
          wrapWidget(const AgentActivityPanel(events: [])),
        );
        expect(
          find.textContaining('No activity yet'),
          findsOneWidget,
        );
      });

      testWidgets('thinking empty state shows waiting message.', (tester) async {
        await tester.pumpWidget(
          wrapWidget(const AgentActivityPanel(events: [], isThinking: true)),
        );
        expect(
          find.textContaining('Waiting for the first stream event'),
          findsOneWidget,
        );
      });

      testWidgets('streaming events render individual tiles.', (tester) async {
        final events = <ActivityEvent>[
          ActivityEvent(
              kind: ActivityEventKind.started, message: 'Starting turn'),
          ActivityEvent(kind: ActivityEventKind.completed, message: 'Done'),
        ];
        await tester.pumpWidget(
          wrapWidget(AgentActivityPanel(events: events)),
        );
        // Each tile wraps its message in a Text widget; verify they appear.
        expect(find.text('Starting turn'), findsOneWidget);
        expect(find.text('Done'), findsOneWidget);
      });

      testWidgets('thinking footer shows spinner.', (tester) async {
        final events = <ActivityEvent>[
          ActivityEvent(kind: ActivityEventKind.started, message: 'Go'),
        ];
        await tester.pumpWidget(
          wrapWidget(AgentActivityPanel(events: events, isThinking: true)),
        );
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.textContaining('thinking'), findsWidgets);
      });

      testWidgets('error event renders as tile.', (tester) async {
        final events = <ActivityEvent>[
          ActivityEvent(
            kind: ActivityEventKind.error,
            message: 'Timeout exceeded',
          ),
        ];
        await tester.pumpWidget(wrapWidget(AgentActivityPanel(events: events)));
        expect(find.text('Timeout exceeded'), findsOneWidget);
      });

      testWidgets('auto-scroll chip is interactive without exception.', (tester) async {
        await tester.pumpWidget(wrapWidget(const AgentActivityPanel(events: [])));
        expect(find.text('Auto-scroll'), findsOneWidget);
        await tester.tap(find.text('Auto-scroll'));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    });

    // ===========================================================================
    // PlayerCard (§6.12 – fourth row)
    // ===========================================================================

    group('PlayerCard', () {
      testWidgets('active card displays clock formatted m:ss.', (tester) async {
        await tester.pumpWidget(
          wrapWidget(
            const PlayerCard(
              name: 'Alice',
              subtitle: 'gpt-4o · t=0.7',
              clockSeconds: 1800,
              isActive: true,
            ),
          ),
        );
        expect(find.text('Alice'), findsOneWidget);
        // 1800 seconds = 30:00.
        expect(find.text('30:00'), findsOneWidget);
      });

      testWidgets('inactive card renders without accent border.', (tester) async {
        await tester.pumpWidget(
          wrapWidget(
            const PlayerCard(name: 'Bob', isActive: false, clockSeconds: null),
          ),
        );
        expect(find.text('Bob'), findsOneWidget);
        expect(find.byIcon(Icons.person), findsNothing);
      });

      testWidgets('human avatar uses person icon.', (tester) async {
        await tester.pumpWidget(
          wrapWidget(const PlayerCard(name: 'You', isHuman: true)),
        );
        expect(find.byIcon(Icons.person), findsOneWidget);
      });

      testWidgets('agent avatar uses robot icon.', (tester) async {
        await tester.pumpWidget(
          wrapWidget(const PlayerCard(name: 'Stockfish', isHuman: false)),
        );
        expect(find.byIcon(Icons.smart_toy_outlined), findsOneWidget);
      });

      testWidgets('long names do not overflow.', (tester) async {
        await tester.pumpWidget(
          wrapWidget(PlayerCard(name: 'A' * 80)),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('subtitle renders when non-empty.', (tester) async {
        await tester.pumpWidget(
          wrapWidget(
            const PlayerCard(
              name: 'Test',
              subtitle: 'model-v2',
              isActive: false,
            ),
          ),
        );
        expect(find.text('model-v2'), findsOneWidget);
      });
    });

    // ===========================================================================
    // BoardPanelLayout (§6.12 – fifth row)
    // ===========================================================================

    group('BoardPanelLayout', () {
      testWidgets('wide mode (>1100) arranges side-by-side Row.', (tester) async {
        await tester.pumpWidget(
          wrapWidget(
            BoardPanelLayout(
              board: const SizedBox(key: Key('board'), width: 400, height: 400),
              panel: const Text('Panel'),
            ),
          ),
        );
        tester.view.physicalSize = const Size(1400, 1000);
        tester.view.devicePixelRatio = 1.0;
        await tester.pumpAndSettle();
        expect(find.byType(Row), findsOneWidget);
        expect(find.text('Panel'), findsOneWidget);
        expect(find.byType(TabBar), findsNothing);
      });

      testWidgets('medium mode (700–1100) stacks with tabs.', (tester) async {
        await tester.pumpWidget(
          wrapWidget(
            BoardPanelLayout(
              board: const SizedBox(key: Key('board')),
              panel: const Text('Side panel content'),
              boardLabel: 'Board',
              panelLabel: 'Panel',
            ),
          ),
        );
        tester.view.physicalSize = const Size(900, 700);
        await tester.pumpAndSettle();
        expect(find.byType(TabBar), findsOneWidget);
        expect(find.text('Board'), findsOneWidget);
        expect(find.text('Panel'), findsOneWidget);
      });

      testWidgets('narrow mode (<700) stacks column without tabs.', (tester) async {
        await tester.pumpWidget(
          wrapWidget(
            BoardPanelLayout(
              board: const SizedBox(key: Key('board')),
              panel: const Text('Panel'),
            ),
          ),
        );
        tester.view.physicalSize = const Size(500, 800);
        await tester.pumpAndSettle();
        expect(find.byType(Column), findsOneWidget);
        expect(find.byType(TabBar), findsNothing);
        expect(find.text('Panel'), findsOneWidget);
      });

      testWidgets('tab switch preserves child state.', (tester) async {
        await tester.pumpWidget(
          wrapWidget(
            BoardPanelLayout(
              board: StatefulBuilder(
                builder: (context, setState) => Column(
                  children: [
                    const Text('Board content'),
                    ElevatedButton(
                      key: const Key('board-btn'),
                      onPressed: () => setState(() {}),
                      child: const Text('Refresh'),
                    ),
                  ],
                ),
              ),
              panel: const Text('SidePanel'),
              boardLabel: 'Board',
              panelLabel: 'Activity',
            ),
          ),
        );
        tester.view.physicalSize = const Size(900, 700);
        await tester.pumpAndSettle();
        expect(find.text('Board content'), findsOneWidget);
        // Switch to Activity tab.
        await tester.tap(find.text('Activity'));
        await tester.pumpAndSettle();
        expect(find.text('SidePanel'), findsOneWidget);
        // Switch back: Board still mounted, button still works.
        await tester.tap(find.text('Board'));
        await tester.pumpAndSettle();
        expect(find.text('Board content'), findsOneWidget);
        await tester.tap(find.byKey(const Key('board-btn')));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    });

    // ===========================================================================
    // StatChip (§6.12 – sixth row)
    // ===========================================================================

    group('StatChip', () {
      testWidgets('renders label and value text.', (tester) async {
        await tester.pumpWidget(
          wrapWidget(const StatChip(label: 'Accuracy', value: '92%')),
        );
        expect(find.text('Accuracy: 92%'), findsOneWidget);
      });

      testWidgets('icon appears as Chip avatar.', (tester) async {
        await tester.pumpWidget(
          wrapWidget(
            const StatChip(
              label: 'Score',
              value: '1.5',
              icon: Icons.star,
              color: Color(0xFFFFD700),
            ),
          ),
        );
        expect(find.byIcon(Icons.star), findsOneWidget);
        expect(find.text('Score: 1.5'), findsOneWidget);
      });

      testWidgets('no icon means no avatar.', (tester) async {
        await tester.pumpWidget(
          wrapWidget(const StatChip(label: 'Turns', value: '42')),
        );
        expect(find.byIcon(Icons.star), findsNothing);
        expect(find.text('Turns: 42'), findsOneWidget);
      });

      testWidgets('multiple chips coexist without overlap.', (tester) async {
        await tester.pumpWidget(
          wrapWidget(
            Wrap(
              children: <Widget>[
                const StatChip(label: 'Accuracy', value: '95%'),
                const StatChip(label: 'Speed', value: '120ms'),
                const StatChip(label: 'Elo', value: '2800'),
              ],
            ),
          ),
        );
        expect(find.text('Accuracy: 95%'), findsOneWidget);
        expect(find.text('Speed: 120ms'), findsOneWidget);
        expect(find.text('Elo: 2800'), findsOneWidget);
      });
    });
  });

  // ===========================================================================
  // Responsive helpers (§6.12 cross-cutting)
  // ===========================================================================

  group('layoutModeFor / ArenaBreakpoints', () {
    test('below medium (<700) is narrow.', () {
      expect(layoutModeFor(500), equals(ArenaLayoutMode.narrow));
    });

    test('at medium boundary (700) is medium.', () {
      expect(layoutModeFor(700), equals(ArenaLayoutMode.medium));
    });

    test('between medium and wide (1000) is medium.', () {
      expect(layoutModeFor(1000), equals(ArenaLayoutMode.medium));
    });

    test('at wide boundary (1100) is medium.', () {
      expect(layoutModeFor(1100), equals(ArenaLayoutMode.medium));
    });

    test('above wide (>1100) is wide.', () {
      expect(layoutModeFor(1200), equals(ArenaLayoutMode.wide));
    });
  });

  group('formatClock', () {
    test('zero seconds renders 0:00.', () {
      expect(formatClock(0), equals('0:00'));
    });

    test('under one hour formats mm:ss.', () {
      expect(formatClock(90), equals('1:30'));
    });

    test('over one hour formats h:mm:ss.', () {
      expect(formatClock(3661), equals('1:01:01'));
    });

    test('negative input clamps to zero.', () {
      expect(formatClock(-300), equals('0:00'));
    });
  });

  group('qualityColorFor', () {
    test('!! in light theme returns dark gold.', () {
      expect(
        qualityColorFor('!!', brightness: Brightness.light),
        equals(const Color(0xFFB8860B)),
      );
    });

    test('! in dark theme returns green.', () {
      expect(
        qualityColorFor('!', brightness: Brightness.dark),
        equals(const Color(0xFF81C784)),
      );
    });

    test('unknown mark returns neutral grey.', () {
      expect(qualityColorFor('xyz'), equals(const Color(0xFF616161)));
    });
  });

  group('qualityIconFor', () {
    test('maps known marks correctly.', () {
      expect(qualityIconFor('!!'), equals(Icons.star));
      expect(qualityIconFor('!'), equals(Icons.check_circle_outline));
      expect(qualityIconFor('!?'), equals(Icons.lightbulb_outline));
      expect(qualityIconFor('?'), equals(Icons.warning_amber_outlined));
      expect(qualityIconFor('??'), equals(Icons.cancel_outlined));
    });

    test('unknown mark returns outlined circle.', () {
      expect(qualityIconFor('xyz'), equals(Icons.circle_outlined));
    });
  });

  group('redactSecrets', () {
    test('redacts sk- API keys.', () {
      expect(
        redactSecrets('token is sk-abcd1234efgh5678'),
        equals('token is sk-[redacted]'),
      );
    });

    test('redacts api_key assignments (leaves trailing quotes).', () {
      // Regex captures up to [^\s"']+ so closing quotes remain.
      expect(
        redactSecrets('api_key = "secret123"'),
        equals('api_key = [redacted]"'),
      );
    });

    test('redacts Bearer tokens.', () {
      expect(
        redactSecrets('Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.test'),
        startsWith('Authorization: Bearer [redacted]'),
      );
    });

    test('safe strings pass through unchanged.', () {
      expect(redactSecrets('Hello world'), equals('Hello world'));
      expect(
        redactSecrets('make_chess_move{from:e2,to:e4}'),
        equals('make_chess_move{from:e2,to:e4}'),
      );
    });
  });
}
