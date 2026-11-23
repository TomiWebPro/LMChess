/// Stockfish move picker for gameplay seats.
///
/// Unlike the LLM providers, Stockfish needs the concrete FEN at turn time
/// (the [AgentRequest] prompt carries only rendered board text, never the
/// FEN). So instead of a long-lived [LlmProvider], this exposes a per-turn
/// factory: connect the embedded engine with an Elo-capped personality,
/// evaluate the live FEN, and script a one-shot [MockProvider] with the
/// engine's pick — exactly like [mockAwareProvider] scripts mock turns.
/// The full [AgentRunner] validation + orchestrator fallback path still runs.
library;

import '../llm/mock_provider.dart';
import '../llm/provider.dart';
import '../llm/tool_schema.dart' show uciToMoveToolCall;
import '../review/embedded_engine.dart';
import '../review/stockfish_evaluator.dart';

/// Minimum/maximum Elo accepted by Stockfish 19 `UCI_Elo`.
const int kStockfishMinElo = 400;

/// Maximum Elo accepted by Stockfish 19 `UCI_Elo`.
const int kStockfishMaxElo = 3600;

/// Default Elo for ad-hoc Stockfish seats.
const int kStockfishDefaultElo = 1500;

/// Builds a one-shot provider whose single scripted move is Stockfish's
/// choice for [fen], playing at [elo] strength.
///
/// Flow: availability probe → evaluator with
/// `{UCI_LimitStrength: true, UCI_Elo: <clamped elo>}` → `connect()` →
/// `evaluate(fen)` → dispose → script a [MockProvider] with the best move.
/// The engine's `bestMoveUci` is preferred only when it is in [legalUcis]
/// (case-insensitive); otherwise the first legal UCI is used so the runner
/// never sees an illegal script.
///
/// Throws [StateError] with the platform's honest reason when the embedded
/// binary cannot run (web/iOS/missing binary) or when evaluation yields no
/// usable move — callers surface this in the game UI error path.
Future<LlmProvider> stockfishMoveProvider(
  String fen,
  List<String> legalUcis, {
  int elo = kStockfishDefaultElo,
  String? phrase,
}) async {
  if (legalUcis.isEmpty) {
    throw StateError('Stockfish has no legal moves to choose from.');
  }
  final clamped = elo.clamp(kStockfishMinElo, kStockfishMaxElo);
  if (!await EmbeddedEngine.isAvailable()) {
    throw StateError(await EmbeddedEngine.explanatoryError());
  }
  final engine = StockfishEvaluator(
    options: <String, String>{
      'Threads': '1',
      'Hash': '64',
      'UCI_LimitStrength': 'true',
      'UCI_Elo': '$clamped',
    },
  );
  try {
    await engine.connect();
    final result = await engine.evaluate(
      fen,
      timeout: const Duration(seconds: 10),
    );
    final pick = _chooseMove(result.bestMoveUci, legalUcis);
    if (pick == null) {
      throw StateError('Stockfish returned no usable move.');
    }
    return MockProvider(
      script: <Object>[uciToMoveToolCall(pick, phrase: phrase)],
      model: 'stockfish-elo$clamped',
    );
  } finally {
    await engine.dispose();
  }
}

/// Picks the engine's move when legal, else the first legal UCI.
String? _chooseMove(String? best, List<String> legalUcis) {
  if (best != null) {
    final want = best.trim().toLowerCase();
    for (final uci in legalUcis) {
      if (uci.toLowerCase() == want) return uci;
    }
  }
  return legalUcis.first;
}
