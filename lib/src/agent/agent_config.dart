/// Agent configuration: retry/fallback policies, per-agent settings, and the
/// [createProvider] factory that materializes the right [LlmProvider].
///
/// Pure Dart. API keys are never stored here: [AgentConfig.apiKeyRef] is an
/// opaque reference (e.g. a secure-storage key) resolved by the caller via
/// [ApiKeyResolver] at provider-construction time. The flutter_secure_storage
/// wrapper must live in its own file (storage layer) — never imported here.
library;

import 'dart:math' show Random;

import 'package:http/http.dart' as http;

import '../llm/anthropic_provider.dart';
import '../llm/gemini_provider.dart';
import '../llm/mock_provider.dart';
import '../llm/ollama_provider.dart';
import '../llm/openai_provider.dart';
import '../llm/provider.dart';
import '../llm/tool_schema.dart';
import '../llm/validation.dart';

/// Resolves an [AgentConfig.apiKeyRef] to the actual secret (or `null` when
/// absent). Implemented by the storage layer.
typedef ApiKeyResolver = String? Function(String ref);

/// Retry behavior for failed turn attempts.
class RetryPolicy {
  /// Extra attempts after the first try (0 = no retries).
  final int maxRetries;

  /// Delay before the first retry; grows by [backoffFactor] per attempt.
  final int baseDelayMs;

  /// Exponential multiplier applied to [baseDelayMs] per attempt (>= 1).
  final double backoffFactor;

  /// Failure kinds worth another attempt. Anything not listed fails fast.
  final List<FailureKind> retryOn;

  /// Creates a retry policy.
  const RetryPolicy({
    this.maxRetries = 2,
    this.baseDelayMs = 500,
    this.backoffFactor = 2.0,
    this.retryOn = const [
      FailureKind.providerError,
      FailureKind.rateLimit,
      FailureKind.timeout,
      FailureKind.incompleteResponse,
    ],
  });

  /// Delay before retry number [attempt] (0-based): base × factor^attempt,
  /// plus uniform ±20% jitter so a fleet of agents sharing one backend does
  /// not retry in lockstep (thundering herd). The [random] source defaults
  /// to a fresh unseeded [Random]; pass a seeded one in tests for
  /// deterministic assertions.
  Duration delayForAttempt(int attempt, [Random? random]) {
    var multiplier = 1.0;
    for (var i = 0; i < attempt; i++) {
      multiplier *= backoffFactor;
    }
    final base = baseDelayMs * multiplier;
    final jitter = base * 0.2 * ((random ?? Random()).nextDouble() * 2 - 1);
    return Duration(milliseconds: (base + jitter).round().clamp(0, 1 << 62));
  }

  /// Serializes to JSON.
  Map<String, Object?> toJson() => {
        'maxRetries': maxRetries,
        'baseDelayMs': baseDelayMs,
        'backoffFactor': backoffFactor,
        'retryOn': [for (final kind in retryOn) kind.name],
      };

  /// Parses from JSON; unknown failure-kind names are dropped, missing keys
  /// fall back to defaults. Never throws on maps produced by [toJson].
  factory RetryPolicy.fromJson(Map json) {
    int asInt(Object? value, int fallback) =>
        value is int ? value : int.tryParse('$value') ?? fallback;
    double asDouble(Object? value, double fallback) =>
        value is num ? value.toDouble() : double.tryParse('$value') ?? fallback;
    final rawRetryOn = json['retryOn'];
    return RetryPolicy(
      maxRetries: asInt(json['maxRetries'], 2),
      baseDelayMs: asInt(json['baseDelayMs'], 500),
      backoffFactor: asDouble(json['backoffFactor'], 2.0),
      retryOn: rawRetryOn is List
          ? [
              for (final name in rawRetryOn)
                ..._parseFailureKind('$name'),
            ]
          : const [
              FailureKind.providerError,
              FailureKind.rateLimit,
              FailureKind.timeout,
              FailureKind.incompleteResponse,
            ],
    );
  }

