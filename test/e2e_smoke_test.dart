// End-to-end logic smoke — the platform loop proven without UI.
//
// Proves the platform loop works end-to-end (run: `flutter test`):
//
//   1. Standard chess: two scripted mock agents play a game through
//      [GameOrchestrator] over the real perft-verified engine, including
//      forced provider failures that must produce *recorded random-legal
//      fallbacks* (never attributed to the agent).
//   2. Chaotic chess: an illegal attempt goes through the interpretation
//      pipeline; determinism is checked for a fixed seed.
//   3. Stats: persisted events compute per-agent metrics with sane
//      denominators and idempotent appends.
//   4. Stockfish: the embedded binary (explicit path here) handshakes and
//      evaluates a real position with `source == 'stockfish-uci'`.
//   5. WintrReviewService: a short real game produces a report with
//      per-move quality and key moments.
//
// Runs under `flutter test` because [GameOrchestrator] is a Flutter
// `ChangeNotifier` (plain `dart run` cannot load dart:ui). The Stockfish
// section skips gracefully when the platform binary is absent.
//
// GPLv3 note: imports GPLv3 project code (Stockfish adapter bounds,
// WintrChess-derived review module) — same license as the application.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/agent/agent_config.dart';
import 'package:llm_chess_arena/src/chess/engine.dart' as chess_eng;
import 'package:llm_chess_arena/src/chess/fen.dart';
import 'package:llm_chess_arena/src/chess/move.dart';
import 'package:llm_chess_arena/src/chess/piece.dart';
import 'package:llm_chess_arena/src/chess/position.dart';
import 'package:llm_chess_arena/src/chess/square.dart';
import 'package:llm_chess_arena/src/game/clock.dart';
import 'package:llm_chess_arena/src/game/game_state.dart';
import 'package:llm_chess_arena/src/game/orchestrator.dart';
import 'package:llm_chess_arena/src/llm/mock_provider.dart';
import 'package:llm_chess_arena/src/llm/provider.dart';
import 'package:llm_chess_arena/src/llm/tool_schema.dart';
import 'package:llm_chess_arena/src/llm/validation.dart';
import 'package:llm_chess_arena/src/review/engine_adapter.dart';
import 'package:llm_chess_arena/src/review/stockfish_evaluator.dart';
import 'package:llm_chess_arena/src/review/wintr_review.dart';
import 'package:llm_chess_arena/src/stats/event_log.dart';
import 'package:llm_chess_arena/src/stats/metrics.dart';
import 'package:llm_chess_arena/src/variant/chaotic_engine.dart';
import 'package:llm_chess_arena/src/variant/interpretation.dart';
import 'package:llm_chess_arena/src/variant/selection.dart';
import 'package:llm_chess_arena/src/variant/variant_board.dart';

/// Asserts [condition] via the test harness with [what] as the reason.
void check(bool condition, String what) {
  expect(condition, isTrue, reason: what);
}

/// Legal UCI moves of [position] as strings.
List<String> legalUcis(Position position) =>
    position.legalMoves().map((m) => m.uci).toList();

/// Builds a mock provider that plays one seeded-random legal move.
MockProvider scriptedMock(
  AgentConfig agent,
  List<String> legalUcis, {
  required int seed,
}) {
  final random = math.Random(seed);
  final pick = legalUcis[random.nextInt(legalUcis.length)];
  final parts = pick.split('');
  final from = '${parts[0]}${parts[1]}';
  final to = '${parts[2]}${parts[3]}';
  final promotion = parts.length > 4 ? parts[4] : null;
  return MockProvider(
    script: <Object>[
      MoveToolCall(
        from: from,
        to: to,
        promotion: promotion,
        phrase: '${agent.name} plays $pick',
      ),
    ],
    model: agent.model,
  );
}

