/// Lossless replay for a chaotic-variant game.
///
/// Replay is deliberately engine-free: every board comes from the recorded
/// [VariantGameRecord] chain, so stepping works even when Stockfish/network is
/// unavailable. Review (Stockfish evaluation, move badges) is layered on top
/// separately.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/registry.dart';
import '../../chess/square.dart';
import '../../review/variant_review.dart';
import '../../variant/variant_replay.dart';
import '../backend_bridge.dart';
import '../widgets/activity_panel.dart';
import '../widgets/board_motion.dart';
import '../widgets/boards.dart';
import '../widgets/chessboard.dart';

/// Step-through replay for one [VariantGameRecord].
class VariantReplayScreen extends ConsumerStatefulWidget {
  /// Creates a replay screen.
  const VariantReplayScreen({super.key, required this.record});

  /// The recorded game.
  final VariantGameRecord record;

  @override
  ConsumerState<VariantReplayScreen> createState() =>
      _VariantReplayScreenState();
}

class _VariantReplayScreenState extends ConsumerState<VariantReplayScreen> {
  /// 0 = initial position; `i` = after ply `i-1`.
  int _ply = 0;

  /// Review run state (lazy: no Stockfish until the button is pressed).
  VariantReviewReport? _report;
  ReviewEvaluatorHandle? _reviewHandle;
  bool _reviewLoading = false;
  String? _reviewError;
  int _reviewToken = 0;

  /// §10.2 seam — injected for tests; production defaults to [resolveReviewEvaluator].
  Future<ReviewEvaluatorHandle> Function() _evalFactory = resolveReviewEvaluator;

  VariantGameRecord get _record => widget.record;

  @override
  void initState() {
    super.initState();
    _evalFactory = ref.read(reviewEvaluatorFactoryProvider);
  }

  @override
  void dispose() {
    _reviewToken++;
    final handle = _reviewHandle;
    _reviewHandle = null;
    if (handle != null) {
      unawaited(handle.dispose());
    }
    super.dispose();
  }

  Future<void> _runReview() async {
    if (_reviewLoading) return;
    final token = ++_reviewToken;
    setState(() {
      _reviewLoading = true;
      _reviewError = null;
    });
    final previous = _reviewHandle;
    _reviewHandle = null;
    if (previous != null) await previous.dispose();
    try {
      final handle = await _evalFactory();
      if (!mounted || token != _reviewToken) {
        await handle.dispose();
        return;
      }
      _reviewHandle = handle;
      final report =
          await VariantReviewService(evaluator: handle.evaluator)
              .reviewGame(_record);
      if (!mounted || token != _reviewToken) return;
      setState(() {
        _report = report;
        _reviewLoading = false;
      });
    } catch (e) {
      if (!mounted || token != _reviewToken) return;
      setState(() {
        _reviewError = '$e';
        _reviewLoading = false;
      });
    }
  }

  void _seek(int ply) {
    final clamped = ply.clamp(0, _record.plies.length);
    if (clamped == _ply) return;
    setState(() => _ply = clamped);
  }

