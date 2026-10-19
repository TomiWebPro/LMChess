/// Elo ratings with separate standard/chaotic ladders.
///
/// # Color advantage
///
/// White moves first and wins measurably more often at every level. This
/// service intentionally does **not** bake in a color correction: ratings
/// converge fairly only when schedules balance colors (see
/// `scheduler.dart` fairness guarantees). Consumers displaying ratings
/// from color-imbalanced schedules should say so.
///
/// # Small-sample caveats
///
/// Elo differences below ~30 games per agent are mostly noise. Ratings for
/// agents with fewer than [minGames] games are flagged provisional via
/// [isProvisional]; UI must render a warning ("provisional — < N games")
/// and must never present such a rating as an established skill claim.
/// There is no placement shortcut: every key starts at [initialRating].
library;

import 'dart:math' as math;

/// One applied rating update, for audit/history views.
class EloHistoryEntry {
  /// Agent keys (model ids) for White / Black.
  final String whiteKey;
  final String blackKey;

  /// `'white_win'`, `'black_win'`, or `'draw'`.
  final String result;

  /// Ladder the update applied to (`'standard'` or `'chaotic'`).
  final String mode;

  /// Ratings before the update.
  final double whiteBefore;
  final double blackBefore;

  /// Ratings after the update.
  final double whiteAfter;
  final double blackAfter;

  /// K-factor used.
  final double kFactor;

  /// When the update was applied (UTC).
  final DateTime at;

  /// Creates an entry.
  EloHistoryEntry({
    required this.whiteKey,
    required this.blackKey,
    required this.result,
    required this.mode,
    required this.whiteBefore,
    required this.blackBefore,
    required this.whiteAfter,
    required this.blackAfter,
    required this.kFactor,
    DateTime? at,
  }) : at = (at ?? DateTime.now().toUtc()).toUtc();

  /// Serializes with stable field ordering.
  Map<String, Object?> toJson() => <String, Object?>{
        'whiteKey': whiteKey,
        'blackKey': blackKey,
        'result': result,
        'mode': mode,
        'whiteBefore': whiteBefore,
        'blackBefore': blackBefore,
        'whiteAfter': whiteAfter,
        'blackAfter': blackAfter,
        'kFactor': kFactor,
        'at': at.toIso8601String(),
      };

  /// Parses [toJson] output. Throws [FormatException] on invalid input.
  factory EloHistoryEntry.fromJson(Map json) {
    String str(String k) {
      final v = json[k];
      if (v is! String || v.isEmpty) {
        throw FormatException('EloHistoryEntry.$k must be a non-empty String');
      }
      return v;
    }

    double numOf(String k) {
      final v = json[k];
      if (v is num) return v.toDouble();
      final parsed = double.tryParse('$v');
      if (parsed == null) {
        throw FormatException('EloHistoryEntry.$k must be a number');
      }
      return parsed;
    }

    final atRaw = json['at'];
    DateTime at;
    if (atRaw is String) {
      at = DateTime.parse(atRaw);
    } else {
      throw const FormatException(
          'EloHistoryEntry.at must be an ISO-8601 String');
    }
    return EloHistoryEntry(
      whiteKey: str('whiteKey'),
      blackKey: str('blackKey'),
      result: str('result'),
      mode: str('mode'),
      whiteBefore: numOf('whiteBefore'),
      blackBefore: numOf('blackBefore'),
      whiteAfter: numOf('whiteAfter'),
      blackAfter: numOf('blackAfter'),
      kFactor: numOf('kFactor'),
      at: at.toUtc(),
    );
  }
}

/// Current version of the [EloService] snapshot schema (see [EloService]).
const int eloSnapshotVersion = 1;

/// Elo rating service with independent `standard` and `chaotic` ladders.
///
/// # Crash-resume
///
/// Snapshots are versioned ([EloService.toJson] writes `version:
/// [eloSnapshotVersion]`; [EloService.fromJson] restores). To resume a
/// crashed tournament with intact ratings, either:
///
/// * **snapshot**: persist `toJson()` after each game (or batch) and
///   restore with `fromJson` before resuming scheduling; the scheduler
///   skips non-pending refs, so only pending games re-run with restored
///   ladders; or
/// * **replay**: re-feed completed game results to a fresh service via
///   [updateAfterGame] in original order (deterministic: same inputs give
///   the same ladders).
class EloService {
  /// Rating assigned to unseen keys.
  final double initialRating;

