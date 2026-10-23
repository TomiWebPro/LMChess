/// [ArenaScreen]: tournament configuration, live standings and mini boards.
///
/// The screen now runs **real** tournaments through the arena backend:
/// the config form builds a [TournamentConfig] (uuid id, selected agent
/// ids, `games = pairs × games per pairing × rounds`, fixed 600 s time
/// control, standard/chaotic mode from the chip, the concurrency slider as
/// `maxConcurrentGames`, balanced colors, a time-based seed shown in the
/// UI), [ArenaScheduler.generateSchedule] lays out the pairings and
/// [ArenaScheduler.run] executes them with bounded concurrency and
/// per-game failure isolation. Every game is played by [_runGame]:
///
/// * **Standard** games run a full [GameOrchestrator] (two AI seats)
///   driven by a sequential pump identical to the watch room's: bind the
///   roster config, one `requestAiTurn` with a [mockAwareProvider]
///   override, replay the UCI history onto a mirror [Position] (idempotent
///   [appliedMetaFor]-based sync), feed the fresh legal list back via
///   `setPosition`, and report engine terminals through [mapTerminal] +
///   `reportTerminal`. Finished games flush buffered [PendingTurn]s to
///   [StatsLog], write per-agent W/L/D markers and land in [ReviewLog] for
///   the review screen.
/// * **Chaotic** games have no orchestrator (its position contract is
///   FEN-shaped): the pump runs [AgentRunner.runTurn] directly against a
///   [VariantBoard] JSON payload, validates against a UI-side pseudo-legal
///   attempt list ([_variantAttempts]), interprets every attempt through
///   [ChaoticRules.interpret] and adjudicates king captures with
///   [ChaoticRules.gameOver]. Definitive failures fall back to a seeded
///   attempt from the same list (explicitly marked, never attributed).
///   Finished chaotic games are recorded losslessly into
///   [VariantReviewLog] as [VariantGameRecord]s ([_concludeGame]): initial
///   board, per-ply attempt/interpretation trail and outcome, replayable
///   from the review screen's "Chaotic replays" card. The FEN-shaped
///   [ReviewLog] is standard-only by design.
///
/// The grid renders one mini [Chessboard] per scheduled game (3/2/1
/// columns) with live squares, check/terminal highlights and status from
/// the scheduler refs; tapping any card opens the drill-down dialog, which
/// follows the running game through a screen-scoped ticker. Standings
/// compute points from the completed refs and Elo from an injectable
/// [EloService] (mode-keyed ladder, shared across tournaments of this app
/// session by default); ratings under the backend's minimum carry a
/// "provisional — N games" note, per the Elo docs.
///
/// Stop cancels pending pairings and stops the in-flight orchestrators
/// (chaos pumps exit between turns); dispose does the same best-effort and
/// each pump disposes its own orchestrator on exit, so no orchestrator is
/// ever disposed with a turn in flight.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../agent/agent_runner.dart';
import '../../arena/elo.dart';
import '../../arena/scheduler.dart';
import '../../arena/tournament.dart';
import '../../chess/engine.dart' as chess_eng;
import '../../chess/fen.dart';
import '../../chess/piece.dart';
import '../../chess/position.dart';
import '../../game/clock.dart';
import '../../game/game_state.dart';
import '../../game/orchestrator.dart';
import '../../llm/prompt_board.dart';
import '../../theme/board_theme.dart';
import '../../theme/piece_theme.dart';
import '../../theme/registry.dart';
import '../../variant/chaotic_engine.dart';
import '../../variant/interpretation.dart';
import '../../variant/variant_board.dart';
import '../../variant/variant_replay.dart';
import 'variant_replay_screen.dart';
import '../backend_bridge.dart';
import '../game_mirror.dart';
import '../ui_models.dart';
import '../widgets/boards.dart';
import '../widgets/chessboard.dart';

/// Shared stats-less runner for chaotic turns (stateless by default).
const AgentRunner _chaosRunner = AgentRunner();

/// Refcounted change notifier so the drill-down dialog follows a live game.
///
/// The screen bumps it next to its own `setState`; [ListenableBuilder] in
/// the dialog then rebuilds from the mutable [_LiveGame] snapshot. Its
/// lifetime is tied to its listeners: [requestDispose] marks it for teardown
/// and it disposes itself as soon as the last dialog listener is removed (or
/// immediately when no dialog is open), so a screen instance cannot leak it
/// while an open dialog still survives the screen's own teardown.
class _ArenaTicker extends ChangeNotifier {
  int _refs = 0;
  bool _disposeRequested = false;
  bool _disposed = false;

  @override
  void addListener(VoidCallback listener) {
    if (_disposed) return;
    _refs++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    if (_disposed) return;
    super.removeListener(listener);
    if (_refs > 0) _refs--;
    _maybeDispose();
  }

  /// Notifies dialog listeners (no-op once disposed).
  void bump() {
    if (!_disposed) notifyListeners();
  }

  /// Requests teardown; disposes now when unreferenced, else on the last
  /// [removeListener].
  void requestDispose() {
    _disposeRequested = true;
    _maybeDispose();
  }

  void _maybeDispose() {
    if (_disposeRequested && !_disposed && _refs <= 0) {
      _disposed = true;
      super.dispose();
    }
  }
}

/// Mutable per-game snapshot for the grid, standings and drill-down.
///
/// One instance per scheduled [TournamentGameRef]; every pump owns its
/// game's instance and mutates it between plies, so `setState` renders
/// without re-deriving from refs.
class _LiveGame {
  /// Creates a pending snapshot for [gameId].
  _LiveGame({
    required this.gameId,
    required this.label,
    required this.whiteAgentId,
    required this.blackAgentId,
    required this.whiteLabel,
    required this.blackLabel,
    required this.mode,
    required this.squares,
  });

  /// Scheduler game id (`<tournamentId>#game<N>`).
  final String gameId;

  /// Human label (`Game 3`, schedule order).
  final String label;

  /// Agent ids (stats/elo attribution) and display labels per seat.
  final String whiteAgentId;
  final String blackAgentId;
  final String whiteLabel;
  final String blackLabel;

  /// `'standard'` or `'chaotic'` (snapshot of the tournament config).
  final String mode;

  /// Current board for the mini/full [Chessboard] (`'e4' → 'wP'`).
  Map<String, String> squares;

  /// `pending` / `running` / `finished` / `cancelled` / `failed`.
  String status = 'pending';

  /// Score string once finished (`'1-0'`, `'0-1'`, `'1/2-1/2'`, `'draw'`).
  String? resultLabel;

  /// Terminal reason (or failure detail for `failed`).
  String reason = '';

  /// Game seed used for mock scripting + fallback picks.
  int seed = 0;

  /// Last-move trail (standard games: exact; chaotic: only standard-legal
  /// attempts, because an interpretation may move the piece elsewhere).
  String? lastFrom;
  String? lastTo;

  /// Check highlight (standard games only).
  String? inCheck;

  /// Checkmated king square (standard games only).
  String? terminalSquare;

