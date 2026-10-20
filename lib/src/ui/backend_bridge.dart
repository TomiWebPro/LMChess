/// UI-to-backend bridge: shared adapters from the UI layer to the domain
/// backends.
///
/// This is the **shared** boundary: the pieces here (provider materialization,
/// board/payload helpers, event mirroring, telemetry logging, review plumbing
/// and terminal mapping) are the ones more than one screen needs, so the
/// contract is documented once instead of per screen. It is *not* the only
/// place screens touch the domain layer — play/watch/arena/review/stats also
/// import domain modules directly for screen-local concerns (clock types,
/// runnable positions, scheduler refs, chart vocabularies). The goal is to
/// avoid duplicating the non-trivial mappings below, not to forbid direct
/// domain imports.
///
/// * **Agents** ([toBackendAgent]/[providerIdFor]): the UI
///   [AgentConfig][1] carries `provider` as a free-form string
///   (`'openai'`, `'demo'`, …) while the agent layer wants a domain
///   provider id. Unknown/`'demo'`/`'custom'` strings map to
///   mock/OpenAI respectively — see [providerIdFor] for the table. `systemPrompt` passes through;
///   `userPromptTemplate` becomes `customInstructions` (the closest
///   backend field; API keys and base URLs stay with the storage layer —
///   see the agent-setup screen docs).
/// * **Mock demo path** ([mockAwareProvider]): keyless [MockProvider]
///   turns must still be *legal*. A blind default-script mock would replay
///   `e2e4` forever (illegal for Black, exhausted after one turn), so for
///   mock agents each turn gets a **fresh** [MockProvider] scripted with
///   one legal UCI sampled from the current position. The full
///   [AgentRunner] validation + orchestrator fallback path still runs —
///   the mock is transport, not a shortcut. Non-mock agents go through
///   [createProvider] with an empty key (keyless probe; failures fall back
///   to seeded random-legal moves with visible attribution).
/// * **Board helpers** ([squaresOf]/[squaresOfFen]/[legalUcis]/
///   [checkSquare]/[fenAdvance]): [Position] ↔ [Chessboard] `wK`-style
///   maps, legal UCI lists for [GameOrchestrator.setPosition], check
///   highlights, and the [PositionUpdater] used by every orchestrator.
/// * **Event mirror** ([activityFromGameEvent]): every [GameEvent] the
///   orchestrator emits (persist-then-broadcast, monotonic `seq`) maps to
///   an [ActivityEvent] for [AgentActivityPanel]. `positionSet` is dropped
///   (per-move intake noise); everything else keeps its message, tokens
///   and latency.
/// * **Telemetry singletons** ([StatsLog]/[QualityLog]/[ReviewLog]):
///   the stats backend ([AgentMetrics.compute]) needs `agentId`-keyed
///   [GameEventRecord]s the activity panel does not carry, so screens log
///   turns/game-ends here (with the metrics payload contract) and review
///   appends per-ply quality marks + full [ReviewGame]s. Stats and review
///   screens read these — no new Riverpod providers, no duplicates with
///   `ui_models.dart`. [StatsLog] additionally mirrors every record into
///   a real [stats_log.InMemoryEventStore] (idempotent by UUID key) and
///   exposes [StatsLog.store] + [StatsLog.changes], so the stats screen
///   consumes the real `EventStore` contract and re-renders when a game
///   finishes; [QualityLog.changes] does the same for quality marks.
/// * **Stats categorization** ([statsErrorCategory]): maps one
///   [stats_log.GameEventRecord]'s failure flags to the stats screen's
///   error-category vocabulary (`none`/`illegal`/`timeout`/`parse`/
///   `engine`) in one place.
/// * **Review plumbing** ([resolveReviewEvaluator]/[reviewInputsFor]/
///   [fensFor]): resolves Stockfish (embedded binary) with an honest
///   [HeuristicEvaluator] fallback, and turns a [ReviewGame] record into
///   the [ReviewMoveInput] list `WintrReviewService` consumes, so the
///   review screen never re-implements either contract. The resolved
///   evaluator handle carries the [EngineSources] label and (when the
///   binary could not run) the platform's honest failure reason, so the
///   UI can always render which source backed a score.
/// * **Per-ply move metadata** ([appliedMetaFor]): the phrase/fallback
///   lookup over an orchestrator's `moveApplied` events that watch/play
///   duplicate privately; arena consumes the shared helper instead.
/// * **Payload rendering** ([squaresOfPayload]): renders a stored
///   position payload — standard FEN *or* chaotic variant JSON — as a
///   [Chessboard] `squares` map, so review/arena can display either game
///   mode without branching.
/// * **Terminal mapping** ([mapTerminal]): the chess rules facade reports
///   [chess_eng.GameResult] (termination + winner); the orchestrator
///   records [gs.GameResult] (outcome string + reason). The mapper keeps
///   both vocabularies straight.
/// * **Lifecycle** ([closeProvider]): network providers that minted their
///   own HTTP client must be closed by the caller when a
///   `providerOverride` was used (the runner only closes providers it
///   created itself).
///
/// [1]: `lib/src/ui/ui_models.dart`
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../agent/agent_config.dart' as agent_backend;
import '../agent/agent_runner.dart';
import '../chess/engine.dart' as chess_eng;
import '../chess/fen.dart';
import '../chess/move.dart';
import '../chess/piece.dart';
import '../chess/position.dart';
import '../game/game_state.dart' as gs;
import '../game/orchestrator.dart';
import '../llm/anthropic_provider.dart';
import '../llm/gemini_provider.dart';
import '../llm/mock_provider.dart';
import '../llm/openai_provider.dart';
import '../llm/provider.dart';
import '../llm/tool_schema.dart';
import '../llm/validation.dart';
import '../review/embedded_engine.dart';
import '../review/engine_adapter.dart';
import '../review/quality.dart';
import '../review/stockfish_evaluator.dart';
import '../review/wintr_review.dart';
import '../stats/event_log.dart' as stats_log;
import '../storage/secure_key_store.dart';
import '../variant/variant_board.dart';
import '../variant/variant_replay.dart';
import 'ui_models.dart' as ui;
import 'widgets/activity_panel.dart';

/// Maps a UI-layer provider string to the domain [ProviderId].
///
/// Table: `'openai'` → openai, `'anthropic'` → anthropic,
/// `'gemini'` → gemini, `'ollama'` → ollama, `'mock'`/`'demo'` → mock
/// (`'demo'` is the legacy UI seed alias — no keys required),
/// `'custom'` → openai (custom endpoints are
/// OpenAI-compatible; the base URL lives with the storage layer, so this
/// is a keyless probe until that wiring lands). Anything else → mock so
/// every screen stays usable with zero configuration.
ProviderId providerIdFor(String provider) {
  switch (provider.trim().toLowerCase()) {
    case 'openai':
      return ProviderId.openai;
    case 'anthropic':
      return ProviderId.anthropic;
    case 'gemini':
      return ProviderId.gemini;
    case 'ollama':
      return ProviderId.ollama;
    case 'mock':
    case 'demo':
      return ProviderId.mock;
    case 'custom':
      return ProviderId.openai;
    default:
      return ProviderId.mock;
  }
}

