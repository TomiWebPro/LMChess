// Regression tests for the deterministic chess clock and the game-level
// result contract:
//   * TimeControl.none clocks never charge and never flag (the untimed-game
//     first-turn false-flag regression),
//   * fixed clocks charge elapsed time and go negative on overrun,
//   * GameResult outcome/winner consistency is enforced.
//
// No network, no real timers beyond the orchestrator's own Stopwatch.
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/agent/agent_config.dart';
import 'package:llm_chess_arena/src/chess/position.dart';
import 'package:llm_chess_arena/src/game/clock.dart';
import 'package:llm_chess_arena/src/game/game_state.dart';
import 'package:llm_chess_arena/src/game/orchestrator.dart';
import 'package:llm_chess_arena/src/llm/mock_provider.dart';
import 'package:llm_chess_arena/src/llm/provider.dart';
import 'package:llm_chess_arena/src/llm/tool_schema.dart';

void main() {
  group('TimeControl.none clock', () {
    test('consume does not change remaining time', () {
      final clock = ChessClock.fromTimeControl(const TimeControl.none());
      expect(clock.remainingW, 0);
      expect(clock.remainingB, 0);
      clock.consume('w', 123456);
      clock.consume('b', 999999);
      expect(clock.remaining('w'), 0);
      expect(clock.remaining('b'), 0);
    });

    test('isFlagged is always false, even with negative remaining time', () {
      final clock = ChessClock.fromTimeControl(const TimeControl.none());
      expect(clock.isFlagged('w'), isFalse);
      expect(clock.isFlagged('b'), isFalse);
      // Defensive: even a hand-built negative snapshot must not flag.
      final negative = ChessClock(
        remainingW: -5000,
        remainingB: -1,
        controlType: TimeControlType.none,
      );
      expect(negative.isFlagged('w'), isFalse);
      expect(negative.isFlagged('b'), isFalse);
    });

    test('an untimed game does not flag on the first AI turn', () async {
      const white = AgentConfig(
        id: 'clock-white',
        name: 'Clock White',
        providerId: ProviderId.mock,
        model: 'mock',
      );
      final engine = Position.initial();
      final orch = GameOrchestrator(
        config: const GameConfig(), // defaults to TimeControl.none()
        white: const GameParticipant(
          agentConfigId: 'clock-white',
          label: 'Clock White',
          isHuman: false,
        ),
        black: const GameParticipant(label: 'You', isHuman: true),
        initialLegalMoves:
            engine.legalMoves().map((m) => m.uci).toList(),
      );
      orch.bindAgent(white);
      expect(orch.startGame(), isTrue);

      final result = await orch.requestAiTurn(
        'w',
        providerOverride: MockProvider(
          script: <Object>[
            MoveToolCall(from: 'e2', to: 'e4', phrase: 'opening'),
          ],
        ),
      );

      expect(result, isNotNull);
      expect(result!.isSuccess, isTrue,
          reason: 'untimed turn must not be adjudicated as a flag');
      expect(orch.moveHistory, contains('e2e4'));
      expect(orch.result, isNull, reason: 'game continues after a valid move');
      expect(
        orch.eventLog.any((e) => e.type == 'flagFall'),
        isFalse,
        reason: 'TimeControl.none can never flag',
      );
      expect(orch.clock.isFlagged('w'), isFalse);
      expect(orch.clock.remaining('w'), 0);
    });
  });

  group('fixed-time clock', () {
    test('consume charges the elapsed time to the right side', () {
      final clock = ChessClock(remainingW: 1000, remainingB: 1000);
      clock.consume('w', 300);
      expect(clock.remaining('w'), 700);
      expect(clock.remaining('b'), 1000);
      clock.consume('b', 150);
      expect(clock.remaining('b'), 850);
    });

    test('overrun goes negative and flags', () {
      final clock = ChessClock(remainingW: 1000, remainingB: 1000);
      clock.consume('w', 1500);
      expect(clock.remaining('w'), -500);
      expect(clock.isFlagged('w'), isTrue);
      expect(clock.isFlagged('b'), isFalse);
    });

    test('delay grants free time and increment adds back', () {
      final delay = ChessClock(remainingW: 1000, remainingB: 1000);
      delay.consume('w', 50, delayMs: 100);
      expect(delay.remaining('w'), 1000, reason: 'within delay: free');

      final increment = ChessClock(remainingW: 1000, remainingB: 1000);
      increment.consume('w', 300, incrementMs: 100);
      expect(increment.remaining('w'), 800);
    });
  });

  group('game result consistency', () {
    test('decisive outcomes require the matching winner', () {
      expect(GameResult.isConsistent('1-0', 'w'), isTrue);
      expect(GameResult.isConsistent('1-0', 'b'), isFalse);
      expect(GameResult.isConsistent('1-0', null), isFalse);
      expect(GameResult.isConsistent('0-1', 'b'), isTrue);
      expect(GameResult.isConsistent('0-1', 'w'), isFalse);
    });

    test('draw/undecided outcomes require no winner', () {
      expect(GameResult.isConsistent('1/2-1/2', null), isTrue);
      expect(GameResult.isConsistent('*', null), isTrue);
      expect(GameResult.isConsistent('1/2-1/2', 'w'), isFalse);
      expect(GameResult.isConsistent('*', 'b'), isFalse);
      // Unknown score strings are rejected outright.
      expect(GameResult.isConsistent('2-0', 'w'), isFalse);
      expect(GameResult.isConsistent('', null), isFalse);
    });

    test('the constructor asserts reject mismatches', () {
      expect(
        () => GameResult(outcome: '1-0', reason: 'checkmate'),
        throwsAssertionError,
      );
      expect(
        () => GameResult(outcome: '1-0', reason: 'checkmate', winnerColor: 'b'),
        throwsAssertionError,
      );
      expect(
        () => GameResult(
            outcome: '1/2-1/2', reason: 'maxMoves', winnerColor: 'w'),
        throwsAssertionError,
      );
    });

    test('the constructor accepts consistent results', () {
      expect(
        () => GameResult(
            outcome: '1-0', reason: 'checkmate', winnerColor: 'w'),
        returnsNormally,
      );
      expect(
        () => GameResult(outcome: '1/2-1/2', reason: 'maxMoves'),
        returnsNormally,
      );
      expect(
        () => GameResult(outcome: '*', reason: 'stopped'),
        returnsNormally,
      );
    });
  });
}
