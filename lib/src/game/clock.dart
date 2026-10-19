/// Deterministic chess clock owned by the orchestrator.
///
/// "Deterministic" means the clock never samples wall-clock time itself:
/// every mutation takes an explicit elapsed/stamp argument, so arena
/// replays and tests control time exactly. The orchestrator measures real
/// elapsed time around turns (Stopwatch/DateTime) and feeds it in via
/// [consume]; [start]/[stop] only record bookkeeping stamps.
///
/// Pure Dart, no timers, no streams.
library;

/// Time-control families.
enum TimeControlType {
  /// No clock; [ChessClock.consume] is a no-op for bookkeeping only.
  none,

  /// Fixed time per game, no bonus.
  fixed,

  /// Fischer increment: [TimeControl.incrementMs] is added back after every
  /// consumed turn.
  increment,

  /// US delay: up to [TimeControl.delayMs] of each turn is not charged.
  delay,
}

/// Static time-control settings for a game.
class TimeControl {
  /// Which family applies.
  final TimeControlType type;

  /// Initial time per side in ms.
  final int initialMs;

  /// Fischer bonus in ms (only meaningful for [TimeControlType.increment]).
  final int? incrementMs;

  /// Free time per turn in ms (only meaningful for [TimeControlType.delay]).
  final int? delayMs;

  /// Creates a time control.
  const TimeControl({
    required this.type,
    required this.initialMs,
    this.incrementMs,
    this.delayMs,
  });

  /// No clock.
  const TimeControl.none()
      : type = TimeControlType.none,
        initialMs = 0,
        incrementMs = null,
        delayMs = null;

  /// Validates settings, returning human-readable problems (empty = valid).
  List<String> validate() {
    final problems = <String>[];
    if (initialMs < 0) problems.add('initialMs must be >= 0.');
    if (type == TimeControlType.none && initialMs != 0) {
      problems.add('initialMs must be 0 for TimeControl.none.');
    }
    if (incrementMs != null && incrementMs! < 0) {
      problems.add('incrementMs must be >= 0.');
    }
    if (delayMs != null && delayMs! < 0) {
      problems.add('delayMs must be >= 0.');
    }
    if (type == TimeControlType.increment &&
        (incrementMs == null || incrementMs == 0)) {
      problems.add('increment time control needs a positive incrementMs.');
    }
    if (type == TimeControlType.delay &&
        (delayMs == null || delayMs == 0)) {
      problems.add('delay time control needs a positive delayMs.');
    }
    return problems;
  }

  /// Serializes to JSON.
  Map<String, Object?> toJson() => {
        'type': type.name,
        'initialMs': initialMs,
        if (incrementMs != null) 'incrementMs': incrementMs,
        if (delayMs != null) 'delayMs': delayMs,
      };

  /// Parses from JSON; unknown types fall back to [TimeControlType.none].
  factory TimeControl.fromJson(Map json) {
    int asInt(Object? value, int fallback) =>
        value is int ? value : int.tryParse('$value') ?? fallback;
    var type = TimeControlType.none;
    for (final candidate in TimeControlType.values) {
      if (candidate.name == '${json['type']}') {
        type = candidate;
        break;
      }
    }
    int? asOptInt(Object? value) =>
        value == null ? null : asInt(value, 0);
    return TimeControl(
      type: type,
      initialMs: asInt(json['initialMs'], 0),
      incrementMs: asOptInt(json['incrementMs']),
      delayMs: asOptInt(json['delayMs']),
    );
  }
}

/// Mutable remaining-time state for both sides.
///
/// Colors are `'w'`/`'b'` (case-insensitive; anything starting with `b` is
/// Black). Remaining time may go negative to record overrun; [isFlagged]
/// reports `remaining <= 0`.
class ChessClock {
  /// Remaining time for White in ms.
  int remainingW;

  /// Remaining time for Black in ms.
  int remainingB;

  /// Time-control family this clock enforces.
  ///
  /// [TimeControlType.none] disables the clock entirely: [consume] is a
  /// no-op and [isFlagged] always returns false. Defaults to
  /// [TimeControlType.fixed] so explicitly constructed clocks keep the
  /// historical charge-and-flag behavior.
  final TimeControlType controlType;