  /// Played attempts in UCI order (chaotic plies are attempt UCIs).
  final List<String> ucis = <String>[];

  /// Move labels parallel to [ucis] (SAN for standard, UCI for chaotic).
  final List<String> sans = <String>[];

  /// FEN history parallel to [ucis] (+1, start first); standard only.
  final List<String> fens = <String>[];

  /// Agent phrases parallel to [ucis] (`null` for fallbacks/human moves).
  final List<String?> phrases = <String?>[];

  /// Fallback flags parallel to [ucis].
  final List<bool> fallbacks = <bool>[];

  /// Chaotic only: interpretation strategy id per ply (parallel to [ucis]).
  final List<String> interpretations = <String>[];

  /// Chaotic only: lossless replay records (parallel to [ucis]).
  final List<VariantPlyRecord> variantPlies = <VariantPlyRecord>[];

  /// Chaotic only: starting board for replay.
  VariantBoard? initialBoard;

  /// Chaotic only: wall-clock start.
  DateTime? startedAt;

  /// Live orchestrator for standard games, while the pump owns it.
  GameOrchestrator? orch;
}

/// Human-readable status for one game, derived from the authoritative
/// scheduler ref plus the pump's snapshot.
String _gameStatusText(TournamentGameRef ref, _LiveGame live) {
  switch (ref.status) {
    case TournamentGameStatus.pending:
      return 'pending';
    case TournamentGameStatus.running:
      return 'running · ${live.ucis.length} plies';
    case TournamentGameStatus.completed:
      final label = live.resultLabel ?? 'finished';
      return live.reason.isEmpty ? label : '$label · ${live.reason}';
    case TournamentGameStatus.failed:
      return 'failed';
    case TournamentGameStatus.cancelled:
      final label = live.resultLabel;
      if (live.status == 'finished' && label != null) {
        return live.reason.isEmpty ? label : '$label · ${live.reason}';
      }
      return 'cancelled';
  }
}

/// One standings row for the current tournament.
class _Standing {
  /// Creates a row for [agentId] with its session Elo on the ladder.
  _Standing({
    required this.agentId,
    required this.name,
    required this.elo,
    required this.eloGames,
    required this.provisional,
  });

  /// Agent id + display name.
  final String agentId;
  final String name;

  /// Session Elo rating for the tournament's mode ladder.
  final double elo;

  /// Ladder games played this session (confidence signal).
  final int eloGames;

  /// True when [eloGames] is below the Elo backend's minimum.
  final bool provisional;

  /// W/L/D accumulated from the current tournament's completed refs.
  int wins = 0;
  int losses = 0;
  int draws = 0;

  /// Points (win = 1, draw = ½).
  double get points => wins + draws * 0.5;

  /// Games counted in the points tally.
  int get played => wins + losses + draws;

  /// `'3W 1L 2D'` record label.
  String get record => '${wins}W ${losses}L ${draws}D';
}

/// Tournament arena: config, standings, mini-board grid, drill-down.
class ArenaScreen extends ConsumerStatefulWidget {
  /// Creates the arena screen.
  ///
  /// [elo] allows tests to inject a fresh [EloService] so tournament ratings
  /// do not leak across test boundaries via the session-static singleton.
  const ArenaScreen({super.key, this.elo, this.initialSeed});

  /// Optional Elo ladders for the tournament. When absent the screen creates
  /// a fresh [EloService] internally.
  final EloService? elo;

  /// Seed for deterministic tournaments — replaces wall-clock randomness.
  final int? initialSeed;

  @override
  ConsumerState<ArenaScreen> createState() => _ArenaScreenState();
}

class _ArenaScreenState extends ConsumerState<ArenaScreen> {
  /// Elo ladders for the tournament. Injected via [ArenaScreen.elo] when tests
  /// require isolation between test cases; otherwise a fresh service is created.
  late final EloService _elo;

  final _name = TextEditingController(text: 'Autumn Invitational');

  /// Rounds per pairing.
  int _rounds = 1;

  /// Games per pairing.
  int _gamesPerPairing = 2;

  /// Chaos-variant mutations enabled.
  bool _chaos = false;

  /// Parallel games (mapped to `TournamentConfig.maxConcurrentGames`).
  double _concurrency = 2;

  /// Selected agent ids.
  final Set<String> _selected = <String>{'demo-white', 'demo-black'};

  /// Live tournament state (`null` before the first start).
  TournamentState? _state;

  /// Running scheduler, while [_running].
  ArenaScheduler? _scheduler;

  /// Progress subscription of the current run.
  StreamSubscription<SchedulerProgress>? _progressSub;

  /// Whether a run is in progress (Stop pending until it settles).
  bool _running = false;

  /// Whether cancellation was requested (Stop or dispose).
  bool _cancelling = false;

  /// Completed/total games (mirrors [SchedulerProgress]).
  int _completed = 0;
  int _total = 0;

  /// Post-run notice (finished/cancelled summary + infra failures).
  String? _notice;

  /// Whether [_notice] reports a problem (drives its color); notices are
  /// success-neutral by default, not error-red.
  bool _noticeIsError = false;

  /// Memoized standings, invalidated when the completed-game count changes.
  List<_Standing>? _standingsCache;
  int _standingsCacheKey = -1;

  /// Agent id → catalog snapshot taken at Start, so games are immune to
  /// later catalog edits (the scheduler roster equivalent for UI labels).
  final Map<String, AgentConfig> _roster = <String, AgentConfig>{};

  /// Per-game snapshots keyed by scheduler game id.
  final Map<String, _LiveGame> _live = <String, _LiveGame>{};

  /// Dialog-follow notifier (see [_ArenaTicker]).
  final _ArenaTicker _ticker = _ArenaTicker();

  /// Wall-clock source (§10.3 seam); tests override via [clockProvider].
  late DateTime Function() _clock;

  /// Per-scope stats store (§13 telemetry isolation).
  late final StatsLog _statsLog;

  /// Per-scope review-game store (§13 telemetry isolation).
  late final ReviewLog _reviewLog;

  /// Per-scope variant-replay store (§13 telemetry isolation).
  late final VariantReviewLog _variantReviewLog;

  @override
  void initState() {
    _clock = ref.read(clockProvider);
    _elo = widget.elo ?? EloService();
    _statsLog = ref.read(statsLogProvider);
    _reviewLog = ref.read(reviewLogProvider);
    _variantReviewLog = ref.read(variantReviewLogProvider);
    super.initState();
  }

  @override
  void dispose() {
    _cancelling = true;
    _scheduler?.cancel();
    unawaited(_progressSub?.cancel());
    for (final live in _live.values) {
      final orch = live.orch;
      if (orch != null && !isTerminalOrchestratorState(orch.state)) {
        orch.stop(reason: 'screen disposed');
      }
      // The pump disposes its own orchestrator on exit (and a late turn
      // must never hit a disposed notifier), so only stop here.
      live.orch = null;
    }
    _ticker.requestDispose();
    _name.dispose();
    super.dispose();
  }

