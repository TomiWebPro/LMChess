// Robustness regressions for failure paths that previously threw the wrong
// exception type, stalled forever, or relied on debug-only asserts.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/arena/elo.dart';
import 'package:llm_chess_arena/src/arena/export.dart';
import 'package:llm_chess_arena/src/arena/scheduler.dart';
import 'package:llm_chess_arena/src/arena/tournament.dart';
import 'package:llm_chess_arena/src/variant/variant_board.dart';

/// Game factory whose future never settles (stalled provider/engine).
class _NeverFactory implements GameFactory {
  @override
  Future<GameResultSummary> runSingleGame(Pairing pairing, int seed) =>
      Completer<GameResultSummary>().future;
}

void main() {
  group('arena scheduler', () {
    test('rejects a degenerate roster with ArgumentError, not an assert', () {
      expect(
        () => ArenaScheduler.generatePairings(
          agentIds: const <String>['solo'],
          totalGames: 1,
          alternateColors: true,
        ),
        throwsArgumentError,
      );
      expect(
        () => ArenaScheduler.generatePairings(
          agentIds: const <String>['a', 'b'],
          totalGames: 0,
          alternateColors: true,
        ),
        throwsArgumentError,
      );
    });

    test('a never-settling game is failed by the wall-clock budget', () async {
      final config = TournamentConfig(
        id: 'timeout-tournament',
        name: 'Timeout',
        agentIds: const <String>['a', 'b'],
        games: 1,
      );
      final state = ArenaScheduler.generateSchedule(config);
      final scheduler = ArenaScheduler(
        state: state,
        gameFactory: _NeverFactory(),
        gameTimeout: const Duration(milliseconds: 20),
      );

      final finished = await scheduler.run();
      expect(finished.games.single.status, TournamentGameStatus.failed);
      expect(finished.games.single.error, contains('wall-clock'));
    });
  });

  group('corrupt JSON never surfaces as TypeError', () {
    test('TournamentGameRef.fromJson rejects mistyped fields', () {
      expect(
        () => TournamentGameRef.fromJson(const <String, Object?>{
          'gameId': 7,
          'whiteAgentId': 'a',
          'blackAgentId': 'b',
          'status': 'pending',
        }),
        throwsFormatException,
      );
    });

    test('parseTournamentExport rejects a mistyped config', () {
      expect(
        () => parseTournamentExport(<String, Object?>{
          'schemaVersion': tournamentExportSchemaVersion,
          'exportedAt': '2026-01-01T00:00:00Z',
          'tournament': <String, Object?>{
            'config': 3,
            'games': <Object?>[],
          },
          'events': <Object?>[],
        }),
        throwsFormatException,
      );
    });

    test('VariantBoard.fromJson rejects mistyped fields', () {
      expect(
        () => VariantBoard.fromJson(const <String, Object?>{
          'sideToMove': 42,
          'pieces': <Object?>[],
        }),
        throwsFormatException,
      );
      expect(
        () => VariantBoard.fromJson(const <String, Object?>{
          'sideToMove': 'w',
          'pieces': <Object?>[
            <String, Object?>{'square': 7},
          ],
        }),
        throwsFormatException,
      );
      expect(
        () => VariantBoard.fromJson(const <String, Object?>{
          'sideToMove': 'w',
          'pieces': <Object?>[],
          'castlingInvalid': 'yes',
        }),
        throwsFormatException,
      );
    });
  });

  test('a non-positive Elo maxHistory cannot crash history eviction', () {
    final service = EloService.fromJson(<String, Object?>{
      'version': eloSnapshotVersion,
      'maxHistory': -5,
    });
    expect(service.maxHistory, greaterThan(0));
    expect(
      service.updateAfterGame('white', 'black', 'white_win'),
      isTrue,
    );
    expect(service.history, isNotEmpty);
  });
}
