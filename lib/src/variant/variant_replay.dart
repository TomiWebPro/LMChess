/// Lossless, serializable replay record for one chaotic-variant game.
///
/// The record stores the initial [VariantBoard] and, for every ply, the exact
/// attempt (including raw tool-call JSON), the selected interpretation and its
/// event log, king-capture facts, and the resulting board. Boards are canonical
/// [VariantBoard.toJson] payloads, so ids, 0..n kings, counters, flags and
/// notes survive a round-trip. Standard-review types (`ReviewGame`) are
/// deliberately untouched.
library;

import '../chess/piece.dart';
import 'interpretation.dart';
import 'variant_board.dart';

/// Current replay schema. Unknown versions are rejected on read.
const String variantReplaySchemaVersion = '1.0';

/// Who produced the attempt.
enum VariantAttemptSource { model, fallback, human }

/// What the engine did with the attempt.
enum VariantInterpretationKind {
  /// Applied as a standard-legal move.
  standard,

  /// Recovered by the `closestLegalMove` strategy.
  closestLegal,

  /// A non-standard creative reading won selection.
  interpreted,

  /// No candidate survived; the turn passed.
  noopPass;

  /// Classifies [strategyId] into the replay vocabulary.
  static VariantInterpretationKind fromStrategyId(String strategyId) {
    return switch (strategyId) {
      'standard' => standard,
      'closestLegalMove' => closestLegal,
      'noopPass' => noopPass,
      _ => interpreted,
    };
  }
}

/// One attempted move exactly as the model (or fallback) produced it.
class VariantAttemptRecord {
  /// Final UCI string (`from`+`to`+promotion), possibly not standard-legal.
  final String uci;

  /// Raw origin square name.
  final String fromSquareName;

  /// Raw destination square name.
  final String toSquareName;

  /// Promotion hint, if any.
  final String? promotion;

  /// Human-readable phrase attached to the attempt.
  final String phrase;

  /// Exact tool-argument JSON string from the stream, when available.
  final String? rawToolArgsJson;

  /// Parsed tool-argument map, when available.
  final Map<String, Object?>? rawToolCallJson;

  /// Whether this came from the model, a seeded fallback, or a human.
  final VariantAttemptSource source;

  /// Creates an attempt record.
  const VariantAttemptRecord({
    required this.uci,
    required this.fromSquareName,
    required this.toSquareName,
    this.promotion,
    this.phrase = '',
    this.rawToolArgsJson,
    this.rawToolCallJson,
    this.source = VariantAttemptSource.model,
  });

  /// Serializes to JSON.
  Map<String, Object?> toJson() => <String, Object?>{
        'uci': uci,
        'from': fromSquareName,
        'to': toSquareName,
        'promotion': ?promotion,
        'phrase': phrase,
        'rawToolArgsJson': ?rawToolArgsJson,
        'rawToolCallJson': ?rawToolCallJson,
        'source': source.name,
      };

  /// Parses [toJson] output; throws [FormatException] on bad input.
  factory VariantAttemptRecord.fromJson(Map<String, Object?> json) {
    String str(String key, {String fallback = ''}) {
      final value = json[key];
      if (value == null) return fallback;
      if (value is String) return value;
      throw FormatException('VariantAttemptRecord.$key must be a String');
    }

    final raw = json['rawToolCallJson'];
    if (raw != null && raw is! Map) {
      throw const FormatException(
          'VariantAttemptRecord.rawToolCallJson must be a Map');
    }
    return VariantAttemptRecord(
      uci: str('uci'),
      fromSquareName: str('from'),
      toSquareName: str('to'),
      promotion: json['promotion'] is String ? json['promotion'] as String : null,
      phrase: str('phrase'),
      rawToolArgsJson:
          json['rawToolArgsJson'] is String ? json['rawToolArgsJson'] as String : null,
      rawToolCallJson: raw == null
          ? null
          : Map<String, Object?>.from(raw as Map),
      source: VariantAttemptSource.values.firstWhere(
        (s) => s.name == json['source'],
        orElse: () => VariantAttemptSource.model,
      ),
    );
  }
}

