// Deterministic offline tests pinning the §11.35 silent-swallow diagnostics
// sites in `lib/src/ui/backend_bridge.dart` and the LLM provider
// `testConnection` catches.
//
// Covers:
//   * `rawToolCallFrom` (backend_bridge.dart) — the malformed-JSON catch
//     now logs the parse failure while keeping the documented contract:
//     never throws, raw string preserved, decoded map null.
//   * `OpenAiProvider` / `AnthropicProvider` / `GeminiProvider`
//     `testConnection` — the `catch (error)` swallow now logs the probe
//     failure while still reporting `false` (never throws).
//
// All HTTP goes through injected fake `http.BaseClient`s that throw before
// any wire I/O; these tests must never open a socket or touch a real LLM
// endpoint.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:llm_chess_arena/src/agent/agent_runner.dart';
import 'package:llm_chess_arena/src/llm/anthropic_provider.dart';
import 'package:llm_chess_arena/src/llm/gemini_provider.dart';
import 'package:llm_chess_arena/src/llm/openai_provider.dart';
import 'package:llm_chess_arena/src/llm/provider.dart';
import 'package:llm_chess_arena/src/llm/validation.dart';
import 'package:llm_chess_arena/src/ui/backend_bridge.dart';

/// Fake HTTP client whose `send` always throws before any I/O.
class _ThrowingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw Exception('probe refused (fake client)');
  }
}

/// Fake HTTP client returning a fixed status code.
class _StatusClient extends http.BaseClient {
  _StatusClient(this.statusCode);

  final int statusCode;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream<List<int>>.value('ok'.codeUnits),
      statusCode,
    );
  }
}

AgentTurnResult _turnResultWith(String? toolArgsJson) => AgentTurnResult(
      outcome: ValidationOutcome(kind: FailureKind.timeout, error: 'unused'),
      events: <LlmStreamEvent>[
        LlmStreamEvent(
          kind: StreamEventKind.toolCallCompleted,
          toolArgsJson: toolArgsJson,
        ),
      ],
      latencyMs: 0,
    );

void main() {
  group('rawToolCallFrom (backend_bridge)', () {
    test('null result yields null raw args and null decoded map', () {
      final parsed = rawToolCallFrom(null);
      expect(parsed.rawToolArgsJson, isNull);
      expect(parsed.rawToolCallJson, isNull);
    });

    test('well-formed tool-call JSON decodes to a map and keeps the raw',
        () {
      final parsed =
          rawToolCallFrom(_turnResultWith('{"from":"e2","to":"e4"}'));
      expect(parsed.rawToolArgsJson, '{"from":"e2","to":"e4"}');
      expect(parsed.rawToolCallJson, <String, Object?>{'from': 'e2', 'to': 'e4'});
    });

    test('malformed tool-call JSON keeps the raw string with a null map — '
        'the parse failure is logged, never thrown', () {
      final parsed =
          rawToolCallFrom(_turnResultWith('{"from":"e2","to":"e4","promotion":'));
      expect(parsed.rawToolArgsJson, '{"from":"e2","to":"e4","promotion":');
      expect(parsed.rawToolCallJson, isNull);
    });

    test('JSON that decodes to a non-map keeps the raw string with a null '
        'map', () {
      final parsed = rawToolCallFrom(_turnResultWith('"just-a-string"'));
      expect(parsed.rawToolArgsJson, '"just-a-string"');
      expect(parsed.rawToolCallJson, isNull);
    });
  });

  group('provider testConnection catches', () {
    test('OpenAiProvider reports false on a transport failure (logged, '
        'never thrown)', () async {
      final provider = OpenAiProvider(
        baseUrl: 'https://example.test/v1',
        apiKey: 'sk-test',
        model: 'gpt-4o-mini',
        httpClient: _ThrowingClient(),
      );
      expect(await provider.testConnection(), isFalse);
    });

    test('AnthropicProvider reports false on a transport failure (logged, '
        'never thrown)', () async {
      final provider = AnthropicProvider(
        baseUrl: 'https://example.test',
        apiKey: 'sk-ant-test',
        model: 'claude-sonnet-test',
        httpClient: _ThrowingClient(),
      );
      expect(await provider.testConnection(), isFalse);
    });

    test('GeminiProvider reports false on a transport failure (logged, '
        'never thrown)', () async {
      final provider = GeminiProvider(
        baseUrl: 'https://generativelanguage.googleapis.com',
        apiKey: 'gem-test',
        model: 'gemini-2.0-flash',
        httpClient: _ThrowingClient(),
      );
      expect(await provider.testConnection(), isFalse);
    });

    test('OpenAiProvider reports true on a 200 probe (happy path sanity)',
        () async {
      final provider = OpenAiProvider(
        baseUrl: 'https://example.test/v1',
        apiKey: 'sk-test',
        model: 'gpt-4o-mini',
        httpClient: _StatusClient(200),
      );
      expect(await provider.testConnection(), isTrue);
    });
  });
}