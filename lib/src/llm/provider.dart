/// Core LLM provider abstractions: ids, capabilities, requests, streaming
/// events, usage, and the [LlmProvider] interface.
///
/// Pure Dart (package:http only at the implementation level, never
/// imported here). Providers stream normalized [LlmStreamEvent]s so the
/// agent runner can treat OpenAI, Anthropic, Gemini, Ollama and Mock
/// uniformly.
library;

/// Stable identifier for each supported LLM backend.
enum ProviderId {
  /// OpenAI chat/completions API (or any OpenAI-compatible endpoint
  /// configured with a custom `baseUrl`, e.g. OpenRouter).
  openai,

  /// Anthropic Messages API.
  anthropic,

  /// Google Generative Language API (`generateContent` family).
  gemini,

  /// Local Ollama server (OpenAI-compatible surface).
  ollama,

  /// Scripted in-process provider for demos / arena runs without API keys.
  mock,
}

/// Kinds of events emitted on an [LlmProvider.streamMove] stream.
///
/// The pipeline contract: every turn stream starts with [started] and ends
/// with exactly one terminal event — [done] on success, or [error]/[errorRetry]
/// on failure. [errorRetry] marks failures worth retrying under a
/// [RetryPolicy][1] (rate limits, transient 5xx, timeouts); [error] marks
/// terminal failures (auth, malformed config).
///
/// [1]: `RetryPolicy` lives in `lib/src/agent/agent_config.dart`.
enum StreamEventKind {
  /// Turn stream opened.
  started,

  /// Human-readable pipeline status (connecting, streaming, …).
  status,

  /// A chunk of plain (thinking) text from the model.
  textDelta,

  /// A chunk of partial tool-call arguments (raw, still incomplete).
  toolCallDelta,

  /// A complete tool call with fully assembled arguments.
  toolCallCompleted,

  /// Token usage reported by the backend (may arrive mid- or post-stream).
  usage,

  /// Wall-clock latency of the provider call in [LlmStreamEvent.latencyMs].
  latency,

  /// Terminal event: stream finished (success path — the runner still has to
  /// validate the tool call; `done` does not imply a legal move).
  done,

  /// Terminal event: retryable provider failure.
  errorRetry,

  /// Terminal event: non-retryable provider failure.
  error,
}

/// Static capability flags for a provider.
class LlmCapabilities {
  /// Whether the backend supports function/tool calling.
  final bool supportsTools;

  /// Whether token-by-token streaming is supported.
  final bool supportsStreaming;

  /// Whether the backend exposes a reasoning/thinking effort control.
  final bool supportsReasoning;

  /// Display name for settings screens and logs.
  final String friendlyName;

  /// Creates capability flags.
  const LlmCapabilities({
    required this.supportsTools,
    required this.supportsStreaming,
    required this.supportsReasoning,
    required this.friendlyName,
  });

  /// Serializes to JSON.
  Map<String, Object?> toJson() => {
        'supportsTools': supportsTools,
        'supportsStreaming': supportsStreaming,
        'supportsReasoning': supportsReasoning,
        'friendlyName': friendlyName,
      };
}

/// Cooperative cancellation token for one agent turn / provider stream.
///
/// A tiny shared-vocabulary class (no threads, no streams): the holder calls
/// [cancel]; producers poll [isCancelled] and abort promptly.
///
/// Intended wiring (documented here because the orchestrator file is owned
/// by another agent): the orchestrator creates one [CancelToken] per AI
/// turn, passes it to `AgentRunner.runTurn` (which forwards it inside
/// [AgentRequest]), and calls [cancel] from its `stop`/`resign`/
/// `reportTerminal`/`dispose` paths when a new game starts mid-turn. The
/// runner checks the token between attempts (a cancelled turn resolves to
/// a non-retryable [FailureKind.cancelled] outcome) and each provider
/// checks `request.cancelToken` before connecting and on every streamed
/// line, yielding a `cancelled` error event instead of hanging. The
/// orchestrator's generation-side stale-completion discard stays the
/// authoritative guard; the token only makes in-flight work stop early.
class CancelToken {
  bool _cancelled = false;

  /// Creates an uncancelled token.
  CancelToken();

  /// Whether [cancel] has been called.
  bool get isCancelled => _cancelled;

  /// Requests cancellation. Idempotent.
  void cancel() {
    _cancelled = true;
  }
}

/// One LLM move request: prompts + tool schemas + sampling controls.
class AgentRequest {
  /// System instruction (built from `systemPromptBuilder` + agent config).
  final String systemPrompt;

  /// Per-turn user message (position, legal moves, clocks, mode).
  final String userPrompt;

  /// Tool schemas in the provider's native envelope (usually a list with
  /// the single `make_chess_move` tool).
  ///
  /// `null` (the default) means "use the provider's native default schema"
  /// — the OpenAI envelope for OpenAI/Ollama, the `input_schema` envelope
  /// for Anthropic, the function-declaration envelope for Gemini. The
  /// agent runner always passes `null` so cross-provider calls cannot mix
  /// envelopes; pass an explicit list only when a test or tool needs to
  /// override the schema deliberately.
  final List<Map<String, Object>>? toolsJson;

