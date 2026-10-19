/// Shared HTTP/SSE helpers for the streaming LLM providers.
///
/// Pure Dart (`package:http` + SDK only). This file exists to dedupe the
/// small routines every streaming provider needs **without** restructuring
/// the class hierarchy or changing any wire behavior:
///
/// * [jsonHeaders] — builds JSON POST headers (optional bearer / API-key
///   headers merged in).
/// * [readErrorBody] — reads up to ~2 KB of a failed [http.StreamedResponse]
///   body for error details (never throws).
/// * [sseDataValue] / [isSseComment] / [isSseBlankLine] — SSE line
///   classifiers with the exact semantics the providers already used:
///   a `data:` prefix (one optional leading space stripped), `:` comments,
///   and blank dispatch lines.
/// * [sseLinesWithInactivityTimeout] — wraps a response byte stream as a
///   line stream that fails with [TimeoutException] when no line arrives
///   within [inactivityTimeout] (timer resets on every received line).
///   The underlying subscription is cancelled on timeout so a stalled
///   server cannot hang the `await for` body loop forever. Providers catch
///   the [TimeoutException] and emit a retryable `timeout` terminal event.
///
/// Behavior-preservation note: these are extractions of the exact logic
/// previously inlined in `openai_provider.dart`, `anthropic_provider.dart`
/// and `gemini_provider.dart` — call sites were converted mechanically.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Builds JSON POST headers, merging optional auth headers.
///
/// * [bearerToken] — when non-empty, added as `Authorization: Bearer …`.
/// * [extra] — provider-specific headers (e.g. `x-api-key`,
///   `anthropic-version`, `x-goog-api-key`); entries with empty values are
///   dropped so keyless backends omit auth headers entirely.
Map<String, String> jsonHeaders({
  String? bearerToken,
  Map<String, String>? extra,
}) {
  final headers = <String, String>{'Content-Type': 'application/json'};
  if (bearerToken != null && bearerToken.isNotEmpty) {
    headers['Authorization'] = 'Bearer $bearerToken';
  }
  if (extra != null) {
    for (final entry in extra.entries) {
      if (entry.value.isNotEmpty) headers[entry.key] = entry.value;
    }
  }
  return headers;
}

/// Reads up to ~2 KB of a failed response body for error details.
///
/// Never throws — returns `''` when the body cannot be read.
Future<String> readErrorBody(
  http.StreamedResponse response, {
  int maxChars = 2048,
}) async {
  try {
    final text = await response.stream
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 5));
    final trimmed = text.trim();
    return trimmed.length > maxChars
        ? trimmed.substring(0, maxChars)
        : trimmed;
  } catch (_) {
    return '';
  }
}

/// Returns the payload of an SSE `data:` line, or `null` when [line] is not
/// a data line.
///
/// Exactly one optional leading space after the prefix is stripped
/// (`'data: {...}'` → `'{...}'`), matching the providers' prior inline
/// parsing. Multi-line `data:` accumulations are joined by the caller with
/// [StringBuffer.writeln], as before.
String? sseDataValue(String line) {
  if (!line.startsWith('data:')) return null;
  var value = line.substring(5);
  if (value.startsWith(' ')) value = value.substring(1);
  return value;
}

/// Whether [line] is an SSE comment / keep-alive (`:` prefix).
bool isSseComment(String line) => line.startsWith(':');

/// Whether [line] is a blank dispatch line ending one SSE event.
bool isSseBlankLine(String line) => line.trim().isEmpty;

/// Wraps a response byte [source] as a line stream with an inactivity
/// deadline.
///
/// The [inactivityTimeout] timer resets on every received line; when it
/// fires (no line arrived in time) the underlying subscription is
/// cancelled and the returned stream errors with a [TimeoutException]
/// then closes. Providers treat that as a retryable `timeout` terminal.
///
/// Callers pass the provider's per-attempt [TimeoutException] budget as
/// [inactivityTimeout] so a hung server can stall at most one budget
/// between lines instead of hanging the body loop forever.
Stream<String> sseLinesWithInactivityTimeout(
  Stream<List<int>> source,
  Duration inactivityTimeout,
) {
  late final StreamController<String> controller;
  StreamSubscription<String>? subscription;
  Timer? timer;

  void cancelTimer() {
    timer?.cancel();
    timer = null;
  }

  void armTimer() {
    cancelTimer();
    timer = Timer(inactivityTimeout, () {
      // No line arrived in time: drop the hung connection and surface a
      // retryable timeout so the provider yields its timeout terminal.
      unawaited(subscription?.cancel());
      cancelTimer();
      controller.addError(
        TimeoutException(
          'SSE stream stalled: no data for '
          '${inactivityTimeout.inMilliseconds}ms.',
        ),
      );
      unawaited(controller.close());
    });
  }

  controller = StreamController<String>(
    onListen: () {
      armTimer();
      subscription = source
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          armTimer();
          controller.add(line);
        },
        onError: (Object error, StackTrace stack) {
          cancelTimer();
          controller.addError(error, stack);
          unawaited(controller.close());
        },
        onDone: () {
          cancelTimer();
          unawaited(controller.close());
        },
        cancelOnError: true,
      );
    },
    onCancel: () async {
      cancelTimer();
      await subscription?.cancel();
    },
  );
  return controller.stream;
}
