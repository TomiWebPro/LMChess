/// Leveled application logging with an inspectable in-memory buffer.
///
/// Replaces scattered `dart:developer log(name: ...)` calls (which carry no
/// severity) with five levels — [AppLogLevel.verbose] through
/// [AppLogLevel.error] — so noisy diagnostics can be filtered without losing
/// warnings and errors. Every record lands in a bounded in-memory buffer
/// ([AppLog.recent]) for post-mortem inspection in tests and diagnostics
/// screens, and fans out to configurable [AppLogSink]s (the default sink
/// forwards to `dart:developer log`, visible in DevTools).
///
/// Conventions:
///
/// * Tags mirror the old `name:` values (`'engine-adapter'`,
///   `'LocalAppStore'`, `'openai-provider'`, …) so existing DevTools filters
///   keep working.
/// * Levels: `verbose` = per-event internals (stream deltas, per-ply notes),
///   `debug` = developer diagnostics, `info` = lifecycle milestones (init,
///   game start/finish), `warning` = degraded-but-continuing (fallbacks,
///   quarantines, failed probes), `error` = failures needing attention
///   (stream errors, write errors, unexpected engine exits).
/// * Secrets: redact BEFORE logging (see `arena/export.dart`
///   [redactSecrets] and the activity panel); the logger never sees raw keys.
/// * Plain-Dart code (engines, stores, providers) logs through
///   [AppLog.current]; widget code prefers [appLogProvider] so tests can
///   override it per `ProviderScope`, mirroring `statsLogProvider`.
///   [AppLog.current] itself is replaceable, so unit tests can install a
///   fresh instance and assert on [AppLog.recent].
library;

import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'backend_log.dart';

/// Severity of an [AppLogRecord], ordered quiet → loud.
///
/// Compare with `>=`/`<` (or `index`) to filter; [AppLog.minLevel] drops
/// everything below it before buffering or sinking.
enum AppLogLevel {
  /// Per-event internals (stream deltas, per-ply notes). Off by default.
  verbose,

  /// Developer diagnostics (handshake steps, cache hits).
  debug,

  /// Lifecycle milestones (store init, game start/finish, engine spawn).
  info,

  /// Degraded but continuing (fallbacks, quarantines, failed probes).
  warning,

  /// Failures needing attention (stream errors, write errors, dead engine).
  error,
}

/// One logged event: when, how severe, from where, and what happened.
class AppLogRecord {
  /// Creates a record with an explicit [timestamp] (const-friendly; tests
  /// use this form).
  const AppLogRecord({
    required this.level,
    required this.tag,
    required this.message,
    required this.timestamp,
    this.error,
    this.stackTrace,
  });

  /// Creates a record stamped with the current time.
  factory AppLogRecord.now({
    required AppLogLevel level,
    required String tag,
    required String message,
    Object? error,
    StackTrace? stackTrace,
  }) => AppLogRecord(
    level: level,
    tag: tag,
    message: message,
    timestamp: DateTime.now(),
    error: error,
    stackTrace: stackTrace,
  );

  /// Severity (see [AppLogLevel]).
  final AppLogLevel level;

  /// Subsystem tag (mirrors the old `dart:developer` `name:` values).
  final String tag;

  /// Human-readable message (already redacted by the caller, if needed).
  final String message;

  /// Attached failure, if any.
  final Object? error;

  /// Stack trace for [error], if captured.
  final StackTrace? stackTrace;

  /// When the record was created.
  final DateTime timestamp;

  /// One-line `HH:MM:SS.mmm LEVEL tag: message` form, with `error:` lines
  /// appended when [error]/[stackTrace] are present.
  @override
  String toString() {
    String two(int v) => v.toString().padLeft(2, '0');
    String three(int v) => v.toString().padLeft(3, '0');
    final t = timestamp;
    final buf = StringBuffer(
      '[${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${three(t.millisecond)}] '
      '${level.name.toUpperCase()} $tag: $message',
    );
    if (error != null) buf.write('\n  error: $error');
    if (stackTrace != null) buf.write('\n  stack: $stackTrace');
    return buf.toString();
  }
}

/// Receives every record that passes [AppLog.minLevel].
typedef AppLogSink = void Function(AppLogRecord record);

/// Leveled log with a bounded inspectable buffer and pluggable sinks.
///
/// Create one via [appLogProvider] (widgets) or use [AppLog.current] from
/// plain-Dart code; tests install a fresh instance and assert on [recent].
///
/// Implements [BackendLog] so the UI can wire `currentBackendLog` to this
/// instance at startup; [gameId]/[tournamentId] are prefixed onto the
/// message (no-op when null, preserving existing call-site behavior).
class AppLog implements BackendLog {
  /// Creates a log with its level floor, buffer cap, and extra sinks.
  ///
  /// [sinks] run after the built-in `dart:developer` forwarder; a throwing
  /// sink never breaks logging (it is swallowed).
  AppLog({
    this.minLevel = AppLogLevel.info,
    this.maxRecords = 500,
    List<AppLogSink>? sinks,
  }) : _sinks = sinks ?? <AppLogSink>[];

