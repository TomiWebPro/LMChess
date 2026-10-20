/// [ReviewScreen]: post-game analysis over real review records.
///
/// Games come from [ReviewLog] (written by play/watch and standard arena
/// games); a picker selects among the latest 20, and the screen re-runs
/// its review whenever the log grows. The pipeline is real:
/// [resolveReviewEvaluator] resolves embedded Stockfish (with an honest
/// [HeuristicEvaluator] fallback + reason on platforms that cannot spawn
/// it), [reviewInputsFor] converts the stored game into per-move inputs,
/// and [WintrReviewService.reviewGame] produces the report — no canned
/// plies or evals.
///
/// Every dependent view follows the replay cursor (`_ply` = applied plies,
/// 0 = start): quality chip + tier + White-relative evals for the last
/// applied move, the clamped eval graph (mate anchors saturate), before/
/// after boards with the last-move highlight, the move record (UCI/SAN,
/// redacted agent phrase, fallback flag, [classify] rationale), accuracy +
/// summary card, key moments (tap jumps the cursor) and a clickable
/// [MoveList] with quality marks. The resolved evaluation **source** and
/// any fallback reason are always rendered next to the scores — heuristic
/// estimates are never presented as engine output. Each review run owns
/// its evaluator handle and disposes it (Stockfish process included) when
/// replaced or the screen goes away.
///
/// **Wiring point**: [ReviewGame] records UCI/SAN/phrase/fallback only —
/// raw tool-call JSON per ply is not stored, so this screen has no "raw
/// call" card; add the JSON trace to the recorder when capture lands.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../review/engine_adapter.dart' show EngineSources;
import '../../review/quality.dart' show MoveQuality;
import '../../review/wintr_review.dart';
import '../../theme/registry.dart';
import '../backend_bridge.dart';
import '../widgets/activity_panel.dart' show redactSecrets;
import '../widgets/boards.dart';
import '../widgets/chessboard.dart';
import '../widgets/tab_visibility.dart';
import 'variant_replay_screen.dart';

/// Post-game review: replay, evals, move record, commentary, accuracy.
class ReviewScreen extends ConsumerStatefulWidget {
  /// Creates the review screen.
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  /// Currently selected record id (`ReviewGame.id`).
  String? _gameId;

  /// Snapshot of the selected record (kept so later caps/edits of the log
  /// cannot mutate the game under review).
  ReviewGame? _game;

  /// FEN history for [_game] (via [fensFor]); rebuilt defensively.
  List<String> _fens = const <String>[];

  /// Replay cursor: number of applied plies (0 = start position).
  int _ply = 0;

  /// Report for the last completed run.
  ReviewReport? _report;

  /// Resolved evaluator for the displayed report (disposed on replace).
  ReviewEvaluatorHandle? _handle;

  /// Failure text of the last run, if any.
  String? _error;

  /// Evaluator provenance for the displayed report. Kept separately so the
  /// banner/graph stay honest after [_suspend] disposes the handle while the
  /// tab is hidden.
  String? _reportSource;
  String? _reportFallbackReason;

  /// Whether a review run is in flight.
  bool _loading = false;

  /// Run token: invalidates stale async completions.
  int _runToken = 0;