/// Converts a UI-layer [ui.AgentConfig] to the domain agent config.
///
/// Field mapping: `id`/`name`/`model`/`temperature`/`maxTokens` pass
/// through; `provider` goes via [providerIdFor]; `systemPrompt` passes
/// through; `userPromptTemplate` becomes `customInstructions` (closest
/// backend field). Timing/retry/fallback use domain defaults except the
/// UI turn budget (`timeoutMs: 30000` — the 60 s domain default would hang
/// interactive screens through retries). The opaque [ui.AgentConfig.apiKeyRef]
/// is carried through so the gameplay pump can resolve the secret with
/// [resolveTurnProvider] (or [agent_backend.resolveApiKey]); the secret
/// itself never touches the config or any log.
agent_backend.AgentConfig toBackendAgent(ui.AgentConfig agent) {
  return agent_backend.AgentConfig(
    id: agent.id,
    name: agent.name,
    providerId: providerIdFor(agent.provider),
    model: agent.model,
    temperature: agent.temperature,
    maxTokens: agent.maxTokens,
    timeoutMs: 30000,
    systemPrompt: agent.systemPrompt,
    customInstructions: agent.userPromptTemplate,
    apiKeyRef: agent.apiKeyRef,
  );
}

/// Builds a [MoveToolCall] from a UCI string (`'e2e4'`, `'e7e8q'`).
///
/// Throws [FormatException] on malformed input; the orchestrator/runner
/// re-validates legality later, so this is shape-only.
MoveToolCall uciToMoveToolCall(String uci, {String? phrase}) {
  final text = uci.trim().toLowerCase();
  if (text.length < 4) {
    throw FormatException('Invalid UCI move: $uci');
  }
  final promotion = text.length > 4 ? text.substring(4, 5) : null;
  return MoveToolCall(
    from: text.substring(0, 2),
    to: text.substring(2, 4),
    promotion: promotion == null || promotion.isEmpty ? null : promotion,
    phrase: phrase,
  );
}

/// Like [mockAwareProvider], but resolves the secure API key for real
/// (non-mock) providers before materializing them, so a *configured* agent
/// actually authenticates at turn time.
///
/// Mock turns stay synchronous and keyless (they carry no secret). For every
/// other provider the secret is read from [keyStore] (defaulting to a plain
/// [SecureKeyStore]) via [agent_backend.resolveApiKey] and handed to
/// [agent_backend.createProvider]; the secret is never logged, persisted in a
/// config, or returned. A missing secret resolves to `''` so keyless backends
/// (Ollama) keep working and the runner surfaces an auth failure as a typed,
/// fallback-able outcome.
Future<LlmProvider> resolveTurnProvider(
  agent_backend.AgentConfig config,
  List<String> legalUcis, {
  int? seed,
  String? phrase,
  agent_backend.SecureKeyReader? keyReader,
}) async {
  if (config.providerId == ProviderId.mock) {
    return mockAwareProvider(config, legalUcis, seed: seed, phrase: phrase);
  }
  final secret = await agent_backend.resolveApiKey(
    config,
    keyReader ?? SecureKeyReaderAdapter(const SecureKeyStore()),
  );
  return agent_backend.createProvider(config, apiKeyResolver: (_) => secret);
}

/// Returns a provider for one AI turn.
///
/// Only the **mock** path is built here (used directly by tests and by
/// [resolveTurnProvider] for scripted agents); real providers must go through
/// [resolveTurnProvider] so their API key is resolved.
///
/// * Mock agents get a **fresh** [MockProvider] scripted with a single
///   legal UCI sampled from [legalUcis]. When [seed] is omitted the sample
///   is still deterministic — derived from the agent id plus the candidate
///   list — so demos replay identically instead of drawing from the wall
///   clock.
/// * An empty [legalUcis] means the game is already over — returns a mock
///   that reports `incompleteResponse` rather than inventing a move.
/// * Non-mock agents return a keyless provider here for backward
///   compatibility; prefer [resolveTurnProvider], which resolves the key.
LlmProvider mockAwareProvider(
  agent_backend.AgentConfig config,
  List<String> legalUcis, {
  int? seed,
  String? phrase,
}) {
  if (config.providerId != ProviderId.mock) {
    return agent_backend.createProvider(config);
  }
  if (legalUcis.isEmpty) {
    return MockProvider(
      script: const <Object>[FailureKind.incompleteResponse],
      model: config.model,
    );
  }
  final random = math.Random(seed ?? _stableMockSeed(config.id, legalUcis));
  final pick = legalUcis[random.nextInt(legalUcis.length)];
  return MockProvider(
    script: <Object>[uciToMoveToolCall(pick, phrase: phrase ?? 'Mock reply')],
    model: config.model,
  );
}

