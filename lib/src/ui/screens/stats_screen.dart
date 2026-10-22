/// [StatsScreen]: fl_chart dashboards over real game telemetry.
///
/// Data comes from the shared telemetry singletons in `backend_bridge.dart`
/// through their real backend contracts — no sample constants:
///
/// * every turn row is a [GameEventRecord] read from [StatsLog.store]
///   (the idempotent [InMemoryEventStore] mirror) and aggregated by the
///   real [AgentMetrics.compute];
/// * the outcome pie reads the `result` markers (`win`/`loss`/`draw`) each
///   finished game logs per seat;
/// * the error-category bar maps each turn through [statsErrorCategory]
///   (`none`/`illegal`/`timeout`/`parse`/`engine`);
/// * the latency histogram buckets the `latencyMs` payloads;
/// * the quality distribution renders [QualityLog.marks] — the per-ply
///   marks the review screen derives from real quality classifications
///   (empty until a review runs, with an honest inline empty state).
///
/// A [ListenableBuilder] over [StatsLog.changes] + [QualityLog.changes]
/// re-renders when a game flushes or a review finishes. Agent/mode
/// dropdowns filter the turn rows and the metrics table; game-count
/// aggregates live in the metrics table. The grid is responsive
/// (2 cols >= 700px, else 1); empty data shows a wiring-point empty state
/// instead of fabricated charts.
library;

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../stats/event_log.dart';
import '../../stats/metrics.dart';
import '../backend_bridge.dart';
import '../ui_models.dart';
import '../widgets/boards.dart';

/// Statistics dashboards with real filters and tap-to-inspect notes.
class StatsScreen extends ConsumerStatefulWidget {
  /// Creates the stats screen.
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  /// Agent filter (`null` = all).
  String? _agentId;

  /// Game-mode filter (`null` = all; values are the metrics vocabulary
  /// `'standard'` / `'chaotic'`).
  String? _mode;

  /// Tapped outcome slice label.
  String _outcomeNote = 'Tap a slice to inspect.';

  /// Tapped error-bar label.
  String _errorNote = 'Tap a bar to inspect.';

  /// Tapped latency-bucket label.
  String _latencyNote = 'Tap a bucket to inspect.';

  /// Tapped quality-bar label.
  String _qualityNote = 'Tap a bar to inspect.';

