/// Turn execution: prompt building, streaming, per-attempt timeouts, retries
/// with exponential backoff, and tool-call validation.
///
/// Pure Dart. The single entry point is [AgentRunner.runTurn].
///
/// Clock contract (important — the runner owns **no** clock):
/// * The chess clock keeps running for the whole duration of [runTurn],
///   **including** retries and backoff sleeps. The runner never starts,
///   stops or consumes any clock.
/// * The orchestrator measures the wall-clock elapsed around [runTurn] and
///   calls `ChessClock.consume` itself; flag/timeout adjudication also lives
///   with the orchestrator (see the timeout-vs-move race handling there).
///
/// Fallback contract: the runner **never** picks a fallback move. It returns
/// the first valid move, or the last failure wrapped in [TurnFailure]; the
/// orchestrator alone decides whether a seeded random-legal fallback applies.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../llm/provider.dart';
import '../llm/tool_schema.dart';
import '../llm/validation.dart';
import 'agent_config.dart';

/// Input describing one agent turn.
class AgentTurnRequest {
  /// Opaque position payload (FEN/JSON) kept for logging and compatibility.
  ///
  /// It is **not** rendered into the prompt: [boardText] is the only board
  /// content the model sees.
  final String positionFenOrJson;

  /// Engine-provided moves used for validation (standard) and mock scripting.
  ///
  /// Never rendered into the prompt: the model is asked for its natural move
  /// rather than told which moves exist.
  final List<String> legalMovesUci;

  /// Pre-rendered, perspective-correct board diagram
  /// (`renderBoardForPrompt`). The exact same format is used by both modes.
  final String boardText;

  /// Game mode label (`standard` / `chaotic`); internal only, never prompted.
  final String mode;

  /// Side to move (`w`/`b` or `white`/`black`).
  final String color;

  /// When true, any well-formed move is accepted without a legal-list check.
  ///
  /// Chaotic turns set this: the variant's interpretation pipeline decides what
  /// the attempt means. Standard turns leave it false. The prompt is identical
  /// either way, so the captured model output stays comparable.
  final bool acceptAnyMove;

  /// Optional remaining-time snapshot (not rendered; retained for future use).
  final Map<String, int>? timersMs;

  /// Castling rights for the side(s) with rights, in `KQkq` order, or `-`.
  final String castlingRights;

  /// En-passant target square name (`'d6'`), or `-` when none.
  final String enPassantTarget;

  /// Creates a turn request.
  const AgentTurnRequest({
    required this.positionFenOrJson,
    required this.legalMovesUci,
    required this.boardText,
    required this.mode,
    required this.color,
    this.acceptAnyMove = false,
    this.timersMs,
    this.castlingRights = '-',
    this.enPassantTarget = '-',
  });
}

/// Definitive failure of a turn (all attempts exhausted or fast-failed).
class TurnFailure {
  /// Machine-readable failure kind of the last attempt.
  final FailureKind kind;

  /// Human-readable explanation of the last attempt.
  final String message;

  /// Number of attempts actually made (>= 1).
  final int attempts;

  /// Creates a turn failure record.
  const TurnFailure({
    required this.kind,
    required this.message,
    required this.attempts,
  });

  /// Serializes to JSON.
  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'message': message,
        'attempts': attempts,
      };
}

/// Result of [AgentRunner.runTurn].
class AgentTurnResult {
  /// Validation outcome of the final attempt (valid on success).
  final ValidationOutcome outcome;

  /// Every stream event observed across all attempts, in order.
  final List<LlmStreamEvent> events;

  /// Total wall-clock time of the turn in ms (attempts + backoff sleeps).
  final int latencyMs;

  /// Last reported token usage, if any backend usage event arrived.
  final LlmUsage? usage;

  /// The legal move, present only when [outcome] is valid.
  final MoveToolCall? selectedMove;

  /// Definitive failure descriptor, present only on failure paths.
  final TurnFailure? failure;

  /// Creates a turn result.
  const AgentTurnResult({
    required this.outcome,
    required this.events,
    required this.latencyMs,
    this.usage,
    this.selectedMove,
    this.failure,
  });

  /// Whether the turn produced a playable move.
  bool get isSuccess => outcome.isValid && selectedMove != null;
}

/// Executes agent turns against an [LlmProvider].
class AgentRunner {
  /// Injectable sleep used for backoff delays (defaults to
  /// [Future.delayed]); override in tests for instant retries.
  final Future<void> Function(Duration delay)? sleep;

  /// Creates a runner.
  const AgentRunner({this.sleep});