/// Deterministic 31-bit seed for keyless mock turns when no explicit seed is
/// supplied: FNV-style mix of the agent id and the candidate moves, so the
/// same agent on the same position always scripts the same pick (the list
/// changes as the position changes, keeping demo lines varied but
/// reproducible). Uses a small multiplier so the intermediate product stays
/// exact on web (JS numbers are only precise below 2^53).
int _stableMockSeed(String agentId, List<String> legalUcis) {
  var hash = 0x811c9dc5 & 0x7fffffff;
  void mix(String s) {
    for (final unit in s.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
  }

  mix(agentId);
  for (final uci in legalUcis) {
    mix(uci);
  }
  return hash & 0x7fffffff;
}

/// Closes network providers the UI created for `providerOverride` turns.
///
/// The runner only closes providers it created itself; when the UI passes
/// a `providerOverride` it owns the instance. Ollama extends the OpenAI
/// provider class so one branch covers both. [MockProvider] has nothing
/// to close.
void closeProvider(LlmProvider provider) {
  if (provider is OpenAiProvider) {
    provider.close();
  } else if (provider is AnthropicProvider) {
    provider.close();
  } else if (provider is GeminiProvider) {
    provider.close();
  }
}

/// Adapts the storage-layer [SecureKeyStore] to the agent layer's
/// [agent_backend.SecureKeyReader] contract.
///
/// Dart is nominally typed, so [SecureKeyStore]'s matching `readApiKey`
/// shape alone does not satisfy the interface; this tiny adapter is the
/// single seam between the two layers.
class SecureKeyReaderAdapter implements agent_backend.SecureKeyReader {
  /// Wraps [store].
  const SecureKeyReaderAdapter(this.store);

  /// Storage-backed key store.
  final SecureKeyStore store;

  @override
  Future<String?> readApiKey(String ref) => store.readApiKey(ref);
}

/// Probes connectivity for [uiAgent] without persisting anything.
///
/// Resolves the API key through [keyStore], or uses [inlineSecret] when the
/// user typed a key in the setup form but has not saved it yet, then
/// materializes the provider via [agent_backend.createProvider] and calls its
/// lightweight [LlmProvider.testConnection] ping.
///
/// Never throws and never logs/returns the secret: any failure reports
/// `false`. The provider is closed afterwards so a probe cannot leak an HTTP
/// client (see [closeProvider]).
Future<bool> testAgentConnection(
  ui.AgentConfig uiAgent,
  SecureKeyStore keyStore, {
  String? inlineSecret,
}) async {
  final backend = toBackendAgent(uiAgent);
  final secret = (inlineSecret != null && inlineSecret.isNotEmpty)
      ? inlineSecret
      : await agent_backend.resolveApiKey(
          backend,
          SecureKeyReaderAdapter(keyStore),
        );
  final provider = agent_backend.createProvider(
    backend,
    apiKeyResolver: (_) => secret,
  );
  try {
    return await provider.testConnection();
  } catch (_) {
    return false;
  } finally {
    closeProvider(provider);
  }
}

/// Renders [position] as a [Chessboard] `squares` map (`'e4' → 'wP'`).
///
/// Uses [Piece.code] (`'wK'`…`'bP'`), one of the two encodings the board
/// accepts (the other being raw glyphs).
Map<String, String> squaresOf(Position position) {
  return <String, String>{
    for (final entry in position.board.entries)
      entry.key.name: entry.value.code,
  };
}

/// Renders a [VariantBoard] as a [Chessboard] `squares` map.
///
/// Uses the same `wK`…`bP` encoding as [squaresOf], including duplicate/missing
/// kings (the board does not assume exactly one king per side).
Map<String, String> squaresOfVariantBoard(VariantBoard board) {
  return <String, String>{
    for (final entry in board.squares.entries)
      entry.key.name: '${colorCode(entry.value.color)}${entry.value.type.letter}',
  };
}

/// Renders a FEN string as a [Chessboard] `squares` map without a
/// [Position] (used for seek/replay over stored FEN histories).
///
/// Parses only the placement field; returns an empty map (never throws)
/// for malformed input so seek never crashes on a bad snapshot.
Map<String, String> squaresOfFen(String fen) {
  try {
    final placement = fen.trim().split(RegExp(r'\s+')).first;
    final rows = placement.split('/');
    if (rows.length != 8) return <String, String>{};
    final out = <String, String>{};
    for (var i = 0; i < 8; i++) {
      var file = 0;
      final row = rows[i];
      final rank = 7 - i;
      for (var j = 0; j < row.length && file < 8; j++) {
        final ch = row[j];
        final digit = int.tryParse(ch);
        if (digit != null) {
          file += digit;
          continue;
        }
        final upper = ch.toUpperCase();
        if ('PNBRQK'.contains(upper)) {
          final isWhite = ch == upper;
          out['${kFiles[file]}${rank + 1}'] =
              '${isWhite ? 'w' : 'b'}$upper';
        }
        file++;
      }
    }
    return out;
  } catch (_) {
    return <String, String>{};
  }
}

/// Renders a stored position payload as a [Chessboard] `squares` map.
///
/// Dispatches on shape: a payload starting with `{` is parsed as chaotic
/// [VariantBoard] JSON (`'e4' → 'wP'` via [colorCode] + the piece letter);
/// anything else goes through [squaresOfFen]. Never throws: malformed
/// variant JSON or FEN yields an empty map so replay views degrade to an
/// empty board instead of crashing.
Map<String, String> squaresOfPayload(String payload) {
  final trimmed = payload.trim();
  if (trimmed.startsWith('{')) {
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) return const <String, String>{};
      final board = VariantBoard.fromJson(
        Map<String, Object?>.from(decoded),
      );
      return <String, String>{
        for (final entry in board.squares.entries)
          entry.key.name:
              '${colorCode(entry.value.color)}${entry.value.type.letter}',
      };
    } catch (_) {
      return const <String, String>{};
    }
  }
  return squaresOfFen(trimmed);
}

/// Legal UCIs for the side to move in [position] (the list
/// [GameOrchestrator.setPosition] requires before any turn may start).
List<String> legalUcis(Position position) {
  return <String>[for (final m in position.legalMoves()) m.uci];
}

/// King square to highlight when the side to move is in check, else null.
String? checkSquare(Position position) {
  if (!position.isInCheck(position.sideToMove)) return null;
  return position.kingSquare(position.sideToMove)?.name;
}

/// Advances an opaque FEN position by one UCI move.
///
/// This is the [PositionUpdater] every screen hands its orchestrator:
/// parse → apply (throws [StateError] on illegal input, which the
/// orchestrator converts to a `failed` state) → serialize. All turn
/// inputs are engine-legal by construction, so the throw path only fires
/// on programming errors.
String fenAdvance(String positionFen, String uci) {
  final position = parseFen(positionFen);
  position.apply(ChessMove.fromUci(uci));
  return position.toFen();
}

/// Maps a chess-rules terminal verdict to the orchestrator result shape.
///
/// Checkmate/resignation/timeout decide by [chess_eng.GameResult.winner];
/// automatic draws (stalemate, fifty-move, insufficient material,
/// agreement) and aborts map to `'1/2-1/2'`/`'*'` with the termination
/// name as reason.
({String outcome, String reason, String? winnerColor}) mapTerminal(
  chess_eng.GameResult terminal,
) {
  switch (terminal.termination) {
    case chess_eng.GameTermination.checkmate:
    case chess_eng.GameTermination.resignation:
    case chess_eng.GameTermination.timeout:
      final whiteWins = terminal.winner == PieceColor.white;
      return (
        outcome: whiteWins ? '1-0' : '0-1',
        reason: terminal.termination.name,
        winnerColor: whiteWins ? 'w' : 'b',
      );
    case chess_eng.GameTermination.stalemate:
    case chess_eng.GameTermination.fiftyMove:
    case chess_eng.GameTermination.insufficientMaterial:
    case chess_eng.GameTermination.agreement:
      return (
        outcome: '1/2-1/2',
        reason: terminal.termination.name,
        winnerColor: null,
      );
    case chess_eng.GameTermination.aborted:
      return (outcome: '*', reason: 'aborted', winnerColor: null);
  }
}

String? _payloadString(Map<String, Object?> payload, String key) {
  final value = payload[key];
  return value is String ? value : null;
}

