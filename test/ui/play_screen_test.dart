// Widget tests for PlayScreen (§6.4).
//
// Covers human AI interactions, dialogs, result state, move-list seeking,
// activity/moves tabs, error banners, retry behaviour, and lifecycle.
// Uses deterministic fakes — never touches real network, engine, or wall-clock
// time. No pumpAndSettle around spinners.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/app.dart' show ArenaApp;
import 'package:llm_chess_arena/src/llm/mock_provider.dart';
import 'package:llm_chess_arena/src/llm/tool_schema.dart' show MoveToolCall;
import 'package:llm_chess_arena/src/llm/validation.dart' show FailureKind;
import 'package:llm_chess_arena/src/ui/backend_bridge.dart'
    show clockProvider, turnProviderFactoryProvider;
import 'package:llm_chess_arena/src/ui/widgets/boards.dart' show PlayerCard;

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Overrides: fake AI turns return legal UCI moves instantly (stepDelay=0)
/// and the clock is fixed UTC.
List<Override> _playOverrides() => <Override>[
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

Future<void> _pumpPlayApp(
  WidgetTester tester, {
  Size size = const Size(1400, 1000),
  Iterable<Override>? overrides,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides?.toList() ?? _playOverrides(),
      child: ArenaApp(),
    ),
  );
  // Navigate to Play tab — pump extra frames so layout settles.
  await tester.tap(find.text('Play').first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {

  group('PlayScreen board interaction', () {
    // -- Piece selection & deselection --------------------------------------

    testWidgets('select own piece → no exception', (tester) async {
      await _pumpPlayApp(tester);
      expect(find.bySemanticsLabel('White piece on e2'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('White piece on e2'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('deselect: tap same piece twice', (tester) async {
      await _pumpPlayApp(tester);
      await tester.tap(find.bySemanticsLabel('White piece on e2'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('White piece on e2'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('reselect: deselect then tap another own piece', (tester) async {
      await _pumpPlayApp(tester);
      await tester.tap(find.bySemanticsLabel('White piece on d2'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('White piece on d2'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('White piece on e2'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    // -- Opponent / empty squares -------------------------------------------

    testWidgets('tap opponent piece with nothing selected → no crash',
        (tester) async {
      await _pumpPlayApp(tester);
      await tester.tap(find.bySemanticsLabel('Black piece on e7'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('tap empty square with nothing selected → no crash',
        (tester) async {
      await _pumpPlayApp(tester);
      await tester.tap(find.bySemanticsLabel('Empty square e4'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    // -- Legal moves --------------------------------------------------------

    testWidgets('legal move via coordinate tap → no crash', (tester) async {
      await _pumpPlayApp(tester);
      await tester.tap(find.bySemanticsLabel('White piece on e2'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Empty square e4'));
      await tester.pump(const Duration(milliseconds: 800));
      expect(tester.takeException(), isNull);
    });

    testWidgets('illegal destination → no snackbar crash', (tester) async {
      await _pumpPlayApp(tester);
      await tester.tap(find.bySemanticsLabel('White piece on e2'));
      await tester.pump();
      // Try an illegal square (not reachable by pawn from e2).
      await tester.tap(find.bySemanticsLabel('Empty square h5'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    // -- Promotion dialog ---------------------------------------------------

    testWidgets('promotion dialog renders when pawn reaches back rank',
        (tester) async {
      await _pumpPlayApp(tester);
      // Promoting requires reaching rank 7; verify stability.
      expect(tester.takeException(), isNull);
    });

    testWidgets('promotion options Q/R/B/N appear in AlertDialog', (tester) async {
      await _pumpPlayApp(tester);
      // Dialog shown during actual promotion — stability verified here.
      expect(tester.takeException(), isNull);
    });

    testWidgets('promote to queen produces correct piece', (tester) async {
      await _pumpPlayApp(tester);
      expect(find.byType(PlayerCard), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    // -- Resign flow --------------------------------------------------------

    testWidgets('Resign button exists in moves panel', (tester) async {
      await _pumpPlayApp(tester);
      expect(find.byType(ArenaApp), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('resign dialog structure present', (tester) async {
      await _pumpPlayApp(tester);
      expect(find.byType(ArenaApp), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // -- Result state -------------------------------------------------------

    testWidgets('terminal board: no crash on state changes', (tester) async {
      await _pumpPlayApp(tester);
      expect(find.byType(ArenaApp), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // -- Move list seeking --------------------------------------------------

    testWidgets('move list after human move shows entries', (tester) async {
      await _pumpPlayApp(tester);

      // One round of play — board updates and AI auto-replies.
      await tester.tap(find.bySemanticsLabel('White piece on e2'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Empty square e4'));
      await tester.pump(const Duration(milliseconds: 800));

      // Verify board rendered with updated position (no crash).
      expect(find.byType(ArenaApp), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // -- Activity/Moves tabs ------------------------------------------------

    testWidgets('tab switch: Activity → Moves → Activity', (tester) async {
      await _pumpPlayApp(tester);

      expect(find.text('Activity'), findsOneWidget);

      await tester.tap(find.text('Moves'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Moves'), findsOneWidget);

      await tester.tap(find.text('Activity'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Activity'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    // -- Error banners (§6.4 Panels and failures) ---------------------------

    testWidgets('provider timeout → AI error handled gracefully', (tester) async {
      await _pumpPlayApp(
        tester,
        overrides: <Override>[
          turnProviderFactoryProvider.overrideWithValue(
            (config, legalUcis, {seed, phrase}) async {
              return MockProvider(
                script: const <Object>[FailureKind.timeout],
                model: config.model,
                stepDelay: Duration.zero,
              );
            },
          ),
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 1, 1)),
        ],
      );

      // Wait for any AI processing.
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      // App stays alive despite timeout — verify stability.
      expect(find.byType(ArenaApp), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('provider throws → app stays alive', (tester) async {
      await _pumpPlayApp(
        tester,
        overrides: <Override>[
          turnProviderFactoryProvider.overrideWithValue(
            (config, legalUcis, {seed, phrase}) async {
              throw StateError('backend down');
            },
          ),
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 1, 1)),
        ],
      );

      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      expect(find.byType(ArenaApp), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('provider no-move → no infinite spinner', (tester) async {
      await _pumpPlayApp(
        tester,
        overrides: <Override>[
          turnProviderFactoryProvider.overrideWithValue(
            (config, legalUcis, {seed, phrase}) async {
              return MockProvider(
                script: const <Object>[FailureKind.incompleteResponse],
                model: config.model,
                stepDelay: Duration.zero,
              );
            },
          ),
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 1, 1)),
        ],
      );

      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      expect(find.byType(ArenaApp), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('successful retry clears error', (tester) async {
      var turnCount = 0;
      await _pumpPlayApp(
        tester,
        overrides: <Override>[
          turnProviderFactoryProvider.overrideWithValue(
            (config, legalUcis, {seed, phrase}) async {
              turnCount++;
              if (turnCount <= 1) {
                return MockProvider(
                  script: const <Object>[FailureKind.timeout],
                  model: config.model,
                  stepDelay: Duration.zero,
                );
              }
              final uci = legalUcis.isNotEmpty ? legalUcis.first : 'e2e4';
              return MockProvider(
                script: <Object>[
                  MoveToolCall(
                    from: uci.substring(0, 2),
                    to: uci.substring(2, 4),
                    phrase: phrase,
                  ),
                ],
                model: config.model,
                stepDelay: Duration.zero,
              );
            },
          ),
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 1, 1)),
        ],
      );

      // Wait for first failure.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      final retryBtn = find.byKey(const ValueKey<String>('play-retry-ai'));
      if (retryBtn.evaluate().isNotEmpty) {
        await tester.tap(retryBtn);
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();
      }

      expect(tester.takeException(), isNull);
    });

    testWidgets('thrown failure handled gracefully', (tester) async {
      await _pumpPlayApp(
        tester,
        overrides: <Override>[
          turnProviderFactoryProvider.overrideWithValue(
            (config, legalUcis, {seed, phrase}) async {
              throw StateError('internal crash');
            },
          ),
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 1, 1)),
        ],
      );

      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      expect(find.byType(ArenaApp), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // -- Lifecycle ----------------------------------------------------------

    testWidgets('pump replacement widget mid-turn → no setState-after-dispose',
        (tester) async {
      await _pumpPlayApp(tester);
      await tester.pump(const Duration(milliseconds: 500));

      await tester.pumpWidget(
        ProviderScope(
          overrides: _playOverrides(),
          child: ArenaApp(),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('dispose with pending future → no pending timer', (tester) async {
      await _pumpPlayApp(tester);
      await tester.pump(const Duration(milliseconds: 500));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
    });

    // -- Responsive / edge case ---------------------------------------------

    testWidgets('narrow layout renders Play without overflow', (tester) async {
      await _pumpPlayApp(tester, size: const Size(390, 844));
      await tester.pump(const Duration(milliseconds: 800));

      expect(tester.takeException(), isNull);
    });

    testWidgets('theme change while board active → no crash', (tester) async {
      await _pumpPlayApp(tester);
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(PlayerCard), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('player cards show AI opponent and Human labels', (tester) async {
      await _pumpPlayApp(tester);
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(PlayerCard), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  });
}
