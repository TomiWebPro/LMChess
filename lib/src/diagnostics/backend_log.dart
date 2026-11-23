/// UI-free logging contract for backend/domain layers.
///
/// Pure Dart: no Flutter/Riverpod imports so `game`, `llm`, `arena`,
/// `ui/backend` and friends can depend on it without pulling UI. The UI
/// wires the real implementation at startup
/// (`currentBackendLog = AppLog.current` in `main.dart`); before that (and
/// in pure-Dart tests) it defaults to [NoopBackendLog].
library;

/// Minimal leveled logger used by backend/domain code.
///
/// Correlation IDs ([gameId]/[tournamentId]) travel as explicit named
/// parameters so every entry/exit/failure record can be tied back to the
/// game and tournament that produced it. Implementations decide how to
/// render them (the [AppLog] adapter prefixes them onto the message).
abstract class BackendLog {
  /// Developer diagnostics (handshake steps, cache hits, turn start/end).
  void debug(
    String msg, {
    String? tag,
    String? gameId,
    String? tournamentId,
    Object? error,
    StackTrace? stackTrace,
  });

  /// Lifecycle milestones (game start/finish, provider ready).
  void info(
    String msg, {
    String? tag,
    String? gameId,
    String? tournamentId,
    Object? error,
    StackTrace? stackTrace,
  });

  /// Degraded-but-continuing events (fallbacks, quarantines, failed probes).
  void warning(
    String msg, {
    String? tag,
    String? gameId,
    String? tournamentId,
    Object? error,
    StackTrace? stackTrace,
  });

  /// Failures needing attention (stream errors, unexpected exits).
  void error(
    String msg, {
    String? tag,
    String? gameId,
    String? tournamentId,
    Object? error,
    StackTrace? stackTrace,
  });
}

/// Drops every record. Default for [currentBackendLog] until the UI wires
/// the real implementation at startup, and handy for tests that do not
/// assert on logs.
class NoopBackendLog implements BackendLog {
  /// Creates a no-op log.
  const NoopBackendLog();

  @override
  void debug(
    String msg, {
    String? tag,
    String? gameId,
    String? tournamentId,
    Object? error,
    StackTrace? stackTrace,
  }) {}

  @override
  void info(
    String msg, {
    String? tag,
    String? gameId,
    String? tournamentId,
    Object? error,
    StackTrace? stackTrace,
  }) {}

  @override
  void warning(
    String msg, {
    String? tag,
    String? gameId,
    String? tournamentId,
    Object? error,
    StackTrace? stackTrace,
  }) {}

  @override
  void error(
    String msg, {
    String? tag,
    String? gameId,
    String? tournamentId,
    Object? error,
    StackTrace? stackTrace,
  }) {}
}

/// Shared backend logger used by domain code.
///
/// Defaults to a [NoopBackendLog]; the UI sets this to `AppLog.current`
/// once at startup (see `lib/main.dart`). Backend call sites must resolve
/// it per-call (`log ?? currentBackendLog`) rather than capturing it in a
/// default parameter value (Dart requires const defaults).
BackendLog currentBackendLog = const NoopBackendLog();