  /// Whether the shell's Review tab is currently visible.
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    ReviewLog.changes.addListener(_onLogChanged);
    // Selection and the review run are deferred to [didChangeDependencies]:
    // the shell builds every tab eagerly inside its IndexedStack, and this
    // screen must not spawn Stockfish while its tab is hidden.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TabVisibility.of(context);
    _visible = visible;
    if (!visible) {
      _suspend();
      return;
    }
    _ensureSelected(run: true);
  }

  @override
  void dispose() {
    _runToken++;
    ReviewLog.changes.removeListener(_onLogChanged);
    final handle = _handle;
    _handle = null;
    if (handle != null) unawaited(handle.dispose());
    super.dispose();
  }

  /// Selects the newest record when none/stale is selected; with [run],
  /// starts a review when the current selection has no report yet.
  void _ensureSelected({required bool run}) {
    final games = ReviewLog.games;
    if (games.isEmpty) {
      if (_gameId != null || _game != null) {
        setState(() {
          _game = null;
          _gameId = null;
          _fens = const <String>[];
          _report = null;
          _error = null;
          _reportSource = null;
          _reportFallbackReason = null;
        });
      }
      return;
    }
    final stillListed = _gameId != null && games.any((g) => g.id == _gameId);
    if (!stillListed) {
      _selectGame(games.first, run: run);
    } else if (run && _report == null && _error == null && !_loading) {
      _runReview();
    }
  }

  /// Stops in-flight review work and releases the evaluator (Stockfish process
  /// included) while this tab is hidden.
  void _suspend() {
    _runToken++; // Invalidate a completion that is still in flight.
    final handle = _handle;
    _handle = null;
    if (handle != null) unawaited(handle.dispose());
    if (_loading) {
      setState(() => _loading = false);
    }
  }

  /// Re-reads the log when games are recorded: follows the newest entry
  /// while the user has not picked an older one, and drops a selection
  /// whose record fell off the capped log.
  void _onLogChanged() {
    if (!mounted) return;
    final games = ReviewLog.games;
    if (games.isEmpty) {
      _ensureSelected(run: false);
      return;
    }
    final stillListed =
        _gameId != null && games.any((g) => g.id == _gameId);
    if (!stillListed) {
      // Do not spawn a review for a hidden tab; [didChangeDependencies] will
      // run it when the tab becomes visible again.
      _selectGame(games.first, run: _visible);
    } else {
      setState(() {});
    }
  }

  /// Selects [game], resets the cursor and — when [run] — kicks off a fresh
  /// review run.
  void _selectGame(ReviewGame game, {bool run = true}) {
    setState(() {
      _game = game;
      _gameId = game.id;
      _fens = fensFor(game);
      _ply = 0;
      _report = null;
      _error = null;
      _reportSource = null;
      _reportFallbackReason = null;
    });
    if (run) _runReview();
  }

  /// Re-checks the log and keeps the selection when it still exists.
  void _refreshList() {
    final games = ReviewLog.games;
    if (games.isEmpty) {
      setState(() {
        _game = null;
        _gameId = null;
        _fens = const <String>[];
        _report = null;
        _error = null;
        _reportSource = null;
        _reportFallbackReason = null;
      });
      return;
    }
    if (_gameId == null || !games.any((g) => g.id == _gameId)) {
      _selectGame(games.first, run: _visible);
      return;
    }
    setState(() {});
  }

  /// Runs one review of the selected game with a fresh evaluator handle.
  ///
  /// The token guards against stale completions: a newer run replaces and
  /// disposes the previous handle, and an outdated run disposes its own
  /// handle without touching the current one.
  Future<void> _runReview() async {
    if (!_visible) return; // Hidden tab: no evaluator work.
    final game = _game;
    final token = ++_runToken;
    if (game == null) {
      setState(() {
        _report = null;
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _report = null;
    });
    final previous = _handle;
    _handle = null;
    if (previous != null) await previous.dispose();
    try {
      final handle = await resolveReviewEvaluator();
      if (!mounted || token != _runToken) {
        await handle.dispose();
        return;
      }
      _handle = handle;
      _reportSource = handle.resolvedSource;
      _reportFallbackReason = handle.fallbackReason;
      final service = WintrReviewService(evaluator: handle.evaluator);
      final report = await service.reviewGame(reviewInputsFor(game));
      if (!mounted || token != _runToken) return;
      QualityLog.setAll(<String>[
        for (final move in report.moves)
          qualityMarkFor(move.assessment.quality),
      ]);
      setState(() {
        _report = report;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _runToken) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final games = ReviewLog.games;
    if (games.isEmpty) return _buildEmptyState();
    final game = _game ?? games.first;
    final report = _report;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildHeader(games, game),
          const SizedBox(height: 8),
          _buildSourceBanner(),
          const SizedBox(height: 12),
          if (_loading)
            _buildLoading(game)
          else if (_error != null)
            _buildError()
          else if (report != null) ...<Widget>[
            _buildReplaySlider(game, report),
            const SizedBox(height: 8),
            _buildQualityRow(game, report),
            const SizedBox(height: 12),
            _buildEvalGraph(report),
            const SizedBox(height: 12),
            _buildBeforeAfter(game),
            const SizedBox(height: 12),
            _buildMoveRecord(game, report),
            const SizedBox(height: 12),
            _buildSummary(report),
            const SizedBox(height: 12),
            _buildMoveList(game, report),
            const SizedBox(height: 12),
            _buildKeyMoments(report),
            const SizedBox(height: 12),
            _buildVariantReplays(),
          ] else
            const Text('Press “Re-run review” to analyze this game.'),
        ],
      ),
    );
  }

  /// Empty state when nothing has been recorded yet.
  Widget _buildEmptyState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: <Widget>[
          const Icon(Icons.replay_outlined, size: 40),
          const SizedBox(height: 8),
          Text(
            'No standard games recorded yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Finish a watch match, a play game, or a standard arena '
            'tournament game — it lands here for review automatically.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _refreshList,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
          const SizedBox(height: 16),
          _buildVariantReplays(),
        ],
      ),
    );
  }

  /// Chaotic-variant replays recorded by the arena.
  ///
  /// These are engine-free and live in a separate log; they remain available
  /// even when no standard game has been recorded.
  Widget _buildVariantReplays() {
    return ListenableBuilder(
      listenable: VariantReviewLog.changes,
      builder: (context, _) {
        final games = VariantReviewLog.games;
        if (games.isEmpty) return const SizedBox.shrink();
        return Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.auto_awesome_motion_outlined),
                title: const Text('Chaotic replays'),
                subtitle: Text(
                  '${games.length} recorded · lossless board + interpretation chain',
                ),
              ),
              for (final game in games.take(5))
                ListTile(
                  leading: const Icon(Icons.replay_outlined),
                  title: Text('${game.whiteLabel} vs ${game.blackLabel}'),
                  subtitle: Text(
                    '${game.outcome}'
                    '${game.reason.isEmpty ? '' : ' · ${game.reason}'}'
                    ' · ${game.plies.length} plies',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => VariantReplayScreen(record: game),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Game picker + refresh / re-run controls.
  Widget _buildHeader(List<ReviewGame> games, ReviewGame game) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                DropdownMenu<String>(
                  key: ValueKey<String>('game-${game.id}'),
                  label: const Text('Game'),
                  initialSelection: game.id,
                  onSelected: (id) {
                    if (id == null || id == game.id) return;
                    _selectGame(
                      games.firstWhere((g) => g.id == id),
                    );
                  },
                  dropdownMenuEntries: <DropdownMenuEntry<String>>[
                    for (final g in games)
                      DropdownMenuEntry(
                        value: g.id,
                        label: '${g.whiteLabel} vs ${g.blackLabel} '
                            '· ${g.mode}',
                      ),
                  ],
                ),
                FilledButton.tonalIcon(
                  onPressed: _loading ? null : _runReview,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Re-run review'),
                ),
                TextButton.icon(
                  onPressed: _refreshList,
                  icon: const Icon(Icons.list_alt_outlined),
                  label: const Text('Refresh list'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${games.length} recorded game${games.length == 1 ? '' : 's'} '
              '(latest first, capped at 20) · mode: ${game.mode} · '
              '${game.ucis.length} plies',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Always-visible evaluation provenance line (source honesty).
  Widget _buildSourceBanner() {
    final theme = Theme.of(context);
    final handle = _handle;
    final source = handle?.resolvedSource ?? _reportSource;
    final reason = handle?.fallbackReason ?? _reportFallbackReason ?? '';
    final isStockfish = source == EngineSources.stockfishUci;
    final color = isStockfish
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.tertiaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            isStockfish ? Icons.memory_outlined : Icons.functions_outlined,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Evaluation source: ${source ?? 'resolving…'}'
              '${isStockfish ? ' (embedded Stockfish via UCI)' : ''}'
              '${reason.isEmpty ? '' : '\n$reason'}',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  /// Indeterminate progress card while the review runs.
  Widget _buildLoading(ReviewGame game) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              'Reviewing ${game.ucis.length} plies — resolving the '
              'evaluator and scoring both sides of every move…',
            ),
          ],
        ),
      ),
    );
  }

  /// Failure card with retry.
  Widget _buildError() {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Review failed',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            Text(_error ?? 'Unknown error.'),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: _runReview,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  /// Replay slider + ply counter.
  Widget _buildReplaySlider(ReviewGame game, ReviewReport report) {
    final theme = Theme.of(context);
    final total = math.min(game.ucis.length, report.moves.length);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            const Icon(Icons.replay_outlined),
            Expanded(
              child: Slider(
                value: _ply.clamp(0, total).toDouble(),
                min: 0,
                max: total == 0 ? 1 : total.toDouble(),
                divisions: total == 0 ? null : total,
                label: 'Ply $_ply',
                onChanged: total == 0
                    ? null
                    : (v) => setState(() => _ply = v.round()),
              ),
            ),
            Text(
              'Ply $_ply / $total',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  /// The last applied ply's assessment, when the cursor is past the start.
  ReviewedMove? _currentMove(ReviewReport report) {
    final index = _ply - 1;
    if (index < 0 || index >= report.moves.length) return null;
    return report.moves[index];
  }

  /// SAN label for ply [index], falling back to UCI when SAN is missing.
  String _sanAt(ReviewGame game, int index) {
    if (index < 0) return '–';
    if (index < game.sans.length && game.sans[index].isNotEmpty) {
      return game.sans[index];
    }
    return index < game.ucis.length ? game.ucis[index] : '?';
  }

  /// Quality chip + tier + evals for the cursor move.
  Widget _buildQualityRow(ReviewGame game, ReviewReport report) {
    final theme = Theme.of(context);
    final move = _currentMove(report);
    if (move == null) {
      return Text(
        'Cursor at the start position — move the slider or tap a move '
        'to inspect plies.',
        style: theme.textTheme.bodySmall,
      );
    }
    final mark = qualityMarkFor(move.assessment.quality);
    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Text(
          _sanAt(game, move.moveIndex),
          style: theme.textTheme.titleLarge,
        ),
        Chip(
          avatar: Icon(
            qualityIconFor(mark),
            size: 16,
            color: qualityColorFor(mark, brightness: theme.brightness),
          ),
          label: Text('$mark · ${move.assessment.quality.name}'),
        ),
        if (move.assessment.supported)
          Text(
            'Eval ${_evalLabel(move.afterCp)} '
            '(before ${_evalLabel(move.beforeCp)})',
            style: theme.textTheme.bodyMedium,
          ),
        if (move.accuracy != null)
          Text(
            'Accuracy ${move.accuracy!.toStringAsFixed(1)}',
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }

  /// White-relative centipawn score as `+x.xx` pawns (or `?`).
  String _evalLabel(int? cp) {
    if (cp == null) return '?';
    final pawns = cp / 100.0;
    return '${pawns >= 0 ? '+' : ''}${pawns.toStringAsFixed(2)}';
  }

  /// Eval graph (White-relative pawns) synced to the replay cursor.
  Widget _buildEvalGraph(ReviewReport report) {
    final theme = Theme.of(context);
    final spots = <FlSpot>[];
    if (report.moves.isNotEmpty && report.moves.first.beforeCp != null) {
      spots.add(FlSpot(0, _pawns(report.moves.first.beforeCp!)));
    }
    for (var i = 0; i < report.moves.length; i++) {
      final cp = report.moves[i].afterCp;
      if (cp != null) spots.add(FlSpot((i + 1).toDouble(), _pawns(cp)));
    }
    if (spots.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'No supported evaluations — the resolved source cannot score '
            'these positions, so no graph is drawn.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }
    var minY = -1.0;
    var maxY = 1.0;
    for (final spot in spots) {
      minY = math.min(minY, spot.y - 0.5);
      maxY = math.max(maxY, spot.y + 0.5);
    }
    final source = _handle?.resolvedSource ?? _reportSource ?? 'unknown';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Evaluation (White-relative pawns · $source)',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 180,
              child: LineChart(
                LineChartData(
                  lineTouchData: LineTouchData(
                    enabled: true,
                    touchCallback: (event, response) {
                      if (event is! FlTapUpEvent) return;
                      final hit = response?.lineBarSpots;
                      if (hit == null || hit.isEmpty) return;
                      final total = report.moves.length;
                      setState(() {
                        _ply = hit.first.x.round().clamp(0, total);
                      });
                    },
                  ),
                  titlesData: const FlTitlesData(
                    show: true,
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  gridData: const FlGridData(show: true),
                  borderData: FlBorderData(show: false),
                  minY: minY,
                  maxY: maxY,
                  lineBarsData: <LineChartBarData>[
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: theme.colorScheme.primary,
                      barWidth: 3,
                      dotData: const FlDotData(show: true),
                    ),
                  ],
                  extraLinesData: ExtraLinesData(
                    horizontalLines: <HorizontalLine>[
                      HorizontalLine(
                        y: 0,
                        color: theme.colorScheme.outlineVariant,
                        strokeWidth: 1,
                      ),
                    ],
                    verticalLines: <VerticalLine>[
                      VerticalLine(
                        x: _ply.toDouble(),
                        color: theme.colorScheme.error,
                        strokeWidth: 2,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Text(
              'Scores are White-relative and clamped to ±10 pawns; '
              'mate-anchored scores saturate the scale.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Centipawns → clamped White-relative pawns for the chart.
  double _pawns(int cp) => (cp / 100.0).clamp(-10.0, 10.0).toDouble();

  /// Before/after boards around the replay cursor.
  Widget _buildBeforeAfter(ReviewGame game) {
    final theme = Theme.of(context);
    final lastIndex = math.max(0, _fens.length - 1);
    final beforeIndex = math.max(0, math.min(_ply - 1, lastIndex));
    final afterIndex = math.max(0, math.min(_ply, lastIndex));
    final uci = _ply >= 1 && _ply - 1 < game.ucis.length
        ? game.ucis[_ply - 1]
        : null;
    final boardTheme = ref.watch(
      themeRegistryProvider.select((r) => r.boardTheme),
    );
    final pieceTheme = ref.watch(
      themeRegistryProvider.select((r) => r.pieceTheme),
    );
    Widget board(
      String label,
      int index, {
      String? lastFrom,
      String? lastTo,
    }) {
      return Column(
        children: <Widget>[
          Text(label),
          const SizedBox(height: 4),
          Chessboard(
            squares: _squaresAt(index),
            boardTheme: boardTheme,
            pieceTheme: pieceTheme,
            lastFrom: lastFrom,
            lastTo: lastTo,
            interactive: false,
            showCoordinates: false,
          ),
        ],
      );
    }

    final bright = uci != null && _ply >= 1;
    final before = board('Before (ply $beforeIndex)', beforeIndex);
    final after = board(
      'After (ply $afterIndex)',
      afterIndex,
      lastFrom: bright ? uci.substring(0, 2) : null,
      lastTo: bright ? uci.substring(2, 4) : null,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth.isFinite
                    ? constraints.maxWidth
                    : 800.0;
                if (layoutModeFor(width) == ArenaLayoutMode.narrow) {
                  // Stack on narrow phones so two boards cannot overflow.
                  return Column(
                    children: <Widget>[
                      before,
                      const SizedBox(height: 12),
                      after,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(child: before),
                    const SizedBox(width: 12),
                    Expanded(child: after),
                  ],
                );
              },
            ),
            if (bright) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                'Last move: $uci${_fallbackAt(game, _ply - 1) ? ' '
                    '(seeded fallback, unattributed)' : ''}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (_fens.length < game.ucis.length + 1) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                'Record has ${_fens.length} position snapshot'
                '${_fens.length == 1 ? '' : 's'} for '
                '${game.ucis.length} plies — some plies cannot be '
                'displayed.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Convenience wrapper over [redactSecrets] (kept local to the card)…
  bool _fallbackAt(ReviewGame game, int index) =>
      index >= 0 &&
      index < game.fallbackFlags.length &&
      game.fallbackFlags[index];

  /// Board squares for FEN-history [index] (FEN or variant JSON payload).
  Map<String, String> _squaresAt(int index) {
    if (_fens.isEmpty) return const <String, String>{};
    final safe = index.clamp(0, _fens.length - 1);
    return squaresOfPayload(_fens[safe]);
  }

  /// Move record for the cursor ply: UCI/SAN, phrase, fallback, rationale.
  Widget _buildMoveRecord(ReviewGame game, ReviewReport report) {
    final theme = Theme.of(context);
    final move = _currentMove(report);
    if (move == null) return const SizedBox.shrink();
    final index = move.moveIndex;
    final uci = index < game.ucis.length ? game.ucis[index] : '?';
    final phrase = index < game.phrases.length ? game.phrases[index] : null;
    final annotation = move.annotations.isEmpty
        ? null
        : move.annotations.join('; ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Move record', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            SelectableText(
              '${_sanAt(game, index)} · $uci'
              '${move.moverIsWhite ? ' (White)' : ' (Black)'}'
              ' · sources: ${move.beforeSource} → ${move.afterSource}',
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 6),
            Text(move.assessment.rationale),
            if (annotation != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                'Annotations: ${redactSecrets(annotation)}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (phrase != null && phrase.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(Icons.format_quote_outlined, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('“${redactSecrets(phrase)}”'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 6),
            Text(
              'Raw per-ply tool-call JSON is not part of the stored '
              'record yet — see the wiring point in this file’s docs.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Summary: text, per-side accuracy and quality counts.
  Widget _buildSummary(ReviewReport report) {
    final theme = Theme.of(context);
    const markOrder = <String>['!!', '!', 'ok', '!?', '?', '??'];
    final chips = <Widget>[];
    for (final mark in markOrder) {
      var count = 0;
      report.qualityCounts.forEach((name, value) {
        // Tier names → UI marks: unsupported/good share 'ok'; match by the
        // mark each tier maps to.
        if (qualityMarkFor(_qualityForName(name)) == mark) count += value;
      });
      if (count > 0) {
        chips.add(
          Chip(
            avatar: Icon(
              qualityIconFor(mark),
              size: 14,
              color: qualityColorFor(mark, brightness: theme.brightness),
            ),
            label: Text('$mark $count'),
            visualDensity: VisualDensity.compact,
          ),
        );
      }
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Summary', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(report.summary),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                StatChip(
                  label: 'White accuracy',
                  value: _accuracyLabel(report.whiteAccuracy),
                  icon: Icons.check_circle_outline,
                ),
                StatChip(
                  label: 'Black accuracy',
                  value: _accuracyLabel(report.blackAccuracy),
                  icon: Icons.check_circle_outline,
                ),
                ...chips,
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Tier name → [MoveQuality] (unknown names map to `unsupported`).
  MoveQuality _qualityForName(String name) {
    for (final quality in MoveQuality.values) {
      if (quality.name == name) return quality;
    }
    return MoveQuality.unsupported;
  }

  /// Accuracy mean as `xx.x` or `n/a`.
  String _accuracyLabel(double? value) =>
      value == null ? 'n/a' : value.toStringAsFixed(1);

  /// Clickable move list with quality/error marks.
  Widget _buildMoveList(ReviewGame game, ReviewReport report) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Moves',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            MoveList(
              moves: <String>[
                for (var i = 0; i < game.ucis.length; i++)
                  _sanAt(game, i),
              ],
              currentIndex: _ply - 1,
              qualityMarks: <int, String>{
                for (var i = 0; i < report.moves.length; i++)
                  i: qualityMarkFor(report.moves[i].assessment.quality),
              },
              errorPlies: <int>{
                for (var i = 0; i < game.fallbackFlags.length; i++)
                  if (game.fallbackFlags[i]) i,
              },
              onTapMove: (ply) => setState(() => _ply = ply + 1),
              maxHeight: 240,
            ),
            const SizedBox(height: 4),
            Text(
              'Fallback plies are marked with ⚠ (seeded moves are never '
              'attributed to an agent).',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Key-moment list; tap jumps the replay cursor to the moment.
  Widget _buildKeyMoments(ReviewReport report) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Key moments', style: theme.textTheme.titleSmall),
            for (final moment in report.keyMoments)
              ListTile(
                dense: true,
                leading: Icon(
                  qualityIconFor(qualityMarkFor(moment.quality)),
                  color: qualityColorFor(
                    qualityMarkFor(moment.quality),
                    brightness: theme.brightness,
                  ),
                ),
                title: Text(
                  'Ply ${moment.moveIndex + 1} · '
                  '${moment.moverIsWhite ? 'White' : 'Black'}',
                ),
                subtitle: Text(moment.note),
                onTap: () => setState(() => _ply = moment.moveIndex + 1),
              ),
            if (report.keyMoments.isEmpty)
              const Text('No supported swings — no key moments.'),
          ],
        ),
      ),
    );
  }
}