/// Replay metadata for one scored interpretation.
///
/// Candidate boards are not serialized: strategies are pure and the selected
/// board is stored on the ply. Metadata is enough to explain the choice.
class VariantInterpretationRecord {
  /// Strategy id (e.g. `directTeleport`, `standard`, `noopPass`).
  final String strategyId;

  /// Short title.
  final String title;

  /// Human-readable description of the reading.
  final String description;

  /// Heuristic selection score (NOT engine evaluation truth).
  final int selectionScoreCp;

  /// Whether any side lost a king in this candidate.
  final bool isKingCapture;

  /// Whether the mover captured an enemy king.
  final bool capturesKing;

  /// Deterministic reproducibility key.
  final String reproducibilityKey;

  /// Layout hash of the resulting board (ids/notes excluded).
  final String boardHash;

  /// Creates an interpretation record.
  const VariantInterpretationRecord({
    required this.strategyId,
    required this.title,
    required this.description,
    required this.selectionScoreCp,
    required this.isKingCapture,
    required this.capturesKing,
    required this.reproducibilityKey,
    required this.boardHash,
  });

  /// Builds a record from an engine candidate.
  factory VariantInterpretationRecord.fromCandidate(
    CandidateInterpretation candidate,
  ) =>
      VariantInterpretationRecord(
        strategyId: candidate.strategyId,
        title: candidate.title,
        description: candidate.description,
        selectionScoreCp: candidate.scoreCp,
        isKingCapture: candidate.isKingCapture,
        capturesKing: candidate.capturesKing,
        reproducibilityKey: candidate.reproducibilityKey,
        boardHash: candidate.resultingBoard.boardHash(),
      );

  /// Serializes to JSON.
  Map<String, Object?> toJson() => <String, Object?>{
        'strategyId': strategyId,
        'title': title,
        'description': description,
        'selectionScoreCp': selectionScoreCp,
        'isKingCapture': isKingCapture,
        'capturesKing': capturesKing,
        'reproducibilityKey': reproducibilityKey,
        'boardHash': boardHash,
      };

  /// Parses [toJson] output; throws [FormatException] on bad input.
  factory VariantInterpretationRecord.fromJson(Map<String, Object?> json) {
    int asInt(String key) {
      final value = json[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      throw FormatException('VariantInterpretationRecord.$key must be an int');
    }

    bool asBool(String key) {
      final value = json[key];
      if (value is bool) return value;
      throw FormatException('VariantInterpretationRecord.$key must be a bool');
    }

    String asString(String key) {
      final value = json[key];
      if (value is String) return value;
      throw FormatException('VariantInterpretationRecord.$key must be a String');
    }

    return VariantInterpretationRecord(
      strategyId: asString('strategyId'),
      title: asString('title'),
      description: asString('description'),
      selectionScoreCp: asInt('selectionScoreCp'),
      isKingCapture: asBool('isKingCapture'),
      capturesKing: asBool('capturesKing'),
      reproducibilityKey: asString('reproducibilityKey'),
      boardHash: asString('boardHash'),
    );
  }
}

/// King-presence facts for one ply, derived from piece ids (not just counts).
class VariantKingFacts {
  /// Mover (`'w'` / `'b'`).
  final String mover;
  final int whiteKingsBefore;
  final int whiteKingsAfter;
  final int blackKingsBefore;
  final int blackKingsAfter;
  final List<String> whiteKingsLost;
  final List<String> blackKingsLost;
  final List<String> whiteKingsGained;
  final List<String> blackKingsGained;

  /// Creates king facts.
  const VariantKingFacts({
    required this.mover,
    required this.whiteKingsBefore,
    required this.whiteKingsAfter,
    required this.blackKingsBefore,
    required this.blackKingsAfter,
    this.whiteKingsLost = const <String>[],
    this.blackKingsLost = const <String>[],
    this.whiteKingsGained = const <String>[],
    this.blackKingsGained = const <String>[],
  });

  /// Whether the mover removed an enemy king.
  bool get capturesEnemyKing =>
      mover == 'w' ? blackKingsLost.isNotEmpty : whiteKingsLost.isNotEmpty;