  /// Builds the per-turn user prompt: only the current board, rendered from
  /// the mover's perspective, plus the side to move.
  ///
  /// Deliberately contains **no** legal-move list, FEN/JSON payload, mode
  /// label, or clock data. Standard and chaotic turns share this exact format,
  /// so the captured model output is comparable; validation and variant
  /// interpretation happen after the turn, never as prompt hints.
  String buildUserPrompt(AgentTurnRequest turn) {
    final color =
        turn.color.trim().toLowerCase().startsWith('b') ? 'Black' : 'White';
    return 'Current board (you are $color; your pieces are at the bottom):\n'
        '${turn.boardText}\n'
        'Uppercase = White, lowercase = Black; "." = empty.\n'
        'Side to move: $color.\n'
        'Castling rights: ${turn.castlingRights}.\n'
        'En passant target: ${turn.enPassantTarget}.';
  }

  /// Runs one turn for [config] against [turn].
  ///
  /// Flow per attempt (up to `retry.maxRetries + 1` attempts):
  /// 1. Build system prompt (`config.systemPrompt` + `systemPromptBuilder`
  ///    + `config.customInstructions`) and user prompt, then stream events
  ///    from the provider with a per-attempt [AgentConfig.timeout] deadline.
  /// 2. Collect text (for observability), tool deltas, the completed tool
  ///    call, usage and error events.
  /// 3. Validate: a completed call is shape-checked; when
  ///    [AgentTurnRequest.acceptAnyMove] is false it must also be in
  ///    [AgentTurnRequest.legalMovesUci] (standard), while chaotic turns
  ///    accept any well-formed square pair for interpretation. Provider error
  ///    events map back to a [FailureKind] via their `<kind>: <detail>`
  ///    prefix; an ended stream with no tool call is `incompleteResponse`.
  ///
  /// Returns the first valid move immediately; otherwise retries when
  /// `retry.retryOn` contains the attempt's kind (with
  /// `retry.delayForAttempt` backoff between tries) and finally returns the
  /// last failure. [seed] is forwarded to backends that support it.
  /// [providerOverride] skips [createProvider] (tests, shared instances);
  /// [onEvent] receives each stream event live (the orchestrator uses it to
  /// re-broadcast `aiStream` game events while the turn is in flight).
  /// [apiKeyResolver]/[httpClient] are forwarded to [createProvider] when no
  /// override is given.
  ///
  /// [cancelToken] is an optional cooperative cancellation handle (see
  /// [CancelToken] in `lib/src/llm/provider.dart`). It is checked before
  /// each attempt and forwarded inside the [AgentRequest] so providers
  /// abort mid-stream; a cancelled turn resolves promptly to a
  /// non-retryable [FailureKind.cancelled] outcome. `null` (the default)
  /// preserves the legacy behavior — no cancellation. Intended
  /// orchestrator wiring (that file is owned by another agent): create one
  /// token per AI turn, pass it here, and call `cancel()` when a new game
  /// starts mid-turn (`stop`/`resign`/`reportTerminal`/`dispose`); the
  /// generation-side stale-completion discard stays authoritative.
  Future<AgentTurnResult> runTurn(
    AgentConfig config,
    AgentTurnRequest turn, {
    int? seed,
    LlmProvider? providerOverride,
    void Function(LlmStreamEvent event)? onEvent,
    ApiKeyResolver? apiKeyResolver,
    http.Client? httpClient,
    CancelToken? cancelToken,
  }) async {
    bool cancelled() => cancelToken?.isCancelled ?? false;
    ValidationOutcome cancelledOutcome() => const ValidationOutcome(
          kind: FailureKind.cancelled,
          error: 'Turn cancelled.',
        );
    final stopwatch = Stopwatch()..start();
    final provider =
        providerOverride ?? createProvider(config, apiKeyResolver: apiKeyResolver, httpClient: httpClient);
    final ownsProvider = providerOverride == null && httpClient == null;

    final systemParts = [
      if (config.systemPrompt.trim().isNotEmpty) config.systemPrompt.trim(),
      systemPromptBuilder(color: turn.color),
      if (config.customInstructions.trim().isNotEmpty)
        config.customInstructions.trim(),
    ];
    // toolsJson: null → each provider uses its NATIVE default envelope
    // (OpenAI `type: function` shape for OpenAI/Ollama, `input_schema` for
    // Anthropic, `function_declarations` for Gemini). Passing the OpenAI
    // envelope explicitly here used to break live Anthropic/Gemini calls,
    // whose wire shapes differ.
    final agentRequest = AgentRequest(
      systemPrompt: systemParts.join('\n\n'),
      userPrompt: buildUserPrompt(turn),
      toolsJson: null,
      temperature: config.temperature,
      maxTokens: config.maxTokens,
      seed: seed,
      cancelToken: cancelToken,
    );

    final legalSet = {
      for (final move in turn.legalMovesUci) move.toLowerCase(),
    };
    bool isLegal(MoveToolCall call) =>
        turn.acceptAnyMove || legalSet.contains(call.uci.toLowerCase());

    final allEvents = <LlmStreamEvent>[];
    LlmUsage? usage;
    var lastOutcome = const ValidationOutcome(
      kind: FailureKind.internal,
      error: 'Turn produced no attempts.',
    );
    var attempts = 0;
    final maxAttempts = config.retry.maxRetries + 1;

    try {
      while (true) {
        if (cancelled()) {
          lastOutcome = cancelledOutcome();
          break;
        }
        attempts++;
        final outcome = await _runAttempt(
          provider: provider,
          request: agentRequest,
          timeout: config.timeout,
          isLegal: isLegal,
          normalizeCastlingAliases: !turn.acceptAnyMove,
          onEvent: (event) {
            allEvents.add(event);
            onEvent?.call(event);
            if (event.kind == StreamEventKind.usage) {
              // Sum across attempts: retries each report their own usage,
              // and keeping only the last would undercount billed tokens.
              usage = LlmUsage(
                inputTokens: (usage?.inputTokens ?? 0) + (event.tokensIn ?? 0),
                outputTokens:
                    (usage?.outputTokens ?? 0) + (event.tokensOut ?? 0),
              );
            }
          },
        );
        lastOutcome = outcome;
        if (outcome.isValid) {
          stopwatch.stop();
          return AgentTurnResult(
            outcome: outcome,
            events: List.unmodifiable(allEvents),
            latencyMs: stopwatch.elapsedMilliseconds,
            usage: usage,
            selectedMove: outcome.toolCall,
          );
        }
        final canRetry = attempts < maxAttempts &&
            config.retry.retryOn.contains(outcome.kind);
        if (!canRetry) break;
        if (cancelled()) {
          lastOutcome = cancelledOutcome();
          break;
        }
        await _sleep(config.retry.delayForAttempt(attempts - 1));
      }
    } finally {
      // Providers created internally (own HTTP client) are closed
      // polymorphically via the `LlmProvider.close()` interface; shared or
      // overridden providers stay open for the caller.
      if (ownsProvider) {
        provider.close();
      }
    }

    stopwatch.stop();
    return AgentTurnResult(
      outcome: lastOutcome,
      events: List.unmodifiable(allEvents),
      latencyMs: stopwatch.elapsedMilliseconds,
      usage: usage,
      failure: TurnFailure(
        kind: lastOutcome.kind,
        message: lastOutcome.error ?? lastOutcome.kind.name,
        attempts: attempts,
      ),
    );
  }