  /// Whether [record] passes the current agent/mode filters.
  bool _passes(GameEventRecord record) {
    final payload = record.payloadJson;
    if (_agentId != null && payload['agentId'] != _agentId) return false;
    if (_mode != null && payload['mode'] != _mode) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // Watched (not read inside the ListenableBuilder) so an agent rename
    // re-renders the filter labels.
    final names = ref.watch(
      agentListProvider.select(
        (s) => <String, String>{for (final a in s.agents) a.id: a.name},
      ),
    );
    String nameOf(String id) => names[id] ?? id;
    // Per-scope stores (§13 telemetry isolation); read once per build so the
    // ListenableBuilder below subscribes to their change notifiers.
    final statsLog = ref.read(statsLogProvider);
    final qualityLog = ref.read(qualityLogProvider);
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        statsLog.changes,
        qualityLog.changes,
      ]),
      builder: (context, _) {
        final all = statsLog.store.listAll();
        final filtered = <GameEventRecord>[
          for (final r in all)
            if (_passes(r)) r,
        ];
        final turns = <GameEventRecord>[
          for (final r in filtered)
            if (r.payloadJson['countAsTurn'] != false) r,
        ];
        final results = <GameEventRecord>[
          for (final r in filtered)
            if (r.payloadJson['result'] is String) r,
        ];
        final latencies = <int>[
          for (final r in turns)
            if (r.payloadJson['latencyMs'] is num)
              (r.payloadJson['latencyMs']! as num).toInt(),
        ];
        final marks = qualityLog.marks;
        final hasData = all.isNotEmpty || marks.isNotEmpty;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildFilters(all, turns.length, nameOf),
              const SizedBox(height: 12),
              if (!hasData)
                _buildEmptyState()
              else ...<Widget>[
                _buildMetricsCard(filtered, nameOf),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final w = constraints.maxWidth.isFinite
                        ? constraints.maxWidth
                        : 800;
                    final cols = w >= 700 ? 2 : 1;
                    return GridView.count(
                      crossAxisCount: cols,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.15,
                      children: <Widget>[
                        _chartCard(
                          'Outcomes',
                          _outcomeNote,
                          _buildOutcomePie(results),
                        ),
                        _chartCard(
                          'Error categories',
                          _errorNote,
                          _buildErrorBar(turns, nameOf),
                        ),
                        _chartCard(
                          'Latency histogram (ms)',
                          _latencyNote,
                          _buildLatencyBar(latencies),
                        ),
                        _chartCard(
                          'Quality distribution',
                          _qualityNote,
                          _buildQualityBar(marks),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Honest empty state: nothing has been played or reviewed yet.
  Widget _buildEmptyState() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.info_outline),
                const SizedBox(width: 8),
                Text(
                  'No stats yet',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Run a watch match, play a game, or start an arena '
              'tournament — stats fill in here as games finish (turns, '
              'errors, latency and per-agent aggregates). Then run the '
              'review screen to fill the quality distribution.',
            ),
          ],
        ),
      ),
    );
  }

  /// Agent/mode filter dropdowns + reset + visible-row count.
  Widget _buildFilters(
    List<GameEventRecord> all,
    int turnCount,
    String Function(String) nameOf,
  ) {
    final agentIds = <String>{
      for (final r in all)
        if (r.payloadJson['agentId'] is String) r.payloadJson['agentId']! as String,
    }.toList()
      ..sort();
    final modes = <String>{
      for (final r in all)
        if (r.payloadJson['mode'] is String) r.payloadJson['mode']! as String,
    }.toList()
      ..sort();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        DropdownMenu<String?>(
          key: ValueKey<String>('agent-${_agentId ?? 'all'}'),
          label: const Text('Agent'),
          initialSelection: _agentId,
          onSelected: (v) => setState(() => _agentId = v),
          dropdownMenuEntries: <DropdownMenuEntry<String?>>[
            const DropdownMenuEntry(value: null, label: 'All agents'),
            for (final id in agentIds)
              DropdownMenuEntry(
                value: id,
                label: nameOf(id),
              ),
          ],
        ),
        DropdownMenu<String?>(
          key: ValueKey<String>('mode-${_mode ?? 'all'}'),
          label: const Text('Variant'),
          initialSelection: _mode,
          onSelected: (v) => setState(() => _mode = v),
          dropdownMenuEntries: <DropdownMenuEntry<String?>>[
            const DropdownMenuEntry(value: null, label: 'All variants'),
            for (final m in modes) DropdownMenuEntry(value: m, label: m),
          ],
        ),
        if (_agentId != null || _mode != null)
          TextButton.icon(
            onPressed: () => setState(() {
              _agentId = null;
              _mode = null;
            }),
            icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
            label: const Text('Reset filters'),
          ),
        Text(
          '$turnCount turn${turnCount == 1 ? '' : 's'} match the filters',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  /// Per-agent table straight from [AgentMetrics.compute].
  ///
  /// Rates follow the denominators documented on [AgentMetrics] (flags
  /// per turn, not per game); cost shows `n/a` when pricing is unknown.
  Widget _buildMetricsCard(
    List<GameEventRecord> filtered,
    String Function(String) nameOf,
  ) {
    final theme = Theme.of(context);
    final metrics = AgentMetrics.compute(filtered);
    final rows = metrics.entries.toList()
      ..sort((a, b) {
        final byTurns = b.value.turns.compareTo(a.value.turns);
        if (byTurns != 0) return byTurns;
        return a.key.compareTo(b.key);
      });
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Agent metrics', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              Text(
                'No turn records match the filters.',
                style: theme.textTheme.bodySmall,
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingTextStyle: theme.textTheme.labelSmall,
                  dataTextStyle: theme.textTheme.bodySmall,
                  columns: const <DataColumn>[
                    DataColumn(label: Text('Agent')),
                    DataColumn(label: Text('Turns'), numeric: true),
                    DataColumn(label: Text('Legal'), numeric: true),
                    DataColumn(label: Text('Fallback'), numeric: true),
                    DataColumn(label: Text('Avg ms'), numeric: true),
                    DataColumn(label: Text('p95 ms'), numeric: true),
                    DataColumn(label: Text('W-L-D'), numeric: true),
                    DataColumn(label: Text('Est. cost')),
                  ],
                  rows: <DataRow>[
                    for (final row in rows)
                      DataRow(
                        cells: <DataCell>[
                          DataCell(Text(nameOf(row.key))),
                          DataCell(Text('${row.value.turns}')),
                          DataCell(
                            Text(_percent(row.value.legalRate)),
                          ),
                          DataCell(
                            Text(_percent(row.value.fallbackRate)),
                          ),
                          DataCell(
                            Text(row.value.avgLatencyMs.toStringAsFixed(0)),
                          ),
                          DataCell(Text(row.value.p95.toStringAsFixed(0))),
                          DataCell(
                            Text(
                              '${row.value.wins}-${row.value.losses}-'
                              '${row.value.draws}',
                            ),
                          ),
                          DataCell(
                            Text(
                              row.value.pricingKnown
                                  ? '\$${row.value.estCostUsd.toStringAsFixed(4)}'
                                  : 'n/a',
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Text(
              'Rates are per-turn flags (see AgentMetrics docs); result '
              'markers count one row per seat — both seats appear without '
              'an agent filter.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// `0.42` → `42%`.
  String _percent(double rate) => '${(rate * 100).toStringAsFixed(0)}%';

  /// Card wrapper: title + chart + tap-to-inspect note.
  Widget _chartCard(String title, String note, Widget chart) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: theme.textTheme.titleSmall),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: chart,
              ),
            ),
            Text(
              note,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Outcome pie over `result` markers (`win`/`loss`/`draw`).
  Widget _buildOutcomePie(List<GameEventRecord> results) {
    final cs = Theme.of(context).colorScheme;
    final wins =
        results.where((r) => r.payloadJson['result'] == 'win').length;
    final draws =
        results.where((r) => r.payloadJson['result'] == 'draw').length;
    final losses =
        results.where((r) => r.payloadJson['result'] == 'loss').length;
    final total = wins + draws + losses;
    if (total == 0) {
      return const Center(child: Text('No finished games to chart.'));
    }
    final sections = <PieChartSectionData>[
      PieChartSectionData(
        value: wins.toDouble(),
        title: 'W $wins',
        color: cs.primary,
        radius: 56,
        titleStyle: TextStyle(
          color: cs.onPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      PieChartSectionData(
        value: draws.toDouble(),
        title: 'D $draws',
        color: cs.outline,
        radius: 56,
        titleStyle: TextStyle(
          color: cs.surface,
          fontWeight: FontWeight.w700,
        ),
      ),
      PieChartSectionData(
        value: losses.toDouble(),
        title: 'L $losses',
        color: cs.error,
        radius: 56,
        titleStyle: TextStyle(
          color: cs.onError,
          fontWeight: FontWeight.w700,
        ),
      ),
    ];
    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 30,
        sections: sections,
        pieTouchData: PieTouchData(
          enabled: true,
          touchCallback: (event, response) {
            if (event is! FlTapUpEvent) return;
            final i = response?.touchedSection?.touchedSectionIndex ?? -1;
            if (i < 0) return;
            const names = <String>['wins', 'draws', 'losses'];
            setState(() {
              final c = <int>[wins, draws, losses][i];
              _outcomeNote = '${names[i]}: $c of $total seat results '
                  '(${(c * 100 / total).toStringAsFixed(0)}%).';
            });
          },
        ),
      ),
    );
  }

  /// Shared bottom-axis titles builder for the bar charts.
  Widget _bottomTitle(double value, TitleMeta meta, List<String> labels) {
    final i = value.toInt();
    final text = (i >= 0 && i < labels.length) ? labels[i] : '';
    return SideTitleWidget(
      axisSide: meta.axisSide,
      child: Text(text, style: const TextStyle(fontSize: 10)),
    );
  }

  /// Bar-chart shell shared by error/latency/quality charts.
  Widget _barShell({
    required List<double> values,
    required List<String> labels,
    required Color Function(int i) colorFor,
    required void Function(int i) onTap,
  }) {
    // Explicit axis scale: fl_chart's auto scale can emit both an interval
    // tick (e.g. 120) and an exact-max tick (121) at the same spot, which
    // renders as overlapping text. A "nice" step ≤ max/5 keeps every tick
    // a clean multiple and the tallest bar near the top.
    final maxValue = values.fold<double>(0, math.max);
    final step = _niceStep(maxValue / 5);
    final ticks = (maxValue / step).ceil();
    final maxY = step * (ticks <= 0 ? 1 : ticks);
    return BarChart(
      BarChartData(
        maxY: maxY,
        barTouchData: BarTouchData(
          enabled: true,
          touchCallback: (event, response) {
            if (event is! FlTapUpEvent) return;
            final i = response?.spot?.touchedBarGroupIndex ?? -1;
            if (i < 0 || i >= values.length) return;
            onTap(i);
          },
        ),
        titlesData: FlTitlesData(
          show: true,
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              // Wide enough for three-digit counts (e.g. `124`); the
              // default 28px reserve wraps such labels onto two lines.
              reservedSize: 40,
              // Explicit label interval: without it fl_chart picks its
              // own step (e.g. 10) AND draws a separate maxY label, which
              // renders as overlapping text at the top of the axis.
              interval: step,
              getTitlesWidget: (value, meta) => Text(
                value.toInt().toString(),
                maxLines: 1,
                softWrap: false,
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, meta) => _bottomTitle(v, meta, labels),
            ),
          ),
        ),
        gridData: FlGridData(show: true, horizontalInterval: step),
        borderData: FlBorderData(show: false),
        barGroups: <BarChartGroupData>[
          for (var i = 0; i < values.length; i++)
            BarChartGroupData(
              x: i,
              barRods: <BarChartRodData>[
                BarChartRodData(
                  toY: values[i],
                  color: colorFor(i),
                  width: 22,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Rounds [v] up to the nearest `{1, 2, 2.5, 5, 10} × 10^k` step.
  ///
  /// Used for the bar-chart Y scale so gridline labels are always short,
  /// whole-looking numbers (0/25/50/… or 0/20/40/…) with at most ~6 ticks.
  double _niceStep(double v) {
    if (v <= 0 || !v.isFinite) return 1;
    final magnitude =
        math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    final n = v / magnitude;
    final nice = n <= 1
        ? 1.0
        : n <= 2
            ? 2.0
            : n <= 2.5
                ? 2.5
                : n <= 5
                    ? 5.0
                    : 10.0;
    return nice * magnitude;
  }

  /// Error-category bars via [statsErrorCategory]; tap → count + example.
  Widget _buildErrorBar(
    List<GameEventRecord> turns,
    String Function(String) nameOf,
  ) {
    const cats = <String>['none', 'illegal', 'timeout', 'parse', 'engine'];
    final counts = <double>[
      for (final c in cats)
        turns.where((r) => statsErrorCategory(r) == c).length.toDouble(),
    ];
    return _barShell(
      values: counts,
      labels: cats,
      colorFor: (i) =>
          i == 0 ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error,
      onTap: (i) => setState(() {
        final examples = turns.where((r) => statsErrorCategory(r) == cats[i]);
        final example = examples.isEmpty ? null : examples.first;
        final id = example?.payloadJson['agentId'];
        final who = id is String ? nameOf(id) : '—';
        _errorNote = '${cats[i]}: ${counts[i].toInt()} turns'
            '${example == null ? '.' : ' (e.g. $who · ${example.gameId}).'}';
      }),
    );
  }

  /// Latency histogram buckets; tap → bucket range + count.
  Widget _buildLatencyBar(List<int> latencies) {
    const labels = <String>['<500', '500-1k', '1k-2k', '>2k'];
    final counts = List<double>.filled(4, 0);
    for (final ms in latencies) {
      counts[ms < 500 ? 0 : (ms < 1000 ? 1 : (ms < 2000 ? 2 : 3))] += 1;
    }
    if (latencies.isEmpty) {
      return const Center(child: Text('No latency samples yet.'));
    }
    return _barShell(
      values: counts,
      labels: labels,
      colorFor: (_) => Theme.of(context).colorScheme.tertiary,
      onTap: (i) => setState(() {
        _latencyNote = '${labels[i]} ms: ${counts[i].toInt()} '
            'turn${counts[i] == 1 ? '' : 's'} of ${latencies.length} '
            'sampled.';
      }),
    );
  }

  /// Quality-mark distribution from [QualityLog.marks] (review output).
  Widget _buildQualityBar(List<String> marks) {
    const markOrder = <String>['!!', '!', '!?', 'ok', '?', '??'];
    final counts = <double>[
      for (final m in markOrder)
        marks.where((mark) => mark == m).length.toDouble(),
    ];
    if (marks.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(8),
          child: Text(
            'No review data yet — open the review screen to classify a '
            'game.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return _barShell(
      values: counts,
      labels: markOrder,
      colorFor: (i) => qualityColorFor(
        markOrder[i],
        brightness: Theme.of(context).brightness,
      ).withValues(alpha: 0.85),
      onTap: (i) => setState(() {
        _qualityNote = '${markOrder[i]}: ${counts[i].toInt()} plies of '
            '${marks.length} reviewed (filters do not apply here).';
      }),
    );
  }
}