void main() {
  test('standard game through the orchestrator', () async {
    await _standardGame();
  });

  test('chaotic interpretation pipeline', () {
    _chaoticPipeline();
  });

  test('stats from persisted events', () async {
    await _stats();
  });

  test('embedded stockfish evaluates and stays honest', () async {
    const binary = 'assets/engines/linux-x86-64/stockfish';
    if (!File(binary).existsSync()) {
      // Binary is gitignored; fetch with
      // `dart run tool/download_stockfish.dart linux-x86-64`.
      markTestSkipped('stockfish binary not present at $binary');
      return;
    }
    await _stockfish(binary);
  }, skip: !File('assets/engines/linux-x86-64/stockfish').existsSync());

  test('wintr review report', () async {
    await _review();
  });
}

/// Full legal game with one forced provider failure → visible fallback.
Future<void> _standardGame() async {
  final white = AgentConfig(
    id: 'smoke-white',
    name: 'Smoke White',
    providerId: ProviderId.mock,
    model: 'mock-1',
  );
  final black = AgentConfig(
    id: 'smoke-black',
    name: 'Smoke Black',
    providerId: ProviderId.mock,
    model: 'mock-1',
  );

  final engine = Position.initial();
  final orch = GameOrchestrator(
    config: const GameConfig(
      seed: 424242,
      maxMoves: 60,
      // A real clock: the default `TimeControl.none()` is zero-time and
      // would (correctly) flag the first mover before any move lands.
      timeControl: TimeControl(type: TimeControlType.fixed, initialMs: 600000),
    ),
    white: GameParticipant(agentConfigId: white.id, label: white.name, isHuman: false),
    black: GameParticipant(agentConfigId: black.id, label: black.name, isHuman: false),
    initialLegalMoves: legalUcis(engine),
  );
  orch.bindAgent(white);
  orch.bindAgent(black);
  orch.startGame();

  var plies = 0;
  var failuresScripted = 0;
  while (plies < 60 && !orch.state.toString().contains('finish')) {
    final turn = orch.turn; // 'w' | 'b'
    final agent = turn == 'w' ? white : black;
    // Every 7th turn, script a provider failure to exercise the fallback
    // path (retries are exhausted → random legal move recorded as fallback).
    final forceFailure = plies > 0 && plies % 7 == 3 && failuresScripted < 2;
    final LlmProvider provider;
    if (forceFailure) {
      failuresScripted++;
      provider = MockProvider(
        script: const <Object>[
          FailureKind.timeout,
          FailureKind.timeout,
          FailureKind.timeout,
          FailureKind.timeout,
        ],
        model: agent.model,
      );
    } else {
      provider = scriptedMock(agent, legalUcis(engine), seed: 424242 + plies);
    }
    final before = orch.moveHistory.length;
    final result = await orch.requestAiTurn(turn, providerOverride: provider);
    check(result != null, 'turn $plies executed (turn not rejected)');
    if (orch.moveHistory.length == before) break; // Defensive: no move applied.
    final uci = orch.moveHistory.last;
    final move = ChessMove.fromUci(uci);
    check(
      engine.legalMoves().any((m) =>
          m.from == move.from && m.to == move.to && m.promotion == move.promotion),
      'applied move $uci is legal in the mirror engine',
    );
    engine.apply(move);
    plies++;
    if (chess_eng.ChessRules.resultOf(engine) != null) {
      orch.reportTerminal(_terminalFor(orch, engine));
      break;
    }
    orch.setPosition(
      engine.toFen(),
      turn: engine.sideToMove.isWhite ? 'w' : 'b',
      legalMoves: legalUcis(engine),
    );
  }

  check(plies >= 10, 'game advanced at least 10 plies ($plies)');
  check(orch.fallbackRecords.length == failuresScripted,
      'fallbacks recorded == failures scripted '
      '(${orch.fallbackRecords.length}/$failuresScripted)');
  for (final record in orch.fallbackRecords) {
    check(record.isFallback, 'fallback record flagged isFallback');
  }
  check(orch.eventLog.isNotEmpty, 'orchestrator event log persisted');
  final keys = orch.eventLog.map((e) => e.idempotencyKey).toSet();
  check(keys.length == orch.eventLog.length, 'event idempotency keys unique');
  debugPrint('  -- game ended after $plies plies, '
      '${orch.fallbackRecords.length} fallback(s)');
}