int? _payloadInt(Map<String, Object?> payload, String key) {
  final value = payload[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}

/// Maps one orchestrator [GameEvent] to an [ActivityEvent] for the panel.
///
/// Returns `null` for `positionSet` (per-move intake noise the panel
/// would otherwise flood with). Live `aiStream` payloads carry the LLM
/// [StreamEventKind]-named `kind` plus `message`/`text`/`toolName`/
/// `toolArgsJson`/`tokensIn`/`tokensOut`/`latencyMs`, which are forwarded
/// verbatim; `moveApplied` marks seeded fallbacks explicitly so they are
/// never misattributed to the agent.
ActivityEvent? activityFromGameEvent(GameEvent event) {
  final p = event.payload;
  switch (event.type) {
    case 'positionSet':
      return null;
    case 'gameStarted':
      return ActivityEvent(
        kind: ActivityEventKind.started,
        message: 'Game started (${p['mode'] ?? 'standard'}, '
            '${p['turn'] ?? '?'} to move)',
      );
    case 'aiTurnStarted':
      return ActivityEvent(
        kind: ActivityEventKind.started,
        message: 'AI turn: ${p['color'] ?? '?'} '
            '(${p['model'] ?? p['agentConfigId'] ?? 'agent'})',
      );
    case 'aiStream':
      final kind = _payloadString(p, 'kind') ?? '';
      final message =
          _payloadString(p, 'message') ?? _payloadString(p, 'text') ?? '';
      switch (kind) {
        case 'started':
          return ActivityEvent(
            kind: ActivityEventKind.started,
            message: message.isEmpty ? 'Turn stream opened' : message,
          );
        case 'status':
          return ActivityEvent(
            kind: ActivityEventKind.status,
            message: message,
          );
        case 'textDelta':
          return ActivityEvent(
            kind: ActivityEventKind.textDelta,
            message: _payloadString(p, 'text') ?? message,
          );
        case 'toolCallDelta':
        case 'toolCallCompleted':
          return ActivityEvent(
            kind: ActivityEventKind.toolDelta,
            toolName: _payloadString(p, 'toolName'),
            message: _payloadString(p, 'toolArgsJson') ?? message,
          );
        case 'usage':
          return ActivityEvent(
            kind: ActivityEventKind.usage,
            message: message.isEmpty ? 'turn usage' : message,
            promptTokens: _payloadInt(p, 'tokensIn'),
            completionTokens: _payloadInt(p, 'tokensOut'),
          );
        case 'latency':
          return ActivityEvent(
            kind: ActivityEventKind.latency,
            message: message.isEmpty ? 'turn latency' : message,
            latencyMs: _payloadInt(p, 'latencyMs'),
          );
        case 'done':
          return ActivityEvent(
            kind: ActivityEventKind.completed,
            message: message.isEmpty ? 'Turn stream done' : message,
          );
        case 'error':
        case 'errorRetry':
          return ActivityEvent(
            kind: ActivityEventKind.error,
            message: message,
          );
        default:
          return ActivityEvent(
            kind: ActivityEventKind.status,
            message: message.isEmpty ? 'stream: $kind' : message,
          );
      }
    case 'moveApplied':
      final uci = _payloadString(p, 'uci') ?? '?';
      final isFallback = p['isFallback'] == true;
      final phrase = _payloadString(p, 'phrase');
      final agent = _payloadString(p, 'agentConfigId');
      final buffer = StringBuffer('Played $uci');
      if (isFallback) buffer.write(' (fallback, unattributed)');
      if (phrase != null && phrase.isNotEmpty) buffer.write(' — "$phrase"');
      if (agent != null && !isFallback) buffer.write(' · $agent');
      return ActivityEvent(
        kind: ActivityEventKind.completed,
        message: buffer.toString(),
      );
    case 'fallbackApplied':
      return ActivityEvent(
        kind: ActivityEventKind.status,
        message: 'Fallback ${_payloadString(p, 'chosenUci') ?? '?'} after '
            '${_payloadString(p, 'reason') ?? 'failure'} '
            '(seeded, unattributed)',
      );
    case 'aiTurnFailed':
      return ActivityEvent(
        kind: ActivityEventKind.error,
        message: 'AI turn failed (${_payloadString(p, 'kind') ?? 'error'}): '
            '${_payloadString(p, 'error') ?? ''}'.trim(),
      );
    case 'turnRejected':
    case 'humanMoveRejected':
    case 'startRejected':
      return ActivityEvent(
        kind: ActivityEventKind.error,
        message:
            'Rejected (${_payloadString(p, 'reason') ?? event.type})',
      );
    case 'paused':
      return ActivityEvent(
        kind: ActivityEventKind.status,
        message: 'Game paused',
      );
    case 'resumed':
      return ActivityEvent(
        kind: ActivityEventKind.status,
        message: 'Game resumed',
      );
    case 'resigned':
      return ActivityEvent(
        kind: ActivityEventKind.completed,
        message: 'Resigned (${_payloadString(p, 'color') ?? '?'}); '
            'winner ${_payloadString(p, 'winner') ?? '?'}',
      );
    case 'flagFall':
      return ActivityEvent(
        kind: ActivityEventKind.completed,
        message: 'Flag: ${_payloadString(p, 'color') ?? '?'} lost on time; '
            'winner ${_payloadString(p, 'winner') ?? '?'}',
      );
    case 'terminalReported':
    case 'gameFinished':
      final outcome = _payloadString(p, 'outcome');
      final reason = _payloadString(p, 'reason');
      return ActivityEvent(
        kind: ActivityEventKind.completed,
        message: 'Game finished${outcome == null ? '' : ' $outcome'}'
            '${reason == null ? '' : ' ($reason)'}',
      );
    default:
      return ActivityEvent(
        kind: ActivityEventKind.status,
        message: event.type,
      );
  }
}

/// In-memory stats-backend log shared by all screens.
///
/// The activity panel's [ActivityEvent]s carry no `agentId`, so
/// [AgentMetrics.compute] would skip them all. Screens therefore log one
/// [stats_log.GameEventRecord] per turn here with the exact payload
/// contract `metrics.dart` consumes (`agentId`, `modelKey`, `latencyMs`,
/// `inputTokens`/`outputTokens`, `color`, `mode`, boolean flags,
/// `countAsTurn: false` on result markers). The stats screen filters these
/// records and aggregates them — the sample constants it used before are
/// gone.
///
/// Every record is also appended to a real [stats_log.InMemoryEventStore]
/// (idempotent by UUID key) — [store] — so consumers exercise the actual
/// [stats_log.EventStore] contract; [changes] fires after every append so
/// listening screens re-render when a game finishes. Not durable
/// (process-local); persistence owns the Hive boxes.
abstract class StatsLog {
  static final List<stats_log.GameEventRecord> _records =
      <stats_log.GameEventRecord>[];
  static final Map<String, int> _seqByGame = <String, int>{};
  static final stats_log.InMemoryEventStore _store =
      stats_log.InMemoryEventStore();
  static final _TelemetryNotifier _changes = _TelemetryNotifier();
  static const Uuid _uuid = Uuid();

  /// Upper bound on retained in-memory records (oldest evicted first).
  ///
  /// The event-store mirror is capped independently; this keeps a long
  /// session with many games/tournaments from growing without limit.
  static const int maxRetainedRecords = 20000;

  /// All logged records (unmodifiable, insertion order).
  static List<stats_log.GameEventRecord> get records =>
      List<stats_log.GameEventRecord>.unmodifiable(_records);

  /// The event-store mirror every record is also appended to.
  ///
  /// Read via [stats_log.EventStore.listAll]/`listByGame`/
  /// `listByTournament`; appends are idempotent by [GameEventRecord.key]
  /// so a replayed flush can never double-count.
  static stats_log.EventStore get store => _store;

  /// Notifies after every append and on [clear] (see the library docs).
  static Listenable get changes => _changes;

  /// Clears the log + store (used by watch/arena restarts).
  static void clear() {
    _records.clear();
    _seqByGame.clear();
    _store.clear();
    _changes.bump();
  }

  static int _nextSeq(String gameId) {
    final next = (_seqByGame[gameId] ?? 0) + 1;
    _seqByGame[gameId] = next;
    return next - 1;
  }

  /// Appends [record] to the log and mirrors it into [store].
  static void _append(stats_log.GameEventRecord record) {
    _records.add(record);
    if (_records.length > maxRetainedRecords) {
      _records.removeRange(0, _records.length - maxRetainedRecords);
    }
    _store.append(record);
    _changes.bump();
  }

  /// Logs one turn for [agentId] with metrics flags.
  static void logTurn({
    required String gameId,
    required String agentId,
    String? tournamentId,
    String modelKey = '',
    String color = 'white',
    String mode = 'standard',
    int? latencyMs,
    int? inputTokens,
    int? outputTokens,
    bool parsedMove = false,
    bool validTool = false,
    bool legal = false,
    bool illegalAttempt = false,
    bool unparseable = false,
    bool missingTool = false,
    bool providerError = false,
    bool timeout = false,
    bool fallback = false,
  }) {
    _append(
      stats_log.GameEventRecord(
        key: _uuid.v4(),
        gameId: gameId,
        tournamentId: tournamentId,
        seq: _nextSeq(gameId),
        type: fallback
            ? 'turn.fallback'
            : (legal ? 'turn.completed' : 'turn.failed'),
        payloadJson: <String, Object?>{
          'agentId': agentId,
          'modelKey': modelKey,
          'color': color,
          'mode': mode,
          'latencyMs': ?latencyMs,
          'inputTokens': ?inputTokens,
          'outputTokens': ?outputTokens,
          'parsedMove': parsedMove,
          'validTool': validTool,
          'legal': legal,
          'illegalAttempt': illegalAttempt,
          'unparseable': unparseable,
          'missingTool': missingTool,
          'providerError': providerError,
          'timeout': timeout,
          'fallback': fallback,
        },
      ),
    );
  }

  /// Logs a result-only marker for [agentId] (never counts as a turn).
  ///
  /// [result] is `'win'`, `'loss'` or `'draw'` from that agent's
  /// perspective — the only values [AgentMetrics.compute] counts.
  static void logGameEnd({
    required String gameId,
    required String agentId,
    String? tournamentId,
    String modelKey = '',
    required String result,
    String color = 'white',
    String mode = 'standard',
  }) {
    _append(
      stats_log.GameEventRecord(
        key: _uuid.v4(),
        gameId: gameId,
        tournamentId: tournamentId,
        seq: _nextSeq(gameId),
        type: 'game.end',
        payloadJson: <String, Object?>{
          'agentId': agentId,
          'modelKey': modelKey,
          'result': result,
          'color': color,
          'mode': mode,
          'countAsTurn': false,
        },
      ),
    );
  }
}

/// Private change notifier for the telemetry singletons.
///
/// They are process-lived (never disposed), so the only exposed capability
/// is "something was appended" via [bump] — listeners cannot fire bogus
/// notifications or dispose shared state.
class _TelemetryNotifier extends ChangeNotifier {
  /// Notifies listeners (see class docs).
  void bump() => notifyListeners();
}

/// Shared per-ply quality marks backing the stats quality chart.
///
/// Review appends the UI marks (`'!!'`…`'??'`) it derives from
/// [classify] here (overwriting per game reviewed); stats renders the
/// distribution and re-renders on [changes]. Empty until the first review
/// runs — the chart shows a wiring-point empty state meanwhile. A future
/// storage wiring will move these to the `evaluations` box keyed by
/// `<game>:<seq>`.
abstract class QualityLog {
  static List<String> _marks = const <String>[];
  static final _TelemetryNotifier _changes = _TelemetryNotifier();

  /// Current marks (unmodifiable).
  static List<String> get marks => List<String>.unmodifiable(_marks);

  /// Notifies after [setAll]/[clear] (see the library docs).
  static Listenable get changes => _changes;

  /// Replaces the marks with [marks] (one review's distribution).
  static void setAll(List<String> marks) {
    _marks = List<String>.of(marks);
    _changes.bump();
  }

  /// Clears the marks.
  static void clear() {
    _marks = const <String>[];
    _changes.bump();
  }
}

/// One reviewable game: full move + FEN + commentary history.
///
/// FENs follow the replay convention `fens.length == ucis.length + 1`
/// (`fens[0]` is the start position). `phrases`/`fallbackFlags` are
/// parallel to `ucis` (human moves carry `null` phrases). Standard games
/// start with White to move, so ply `i`'s mover is White iff `i` is even.
class ReviewGame {
  /// Creates a review game. Length invariants are documented, not
  /// asserted, so a malformed record degrades to an empty review rather
  /// than crashing the screen.
  const ReviewGame({
    required this.id,
    required this.whiteLabel,
    required this.blackLabel,
    this.whiteAgentId,
    this.blackAgentId,
    this.mode = 'standard',
    this.ucis = const <String>[],
    this.sans = const <String>[],
    this.fens = const <String>[],
    this.phrases = const <String?>[],
    this.fallbackFlags = const <bool>[],
  });

  /// Stable id (`'play-game'`, `'watch-game'`, tournament game ids…).
  final String id;

  /// Display labels for both seats.
  final String whiteLabel;

  /// Display labels for both seats.
  final String blackLabel;

  /// Agent ids for stats attribution, when known.
  final String? whiteAgentId;

  /// Agent ids for stats attribution, when known.
  final String? blackAgentId;

  /// `'standard'` or `'chaotic'`.
  final String mode;

  /// Played moves in UCI order.
  final List<String> ucis;

  /// SAN labels parallel to [ucis].
  final List<String> sans;

  /// FEN history (`length == ucis.length + 1` when well-formed).
  final List<String> fens;

  /// Agent phrases parallel to [ucis] (`null` for human moves).
  final List<String?> phrases;

  /// Fallback flags parallel to [ucis].
  final List<bool> fallbackFlags;
}

/// Process-local review-game log (latest-finished-first, capped).
///
/// Play/watch record their finished games here; arena records each
/// completed standard tournament game; review reads the latest (or a
/// picked) entry and re-renders on [changes]. Cap of 20 keeps memory
/// bounded; re-recording an id replaces it.
abstract class ReviewLog {
  static final List<ReviewGame> _games = <ReviewGame>[];
  static final _TelemetryNotifier _changes = _TelemetryNotifier();

  /// Logged games, latest first (unmodifiable).
  static List<ReviewGame> get games => List<ReviewGame>.unmodifiable(_games);

  /// Latest game, or `null` when nothing has been recorded yet.
  static ReviewGame? get latest => _games.isEmpty ? null : _games.first;

  /// Notifies after [record]/[clear] (see the library docs).
  static Listenable get changes => _changes;

  /// Records [game], replacing any same-id entry and capping at 20.
  static void record(ReviewGame game) {
    _games.removeWhere((g) => g.id == game.id);
    _games.insert(0, game);
    if (_games.length > 20) {
      _games.removeRange(20, _games.length);
    }
    _changes.bump();
  }

  /// Clears the log.
  static void clear() {
    _games.clear();
    _changes.bump();
  }
}

/// Process-local log of chaotic-variant replay records (latest first, capped).
///
/// Kept separate from [ReviewLog] because variant records are JSON/board-chain
/// shaped and must not be forced into the FEN-based standard review model.
abstract class VariantReviewLog {
  static final List<VariantGameRecord> _games = <VariantGameRecord>[];
  static final _TelemetryNotifier _changes = _TelemetryNotifier();

  /// Maximum retained games (memory bound).
  static const int maxGames = 20;

  /// Logged games, latest first (unmodifiable).
  static List<VariantGameRecord> get games =>
      List<VariantGameRecord>.unmodifiable(_games);

  /// Latest game, or `null` when nothing has been recorded yet.
  static VariantGameRecord? get latest =>
      _games.isEmpty ? null : _games.first;

  /// Looks up a game by id, or `null`.
  static VariantGameRecord? byId(String id) {
    for (final game in _games) {
      if (game.id == id) return game;
    }
    return null;
  }

  /// Notifies after [record]/[clear].
  static Listenable get changes => _changes;

  /// Records [game], replacing any same-id entry and capping at [maxGames].
  static void record(VariantGameRecord game) {
    _games.removeWhere((g) => g.id == game.id);
    _games.insert(0, game);
    if (_games.length > maxGames) {
      _games.removeRange(maxGames, _games.length);
    }
    _changes.bump();
  }

  /// Clears the log.
  static void clear() {
    _games.clear();
    _changes.bump();
  }
}

/// Maps a [MoveQuality] tier to the UI quality mark vocabulary.
///
/// `'!!'` covers both brilliant tiers, `'!'` best/excellent, `'ok'`
/// good + unsupported (no judgment available), `'!?'` inaccuracy, `'?'`
/// mistake, `'??'` blunder/super-blunder. Icons/colors come from
/// `qualityIconFor`/`qualityColorFor` in `widgets/boards.dart`.
String qualityMarkFor(MoveQuality quality) {
  switch (quality) {
    case MoveQuality.superBrilliant:
    case MoveQuality.brilliant:
      return '!!';
    case MoveQuality.best:
    case MoveQuality.excellent:
      return '!';
    case MoveQuality.good:
    case MoveQuality.unsupported:
      return 'ok';
    case MoveQuality.inaccuracy:
      return '!?';
    case MoveQuality.mistake:
      return '?';
    case MoveQuality.blunder:
    case MoveQuality.superBlunder:
      return '??';
  }
}

/// Resolved evaluation source for one review run.
///
/// [resolvedSource] is the [EngineSources] label of [evaluator]
/// (`'stockfish-uci'` or `'heuristic'`), which the review UI must render
/// next to every score. When Stockfish could not be used, [fallbackReason]
/// carries the platform's honest explanation ([EmbeddedEngine] error or
/// connect failure) — never silently swallowed. [dispose] shuts down the
/// spawned engine process (no-op for the heuristic estimator); call it
/// once per run, when the review finishes or the screen goes away.
class ReviewEvaluatorHandle {
  /// Creates a handle (construct via [resolveReviewEvaluator]).
  ReviewEvaluatorHandle({
    required this.evaluator,
    required this.resolvedSource,
    this.fallbackReason = '',
    this.engine,
  });

  /// Evaluator for both positions of every reviewed move.
  final PositionEvaluator evaluator;

  /// [EngineSources] label of [evaluator] (render verbatim in the UI).
  final String resolvedSource;

  /// Human-readable reason the heuristic fallback was chosen; `''` when
  /// the embedded Stockfish binary connected.
  final String fallbackReason;

  /// Connected UCI engine adapter to shut down, or `null` when the run
  /// uses the built-in heuristic estimator.
  final UciEngineAdapter? engine;

  /// Whether the heuristic estimator (not an engine) backs this run.
  bool get isFallback => resolvedSource != EngineSources.stockfishUci;

  /// Shuts down the spawned engine process, if any. Idempotent.
  Future<void> dispose() async {
    await engine?.dispose();
  }
}

/// Resolves the best available reviewer: embedded Stockfish when the
/// platform can spawn it, else the honest [HeuristicEvaluator] fallback.
///
/// Flow: [EmbeddedEngine.isAvailable] performs the same first-run
/// extraction [StockfishEvaluator] would (so a `true` probe leaves the
/// binary ready); on success a `StockfishEvaluator` is constructed and
/// [UciEngineAdapter.connect]ed — a connect failure (AV sandbox, broken
/// binary) is caught, the half-connected adapter disposed, and the
/// heuristic fallback applies. On unavailable platforms
/// ([EmbeddedEngine.explanatoryError] carries the iOS/Web/no-binary
/// reason verbatim). The returned handle's [ReviewEvaluatorHandle
/// .resolvedSource]/[ReviewEvaluatorHandle.fallbackReason] must be shown
/// in the UI — heuristic numbers are estimates, never engine output.
Future<ReviewEvaluatorHandle> resolveReviewEvaluator() async {
  if (await EmbeddedEngine.isAvailable()) {
    final engine = StockfishEvaluator();
    try {
      await engine.connect();
      return ReviewEvaluatorHandle(
        evaluator: engine,
        resolvedSource: EngineSources.stockfishUci,
        engine: engine,
      );
    } catch (e) {
      await engine.dispose();
      return ReviewEvaluatorHandle(
        evaluator: HeuristicEvaluator(),
        resolvedSource: EngineSources.heuristic,
        fallbackReason:
            'Stockfish was found but failed to start ($e); using the '
            'heuristic estimator instead.',
      );
    }
  }
  return ReviewEvaluatorHandle(
    evaluator: HeuristicEvaluator(),
    resolvedSource: EngineSources.heuristic,
    fallbackReason: await EmbeddedEngine.explanatoryError(),
  );
}

/// FEN history for [game], rebuilt by replay when the record is malformed.
///
/// Stored records follow the replay convention
/// `fens.length == ucis.length + 1`. When a caller (or an interrupted
/// recorder) produced a short history, this replays [ReviewGame.ucis]
/// from [standardStartFen] via [fenAdvance] to reconstruct it; if replay
/// fails (chaotic UCI list, corrupt records) the stored list is returned
/// unchanged so callers can degrade honestly instead of crashing.
List<String> fensFor(ReviewGame game) {
  if (game.fens.length == game.ucis.length + 1) {
    return List<String>.of(game.fens);
  }
  try {
    final rebuilt = <String>[standardStartFen];
    for (final uci in game.ucis) {
      rebuilt.add(fenAdvance(rebuilt.last, uci));
    }
    return rebuilt;
  } catch (_) {
    return List<String>.of(game.fens);
  }
}

/// Turns a stored [ReviewGame] into the [ReviewMoveInput] list
/// [WintrReviewService.reviewGame] consumes.
///
/// One input per stored UCI: `fenBefore`/`fenAfterOrVariantJson` come
/// from [fensFor] (standard FEN for standard games; variant JSON passes
/// through to variant-capable evaluators — Stockfish reports
/// `supported: false` for it, per the `engine_adapter.dart` contract).
/// `moverIsWhite` follows the standard-game convention (White starts, so
/// even plies are White's). Commentary is the stored agent phrase, or
/// `null` on seeded fallbacks (fallbacks are never attributed); the
/// fallback also lands as an annotation. `wasIllegalAttempt` is not part
/// of [ReviewGame] — illegal attempts never auto-penalize in [classify],
/// so its absence cannot skew a tier; a future recorder that tracks it
/// should extend the record (**Wiring point**).
///
/// Plies without a supporting FEN pair (malformed record that replay
/// could not repair) are skipped rather than fabricated; an empty result
/// is a valid empty review.
List<ReviewMoveInput> reviewInputsFor(ReviewGame game) {
  final fens = fensFor(game);
  final usable =
      fens.isEmpty ? 0 : math.min(game.ucis.length, fens.length - 1);
  final out = <ReviewMoveInput>[];
  for (var i = 0; i < usable; i++) {
    final fallback =
        i < game.fallbackFlags.length && game.fallbackFlags[i];
    final phrase = i < game.phrases.length ? game.phrases[i] : null;
    out.add(
      ReviewMoveInput(
        fenBefore: fens[i],
        fenAfterOrVariantJson: fens[i + 1],
        moverIsWhite: i.isEven,
        commentary: fallback ? null : phrase,
        annotations: fallback
            ? const <String>['seeded fallback move (unattributed)']
            : const <String>[],
      ),
    );
  }
  return out;
}

/// Maps an [AgentTurnResult] to [StatsLog.logTurn] metrics flags.
///
/// Success → `parsedMove`/`validTool`/`legal`. Failure kinds map to their
/// metrics flags: `illegalMove` → `illegalAttempt`, `timeout` → `timeout`,
/// `providerError`/`rateLimit` → `providerError`,
/// `unparseableResponse`/`malformedArgs` → `unparseable`,
/// `missingToolCall`/`incompleteResponse`/`cancelled`/`internal` →
/// `missingTool`. [fallback] marks orchestrator-applied seeded fallbacks
/// explicitly (the move is legal but unattributed — see `fallbackRate`).
/// Token counts come from the runner's last usage event ([MockProvider]
/// scripted turns report 128 in / 16 out).
void logTurnOutcome({
  required String gameId,
  required String agentId,
  String? tournamentId,
  String modelKey = '',
  String color = 'white',
  String mode = 'standard',
  required AgentTurnResult result,
  bool fallback = false,
}) {
  final legal = result.isSuccess;
  var illegalAttempt = false;
  var unparseable = false;
  var missingTool = false;
  var providerError = false;
  var timeout = false;
  final kind = result.outcome.kind;
  if (!legal) {
    switch (kind) {
      case FailureKind.illegalMove:
        illegalAttempt = true;
      case FailureKind.timeout:
        timeout = true;
      case FailureKind.providerError:
      case FailureKind.rateLimit:
      case FailureKind.authError:
        providerError = true;
      case FailureKind.unparseableResponse:
      case FailureKind.malformedArgs:
        unparseable = true;
      case FailureKind.missingToolCall:
      case FailureKind.incompleteResponse:
      case FailureKind.cancelled:
      case FailureKind.internal:
      case FailureKind.valid:
        missingTool = true;
    }
  }
  StatsLog.logTurn(
    gameId: gameId,
    agentId: agentId,
    tournamentId: tournamentId,
    modelKey: modelKey,
    color: color,
    mode: mode,
    latencyMs: result.latencyMs,
    inputTokens: result.usage?.inputTokens,
    outputTokens: result.usage?.outputTokens,
    parsedMove: legal,
    validTool: legal,
    legal: legal,
    illegalAttempt: illegalAttempt,
    unparseable: unparseable,
    missingTool: missingTool,
    providerError: providerError,
    timeout: timeout,
    fallback: fallback,
  );
}

/// Logs per-agent result markers for a finished game.
///
/// [outcome] is the `1-0`/`0-1`/`1/2-1/2` score string; each side gets the
/// `'win'`/`'loss'`/`'draw'` value [AgentMetrics.compute] counts (from
/// that agent's perspective). `'*'` (aborted/undecided) logs nothing — an
/// abandoned game is not evidence of skill.
void logGameResults({
  required String gameId,
  required String whiteAgentId,
  required String blackAgentId,
  String? tournamentId,
  String whiteModelKey = '',
  String blackModelKey = '',
  String mode = 'standard',
  required String outcome,
}) {
  switch (outcome) {
    case '1-0':
      StatsLog.logGameEnd(
        gameId: gameId,
        agentId: whiteAgentId,
        tournamentId: tournamentId,
        modelKey: whiteModelKey,
        result: 'win',
        color: 'white',
        mode: mode,
      );
      StatsLog.logGameEnd(
        gameId: gameId,
        agentId: blackAgentId,
        tournamentId: tournamentId,
        modelKey: blackModelKey,
        result: 'loss',
        color: 'black',
        mode: mode,
      );
    case '0-1':
      StatsLog.logGameEnd(
        gameId: gameId,
        agentId: whiteAgentId,
        tournamentId: tournamentId,
        modelKey: whiteModelKey,
        result: 'loss',
        color: 'white',
        mode: mode,
      );
      StatsLog.logGameEnd(
        gameId: gameId,
        agentId: blackAgentId,
        tournamentId: tournamentId,
        modelKey: blackModelKey,
        result: 'win',
        color: 'black',
        mode: mode,
      );
    case '1/2-1/2':
      StatsLog.logGameEnd(
        gameId: gameId,
        agentId: whiteAgentId,
        tournamentId: tournamentId,
        modelKey: whiteModelKey,
        result: 'draw',
        color: 'white',
        mode: mode,
      );
      StatsLog.logGameEnd(
        gameId: gameId,
        agentId: blackAgentId,
        tournamentId: tournamentId,
        modelKey: blackModelKey,
        result: 'draw',
        color: 'black',
        mode: mode,
      );
    default:
      break;
  }
}

/// Maps one [stats_log.GameEventRecord] to the stats error vocabulary.
///
/// Returns one of `'none'`, `'illegal'`, `'timeout'`, `'parse'` or
/// `'engine'` — the exact label set the stats screen's error-category
/// chart renders. Precedence when a turn carries several flags: `timeout`
/// (a flagged turn is the clearest terminal fault), then `illegalAttempt`
/// → `illegal`, then `unparseable`/`missingTool` → `parse` (the model
/// output was unusable), then `providerError` → `engine`. Result markers
/// and clean turns map to `'none'`.
String statsErrorCategory(stats_log.GameEventRecord record) {
  final payload = record.payloadJson;
  bool flag(String key) => payload[key] == true;
  if (flag('timeout')) return 'timeout';
  if (flag('illegalAttempt')) return 'illegal';
  if (flag('unparseable') || flag('missingTool')) return 'parse';
  if (flag('providerError')) return 'engine';
  return 'none';
}

/// Whether an orchestrator lifecycle state is terminal (finished/failed).
bool isTerminalOrchestratorState(gs.OrchestratorState state) {
  return state == gs.OrchestratorState.finished ||
      state == gs.OrchestratorState.failed;
}

/// Phrase/fallback metadata for the orchestrator's `moveApplied` entry
/// [moveIndex] (1-based, matching the event payload's `moveIndex`).
///
/// **Design note (shared pump):** play/watch/arena each carry their own
/// sequential "pump" loop (bind agent → request turn → replay UCIs onto a
/// mirror position → report terminal). The replay step itself is shared via
/// `game_mirror.dart`'s `replayMoves` (parse/apply/metadata + failure
/// reporting); the loops and their post-sync hooks (finish/AI-reply/arena
/// touch) stay local because they diverge on chaotic handling, cancellation
/// and per-turn stats buffering. `test/game_mirror_test.dart` locks the
/// shared core's behavior for all three recording shapes.
///
/// Scans [orch]'s persisted [GameOrchestrator.eventLog] backwards for the
/// matching event and returns its `phrase` (null when absent or when the
/// move was an unattributed fallback). The phrase is only ever attributed
/// to an agent when `isFallback` is false — mirrors the private lookups
/// watch/play keep for their own sync loops.
({String? phrase, bool isFallback}) appliedMetaFor(
  GameOrchestrator orch,
  int moveIndex,
) {
  for (var i = orch.eventLog.length - 1; i >= 0; i--) {
    final event = orch.eventLog[i];
    if (event.type == 'moveApplied' &&
        event.payload['moveIndex'] == moveIndex) {
      final phrase = event.payload['phrase'];
      return (
        phrase: phrase is String ? phrase : null,
        isFallback: event.payload['isFallback'] == true,
      );
    }
  }
  return (phrase: null, isFallback: false);
}

/// Retires an orchestrator replaced by a newer game: stops it first (so
/// a late in-flight turn discards against the terminal state instead of
/// touching listeners), cancels the event subscription, then disposes.
///
/// Late turns on a stopped game hit the `_isTerminal` guard in
/// `requestAiTurn`/`_applyMove` paths and are discarded — they never emit
/// into [_events] sinks or the mirror engine, so orphaned pump loops exit
/// on their identity check without side effects.
Future<void> retireOrchestrator(
  GameOrchestrator? orch,
  StreamSubscription<GameEvent>? sub,
) async {
  await sub?.cancel();
  if (orch != null && !isTerminalOrchestratorState(orch.state)) {
    orch.stop(reason: 'superseded');
  }
  orch?.dispose();
}

/// Extracts the raw tool-call JSON from the last completed call in [result].
///
/// Replay/audit uses the exact model payload, not a re-serialized move. Falls
/// back to [AgentTurnResult.selectedMove] when the event stream did not retain
/// the raw string. Never throws; unparseable JSON yields a null map but keeps
/// the raw string.
({String? rawToolArgsJson, Map<String, Object?>? rawToolCallJson})
    rawToolCallFrom(AgentTurnResult? result) {
  if (result == null) {
    return (rawToolArgsJson: null, rawToolCallJson: null);
  }
  for (var i = result.events.length - 1; i >= 0; i--) {
    final event = result.events[i];
    if (event.kind != StreamEventKind.toolCallCompleted) continue;
    final raw = event.toolArgsJson;
    if (raw == null || raw.isEmpty) continue;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      decoded = null;
    }
    return (
      rawToolArgsJson: raw,
      rawToolCallJson:
          decoded is Map ? Map<String, Object?>.from(decoded) : null,
    );
  }
  final move = result.selectedMove;
  return (
    rawToolArgsJson: move == null ? null : jsonEncode(move.toJson()),
    rawToolCallJson: move?.toJson(),
  );
}

