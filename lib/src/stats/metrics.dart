/// Per-agent aggregate metrics derived from [GameEventRecord] streams.
///
/// # Denominators (read before quoting a rate)
///
/// Every `*Rate` field is a fraction in `[0, 1]`. Denominators differ per
/// metric and are fixed by this table:
///
/// | field              | numerator                        | denominator              |
/// |--------------------|----------------------------------|----------------------------|
/// | [validToolRate]    | turns with a valid tool call     | [turns]                    |
/// | [legalRate]        | turns ending in a legal move     | [turns]                    |
/// | [illegalRate]      | turns with >= 1 illegal attempt  | [turns]                    |
/// | [unparseableRate]  | turns with unparseable output    | [turns]                    |
/// | [missingToolRate]  | turns with no tool call          | [turns]                    |
/// | [providerErrorRate]| provider errors observed         | [turns] (0 if no turns)  |
/// | [timeoutRate]      | turns that timed out             | [turns]                    |
/// | [fallbackRate]     | turns resolved by fallback       | [turns]                    |
///
/// A turn may exhibit several flags at once (e.g. an illegal attempt
/// followed by a legal move counts toward both [illegalRate] and
/// [legalRate]), so rates do **not** sum to 1.
///
/// # Consumed event contract
///
/// [AgentMetrics.compute] reads these well-known `payloadJson` keys:
///
/// * `agentId` (String, required to attribute the event; the deprecated
///   `agentConfigId` alias is accepted as a fallback for one release),
/// * `modelKey` (String, optional; used for cost estimation),
/// * `latencyMs` (num, optional; per-turn latency),
/// * `inputTokens` / `outputTokens` (num, optional),
/// * `color` (`'white'`/`'black'`; the compact `'w'`/`'b'` spellings are
///   normalized defensively),
/// * `mode` (`'standard'`/`'chaotic'`, optional),
/// * `result` (`'win'`/`'loss'`/`'draw'`, on `game.end` events),
/// * boolean flags: `parsedMove`, `validTool`, `legal`, `illegalAttempt`,
///   `unparseable`, `missingTool`, `providerError`, `timeout`, `fallback`.
///
/// The [GameEventRecord.type] string is informational only; attribution
/// and flags come from the payload so producers can evolve type names
/// without breaking aggregation.
///
/// # Turn counting
///
/// Every event with an attributed `agentId` counts as one turn for that
/// agent unless its payload sets `countAsTurn: false` (auxiliary events
/// such as `aiTurnStarted`, `aiStream`, `moveApplied`, rejections, and
/// `game.end` markers, which carry information but are not turns). The
/// default is `true` for backward compatibility with producers that log
/// bare turn records without the key; producers emitting multiple events
/// per turn (e.g. the orchestrator) must set `countAsTurn: true`
/// explicitly on exactly one turn-summary event per turn and `false`
/// everywhere else, so the [turns] denominator counts turns, not events.
///
/// # Cost estimation
///
/// [estCostUsd] = `inputTokens / 1e6 * inputPer1M +
/// outputTokens / 1e6 * outputPer1M` using [pricingTable]. Models absent
/// from the table contribute `0` and set [pricingKnown] to `false`.
library;

import 'dart:math' as math;

import 'event_log.dart';

/// Per-1M-token prices in USD for a known model.
class ModelPricing {
  /// USD per 1M input tokens.
  final double inputPer1M;

  /// USD per 1M output tokens.
  final double outputPer1M;

  /// Creates a pricing entry. Both values must be non-negative.
  const ModelPricing({required this.inputPer1M, required this.outputPer1M});
}