  /// Copies with selectively replaced fields.
  RetryPolicy copyWith({
    int? maxRetries,
    int? baseDelayMs,
    double? backoffFactor,
    List<FailureKind>? retryOn,
  }) {
    return RetryPolicy(
      maxRetries: maxRetries ?? this.maxRetries,
      baseDelayMs: baseDelayMs ?? this.baseDelayMs,
      backoffFactor: backoffFactor ?? this.backoffFactor,
      retryOn: retryOn ?? this.retryOn,
    );
  }

  static Iterable<FailureKind> _parseFailureKind(String name) sync* {
    for (final kind in FailureKind.values) {
      if (kind.name == name) {
        yield kind;
        return;
      }
    }
  }
}

/// What the orchestrator may do when an agent turn fails definitively.
class FallbackPolicy {
  /// Well-known mode: pick a uniform random legal move (seeded).
  static const String modeRandomLegal = 'randomLegal';

  /// Whether fallback moves are allowed at all.
  final bool enabled;

  /// Fallback strategy id. Only [modeRandomLegal] is implemented.
  final String mode;

  /// Optional seed for the fallback RNG (reproducible arena runs).
  final int? seed;

  /// Creates a fallback policy.
  const FallbackPolicy({
    this.enabled = true,
    this.mode = modeRandomLegal,
    this.seed,
  });

  /// Serializes to JSON.
  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'mode': mode,
        if (seed != null) 'seed': seed,
      };

  /// Parses from JSON; missing keys fall back to defaults.
  factory FallbackPolicy.fromJson(Map json) {
    final seed = json['seed'];
    return FallbackPolicy(
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      mode: json['mode'] is String
          ? json['mode'] as String
          : modeRandomLegal,
      seed: seed is int ? seed : int.tryParse('$seed'),
    );
  }

  /// Copies with selectively replaced fields.
  FallbackPolicy copyWith({bool? enabled, String? mode, int? seed}) {
    return FallbackPolicy(
      enabled: enabled ?? this.enabled,
      mode: mode ?? this.mode,
      seed: seed ?? this.seed,
    );
  }
}

/// Full configuration for one LLM agent (one tournament entrant / seat).
class AgentConfig {
  /// Stable id referenced by game participants and arena pairings.
  final String id;

  /// Display name.
  final String name;

  /// Which backend serves this agent.
  final ProviderId providerId;

  /// Model id passed to the backend.
  final String model;

  /// Custom API root for OpenAI-compatible endpoints (OpenRouter, proxies).
  /// Ignored by providers with fixed roots unless they support overrides.
  final String? baseUrl;

  /// Opaque secure-storage reference for the API key (never the key itself).
  /// `null` means "no key needed" (local Ollama / mock).
  final String? apiKeyRef;

  /// Sampling temperature.
  final double temperature;

  /// Backend token budget per turn.
  final int maxTokens;

  /// Per-attempt wall-clock budget in ms (enforced by the runner).
  final int timeoutMs;

  /// Retry behavior across attempts of one turn.
  final RetryPolicy retry;

  /// Fallback behavior after definitive failure (applied by the
  /// orchestrator, never by the runner).
  final FallbackPolicy fallback;

  /// Operator-controlled prefix prepended to the built system prompt.
  final String systemPrompt;

  /// Free-form extra instructions appended to the system prompt.
  final String customInstructions;

  /// Reasoning-effort hint for backends that support it (`low`/`medium`/
  /// `high`); advisory only, ignored otherwise.
  final String? reasoningEffort;

  /// Max concurrent turns for this agent (arena scheduler hint, >= 1).
  final int concurrencyLimit;

  /// Creates an agent config.
  const AgentConfig({
    required this.id,
    required this.name,
    required this.providerId,
    required this.model,
    this.baseUrl,
    this.apiKeyRef,
    this.temperature = 0.7,
    this.maxTokens = 1024,
    this.timeoutMs = 60000,
    this.retry = const RetryPolicy(),
    this.fallback = const FallbackPolicy(),
    this.systemPrompt = '',
    this.customInstructions = '',
    this.reasoningEffort,
    this.concurrencyLimit = 1,
  });

