/// Google Generative Language API provider (`generateContent` family) with
/// function calling and SSE streaming.
///
/// Pure Dart with an injectable `http.Client`.
///
/// Wire details:
/// * `POST {baseUrl}/v1beta/models/{model}:streamGenerateContent?alt=sse`
///   with `system_instruction`, `contents`, `tools: [{function_declarations:
///   [make_chess_move]}]`, `tool_config.function_calling_config.mode: AUTO`
///   and `generationConfig {temperature, maxOutputTokens}`. Auth via the
///   `x-goog-api-key` header.
/// * Each SSE `data:` payload is a `GenerateContentResponse` object (a bare
///   list of them is also tolerated): text lives in
///   `candidates[0].content.parts[]` (`{text: …}`), moves in
///   `{functionCall: {name, args}}` parts (args arrive as a decoded object
///   and are re-encoded to the canonical `toolArgsJson` string),
///   token counts in `usageMetadata`.
/// * Safety blocks (`promptFeedback.blockReason`) and HTTP failures are
///   **emitted** as error events with a `<failureKind>: <detail>` message,
///   never thrown.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'http_helpers.dart';
import 'provider.dart';
import 'tool_schema.dart';
import 'validation.dart';

/// Google Generative Language API streaming provider.
class GeminiProvider extends LlmProvider {
  /// API root, e.g. `https://generativelanguage.googleapis.com`.
  final String baseUrl;

  /// API key sent as `x-goog-api-key`.
  final String apiKey;

  /// Model id, e.g. `gemini-2.0-flash`.
  final String model;

  /// Wall-clock budget for connecting *and* receiving the stream.
  final Duration timeout;

  /// HTTP client (injected for tests) or an owned private client.
  final http.Client _client;

  /// Whether [_client] was created internally (and thus closed by [close]).
  final bool _ownsClient;

  /// Creates a provider.
  GeminiProvider({
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
  ProviderId get id => ProviderId.gemini;

  @override
  LlmCapabilities get capabilities => const LlmCapabilities(
        supportsTools: true,
        supportsStreaming: true,
        supportsReasoning: false,
        friendlyName: 'Gemini',
      );

  /// Base URL without trailing slashes.
  String get _base => baseUrl.replaceAll(RegExp(r'/+$'), '');

  Map<String, String> get _headers => jsonHeaders(
        extra: {'x-goog-api-key': apiKey},
      );

  @override
  Future<bool> testConnection() async {
    try {
      final response = await _client
          .get(Uri.parse('$_base/v1beta/models'), headers: _headers)
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
      'system_instruction': {
        'parts': [
          {'text': request.systemPrompt},
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': request.userPrompt},
          ],
        },
      ],
      'tools': [
        {
          'function_declarations':
              request.toolsJson ?? [geminiChessMoveDeclarationEnvelope()],
        },
      ],
      'tool_config': {
        'function_calling_config': {'mode': 'AUTO'},
      },
      'generationConfig': {
        'temperature': request.temperature,
        'maxOutputTokens': request.maxTokens,
      },
    };

    late final http.StreamedResponse response;
    try {
      final uri = Uri.parse('$_base/v1beta/models/$model'
          ':streamGenerateContent?alt=sse');
      final httpRequest = http.Request('POST', uri)
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

    String? functionName;
    Map<String, Object?>? functionArgs;
    int? tokensIn;
    int? tokensOut;
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
      // `alt=sse` yields one response object per payload, but tolerate a
      // bare list defensively.
      final responses = decoded is List ? decoded : [decoded];
      for (final item in responses) {
        if (item is! Map) continue;
        final feedback = item['promptFeedback'];
        if (feedback is Map) {
          final blockReason = feedback['blockReason'];
          if (blockReason is String && blockReason.isNotEmpty) {
            yield LlmStreamEvent(
              kind: StreamEventKind.error,
              message:
                  '${FailureKind.providerError.name}: response blocked '
                  '($blockReason).',
            );
            return;
          }
        }
        final usage = item['usageMetadata'];
        if (usage is Map) {
          final input = _asInt(usage['promptTokenCount']);
          final output = _asInt(usage['candidatesTokenCount']);
          if (input != null) tokensIn = input;
          if (output != null) tokensOut = output;
        }
        final candidates = item['candidates'];
        if (candidates is! List) continue;
        for (final candidate in candidates) {
          if (candidate is! Map) continue;
          final content = candidate['content'];
          final parts = content is Map ? content['parts'] : null;
          if (parts is! List) continue;
          for (final part in parts) {
            if (part is! Map) continue;
            final text = part['text'];
            if (text is String && text.isNotEmpty) {
              yield LlmStreamEvent(
                kind: StreamEventKind.textDelta,
                text: text,
              );
            }
            final functionCall = part['functionCall'];
            if (functionCall is Map) {
              final name = functionCall['name'];
              if (name is String && name.isNotEmpty) functionName = name;
              final args = functionCall['args'];
              if (args is Map) {
                // Chunked `functionCall.args` may arrive split across SSE
                // frames with disjoint key sets — merge into the running
                // map so no keys are lost (last key wins within a frame).
                functionArgs ??= <String, Object?>{};
                for (final argEntry in args.entries) {
                  functionArgs!['${argEntry.key}'] =
                      argEntry.value as Object?;
                }
                yield LlmStreamEvent(
                  kind: StreamEventKind.toolCallDelta,
                  toolName: functionName,
                  toolArgsJson: jsonEncode(functionArgs),
                );
              }
            }
          }
        }
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

    if (functionArgs != null) {
      yield LlmStreamEvent(
        kind: StreamEventKind.toolCallCompleted,
        toolName: functionName ?? chessMoveToolName,
        toolArgsJson: jsonEncode(functionArgs),
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
