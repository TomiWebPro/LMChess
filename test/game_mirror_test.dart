// Behavior locks for the shared replay core used by the play, watch and
// arena pumps (`lib/src/ui/game_mirror.dart`).
//
// The three screens keep their own turn loops and post-sync hooks, but the
// move-for-move mirror replay is now one implementation. These tests pin:
//   * order and metadata (SAN, phrase, fallback attribution, FEN, trail);
//   * idempotence (a second pass applies nothing);
//   * failure handling (parse/illegal move stops at that ply, cursor stays);
//   * all three recording shapes produce the same journal from one history;
//   * buffered turns still flush with the same stats attribution.
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/agent/agent_config.dart';
import 'package:llm_chess_arena/src/agent/agent_runner.dart';
import 'package:llm_chess_arena/src/chess/fen.dart';
import 'package:llm_chess_arena/src/chess/move.dart';
import 'package:llm_chess_arena/src/chess/position.dart';
import 'package:llm_chess_arena/src/game/clock.dart';
import 'package:llm_chess_arena/src/game/game_state.dart';
import 'package:llm_chess_arena/src/game/orchestrator.dart';
import 'package:llm_chess_arena/src/llm/mock_provider.dart';
import 'package:llm_chess_arena/src/llm/provider.dart';
import 'package:llm_chess_arena/src/llm/tool_schema.dart';
import 'package:llm_chess_arena/src/llm/validation.dart';
import 'package:llm_chess_arena/src/ui/backend_bridge.dart';
import 'package:llm_chess_arena/src/ui/game_mirror.dart';

/// Per-move journal shaped like the union of the three screens' state.
class _Journal {
  final List<String> ucis = <String>[];
  final List<String> sans = <String>[];
  final List<String?> phrases = <String?>[];
  final List<bool> fallbacks = <bool>[];
  final List<String> fens = <String>[standardStartFen];
  String? lastFrom;
  String? lastTo;
  String? inCheck;
}

GameOrchestrator _newOrchestrator() {
  final engine = Position.initial();
  final orch = GameOrchestrator(
    config: const GameConfig(
      seed: 424242,
      maxMoves: 200,
      timeControl: TimeControl(
        type: TimeControlType.fixed,
        initialMs: 600000,
      ),
    ),
    white: const GameParticipant(
      agentConfigId: 'w',
      label: 'White',
      isHuman: false,
    ),
    black: const GameParticipant(
      agentConfigId: 'b',
      label: 'Black',
      isHuman: false,
    ),
    positionUpdater: fenAdvance,
  );
  orch.bindAgent(
    AgentConfig(
      id: 'w',
      name: 'White',
      providerId: ProviderId.mock,
      model: 'mock-white',
    ),
  );
  orch.bindAgent(
    AgentConfig(
      id: 'b',
      name: 'Black',
      providerId: ProviderId.mock,
      model: 'mock-black',
    ),
  );
  orch.setPosition(
    standardStartFen,
    turn: 'w',
    legalMoves: _legalUcis(engine),
  );
  orch.startGame();
  return orch;
}

List<String> _legalUcis(Position position) =>
    position.legalMoves().map((m) => m.uci).toList();

/// Plays [uci] through the orchestrator with a scripted mock provider and
/// advances [driver] so the next turn sees a fresh legal list.
Future<void> _play(
  GameOrchestrator orch,
  Position driver,
  String uci, {
  String? phrase,
}) async {
  final move = ChessMove.fromUci(uci);
  final provider = MockProvider(
    script: <Object>[
      MoveToolCall(
        from: move.from.name,
        to: move.to.name,
        promotion: move.promotion?.letter,
        phrase: phrase,
      ),
    ],
    model: 'mock',
  );
  final turn = orch.turn;
  final result = await orch.requestAiTurn(turn, providerOverride: provider);
  expect(result, isNotNull, reason: 'turn must not be rejected');
  expect(orch.moveHistory.last, uci);
  driver.apply(move);
  orch.setPosition(
    driver.toFen(),
    turn: driver.sideToMove.isWhite ? 'w' : 'b',
    legalMoves: _legalUcis(driver),
  );
}

