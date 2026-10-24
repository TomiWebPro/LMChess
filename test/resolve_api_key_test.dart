// Regression tests for [resolveApiKey] — the agent-layer API-key resolution
// helper. Pins the "storage failure is never silent" contract: a failed
// secure-store read is logged by default (or handed to `onReadError` when
// provided) while still returning `''` and never throwing, so keyless
// backends keep working and operators can distinguish "no key stored" from
// "store failed". Deterministic in-memory fakes only — no platform secure
// backend, no network, no wall clock.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/agent/agent_config.dart';
import 'package:llm_chess_arena/src/llm/provider.dart' show ProviderId;

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

/// Records failures handed to the [resolveApiKey] `onReadError` sink.
class _ErrorRecorder {
  int calls = 0;
  String? ref;
  Object? error;
  StackTrace? stackTrace;

  void call(String ref, Object error, StackTrace stackTrace) {
    calls++;
    this.ref = ref;
    this.error = error;
    this.stackTrace = stackTrace;
  }
}

AgentConfig _config({String? apiKeyRef}) => AgentConfig(
      id: 'agent-1',
      name: 'Agent One',
      providerId: ProviderId.openai,
      model: 'gpt-4o-mini',
      apiKeyRef: apiKeyRef,
    );

void main() {
  group('resolveApiKey (key resolution contract)', () {
    test('returns the stored secret for a valid ref', () async {
      final key = await resolveApiKey(
        _config(apiKeyRef: 'ref-a'),
        _FakeKeyReader(const {'ref-a': 'sk-secret-123'}),
      );

      expect(key, 'sk-secret-123');
    });

    test('no ref on the config yields an empty key without touching the store',
        () async {
      final recorder = _ErrorRecorder();
      final key = await resolveApiKey(
        _config(apiKeyRef: null),
        _ThrowingKeyReader(),
        onReadError: recorder.call,
      );

      expect(key, isEmpty);
      expect(recorder.calls, 0);
    });

    test('an empty ref yields an empty key without invoking onReadError',
        () async {
      final recorder = _ErrorRecorder();
      final key = await resolveApiKey(
        _config(apiKeyRef: ''),
        _ThrowingKeyReader(),
        onReadError: recorder.call,
      );

      expect(key, isEmpty);
      expect(recorder.calls, 0);
    });

    test('a store that holds no secret returns an empty key without invoking '
        'onReadError', () async {
      final recorder = _ErrorRecorder();
      final key = await resolveApiKey(
        _config(apiKeyRef: 'absent'),
        _FakeKeyReader(const <String, String>{}),
        onReadError: recorder.call,
      );

      expect(key, isEmpty);
      expect(recorder.calls, 0);
    });

    test('a store failure degrades to an empty key instead of throwing',
        () async {
      final key = await resolveApiKey(
        _config(apiKeyRef: 'ref-c'),
        _ThrowingKeyReader(),
      );

      expect(key, isEmpty);
    });

    test('a store failure is reported to onReadError with ref + error + '
        'stackTrace and still returns an empty key', () async {
      final recorder = _ErrorRecorder();
      final key = await resolveApiKey(
        _config(apiKeyRef: 'ref-c'),
        _ThrowingKeyReader(),
        onReadError: recorder.call,
      );

      expect(key, isEmpty);
      expect(recorder.calls, 1);
      expect(recorder.ref, 'ref-c');
      expect(recorder.error, isA<StateError>());
      expect((recorder.error as StateError).message, 'no vault');
      expect(recorder.stackTrace, isA<StackTrace>());
    });
  });
}
