// Regression tests for [AgentRunner]: timeouts, cooperative cancellation,
// HTTP-failure retryability, ambiguous multi-tool-call turns, and usage
// accounting across retries.
//
// Everything runs in-process: a scripted fake provider and a fake
// `http.Client`. No network, no API keys, no real backoff sleeps.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:llm_chess_arena/src/agent/agent_config.dart';
import 'package:llm_chess_arena/src/agent/agent_runner.dart';
import 'package:llm_chess_arena/src/llm/mock_provider.dart';
import 'package:llm_chess_arena/src/llm/openai_provider.dart';
import 'package:llm_chess_arena/src/llm/provider.dart';
import 'package:llm_chess_arena/src/llm/tool_schema.dart';
import 'package:llm_chess_arena/src/llm/validation.dart';

const String _startFen =
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

const List<FailureKind> _defaultRetryOn = <FailureKind>[
  FailureKind.providerError,
  FailureKind.rateLimit,
  FailureKind.timeout,
  FailureKind.incompleteResponse,
];

AgentConfig _agent({
  int maxRetries = 2,
  int timeoutMs = 5000,
}) =>
    AgentConfig(
      id: 'agent-1',
      name: 'Agent One',
      providerId: ProviderId.mock,
      model: 'mock-1',
      timeoutMs: timeoutMs,
      retry: RetryPolicy(
        maxRetries: maxRetries,
        baseDelayMs: 0,
        backoffFactor: 1,
        retryOn: _defaultRetryOn,
      ),
    );

AgentConfig _httpAgent({
  int maxRetries = 2,
  int timeoutMs = 5000,
}) =>
    AgentConfig(
      id: 'agent-http',
      name: 'Agent HTTP',
      providerId: ProviderId.openai,
      baseUrl: 'https://example.test/v1',
      model: 'gpt-4o-mini',
      timeoutMs: timeoutMs,
      retry: RetryPolicy(
        maxRetries: maxRetries,
        baseDelayMs: 0,
        backoffFactor: 1,
        retryOn: _defaultRetryOn,
      ),
    );

const AgentTurnRequest _turn = AgentTurnRequest(
  positionFenOrJson: _startFen,
  legalMovesUci: <String>['e2e4', 'd2d4'],
  mode: 'standard',
  color: 'w',
);

/// Instant, deterministic retry backoff.
AgentRunner _runner() => AgentRunner(sleep: (_) async {});

/// Provider whose per-call streams are supplied by a builder.
typedef _StreamBuilder = Stream<LlmStreamEvent> Function(
    AgentRequest request, int call);

class _FakeProvider extends LlmProvider {
  _FakeProvider(this._build);

  final _StreamBuilder _build;
  int calls = 0;

  @override
  ProviderId get id => ProviderId.mock;

  @override
  LlmCapabilities get capabilities => const LlmCapabilities(
        supportsTools: true,
        supportsStreaming: true,
        supportsReasoning: false,
        friendlyName: 'fake',
      );

  @override
  Future<bool> testConnection() async => true;

  @override
  void close() {}

  @override
  Stream<LlmStreamEvent> streamMove(AgentRequest request) {
    final call = calls++;
    return _build(request, call);
  }
}

/// Fake HTTP client returning a fixed status code and a short error body.
class _StatusClient extends http.BaseClient {
  _StatusClient(this.statusCode);

  final int statusCode;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream<List<int>>.value('error'.codeUnits),
      statusCode,
    );
  }
}

/// Fake HTTP client that opens a 200 response whose body never emits a line.
class _StalledClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final controller = StreamController<List<int>>();
    return http.StreamedResponse(controller.stream, 200);
  }
}

LlmStreamEvent _toolCall(String from, String to) => LlmStreamEvent(
      kind: StreamEventKind.toolCallCompleted,
      toolName: chessMoveToolName,
      toolArgsJson: '{"from":"$from","to":"$to"}',
    );

