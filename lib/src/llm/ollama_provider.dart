/// Local Ollama provider: a thin [OpenAiProvider] subtype pre-pointed at the
/// default Ollama server and its OpenAI-compatible surface.
///
/// Pure Dart with an injectable `http.Client`. Only the defaults, [id] and
/// [capabilities] differ from [OpenAiProvider]; all streaming, SSE parsing
/// and error mapping are inherited (Ollama serves `/v1/models` and
/// `/v1/chat/completions` on its OpenAI-compat prefix).
library;

import 'openai_provider.dart';
import 'provider.dart';

/// Default base URL of a local Ollama server (OpenAI-compatible prefix).
const String ollamaDefaultBaseUrl = 'http://localhost:11434/v1';

/// Ollama chat provider (OpenAI-compatible streaming).
class OllamaProvider extends OpenAiProvider {
  /// Creates a provider pointed at a local (or remote) Ollama server.
  ///
  /// Ollama's OpenAI-compat endpoints typically skip auth; the placeholder
  /// default key is only sent when non-empty — pass `apiKey: ''` to omit
  /// the header entirely.
  OllamaProvider({
    super.baseUrl = ollamaDefaultBaseUrl,
    super.apiKey = '',
    required super.model,
    super.httpClient,
    super.timeout = const Duration(seconds: 180),
  });

  @override
  ProviderId get id => ProviderId.ollama;

  @override
  LlmCapabilities get capabilities => const LlmCapabilities(
        supportsTools: true,
        supportsStreaming: true,
        supportsReasoning: false,
        friendlyName: 'Ollama (local)',
      );
}