  /// Per-attempt timeout as a [Duration].
  Duration get timeout => Duration(milliseconds: timeoutMs);

  /// Validates field ranges/values, returning a list of human-readable
  /// problems (empty = valid).
  List<String> validate() {
    final problems = <String>[];
    if (id.trim().isEmpty) problems.add('id must not be empty.');
    if (name.trim().isEmpty) problems.add('name must not be empty.');
    if (model.trim().isEmpty) problems.add('model must not be empty.');
    if (temperature.isNaN || temperature < 0 || temperature > 2) {
      problems.add('temperature must be within 0..2.');
    }
    if (maxTokens <= 0) problems.add('maxTokens must be positive.');
    if (timeoutMs <= 0) problems.add('timeoutMs must be positive.');
    if (retry.maxRetries < 0) problems.add('retry.maxRetries must be >= 0.');
    if (retry.baseDelayMs < 0) {
      problems.add('retry.baseDelayMs must be >= 0.');
    }
    if (retry.backoffFactor < 1) {
      problems.add('retry.backoffFactor must be >= 1.');
    }
    if (fallback.enabled &&
        fallback.mode != FallbackPolicy.modeRandomLegal) {
      problems.add('fallback.mode "${fallback.mode}" is not supported.');
    }
    if (reasoningEffort != null &&
        !{'low', 'medium', 'high'}.contains(reasoningEffort)) {
      problems.add('reasoningEffort must be low, medium or high.');
    }
    if (concurrencyLimit < 1) {
      problems.add('concurrencyLimit must be >= 1.');
    }
    if (baseUrl != null) {
      for (final problem in validateBaseUrl(baseUrl)) {
        problems.add(problem);
      }
    }
    return problems;
  }

  /// Serializes to JSON.
  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'providerId': providerId.name,
        'model': model,
        if (baseUrl != null) 'baseUrl': baseUrl,
        if (apiKeyRef != null) 'apiKeyRef': apiKeyRef,
        'temperature': temperature,
        'maxTokens': maxTokens,
        'timeoutMs': timeoutMs,
        'retry': retry.toJson(),
        'fallback': fallback.toJson(),
        'systemPrompt': systemPrompt,
        'customInstructions': customInstructions,
        if (reasoningEffort != null) 'reasoningEffort': reasoningEffort,
        'concurrencyLimit': concurrencyLimit,
      };

  /// Parses from JSON; unknown [ProviderId] names fall back to
  /// [ProviderId.mock] so stored configs stay loadable. Missing scalar keys
  /// fall back to constructor defaults.
  factory AgentConfig.fromJson(Map json) {
    int asInt(Object? value, int fallback) =>
        value is int ? value : int.tryParse('$value') ?? fallback;
    double asDouble(Object? value, double fallback) =>
        value is num ? value.toDouble() : double.tryParse('$value') ?? fallback;
    ProviderId providerFrom(Object? value) {
      for (final candidate in ProviderId.values) {
        if (candidate.name == '$value') return candidate;
      }
      return ProviderId.mock;
    }

    final retryRaw = json['retry'];
    final fallbackRaw = json['fallback'];
    return AgentConfig(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      providerId: providerFrom(json['providerId']),
      model: '${json['model'] ?? ''}',
      baseUrl:
          json['baseUrl'] is String ? json['baseUrl'] as String : null,
      apiKeyRef:
          json['apiKeyRef'] is String ? json['apiKeyRef'] as String : null,
      temperature: asDouble(json['temperature'], 0.7),
      maxTokens: asInt(json['maxTokens'], 1024),
      timeoutMs: asInt(json['timeoutMs'], 60000),
      retry: retryRaw is Map ? RetryPolicy.fromJson(retryRaw) : const RetryPolicy(),
      fallback: fallbackRaw is Map
          ? FallbackPolicy.fromJson(fallbackRaw)
          : const FallbackPolicy(),
      systemPrompt:
          json['systemPrompt'] is String ? json['systemPrompt'] as String : '',
      customInstructions: json['customInstructions'] is String
          ? json['customInstructions'] as String
          : '',
      reasoningEffort: json['reasoningEffort'] is String
          ? json['reasoningEffort'] as String
          : null,
      concurrencyLimit: asInt(json['concurrencyLimit'], 1),
    );
  }

  /// Copies with selectively replaced fields.
  AgentConfig copyWith({
    String? id,
    String? name,
    ProviderId? providerId,
    String? model,
    String? baseUrl,
    String? apiKeyRef,
    double? temperature,
    int? maxTokens,
    int? timeoutMs,
    RetryPolicy? retry,
    FallbackPolicy? fallback,
    String? systemPrompt,
    String? customInstructions,
    String? reasoningEffort,
    int? concurrencyLimit,
  }) {
    return AgentConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      providerId: providerId ?? this.providerId,
      model: model ?? this.model,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKeyRef: apiKeyRef ?? this.apiKeyRef,
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
      timeoutMs: timeoutMs ?? this.timeoutMs,
      retry: retry ?? this.retry,
      fallback: fallback ?? this.fallback,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      customInstructions: customInstructions ?? this.customInstructions,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
      concurrencyLimit: concurrencyLimit ?? this.concurrencyLimit,
    );
  }
}