void main() {
  group('timeout / inactivity', () {
    test('a slow provider yields a retryable timeout and does not hang',
        () async {
      final provider = MockProvider(
        script: <Object>[MoveToolCall(from: 'e2', to: 'e4')],
        stepDelay: const Duration(milliseconds: 300),
      );
      final sw = Stopwatch()..start();
      final result = await _runner().runTurn(
        _agent(maxRetries: 0, timeoutMs: 40),
        _turn,
        providerOverride: provider,
      );
      sw.stop();

      expect(result.isSuccess, isFalse);
      expect(result.failure, isNotNull);
      expect(result.failure!.kind, FailureKind.timeout);
      expect(isRetryableFailureKind(result.failure!.kind), isTrue);
      expect(sw.elapsedMilliseconds, lessThan(2000),
          reason: 'the turn must time out promptly, not hang');
    });

    test('a stalled HTTP stream (provider inactivity) times out', () async {
      // The provider owns an SSE inactivity timer; give it a short budget so
      // a server that opens a 200 stream and then sends nothing yields its
      // retryable `timeout` terminal instead of hanging the turn.
      final provider = OpenAiProvider(
        baseUrl: 'https://example.test/v1',
        apiKey: '',
        model: 'gpt-4o-mini',
        httpClient: _StalledClient(),
        timeout: const Duration(milliseconds: 50),
      );
      final sw = Stopwatch()..start();
      final result = await _runner().runTurn(
        _httpAgent(maxRetries: 0, timeoutMs: 5000),
        _turn,
        providerOverride: provider,
      );
      sw.stop();
      expect(result.failure!.kind, FailureKind.timeout);
      expect(isRetryableFailureKind(result.failure!.kind), isTrue);
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });
  });

  group('cooperative cancellation', () {
    test('CancelToken.cancel() aborts promptly with a non-retryable outcome',
        () async {
      final token = CancelToken();
      final provider = _FakeProvider((request, call) async* {
        yield const LlmStreamEvent(kind: StreamEventKind.started);
        for (var i = 0; i < 200; i++) {
          if (request.cancelToken?.isCancelled ?? false) {
            yield const LlmStreamEvent(
              kind: StreamEventKind.error,
              message: 'cancelled: turn cancelled mid-stream.',
            );
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        yield _toolCall('e2', 'e4');
        yield const LlmStreamEvent(kind: StreamEventKind.done);
      });

      final pending = _runner().runTurn(
        _agent(maxRetries: 2),
        _turn,
        providerOverride: provider,
        cancelToken: token,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final sw = Stopwatch()..start();
      token.cancel();
      final result = await pending;
      sw.stop();

      expect(result.isSuccess, isFalse);
      expect(result.failure!.kind, FailureKind.cancelled);
      expect(isRetryableFailureKind(FailureKind.cancelled), isFalse);
      expect(sw.elapsedMilliseconds, lessThan(1000),
          reason: 'abort must be prompt');
    });

    test('a pre-cancelled token short-circuits before any attempt', () async {
      final token = CancelToken()..cancel();
      final provider = _FakeProvider((request, call) async* {
        yield const LlmStreamEvent(kind: StreamEventKind.started);
      });
      final result = await _runner().runTurn(
        _agent(),
        _turn,
        providerOverride: provider,
        cancelToken: token,
      );
      expect(result.failure!.kind, FailureKind.cancelled);
      expect(provider.calls, 0, reason: 'no attempt should be made');
    });
  });

  group('HTTP failure mapping and retryability', () {
    Future<AgentTurnResult> run(int status, {int maxRetries = 2}) =>
        _runner().runTurn(
          _httpAgent(maxRetries: maxRetries, timeoutMs: 5000),
          _turn,
          httpClient: _StatusClient(status),
        );

    test('HTTP 400 is non-retryable and does not retry three times',
        () async {
      final result = await run(400, maxRetries: 2);
      expect(result.failure!.kind, FailureKind.malformedArgs);
      expect(isRetryableFailureKind(result.failure!.kind), isFalse);
      expect(result.failure!.attempts, 1,
          reason: 'invalid request must fail fast (no 3x retry)');
    });

    test('HTTP 401 is a non-retryable auth error', () async {
      final result = await run(401);
      expect(result.failure!.kind, FailureKind.authError);
      expect(isRetryableFailureKind(result.failure!.kind), isFalse);
      expect(result.failure!.attempts, 1);
    });

    test('HTTP 429 stays retryable (3 attempts at maxRetries=2)', () async {
      final result = await run(429, maxRetries: 2);
      expect(result.failure!.kind, FailureKind.rateLimit);
      expect(isRetryableFailureKind(result.failure!.kind), isTrue);
      expect(result.failure!.attempts, 3);
    });

    test('HTTP 500 stays retryable', () async {
      final result = await run(500, maxRetries: 2);
      expect(result.failure!.kind, FailureKind.providerError);
      expect(isRetryableFailureKind(result.failure!.kind), isTrue);
      expect(result.failure!.attempts, 3);
    });
  });

  group('tool-call ambiguity', () {
    test('multiple tool calls fail as malformedArgs (no arbitrary pick)',
        () async {
      final provider = _FakeProvider((request, call) async* {
        yield const LlmStreamEvent(kind: StreamEventKind.started);
        yield _toolCall('e2', 'e4');
        yield _toolCall('d2', 'd4');
        yield const LlmStreamEvent(kind: StreamEventKind.done);
      });
      final result = await _runner().runTurn(
        _agent(maxRetries: 0),
        _turn,
        providerOverride: provider,
      );
      expect(result.isSuccess, isFalse);
      expect(result.selectedMove, isNull);
      expect(result.failure!.kind, FailureKind.malformedArgs);
      expect(isRetryableFailureKind(result.failure!.kind), isFalse);
    });
  });

  group('usage accounting', () {
    test('usage tokens are summed across retry attempts', () async {
      final provider = _FakeProvider((request, call) async* {
        yield const LlmStreamEvent(kind: StreamEventKind.started);
        if (call == 0) {
          yield const LlmStreamEvent(
            kind: StreamEventKind.usage,
            tokensIn: 100,
            tokensOut: 10,
          );
          yield const LlmStreamEvent(
            kind: StreamEventKind.errorRetry,
            message: 'rateLimit: retry me',
          );
          return;
        }
        yield const LlmStreamEvent(
          kind: StreamEventKind.usage,
          tokensIn: 5,
          tokensOut: 2,
        );
        yield _toolCall('e2', 'e4');
        yield const LlmStreamEvent(kind: StreamEventKind.done);
      });

      final result = await _runner().runTurn(
        _agent(maxRetries: 2),
        _turn,
        providerOverride: provider,
      );

      expect(result.isSuccess, isTrue);
      expect(provider.calls, 2, reason: 'one failed attempt then a success');
      expect(result.usage, isNotNull);
      expect(result.usage!.inputTokens, 105);
      expect(result.usage!.outputTokens, 12);
      expect(result.usage!.totalTokens, 117);
    });
  });
}
