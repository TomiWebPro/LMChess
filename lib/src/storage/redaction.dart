/// Storage-layer secret redaction.
///
/// [redactForStorage] is a superset of the export redactor
/// ([redactSecrets] in `arena/export.dart`):
///
/// * It first delegates to [redactSecrets], so the two layers share one
///   fragment list and one placeholder.
/// * It then applies two storage-specific corrections:
///   1. **`*Ref` exemption** — opaque reference fields such as `apiKeyRef`
///      must survive persistence verbatim (the ref is not the secret; the
///      secret lives in `SecureKeyStore`). The export redactor would clobber
///      them because `apiKeyRef` contains `apikey`.
///   2. **Broadened key matching** — keys the export list misses, notably
///      `openAIKey` (normalized `openaikey`), are redacted too.
library;

import '../arena/export.dart' show redactedPlaceholder, redactSecrets;

/// Returns a deep, JSON-safe copy of [value] with secret-looking values
/// replaced by [redactedPlaceholder], except for `*Ref` fields which are
/// preserved (deep-copied) as-is.
Object? redactForStorage(Object? value) =>
    _restoreRefsAndBroaden(value, redactSecrets(value));

/// Walks the original [original] tree, using the export layer's decision
/// ([redacted]) for scalars while re-applying the ref exemption and the
/// broadened key matching.
Object? _restoreRefsAndBroaden(Object? original, Object? redacted) {
  if (original is Map) {
    final redactedMap = redacted is Map ? redacted : const <Object?, Object?>{};
    final out = <String, Object?>{};
    for (final entry in original.entries) {
      final key = entry.key.toString();
      if (_isSecretRef(key)) {
        out[key] = _deepCopy(entry.value);
      } else if (_looksLikeSecretBroad(key)) {
        out[key] = redactedPlaceholder;
      } else {
        out[key] = _restoreRefsAndBroaden(entry.value, redactedMap[entry.key]);
      }
    }
    return out;
  }
  if (original is List) {
    final redactedList = redacted is List ? redacted : const <Object?>[];
    return <Object?>[
      for (var i = 0; i < original.length; i++)
        _restoreRefsAndBroaden(
          original[i],
          i < redactedList.length ? redactedList[i] : null,
        ),
    ];
  }
  // Scalars: defer entirely to the export redactor (returns them as-is).
  return redacted;
}

/// Deep, JSON-safe copy that preserves values without inspecting keys.
Object? _deepCopy(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key.toString(): _deepCopy(entry.value),
    };
  }
  if (value is List) {
    return <Object?>[for (final element in value) _deepCopy(element)];
  }
  return value;
}

/// Normalizes a key the same way the export redactor does.
String _normalize(String key) =>
    key.toLowerCase().replaceAll(RegExp(r'[-_\s]'), '');

/// Whether [key] is an opaque secret *reference* that must survive storage.
bool _isSecretRef(String key) => _normalize(key).endsWith('ref');

/// Storage-only fragments the export list misses, plus a provider-aware
/// `...key` rule (e.g. `openAIKey`, `anthropicKey`, `geminiKey`).
bool _looksLikeSecretBroad(String key) {
  final normalized = _normalize(key);
  if (normalized.endsWith('ref')) return false;
  const extraFragments = <String>['aikey', 'accesskey', 'secretkey'];
  for (final fragment in extraFragments) {
    if (normalized.contains(fragment)) return true;
  }
  if (normalized.endsWith('key')) {
    const providers = <String>[
      'api',
      'ai',
      'openai',
      'anthropic',
      'gemini',
      'ollama',
      'token',
      'secret',
    ];
    for (final provider in providers) {
      if (normalized.contains(provider)) return true;
    }
  }
  return false;
}
