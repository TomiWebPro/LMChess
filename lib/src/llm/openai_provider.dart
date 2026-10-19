/// OpenAI chat/completions provider, also serving as the base class for all
/// OpenAI-compatible backends (OpenRouter, vLLM, Ollama, …) via a configurable
/// [baseUrl].
///
/// Pure Dart: HTTP goes through an injectable `http.Client` (pass a fake in
/// tests/demos; otherwise a private client is created and owned).
///
/// Wire details:
/// * `POST {baseUrl}/chat/completions` with `tools: [make_chess_move]`,
///   `tool_choice: "auto"`, `stream: true` and
///   `stream_options: {"include_usage": true}`.
/// * `tool_choice` is `"auto"` (not forced) on purpose: some compatible
///   servers reject forced function calls; a missing tool call is simply a
///   `missingToolCall` outcome the retry layer handles.
/// * SSE (`text/event-stream`) is parsed incrementally: `delta.content`
///   chunks become [StreamEventKind.textDelta], `delta.tool_calls[*]`
///   argument fragments accumulate per index and are flushed as one
///   [StreamEventKind.toolCallCompleted] per call when the stream ends.
///   A non-SSE full-JSON body (some proxies buffer) is tolerated via the
///   `message`-shape fallback.
/// * HTTP 401/403/429/5xx and transport timeouts are **emitted** as
///   [StreamEventKind.error]/[StreamEventKind.errorRetry] events with a
///   `<failureKind>: <detail>` message (never thrown), with the failure-kind
///   mapping from `failureKindForHttpStatus`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'http_helpers.dart';
import 'provider.dart';
import 'tool_schema.dart';
import 'validation.dart';

/// OpenAI + OpenAI-compatible streaming provider.
class OpenAiProvider extends LlmProvider {
  /// API root without trailing slash, e.g. `https://api.openai.com/v1`.
  final String baseUrl;

  /// Bearer token. Empty string is allowed (some local servers skip auth).
  final String apiKey;

  /// Model id, e.g. `gpt-4o-mini`.
  final String model;

  /// Wall-clock budget for connecting *and* receiving the stream.
  final Duration timeout;

  /// HTTP client (injected for tests) or an owned private client.
  final http.Client _client;

  /// Whether [_client] was created internally (and thus closed by [close]).
  final bool _ownsClient;

  /// Creates a provider.
  ///
  /// Pass [httpClient] to share a client or inject fakes; otherwise one is
  /// created and must be released with [close].
  OpenAiProvider({
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
  ProviderId get id => ProviderId.openai;

  @override
  LlmCapabilities get capabilities => const LlmCapabilities(
        supportsTools: true,
        supportsStreaming: true,
        supportsReasoning: false,
        friendlyName: 'OpenAI',
      );

  /// Base URL without trailing slashes.
  String get _base => baseUrl.replaceAll(RegExp(r'/+$'), '');

  Map<String, String> get _headers => jsonHeaders(bearerToken: apiKey);

  @override
  Future<bool> testConnection() async {
    try {
      final response = await _client
          .get(Uri.parse('$_base/models'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (_) {
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
      'messages': [
        {'role': 'system', 'content': request.systemPrompt},
        {'role': 'user', 'content': request.userPrompt},
      ],
      'tools': request.toolsJson ?? [makeChessMoveToolJson],
      'tool_choice': 'auto',
      'temperature': request.temperature,
      'max_tokens': request.maxTokens,
      if (request.seed != null) 'seed': request.seed,
      'stream': true,
      'stream_options': {'include_usage': true},
    };

    late final http.StreamedResponse response;
    try {
      final httpRequest = http.Request(
        'POST',
        Uri.parse('$_base/chat/completions'),
      )
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
    var sawDone = false;
    StringBuffer? pendingData;

    // Parses one complete SSE payload and yields the delta events it
    // contains. Returns true when the terminal `[DONE]` marker was seen.
    Iterable<LlmStreamEvent> dispatchPayload(String payload) {
      final events = <LlmStreamEvent>[];
      final trimmed = payload.trim();
      if (trimmed.isEmpty) return events;
      if (trimmed == '[DONE]') {
        sawDone = true;
        return events;
      }
      dynamic decoded;
      try {
        decoded = jsonDecode(trimmed);
      } catch (_) {
        return events; // Skip malformed payloads; the stream continues.
      }
      final usage = decoded is Map ? decoded['usage'] : null;
      if (usage is Map) {
        final input = _asInt(usage['prompt_tokens']);
        final output = _asInt(usage['completion_tokens']);
        if (input != null) tokensIn = input;
        if (output != null) tokensOut = output;
      }
      final choices = decoded is Map ? decoded['choices'] : null;
      if (choices is! List) return events;
      for (final choice in choices) {
        if (choice is! Map) continue;
        // Streaming shape uses `delta`; buffered non-SSE proxies may send
        // the full `message` shape instead — both are handled.
        final node =
            choice['delta'] is Map ? choice['delta'] : choice['message'];
        if (node is! Map) continue;
        final content = node['content'];
        if (content is String && content.isNotEmpty) {
          events.add(
            LlmStreamEvent(kind: StreamEventKind.textDelta, text: content),
          );
        }
        final toolCalls = node['tool_calls'];
        if (toolCalls is List) {
          for (final call in toolCalls) {
            if (call is! Map) continue;
            final index = _asInt(call['index']) ?? 0;
            final function = call['function'];
            if (function is! Map) continue;
            final name = function['name'];
            if (name is String && name.isNotEmpty) toolNames[index] = name;
            final args = function['arguments'];
            if (args is String && args.isNotEmpty) {
              toolArgs.putIfAbsent(index, () => StringBuffer()).write(args);
              events.add(
                LlmStreamEvent(
                  kind: StreamEventKind.toolCallDelta,
                  toolName: toolNames[index],
                  toolArgsJson: args,
                ),
              );
            } else if (args is Map && args.isNotEmpty) {
              final encoded = jsonEncode(args);
              toolArgs.putIfAbsent(index, () => StringBuffer())
                ..clear()
                ..write(encoded);
            }
          }
        }
      }
      return events;
    }

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
            yield event;
          }
          if (sawDone) break;
        }
        // Other SSE fields (`event:`, `id:`, `retry:`) carry nothing for the
        // OpenAI chat stream and are ignored.
      }
      // Flush a trailing payload when the stream ends without a blank line.
      if (pendingData != null) {
        final payload = pendingData.toString();
        pendingData = null;
        for (final event in dispatchPayload(payload)) {
          yield event;
        }
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

    if (toolArgs.length > 1) {
      // Ambiguous: the model emitted several tool calls in one turn and
      // last-wins would play an arbitrary pick. Surface it as a
      // non-retryable malformed outcome instead (no toolCallCompleted is
      // emitted, so the runner cannot validate a partial pick).
      yield LlmStreamEvent(
        kind: StreamEventKind.error,
        message:
            '${FailureKind.malformedArgs.name}: model emitted '
            '${toolArgs.length} tool calls in one turn; want exactly one '
            '"$chessMoveToolName" call.',
      );
      return;
    }
    for (final entry in toolArgs.entries) {
      yield LlmStreamEvent(
        kind: StreamEventKind.toolCallCompleted,
        toolName: toolNames[entry.key] ?? chessMoveToolName,
        toolArgsJson: entry.value.toString(),
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

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