  /// Last start/stop bookkeeping stamp in ms (caller-provided epoch), or
  /// `null` when never started. Informational only — never drives math.
  int? lastTickStamp;

  bool _running = false;
  String _runningColor = 'w';

  /// Creates a clock with explicit remaining times.
  ChessClock({
    required this.remainingW,
    required this.remainingB,
    this.lastTickStamp,
    this.controlType = TimeControlType.fixed,
  });

  /// Creates a clock from a [TimeControl] (both sides get `initialMs`).
  factory ChessClock.fromTimeControl(TimeControl control) {
    return ChessClock(
      remainingW: control.initialMs,
      remainingB: control.initialMs,
      controlType: control.type,
    );
  }

  /// Whether the clock is currently running (bookkeeping flag for the UI).
  bool get isRunning => _running;

  /// Which side the clock is running for (bookkeeping only).
  String get runningColor => _runningColor;

  /// Starts (or restarts) the clock for [color], recording [nowMs].
  void start({String color = 'w', int? nowMs}) {
    _running = true;
    _runningColor = _normalize(color);
    if (nowMs != null) lastTickStamp = nowMs;
  }

  /// Stops the clock, recording [nowMs].
  void stop({int? nowMs}) {
    _running = false;
    if (nowMs != null) lastTickStamp = nowMs;
  }

  /// Charges [elapsedMs] to [color]'s remaining time.
  ///
  /// * [delayMs] (US delay): the first [delayMs] of the turn is free, i.e.
  ///   only `max(0, elapsedMs - delayMs)` is charged.
  /// * [incrementMs] (Fischer): added back in full after the charge.
  ///
  /// No-op when [controlType] is [TimeControlType.none]: untimed games
  /// never flag. Pass the values from the game's [TimeControl]; defaults
  /// (0/0) model fixed/no-bonus clocks. Never clamps: overrun goes
  /// negative so [isFlagged] can adjudicate.
  void consume(String color, int elapsedMs,
      {int incrementMs = 0, int delayMs = 0}) {
    if (controlType == TimeControlType.none) return;
    final normalized = _normalize(color);
    final chargeable = elapsedMs < 0
        ? 0
        : (elapsedMs - delayMs < 0 ? 0 : elapsedMs - delayMs);
    if (normalized == 'b') {
      remainingB = remainingB - chargeable + incrementMs;
    } else {
      remainingW = remainingW - chargeable + incrementMs;
    }
  }

  /// Remaining time for [color] in ms.
  int remaining(String color) =>
      _normalize(color) == 'b' ? remainingB : remainingW;

  /// Whether [color]'s time has run out (`remaining <= 0`).
  ///
  /// Always false when [controlType] is [TimeControlType.none]: untimed
  /// games cannot flag.
  bool isFlagged(String color) =>
      controlType == TimeControlType.none ? false : remaining(color) <= 0;

  /// Serializes to JSON.
  Map<String, Object?> toJson() => {
        'remainingW': remainingW,
        'remainingB': remainingB,
        'controlType': controlType.name,
        if (lastTickStamp != null) 'lastTickStamp': lastTickStamp,
        'isRunning': _running,
        'runningColor': _runningColor,
      };

  /// Parses from JSON; missing keys default to zeros/stopped.
  ///
  /// Missing `controlType` falls back to [TimeControlType.fixed] to
  /// preserve the historical charge-and-flag behavior of snapshots
  /// written before the field existed.
  factory ChessClock.fromJson(Map json) {
    int asInt(Object? value) =>
        value is int ? value : int.tryParse('$value') ?? 0;
    var controlType = TimeControlType.fixed;
    for (final candidate in TimeControlType.values) {
      if (candidate.name == '${json['controlType']}') {
        controlType = candidate;
        break;
      }
    }
    final clock = ChessClock(
      remainingW: asInt(json['remainingW']),
      remainingB: asInt(json['remainingB']),
      lastTickStamp: json['lastTickStamp'] is int
          ? json['lastTickStamp'] as int
          : null,
      controlType: controlType,
    );
    if (json['isRunning'] == true) {
      clock.start(
        color: json['runningColor'] is String
            ? json['runningColor'] as String
            : 'w',
      );
    }
    return clock;
  }

  static String _normalize(String color) =>
      color.trim().toLowerCase().startsWith('b') ? 'b' : 'w';
}
