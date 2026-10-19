// Regression tests for secret redaction across the export and storage layers.
//
//   * `redactSecrets` (arena/export.dart) replaces secret-looking map values,
//   * `redactForStorage` (storage/redaction.dart) broadens that key set
//     (e.g. `openAIKey`) while exempting opaque `*Ref` fields.
//
// No I/O; pure data-structure assertions.
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/arena/export.dart';
import 'package:llm_chess_arena/src/storage/redaction.dart';

void main() {
  group('redactSecrets (export layer)', () {
    test('redacts common secret keys', () {
      final redacted = redactSecrets(<String, Object?>{
        'api_key': 'sk-live-123',
        'x-api-key': 'abc',
        'token': 'tok',
        'authorization': 'Bearer xyz',
        'password': 'hunter2',
        'name': 'gpt',
      })! as Map<String, Object?>;
      for (final key in <String>[
        'api_key',
        'x-api-key',
        'token',
        'authorization',
        'password',
      ]) {
        expect(redacted[key], redactedPlaceholder, reason: '$key redacted');
      }
      expect(redacted['name'], 'gpt', reason: 'non-secret values survive');
    });

    test('recurses into nested maps and lists', () {
      final redacted = redactSecrets(<String, Object?>{
        'outer': <String, Object?>{
          'apiKey': 'sk',
          'config': <Object?>[
            <String, Object?>{'secret': 's'},
            'plain',
          ],
        },
      })! as Map<String, Object?>;
      final outer = redacted['outer']! as Map<String, Object?>;
      expect(outer['apiKey'], redactedPlaceholder);
      final config = outer['config']! as List<Object?>;
      expect((config[0]! as Map<String, Object?>)['secret'],
          redactedPlaceholder);
      expect(config[1], 'plain');
    });

    test('does not (by design) catch provider-specific keys or *Ref', () {
      // Documented gap the storage layer closes: `openAIKey` normalizes to
      // `openaikey`, which the export fragment list misses.
      final redacted = redactSecrets(<String, Object?>{
        'openAIKey': 'sk-open',
        // `apiKeyRef` contains `apikey`, so the export layer clobbers it —
        // exactly why storage re-applies a `*Ref` exemption.
        'apiKeyRef': 'vault:openai',
      })! as Map<String, Object?>;
      expect(redacted['openAIKey'], 'sk-open');
      expect(redacted['apiKeyRef'], redactedPlaceholder);
    });
  });

  group('redactForStorage (storage layer)', () {
    test('redacts the broadened key set', () {
      final redacted = redactForStorage(<String, Object?>{
        'openAIKey': 'sk-open',
        'anthropicKey': 'sk-ant',
        'api_key': 'sk-live',
        'x-api-key': 'abc',
        'token': 'tok',
        'authorization': 'Bearer xyz',
        'name': 'gpt',
      })! as Map<String, Object?>;
      for (final key in <String>[
        'openAIKey',
        'anthropicKey',
        'api_key',
        'x-api-key',
        'token',
        'authorization',
      ]) {
        expect(redacted[key], redactedPlaceholder,
            reason: '$key redacted for storage');
      }
      expect(redacted['name'], 'gpt');
    });

    test('*Ref fields survive verbatim (deep-copied)', () {
      final redacted = redactForStorage(<String, Object?>{
        'apiKeyRef': 'vault:openai',
        'openAIKey': 'sk-open',
        'nested': <String, Object?>{
          'tokenRef': 'vault:tok',
          'token': 'tok',
        },
      })! as Map<String, Object?>;
      expect(redacted['apiKeyRef'], 'vault:openai');
      final nested = redacted['nested']! as Map<String, Object?>;
      expect(nested['tokenRef'], 'vault:tok');
      expect(nested['token'], redactedPlaceholder);
    });

    test('redacts secrets nested inside an event payload', () {
      final stored = redactForStorage(<String, Object?>{
        'key': 'evt-1',
        'type': 'turnSummary',
        'payloadJson': <String, Object?>{
          'agentId': 'agent-1',
          'authorization': 'Bearer secret',
          'apiKey': 'sk',
          'extra': <Object?>[
            <String, Object?>{'refresh_token': 'r'},
          ],
        },
      })! as Map<String, Object?>;
      final payload = stored['payloadJson']! as Map<String, Object?>;
      expect(payload['agentId'], 'agent-1');
      expect(payload['authorization'], redactedPlaceholder);
      expect(payload['apiKey'], redactedPlaceholder);
      expect(
        ((payload['extra']! as List<Object?>)[0]! as Map<String, Object?>)[
            'refresh_token'],
        redactedPlaceholder,
      );
    });

    test('returns an independent deep copy and passes scalars through', () {
      final source = <String, Object?>{
        'config': <String, Object?>{'apiKeyRef': 'r', 'name': 'n'},
      };
      final redacted = redactForStorage(source)! as Map<String, Object?>;
      // Mutating the source must not touch the redacted copy.
      (source['config']! as Map<String, Object?>)['name'] = 'changed';
      expect((redacted['config']! as Map<String, Object?>)['name'], 'n');
      expect(redactForStorage(42), 42);
      expect(redactForStorage('plain'), 'plain');
      expect(redactForStorage(null), isNull);
    });
  });
}