  /// Whether any king disappeared (including self-inflicted losses).
  bool get anyKingLost =>
      whiteKingsLost.isNotEmpty || blackKingsLost.isNotEmpty;

  /// Kings the mover has after the ply.
  int get moverKingsAfter => mover == 'w' ? whiteKingsAfter : blackKingsAfter;

  /// Kings the opponent has after the ply.
  int get enemyKingsAfter => mover == 'w' ? blackKingsAfter : whiteKingsAfter;

  /// Kings the mover had before the ply.
  int get moverKingsBefore =>
      mover == 'w' ? whiteKingsBefore : blackKingsBefore;

  /// Kings the opponent had before the ply.
  int get enemyKingsBefore =>
      mover == 'w' ? blackKingsBefore : whiteKingsBefore;

  /// Diffs king ids between [before] and [after] for [mover]'s perspective.
  factory VariantKingFacts.between(
    VariantBoard before,
    VariantBoard after,
    PieceColor mover,
  ) {
    Set<String> ids(VariantBoard board, PieceColor color) => <String>{
          for (final sq in board.kingSquares(color)) board.pieceAt(sq)!.id,
        };
    final wb = ids(before, PieceColor.white);
    final wa = ids(after, PieceColor.white);
    final bb = ids(before, PieceColor.black);
    final ba = ids(after, PieceColor.black);
    List<String> lost(Set<String> b, Set<String> a) =>
        (b.difference(a).toList()..sort());
    List<String> gained(Set<String> b, Set<String> a) =>
        (a.difference(b).toList()..sort());
    return VariantKingFacts(
      mover: mover.isWhite ? 'w' : 'b',
      whiteKingsBefore: wb.length,
      whiteKingsAfter: wa.length,
      blackKingsBefore: bb.length,
      blackKingsAfter: ba.length,
      whiteKingsLost: lost(wb, wa),
      blackKingsLost: lost(bb, ba),
      whiteKingsGained: gained(wb, wa),
      blackKingsGained: gained(bb, ba),
    );
  }

  /// Serializes to JSON.
  Map<String, Object?> toJson() => <String, Object?>{
        'mover': mover,
        'whiteKingsBefore': whiteKingsBefore,
        'whiteKingsAfter': whiteKingsAfter,
        'blackKingsBefore': blackKingsBefore,
        'blackKingsAfter': blackKingsAfter,
        'whiteKingsLost': whiteKingsLost,
        'blackKingsLost': blackKingsLost,
        'whiteKingsGained': whiteKingsGained,
        'blackKingsGained': blackKingsGained,
      };

  /// Parses [toJson] output; throws [FormatException] on bad input.
  factory VariantKingFacts.fromJson(Map<String, Object?> json) {
    int asInt(String key) {
      final value = json[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      throw FormatException('VariantKingFacts.$key must be an int');
    }

    List<String> asList(String key) {
      final value = json[key];
      if (value == null) return const <String>[];
      if (value is! List) {
        throw FormatException('VariantKingFacts.$key must be a List');
      }
      return <String>[
        for (final item in value)
          if (item is String)
            item
          else
            throw FormatException('VariantKingFacts.$key entries must be Strings'),
      ];
    }

    final mover = json['mover'];
    if (mover != 'w' && mover != 'b') {
      throw const FormatException('VariantKingFacts.mover must be w or b');
    }
    return VariantKingFacts(
      mover: mover as String,
      whiteKingsBefore: asInt('whiteKingsBefore'),
      whiteKingsAfter: asInt('whiteKingsAfter'),
      blackKingsBefore: asInt('blackKingsBefore'),
      blackKingsAfter: asInt('blackKingsAfter'),
      whiteKingsLost: asList('whiteKingsLost'),
      blackKingsLost: asList('blackKingsLost'),
      whiteKingsGained: asList('whiteKingsGained'),
      blackKingsGained: asList('blackKingsGained'),
    );
  }
}

/// One fully recorded ply.
class VariantPlyRecord {
  /// 0-based ply index.
  final int ply;

