/// Validation of `make_chess_move` tool calls: failure taxonomy, the
/// [ValidationOutcome] result type, [validateToolCall], and helpers that map
/// provider/HTTP failures onto [FailureKind].
///
/// Design rules:
/// * [validateToolCall] **never throws** and **never invents moves** — every
///   failure path returns a [ValidationOutcome] describing what went wrong.
/// * Error-carrying [LlmStreamEvent]s (see `provider.dart`) encode the
///   failure kind as a `<kindName>: <detail>` message prefix; use
///   [tryParseFailureKind] to recover it.
library;

import 'tool_schema.dart';

/// Machine-readable failure taxonomy for one agent-turn attempt.
///
/// The `valid` value doubles as the success marker so a single enum covers
/// both outcomes and retry-policy matching (`RetryPolicy.retryOn`).
enum FailureKind {
  /// A legal tool call was produced (success, not a failure).
  valid,

  /// Tool arguments were missing required fields or had the wrong shape.
  malformedArgs,

  /// The model answered without any `make_chess_move` tool call.
  missingToolCall,

  /// Tool arguments arrived but were not parseable JSON.
  unparseableResponse,

  /// The parsed move is not in the engine-provided legal move list.
  illegalMove,

  /// Generic provider/backend failure (5xx, network, unknown).
  providerError,

  /// Authentication failure (HTTP 401/403, bad key).
  authError,

  /// Rate limited (HTTP 429) or backend overloaded.
  rateLimit,

  /// Attempt exceeded its deadline.
  timeout,

  /// Stream ended (or errored) before a complete tool call arrived.
  incompleteResponse,

  /// Attempt was cancelled by the caller.
  cancelled,

  /// Unexpected internal error (callback threw, invariant violated, …).
  internal,
}

/// Result of validating one turn attempt.
///
/// On success ([kind] == [FailureKind.valid]) [toolCall] holds the legal,
/// engine-approved move. On failure [error] holds a human-readable
/// explanation and [rawText] optionally holds any thinking text the model
/// produced (useful for review/debugging; never played as a move).
class ValidationOutcome {
  /// What happened.
  final FailureKind kind;

  /// The legal move, present only when [kind] is [FailureKind.valid].
  final MoveToolCall? toolCall;

  /// Human-readable explanation, present on failure paths.
  final String? error;

  /// Raw thinking/text output captured alongside the attempt, if any.
  final String? rawText;

  /// Creates an outcome.
  const ValidationOutcome({
    required this.kind,
    this.toolCall,
    this.error,
    this.rawText,
  });

  /// Whether a legal move was produced.
  bool get isValid => kind == FailureKind.valid;

  @override
  String toString() =>
      'ValidationOutcome(${kind.name}${error == null ? '' : ', $error'})';
}

