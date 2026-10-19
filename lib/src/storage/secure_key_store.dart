/// Secure-storage wrapper for LLM provider API keys.
///
/// Secrets never live in Hive: [LocalAppStore] only persists opaque
/// `apiKeyRef` strings (see `AgentConfig.apiKeyRef`), and the actual secret is
/// written here, backed by `flutter_secure_storage` (Keychain / Keystore /
/// libsecret depending on platform).
///
/// The public shape is intentionally tiny and stable because the agent/UI
/// layers depend on it:
///
/// ```dart
/// class SecureKeyStore {
///   const SecureKeyStore();
///   Future<void> writeApiKey(String ref, String secret);
///   Future<String?> readApiKey(String ref);
///   Future<void> deleteApiKey(String ref);
/// }
/// ```
///
/// [readApiKey] is structurally compatible with the `SecureKeyReader`
/// contract declared in `agent_config.dart`, so a caller can adapt it with a
/// one-line closure if it needs that static type:
/// `readApiKey: (ref) => keyStore.readApiKey(ref)`.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persistent, encrypted key/value store for API keys.
class SecureKeyStore {
  /// Creates a key store backed by the platform secure storage.
  const SecureKeyStore();

  /// Prefix applied to every secure-storage key so arena secrets cannot
  /// collide with unrelated entries in the same platform store.
  static const String keyPrefix = 'llm_chess_arena/apikey/';

  /// Shared secure-storage handle (const-constructible, so [SecureKeyStore]
  /// can offer a const constructor).
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  /// Storage key for an opaque [ref].
  static String _keyFor(String ref) => '$keyPrefix$ref';

  /// Stores [secret] under [ref], replacing any previous value.
  Future<void> writeApiKey(String ref, String secret) =>
      _storage.write(key: _keyFor(ref), value: secret);

  /// Returns the secret stored under [ref], or `null` when absent.
  Future<String?> readApiKey(String ref) => _storage.read(key: _keyFor(ref));

  /// Removes the secret stored under [ref]. No-op when absent.
  Future<void> deleteApiKey(String ref) => _storage.delete(key: _keyFor(ref));
}
