/// Anthropic Messages API provider with tool use and SSE streaming.
///
/// Pure Dart with an injectable `http.Client`.
///
/// Wire details:
/// * `POST {baseUrl}/v1/messages` with `tools: [make_chess_move]`,
///   `tool_choice: {"type": "auto"}`, `stream: true`, and the required
///   `anthropic-version: 2023-06-01` header.
/// * SSE payloads are self-describing (`type` field on each JSON body), so
///   the `event:` line prefix is ignored: `message_start` yields input usage,
///   `content_block_start` (tool_use) registers the tool name per index,
///   `content_block_delta` yields [StreamEventKind.textDelta] for
///   `text_delta` and accumulates/emits [StreamEventKind.toolCallDelta] for
///   `input_json_delta`, `message_delta` yields output usage, and
///   `message_stop` closes the turn. Backend `error` payloads are mapped by
///   their Anthropic error type (authentication/permission → auth,
///   rate-limit/overloaded → retryable).
/// * HTTP failures and timeouts are **emitted** as error events with a
///   `<failureKind>: <detail>` message, never thrown.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' show log;

import 'package:http/http.dart' as http;

import 'http_helpers.dart';
import 'provider.dart';
import 'tool_schema.dart';
import 'validation.dart';

/// Anthropic API version pinned for the Messages + tool-use surface.
const String anthropicApiVersion = '2023-06-01';

/// Anthropic Messages API streaming provider.
class AnthropicProvider extends LlmProvider {
  /// API root, e.g. `https://api.anthropic.com`.
  final String baseUrl;

  /// Value of the `x-api-key` header.
  final String apiKey;

  /// Model id, e.g. `claude-sonnet-4-20250514`.
  final String model;

  /// Wall-clock budget for connecting *and* receiving the stream.
  final Duration timeout;

  /// HTTP client (injected for tests) or an owned private client.
  final http.Client _client;

  /// Whether [_client] was created internally (and thus closed by [close]).
  final bool _ownsClient;