  /// Mover (`'w'` / `'b'`).
  final String mover;

  /// Agent attribution, when the turn came from an agent.
  final String? agentId;

  /// Model key, when available.
  final String? modelKey;

  /// Deterministic turn seed.
  final int seed;

  /// Whether this attempt was a seeded fallback.
  final bool fallback;

  /// The exact attempt.
  final VariantAttemptRecord attempt;

  /// Whether the attempt applied as a standard-legal move.
  final bool wasLegal;

  /// Detail from the standard-apply attempt (why it failed, or `legal`).
  final String standardDetail;

  /// Interpretation category.
  final VariantInterpretationKind interpretationKind;

  /// Selected interpretation metadata.
  final VariantInterpretationRecord selected;

  /// All surviving candidates' metadata.
  final List<VariantInterpretationRecord> candidates;

  /// Human-readable pipeline events.
  final List<String> events;

  /// Board after the ply (canonical JSON on the wire).
  final VariantBoard boardAfter;

  /// King facts for this ply.
  final VariantKingFacts kingFacts;

  /// Layout hash before/after (integrity chain).
  final String boardHashBefore;
  final String boardHashAfter;

  /// Selection policy name.
  final String policy;

  /// Failure kind/message when the runner produced no move.
  final String? turnFailureKind;
  final String? turnFailureMessage;

  /// Latency/token usage, when available.
  final int? latencyMs;
  final int? inputTokens;
  final int? outputTokens;

  /// Creates a ply record.
  const VariantPlyRecord({
    required this.ply,
    required this.mover,
    required this.agentId,
    required this.modelKey,
    required this.seed,
    required this.fallback,
    required this.attempt,
    required this.wasLegal,
    required this.standardDetail,
    required this.interpretationKind,
    required this.selected,
    required this.candidates,
    required this.events,
    required this.boardAfter,
    required this.kingFacts,
    required this.boardHashBefore,
    required this.boardHashAfter,
    required this.policy,
    this.turnFailureKind,
    this.turnFailureMessage,
    this.latencyMs,
    this.inputTokens,
    this.outputTokens,
  });

  /// Serializes to JSON.
  Map<String, Object?> toJson() => <String, Object?>{
        'ply': ply,
        'mover': mover,
        'agentId': ?agentId,
        'modelKey': ?modelKey,
        'seed': seed,
        'fallback': fallback,
        'attempt': attempt.toJson(),
        'wasLegal': wasLegal,
        'standardDetail': standardDetail,
        'interpretationKind': interpretationKind.name,
        'selected': selected.toJson(),
        'candidates': <Object?>[for (final c in candidates) c.toJson()],
        'events': events,
        'boardAfter': boardAfter.toJson(),
        'kingFacts': kingFacts.toJson(),
        'boardHashBefore': boardHashBefore,
        'boardHashAfter': boardHashAfter,
        'policy': policy,
        'turnFailureKind': ?turnFailureKind,
        'turnFailureMessage': ?turnFailureMessage,
        'latencyMs': ?latencyMs,
        'inputTokens': ?inputTokens,
        'outputTokens': ?outputTokens,
      };

  /// Parses [toJson] output; throws [FormatException] on bad input.
  factory VariantPlyRecord.fromJson(Map<String, Object?> json) {
    int? maybeInt(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is int) return value;
      if (value is num) return value.toInt();
      throw FormatException('VariantPlyRecord.$key must be an int');
    }

    String? maybeString(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is String) return value;
      throw FormatException('VariantPlyRecord.$key must be a String');
    }

    String asString(String key) {
      final value = maybeString(key);
      if (value == null) {
        throw FormatException('VariantPlyRecord.$key is required');
      }
      return value;
    }