/// USD price per 1M tokens for known models.
///
/// Keyed by lowercase `modelKey` (e.g. `'gpt-4o'`). Values are snapshot
/// estimates for display/ranking only — never use for billing.
/// Unknown models estimate to `0` and flip [AgentMetrics.pricingKnown]
/// to `false` so the UI can show "pricing unavailable" instead of "$0".
const Map<String, ModelPricing> pricingTable = <String, ModelPricing>{
  'gpt-4o': ModelPricing(inputPer1M: 2.50, outputPer1M: 10.00),
  'gpt-4o-mini': ModelPricing(inputPer1M: 0.15, outputPer1M: 0.60),
  'gpt-4.1': ModelPricing(inputPer1M: 2.00, outputPer1M: 8.00),
  'o1': ModelPricing(inputPer1M: 15.00, outputPer1M: 60.00),
  'o3-mini': ModelPricing(inputPer1M: 1.10, outputPer1M: 4.40),
  'claude-3-5-sonnet': ModelPricing(inputPer1M: 3.00, outputPer1M: 15.00),
  'claude-3-5-haiku': ModelPricing(inputPer1M: 0.80, outputPer1M: 4.00),
  'claude-3-opus': ModelPricing(inputPer1M: 15.00, outputPer1M: 75.00),
  'gemini-1.5-pro': ModelPricing(inputPer1M: 1.25, outputPer1M: 5.00),
  'gemini-1.5-flash': ModelPricing(inputPer1M: 0.075, outputPer1M: 0.30),
  'gemini-2.0-flash': ModelPricing(inputPer1M: 0.10, outputPer1M: 0.40),
  'grok-2': ModelPricing(inputPer1M: 2.00, outputPer1M: 10.00),
  'deepseek-chat': ModelPricing(inputPer1M: 0.27, outputPer1M: 1.10),
  'llama-3.3-70b': ModelPricing(inputPer1M: 0.35, outputPer1M: 0.40),
};

/// Aggregated per-agent statistics. See library docs for denominators.
class AgentMetrics {
  /// Number of turns attributed to the agent.
  final int turns;

  /// Turns where model output parsed into a candidate move.
  final int parsedMoves;

  /// Fraction of turns with a valid tool call. Denominator: [turns].
  final double validToolRate;

  /// Fraction of turns ending in a legal move. Denominator: [turns].
  final double legalRate;

  /// Fraction of turns with >= 1 illegal attempt. Denominator: [turns].
  final double illegalRate;

  /// Fraction of turns with unparseable output. Denominator: [turns].
  final double unparseableRate;

  /// Fraction of turns with no tool call. Denominator: [turns].
  final double missingToolRate;

  /// Fraction of turns with a provider error. Denominator: [turns].
  final double providerErrorRate;

  /// Fraction of turns that timed out. Denominator: [turns].
  final double timeoutRate;

  /// Fraction of turns resolved by fallback policy. Denominator: [turns].
  final double fallbackRate;

  /// Mean per-turn latency in ms (0 when no latency samples).
  final double avgLatencyMs;

  /// 50th percentile latency in ms (0 when no samples).
  final double p50;

  /// 95th percentile latency in ms (0 when no samples).
  final double p95;

  /// Total input tokens observed.
  final int inputTokens;

  /// Total output tokens observed.
  final int outputTokens;

  /// Estimated cost in USD via [pricingTable].
  final double estCostUsd;

  /// `false` when any attributed event used an unknown model key, in
  /// which case [estCostUsd] is a lower bound (unknown part counted as 0).
  final bool pricingKnown;

  /// Games won / lost / drawn (from `game.end`-style result flags).
  final int wins;
  final int losses;
  final int draws;

  /// Turn counts by color, e.g. `{'white': 12, 'black': 10}`.
  final Map<String, int> byColor;

  /// Turn counts by mode, e.g. `{'standard': 20, 'chaotic': 2}`.
  final Map<String, int> byMode;

  /// Creates an aggregate. Rates must be in `[0, 1]`.
  const AgentMetrics({
    this.turns = 0,
    this.parsedMoves = 0,
    this.validToolRate = 0,
    this.legalRate = 0,
    this.illegalRate = 0,
    this.unparseableRate = 0,
    this.missingToolRate = 0,
    this.providerErrorRate = 0,
    this.timeoutRate = 0,
    this.fallbackRate = 0,
    this.avgLatencyMs = 0,
    this.p50 = 0,
    this.p95 = 0,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.estCostUsd = 0,
    this.pricingKnown = true,
    this.wins = 0,
    this.losses = 0,
    this.draws = 0,
    this.byColor = const <String, int>{},
    this.byMode = const <String, int>{},
  });

  /// Zero-value metrics (no data).
  static const AgentMetrics empty = AgentMetrics();