  Future<void> _sleep(Duration delay) {
    final custom = sleep;
    if (custom != null) return custom(delay);
    return Future<void>.delayed(delay);
  }

  /// Decodes a completed tool-argument JSON document, returning the [Map]
  /// on success or a failure [ValidationOutcome] when it is not valid JSON
  /// or not an object.
  Object _decodeArgs(String toolArgsJson, String? rawText) {
    try {
      final decoded = jsonDecode(toolArgsJson);
      if (decoded is! Map) {
        return ValidationOutcome(
          kind: FailureKind.unparseableResponse,
          error: 'Tool arguments are not a JSON object: $toolArgsJson',
          rawText: rawText,
        );
      }
      return decoded;
    } catch (e) {
      return ValidationOutcome(
        kind: FailureKind.unparseableResponse,
        error: 'Tool arguments are not valid JSON: $e',
        rawText: rawText,
      );
    }
  }

  /// Streams a single attempt and validates it, returning the outcome.
  /// Never throws: transport/stream errors become failure outcomes.
  Future<ValidationOutcome> _runAttempt({
    required LlmProvider provider,
    required AgentRequest request,
    required Duration timeout,
    required bool Function(MoveToolCall) isLegal,
    required void Function(LlmStreamEvent) onEvent,
    required bool normalizeCastlingAliases,
  }) async {
    String? toolName;
    String? toolArgsJson;
    var toolCallCount = 0;
    final textBuffer = StringBuffer();
    FailureKind? streamErrorKind;
    String? streamErrorMessage;

    // A hard total deadline, not `Stream.timeout` (which is an inactivity
    // timeout and never fires while a provider trickles one delta just under
    // the gap). The subscription is cancelled as soon as the deadline wins.
    var timedOut = false;
    var streamDone = false;
    Object? streamFailure;
    final finished = Completer<void>();
    final timer = Timer(timeout, () {
      timedOut = true;
      if (!finished.isCompleted) finished.complete();
    });
    StreamSubscription<LlmStreamEvent>? subscription;
    try {
      subscription = provider.streamMove(request).listen(
        (event) {
          onEvent(event);
          if (event.kind == StreamEventKind.textDelta && event.text != null) {
            textBuffer.write(event.text);
          }
          switch (event.kind) {
            case StreamEventKind.toolCallCompleted:
              // Providers normally emit at most one; count them so an
              // ambiguous multi-call turn fails loudly instead of
              // last-wins playing an arbitrary pick (see below).
              toolCallCount++;
              toolName = event.toolName;
              toolArgsJson = event.toolArgsJson;
            case StreamEventKind.error:
            case StreamEventKind.errorRetry:
              streamErrorKind ??= tryParseFailureKind(event.message) ??
                  FailureKind.providerError;
              streamErrorMessage ??= event.message;
            case StreamEventKind.started:
            case StreamEventKind.status:
            case StreamEventKind.textDelta:
            case StreamEventKind.toolCallDelta:
            case StreamEventKind.usage:
            case StreamEventKind.latency:
            case StreamEventKind.done:
              break;
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          streamFailure = error;
          if (!finished.isCompleted) finished.complete();
        },
        onDone: () {
          streamDone = true;
          if (!finished.isCompleted) finished.complete();
        },
      );
    } catch (e) {
      timer.cancel();
      return ValidationOutcome(
        kind: FailureKind.internal,
        error: 'Streaming failed: $e',
        rawText: textBuffer.isEmpty ? null : textBuffer.toString(),
      );
    }
    try {
      await finished.future;
    } finally {
      timer.cancel();
      // A normally-closed subscription is already done; cancelling it again
      // can keep a future pending on some async* implementations under the
      // test scheduler. Only cancel when the deadline/error cut it short.
      if (!streamDone) {
        await subscription.cancel();
      }
    }

    if (timedOut) {
      return ValidationOutcome(
        kind: FailureKind.timeout,
        error: 'Attempt exceeded ${timeout.inMilliseconds}ms.',
        rawText: textBuffer.isEmpty ? null : textBuffer.toString(),
      );
    }
    if (streamFailure != null) {
      return ValidationOutcome(
        kind: FailureKind.internal,
        error: 'Streaming failed: $streamFailure',
        rawText: textBuffer.isEmpty ? null : textBuffer.toString(),
      );
    }

    final rawText = textBuffer.isEmpty ? null : textBuffer.toString();

    if (toolCallCount > 1) {
      // Ambiguous: the turn produced several complete tool calls and any
      // single pick would be arbitrary. Fail loudly with malformedArgs
      // (non-retryable by default) instead of validating last-wins.
      return ValidationOutcome(
        kind: FailureKind.malformedArgs,
        error: 'Model emitted $toolCallCount tool calls in one turn; '
            'want exactly one "$chessMoveToolName" call.',
        rawText: rawText,
      );
    }
    final argsText = toolArgsJson;
    if (argsText != null) {
      if (toolName != null && toolName != chessMoveToolName) {
        return ValidationOutcome(
          kind: FailureKind.missingToolCall,
          error: 'Unexpected tool "$toolName"; want "$chessMoveToolName".',
          rawText: rawText,
        );
      }
      final argsJson = _decodeArgs(argsText, rawText);
      if (argsJson is ValidationOutcome) return argsJson;
      return validateToolCall(
        argsJson: argsJson as Map,
        rawText: rawText,
        isLegal: isLegal,
        // Standard: accept "king to rook square" as castling when the real
        // castling move is legal. Chaotic: keep the attempt verbatim for
        // interpretation.
        normalizeCastlingAliases: normalizeCastlingAliases,
      );
    }

    final errorKind = streamErrorKind;
    if (errorKind != null) {
      return ValidationOutcome(
        kind: errorKind,
        error: streamErrorMessage ?? errorKind.name,
        rawText: rawText,
      );
    }
    return ValidationOutcome(
      kind: FailureKind.incompleteResponse,
      error: 'Stream ended without a $chessMoveToolName tool call.',
      rawText: rawText,
    );
  }
}

/// Computes exponential backoff delays without an [AgentRunner] (arena
/// scheduler reuse): `baseDelayMs * backoffFactor^attempt`, plus the same
/// uniform ±20% jitter as [RetryPolicy.delayForAttempt] (pass a seeded
/// [random] for deterministic tests).
Duration backoffDelay({
  required int baseDelayMs,
  required double backoffFactor,
  required int attempt,
  Random? random,
}) {
  final base = baseDelayMs * pow(backoffFactor, max(0, attempt));
  final jitter = base * 0.2 * ((random ?? Random()).nextDouble() * 2 - 1);
  return Duration(milliseconds: (base + jitter).round().clamp(0, 1 << 62));
}
