// Regression tests for the orchestrator -> metrics contract.
//
// Drives a short real game through [GameOrchestrator] and feeds the ACTUAL
// emitted event payloads into [AgentMetrics.compute], asserting:
//   * attribution works for both `agentId` and the legacy `agentConfigId`
//     alias,
//   * compact/full colors (`w`/`white`, `b`/`black`) collapse correctly,
//   * one AI turn emits many auxiliary events but only ONE `countAsTurn:true`
//     summary, so the turns denominator counts turns, not events.
//
// No network (mock provider), no real timers beyond mock step delays.
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/agent/agent_config.dart';
import 'package:llm_chess_arena/src/chess/fen.dart';
import 'package:llm_chess_arena/src/chess/move.dart';
import 'package:llm_chess_arena/src/chess/position.dart';
import 'package:llm_chess_arena/src/game/game_state.dart';
import 'package:llm_chess_arena/src/game/orchestrator.dart';
import 'package:llm_chess_arena/src/llm/mock_provider.dart';
import 'package:llm_chess_arena/src/llm/provider.dart';
import 'package:llm_chess_arena/src/llm/tool_schema.dart';
import 'package:llm_chess_arena/src/stats/event_log.dart';
import 'package:llm_chess_arena/src/stats/metrics.dart';

List<String> _legalUcis(Position position) =>
    position.legalMoves().map((m) => m.uci).toList();

GameEventRecord _record(
  int seq,
  Map<String, Object?> payload, {
  String type = 'turnSummary',
}) =>
    GameEventRecord(
      key: 'k$seq',
      gameId: 'game-1',
      seq: seq,
      type: type,
      payloadJson: payload,
      createdAt: DateTime.utc(2026, 1, 1),
    );

Future<List<GameEventRecord>> _runTwoTurnGame() async {
  const white = AgentConfig(
    id: 'white-1',
    name: 'White One',
    providerId: ProviderId.mock,
    model: 'mock-1',
  );
  const black = AgentConfig(
    id: 'black-1',
    name: 'Black One',
    providerId: ProviderId.mock,
    model: 'mock-1',
  );
  final engine = Position.initial();
  final orch = GameOrchestrator(
    config: const GameConfig(),
    white: const GameParticipant(
      agentConfigId: 'white-1',
      label: 'White One',
      isHuman: false,
    ),
    black: const GameParticipant(
      agentConfigId: 'black-1',
      label: 'Black One',
      isHuman: false,
    ),
    initialLegalMoves: _legalUcis(engine),
  );
  orch.bindAgent(white);
  orch.bindAgent(black);
  orch.startGame();

  await orch.requestAiTurn(
    'w',
    providerOverride: MockProvider(
      script: <Object>[
        MoveToolCall(from: 'e2', to: 'e4', phrase: 'king pawn'),
      ],
    ),
  );
  engine.apply(ChessMove.fromUci(orch.moveHistory.last));
  orch.setPosition(
    engine.toFen(),
    turn: 'b',
    legalMoves: _legalUcis(engine),
  );

  await orch.requestAiTurn(
    'b',
    providerOverride: MockProvider(
      script: <Object>[MoveToolCall(from: 'e7', to: 'e5')],
    ),
  );

  return <GameEventRecord>[
    for (final event in orch.eventLog)
      GameEventRecord(
        key: event.idempotencyKey,
        gameId: 'game-1',
        seq: event.seq,
        type: event.type,
        payloadJson: event.payload,
        createdAt: event.timestamp,
      ),
  ];
}