/// Records the play/watch shape (they differ only in list names).
void _recordSimple(
  _Journal journal,
  Position engine,
  int index,
  String uci,
  ChessMove move,
  AppliedMove receipt,
  AppliedMoveMeta meta,
) {
  journal.ucis.add(uci);
  journal.sans.add(receipt.san);
  journal.phrases.add(meta.isFallback ? null : meta.phrase);
  journal.fallbacks.add(meta.isFallback);
  journal.fens.add(engine.toFen());
  journal.lastFrom = move.from.name;
  journal.lastTo = move.to.name;
}

/// Records the arena shape (adds the live check snapshot).
void _recordArena(
  _Journal journal,
  Position engine,
  int index,
  String uci,
  ChessMove move,
  AppliedMove receipt,
  AppliedMoveMeta meta,
) {
  _recordSimple(journal, engine, index, uci, move, receipt, meta);
  journal.inCheck = checkSquare(engine);
}

void main() {
  group('replayMoves', () {
    test('applies in order with SAN, phrases, FENs and last-move trail',
        () async {
      final orch = _newOrchestrator();
      final driver = Position.initial();
      await _play(orch, driver, 'e2e4', phrase: 'opening');
      await _play(orch, driver, 'e7e5', phrase: 'reply');

      final engine = Position.initial();
      final journal = _Journal();
      final result = replayMoves(
        orch: orch,
        engine: engine,
        applied: 0,
        onApplied: (index, uci, move, receipt, meta) =>
            _recordSimple(journal, engine, index, uci, move, receipt, meta),
      );

      expect(result.error, isNull);
      expect(result.applied, 2);
      expect(result.changed, isTrue);
      expect(journal.ucis, <String>['e2e4', 'e7e5']);
      expect(journal.sans, <String>['e4', 'e5']);
      expect(journal.phrases, <String?>['opening', 'reply']);
      expect(journal.fallbacks, <bool>[false, false]);
      expect(journal.fens, hasLength(3));
      expect(journal.fens.last, engine.toFen());
      expect(journal.lastFrom, 'e7');
      expect(journal.lastTo, 'e5');
    });

    test('is idempotent from the returned cursor', () async {
      final orch = _newOrchestrator();
      final driver = Position.initial();
      await _play(orch, driver, 'e2e4');

      final engine = Position.initial();
      final first = _Journal();
      final initial = replayMoves(
        orch: orch,
        engine: engine,
        applied: 0,
        onApplied: (index, uci, move, receipt, meta) =>
            _recordSimple(first, engine, index, uci, move, receipt, meta),
      );

      final second = _Journal();
      final again = replayMoves(
        orch: orch,
        engine: engine,
        applied: initial.applied,
        onApplied: (index, uci, move, receipt, meta) =>
            _recordSimple(second, engine, index, uci, move, receipt, meta),
      );

      expect(again.error, isNull);
      expect(again.changed, isFalse);
      expect(again.applied, initial.applied);
      expect(second.ucis, isEmpty);
      expect(second.fens, <String>[standardStartFen]);
    });

    test('stops at the first unappliable ply and leaves the cursor behind',
        () async {
      final orch = _newOrchestrator();
      final driver = Position.initial();
      await _play(orch, driver, 'e2e4');

      // Same UCI parses, but this mirror has no pawn on e2.
      final engine = parseFen('4k3/8/8/8/8/8/8/4K3 w - - 0 1');
      var recorded = 0;
      final result = replayMoves(
        orch: orch,
        engine: engine,
        applied: 0,
        onApplied: (index, uci, move, receipt, meta) => recorded++,
      );

      expect(result.error, isNotNull);
      expect(result.failedUci, 'e2e4');
      expect(result.applied, 0);
      expect(result.changed, isFalse);
      expect(recorded, 0);
    });

    test('one core serves the play/watch/arena recording shapes', () async {
      final orch = _newOrchestrator();
      final driver = Position.initial();
      await _play(orch, driver, 'e2e4', phrase: 'opening');
      await _play(orch, driver, 'e7e5', phrase: 'reply');

      final playEngine = Position.initial();
      final play = _Journal();
      replayMoves(
        orch: orch,
        engine: playEngine,
        applied: 0,
        onApplied: (index, uci, move, receipt, meta) =>
            _recordSimple(play, playEngine, index, uci, move, receipt, meta),
      );

      final watchEngine = Position.initial();
      final watch = _Journal();
      replayMoves(
        orch: orch,
        engine: watchEngine,
        applied: 0,
        onApplied: (index, uci, move, receipt, meta) =>
            _recordSimple(watch, watchEngine, index, uci, move, receipt, meta),
      );

      final arenaEngine = Position.initial();
      final arena = _Journal();
      replayMoves(
        orch: orch,
        engine: arenaEngine,
        applied: 0,
        onApplied: (index, uci, move, receipt, meta) =>
            _recordArena(arena, arenaEngine, index, uci, move, receipt, meta),
      );

      expect(play.sans, watch.sans);
      expect(play.sans, arena.sans);
      expect(play.phrases, watch.phrases);
      expect(play.fallbacks, watch.fallbacks);
      expect(play.fens, watch.fens);
      expect(arena.ucis, orch.moveHistory);
      expect(arena.fens, play.fens);
      expect(arena.lastFrom, play.lastFrom);
      expect(arena.lastTo, play.lastTo);
    });

    test('a forced provider failure is recorded as an unattributed fallback',
        () async {
      final orch = _newOrchestrator();
      final before = orch.moveHistory.length;
      final provider = MockProvider(
        script: const <Object>[
          FailureKind.timeout,
          FailureKind.timeout,
          FailureKind.timeout,
          FailureKind.timeout,
        ],
        model: 'mock',
      );
      final turn = orch.turn;
      final turnResult = await orch.requestAiTurn(
        turn,
        providerOverride: provider,
      );

      expect(turnResult, isNotNull);
      expect(orch.moveHistory.length, before + 1,
          reason: 'the seeded fallback must still play a move');
      expect(orch.fallbackRecords, isNotEmpty);

      final engine = Position.initial();
      final journal = _Journal();
      final replay = replayMoves(
        orch: orch,
        engine: engine,
        applied: 0,
        onApplied: (index, uci, move, receipt, meta) =>
            _recordSimple(journal, engine, index, uci, move, receipt, meta),
      );

      expect(replay.error, isNull);
      expect(journal.fallbacks.single, isTrue);
      expect(journal.phrases.single, isNull,
          reason: 'fallbacks are never attributed to the agent');
    });
  });

  group('per-turn stats buffering', () {
    test('flush keeps clean and fallback turns distinct', () {
      final log = StatsLog();

      PendingTurn.human().flush(log: log, gameId: 'lock-game');
      const failed = AgentTurnResult(
        outcome: ValidationOutcome(
          kind: FailureKind.timeout,
          error: 'attempt deadline exceeded',
        ),
        events: <LlmStreamEvent>[],
        latencyMs: 12,
      );
      PendingTurn.ai(
        agentId: 'agent-a',
        modelKey: 'mock-a',
        color: 'black',
        mode: 'standard',
        result: failed,
        fallback: true,
      ).flush(log: log, gameId: 'lock-game');

      final records = log.records;
      expect(records, hasLength(2));
      expect(records[0].type, 'turn.completed');
      expect(records[0].payloadJson['agentId'], 'human');
      expect(records[0].payloadJson['legal'], isTrue);
      expect(records[1].type, 'turn.fallback');
      expect(records[1].payloadJson['fallback'], isTrue);
      expect(records[1].payloadJson['timeout'], isTrue);
      expect(records[1].payloadJson['agentId'], 'agent-a');
    });
  });
}