  /// Shared instance used by plain-Dart call sites ([AppLog.current.info]
  /// etc.). Replaceable in tests (`AppLog.current = AppLog()`).
  static AppLog current = AppLog();

  /// Upper bound on retained records (oldest evicted first).
  final int maxRecords;

  /// Records below this level are dropped before buffering or sinking.
  AppLogLevel minLevel;

  final List<AppLogRecord> _records = <AppLogRecord>[];
  final List<AppLogSink> _sinks;

  /// All retained records (unmodifiable, insertion order).
  List<AppLogRecord> get records => List<AppLogRecord>.unmodifiable(_records);

  /// Adds an extra [sink] (also used by tests to capture records).
  void addSink(AppLogSink sink) => _sinks.add(sink);

  /// Clears the buffer (sinks are kept).
  void clear() => _records.clear();

  /// Buffered records, newest last, filtered by floor [minLevel] and/or
  /// exact [tag], capped to the newest [limit] entries.
  List<AppLogRecord> recent({AppLogLevel? minLevel, String? tag, int? limit}) {
    final out = _records.where((r) {
      if (minLevel != null && r.level.index < minLevel.index) return false;
      if (tag != null && r.tag != tag) return false;
      return true;
    }).toList();
    if (limit != null && out.length > limit) {
      return out.sublist(out.length - limit);
    }
    return out;
  }

  /// Logs [message] at [level] (dropped when below [minLevel]).
  void log(
    AppLogLevel level,
    String message, {
    String tag = 'app',
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (level.index < minLevel.index) return;
    final record = AppLogRecord.now(
      level: level,
      tag: tag,
      message: message,
      error: error,
      stackTrace: stackTrace,
    );
    _records.add(record);
    if (_records.length > maxRecords) {
      _records.removeRange(0, _records.length - maxRecords);
    }
    _forward(record);
    for (final sink in List<AppLogSink>.of(_sinks)) {
      try {
        sink(record);
      } on Object {
        // A throwing sink must never break logging.
      }
    }
  }

  /// Logs a per-event internal at [AppLogLevel.verbose].
  void verbose(
    String message, {
    String tag = 'app',
    Object? error,
    StackTrace? stackTrace,
  }) => log(
    AppLogLevel.verbose,
    message,
    tag: tag,
    error: error,
    stackTrace: stackTrace,
  );

  /// Logs developer diagnostics at [AppLogLevel.debug].
  @override
  void debug(
    String message, {
    String? tag,
    String? gameId,
    String? tournamentId,
    Object? error,
    StackTrace? stackTrace,
  }) => log(
    AppLogLevel.debug,
    _withCorrelation(message, gameId, tournamentId),
    tag: tag ?? 'app',
    error: error,
    stackTrace: stackTrace,
  );

  /// Logs a lifecycle milestone at [AppLogLevel.info].
  @override
  void info(
    String message, {
    String? tag,
    String? gameId,
    String? tournamentId,
    Object? error,
    StackTrace? stackTrace,
  }) => log(
    AppLogLevel.info,
    _withCorrelation(message, gameId, tournamentId),
    tag: tag ?? 'app',
    error: error,
    stackTrace: stackTrace,
  );

  /// Logs a degraded-but-continuing event at [AppLogLevel.warning].
  @override
  void warning(
    String message, {
    String? tag,
    String? gameId,
    String? tournamentId,
    Object? error,
    StackTrace? stackTrace,
  }) => log(
    AppLogLevel.warning,
    _withCorrelation(message, gameId, tournamentId),
    tag: tag ?? 'app',
    error: error,
    stackTrace: stackTrace,
  );

  /// Logs a failure needing attention at [AppLogLevel.error].
  @override
  void error(
    String message, {
    String? tag,
    String? gameId,
    String? tournamentId,
    Object? error,
    StackTrace? stackTrace,
  }) => log(
    AppLogLevel.error,
    _withCorrelation(message, gameId, tournamentId),
    tag: tag ?? 'app',
    error: error,
    stackTrace: stackTrace,
  );

  /// Prefixes correlation IDs onto [message] (no-op when both are null).
  static String _withCorrelation(
    String message,
    String? gameId,
    String? tournamentId,
  ) {
    if (gameId == null && tournamentId == null) return message;
    final buf = StringBuffer();
    if (gameId != null) buf.write('[game $gameId] ');
    if (tournamentId != null) buf.write('[tournament $tournamentId] ');
    buf.write(message);
    return buf.toString();
  }

  /// Forwards [record] to `dart:developer` (visible in DevTools' logging
  /// view); levels map onto the Observatory severity scale.
  void _forward(AppLogRecord record) {
    developer.log(
      record.message,
      name: record.tag,
      level: switch (record.level) {
        AppLogLevel.verbose => 300,
        AppLogLevel.debug => 500,
        AppLogLevel.info => 800,
        AppLogLevel.warning => 900,
        AppLogLevel.error => 1000,
      },
      error: record.error,
      stackTrace: record.stackTrace,
    );
  }
}

/// Provider-scope handle on the shared log (override per-test with a fresh
/// [AppLog], mirroring `statsLogProvider`).
final appLogProvider = Provider<AppLog>((ref) => AppLog.current);