/// One turn's stats-backend attribution, buffered per game and flushed at
/// game end (so undone or abandoned moves never pollute aggregates).
///
/// Human moves carry no runner result and are logged as clean legal turns;
/// AI moves carry their [AgentTurnResult] and go through [logTurnOutcome]
/// (failure-kind → metrics-flag mapping plus the explicit fallback mark).
class PendingTurn {
  /// Creates a pending turn record.
  const PendingTurn({
    required this.agentId,
    required this.modelKey,
    required this.color,
    required this.mode,
    this.result,
    this.fallback = false,
    this.human = false,
  });

  /// Agent id for metrics attribution (`'human'` for human moves).
  final String agentId;

  /// Model key for cost estimation (`'human'` for human moves).
  final String modelKey;

  /// `'white'` or `'black'` (metrics vocabulary).
  final String color;

  /// `'standard'` or `'chaotic'`.
  final String mode;

  /// Runner result for AI turns; `null` for human moves.
  final AgentTurnResult? result;

  /// Whether the orchestrator applied a seeded fallback this turn.
  final bool fallback;

  /// Whether this is a human move (logged as a clean legal turn).
  final bool human;

  /// Creates a human-move record.
  factory PendingTurn.human({String mode = 'standard'}) => PendingTurn(
    agentId: 'human',
    modelKey: 'human',
    color: 'white',
    mode: mode,
  );

