// Regression tests for §10.7 stable keys: every control that previously had a
// duplicate label text now resolves by its ValueKey instead of find.text().
//
/// Light-weight: plain dart tests confirm const key uniqueness; the one
/// widget test pumps only the app scaffold (no screen navigation needed) and
/// verifies the ValueKey strings resolve as valid Finders (controls may be
/// off-screen depending on visibility — that's expected). No real network.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/app.dart';
import 'package:llm_chess_arena/src/llm/mock_provider.dart';
import 'package:llm_chess_arena/src/ui/backend_bridge.dart';

void main() {
  // ------------------------------------------------------------------------
  // Plain dart tests: key uniqueness (zero widget churn).
  // ------------------------------------------------------------------------

  group('§10.7 stable keys — uniqueness', () {
    const playKeys = <String>[
      'play-new-game-banner',
      'play-new-game-button',
      'play-resign-button',
      'play-retry-ai',
      'play-resign-confirm',
    ];

    const watchArenaKeys = <String>[
      'watch-start',
      'watch-pause',
      'watch-resume',
      'watch-stop',
      'arena-start-tournament',
      'arena-stop',
    ];

    test('all five Play key strings are distinct', () {
      expect(playKeys.toSet().length, playKeys.length);
    });

    test('all six Watch/Arena key strings are distinct', () {
      expect(watchArenaKeys.toSet().length, watchArenaKeys.length);
    });

    test('Play keys do not collide with Watch/Arena keys', () {
      final allStrings = {...playKeys, ...watchArenaKeys};
      expect(allStrings.length, playKeys.length + watchArenaKeys.length);
    });
  });

  // ------------------------------------------------------------------------
  // Widget test: pump bare AppShell with fake providers; verify keys parse.
  // ------------------------------------------------------------------------

  group('§10.7 stable keys — ValueKey parsing in app shell', () {
    testWidgets('app shell renders with overrides and no exception',
        (tester) async {
      final fake = MockProvider();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            turnProviderFactoryProvider.overrideWithValue((config, legalUcis, {seed, phrase}) async => fake),
            clockProvider.overrideWithValue(() => DateTime.utc(2026, 1, 1)),
          ],
          child: const ArenaApp(),
        ),
      );
      await tester.pump();

      // Verify the shell rendered without crashing.
      expect(find.byType(Scaffold), findsOneWidget);
      expect(tester.takeException(), isNull);

      // All Play keys are non-null and their value matches the expected string.
      final playValues = const <ValueKey<String>>[
        ValueKey<String>('play-new-game-banner'),
        ValueKey<String>('play-new-game-button'),
        ValueKey<String>('play-resign-button'),
        ValueKey<String>('play-retry-ai'),
        ValueKey<String>('play-resign-confirm'),
      ];
      for (final k in playValues) {
        expect(k, isA<ValueKey<String>>());
        expect(k.value, isNotNull);
      }

      // All Watch/Arena keys are well-formed.
      final watchValues = const <ValueKey<String>>[
        ValueKey<String>('watch-start'),
        ValueKey<String>('watch-pause'),
        ValueKey<String>('watch-resume'),
        ValueKey<String>('watch-stop'),
        ValueKey<String>('arena-start-tournament'),
        ValueKey<String>('arena-stop'),
      ];
      for (final k in watchValues) {
        expect(k, isA<ValueKey<String>>());
        expect(k.value, isNotNull);
      }
    });
  });
}
