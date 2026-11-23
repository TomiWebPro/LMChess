/// Agent/provider materialization for the UI-to-backend bridge.
///
/// Extracted from `backend_bridge.dart`: UI provider-string mapping, backend
/// agent conversion, per-turn provider resolution (mock + key-resolving),
/// lifecycle close and connection probing. Pure Dart: the injectable
/// Riverpod seams screens use to inject fakes in widget tests
/// (`turnProviderFactoryProvider`, `clockProvider`,
/// `connectionTesterProvider`) live in
/// `../providers/backend_providers.dart`.
/// Talks to: `agent/agent_config.dart`, `llm/*` providers, `storage/secure_key_store.dart`; Riverpod seams for screens/tests live in `../providers/backend_providers.dart`.
/// Never imports: `package:flutter` widgets/material, `package:flutter_riverpod`, `storage/local_store`, `hive` — keys resolve via the secure store.
library;

import 'dart:async';
import 'dart:math' as math;

import '../../diagnostics/app_log.dart';

import '../../agent/agent_config.dart' as agent_backend;
import '../../llm/anthropic_provider.dart';
import '../../llm/gemini_provider.dart';
import '../../llm/mock_provider.dart';
import '../../llm/openai_provider.dart';
import '../../llm/provider.dart';
import '../../llm/tool_schema.dart';
import '../../llm/validation.dart';
import '../../storage/secure_key_store.dart';
import '../ui_models.dart' as ui;

// Re-exported from domain so existing callers via this barrel
// (and `ui/backend_bridge.dart`) keep working with zero edits.
export '../../llm/tool_schema.dart' show uciToMoveToolCall;

/// Maps a UI-layer provider string to the domain [ProviderId].
///
/// Table: `'openai'` → openai, `'anthropic'` → anthropic,
/// `'gemini'` → gemini, `'ollama'` → ollama, `'stockfish'` → stockfish
/// (embedded engine, Elo-capped), `'mock'`/`'demo'` → mock
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
    case 'stockfish':
      return ProviderId.stockfish;
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
    model:
        agent.model.isEmpty &&
            agent.provider.trim().toLowerCase() == 'stockfish'
        ? 'stockfish-elo${agent.stockfishElo}'
        : agent.model,
    temperature: agent.temperature,
    maxTokens: agent.maxTokens,
    timeoutMs: 30000,
    systemPrompt: agent.systemPrompt,
    customInstructions: agent.userPromptTemplate,
    apiKeyRef: agent.apiKeyRef,
    stockfishElo: agent.stockfishElo,
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
/// Injectable seam for one AI turn's provider (FUTURE_WORK §10.1).
///
/// Screens must resolve the turn provider through
/// `turnProviderFactoryProvider` (in
/// `../providers/backend_providers.dart`) instead of calling
/// [resolveTurnProvider] directly, so widget tests can override it with a
/// [MockProvider] that returns immediately and injects timeout,
/// malformed-response, no-move, or thrown failures — no sockets, no
/// wall-clock waits.
///
/// The default factory is [resolveTurnProvider] itself, so production
/// behavior (including API-key resolution) is unchanged.
typedef TurnProviderFactory = Future<LlmProvider> Function(
  agent_backend.AgentConfig config,
  List<String> legalUcis, {
  int? seed,
  String? phrase,
});

/// Injectable wall-clock source for seeds and timestamps (§10.3 seam).
///
/// Production default is `DateTime.now` (see `clockProvider` in
/// `../providers/backend_providers.dart`); widget tests override it with a
/// fixed `DateTime.utc(2026, 1, 1)` so every seed and timestamp becomes
/// deterministic — no wall-clock dependency, no pending-timer failures
/// caused by stale `pumpAndSettle`.

/// Typedef for the §10.4 connection-tester seam.
///
/// Wraps [testAgentConnection] so that [AgentSetupScreen] resolves it through
/// a Riverpod provider (`connectionTesterProvider` in
/// `../providers/backend_providers.dart`) instead of calling the free
/// function directly. Widget tests override this provider with a lambda
/// that returns `true` or `false` immediately — no real HTTP request, no
/// platform channel into secure storage.
///
/// The default provider points to [testAgentConnection], keeping production
/// behaviour identical (it receives a [SecureKeyStore] internally via
/// `SecureKeyReaderAdapter`).
typedef ConnectionTester = Future<bool> Function(
  ui.AgentConfig agent, {
  String? inlineSecret,
});

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
/// `false` (the failure reason is surfaced via a `dart:developer` log that
/// carries no secret material). The provider is closed afterwards so a probe
/// cannot leak an HTTP client (see [closeProvider]).
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
  } catch (error) {
    AppLog.current.warning(
      'testAgentConnection: probe failed for ${provider.id} — reporting '
      'false',
      tag: 'connection-tester',
      error: error,
    );
    return false;
  } finally {
    closeProvider(provider);
  }
}