void main() {
  group('orchestrator turnSummary feeds AgentMetrics', () {
    test('both agents get non-empty aggregates from real event payloads',
        () async {
      final records = await _runTwoTurnGame();
      final metrics = AgentMetrics.compute(records);

      final white = metrics['white-1'];
      final black = metrics['black-1'];
      expect(white, isNotNull);
      expect(black, isNotNull);

      expect(white!.turns, 1);
      expect(black!.turns, 1);
      expect(white.validToolRate, 1.0);
      expect(black.validToolRate, 1.0);
      expect(white.legalRate, 1.0);
      expect(black.legalRate, 1.0);
      expect(white.parsedMoves, 1);
      expect(white.byColor['white'], 1);
      expect(black.byColor['black'], 1);
      expect(white.byMode['standard'], 1);
    });

    test('a turn emits many events but counts as ONE turn', () async {
      final records = await _runTwoTurnGame();

      final whiteEvents =
          records.where((r) => r.payloadJson['agentId'] == 'white-1').toList();
      expect(whiteEvents.length, greaterThan(1),
          reason: 'auxiliary events (aiTurnStarted/aiStream/moveApplied) '
              'must be more numerous than turns');
      // Exactly one turn-summary per turn.
      final summaries = whiteEvents
          .where((r) => r.payloadJson['countAsTurn'] == true)
          .toList();
      expect(summaries.length, 1);
      // Every other attributed event opts out of turn counting.
      for (final event in whiteEvents) {
        if (event.type == 'turnSummary') continue;
        expect(event.payloadJson['countAsTurn'], isFalse,
            reason: '${event.type} must not inflate the turns denominator');
      }

      final metrics = AgentMetrics.compute(records);
      expect(metrics['white-1']!.turns, 1,
          reason: 'turns counts turns, not events');
      // AiStream carries usage tokens; they must still be aggregated even
      // though the events do not count as turns.
      expect(metrics['white-1']!.inputTokens, greaterThan(0));
    });

    test('turnSummary carries agentId AND the agentConfigId alias', () async {
      final records = await _runTwoTurnGame();
      final summary = records
          .firstWhere((r) => r.type == 'turnSummary' &&
              r.payloadJson['agentId'] == 'white-1');
      expect(summary.payloadJson['agentId'], 'white-1');
      expect(summary.payloadJson['agentConfigId'], 'white-1');
      expect(summary.payloadJson['color'], 'w');
      expect(summary.payloadJson['colorName'], 'white');
    });

    test('legacy agentConfigId alias alone still attributes a turn', () {
      final metrics = AgentMetrics.compute(<GameEventRecord>[
        _record(0, const <String, Object?>{
          'agentConfigId': 'legacy-1',
          'color': 'w',
          'legal': true,
        }),
      ]);
      final legacy = metrics['legacy-1'];
      expect(legacy, isNotNull);
      expect(legacy!.turns, 1);
      expect(legacy.byColor['white'], 1);
    });
  });

  group('color normalization', () {
    test('w/white and b/black collapse into canonical buckets', () {
      final metrics = AgentMetrics.compute(<GameEventRecord>[
        _record(0, const {'agentId': 'c1', 'color': 'w'}),
        _record(1, const {'agentId': 'c1', 'color': 'white'}),
        _record(2, const {'agentId': 'c1', 'color': 'b'}),
        _record(3, const {'agentId': 'c1', 'color': 'black'}),
        _record(4, const {'agentId': 'c1', 'color': 'WHITE'}),
      ]);
      final c1 = metrics['c1']!;
      expect(c1.turns, 5);
      expect(c1.byColor['white'], 3);
      expect(c1.byColor['black'], 2);
    });
  });

  group('turn denominator', () {
    test('countAsTurn:false auxiliary events never bump turns', () {
      final metrics = AgentMetrics.compute(<GameEventRecord>[
        _record(0, const {'agentId': 'm1', 'countAsTurn': false}),
        _record(1, const {'agentId': 'm1', 'countAsTurn': false}),
        _record(2, const {'agentId': 'm1', 'countAsTurn': false}),
        _record(3, const <String, Object?>{
          'agentId': 'm1',
          'countAsTurn': true,
          'color': 'w',
          'legal': true,
        }),
      ]);
      expect(metrics['m1']!.turns, 1);
      expect(metrics['m1']!.legalRate, 1.0);
    });
  });
}
