// Regression tests for the Elo service: zero-sum logistic updates, the
// provisional (minGames) gate, snapshot round-trips, and version refusal.
//
// Pure Dart, deterministic (no wall-clock dependence beyond history stamps).
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/arena/elo.dart';

void main() {
  group('update math', () {
    test('expectedScore is the standard logistic curve', () {
      expect(EloService.expectedScore(2000, 2000), closeTo(0.5, 1e-12));
      // A 400-point edge is ~10:1 odds.
      expect(EloService.expectedScore(1800, 1400), closeTo(1 / 1.1, 1e-9));
    });

    test('a win against a known gap matches the logistic expectation',
        () {
      final service = EloService.fromJson(<String, Object?>{
        'version': eloSnapshotVersion,
        'standard': <String, Object?>{'a': 1600.0, 'b': 1400.0},
      });
      final expectedWhite = EloService.expectedScore(1600, 1400);
      final applied =
          service.updateAfterGame('a', 'b', 'white_win', kFactor: 32);
      expect(applied, isTrue);
      expect(service.ratingFor('a', 'standard'),
          closeTo(1600 + 32 * (1 - expectedWhite), 1e-9));
      expect(service.ratingFor('b', 'standard'),
          closeTo(1400 + 32 * (0 - (1 - expectedWhite)), 1e-9));
      expect(service.gamesFor('a', 'standard'), 1);
      expect(service.gamesFor('b', 'standard'), 1);
    });

    test('every update is zero-sum', () {
      final service = EloService(initialRating: 1500);
      final aBefore = service.ratingFor('a', 'standard');
      final bBefore = service.ratingFor('b', 'standard');
      service.updateAfterGame('a', 'b', 'draw', kFactor: 40);
      final aDelta = service.ratingFor('a', 'standard') - aBefore;
      final bDelta = service.ratingFor('b', 'standard') - bBefore;
      expect(aDelta + bDelta, closeTo(0, 1e-9));
    });

    test('minGames gate counts the game but holds provisional ratings', () {
      final service = EloService();
      final first =
          service.updateAfterGame('a', 'b', 'white_win', minGames: 1);
      expect(first, isFalse, reason: 'provisional ratings must not move');
      expect(service.ratingFor('a', 'standard'), 1500);
      expect(service.ratingFor('b', 'standard'), 1500);
      expect(service.gamesFor('a', 'standard'), 1);
      // Second game: both sides now have 1 game, so the update applies.
      final second =
          service.updateAfterGame('a', 'b', 'white_win', minGames: 1);
      expect(second, isTrue);
      expect(service.ratingFor('a', 'standard'), greaterThan(1500));
    });

    test('history retention is bounded by maxHistory', () {
      final service = EloService(maxHistory: 2);
      for (var i = 0; i < 5; i++) {
        service.updateAfterGame('a', 'b', 'draw');
      }
      expect(service.history.length, 2);
    });
  });

  group('snapshot round-trip', () {
    test('toJson/fromJson restores ladders, counters and history', () {
      final original = EloService();
      original.updateAfterGame('a', 'b', 'white_win', mode: 'standard');
      original.updateAfterGame('b', 'a', 'black_win', mode: 'chaotic');
      original.updateAfterGame('a', 'b', 'draw', mode: 'chaotic');

      final snapshot = original.toJson();
      expect(snapshot['version'], eloSnapshotVersion);

      final restored = EloService.fromJson(snapshot);
      for (final mode in <String>['standard', 'chaotic']) {
        for (final key in <String>['a', 'b']) {
          expect(restored.ratingFor(key, mode),
              closeTo(original.ratingFor(key, mode), 1e-12),
              reason: '$key/$mode rating preserved');
          expect(restored.gamesFor(key, mode), original.gamesFor(key, mode));
        }
      }
      expect(restored.history.length, original.history.length);
      expect(restored.history.first.toJson(), original.history.first.toJson());
      expect(restored.history.last.toJson(), original.history.last.toJson());
    });

    test('fromJson refuses an unknown/absent version', () {
      expect(
        () => EloService.fromJson(<String, Object?>{'version': 999}),
        throwsFormatException,
      );
      expect(
        () => EloService.fromJson(const <String, Object?>{}),
        throwsFormatException,
      );
    });
  });
}
