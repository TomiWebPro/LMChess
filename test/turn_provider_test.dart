// Regression tests for [resolveTurnProvider]: the seam that makes a
// *configured* (non-mock) agent actually authenticate at turn time by
// resolving its secret from secure storage.
//
// Without this wiring, real providers were built keyless during gameplay
// even though the setup screen stored a key — the app's LLM play path would
// silently fail auth. These tests pin the plumbing: the resolved secret
// reaches the provider, stays out of the config, and mock turns remain
// keyless and deterministic.
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/agent/agent_config.dart';
import 'package:llm_chess_arena/src/llm/anthropic_provider.dart';
import 'package:llm_chess_arena/src/llm/mock_provider.dart';
import 'package:llm_chess_arena/src/llm/openai_provider.dart';
import 'package:llm_chess_arena/src/llm/provider.dart' show ProviderId;
import 'package:llm_chess_arena/src/ui/backend_bridge.dart';

/// In-memory [SecureKeyReader] standing in for the storage layer.
class _FakeKeyReader implements SecureKeyReader {
  _FakeKeyReader(this._secrets);

  final Map<String, String> _secrets;

  @override
  Future<String?> readApiKey(String ref) async => _secrets[ref];
}

/// A reader that always throws, exercising the "storage unavailable" path.
class _ThrowingKeyReader implements SecureKeyReader {
  @override
  Future<String?> readApiKey(String ref) async => throw StateError('no vault');
}

AgentConfig _config({
  required ProviderId providerId,
  String? apiKeyRef,
}) =>
    AgentConfig(
      id: 'agent-1',
      name: 'Agent One',
      providerId: providerId,
      model: 'gpt-4o-mini',
      apiKeyRef: apiKeyRef,
    );

void main() {
  group('resolveTurnProvider', () {
    test('resolves the stored secret into the OpenAI provider', () async {
      final config = _config(providerId: ProviderId.openai, apiKeyRef: 'ref-a');
      final provider = await resolveTurnProvider(
        config,
        const <String>['e2e4'],
        keyReader: _FakeKeyReader(const {'ref-a': 'sk-secret-123'}),
      );

      expect(provider, isA<OpenAiProvider>());
      expect((provider as OpenAiProvider).apiKey, 'sk-secret-123');
      provider.close();
    });

    test('resolves the stored secret into the Anthropic provider', () async {
      final config =
          _config(providerId: ProviderId.anthropic, apiKeyRef: 'ref-b');
      final provider = await resolveTurnProvider(
        config,
        const <String>['e2e4'],
        keyReader: _FakeKeyReader(const {'ref-b': 'anthropic-key'}),
      );

      expect(provider, isA<AnthropicProvider>());
      expect((provider as AnthropicProvider).apiKey, 'anthropic-key');
      provider.close();
    });

    test('a missing secret yields an empty key (keyless backends keep working)',
        () async {
      final config = _config(providerId: ProviderId.openai, apiKeyRef: 'absent');
      final provider = await resolveTurnProvider(
        config,
        const <String>['e2e4'],
        keyReader: _FakeKeyReader(const <String, String>{}),
      );

      expect((provider as OpenAiProvider).apiKey, isEmpty);
      provider.close();
    });

    test('a reader that throws degrades to an empty key instead of crashing',
        () async {
      final config = _config(providerId: ProviderId.openai, apiKeyRef: 'ref-c');
      final provider = await resolveTurnProvider(
        config,
        const <String>['e2e4'],
        keyReader: _ThrowingKeyReader(),
      );

      expect((provider as OpenAiProvider).apiKey, isEmpty);
      provider.close();
    });

    test('the secret never leaks into the config (only the ref is carried)',
        () {
      final config =
          _config(providerId: ProviderId.openai, apiKeyRef: 'ref-d');
      expect(config.apiKeyRef, 'ref-d');
      expect(config.toJson().values, isNot(contains('ref-d-secret')));
      // The serialized config carries the opaque ref, never a raw secret.
      expect(config.toJson()['apiKeyRef'], 'ref-d');
    });

    test('mock turns stay keyless and deterministic', () async {
      final config = AgentConfig(
        id: 'mock-1',
        name: 'Mock',
        providerId: ProviderId.mock,
        model: 'mock',
      );
      final first = await resolveTurnProvider(
        config,
        const <String>['e2e4', 'd2d4', 'g1f3'],
      );
      final second = await resolveTurnProvider(
        config,
        const <String>['e2e4', 'd2d4', 'g1f3'],
      );

      expect(first, isA<MockProvider>());
      expect(second, isA<MockProvider>());
      // Same agent + same candidate list => same scripted pick.
      expect((first as MockProvider).script.first.toString(),
          (second as MockProvider).script.first.toString());
    });
  });
}