  /// Aggregates [events] into per-agent metrics keyed by `agentId`.
  ///
  /// Events attribution: the `agentId` payload key attributes the event;
  /// the deprecated `agentConfigId` alias is accepted when `agentId` is
  /// absent (one-release compatibility window). Events with neither are
  /// skipped. Compact colors (`'w'`/`'b'`, any case) are normalized to
  /// `'white'`/`'black'`; any other non-empty color string is kept as-is.
  /// Every attributed event counts as one turn for that agent unless its
  /// payload sets `countAsTurn: false` (used by auxiliary events and by
  /// `game.end` markers, which carry a result but are not turns). The
  /// default for a missing key is `true` for backward compatibility with
  /// producers that log bare turn records; multi-event producers must set
  /// the key explicitly (exactly one `true` per turn).
  static Map<String, AgentMetrics> compute(List<GameEventRecord> events) {
    final turns = <String, int>{};
    final parsed = <String, int>{};
    final validTool = <String, int>{};
    final legal = <String, int>{};
    final illegal = <String, int>{};
    final unparseable = <String, int>{};
    final missingTool = <String, int>{};
    final providerError = <String, int>{};
    final timeout = <String, int>{};
    final fallback = <String, int>{};
    final latencies = <String, List<double>>{};
    final inTokens = <String, int>{};
    final outTokens = <String, int>{};
    final cost = <String, double>{};
    final pricingKnown = <String, bool>{};
    final wins = <String, int>{};
    final losses = <String, int>{};
    final draws = <String, int>{};
    final byColor = <String, Map<String, int>>{};
    final byMode = <String, Map<String, int>>{};

    void bump(Map<String, int> m, String k) => m[k] = (m[k] ?? 0) + 1;

    bool flag(Map<String, Object?> p, String k) => p[k] == true;

    for (final e in events) {
      final p = e.payloadJson;
      // Attribution: `agentId` is canonical; the deprecated
      // `agentConfigId` alias keeps old producers working for one release.
      var agentId = p['agentId'];
      if (agentId is! String || agentId.isEmpty) {
        final alias = p['agentConfigId'];
        if (alias is String && alias.isNotEmpty) {
          agentId = alias;
        } else {
          continue;
        }
      }
      final String agent = agentId;
      pricingKnown.putIfAbsent(agent, () => true);

      // Result-only markers (e.g. game.end) update W/L/D without
      // counting a turn, unless the producer says otherwise.
      final countAsTurn = p['countAsTurn'];
      final isTurn = countAsTurn is bool ? countAsTurn : true;
      if (isTurn) {
        bump(turns, agentId);
        if (flag(p, 'parsedMove')) bump(parsed, agentId);
        if (flag(p, 'validTool')) bump(validTool, agentId);
        if (flag(p, 'legal')) bump(legal, agentId);
        if (flag(p, 'illegalAttempt')) bump(illegal, agentId);
        if (flag(p, 'unparseable')) bump(unparseable, agentId);
        if (flag(p, 'missingTool')) bump(missingTool, agentId);
        if (flag(p, 'providerError')) bump(providerError, agentId);
        if (flag(p, 'timeout')) bump(timeout, agentId);
        if (flag(p, 'fallback')) bump(fallback, agentId);

        final latency = p['latencyMs'];
        if (latency is num) {
          latencies.putIfAbsent(agentId, () => <double>[]).add(latency.toDouble());
        }
        final inT = p['inputTokens'];
        if (inT is num) inTokens[agentId] = (inTokens[agentId] ?? 0) + inT.toInt();
        final outT = p['outputTokens'];
        if (outT is num) outTokens[agentId] = (outTokens[agentId] ?? 0) + outT.toInt();

        // Cost: only when a modelKey is present so unattributed token
        // counts never silently price at 0.
        final modelKey = p['modelKey'];
        if (modelKey is String && modelKey.isNotEmpty) {
          final pricing = pricingTable[modelKey.toLowerCase()];
          if (pricing == null) {
            pricingKnown[agentId] = false;
          } else {
            final i = inT is num ? inT.toDouble() : 0.0;
            final o = outT is num ? outT.toDouble() : 0.0;
            cost[agentId] = (cost[agentId] ?? 0.0) +
                (i / 1e6 * pricing.inputPer1M + o / 1e6 * pricing.outputPer1M);
          }
        }

        final color = p['color'];
        if (color is String && color.isNotEmpty) {
          final m = byColor.putIfAbsent(agentId, () => <String, int>{});
          bump(m, normalizeColor(color));
        }
        final mode = p['mode'];
        if (mode is String && mode.isNotEmpty) {
          final m = byMode.putIfAbsent(agentId, () => <String, int>{});
          bump(m, mode);
        }
      }

      final result = p['result'];
      if (result == 'win') {
        bump(wins, agentId);
      } else if (result == 'loss') {
        bump(losses, agentId);
      } else if (result == 'draw') {
        bump(draws, agentId);
      }
    }

    final ids = <String>{
      ...turns.keys,
      ...wins.keys,
      ...losses.keys,
      ...draws.keys,
    };
    final out = <String, AgentMetrics>{};
    for (final id in ids) {
      final n = turns[id] ?? 0;
      double rate(int c) => n == 0 ? 0.0 : c / n;
      final lat = latencies[id] ?? const <double>[];
      out[id] = AgentMetrics(
        turns: n,
        parsedMoves: parsed[id] ?? 0,
        validToolRate: rate(validTool[id] ?? 0),
        legalRate: rate(legal[id] ?? 0),
        illegalRate: rate(illegal[id] ?? 0),
        unparseableRate: rate(unparseable[id] ?? 0),
        missingToolRate: rate(missingTool[id] ?? 0),
        providerErrorRate: rate(providerError[id] ?? 0),
        timeoutRate: rate(timeout[id] ?? 0),
        fallbackRate: rate(fallback[id] ?? 0),
        avgLatencyMs: lat.isEmpty ? 0.0 : lat.reduce((a, b) => a + b) / lat.length,
        p50: _percentile(lat, 50),
        p95: _percentile(lat, 95),
        inputTokens: inTokens[id] ?? 0,
        outputTokens: outTokens[id] ?? 0,
        estCostUsd: cost[id] ?? 0.0,
        pricingKnown: pricingKnown[id] ?? true,
        wins: wins[id] ?? 0,
        losses: losses[id] ?? 0,
        draws: draws[id] ?? 0,
        byColor: Map<String, int>.unmodifiable(byColor[id] ?? const <String, int>{}),
        byMode: Map<String, int>.unmodifiable(byMode[id] ?? const <String, int>{}),
      );
    }
    return out;
  }