/// Maps the chess-engine terminal to the orchestrator's result type.
GameResult _terminalFor(GameOrchestrator orch, Position position) {
  final terminal = chess_eng.ChessRules.resultOf(position)!;
  switch (terminal.termination) {
    case chess_eng.GameTermination.checkmate:
    case chess_eng.GameTermination.resignation:
    case chess_eng.GameTermination.timeout:
      final whiteWins = terminal.winner == PieceColor.white;
      return GameResult(
        outcome: whiteWins ? '1-0' : '0-1',
        reason: terminal.termination.name,
        winnerColor: whiteWins ? 'w' : 'b',
      );
    case chess_eng.GameTermination.stalemate:
    case chess_eng.GameTermination.fiftyMove:
    case chess_eng.GameTermination.insufficientMaterial:
    case chess_eng.GameTermination.agreement:
      return GameResult(
        outcome: '1/2-1/2',
        reason: terminal.termination.name,
      );
    case chess_eng.GameTermination.aborted:
      return const GameResult(outcome: '*', reason: 'aborted');
  }
}

/// Illegal attempts fan out through the interpretation registry
/// deterministically for a fixed seed.
void _chaoticPipeline() {
  final board = VariantBoard.fromStandard(Position.initial());
  const attempt = AttemptedMove(
    fromSquareName: 'e2',
    toSquareName: 'e7',
    rawToolCallJson: <String, Object?>{
      'from': 'e2',
      'to': 'e7',
      'phrase': 'Pawns, but make it long-range.',
    },
    phrase: 'Pawns, but make it long-range.',
  );

  final first = ChaoticRules.interpret(
    board,
    attempt,
    policy: SelectionPolicy.bestStrategic,
    seed: 7,
  );
  final second = ChaoticRules.interpret(
    board,
    attempt,
    policy: SelectionPolicy.bestStrategic,
    seed: 7,
  );

  check(first.wasLegal == false, 'e2e7 recognized as illegal in standard rules');
  check(first.candidates.isNotEmpty, 'at least one interpretation generated');
  check(first.selected.strategyId == second.selected.strategyId,
      'selection deterministic for fixed seed+policy');
  check(first.selected.resultingBoard.toJson().toString() ==
          second.selected.resultingBoard.toJson().toString(),
      'resulting boards identical across runs');
  debugPrint('  -- selected: ${first.selected.strategyId} '
      '(${first.candidates.length} candidates)');

  // Legal moves short-circuit (no interpretation needed).
  const legalAttempt = AttemptedMove(
    fromSquareName: 'e2',
    toSquareName: 'e4',
    rawToolCallJson: <String, Object?>{'from': 'e2', 'to': 'e4'},
  );
  final legal = ChaoticRules.interpret(board, legalAttempt);
  check(legal.wasLegal, 'e2e4 applied as a normal legal move');

  // King capture terminates the variant game: construct a board without
  // the black king (immutable map → build a fresh board from squares).
  final captureBoard = VariantBoard.fromStandard(Position.initial());
  final captureSquares = Map<Square, VariantPiece>.of(captureBoard.squares);
  captureSquares.remove(tryParseSquare('e8')!);
  final afterCapture = VariantBoard(squares: captureSquares);
  check(
    ChaoticRules.isKingCaptured(afterCapture, PieceColor.black),
    'king removal detected as capture',
  );
  final over = ChaoticRules.gameOver(afterCapture);
  check(over.over && over.winner == PieceColor.white,
      'game over with White winner after black king capture');
}