  @override
  Widget build(BuildContext context) {
    final boardTheme = ref.watch(
      themeRegistryProvider.select((r) => r.boardTheme),
    );
    final pieceTheme = ref.watch(
      themeRegistryProvider.select((r) => r.pieceTheme),
    );
    final board = _record.boardAt(_ply);
    final current = _ply == 0 ? null : _record.plies[_ply - 1];
    final reviewed = _ply > 0 && _report != null && _ply <= _report!.moves.length
        ? _report!.moves[_ply - 1]
        : null;
    final chainErrors = _record.validateChain();

    final boardPane = Column(
      children: <Widget>[
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: Chessboard(
                squares: squaresOfVariantBoard(board),
                boardTheme: boardTheme,
                pieceTheme: pieceTheme,
                showCoordinates: true,
                interactive: false,
                lastFrom: current != null && current.wasLegal
                    ? current.attempt.fromSquareName
                    : null,
                lastTo: current != null && current.wasLegal
                    ? current.attempt.toSquareName
                    : null,
                // Forward steps through a legal ply animate via the §15.2
                // motion layer; the board derives capture/en-passant/castle
                // from its before→after snapshot diff, so the bare from/to
                // pair is a complete motion value. Illegal plies and backward
                // seeks snap (no flight: the origin piece is absent from the
                // old snapshot).
                motion: current != null && current.wasLegal
                    ? BoardMove(
                        from: Square.fromName(current.attempt.fromSquareName),
                        to: Square.fromName(current.attempt.toSquareName),
                      )
                    : null,
              ),
            ),
          ),
        ),
        _buildControls(),
      ],
    );

    final panel = ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        _buildHeader(),
        const SizedBox(height: 8),
        _buildReviewCard(),
        if (chainErrors.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          _buildChainBanner(chainErrors),
        ],
        const SizedBox(height: 8),
        _buildMoveList(),
        const SizedBox(height: 8),
        if (current == null)
          const Card(
            child: ListTile(
              leading: Icon(Icons.flag_outlined),
              title: Text('Initial position'),
              subtitle: Text('Step forward to replay the first attempt.'),
            ),
          )
        else ...<Widget>[
          _buildAttemptCard(current),
          const SizedBox(height: 8),
          _buildInterpretationCard(current, reviewed),
          const SizedBox(height: 8),
          _buildEventsCard(current),
        ],
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chaotic replay'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: Text(
                'Ply $_ply / ${_record.plies.length}',
                key: const ValueKey<String>('variant-ply-label'),
              ),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 900) {
            return Row(
              children: <Widget>[
                Expanded(child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: boardPane,
                )),
                SizedBox(
                  width: 440,
                  child: panel,
                ),
              ],
            );
          }
          return Column(
            children: <Widget>[
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: boardPane,
                ),
              ),
              Expanded(
                flex: 2,
                child: panel,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '${_record.whiteLabel} vs ${_record.blackLabel}',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '${_record.outcome}'
              '${_record.reason.isEmpty ? '' : ' · ${_record.reason}'}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              'seed ${_record.seed} · ${_record.plies.length} plies'
              '${_record.tournamentId == null ? '' : ' · ${_record.tournamentId}'}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChainBanner(List<String> errors) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Replay integrity warnings',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 4),
            for (final error in errors)
              SelectableText(
                '- $error',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
    final last = _record.plies.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          IconButton(
            key: const ValueKey<String>('variant-first'),
            tooltip: 'First position',
            onPressed: _ply == 0 ? null : () => _seek(0),
            icon: const Icon(Icons.first_page),
          ),
          IconButton(
            key: const ValueKey<String>('variant-prev'),
            tooltip: 'Previous ply',
            onPressed: _ply == 0 ? null : () => _seek(_ply - 1),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Slider(
              key: const ValueKey<String>('variant-ply-slider'),
              value: _ply.toDouble(),
              min: 0,
              max: last.toDouble(),
              divisions: last == 0 ? null : last,
              label: 'Ply $_ply',
              onChanged: last == 0
                  ? null
                  : (value) => _seek(value.round()),
            ),
          ),
          IconButton(
            key: const ValueKey<String>('variant-next'),
            tooltip: 'Next ply',
            onPressed: _ply >= last ? null : () => _seek(_ply + 1),
            icon: const Icon(Icons.chevron_right),
          ),
          IconButton(
            key: const ValueKey<String>('variant-last'),
            tooltip: 'Final position',
            onPressed: _ply >= last ? null : () => _seek(last),
            icon: const Icon(Icons.last_page),
          ),
        ],
      ),
    );
  }

  Widget _buildMoveList() {
    final report = _report;
    return MoveList(
      moves: <String>[for (final ply in _record.plies) ply.attempt.uci],
      currentIndex: _ply == 0 ? -1 : _ply - 1,
      qualityMarks: report == null
          ? const <int, String>{}
          : <int, String>{
              for (var i = 0; i < report.moves.length; i++)
                i: qualityMarkFor(report.moves[i].assessment.quality),
            },
      errorPlies: <int>{
        for (var i = 0; i < _record.plies.length; i++)
          if (_record.plies[i].fallback) i,
      },
      onTapMove: (index) => _seek(index + 1),
      maxHeight: 180,
    );
  }

  Widget _buildReviewCard() {
    final theme = Theme.of(context);
    final report = _report;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.analytics_outlined, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Engine review',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (report == null)
                  FilledButton.icon(
                    key: const ValueKey<String>('variant-analyze'),
                    onPressed: _reviewLoading ? null : _runReview,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(_reviewLoading ? 'Analyzing…' : 'Analyze'),
                  )
                else
                  TextButton.icon(
                    onPressed: _reviewLoading ? null : _runReview,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Re-analyze'),
                  ),
              ],
            ),
            if (_reviewLoading) ...<Widget>[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
              const SizedBox(height: 4),
              Text(
                'Evaluating projected positions…',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (_reviewError != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                _reviewError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            if (report != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                'Source: ${report.source}',
                style: theme.textTheme.bodySmall,
              ),
              if (report.source == 'variant-heuristic' ||
                  report.source == 'heuristic')
                Text(
                  'Heuristic review — not Stockfish output.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                )
              else if (report.source == 'variant-rule')
                Text(
                  'Terminal positions scored by variant rules (no engine call).',
                  style: theme.textTheme.bodySmall,
                )
              else if (report.source == 'mixed')
                Text(
                  'Mixed sources: Stockfish projections plus variant '
                  'rules/heuristics (see per-ply source).',
                  style: theme.textTheme.bodySmall,
                ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: <Widget>[
                  for (final entry in report.qualityCounts.entries)
                    StatChip(
                      label: entry.key,
                      value: '${entry.value}',
                      icon: Icons.insights_outlined,
                    ),
                  if (report.whiteAccuracy != null)
                    StatChip(
                      label: 'White acc',
                      value: '${report.whiteAccuracy!.toStringAsFixed(1)}%',
                      icon: Icons.percent,
                    ),
                  if (report.blackAccuracy != null)
                    StatChip(
                      label: 'Black acc',
                      value: '${report.blackAccuracy!.toStringAsFixed(1)}%',
                      icon: Icons.percent,
                    ),
                ],
              ),
              if (report.warnings.isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                for (final warning in report.warnings)
                  Text('- $warning', style: theme.textTheme.bodySmall),
              ],
              const SizedBox(height: 6),
              for (var i = 0; i < report.moves.length; i++)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 12,
                    child: Text(
                      qualityMarkFor(report.moves[i].assessment.quality),
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                  title: Text(
                    '${i + 1}. ${_record.plies[i].attempt.uci} · '
                    '${report.moves[i].assessment.quality.name}',
                  ),
                  subtitle: Text(_reviewSubtitle(report.moves[i])),
                  onTap: () => _seek(i + 1),
                ),
            ] else if (!_reviewLoading) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                'Replay works without an engine. Analyze evaluates each ply '
                '(before vs after) from the mover\'s perspective.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _reviewSubtitle(VariantReviewedPly move) {
    final parts = <String>[
      if (move.lossCp == null) 'no score' else 'loss ${move.lossCp} cp',
      if (move.assessment.tags.isNotEmpty)
        move.assessment.tags.join(', '),
    ];
    return parts.join(' · ');
  }

  Widget _buildAttemptCard(VariantPlyRecord ply) {
    final theme = Theme.of(context);
    final raw = _prettyRaw(ply.attempt.rawToolCallJson, ply.attempt.rawToolArgsJson);
    return Card(
      child: ExpansionTile(
        leading: Icon(
          ply.fallback ? Icons.warning_amber_outlined : Icons.psychology_outlined,
        ),
        title: Text('Attempt ${ply.attempt.uci}'),
        subtitle: Text(
          '${ply.mover == 'w' ? 'White' : 'Black'}'
          ' · ${ply.attempt.source.name}'
          '${ply.attempt.phrase.isEmpty ? '' : ' · "${ply.attempt.phrase}"'}',
          style: theme.textTheme.bodySmall,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              'from ${ply.attempt.fromSquareName} → '
              'to ${ply.attempt.toSquareName}'
              '${ply.attempt.promotion == null ? '' : ' · promotion ${ply.attempt.promotion}'}',
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Raw tool call', style: theme.textTheme.labelMedium),
          ),
          const SizedBox(height: 4),
          SelectableText(
            raw,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInterpretationCard(
    VariantPlyRecord ply,
    VariantReviewedPly? reviewed,
  ) {
    final theme = Theme.of(context);
    final selected = ply.selected;
    final facts = ply.kingFacts;
    final r = reviewed;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  ply.wasLegal ? Icons.check_circle_outline : Icons.auto_fix_high,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${selected.strategyId} · ${ply.interpretationKind.name}',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(selected.title, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 2),
            Text(selected.description, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: <Widget>[
                StatChip(
                  label: 'Selection heuristic',
                  value: '${selected.selectionScoreCp} cp',
                  icon: Icons.calculate_outlined,
                ),
                StatChip(
                  label: 'Standard',
                  value: ply.wasLegal ? 'legal' : 'interpreted',
                  icon: Icons.rule_outlined,
                ),
                StatChip(
                  label: 'Policy',
                  value: ply.policy,
                  icon: Icons.tune_outlined,
                ),
                if (r != null)
                  StatChip(
                    label: 'Review',
                    value: r.assessment.quality.name,
                    icon: Icons.analytics_outlined,
                  ),
                if (r != null)
                  StatChip(
                    label: 'Loss',
                    value: r.lossCp == null ? '—' : '${r.lossCp} cp',
                    icon: Icons.trending_down,
                  ),
              ],
            ),
            if (r != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                'Eval: ${r.beforeCp ?? '—'} → ${r.afterCp ?? '—'} cp '
                '(${r.afterScore.source})',
                style: theme.textTheme.bodySmall,
              ),
              Text(
                r.assessment.rationale,
                style: theme.textTheme.bodySmall,
              ),
              if (r.assessment.tags.isNotEmpty)
                Text(
                  'Tags: ${r.assessment.tags.join(', ')}',
                  style: theme.textTheme.bodySmall,
                ),
              if (r.annotations.isNotEmpty)
                Text(
                  'Projection: ${r.annotations.join('; ')}',
                  style: theme.textTheme.bodySmall,
                ),
              if (r.lowConfidence)
                Text(
                  'Low-confidence evaluation (${r.afterScore.source}).',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
            ],
            if (!ply.wasLegal && ply.standardDetail.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Standard legality: ${ply.standardDetail}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Kings: W ${facts.whiteKingsBefore}→${facts.whiteKingsAfter}, '
              'B ${facts.blackKingsBefore}→${facts.blackKingsAfter}',
              style: theme.textTheme.bodySmall,
            ),
            if (facts.whiteKingsLost.isNotEmpty)
              Text(
                'White kings lost: ${facts.whiteKingsLost.join(', ')}',
                style: theme.textTheme.bodySmall,
              ),
            if (facts.blackKingsLost.isNotEmpty)
              Text(
                'Black kings lost: ${facts.blackKingsLost.join(', ')}',
                style: theme.textTheme.bodySmall,
              ),
            if (facts.capturesEnemyKing)
              Text(
                'Enemy king captured',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (ply.latencyMs != null || ply.inputTokens != null)
              Text(
                <String>[
                  if (ply.latencyMs != null) '${ply.latencyMs} ms',
                  if (ply.inputTokens != null) '${ply.inputTokens} in',
                  if (ply.outputTokens != null) '${ply.outputTokens} out',
                ].join(' · '),
                style: theme.textTheme.bodySmall,
              ),
            if (ply.turnFailureKind != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                'Turn failure: ${ply.turnFailureKind}'
                '${ply.turnFailureMessage == null ? '' : ' — ${ply.turnFailureMessage}'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEventsCard(VariantPlyRecord ply) {
    final theme = Theme.of(context);
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.receipt_long_outlined),
        title: Text('Pipeline events (${ply.events.length})'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: <Widget>[
          for (final event in ply.events)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '- $event',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _prettyRaw(
    Map<String, Object?>? json,
    String? raw,
  ) {
    if (json != null) {
      try {
        return redactSecrets(
          const JsonEncoder.withIndent('  ').convert(json),
        );
      } catch (_) {
        // Fall through to the raw string.
      }
    }
    if (raw != null && raw.isNotEmpty) return raw;
    return '(no raw tool call captured)';
  }
}