  /// Nearest-rank percentile over [values] (unsorted input accepted).
  /// Returns 0 when empty.
  static double _percentile(List<double> values, int p) {
    if (values.isEmpty) return 0.0;
    assert(p >= 0 && p <= 100);
    final sorted = List<double>.of(values)..sort();
    if (sorted.length == 1) return sorted.single;
    final rank = (p / 100 * sorted.length).ceil().clamp(1, sorted.length);
    return sorted[rank - 1];
  }

  /// Lowest latency sample helper kept for symmetry with p50/p95.
  static double minOf(List<double> values) =>
      values.isEmpty ? 0.0 : values.reduce(math.min);

  /// Normalizes a color label to the canonical `'white'`/`'black'`
  /// vocabulary: compact `'w'`/`'b'` (any case/whitespace) map to the full
  /// names; anything else passes through trimmed and lowercased so
  /// aggregation buckets stay stable.
  static String normalizeColor(String color) {
    final c = color.trim().toLowerCase();
    if (c == 'w' || c == 'white') return 'white';
    if (c == 'b' || c == 'black') return 'black';
    return c;
  }

  /// Serializes to a JSON-compatible map with stable field ordering.
  Map<String, Object?> toJson() => <String, Object?>{
        'turns': turns,
        'parsedMoves': parsedMoves,
        'validToolRate': validToolRate,
        'legalRate': legalRate,
        'illegalRate': illegalRate,
        'unparseableRate': unparseableRate,
        'missingToolRate': missingToolRate,
        'providerErrorRate': providerErrorRate,
        'timeoutRate': timeoutRate,
        'fallbackRate': fallbackRate,
        'avgLatencyMs': avgLatencyMs,
        'p50': p50,
        'p95': p95,
        'inputTokens': inputTokens,
        'outputTokens': outputTokens,
        'estCostUsd': estCostUsd,
        'pricingKnown': pricingKnown,
        'wins': wins,
        'losses': losses,
        'draws': draws,
        'byColor': byColor,
        'byMode': byMode,
      };
}