    final mover = asString('mover');
    if (mover != 'w' && mover != 'b') {
      throw const FormatException('VariantPlyRecord.mover must be w or b');
    }
    final attempt = json['attempt'];
    final selected = json['selected'];
    final boardAfter = json['boardAfter'];
    final kingFacts = json['kingFacts'];
    if (attempt is! Map ||
        selected is! Map ||
        boardAfter is! Map ||
        kingFacts is! Map) {
      throw const FormatException(
          'VariantPlyRecord requires attempt/selected/boardAfter/kingFacts maps');
    }
    final rawCandidates = json['candidates'];
    if (rawCandidates != null && rawCandidates is! List) {
      throw const FormatException('VariantPlyRecord.candidates must be a List');
    }
    final candidateList = rawCandidates as List?;
    final rawEvents = json['events'];
    if (rawEvents != null && rawEvents is! List) {
      throw const FormatException('VariantPlyRecord.events must be a List');
    }
    final eventList = rawEvents as List?;
    return VariantPlyRecord(
      ply: maybeInt('ply') ?? 0,
      mover: mover,
      agentId: maybeString('agentId'),
      modelKey: maybeString('modelKey'),
      seed: maybeInt('seed') ?? 0,
      fallback: json['fallback'] == true,
      attempt: VariantAttemptRecord.fromJson(
        Map<String, Object?>.from(attempt),
      ),
      wasLegal: json['wasLegal'] == true,
      standardDetail: maybeString('standardDetail') ?? '',
      interpretationKind: VariantInterpretationKind.values.firstWhere(
        (k) => k.name == json['interpretationKind'],
        orElse: () => VariantInterpretationKind.interpreted,
      ),
      selected: VariantInterpretationRecord.fromJson(
        Map<String, Object?>.from(selected),
      ),
      candidates: candidateList == null
          ? const <VariantInterpretationRecord>[]
          : <VariantInterpretationRecord>[
              for (final c in candidateList)
                if (c is Map)
                  VariantInterpretationRecord.fromJson(
                    Map<String, Object?>.from(c),
                  )
                else
                  throw const FormatException(
                      'VariantPlyRecord.candidates entries must be maps'),
            ],
      events: eventList == null
          ? const <String>[]
          : <String>[
              for (final e in eventList)
                if (e is String)
                  e
                else
                  throw const FormatException(
                      'VariantPlyRecord.events entries must be Strings'),
            ],
      boardAfter: VariantBoard.fromJson(Map<String, Object?>.from(boardAfter)),
      kingFacts: VariantKingFacts.fromJson(
        Map<String, Object?>.from(kingFacts),
      ),
      boardHashBefore: asString('boardHashBefore'),
      boardHashAfter: asString('boardHashAfter'),
      policy: maybeString('policy') ?? 'bestStrategic',
      turnFailureKind: maybeString('turnFailureKind'),
      turnFailureMessage: maybeString('turnFailureMessage'),
      latencyMs: maybeInt('latencyMs'),
      inputTokens: maybeInt('inputTokens'),
      outputTokens: maybeInt('outputTokens'),
    );
  }
}

/// One complete chaotic game, replayable without any engine.
class VariantGameRecord {
  /// Schema version (must be [variantReplaySchemaVersion]).
  final String schemaVersion;

  /// Game id (arena pairing id or a screen-specific id).
  final String id;

  /// Always `'chaotic'` today; kept for forward compatibility.
  final String mode;

  /// Tournament id, when part of an arena run.
  final String? tournamentId;

  /// Display labels and agent ids.
  final String whiteLabel;
  final String blackLabel;
  final String? whiteAgentId;
  final String? blackAgentId;

  /// Game seed.
  final int seed;

  /// Starting board.
  final VariantBoard initialBoard;

  /// Every recorded ply.
  final List<VariantPlyRecord> plies;

  /// Outcome (`'1-0'`, `'0-1'`, `'1/2-1/2'`, `'*'`).
  final String outcome;

  /// Human-readable termination reason.
  final String reason;

  /// Wall-clock timestamps.
  final DateTime? startedAt;
  final DateTime? finishedAt;

  /// Creates a game record.
  const VariantGameRecord({
    this.schemaVersion = variantReplaySchemaVersion,
    required this.id,
    this.mode = 'chaotic',
    this.tournamentId,
    required this.whiteLabel,
    required this.blackLabel,
    this.whiteAgentId,
    this.blackAgentId,
    required this.seed,
    required this.initialBoard,
    required this.plies,
    required this.outcome,
    required this.reason,
    this.startedAt,
    this.finishedAt,
  });