  /// Sampling temperature.
  final double temperature;

  /// Backend token budget for the turn.
  final int maxTokens;

  /// Optional deterministic seed (supported backends only).
  final int? seed;

  /// Optional cooperative cancellation token (see [CancelToken]).
  ///
  /// `null` (the default) preserves the legacy behavior: no cancellation.
  /// Providers check this before connecting and while consuming the
  /// response stream; the runner checks it between attempts.
  final CancelToken? cancelToken;

  /// Creates a move request.
  const AgentRequest({
    required this.systemPrompt,
    required this.userPrompt,
    this.toolsJson,
    this.temperature = 0.7,
    this.maxTokens = 1024,
    this.seed,
    this.cancelToken,
  });
}

/// One normalized streaming event.
///
/// Conventions:
/// * `text` carries thinking/plain-text chunks ([StreamEventKind.textDelta]).
/// * `toolName` + `toolArgsJson` carry tool data: partial JSON fragments on
///   [StreamEventKind.toolCallDelta], the complete argument JSON document on
///   [StreamEventKind.toolCallCompleted].
/// * `message` carries status text or error details. Provider HTTP failures
///   use the documented prefix format `<failureKindName>: <detail>` (see
///   `tryParseFailureKind` in `validation.dart`) so the runner can recover a
///   typed [FailureKind] without provider-specific imports.
/// * `tokensIn`/`tokensOut` ride on [StreamEventKind.usage] events.
/// * `latencyMs` rides on [StreamEventKind.latency] events.
class LlmStreamEvent {
  /// Event discriminator.
  final StreamEventKind kind;

  /// Status text or error detail (`<failureKind>: <detail>` for errors).
  final String? message;

  /// Plain-text chunk (thinking output).
  final String? text;

  /// Tool name for tool-call events.
  final String? toolName;

  /// Raw tool-argument JSON: fragment ([StreamEventKind.toolCallDelta]) or
  /// complete document ([StreamEventKind.toolCallCompleted]).
  final String? toolArgsJson;

  /// Input tokens (usage events).
  final int? tokensIn;

  /// Output tokens (usage events).
  final int? tokensOut;

  /// Wall-clock latency in ms (latency events).
  final int? latencyMs;

  /// Creates a stream event.
  const LlmStreamEvent({
    required this.kind,
    this.message,
    this.text,
    this.toolName,
    this.toolArgsJson,
    this.tokensIn,
    this.tokensOut,
    this.latencyMs,
  });

  @override
  String toString() {
    final detail = message ?? text ?? toolName ?? '';
    return 'LlmStreamEvent(${kind.name}${
        detail.isEmpty ? '' : ', $detail'})';
  }
}

/// Token usage accumulated for one turn.
class LlmUsage {
  /// Input (prompt) tokens.
  final int inputTokens;

  /// Output (completion) tokens.
  final int outputTokens;

  /// Creates a usage record.
  const LlmUsage({this.inputTokens = 0, this.outputTokens = 0});

  /// Total tokens.
  int get totalTokens => inputTokens + outputTokens;

  /// Serializes to JSON.
  Map<String, Object?> toJson() =>
      {'inputTokens': inputTokens, 'outputTokens': outputTokens};

  /// Parses from JSON; missing keys default to 0, never throws on shapes
  /// produced by [toJson].
  factory LlmUsage.fromJson(Map json) {
    int asInt(Object? value) =>
        value is int ? value : int.tryParse('$value') ?? 0;
    return LlmUsage(
      inputTokens: asInt(json['inputTokens']),
      outputTokens: asInt(json['outputTokens']),
    );
  }
}

/// Interface every LLM backend implements.
///
/// Implementations must:
/// * be pure Dart (injectable `http.Client` for testability — see the
///   concrete providers),
/// * emit [StreamEventKind.started] first and exactly one of
///   [StreamEventKind.done]/[StreamEventKind.error]/[StreamEventKind.errorRetry]
///   last,
/// * **emit** error events for HTTP/API failures (401/429/5xx, timeouts)
///   instead of throwing, so the runner's retry policy can inspect them.
abstract class LlmProvider {
  /// Stable backend id.
  ProviderId get id;

  /// Static capability flags.
  LlmCapabilities get capabilities;

  /// Lightweight connectivity check (e.g. list-models ping).
  ///
  /// Returns `true` on success, `false` on any failure — never throws.
  Future<bool> testConnection();

  /// Streams one move turn for [request], mapping backend SSE/chunks to
  /// normalized [LlmStreamEvent]s.
  ///
  /// Implementations honor `request.cancelToken` cooperatively: they check
  /// it before connecting and while consuming the response stream, and
  /// yield a non-retryable `cancelled` error event (then return) when it
  /// fires.
  Stream<LlmStreamEvent> streamMove(AgentRequest request);

  /// Releases resources held by the provider (owned HTTP client, …).
  ///
  /// Providers that were constructed with a shared/injected client keep
  /// that client open; providers that minted their own close it. No-op
  /// implementations (e.g. the mock provider) are valid. The agent runner
  /// calls this polymorphically for providers it created itself.
  void close();
}