  /// Creates an AI-turn record.
  factory PendingTurn.ai({
    required String agentId,
    required String modelKey,
    required String color,
    required String mode,
    required AgentTurnResult result,
    bool fallback = false,
  }) => PendingTurn(
    agentId: agentId,
    modelKey: modelKey,
    color: color,
    mode: mode,
    result: result,
    fallback: fallback,
  );

  /// Writes this turn to [StatsLog].
  void flush({required String gameId, String? tournamentId}) {
    if (human || result == null) {
      StatsLog.logTurn(
        gameId: gameId,
        agentId: agentId,
        tournamentId: tournamentId,
        modelKey: modelKey,
        color: color,
        mode: mode,
        parsedMove: true,
        validTool: true,
        legal: true,
      );
      return;
    }
    logTurnOutcome(
      gameId: gameId,
      agentId: agentId,
      tournamentId: tournamentId,
      modelKey: modelKey,
      color: color,
      mode: mode,
      result: result!,
      fallback: fallback,
    );
  }
}

/// Game-layer result constructor shorthand (avoids importing
/// `game_state.dart` in every screen).
gs.GameResult gameResult({
  required String outcome,
  required String reason,
  String? winnerColor,
}) {
  return gs.GameResult(
    outcome: outcome,
    reason: reason,
    winnerColor: winnerColor,
  );
}