  /// Board visible at [ply] (0 = initial).
  VariantBoard boardAt(int ply) {
    if (ply <= 0) return initialBoard;
    final index = ply - 1;
    if (index >= plies.length) return plies.last.boardAfter;
    return plies[index].boardAfter;
  }

  /// Integrity diagnostics for the board/hash chain; never throws.
  List<String> validateChain() {
    final out = <String>[];
    var previousHash = initialBoard.boardHash();
    for (var i = 0; i < plies.length; i++) {
      final ply = plies[i];
      if (ply.ply != i) {
        out.add('ply $i: recorded index ${ply.ply}');
      }
      if (ply.boardHashBefore != previousHash) {
        out.add(
          'ply $i: before-hash ${ply.boardHashBefore} != previous $previousHash',
        );
      }
      if (ply.boardHashAfter != ply.boardAfter.boardHash()) {
        out.add('ply $i: after-hash does not match stored board');
      }
      previousHash = ply.boardHashAfter;
    }
    return out;
  }

  /// Serializes to JSON.
  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': schemaVersion,
        'id': id,
        'mode': mode,
        'tournamentId': ?tournamentId,
        'whiteLabel': whiteLabel,
        'blackLabel': blackLabel,
        'whiteAgentId': ?whiteAgentId,
        'blackAgentId': ?blackAgentId,
        'seed': seed,
        'initialBoard': initialBoard.toJson(),
        'plies': <Object?>[for (final ply in plies) ply.toJson()],
        'outcome': outcome,
        'reason': reason,
        'startedAt': ?startedAt?.toUtc().toIso8601String(),
        'finishedAt': ?finishedAt?.toUtc().toIso8601String(),
      };

  /// Parses [toJson] output; throws [FormatException] on bad input.
  factory VariantGameRecord.fromJson(Map<String, Object?> json) {
    final version = json['schemaVersion'];
    if (version != variantReplaySchemaVersion) {
      throw FormatException(
        'Unsupported variant replay schemaVersion: $version '
        '(expected $variantReplaySchemaVersion)',
      );
    }
    String asString(String key) {
      final value = json[key];
      if (value is String) return value;
      throw FormatException('VariantGameRecord.$key must be a String');
    }

    String? maybeString(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is String) return value;
      throw FormatException('VariantGameRecord.$key must be a String');
    }

    DateTime? maybeDate(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is String) return DateTime.tryParse(value)?.toUtc();
      throw FormatException('VariantGameRecord.$key must be an ISO string');
    }

    final seed = json['seed'];
    if (seed is! int) {
      throw const FormatException('VariantGameRecord.seed must be an int');
    }
    final initial = json['initialBoard'];
    if (initial is! Map) {
      throw const FormatException(
          'VariantGameRecord.initialBoard must be a Map');
    }
    final rawPlies = json['plies'];
    if (rawPlies is! List) {
      throw const FormatException('VariantGameRecord.plies must be a List');
    }
    return VariantGameRecord(
      schemaVersion: version as String,
      id: asString('id'),
      mode: maybeString('mode') ?? 'chaotic',
      tournamentId: maybeString('tournamentId'),
      whiteLabel: asString('whiteLabel'),
      blackLabel: asString('blackLabel'),
      whiteAgentId: maybeString('whiteAgentId'),
      blackAgentId: maybeString('blackAgentId'),
      seed: seed,
      initialBoard: VariantBoard.fromJson(
        Map<String, Object?>.from(initial),
      ),
      plies: <VariantPlyRecord>[
        for (final ply in rawPlies)
          if (ply is Map)
            VariantPlyRecord.fromJson(Map<String, Object?>.from(ply))
          else
            throw const FormatException(
                'VariantGameRecord.plies entries must be maps'),
      ],
      outcome: maybeString('outcome') ?? '*',
      reason: maybeString('reason') ?? '',
      startedAt: maybeDate('startedAt'),
      finishedAt: maybeDate('finishedAt'),
    );
  }
}