  /// Re-renders the screen and any open drill-down dialog.
  void _touch() {
    _ticker.bump();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final agents = ref.watch(agentListProvider).agents;
    final boardTheme = ref.watch(
      themeRegistryProvider.select((r) => r.boardTheme),
    );
    final pieceTheme = ref.watch(
      themeRegistryProvider.select((r) => r.pieceTheme),
    );
    final state = _state;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildConfig(agents),
          if (state == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Configure the tournament above, then press Start. '
                  'Games run with real orchestrators — mock agents need '
                  'no keys.',
                ),
              ),
            )
          else ...<Widget>[
            const SizedBox(height: 16),
            _buildProgress(state),
            const SizedBox(height: 16),
            _buildStandings(state),
            const SizedBox(height: 16),
            _buildGrid(state, boardTheme, pieceTheme),
          ],
        ],
      ),
    );
  }

  /// Tournament config form + start/stop.
  Widget _buildConfig(List<AgentConfig> agents) {
    final theme = Theme.of(context);
    final picked = agents.where((a) => _selected.contains(a.id)).length;
    final pairs = picked < 2 ? 0 : picked * (picked - 1) ~/ 2;
    final totalGames = pairs * _gamesPerPairing * _rounds;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Tournament', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              enabled: !_running,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                DropdownMenu<int>(
                  enabled: !_running,
                  label: const Text('Rounds'),
                  initialSelection: _rounds,
                  dropdownMenuEntries: const <DropdownMenuEntry<int>>[
                    DropdownMenuEntry(value: 1, label: '1'),
                    DropdownMenuEntry(value: 3, label: '3'),
                    DropdownMenuEntry(value: 5, label: '5'),
                  ],
                  onSelected: (v) => setState(() => _rounds = v ?? 1),
                ),
                DropdownMenu<int>(
                  enabled: !_running,
                  label: const Text('Games / pairing'),
                  initialSelection: _gamesPerPairing,
                  dropdownMenuEntries: const <DropdownMenuEntry<int>>[
                    DropdownMenuEntry(value: 1, label: '1'),
                    DropdownMenuEntry(value: 2, label: '2'),
                    DropdownMenuEntry(value: 4, label: '4'),
                  ],
                  onSelected: (v) =>
                      setState(() => _gamesPerPairing = v ?? 2),
                ),
                FilterChip(
                  label: const Text('Chaos variants'),
                  selected: _chaos,
                  onSelected:
                      _running ? null : (v) => setState(() => _chaos = v),
                ),
              ],
            ),
            Row(
              children: <Widget>[
                const Text('Concurrency'),
                Expanded(
                  child: Slider(
                    value: _concurrency,
                    min: 1,
                    max: 8,
                    divisions: 7,
                    label: _concurrency.toStringAsFixed(0),
                    onChanged: _running
                        ? null
                        : (v) => setState(() => _concurrency = v),
                  ),
                ),
                Text(_concurrency.toStringAsFixed(0)),
              ],
            ),
            Text(
              '$pairs pairing(s) × $_gamesPerPairing game(s) × $_rounds '
              'round(s) = $totalGames game(s). Colors alternate per pairing; '
              'the seed is drawn at start.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text('Agents', style: theme.textTheme.labelLarge),
            Wrap(
              spacing: 8,
              children: <Widget>[
                for (final a in agents)
                  FilterChip(
                    label: Text(a.name),
                    selected: _selected.contains(a.id),
                    onSelected: _running
                        ? null
                        : (v) => setState(() {
                              if (v) {
                                _selected.add(a.id);
                              } else {
                                _selected.remove(a.id);
                              }
                            }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                FilledButton.icon(
                  onPressed: (picked < 2 || _running) ? null : _start,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start tournament'),
                ),
                const SizedBox(width: 8),
                if (_running)
                  TextButton.icon(
                    onPressed: _cancelling ? null : _cancel,
                    icon: const Icon(Icons.stop_outlined),
                    label: Text(_cancelling ? 'Cancelling…' : 'Stop'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Progress card: name, mode/seed chips, completion bar, run notice.
  Widget _buildProgress(TournamentState state) {
    final theme = Theme.of(context);
    final config = state.config;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    config.name,
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Chip(
                  label: Text(
                    config.mode == 'chaotic' ? 'chaos variants' : 'standard',
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 4),
                Chip(
                  label: Text('seed ${config.seed}'),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: _total == 0 ? 1.0 : _completed / _total,
            ),
            const SizedBox(height: 4),
            Text(
              '$_completed/$_total games done · concurrency '
              '${config.maxConcurrentGames}',
              style: theme.textTheme.bodySmall,
            ),
            if (_notice != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                _notice!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _noticeIsError
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Standings: points from completed refs + session Elo per mode ladder.
  Widget _buildStandings(TournamentState state) {
    final theme = Theme.of(context);
    final rows = _computeStandings(state);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Standings · ${state.config.mode} ladder',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Table(
              columnWidths: const <int, TableColumnWidth>{
                0: FlexColumnWidth(4),
                1: FlexColumnWidth(1),
                2: FlexColumnWidth(2),
                3: FlexColumnWidth(2),
              },
              children: <TableRow>[
                for (var i = 0; i < rows.length; i++)
                  TableRow(
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text('${i + 1}. ${rows[i].name}'),
                            Text(
                              '${rows[i].played} game(s) this run',
                              style: theme.textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                      Text('${rows[i].points.toStringAsFixed(1)} pts'),
                      Text(rows[i].record),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text('Elo ${rows[i].elo.round()}'),
                          if (rows[i].provisional)
                            Text(
                              'provisional — ${rows[i].eloGames} games',
                              style: theme.textTheme.labelSmall,
                            ),
                        ],
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Elo is session-scoped per mode ladder. Ratings are '
              'provisional below 10 games, and Elo differences under ~30 '
              'games per agent are mostly noise.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  /// Responsive grid of mini boards (tap → drill-down dialog).
  Widget _buildGrid(
    TournamentState state,
    BoardTheme boardTheme,
    PieceTheme pieceTheme,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 800;
        final cols = w > 1100 ? 3 : (w >= 700 ? 2 : 1);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.92,
          ),
          itemCount: state.games.length,
          itemBuilder: (context, i) {
            final gameRef = state.games[i];
            final live = _live[gameRef.gameId];
            if (live == null) return const SizedBox.shrink();
            return Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _openDetail(gameRef, live),
                child: Column(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              '${live.label} · ${live.whiteLabel} vs '
                              '${live.blackLabel}',
                              style: Theme.of(context).textTheme.labelLarge,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _gameStatusText(gameRef, live),
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: Chessboard(
                          squares: live.squares,
                          boardTheme: boardTheme,
                          pieceTheme: pieceTheme,
                          lastFrom: live.lastFrom,
                          lastTo: live.lastTo,
                          inCheck: live.inCheck,
                          terminalSquare: live.terminalSquare,
                          interactive: false,
                          showCoordinates: false,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Builds the tournament from the form and starts executing it.
  void _start() {
    // Guard against re-entry (button is disabled while running, but a
    // programmatic/second tap must not start two schedulers — `run()` throws
    // if the scheduler is already running).
    if (_running) return;
    final catalog = ref.read(agentListProvider);
    final picked = <AgentConfig>[
      for (final a in catalog.agents)
        if (_selected.contains(a.id)) a,
    ];
    if (picked.length < 2) return; // Button is disabled; double-guard.
    final pairs = picked.length * (picked.length - 1) ~/ 2;
    final mode = _chaos ? 'chaotic' : 'standard';
    final seed = widget.initialSeed ?? (_clock().millisecondsSinceEpoch & 0x7fffffff);
    final config = TournamentConfig(
      id: const Uuid().v4(),
      name: _name.text.trim().isEmpty ? 'Tournament' : _name.text.trim(),
      agentIds: <String>[for (final a in picked) a.id],
      games: pairs * _gamesPerPairing * _rounds,
      timeControlJson: const <String, Object?>{
        'kind': 'fixed',
        'initialMs': 600000,
      },
      mode: mode,
      maxConcurrentGames: _concurrency.round(),
      colorAlternation: true,
      seed: seed,
      failFast: false,
    );
    final state = ArenaScheduler.generateSchedule(config);

    unawaited(_progressSub?.cancel());
    _cancelling = false;
    _running = true;
    _notice = null;
    _noticeIsError = false;
    _completed = 0;
    _total = state.games.length;
    _state = state;
    _standingsCache = null;
    _roster
      ..clear()
      ..addEntries(
        <MapEntry<String, AgentConfig>>[
          for (final a in picked) MapEntry<String, AgentConfig>(a.id, a),
        ],
      );
    _live.clear();
    final startSquares = squaresOf(Position.initial());
    for (var i = 0; i < state.games.length; i++) {
      final ref = state.games[i];
      _live[ref.gameId] = _LiveGame(
        gameId: ref.gameId,
        label: 'Game ${i + 1}',
        whiteAgentId: ref.whiteAgentId,
        blackAgentId: ref.blackAgentId,
        whiteLabel: _roster[ref.whiteAgentId]?.name ?? ref.whiteAgentId,
        blackLabel: _roster[ref.blackAgentId]?.name ?? ref.blackAgentId,
        mode: mode,
        squares: startSquares,
      );
    }

    final scheduler = ArenaScheduler(
      state: state,
      gameFactory: FunctionGameFactory(
        (pairing, gameSeed) => _runGame(state, pairing, gameSeed),
      ),
    );
    _progressSub = scheduler.progress.listen((progress) {
      if (!mounted) return;
      setState(() {
        _completed = progress.completed;
        _total = progress.total;
      });
    });
    _scheduler = scheduler;
    setState(() {});
    unawaited(() async {
      try {
        final finished = await scheduler.run();
        if (!mounted) return;
        final played = finished.games
            .where((g) => g.status == TournamentGameStatus.completed)
            .length;
        final failed = finished.games
            .where((g) => g.status == TournamentGameStatus.failed)
            .length;
        setState(() {
          _running = false;
          final failureNote =
              failed == 0 ? '' : ' · $failed infrastructure failure(s)';
          _noticeIsError = failed > 0;
          _notice = _cancelling
              ? 'Cancelled after $played/${finished.games.length} played '
                  'games.'
              : 'Finished: $played/${finished.games.length} games with '
                  'results$failureNote.';
        });
      } catch (error) {
        // A throwing run() must not leave the screen stuck on "running" with
        // an unhandled async error.
        if (!mounted) return;
        setState(() {
          _running = false;
          _cancelling = false;
          _noticeIsError = true;
          _notice = 'Tournament run failed: $error';
        });
      }
    }());
  }

  /// Requests cancellation: scheduler stops dispatching, running standard
  /// orchestrators stop (late turns discard), chaos pumps see [_cancelling]
  /// between turns. Slot statuses are reconciled here and when the run
  /// future settles.
  void _cancel() {
    if (!_running || _cancelling) return;
    _cancelling = true;
    _scheduler?.cancel();
    final state = _state;
    if (state != null) {
      for (final ref in state.games) {
        if (ref.status == TournamentGameStatus.pending) {
          final live = _live[ref.gameId];
          if (live != null && live.status != 'finished') {
            live.status = 'cancelled';
          }
        }
      }
    }
    for (final live in _live.values) {
      final orch = live.orch;
      if (orch != null && !isTerminalOrchestratorState(orch.state)) {
        orch.stop(reason: 'stopped');
      }
    }
    setState(() {});
    _ticker.bump();
  }

  /// Opens the drill-down dialog for [live] (follows the live snapshot).
  void _openDetail(TournamentGameRef gameRef, _LiveGame live) {
    showDialog<void>(
      context: context,
      builder: (context) => _GameDetailDialog(
        live: live,
        gameRef: gameRef,
        ticker: _ticker,
        tournamentName: _state?.config.name ?? '',
      ),
    );
  }

  /// Computes standings rows: tournament points from completed refs, Elo
  /// from the session-static service for the tournament's mode ladder.
  ///
  /// Memoized on `(_completed, _total, mode)` so the per-ply `_touch()`
  /// rebuild does not re-aggregate every ref on each ply; the cache is
  /// dropped when a run starts (roster/mode change) and recomputed as the
  /// completed count advances.
  List<_Standing> _computeStandings(TournamentState state) {
    final key = Object.hash(_completed, _total, state.config.mode);
    final cached = _standingsCache;
    if (cached != null && _standingsCacheKey == key) return cached;
    final mode = state.config.mode;
    final byId = <String, _Standing>{};
    for (final agentId in state.config.agentIds) {
      byId[agentId] = _Standing(
        agentId: agentId,
        name: _roster[agentId]?.name ?? agentId,
        elo: _elo.ratingFor(agentId, mode),
        eloGames: _elo.gamesFor(agentId, mode),
        provisional: _elo.isProvisional(agentId, mode),
      );
    }
    for (final ref in state.games) {
      final result = ref.result;
      if (ref.status != TournamentGameStatus.completed || result == null) {
        continue;
      }
      final white = byId[ref.whiteAgentId];
      final black = byId[ref.blackAgentId];
      switch (result) {
        case TournamentGameResult.whiteWin:
          white?.wins++;
          black?.losses++;
        case TournamentGameResult.blackWin:
          black?.wins++;
          white?.losses++;
        case TournamentGameResult.draw:
          white?.draws++;
          black?.draws++;
      }
    }
    final rows = byId.values.toList()
      ..sort((a, b) {
        final byPoints = b.points.compareTo(a.points);
        if (byPoints != 0) return byPoints;
        final byElo = b.elo.compareTo(a.elo);
        if (byElo != 0) return byElo;
        return a.name.compareTo(b.name);
      });
    _standingsCache = rows;
    _standingsCacheKey = key;
    return rows;
  }

  /// Executes one scheduled game with full failure isolation.
  ///
  /// Wraps the mode-specific pump: [state.config] decides standard vs
  /// chaotic, so a re-run can never leak mode changes into games already
  /// dispatched. Any throw becomes that game's `infraFailure` only.
  Future<GameResultSummary> _runGame(
    TournamentState state,
    Pairing pairing,
    int seed,
  ) async {
    final live = _live[pairing.gameId];
    if (live == null) {
      return GameResultSummary(
        gameId: pairing.gameId,
        whiteAgentId: pairing.whiteAgentId,
        blackAgentId: pairing.blackAgentId,
        infraFailure: 'live snapshot missing for ${pairing.gameId}',
      );
    }
    if (_cancelling) {
      // Returning neither result nor failure marks the ref cancelled.
      return GameResultSummary(
        gameId: pairing.gameId,
        whiteAgentId: pairing.whiteAgentId,
        blackAgentId: pairing.blackAgentId,
      );
    }
    live.status = 'running';
    live.seed = seed;
    live.reason = '';
    _touch();
    try {
      return state.config.mode == 'chaotic'
          ? await _runChaoticGame(state, pairing, seed, live)
          : await _runStandardGame(state, pairing, seed, live);
    } catch (e) {
      live.status = 'failed';
      live.reason = '$e';
      _touch();
      return GameResultSummary(
        gameId: pairing.gameId,
        whiteAgentId: pairing.whiteAgentId,
        blackAgentId: pairing.blackAgentId,
        infraFailure: '$e',
      );
    }
  }

  /// Standard pump: orchestrator + mirror engine (watch-room pattern).
  Future<GameResultSummary> _runStandardGame(
    TournamentState state,
    Pairing pairing,
    int seed,
    _LiveGame live,
  ) async {
    final white = _roster[pairing.whiteAgentId];
    final black = _roster[pairing.blackAgentId];
    if (white == null || black == null) {
      return GameResultSummary(
        gameId: pairing.gameId,
        whiteAgentId: pairing.whiteAgentId,
        blackAgentId: pairing.blackAgentId,
        infraFailure: 'agent config missing from the roster snapshot',
      );
    }
    final engine = Position.initial();
    if (live.fens.isEmpty) live.fens.add(standardStartFen);
    var applied = 0;
    final pending = <PendingTurn>[];
    final orch = GameOrchestrator(
      config: GameConfig(
        mode: GameMode.standard,
        timeControl: const TimeControl(
          type: TimeControlType.fixed,
          initialMs: 600000,
        ),
        maxMoves: 200,
        seed: seed,
      ),
      white: GameParticipant(
        agentConfigId: white.id,
        label: white.name,
        isHuman: false,
      ),
      black: GameParticipant(
        agentConfigId: black.id,
        label: black.name,
        isHuman: false,
      ),
      positionUpdater: fenAdvance,
    );
    live.orch = orch;
    orch.setPosition(
      standardStartFen,
      turn: 'w',
      legalMoves: legalUcis(engine),
    );
    orch.startGame();
    try {
      while (!_cancelling && identical(live, _live[pairing.gameId])) {
        if (isTerminalOrchestratorState(orch.state)) break;
        if (orch.state != OrchestratorState.waitingAi) break;
        if (orch.legalMoves.isEmpty) break;
        final color = orch.turn;
        final uiAgent = color == 'w' ? white : black;
        final backend = toBackendAgent(uiAgent);
        orch.bindAgent(backend);
        final before = orch.moveHistory.length;
        final provider = await ref.read(turnProviderFactoryProvider)(
          backend,
          orch.legalMoves,
          seed: _turnSeed(seed, before),
          phrase: '${uiAgent.name} move',
        );
        AgentTurnResult? result;
        try {
          result = await orch.requestAiTurn(color, providerOverride: provider);
        } finally {
          closeProvider(provider);
        }
        if (!identical(live, _live[pairing.gameId])) break;
        final replay = _syncStandard(live, orch, engine, applied);
        applied = replay.applied;
        if (result == null) break; // Rejected: stop/finish raced us.
        final grew = orch.moveHistory.length > before;
        if (grew || !result.isSuccess) {
          pending.add(
            PendingTurn.ai(
              agentId: backend.id,
              modelKey: backend.model,
              color: color == 'w' ? 'white' : 'black',
              mode: 'standard',
              result: result,
              fallback: grew && !result.isSuccess,
            ),
          );
        }
        if (replay.hasError || applied != orch.moveHistory.length) {
          // Mirror desync: an engine/UI bug, not a normal game outcome.
          for (final turn in pending) {
            turn.flush(
              log: _statsLog,
              gameId: pairing.gameId,
              tournamentId: state.config.id,
            );
          }
          live.status = 'failed';
          live.reason = replay.hasError
              ? 'mirror desync at ply $applied: ${replay.error}'
              : 'mirror desync at ply $applied';
          _touch();
          return GameResultSummary(
            gameId: pairing.gameId,
            whiteAgentId: pairing.whiteAgentId,
            blackAgentId: pairing.blackAgentId,
            infraFailure: live.reason,
          );
        }
        if (!isTerminalOrchestratorState(orch.state)) {
          orch.setPosition(
            engine.toFen(),
            turn: engine.sideToMove.isWhite ? 'w' : 'b',
            legalMoves: legalUcis(engine),
          );
        }
        final terminal = chess_eng.ChessRules.resultOf(engine);
        if (terminal != null && !isTerminalOrchestratorState(orch.state)) {
          if (terminal.termination == chess_eng.GameTermination.checkmate) {
            live.terminalSquare =
                engine.kingSquare(engine.sideToMove)?.name;
          }
          final mapped = mapTerminal(terminal);
          orch.reportTerminal(
            gameResult(
              outcome: mapped.outcome,
              reason: mapped.reason,
              winnerColor: mapped.winnerColor,
            ),
          );
        }
        _touch();
      }
    } finally {
      if (identical(live.orch, orch)) live.orch = null;
      orch.dispose();
    }
    if (orch.state == OrchestratorState.failed) {
      for (final turn in pending) {
        turn.flush(
          log: _statsLog,
          gameId: pairing.gameId,
          tournamentId: state.config.id,
        );
      }
      live.status = 'failed';
      live.reason = orch.failureMessage ?? 'orchestrator failed';
      _touch();
      return GameResultSummary(
        gameId: pairing.gameId,
        whiteAgentId: pairing.whiteAgentId,
        blackAgentId: pairing.blackAgentId,
        infraFailure: live.reason,
      );
    }
    final outcome = orch.result?.outcome ?? '*';
    final reason = orch.result?.reason ?? '';
    final mapped = _mapOutcome(outcome, reason);
    _concludeGame(
      state: state,
      pairing: pairing,
      live: live,
      result: mapped,
      outcome: outcome,
      reason: reason,
      pending: pending,
    );
    return GameResultSummary(
      gameId: pairing.gameId,
      whiteAgentId: pairing.whiteAgentId,
      blackAgentId: pairing.blackAgentId,
      result: mapped,
    );
  }

  /// Chaotic pump: direct runner turns + interpretation pipeline.
  ///
  /// No orchestrator: its position contract is FEN-shaped, while variant
  /// state is JSON. The runner still does all validation/retry; a turn
  /// that definitively fails (or crashes) falls back to a seeded attempt
  /// from [_variantAttempts], applied through [ChaoticRules.interpret] and
  /// recorded as an unattributed fallback.
  Future<GameResultSummary> _runChaoticGame(
    TournamentState state,
    Pairing pairing,
    int seed,
    _LiveGame live,
  ) async {
    final white = _roster[pairing.whiteAgentId];
    final black = _roster[pairing.blackAgentId];
    if (white == null || black == null) {
      return GameResultSummary(
        gameId: pairing.gameId,
        whiteAgentId: pairing.whiteAgentId,
        blackAgentId: pairing.blackAgentId,
        infraFailure: 'agent config missing from the roster snapshot',
      );
    }
    var board = VariantBoard.fromStandard(Position.initial());
    final pending = <PendingTurn>[];
    live.initialBoard = board;
    live.variantPlies.clear();
    live.startedAt = _clock().toUtc();
    var ply = 0;
    var outcome = '*';
    var reason = '';
    while (true) {
      if (_cancelling) {
        reason = 'cancelled';
        break;
      }
      if (ply >= 200) {
        reason = 'maxMoves';
        break;
      }
      final over = ChaoticRules.gameOver(board);
      if (over.over) {
        outcome = over.winner == null
            ? '1/2-1/2'
            : (over.winner!.isWhite ? '1-0' : '0-1');
        reason = over.reason;
        break;
      }
      final moverColor = board.sideToMove;
      final uiAgent = moverColor.isWhite ? white : black;
      final backend = toBackendAgent(uiAgent);
      final attempts = _variantAttempts(board);
      if (attempts.isEmpty) {
        reason = 'noAttempts';
        break;
      }
      final turnSeed = _turnSeed(seed, ply);
      final provider = await ref.read(turnProviderFactoryProvider)(
        backend,
        attempts,
        seed: turnSeed,
        phrase: '${uiAgent.name} move',
      );
      AgentTurnResult? result;
      final promptState = _variantPromptState(board);
      try {
        result = await _chaosRunner.runTurn(
          backend,
          AgentTurnRequest(
            positionFenOrJson: jsonEncode(board.toJson()),
            legalMovesUci: attempts,
            boardText: promptState.board,
            castlingRights: promptState.castling,
            enPassantTarget: promptState.enPassant,
            mode: 'chaotic',
            color: moverColor.isWhite ? 'w' : 'b',
            // Intent-first: any well-formed attempt reaches the interpreter;
            // the prompt never showed a legal-move list to begin with.
            acceptAnyMove: true,
          ),
          seed: turnSeed,
          providerOverride: provider,
        );
      } catch (_) {
        result = null; // Runner internals only; treated as provider error.
      } finally {
        closeProvider(provider);
      }
      final colorName = moverColor.isWhite ? 'white' : 'black';
      var attemptUci = '';
      String? phrase;
      var wasFallback = false;
      if (result != null && result.isSuccess && result.selectedMove != null) {
        attemptUci = result.selectedMove!.uci;
        phrase = result.selectedMove!.phrase;
        pending.add(
          PendingTurn.ai(
            agentId: backend.id,
            modelKey: backend.model,
            color: colorName,
            mode: state.config.mode,
            result: result,
          ),
        );
      } else {
        // Seeded fallback attempt (unattributed), never the model's pick.
        attemptUci = attempts[math.Random(turnSeed).nextInt(attempts.length)];
        phrase = null;
        wasFallback = true;
        if (result != null) {
          pending.add(
            PendingTurn.ai(
              agentId: backend.id,
              modelKey: backend.model,
              color: colorName,
              mode: state.config.mode,
              result: result,
              fallback: true,
            ),
          );
        } else {
          _statsLog.logTurn(
            gameId: pairing.gameId,
            agentId: backend.id,
            tournamentId: state.config.id,
            modelKey: backend.model,
            color: colorName,
            mode: state.config.mode,
            providerError: true,
          );
        }
      }
      final boardBefore = board;
      final rawTool = rawToolCallFrom(result);
      final selectedMove = result?.selectedMove;
      final attemptFrom = selectedMove?.from ??
          (attemptUci.length >= 2 ? attemptUci.substring(0, 2) : '');
      final attemptTo = selectedMove?.to ??
          (attemptUci.length >= 4 ? attemptUci.substring(2, 4) : '');
      final attemptPromotion = selectedMove?.promotion ??
          (attemptUci.length > 4 ? attemptUci.substring(4, 5) : null);
      final attemptRecord = VariantAttemptRecord(
        uci: attemptUci,
        fromSquareName: attemptFrom,
        toSquareName: attemptTo,
        promotion: attemptPromotion,
        phrase: phrase ?? '',
        rawToolArgsJson: rawTool.rawToolArgsJson,
        rawToolCallJson: rawTool.rawToolCallJson,
        source: wasFallback
            ? VariantAttemptSource.fallback
            : VariantAttemptSource.model,
      );
      final interpreted = ChaoticRules.interpret(
        boardBefore,
        AttemptedMove(
          fromSquareName: attemptFrom,
          toSquareName: attemptTo,
          promotion: attemptPromotion,
          phrase: phrase ?? '',
          rawToolCallJson:
              rawTool.rawToolCallJson ?? <String, Object?>{'uci': attemptUci},
          rawToolArgsJson: rawTool.rawToolArgsJson ?? '',
        ),
        seed: turnSeed,
      );
      live.variantPlies.add(VariantPlyRecord(
        ply: ply,
        mover: colorName == 'white' ? 'w' : 'b',
        agentId: backend.id,
        modelKey: backend.model,
        seed: turnSeed,
        fallback: wasFallback,
        attempt: attemptRecord,
        wasLegal: interpreted.wasLegal,
        standardDetail: interpreted.standardDetail,
        interpretationKind: VariantInterpretationKind.fromStrategyId(
          interpreted.selected.strategyId,
        ),
        selected:
            VariantInterpretationRecord.fromCandidate(interpreted.selected),
        candidates: <VariantInterpretationRecord>[
          for (final c in interpreted.candidates)
            VariantInterpretationRecord.fromCandidate(c),
        ],
        events: interpreted.events,
        boardAfter: interpreted.selected.resultingBoard,
        kingFacts: VariantKingFacts.between(
          boardBefore,
          interpreted.selected.resultingBoard,
          moverColor,
        ),
        boardHashBefore: boardBefore.boardHash(),
        boardHashAfter: interpreted.selected.resultingBoard.boardHash(),
        policy: interpreted.policy,
        turnFailureKind: result?.failure?.kind.name,
        turnFailureMessage: result?.failure?.message,
        latencyMs: result?.latencyMs,
        inputTokens: result?.usage?.inputTokens,
        outputTokens: result?.usage?.outputTokens,
      ));
      board = interpreted.selected.resultingBoard;
      ply++;
      live.ucis.add(attemptUci);
      live.sans.add(attemptUci); // Chaotic plies have no SAN; UCI is honest.
      live.phrases.add(wasFallback ? null : phrase);
      live.fallbacks.add(wasFallback);
      live.interpretations.add(
        '${interpreted.selected.strategyId}'
        '${interpreted.selected.capturesKing ? ' · king captured' : ''}',
      );
      live.squares = _variantSquares(board);
      // Exact trail only for standard-legal attempts; an interpretation
      // (teleport, closest-legal, …) may have moved another piece.
      if (interpreted.wasLegal) {
        live.lastFrom = attemptUci.substring(0, 2);
        live.lastTo = attemptUci.substring(2, 4);
      } else {
        live.lastFrom = null;
        live.lastTo = null;
      }
      _touch();
    }
    final mapped = _mapOutcome(outcome, reason);
    _concludeGame(
      state: state,
      pairing: pairing,
      live: live,
      result: mapped,
      outcome: outcome,
      reason: reason,
      pending: pending,
    );
    return GameResultSummary(
      gameId: pairing.gameId,
      whiteAgentId: pairing.whiteAgentId,
      blackAgentId: pairing.blackAgentId,
      result: mapped,
    );
  }

  /// Replays unapplied orchestrator UCIs onto the mirror engine.
  ///
  /// Idempotent (called after every turn); refreshes the check highlight
  /// and returns the new applied count.
  MirrorReplayResult _syncStandard(
    _LiveGame live,
    GameOrchestrator orch,
    Position engine,
    int applied,
  ) {
    // Shared replay core; arena's hooks also maintain the mini-board/check
    // snapshot. Any error is reported to the caller as a mirror desync.
    return replayMoves(
      orch: orch,
      engine: engine,
      applied: applied,
      onApplied: (index, uci, move, receipt, meta) {
        live.sans.add(receipt.san);
        live.ucis.add(uci);
        live.phrases.add(meta.isFallback ? null : meta.phrase);
        live.fallbacks.add(meta.isFallback);
        live.fens.add(engine.toFen());
        live.squares = squaresOf(engine);
        live.lastFrom = move.from.name;
        live.lastTo = move.to.name;
        live.inCheck = checkSquare(engine);
      },
    );
  }

  /// Flushes buffered turns, writes result markers, updates Elo (when the
  /// game has a result) and records the standard game for review.
  void _concludeGame({
    required TournamentState state,
    required Pairing pairing,
    required _LiveGame live,
    required TournamentGameResult? result,
    required String outcome,
    required String reason,
    required List<PendingTurn> pending,
  }) {
    live.status = result == null ? 'cancelled' : 'finished';
    live.resultLabel =
        result == null ? null : (outcome == '*' ? 'draw' : outcome);
    live.reason = reason;
    for (final turn in pending) {
      turn.flush(
        log: _statsLog,
        gameId: pairing.gameId,
        tournamentId: state.config.id,
      );
    }
    pending.clear();
    logGameResults(
      log: _statsLog,
      gameId: pairing.gameId,
      whiteAgentId: pairing.whiteAgentId,
      blackAgentId: pairing.blackAgentId,
      tournamentId: state.config.id,
      whiteModelKey: _roster[pairing.whiteAgentId]?.model ?? '',
      blackModelKey: _roster[pairing.blackAgentId]?.model ?? '',
      mode: state.config.mode,
      outcome: outcome,
    );
    final eloResult = _eloResult(result);
    if (eloResult != null) {
      _elo.updateAfterGame(
        pairing.whiteAgentId,
        pairing.blackAgentId,
        eloResult,
        mode: state.config.mode,
      );
    }
    // Standard games land in the FEN-based review log; chaotic games land in
    // the lossless variant replay log (board chain + attempts + readings).
    if (state.config.mode == 'standard') {
      _reviewLog.record(
        ReviewGame(
          id: pairing.gameId,
          whiteLabel: live.whiteLabel,
          blackLabel: live.blackLabel,
          whiteAgentId: pairing.whiteAgentId,
          blackAgentId: pairing.blackAgentId,
          mode: state.config.mode,
          ucis: List<String>.of(live.ucis),
          sans: List<String>.of(live.sans),
          fens: List<String>.of(live.fens),
          phrases: List<String?>.of(live.phrases),
          fallbackFlags: List<bool>.of(live.fallbacks),
        ),
      );
    } else {
      final initial = live.initialBoard;
      if (initial != null) {
        _variantReviewLog.record(VariantGameRecord(
          id: pairing.gameId,
          tournamentId: state.config.id,
          whiteLabel: live.whiteLabel,
          blackLabel: live.blackLabel,
          whiteAgentId: pairing.whiteAgentId,
          blackAgentId: pairing.blackAgentId,
          seed: live.seed,
          initialBoard: initial,
          plies: List<VariantPlyRecord>.of(live.variantPlies),
          outcome: outcome,
          reason: reason,
          startedAt: live.startedAt,
          finishedAt: _clock().toUtc(),
        ));
      }
    }
    _touch();
  }

  /// Ping-pong seed for mock scripting/fallback picks (game seed + ply).
  int _turnSeed(int gameSeed, int ply) =>
      (gameSeed + ply * 0x85EBCA6B) & 0x7fffffff;

  /// Renders a [VariantBoard] as the shared LLM prompt state (same format as
  /// the standard orchestrator uses).
  ///
  /// Castling rights come from the board's home-square geometry; en passant is
  /// always `-` because variant boards carry no double-push history.
  ({String board, String castling, String enPassant}) _variantPromptState(
    VariantBoard board,
  ) {
    final rights = board.castlingRights;
    final castling = <String>['K', 'Q', 'k', 'q']
        .where(rights.contains)
        .join();
    return (
      board: renderBoardForPrompt(
        squares: <String, String>{
          for (final e in board.squares.entries)
            e.key.name: promptPieceLetter(
              e.value.type.letter,
              isWhite: e.value.color.isWhite,
            ),
        },
        sideToMove: board.sideToMove.isWhite ? 'white' : 'black',
      ),
      castling: castling.isEmpty ? '-' : castling,
      enPassant: '-',
    );
  }

  /// Renders a [VariantBoard] as a [Chessboard] `squares` map.
  Map<String, String> _variantSquares(VariantBoard board) {
    return <String, String>{
      for (final e in board.squares.entries)
        e.key.name:
            '${colorCode(e.value.color)}${e.value.type.letter}',
    };
  }

  /// Pseudo-legal attempt generator for chaotic boards.
  ///
  /// Deliberately standard-move-shaped: pawn pushes (double from the home
  /// rank, queen on promotion), pawn diagonal captures, knight jumps,
  /// sliding rays (stop at the first blocker, capture enemy), king steps.
  /// No castling and no en passant (variant boards carry no double-push
  /// history) — a documented deviation, and no check filtering, because
  /// illegal attempts are exactly what [ChaoticRules.interpret] resolves.
  /// The list only scripts mock agents with meaningful attempts and gives
  /// the runner an initial legality vocabulary; whatever the model
  /// actually attempts is interpreted as-is.
  List<String> _variantAttempts(VariantBoard board) {
    final out = <String>[];
    final squares = board.squares.keys.toList()..sort();
    for (final sq in squares) {
      final piece = board.pieceAt(sq)!;
      if (piece.color != board.sideToMove) continue;
      switch (piece.type) {
        case PieceType.pawn:
          final step = piece.color.isWhite ? 1 : -1;
          final promoRank = piece.color.isWhite ? 7 : 0;
          final forward = sq.offset(0, step);
          if (forward != null && board.pieceAt(forward) == null) {
            if (forward.rank == promoRank) {
              out.add('${sq.name}${forward.name}q');
            } else {
              out.add('${sq.name}${forward.name}');
              final dbl = sq.offset(0, 2 * step);
              final startRank = piece.color.isWhite ? 1 : 6;
              if (sq.rank == startRank &&
                  dbl != null &&
                  board.pieceAt(dbl) == null) {
                out.add('${sq.name}${dbl.name}');
              }
            }
          }
          for (final df in const <int>[-1, 1]) {
            final capture = sq.offset(df, step);
            if (capture == null) continue;
            final target = board.pieceAt(capture);
            if (target == null || target.color == board.sideToMove) continue;
            out.add(
              '${sq.name}${capture.name}'
              '${capture.rank == promoRank ? 'q' : ''}',
            );
          }
        case PieceType.knight:
          const jumps = <(int, int)>[
            (1, 2),
            (2, 1),
            (2, -1),
            (1, -2),
            (-1, -2),
            (-2, -1),
            (-2, 1),
            (-1, 2),
          ];
          for (final (df, dr) in jumps) {
            final target = sq.offset(df, dr);
            if (target == null) continue;
            final occupant = board.pieceAt(target);
            if (occupant == null || occupant.color != board.sideToMove) {
              out.add('${sq.name}${target.name}');
            }
          }
        case PieceType.bishop:
        case PieceType.rook:
        case PieceType.queen:
          final dirs = switch (piece.type) {
            PieceType.bishop => const <(int, int)>[
              (1, 1),
              (1, -1),
              (-1, -1),
              (-1, 1),
            ],
            PieceType.rook => const <(int, int)>[
              (1, 0),
              (-1, 0),
              (0, 1),
              (0, -1),
            ],
            _ => const <(int, int)>[
              (1, 0),
              (-1, 0),
              (0, 1),
              (0, -1),
              (1, 1),
              (1, -1),
              (-1, -1),
              (-1, 1),
            ],
          };
          for (final (df, dr) in dirs) {
            var cursor = sq;
            while (true) {
              final next = cursor.offset(df, dr);
              if (next == null) break;
              final target = board.pieceAt(next);
              if (target == null) {
                out.add('${sq.name}${next.name}');
                cursor = next;
                continue;
              }
              if (target.color != board.sideToMove) {
                out.add('${sq.name}${next.name}');
              }
              break;
            }
          }
        case PieceType.king:
          for (final neighbor in squareNeighbors(sq)) {
            final occupant = board.pieceAt(neighbor);
            if (occupant == null || occupant.color != board.sideToMove) {
              out.add('${sq.name}${neighbor.name}');
            }
          }
      }
    }
    return out;
  }

  /// Maps an outcome/reason pair to a scheduler result.
  ///
  /// `'*'` with a move-limit/no-attempt reason is a completed draw;
  /// `'*'` from a stop/cancel is "no result" (the scheduler marks the ref
  /// cancelled when the summary carries neither result nor failure).
  TournamentGameResult? _mapOutcome(String outcome, String reason) {
    switch (outcome) {
      case '1-0':
        return TournamentGameResult.whiteWin;
      case '0-1':
        return TournamentGameResult.blackWin;
      case '1/2-1/2':
        return TournamentGameResult.draw;
      default:
        if (reason == 'maxMoves' ||
            reason == 'maxDurationExceeded' ||
            reason == 'noAttempts') {
          return TournamentGameResult.draw;
        }
        return null;
    }
  }

  /// Elo result vocabulary for [TournamentGameResult] (`null` = no update).
  String? _eloResult(TournamentGameResult? result) {
    switch (result) {
      case TournamentGameResult.whiteWin:
        return 'white_win';
      case TournamentGameResult.blackWin:
        return 'black_win';
      case TournamentGameResult.draw:
        return 'draw';
      case null:
        return null;
    }
  }
}

/// Drill-down dialog: full board, move list, status; follows the game.
class _GameDetailDialog extends ConsumerWidget {
  /// Creates a detail dialog for [live].
  const _GameDetailDialog({
    required this.live,
    required this.gameRef,
    required this.ticker,
    required this.tournamentName,
  });

  /// Live snapshot to render.
  final _LiveGame live;

  /// Authoritative scheduler ref (status/result).
  final TournamentGameRef gameRef;

  /// Screen ticker so an open dialog follows a running game.
  final Listenable ticker;

  /// Tournament display name.
  final String tournamentName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardTheme = ref.watch(
      themeRegistryProvider.select((r) => r.boardTheme),
    );
    final pieceTheme = ref.watch(
      themeRegistryProvider.select((r) => r.pieceTheme),
    );
    return ListenableBuilder(
      listenable: ticker,
      builder: (context, _) {
        final theme = Theme.of(context);
        final replay = ref.read(variantReviewLogProvider).byId(
          gameRef.gameId,
        );
        return AlertDialog(
          title: Text(
            '${live.label} · ${live.whiteLabel} vs ${live.blackLabel}',
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Chessboard(
                    squares: live.squares,
                    boardTheme: boardTheme,
                    pieceTheme: pieceTheme,
                    lastFrom: live.lastFrom,
                    lastTo: live.lastTo,
                    inCheck: live.inCheck,
                    terminalSquare: live.terminalSquare,
                    interactive: false,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: <Widget>[
                      StatChip(
                        label: 'Status',
                        value: _gameStatusText(gameRef, live),
                      ),
                      StatChip(
                        label: 'Mode',
                        value: live.mode,
                      ),
                      StatChip(
                        label: 'Seed',
                        value: '${live.seed}',
                      ),
                    ],
                  ),
                  if (live.mode == 'chaotic' &&
                      live.interpretations.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      'Last ply interpreted as: '
                      '${live.interpretations.last}',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                  const SizedBox(height: 12),
                  MoveList(
                    moves: live.sans,
                    currentIndex: live.sans.length - 1,
                    errorPlies: <int>{
                      for (var i = 0; i < live.fallbacks.length; i++)
                        if (live.fallbacks[i]) i,
                    },
                    maxHeight: 240,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tournamentName,
                    style: theme.textTheme.labelSmall,
                  ),
                  Text(
                    'Fallback plies are marked and unattributed. Standard '
                    'moves are SAN; chaotic plies are the attempted UCI '
                    '(the interpretation may have resolved differently).',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            if (replay != null)
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => VariantReplayScreen(record: replay),
                    ),
                  );
                },
                child: const Text('Replay'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}