/// Persisted events → aggregate metrics with sane denominators.
Future<void> _stats() async {
  final store = InMemoryEventStore();
  const gameId = 'smoke-game';
  const turns = 11;
  for (var i = 0; i < turns; i++) {
    final fallback = i % 5 == 0;
    store.append(GameEventRecord(
      key: '$gameId:$i',
      gameId: gameId,
      seq: i,
      type: fallback ? 'fallback.randomLegal' : 'move.accepted',
      payloadJson: <String, Object?>{
        'agentId': i.isEven ? 'smoke-white' : 'smoke-black',
        'legal': !fallback,
        // Metrics convention (see metrics.dart): the boolean key is
        // `fallback`, not the orchestrator record's `isFallback`.
        'fallback': fallback,
        'latencyMs': 120 + i * 3,
        'inputTokens': 100,
        'outputTokens': 20,
      },
      createdAt: DateTime.now(),
    ));
    // Idempotency: appending the same key twice must not duplicate.
    store.append(GameEventRecord(
      key: '$gameId:$i',
      gameId: gameId,
      seq: i,
      type: 'duplicate.shouldBeIgnored',
      payloadJson: const <String, Object?>{},
      createdAt: DateTime.now(),
    ));
  }
  final events = store.listByGame(gameId);
  check(events.length == turns, 'idempotent append kept $turns unique events');

  final metrics = AgentMetrics.compute(events);
  final white = metrics['smoke-white'];
  final black = metrics['smoke-black'];
  check(white != null && black != null, 'metrics computed per agent');
  check(white!.turns + black!.turns == turns,
      'turn denominators sum to total (${white.turns}+${black.turns})');
  final whites = events
      .where((e) => e.payloadJson['agentId'] == 'smoke-white')
      .toList();
  // i = 0, 10 are fallback turns and even ⇒ White must show a rate > 0.
  final whiteFallbacks =
      whites.where((e) => e.payloadJson['fallback'] == true).length;
  check(whiteFallbacks == 2, 'white recorded 2 fallback events');
  check(white.fallbackRate > 0, 'white fallback rate ${white.fallbackRate}');
  check(white.legalRate < 1.0, 'legal rate reflects the fallbacks');
  debugPrint('  -- white turns=${white.turns} fallbacks=$whiteFallbacks');
}

/// Counts fallback markers for the print line.
int whiteFallbackCount(List<GameEventRecord> events) => events
    .where((e) =>
        e.payloadJson['agentId'] == 'smoke-white' &&
        e.payloadJson['fallback'] == true)
    .length;

/// Embedded Stockfish evaluates a real position (explicit binary path).
Future<void> _stockfish(String binary) async {
  final evaluator = StockfishEvaluator(
    executablePath: binary,
    defaultDepth: 10,
  );
  await evaluator.connect();
  final result = await evaluator.evaluate(
    'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1',
  );
  await evaluator.dispose();
  check(result.supported, 'stockfish returned a supported evaluation');
  check(result.source == EngineSources.stockfishUci,
      'source labeled ${result.source}');
  check(result.scoreCp != null, 'score present (${result.scoreCp} cp)');
  check(result.bestMoveUci != null, 'best move present (${result.bestMoveUci})');
  debugPrint('  -- stockfish: ${result.scoreCp} cp, best ${result.bestMoveUci}');

  // Variant JSON must NOT be silently evaluated by Stockfish.
  final scene = StockfishEvaluator(
    executablePath: binary,
  );
  await scene.connect();
  final unsupported = await scene.evaluate('{"variant":"chaotic"}');
  await scene.dispose();
  check(!unsupported.supported,
      'variant JSON reported unsupported (no fake engine score)');
}

/// Short real game → per-move quality + key moments via the review module.
Future<void> _review() async {
  final engine = Position.initial();
  final service = WintrReviewService(evaluator: HeuristicEvaluator());
  final inputs = <ReviewMoveInput>[];
  final line = <String>['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1c4', 'g8f6', 'f3g5'];
  for (var i = 0; i < line.length; i++) {
    final move = ChessMove.fromUci(line[i]);
    final beforeFen = engine.toFen();
    final moverIsWhite = engine.sideToMove.isWhite;
    engine.apply(move);
    inputs.add(ReviewMoveInput(
      fenBefore: beforeFen,
      fenAfterOrVariantJson: engine.toFen(),
      moverIsWhite: moverIsWhite,
    ));
  }
  final report = await service.reviewGame(inputs);
  check(report.moves.length == line.length, 'report covers every ply');
  check(report.moves.every((m) => m.assessment.quality.name.isNotEmpty),
      'every ply classified');
  check(report.toJson()['moves'] != null, 'report serializes to JSON');
  debugPrint('  -- ${report.moves.length} plies, '
      '${report.keyMoments.length} key moment(s), '
      'white acc ${report.whiteAccuracy?.toStringAsFixed(1) ?? '-'}');
}
