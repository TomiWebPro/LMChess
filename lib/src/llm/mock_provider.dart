/// Scripted mock provider for demos, arena runs without API keys, and
/// pipeline development.
///
/// The [script] is an ordered queue whose items are either [MoveToolCall]
/// (a move to play) or [FailureKind] (a failure to simulate — anything other
/// than [FailureKind.valid]). Each [streamMove] call consumes the next item
/// and replays it with artificial streaming delays ([stepDelay]) so UI
/// streaming paths exercise realistically: `started → [textDelta] →
/// toolCallDelta* → toolCallCompleted → usage → latency → done` for moves,
/// or `started → error/errorRetry` for scripted failures.
///
/// When the script is exhausted, further turns emit a non-retryable
/// `error` (rather than inventing moves). An empty script defaults to a
/// single `e2e4` demo move.
///
/// Pure Dart, no I/O. [testConnection] always returns `true`.
library;

import 'provider.dart';
import 'tool_schema.dart';
import 'validation.dart';

/// Scripted in-process provider.
class MockProvider extends LlmProvider {
  /// Ordered queue of [MoveToolCall] or [FailureKind] items.
  final List<Object> script;

  /// Artificial delay between emitted events.
  final Duration stepDelay;

  /// Reported model label (observability only).
  final String model;

  int _cursor = 0;

  /// Creates a mock provider.
  ///
  /// Items of [script] must be [MoveToolCall] or [FailureKind]; anything
  /// else surfaces as an `internal` error event at stream time.
  MockProvider({
    List<Object>? script,
    this.stepDelay = const Duration(milliseconds: 20),
    this.model = 'mock',
  }) : script = script ??
            [
              MoveToolCall(from: 'e2', to: 'e4', phrase: 'Demo opening'),
            ];

  /// Number of script items consumed so far.
  int get consumed => _cursor;

  /// Number of script items remaining.
  int get remaining =>
      script.length - _cursor < 0 ? 0 : script.length - _cursor;

  /// Resets the script cursor to the beginning.
  void reset() {
    _cursor = 0;
  }

  @override
  ProviderId get id => ProviderId.mock;

  @override
  LlmCapabilities get capabilities => const LlmCapabilities(
        supportsTools: true,
        supportsStreaming: true,
        supportsReasoning: false,
        friendlyName: 'Mock (scripted)',
      );

  @override
  Future<bool> testConnection() async => true;

  @override
  void close() {
    // In-process scripted provider: nothing to release.
  }

  @override
  Stream<LlmStreamEvent> streamMove(AgentRequest request) async* {
    final stopwatch = Stopwatch()..start();
    yield const LlmStreamEvent(kind: StreamEventKind.started);

    if (request.cancelToken?.isCancelled ?? false) {
      yield LlmStreamEvent(
        kind: StreamEventKind.error,
        message: '${FailureKind.cancelled.name}: turn cancelled before send.',
      );
      return;
    }

    if (_cursor >= script.length) {
      // Non-retryable on purpose: exhaustion is deterministic — retrying
      // the same empty queue would burn `maxRetries` attempts plus backoff
      // for a failure that can never heal.
      yield LlmStreamEvent(
        kind: StreamEventKind.error,
        message:
            '${FailureKind.incompleteResponse.name}: mock script exhausted.',
      );
      return;
    }

    final item = script[_cursor];
    _cursor++;

    if (item is FailureKind) {
      await Future<void>.delayed(stepDelay);
      if (item == FailureKind.valid) {
        // `valid` is not a failure: treat a stray entry as a no-op error so
        // the runner never receives an ambiguous turn.
        yield LlmStreamEvent(
          kind: StreamEventKind.error,
          message:
              '${FailureKind.internal.name}: scripted FailureKind.valid '
              'carries no move; use a MoveToolCall entry instead.',
        );
        return;
      }
      final retryable = item == FailureKind.rateLimit ||
          item == FailureKind.providerError ||
          item == FailureKind.timeout ||
          item == FailureKind.incompleteResponse;
      yield LlmStreamEvent(
        kind: retryable ? StreamEventKind.errorRetry : StreamEventKind.error,
        message: '${item.name}: scripted ${item.name} failure.',
      );
      return;
    }

    if (item is! MoveToolCall) {
      yield LlmStreamEvent(
        kind: StreamEventKind.error,
        message:
            '${FailureKind.internal.name}: invalid mock script entry '
            '(${item.runtimeType}); want MoveToolCall or FailureKind.',
      );
      return;
    }

    final argsJson = item.toJson();
    // Remove nulls so the replayed JSON matches real provider payloads.
    argsJson.removeWhere((key, value) => value == null);

    await Future<void>.delayed(stepDelay);
    yield LlmStreamEvent(
      kind: StreamEventKind.status,
      message: 'mock $model thinking',
    );
    if (item.phrase != null && item.phrase!.isNotEmpty) {
      await Future<void>.delayed(stepDelay);
      yield LlmStreamEvent(
        kind: StreamEventKind.textDelta,
        text: item.phrase,
      );
    }
    await Future<void>.delayed(stepDelay);
    final encoded = _encode(argsJson);
    yield LlmStreamEvent(
      kind: StreamEventKind.toolCallDelta,
      toolName: chessMoveToolName,
      toolArgsJson: encoded,
    );
    await Future<void>.delayed(stepDelay);
    yield LlmStreamEvent(
      kind: StreamEventKind.toolCallCompleted,
      toolName: chessMoveToolName,
      toolArgsJson: encoded,
    );
    yield const LlmStreamEvent(
      kind: StreamEventKind.usage,
      tokensIn: 128,
      tokensOut: 16,
    );
    stopwatch.stop();
    yield LlmStreamEvent(
      kind: StreamEventKind.latency,
      latencyMs: stopwatch.elapsedMilliseconds,
    );
    yield const LlmStreamEvent(kind: StreamEventKind.done);
  }

  String _encode(Map<String, Object?> argsJson) {
    final entries = argsJson.entries.map((e) {
      final value = e.value;
      final rendered =
          value is String ? '"${value.replaceAll('"', '\\"')}"' : '$value';
      return '"${e.key}":$rendered';
    });
    return '{${entries.join(',')}}';
  }
}