/// Default API roots per provider (used when [AgentConfig.baseUrl] is null).
const Map<ProviderId, String> defaultBaseUrls = {
  ProviderId.openai: 'https://api.openai.com/v1',
  ProviderId.anthropic: 'https://api.anthropic.com',
  ProviderId.gemini: 'https://generativelanguage.googleapis.com',
  ProviderId.ollama: ollamaDefaultBaseUrl,
  ProviderId.mock: '',
};

/// Materializes the [LlmProvider] for [config].
///
/// * [apiKeyResolver] maps [AgentConfig.apiKeyRef] to the real secret and is
///   provided by the storage layer; when `null` (or the ref is `null`), an
///   empty key is used, which is fine for keyless backends (Ollama, mock).
/// * [httpClient] is forwarded to network providers for client sharing or
///   test fakes.
/// * Mock configs ignore keys/URLs and yield a [MockProvider] with the
///   default demo script (scripted scenarios are built by constructing
///   [MockProvider] directly).
///
/// The caller owns the returned provider (call `close()` on network
/// providers that created their own client — or, preferably, pass a shared
/// [httpClient]).
LlmProvider createProvider(
  AgentConfig config, {
  ApiKeyResolver? apiKeyResolver,
  http.Client? httpClient,
}) {
  final ref = config.apiKeyRef;
  final apiKey = ref == null ? '' : (apiKeyResolver?.call(ref) ?? '');
  final baseUrl = config.baseUrl;
  switch (config.providerId) {
    case ProviderId.openai:
      return OpenAiProvider(
        baseUrl: baseUrl ?? defaultBaseUrls[ProviderId.openai]!,
        apiKey: apiKey,
        model: config.model,
        httpClient: httpClient,
      );
    case ProviderId.anthropic:
      return AnthropicProvider(
        baseUrl: baseUrl ?? defaultBaseUrls[ProviderId.anthropic]!,
        apiKey: apiKey,
        model: config.model,
        httpClient: httpClient,
      );
    case ProviderId.gemini:
      return GeminiProvider(
        baseUrl: baseUrl ?? defaultBaseUrls[ProviderId.gemini]!,
        apiKey: apiKey,
        model: config.model,
        httpClient: httpClient,
      );
    case ProviderId.ollama:
      return OllamaProvider(
        baseUrl: baseUrl ?? defaultBaseUrls[ProviderId.ollama]!,
        apiKey: apiKey,
        model: config.model,
        httpClient: httpClient,
      );
    case ProviderId.mock:
      return MockProvider(model: config.model);
  }
}