  /// Default K-factor used when callers pass none.
  final double defaultKFactor;

  /// Maximum retained entries in [history] (oldest-first eviction).
  ///
  /// Bounded retention: long tournaments cannot grow memory without
  /// limit. Ratings and game counts are unaffected — eviction only trims
  /// the audit log.
  final int maxHistory;

  final Map<String, double> _standard = <String, double>{};
  final Map<String, double> _chaotic = <String, double>{};
  final Map<String, int> _gamesStandard = <String, int>{};
  final Map<String, int> _gamesChaotic = <String, int>{};

  /// Ordered audit log of applied updates.
  final List<EloHistoryEntry> history = <EloHistoryEntry>[];

  /// Creates a service with optional custom defaults.
  EloService({
    this.initialRating = 1500.0,
    this.defaultKFactor = 32.0,
    this.maxHistory = 10000,
  });

  Map<String, double> _table(String mode) {
    _checkMode(mode);
    return mode == 'chaotic' ? _chaotic : _standard;
  }

  Map<String, int> _games(String mode) {
    _checkMode(mode);
    return mode == 'chaotic' ? _gamesChaotic : _gamesStandard;
  }

  static void _checkMode(String mode) {
    if (mode != 'standard' && mode != 'chaotic') {
      throw ArgumentError.value(mode, 'mode', 'must be standard or chaotic');
    }
  }

  /// Current rating for [modelKey] on [mode]'s ladder.
  /// Unseen keys return [initialRating].
  double ratingFor(String modelKey, String mode) =>
      _table(mode)[modelKey] ?? initialRating;

  /// Games counted for [modelKey] on [mode]'s ladder. This is the
  /// confidence signal: higher is more trustworthy.
  int gamesFor(String modelKey, String mode) =>
      _games(mode)[modelKey] ?? 0;

  /// True when the agent has played fewer than [minGames] games on
  /// [mode]'s ladder. Provisional ratings must be displayed with a
  /// warning and never cited as established skill.
  bool isProvisional(String modelKey, String mode, {int minGames = 10}) =>
      gamesFor(modelKey, mode) < minGames;

  /// Expected score for player A against player B (0..1).
  ///
  /// Standard logistic curve: `1 / (1 + 10^((Rb - Ra) / 400))`.
  static double expectedScore(double ratingA, double ratingB) =>
      1.0 / (1.0 + math.pow(10.0, (ratingB - ratingA) / 400.0));

  /// Applies one game result to the chosen ladder.
  ///
  /// [result] must be `'white_win'`, `'black_win'`, or `'draw'`.
  /// [mode] selects the ladder (default `'standard'`).
  /// [kFactor] defaults to [defaultKFactor]; [minGames] is a real
  /// confidence gate: when either side has played fewer than [minGames]
  /// games on this ladder, the game still counts in the games tally but
  /// the rating update is skipped (returned `false`) — provisional
  /// ratings must never move on untrusted evidence. Use [isProvisional]
  /// to surface the warning flag. Returns `true` when the update applied.
  bool updateAfterGame(
    String whiteKey,
    String blackKey,
    String result, {
    double? kFactor,
    int minGames = 0,
    String mode = 'standard',
  }) {
    _checkMode(mode);
    if (minGames < 0) {
      throw ArgumentError.value(minGames, 'minGames', 'must be >= 0');
    }
    final k = kFactor ?? defaultKFactor;
    if (k <= 0) {
      throw ArgumentError.value(k, 'kFactor', 'must be positive');
    }

    double actualWhite;
    if (result == 'white_win') {
      actualWhite = 1.0;
    } else if (result == 'black_win') {
      actualWhite = 0.0;
    } else if (result == 'draw') {
      actualWhite = 0.5;
    } else {
      throw ArgumentError.value(
          result, 'result', 'must be white_win, black_win, or draw');
    }

    final table = _table(mode);
    final games = _games(mode);
    final whiteGames = games[whiteKey] ?? 0;
    final blackGames = games[blackKey] ?? 0;
    // Confidence gate: tally the game, but hold provisional ratings
    // steady until both sides reach [minGames].
    games[whiteKey] = whiteGames + 1;
    games[blackKey] = blackGames + 1;
    if (whiteGames < minGames || blackGames < minGames) {
      return false;
    }
    final whiteBefore = table[whiteKey] ?? initialRating;
    final blackBefore = table[blackKey] ?? initialRating;
    final expectedWhite = expectedScore(whiteBefore, blackBefore);
    final expectedBlack = 1.0 - expectedWhite;
    final whiteAfter = whiteBefore + k * (actualWhite - expectedWhite);
    final blackAfter =
        blackBefore + k * ((1.0 - actualWhite) - expectedBlack);
    table[whiteKey] = whiteAfter;
    table[blackKey] = blackAfter;
    history.add(EloHistoryEntry(
      whiteKey: whiteKey,
      blackKey: blackKey,
      result: result,
      mode: mode,
      whiteBefore: whiteBefore,
      blackBefore: blackBefore,
      whiteAfter: whiteAfter,
      blackAfter: blackAfter,
      kFactor: k,
    ));
    while (history.length > maxHistory) {
      history.removeAt(0);
    }
    return true;
  }