  /// Creates a provider.
  AnthropicProvider({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 120),
  })  : _client = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  /// Releases the internally created HTTP client, if any.
  @override
  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }

  @override
  ProviderId get id => ProviderId.anthropic;

  @override
  LlmCapabilities get capabilities => const LlmCapabilities(
        supportsTools: true,
        supportsStreaming: true,
        supportsReasoning: false,
        friendlyName: 'Anthropic',
      );

  /// Base URL without trailing slashes.
  String get _base => baseUrl.replaceAll(RegExp(r'/+$'), '');

  Map<String, String> get _headers => jsonHeaders(
        extra: {
          'x-api-key': apiKey,
          'anthropic-version': anthropicApiVersion,
        },
      );

  @override
  Future<bool> testConnection() async {
    try {
      final response = await _client
          .get(Uri.parse('$_base/v1/models'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (error) {
      log(
        'testConnection: $id models probe failed — reporting false',
        name: 'anthropic-provider',
        error: error,
      );
      return false;
    }
  }

  @override
  Stream<LlmStreamEvent> streamMove(AgentRequest request) async* {
    final stopwatch = Stopwatch()..start();
    yield const LlmStreamEvent(kind: StreamEventKind.started);

    bool cancelled() => request.cancelToken?.isCancelled ?? false;
    if (cancelled()) {
      yield LlmStreamEvent(
        kind: StreamEventKind.error,
        message: '${FailureKind.cancelled.name}: turn cancelled before send.',
      );
      return;
    }

    final body = {
      'model': model,
      'max_tokens': request.maxTokens,
      'system': request.systemPrompt,
      'messages': [
        {'role': 'user', 'content': request.userPrompt},
      ],
      'tools': request.toolsJson ?? [anthropicChessMoveToolEnvelope()],
      'tool_choice': {'type': 'auto'},
      'temperature': request.temperature,
      'stream': true,
    };

    late final http.StreamedResponse response;
    try {
      final httpRequest = http.Request('POST', Uri.parse('$_base/v1/messages'))
        ..headers.addAll(_headers)
        ..body = jsonEncode(body);
      response = await _client.send(httpRequest).timeout(timeout);
    } on TimeoutException {
      yield LlmStreamEvent(
        kind: StreamEventKind.errorRetry,
        message: '${FailureKind.timeout.name}: connection timed out.',
      );
      return;
    } catch (e) {
      yield LlmStreamEvent(
        kind: StreamEventKind.errorRetry,
        message: '${FailureKind.providerError.name}: transport error: $e',
      );
      return;
    }

    if (response.statusCode != 200) {
      final detail = await readErrorBody(response);
      final kind = failureKindForHttpStatus(response.statusCode);
      yield LlmStreamEvent(
        kind: isRetryableFailureKind(kind)
            ? StreamEventKind.errorRetry
            : StreamEventKind.error,
        message: '${kind.name}: HTTP ${response.statusCode} $detail'.trim(),
      );
      return;
    }

    yield const LlmStreamEvent(
      kind: StreamEventKind.status,
      message: 'streaming',
    );

    final toolNames = <int, String>{};
    final toolArgs = <int, StringBuffer>{};
    int? tokensIn;
    int? tokensOut;
    var stopReason = 'end_turn';
    StringBuffer? pendingData;

    /// Handles one complete SSE JSON payload, yielding its delta events.
    Iterable<LlmStreamEvent> dispatchPayload(String payload) sync* {
      final trimmed = payload.trim();
      if (trimmed.isEmpty) return;
      dynamic decoded;
      try {
        decoded = jsonDecode(trimmed);
      } catch (_) {
        return; // Skip malformed payloads; the stream continues.
      }
      if (decoded is! Map) return;
      final type = decoded['type'];
      switch (type) {
        case 'message_start':
          final message = decoded['message'];
          final usage = message is Map ? message['usage'] : null;
          if (usage is Map) {
            final input = _asInt(usage['input_tokens']);
            if (input != null) tokensIn = input;
          }
        case 'content_block_start':
          final index = _asInt(decoded['index']) ?? 0;
          final block = decoded['content_block'];
          if (block is Map && block['type'] == 'tool_use') {
            final name = block['name'];
            if (name is String && name.isNotEmpty) toolNames[index] = name;
            toolArgs.putIfAbsent(index, () => StringBuffer());
          }
        case 'content_block_delta':
          final index = _asInt(decoded['index']) ?? 0;
          final delta = decoded['delta'];
          if (delta is! Map) return;
          final deltaType = delta['type'];
          if (deltaType == 'text_delta') {
            final text = delta['text'];
            if (text is String && text.isNotEmpty) {
              yield LlmStreamEvent(
                kind: StreamEventKind.textDelta,
                text: text,
              );
            }
          } else if (deltaType == 'input_json_delta') {
            final fragment = delta['partial_json'];
            if (fragment is String && fragment.isNotEmpty) {
              toolArgs.putIfAbsent(index, () => StringBuffer()).write(fragment);
              yield LlmStreamEvent(
                kind: StreamEventKind.toolCallDelta,
                toolName: toolNames[index],
                toolArgsJson: fragment,
              );
            }
          }
        case 'message_delta':
          final delta = decoded['delta'];
          if (delta is Map) {
            final reason = delta['stop_reason'];
            if (reason is String && reason.isNotEmpty) stopReason = reason;
          }
          final usage = decoded['usage'];
          if (usage is Map) {
            final output = _asInt(usage['output_tokens']);
            if (output != null) tokensOut = output;
          }
        case 'error':
          final error = decoded['error'];
          final errorType = error is Map ? error['type'] : null;
          final messageText =
              error is Map && error['message'] is String
                  ? error['message'] as String
                  : 'stream error';
          final kind = _failureKindForAnthropicError('$errorType');
          yield LlmStreamEvent(
            kind: isRetryableFailureKind(kind)
                ? StreamEventKind.errorRetry
                : StreamEventKind.error,
            message: '${kind.name}: $messageText',
          );
        // `message_stop`, `content_block_stop` and `ping` carry no data.
      }
    }

    var streamFailed = false;
    try {
      await for (final line in sseLinesWithInactivityTimeout(
        response.stream,
        timeout,
      )) {
        if (cancelled()) {
          yield LlmStreamEvent(
            kind: StreamEventKind.error,
            message: '${FailureKind.cancelled.name}: turn cancelled mid-stream.',
          );
          return;
        }
        final dataValue = sseDataValue(line);
        if (dataValue != null) {
          pendingData ??= StringBuffer();
          pendingData.writeln(dataValue);
        } else if (isSseComment(line)) {
          continue; // SSE comment / keep-alive.
        } else if (isSseBlankLine(line)) {
          final payload = pendingData?.toString() ?? '';
          pendingData = null;
          for (final event in dispatchPayload(payload)) {
            if (event.kind == StreamEventKind.error ||
                event.kind == StreamEventKind.errorRetry) {
              streamFailed = true;
            }
            yield event;
          }
          // Exactly-one-terminal contract (provider.dart): the payload
          // error above is already the terminal event, so return now —
          // falling through would emit a second terminal (`done`) below.
          if (streamFailed) return;
        }
        // `event:` prefixes are redundant with each JSON body's own `type`.
      }
      if (pendingData != null) {
        final payload = pendingData.toString();
        pendingData = null;
        for (final event in dispatchPayload(payload)) {
          if (event.kind == StreamEventKind.error ||
              event.kind == StreamEventKind.errorRetry) {
            streamFailed = true;
          }
          yield event;
        }
        // Trailing-flush error is likewise terminal: return immediately so
        // no second terminal follows.
        if (streamFailed) return;
      }
    } on TimeoutException {
      yield LlmStreamEvent(
        kind: StreamEventKind.errorRetry,
        message:
            '${FailureKind.timeout.name}: stream stalled with no data for '
            '${timeout.inMilliseconds}ms.',
      );
      return;
    } catch (e) {
      yield LlmStreamEvent(
        kind: StreamEventKind.errorRetry,
        message: '${FailureKind.providerError.name}: stream failed: $e',
      );
      return;
    }
    if (cancelled()) {
      yield LlmStreamEvent(
        kind: StreamEventKind.error,
        message: '${FailureKind.cancelled.name}: turn cancelled mid-stream.',
      );
      return;
    }

    if (stopReason == 'max_tokens') {
      yield LlmStreamEvent(
        kind: StreamEventKind.errorRetry,
        message:
            '${FailureKind.incompleteResponse.name}: stopped at max_tokens '
            'before a complete tool call.',
      );
      return;
    }

    final completedCalls = <int, String>{
      for (final entry in toolArgs.entries)
        if (entry.value.toString().isNotEmpty) entry.key: entry.value.toString(),
    };
    if (completedCalls.length > 1) {
      // Ambiguous: several tool blocks in one turn — playing an arbitrary
      // pick would be last-wins. Surface non-retryable malformed instead.
      yield LlmStreamEvent(
        kind: StreamEventKind.error,
        message:
            '${FailureKind.malformedArgs.name}: model emitted '
            '${completedCalls.length} tool calls in one turn; want exactly '
            'one "$chessMoveToolName" call.',
      );
      return;
    }
    for (final entry in completedCalls.entries) {
      yield LlmStreamEvent(
        kind: StreamEventKind.toolCallCompleted,
        toolName: toolNames[entry.key] ?? chessMoveToolName,
        toolArgsJson: entry.value,
      );
    }
    if (tokensIn != null || tokensOut != null) {
      yield LlmStreamEvent(
        kind: StreamEventKind.usage,
        tokensIn: tokensIn,
        tokensOut: tokensOut,
      );
    }
    stopwatch.stop();
    yield LlmStreamEvent(
      kind: StreamEventKind.latency,
      latencyMs: stopwatch.elapsedMilliseconds,
    );
    yield const LlmStreamEvent(kind: StreamEventKind.done);
  }

  /// Maps Anthropic stream error types onto the failure taxonomy.
  ///
  /// Auth/permission failures are non-retryable; invalid requests (HTTP
  /// 400-class: malformed tool schemas, bad params) are likewise
  /// non-retryable — resending the same request fails the same way.
  /// Rate limits and overloads stay retryable; unknown `api_error`s are
  /// treated as transient provider errors (retryable) since that bucket
  /// covers server-side faults.
  FailureKind _failureKindForAnthropicError(String errorType) {
    switch (errorType) {
      case 'authentication_error':
      case 'permission_error':
        return FailureKind.authError;
      case 'invalid_request_error':
        return FailureKind.malformedArgs;
      case 'rate_limit_error':
      case 'overloaded_error':
        return FailureKind.rateLimit;
      case 'api_error':
        return FailureKind.providerError;
      default:
        return FailureKind.providerError;
    }
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