/// Re-exports the tool name so agent-layer code can reference the contract
/// without importing the llm schema file directly.
String get agentToolName => chessMoveToolName;

/// Validates a provider `baseUrl`, returning human-readable problems.
///
/// Rules (defense against SSRF-adjacent misconfiguration and credential
/// leaks):
/// * Must parse and use `http` or `https` (`http:` with an empty host,
///   `ftp:`, … are rejected — the old `hasScheme`-only check let them
///   through, and `Uri.parse('$_base/...')` string-concatenation would
///   then build attacker-shaped URLs).
/// * Embedded userinfo (`https://user:pass@host/`) is rejected — it would
///   ship credentials to the endpoint and usually indicates a pasted
///   secret rather than an intentional base URL.
/// * Plain `http` to a non-loopback host is flagged: remote traffic must
///   be encrypted. Loopback `http` (`localhost`, `127.0.0.1`, `[::1]`)
///   stays allowed — local Ollama serves exactly that.
List<String> validateBaseUrl(String? baseUrl) {
  if (baseUrl == null) return const [];
  final parsed = Uri.tryParse(baseUrl);
  if (parsed == null || !parsed.hasAuthority) {
    return ['baseUrl "$baseUrl" is not a valid absolute URL.'];
  }
  final problems = <String>[];
  final scheme = parsed.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    problems.add(
      'baseUrl "$baseUrl" must use http or https (got "$scheme").',
    );
  }
  if (parsed.userInfo.isNotEmpty) {
    problems.add(
      'baseUrl "$baseUrl" must not embed userinfo (credentials in URLs '
      'leak to logs and intermediaries).',
    );
  }
  if (scheme == 'http' && !_isLoopbackHost(parsed.host)) {
    problems.add(
      'baseUrl "$baseUrl" uses plain http to a non-loopback host; '
      'use https so API keys and prompts are encrypted in transit.',
    );
  }
  return problems;
}

/// Whether [host] is a loopback address (`localhost`, IPv4/IPv6 loopback).
bool _isLoopbackHost(String host) {
  final normalized = host.toLowerCase();
  if (normalized == 'localhost') return true;
  if (normalized == '127.0.0.1') return true;
  if (normalized == '[::1]' || normalized == '::1') return true;
  return false;
}

/// Minimal read side of the secure key store contract.
///
/// Mirrors the `SecureKeyStore.readApiKey` API owned by the storage layer
/// (`lib/src/storage/secure_key_store.dart`, backed by
/// flutter_secure_storage). Declared here so the agent layer's
/// [resolveApiKey] can accept it without importing Flutter or the storage
/// layer (which the agent layer must not depend on).
abstract class SecureKeyReader {
  /// Returns the secret stored under [ref], or `null` when absent.
  Future<String?> readApiKey(String ref);
}

/// Resolves [config]'s API key via the secure key store.
///
/// The provider-creation path ([createProvider]) takes a synchronous
/// [ApiKeyResolver]; secure storage is async, so UI/startup code must
/// first `await` this helper and then hand the secret to [createProvider]
/// via `apiKeyResolver: (_) => key`. [AgentConfig] keeps storing only the
/// opaque [AgentConfig.apiKeyRef] — the secret itself is never written
/// into any config, log, or Hive box.
///
/// ```dart
/// final key = await resolveApiKey(config, secureKeyStore);
/// final provider = createProvider(
///   config,
///   apiKeyResolver: (_) => key,
///   httpClient: sharedClient,
/// );
/// ```
///
/// Returns `''` when the config carries no ref or the store holds no
/// secret (correct for keyless backends: Ollama, mock).
Future<String> resolveApiKey(
  AgentConfig config,
  SecureKeyReader keyStore,
) async {
  final ref = config.apiKeyRef;
  if (ref == null || ref.isEmpty) return '';
  try {
    return await keyStore.readApiKey(ref) ?? '';
  } catch (_) {
    return '';
  }
}