/// Validates one parsed tool call against shape rules and engine legality.
///
/// * [argsJson] — decoded tool-argument map, or `null` when the model made
///   no tool call (yields [FailureKind.missingToolCall]).
/// * [rawText] — thinking/text output captured during the attempt, kept for
///   observability only.
/// * [isLegal] — engine legality predicate over the parsed [MoveToolCall]
///   (typically a membership test against the legal UCI list). Exceptions
///   thrown by [isLegal] are converted to [FailureKind.internal], never
///   rethrown.
///
/// Never throws, never invents or repairs moves: anything ambiguous is a
/// failure outcome the retry/fallback layers handle explicitly.
ValidationOutcome validateToolCall({
  required Map? argsJson,
  required String? rawText,
  required bool Function(MoveToolCall) isLegal,
}) {
  try {
    if (argsJson == null) {
      return ValidationOutcome(
        kind: FailureKind.missingToolCall,
        error: 'Model responded without a make_chess_move tool call.',
        rawText: rawText,
      );
    }

    late final MoveToolCall call;
    try {
      call = MoveToolCall.fromJson(argsJson);
    } catch (e) {
      return ValidationOutcome(
        kind: FailureKind.malformedArgs,
        error: 'Tool arguments malformed: $e',
        rawText: rawText,
      );
    }

    // Variant-safe shape check: 2-4 alphanumerics for squares, single
    // q/r/b/n promotion. Standard squares ("e2") pass; larger chaotic
    // boards pass; garbage ("hello!", "") does not.
    final square = RegExp(r'^[a-z0-9]{2,4}$');
    if (!square.hasMatch(call.from.toLowerCase()) ||
        !square.hasMatch(call.to.toLowerCase())) {
      return ValidationOutcome(
        kind: FailureKind.malformedArgs,
        error: 'Malformed squares from="${call.from}" to="${call.to}".',
        rawText: rawText,
      );
    }
    if (call.promotion != null &&
        call.promotion!.isNotEmpty &&
        !RegExp(r'^[qrbn]$').hasMatch(call.promotion!.toLowerCase())) {
      return ValidationOutcome(
        kind: FailureKind.malformedArgs,
        error: 'Invalid promotion "${call.promotion}" (want q/r/b/n).',
        rawText: rawText,
      );
    }

    late final bool legal;
    try {
      legal = isLegal(call);
    } catch (e) {
      return ValidationOutcome(
        kind: FailureKind.internal,
        error: 'Legality check threw: $e',
        rawText: rawText,
      );
    }
    if (!legal) {
      return ValidationOutcome(
        kind: FailureKind.illegalMove,
        error: 'Move ${call.uci} is not legal in the current position.',
        rawText: rawText,
      );
    }
    return ValidationOutcome(kind: FailureKind.valid, toolCall: call);
  } catch (e) {
    // Absolute backstop: this function never throws.
    return ValidationOutcome(
      kind: FailureKind.internal,
      error: 'Unexpected validation error: $e',
      rawText: rawText,
    );
  }
}

/// Maps an HTTP status code to a [FailureKind].
///
/// 400 → [FailureKind.malformedArgs] (the request we built was rejected —
/// deliberately **not** retryable: resending the same bytes fails the same
/// way); 401/403 → [FailureKind.authError]; 408/429 →
/// [FailureKind.rateLimit]; 5xx → [FailureKind.providerError]; anything
/// else non-2xx → [FailureKind.providerError].
FailureKind failureKindForHttpStatus(int statusCode) {
  if (statusCode == 400) return FailureKind.malformedArgs;
  if (statusCode == 401 || statusCode == 403) return FailureKind.authError;
  if (statusCode == 408 || statusCode == 429) return FailureKind.rateLimit;
  if (statusCode >= 500 && statusCode < 600) return FailureKind.providerError;
  return FailureKind.providerError;
}

/// Whether [kind] is worth another attempt under a default [RetryPolicy].
///
/// Single source of truth for the provider-side `error` vs `errorRetry`
/// split: retryable kinds (rate limits, transient 5xx, timeouts,
/// truncated streams) surface as [StreamEventKind.errorRetry]; everything
/// else — auth, malformed requests, illegal moves, cancellations — as
/// [StreamEventKind.error]. The runner still applies the configured
/// `retry.retryOn` list, and additionally treats any `error` terminal as
/// fast-fail, so providers only need this helper to pick the event kind.
bool isRetryableFailureKind(FailureKind kind) {
  return kind == FailureKind.providerError ||
      kind == FailureKind.rateLimit ||
      kind == FailureKind.timeout ||
      kind == FailureKind.incompleteResponse;
}

/// Recovers a [FailureKind] from a provider error-event message.
///
/// Providers format error messages as `<failureKindName>: <detail>`; this
/// parses the prefix back. Returns `null` when [message] is null or carries
/// no recognizable prefix.
FailureKind? tryParseFailureKind(String? message) {
  if (message == null || message.isEmpty) return null;
  final prefix = message.split(':').first.trim();
  for (final kind in FailureKind.values) {
    if (kind.name == prefix) return kind;
  }
  return null;
}