  /// Serializes both ladders, game counts, and history.
  ///
  /// The map carries `version: [eloSnapshotVersion]`; [fromJson] restores
  /// it (see the crash-resume docs on [EloService]).
  Map<String, Object?> toJson() => <String, Object?>{
        'version': eloSnapshotVersion,
        'initialRating': initialRating,
        'defaultKFactor': defaultKFactor,
        'maxHistory': maxHistory,
        'standard': Map<String, double>.of(_standard),
        'chaotic': Map<String, double>.of(_chaotic),
        'gamesStandard': Map<String, int>.of(_gamesStandard),
        'gamesChaotic': Map<String, int>.of(_gamesChaotic),
        'history': history.map((e) => e.toJson()).toList(),
      };

  /// Restores a [toJson] snapshot. Throws [FormatException] on missing or
  /// unknown `version` — never silently interpret a newer schema with old
  /// code.
  factory EloService.fromJson(Map json) {
    final version = json['version'];
    if (version != eloSnapshotVersion) {
      throw FormatException(
        'Unsupported Elo snapshot version: $version '
        '(expected $eloSnapshotVersion)',
      );
    }
    double asDouble(Object? value, double fallback) {
      if (value is num) return value.toDouble();
      return double.tryParse('$value') ?? fallback;
    }

    int asInt(Object? value, int fallback) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse('$value') ?? fallback;
    }

    Map<String, double> doubleMap(Object? value) {
      final out = <String, double>{};
      if (value is Map) {
        for (final entry in value.entries) {
          final v = entry.value;
          if (v is num) {
            out['${entry.key}'] = v.toDouble();
          }
        }
      }
      return out;
    }

    Map<String, int> intMap(Object? value) {
      final out = <String, int>{};
      if (value is Map) {
        for (final entry in value.entries) {
          final v = entry.value;
          if (v is int) {
            out['${entry.key}'] = v;
          } else if (v is num) {
            out['${entry.key}'] = v.toInt();
          }
        }
      }
      return out;
    }

    final service = EloService(
      initialRating: asDouble(json['initialRating'], 1500.0),
      defaultKFactor: asDouble(json['defaultKFactor'], 32.0),
      maxHistory: asInt(json['maxHistory'], 10000),
    );
    service._standard.addAll(doubleMap(json['standard']));
    service._chaotic.addAll(doubleMap(json['chaotic']));
    service._gamesStandard.addAll(intMap(json['gamesStandard']));
    service._gamesChaotic.addAll(intMap(json['gamesChaotic']));
    final rawHistory = json['history'];
    if (rawHistory is List) {
      for (final entry in rawHistory) {
        if (entry is Map) {
          service.history.add(EloHistoryEntry.fromJson(entry));
        }
      }
      while (service.history.length > service.maxHistory) {
        service.history.removeAt(0);
      }
    }
    return service;
  }
}
