/// [WatchScreen]: AI-vs-AI watch room (content-only; `AppShell` hosts it).
///
/// White/black agent selectors (from [agentListProvider]) feed a real
/// [GameOrchestrator] running two AI seats over a real [Position]. The
/// transport buttons drive the orchestrator lifecycle directly
/// (`startGame`/`pause`/`resume`/`stop`); there is no timer and no canned
/// move line:
///
/// * [_pump] is a sequential turn loop: while the orchestrator waits for
///   AI input it binds the side-to-move's catalog config (fresh every turn
///   so setup edits apply live), executes one [GameOrchestrator.requestAiTurn]
///   with a [mockAwareProvider] override, syncs the mirror engine, buffers
///   the runner result for stats, and continues. The [_pumping] flag plus
///   the orchestrator's own `_turnInFlight` rejection guarantee no
///   overlapping turns; pause/resume/stop between turns take effect at the
///   next loop check, and a pause mid-turn is honored when the turn settles.
/// * The mirror board advances only in [_syncBoard], which replays the
///   orchestrator's `moveHistory` tail (idempotent — both the event
///   listener and [_pump] call it). Engine terminals are reported back via
///   [GameOrchestrator.reportTerminal] after [mapTerminal] mapping.
/// * [GameEvent]s map to [ActivityEvent]s via [activityFromGameEvent] for
///   the Activity tab; the Moves tab shows real SANs and the Errors tab
///   shows error-kind events with token/latency totals.
/// * Finished games flush buffered [PendingTurn]s to [StatsLog], write
///   per-agent end markers, and land in [ReviewLog] for the review screen.
/// * Mock agents are scripted per turn with a fresh legal move, so the room
///   runs with zero configuration; real providers run keyless and fall back
///   to seeded random-legal moves with visible attribution.
/// * Stopping or restarting a game with a turn in flight is safe: the old
///   orchestrator is `stop()`ped first (late turns discard against the
///   terminal state without touching listeners — see [retireOrchestrator])
///   and the orphaned [_pump] exits on its identity check.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/agent_runner.dart';
import '../../chess/engine.dart' as chess_eng;
import '../../chess/fen.dart';
import '../../chess/position.dart';
import '../../game/clock.dart';
import '../../game/game_state.dart';
import '../../game/orchestrator.dart';
import '../../theme/registry.dart';
import '../backend_bridge.dart';
import '../game_mirror.dart';
import '../ui_models.dart';
import '../widgets/activity_panel.dart';
import '../widgets/boards.dart';
import '../widgets/board_motion.dart';
import '../widgets/chessboard.dart';
import '../widgets/scrub_shortcuts.dart';

/// Game id used by the watch room's stats/review attribution.
const String kWatchGameId = 'watch-game';

/// AI-vs-AI watch room with selectors, transport controls and telemetry.
class WatchScreen extends ConsumerStatefulWidget {
  /// Creates the watch screen.
  const WatchScreen({super.key, this.initialSeed});

  /// Seed for deterministic mock runs — replaces wall-clock randomness.
  final int? initialSeed;

  @override
  ConsumerState<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends ConsumerState<WatchScreen> {
  /// Wall-clock source (§10.3 seam); tests override via [clockProvider].
  late DateTime Function() _clock;

  /// Mirror engine; advanced only by [_syncBoard] from the orchestrator.
  Position _engine = Position.initial();

  /// SAN history parallel to the orchestrator's UCI history.
  final List<String> _moves = <String>[];

  /// FEN history (`fens[0]` is the start position; one entry per ply + 1).
  List<String> _fens = <String>[standardStartFen];

  /// Agent phrases parallel to the UCI history (`null` for fallbacks).
  final List<String?> _phrases = <String?>[];

  /// Fallback flags parallel to the UCI history.
  final List<bool> _fallbacks = <bool>[];

  /// How many of the orchestrator's UCIs [_engine] has applied.
  int _applied = 0;

  /// Last-move trail.
  String? _lastFrom;
  String? _lastTo;

  /// Most recently applied transition for the board's §15.2 motion layer.
  BoardMove? _lastMotion;

  /// Scrubbed view ply (meaningful only while [_followLive] is false).
  /// See §15.3.
  int _viewPly = 0;

  /// Whether the board follows the live game tail. Stays true until the user
  /// seeks away; new moves then append underneath the pinned view and the
  /// view returns to live only via End / "Return to live position".
  bool _followLive = true;

  /// The ply currently on screen: the live tail while following, otherwise
  /// the pinned [_viewPly].
  int get _effectiveViewPly => _followLive ? _moves.length : _viewPly;

  /// Motion for the scrubbed view — adjacent seek steps only (§15.3).
  BoardMove? _viewMotion;

  /// Selected agent ids (dropdowns); default to the seeded demos.
  String? _whiteId = 'demo-white';
  String? _blackId = 'demo-black';

  /// Streaming activity for the panel.
  final List<ActivityEvent> _events = <ActivityEvent>[];

  /// Error subset of [_events], maintained incrementally so the build never
  /// re-filters the whole stream.
  final List<ActivityEvent> _errors = <ActivityEvent>[];

  /// Presentation revision for the activity panel (see the same field in
  /// play_screen): stream events rebuild only the panel, not the board.
  final ValueNotifier<int> _activityRevision = ValueNotifier<int>(0);

  /// Stats turns buffered until game end.
  final List<PendingTurn> _pending = <PendingTurn>[];

  /// Whether [_finishGame] has run for the current game.
  bool _finished = false;

  /// Bound agent ids/models for end markers (updated per turn).
  String _whiteAgentId = 'demo-white';
  String _blackAgentId = 'demo-black';
  String _whiteModel = 'mock';
  String _blackModel = 'mock';

  /// The live orchestrator (recreated per game; null before first start).
  GameOrchestrator? _orch;

  /// Subscription mapping [GameEvent]s into [_events].
  StreamSubscription<GameEvent>? _sub;

  /// Whether [_pump] is currently executing (reentrancy guard).
  bool _pumping = false;

  /// Last rendered orchestrator state; drives a cheap setState only when the
  /// lifecycle actually changes (so mid-turn status chips stay honest while
  /// stream events no longer repaint the board).
  OrchestratorState? _lastOrchState;

  /// Per-scope stats store (§13 telemetry isolation).
  late final StatsLog _statsLog;

  /// Per-scope review-game store (§13 telemetry isolation).
  late final ReviewLog _reviewLog;

  @override
  void initState() {
    _clock = ref.read(clockProvider);
    _statsLog = ref.read(statsLogProvider);
    _reviewLog = ref.read(reviewLogProvider);
    super.initState();
  }

  @override
  void dispose() {
    unawaited(retireOrchestrator(_orch, _sub));
    _activityRevision.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final boardTheme = ref.watch(
      themeRegistryProvider.select((r) => r.boardTheme),
    );
    final pieceTheme = ref.watch(
      themeRegistryProvider.select((r) => r.pieceTheme),
    );
    final agents = ref.watch(agentListProvider);
    final orch = _orch;
    final viewingLive = _followLive;
    return ScrubShortcuts(
      enabled: _moves.isNotEmpty,
      onAction: _onScrubAction,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: <Widget>[
            _buildSelectors(agents.agents),
            const SizedBox(height: 8),
            _buildTransport(orch),
            const SizedBox(height: 8),
            if (!viewingLive && _moves.isNotEmpty)
              TextButton(
                onPressed: () => _seekViewPly(_moves.length),
                child: const Text('Return to live position'),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: BoardPanelLayout(
                boardLabel: 'Board',
                panelLabel: 'Activity',
                board: Chessboard(
                  squares: viewingLive
                      ? squaresOf(_engine)
                      : squaresOfFen(
                          _fens[_viewPly.clamp(0, _fens.length - 1)],
                        ),
                  orientationWhite: true,
                  lastFrom: _lastFrom,
                  lastTo: _lastTo,
                  inCheck: viewingLive ? checkSquare(_engine) : null,
                  terminalSquare: viewingLive ? _terminalKingSquare() : null,
                  boardTheme: boardTheme,
                  pieceTheme: pieceTheme,
                  motion: viewingLive ? _lastMotion : _viewMotion,
                  interactive: false,
                ),
                panel: ValueListenableBuilder<int>(
                  valueListenable: _activityRevision,
                  builder: (context, _, _) {
                    // Recomputed inside the panel-only builder so the spinner
                    // tracks the live turn without repainting the board.
                    final liveOrch = _orch;
                    final busy =
                        _pumping ||
                        (liveOrch != null &&
                            (liveOrch.state == OrchestratorState.streaming ||
                                liveOrch.state ==
                                    OrchestratorState.validating ||
                                liveOrch.state == OrchestratorState.applying));
                    return DefaultTabController(
                      length: 3,
                      child: Column(
                        children: <Widget>[
                          const TabBar(
                            tabs: <Widget>[
                              Tab(text: 'Activity'),
                              Tab(text: 'Moves'),
                              Tab(text: 'Errors'),
                            ],
                          ),
                          Expanded(
                            child: TabBarView(
                              children: <Widget>[
                                AgentActivityPanel(
                                  // Snapshot so the panel's didUpdateWidget
                                  // length check (autoscroll) sees the growth;
                                  // only copies when the panel rebuilds.
                                  events: List<ActivityEvent>.unmodifiable(
                                    _events,
                                  ),
                                  isThinking: busy,
                                ),
                                SingleChildScrollView(
                                  padding: const EdgeInsets.all(12),
                                  child: MoveList(
                                    moves: _moves,
                                    currentIndex: _effectiveViewPly == 0
                                        ? -1
                                        : _effectiveViewPly - 1,
                                    errorPlies: <int>{
                                      for (
                                        var i = 0;
                                        i < _fallbacks.length;
                                        i++
                                      )
                                        if (_fallbacks[i]) i,
                                    },
                                    onTapMove: (ply) => _seekViewPly(ply + 1),
                                  ),
                                ),
                                _buildErrors(_errors),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// King square of the side to move when the game ended by checkmate
  /// (purple terminal overlay); null otherwise.
  String? _terminalKingSquare() {
    final orch = _orch;
    if (orch == null || !isTerminalOrchestratorState(orch.state)) {
      return null;
    }
    if (!_engine.isCheckmate) return null;
    return _engine.kingSquare(_engine.sideToMove)?.name;
  }

  /// White/black agent dropdowns (disabled while a game is live).
  Widget _buildSelectors(List<AgentConfig> agents) {
    final orch = _orch;
    final locked = orch != null && !isTerminalOrchestratorState(orch.state);
    Widget drop(String? value, ValueChanged<String?> onChanged, String label) {
      return Expanded(
        child: DropdownButtonFormField<String>(
          initialValue: agents.any((a) => a.id == value) ? value : null,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          items: <DropdownMenuItem<String>>[
            for (final a in agents)
              DropdownMenuItem(value: a.id, child: Text(a.name)),
          ],
          onChanged: locked ? null : onChanged,
        ),
      );
    }

    return Row(
      children: <Widget>[
        drop(_whiteId, (v) => setState(() => _whiteId = v), 'White agent'),
        const SizedBox(width: 8),
        drop(_blackId, (v) => setState(() => _blackId = v), 'Black agent'),
      ],
    );
  }

  /// Status chip (real orchestrator state + result) + transport buttons
  /// valid for the current phase + live clocks.
  Widget _buildTransport(GameOrchestrator? orch) {
    final theme = Theme.of(context);
    final terminal = orch == null || isTerminalOrchestratorState(orch.state);
    final paused = orch?.state == OrchestratorState.paused;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Chip(
          avatar: Icon(
            orch?.state == OrchestratorState.failed
                ? Icons.error_outline
                : Icons.sync_outlined,
            size: 16,
          ),
          label: Text(_statusLabel(orch)),
        ),
        Text(
          'Move ${orch?.moveHistory.length ?? 0}',
          style: theme.textTheme.bodySmall,
        ),
        if (orch != null) ...<Widget>[
          Chip(
            label: Text(
              '♔ ${formatClock((orch.clock.remainingW / 1000).ceil())}',
              style: theme.textTheme.bodySmall,
            ),
            visualDensity: VisualDensity.compact,
          ),
          Chip(
            label: Text(
              '♚ ${formatClock((orch.clock.remainingB / 1000).ceil())}',
              style: theme.textTheme.bodySmall,
            ),
            visualDensity: VisualDensity.compact,
          ),
        ],
        if (terminal)
          FilledButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start'),
          ),
        if (!terminal && !paused)
          OutlinedButton.icon(
            onPressed: _pause,
            icon: const Icon(Icons.pause_outlined),
            label: const Text('Pause'),
          ),
        if (paused)
          FilledButton.icon(
            onPressed: _resume,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Resume'),
          ),
        if (!terminal)
          TextButton.icon(
            onPressed: _stop,
            icon: const Icon(Icons.stop_outlined),
            label: const Text('Stop'),
          ),
        if (orch?.failureMessage != null)
          Text(
            orch!.failureMessage!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
      ],
    );
  }

  /// Human-readable label for the orchestrator lifecycle state.
  String _statusLabel(GameOrchestrator? orch) {
    if (orch == null) return 'Idle';
    switch (orch.state) {
      case OrchestratorState.initializing:
        return 'Ready';
      case OrchestratorState.waitingHuman:
        return 'Waiting';
      case OrchestratorState.waitingAi:
        return 'Running';
      case OrchestratorState.streaming:
        return 'Streaming';
      case OrchestratorState.validating:
        return 'Validating';
      case OrchestratorState.applying:
        return 'Applying';
      case OrchestratorState.paused:
        return 'Paused';
      case OrchestratorState.finished:
        final outcome = orch.result?.outcome;
        return 'Finished${outcome == null ? '' : ' · $outcome'}';
      case OrchestratorState.failed:
        return 'Error';
    }
  }

  /// Errors tab: error-kind events plus token/latency totals.
  Widget _buildErrors(List<ActivityEvent> errors) {
    var tokens = 0;
    var latency = 0;
    for (final e in _events) {
      if (e.kind == ActivityEventKind.usage) {
        tokens += (e.promptTokens ?? 0) + (e.completionTokens ?? 0);
      } else if (e.kind == ActivityEventKind.latency) {
        latency += e.latencyMs ?? 0;
      }
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        Wrap(
          spacing: 8,
          children: <Widget>[
            StatChip(
              label: 'Errors',
              value: '${errors.length}',
              icon: Icons.error_outline,
            ),
            StatChip(
              label: 'Tokens',
              value: '$tokens',
              icon: Icons.token_outlined,
            ),
            StatChip(
              label: 'Latency',
              value: '${latency}ms',
              icon: Icons.timer_outlined,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (errors.isEmpty)
          const Text('No errors recorded this game.')
        else
          for (final e in errors)
            Card(
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: Text(e.message),
                subtitle: Text(formatEventTime(e.timestamp)),
              ),
            ),
      ],
    );
  }

  /// Starts a fresh game: retires the old orchestrator, resets the mirror,
  /// starts the clock and kicks [_pump].
  Future<void> _start() async {
    final white = ref.read(agentListProvider).byId(_whiteId);
    final black = ref.read(agentListProvider).byId(_blackId);
    if (white == null || black == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Pick two agents first.')));
      }
      return;
    }
    await retireOrchestrator(_orch, _sub);
    if (!mounted) return;
    _sub = null;
    _engine = Position.initial();
    _moves.clear();
    _fens = <String>[standardStartFen];
    _phrases.clear();
    _fallbacks.clear();
    _applied = 0;
    _lastFrom = null;
    _lastTo = null;
    _lastMotion = null;
    _viewPly = 0;
    _followLive = true;
    _viewMotion = null;
    _events.clear();
    _errors.clear();
    _pending.clear();
    _finished = false;
    _lastOrchState = null;
    _watchSeed =
        widget.initialSeed ?? (_clock().millisecondsSinceEpoch & 0x7fffffff);
    _whiteAgentId = white.id;
    _blackAgentId = black.id;
    _whiteModel = white.model;
    _blackModel = black.model;
    final orch = GameOrchestrator(
      config: const GameConfig(
        mode: GameMode.standard,
        timeControl: TimeControl(
          type: TimeControlType.fixed,
          initialMs: 600000,
        ),
        maxMoves: 200,
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
    orch.setPosition(
      standardStartFen,
      turn: 'w',
      legalMoves: legalUcis(_engine),
    );
    orch.startGame();
    _orch = orch;
    _sub = orch.events.listen(_onEvent);
    if (mounted) setState(() {});
    _pump();
  }

  /// Pauses the clock/turn intake (an in-flight turn still settles).
  void _pause() {
    _orch?.pause();
    if (mounted) setState(() {});
  }

  /// Resumes a paused game and restarts [_pump].
  void _resume() {
    _orch?.resume();
    if (mounted) setState(() {});
    _pump();
  }

  /// Aborts the game without a winner (`'*'` outcome).
  void _stop() {
    _orch?.stop();
    if (mounted) setState(() {});
  }

  /// Maps one orchestrator event into the activity panel, then syncs.
  void _onEvent(GameEvent event) {
    final activity = activityFromGameEvent(event);
    if (activity != null) {
      _addActivity(activity);
    }
    if (event.type == 'moveApplied') {
      _syncBoard();
    } else if (event.type == 'gameFinished' ||
        event.type == 'terminalReported' ||
        event.type == 'resigned' ||
        event.type == 'flagFall') {
      _finishGame();
    } else if (_orch?.state != _lastOrchState) {
      // Lifecycle changed (streaming/validating/…): refresh the status chip
      // once, but do not repaint the board for every stream event.
      _lastOrchState = _orch?.state;
      if (mounted) setState(() {});
    }
  }

  /// Appends [event] to the activity panel (and the error subset) without
  /// rebuilding the board.
  void _addActivity(ActivityEvent event) {
    if (!mounted) return;
    _events.add(event);
    if (event.isError) _errors.add(event);
    _activityRevision.value++;
  }

  /// Replays unapplied orchestrator UCIs onto the mirror engine.
  ///
  /// Idempotent: both [_onEvent] and [_pump] call it. Refreshes the legal
  /// intake after syncing (the orchestrator clears it per move) and
  /// finishes engine-terminal games.
  void _syncBoard() {
    final orch = _orch;
    if (orch == null) return;
    // Shared replay core; the watch-only hooks (legal intake, finish-once)
    // stay in this screen.
    final replay = replayMoves(
      orch: orch,
      engine: _engine,
      applied: _applied,
      onApplied: (index, uci, move, receipt, meta) {
        _moves.add(receipt.san);
        _phrases.add(meta.isFallback ? null : meta.phrase);
        _fallbacks.add(meta.isFallback);
        _fens.add(_engine.toFen());
        _lastFrom = move.from.name;
        _lastTo = move.to.name;
        _lastMotion = BoardMove.fromApplied(receipt);
      },
    );
    _applied = replay.applied;
    if (replay.hasError) {
      _addActivity(
        ActivityEvent(
          kind: ActivityEventKind.error,
          message: 'Mirror sync failed on ${replay.failedUci}: ${replay.error}',
        ),
      );
    }
    if (replay.changed && mounted) {
      setState(() {});
      orch.setPosition(
        _engine.toFen(),
        turn: _engine.sideToMove.isWhite ? 'w' : 'b',
        legalMoves: legalUcis(_engine),
      );
    }
    if (!_finished && chess_eng.ChessRules.resultOf(_engine) != null) {
      _finishGame();
    }
  }

  /// Moves the view cursor for scrubbing (§15.3); the live game keeps
  /// running underneath — only the displayed snapshot changes. Adjacent
  /// steps set [_viewMotion] so the board slides between plies; multi-ply
  /// jumps snap.
  void _seekViewPly(int target) {
    if (_orch == null) return;
    final clamped = target.clamp(0, _moves.length);
    if (clamped == _moves.length && _followLive) return; // already live
    if (!_followLive && clamped == _viewPly) return; // already there
    final motion = _scrubMotionFor(clamped);
    setState(() {
      _followLive = clamped == _moves.length;
      _viewPly = clamped;
      _viewMotion = motion;
    });
  }

  /// Motion value for a scrub step into [target] (`null` snaps); see
  /// [ScrubShortcuts.scrubMotionFor].
  BoardMove? _scrubMotionFor(int target) {
    final orch = _orch;
    if (orch == null) return null;
    final prev = _effectiveViewPly;
    final delta = target - prev;
    if (delta.abs() != 1) return null;
    final ucis = orch.moveHistory;
    if (ucis.isEmpty) return null;
    final index = delta > 0 ? target - 1 : prev - 1;
    if (index < 0 || index >= ucis.length) return null;
    return scrubMotionFor(ucis[index], delta);
  }

  /// Maps scrub key actions onto the view cursor (§15.3).
  void _onScrubAction(ScrubAction action) {
    switch (action) {
      case ScrubAction.stepBack:
        _seekViewPly(_effectiveViewPly - 1);
      case ScrubAction.stepForward:
        _seekViewPly(_effectiveViewPly + 1);
      case ScrubAction.toStart:
        _seekViewPly(0);
      case ScrubAction.toEnd:
        _seekViewPly(_moves.length);
    }
  }

  /// Phrase/fallback metadata for `moveApplied` entry [moveIndex]
  /// (1-based, matches the orchestrator's `moveIndex` payload).
  /// Sequential turn loop: one AI turn at a time until the game ends.
  ///
  /// Exits when the game reaches a terminal state, pauses, leaves the
  /// `waitingAi` state, or the turn is rejected (a stop/pause raced us);
  /// pause/resume/stop controls re-enter via [_resume] or the event
  /// listener. The orchestrator additionally rejects overlapping turns
  /// itself, so at most one turn is ever in flight.
  Future<void> _pump() async {
    final orch = _orch;
    if (_pumping || orch == null) return;
    _pumping = true;
    try {
      while (mounted && identical(_orch, orch)) {
        if (isTerminalOrchestratorState(orch.state)) break;
        if (orch.state == OrchestratorState.paused) break;
        if (orch.state != OrchestratorState.waitingAi) break;
        final color = orch.turn;
        final seatId = color == 'w' ? _whiteId : _blackId;
        final uiAgent = ref.read(agentListProvider).byId(seatId);
        if (uiAgent == null) {
          _addActivity(
            ActivityEvent(
              kind: ActivityEventKind.error,
              message:
                  'No agent selected for ${color == 'w' ? 'White' : 'Black'}.',
            ),
          );
          break;
        }
        final backend = toBackendAgent(uiAgent);
        orch.bindAgent(backend);
        if (color == 'w') {
          _whiteAgentId = backend.id;
          _whiteModel = backend.model;
        } else {
          _blackAgentId = backend.id;
          _blackModel = backend.model;
        }
        _syncBoard();
        if (!mounted || !identical(_orch, orch)) return;
        if (orch.legalMoves.isEmpty) break;
        final before = orch.moveHistory.length;
        final provider = await ref.read(turnProviderFactoryProvider)(
          backend,
          orch.legalMoves,
          seed: _turnSeed(before),
          phrase: '${uiAgent.name} move',
        );
        AgentTurnResult? result;
        try {
          result = await orch.requestAiTurn(color, providerOverride: provider);
        } catch (e) {
          _addActivity(
            ActivityEvent(
              kind: ActivityEventKind.error,
              message: 'AI turn crashed: $e',
            ),
          );
          break;
        } finally {
          closeProvider(provider);
        }
        if (!mounted || !identical(_orch, orch)) return;
        if (result == null) break; // Rejected (pause/stop raced us).
        final grew = orch.moveHistory.length > before;
        _pending.add(
          PendingTurn.ai(
            agentId: backend.id,
            modelKey: backend.model,
            color: color == 'w' ? 'white' : 'black',
            mode: 'standard',
            result: result,
            fallback: grew && !result.isSuccess,
          ),
        );
        _syncBoard();
        if (mounted) setState(() {});
      }
    } catch (e) {
      // The pump runs fire-and-forget; never let a provider/dispatch error
      // escape as an unhandled async error (which would leave the board
      // silently idle).
      _addActivity(
        ActivityEvent(
          kind: ActivityEventKind.error,
          message: 'Watch loop failed: $e',
        ),
      );
    } finally {
      _pumping = false;
      // A Stop→Start (or any game replacement) can retire `orch` while this
      // loop still owns the guard, in which case the replacement's kick-off
      // `_pump()` was dropped at the `_pumping` check and the new game would
      // sit idle until the user paused/resumed. Hand the guard over.
      if (mounted && !identical(_orch, orch)) {
        unawaited(_pump());
      }
      if (mounted) setState(() {});
    }
  }

  /// Deterministic per-ply seed for mock scripting (game seed + ply).
  int _turnSeed(int ply) {
    return (_watchSeed + ply * 0x85EBCA6B) & 0x7fffffff;
  }

  /// Game seed, refreshed per game start for reproducible mock lines.
  int _watchSeed = 0;

  /// Finishes the game: records the result, flushes stats, logs review.
  ///
  /// Runs once ([_finished]); a stopped/aborted (`'*'`) game still flushes
  /// its played turns and records a partial review, but writes no W/L/D
  /// markers (an abandoned game is not evidence of skill).
  void _finishGame() {
    if (_finished || _orch == null) return;
    final orch = _orch!;
    var outcome = orch.result?.outcome;
    if (outcome == null) {
      final terminal = chess_eng.ChessRules.resultOf(_engine);
      if (terminal == null) return;
      final mapped = mapTerminal(terminal);
      orch.reportTerminal(
        gameResult(
          outcome: mapped.outcome,
          reason: mapped.reason,
          winnerColor: mapped.winnerColor,
        ),
      );
      outcome = mapped.outcome;
    }
    _finished = true;
    final scored = outcome;
    for (final turn in _pending) {
      turn.flush(log: _statsLog, gameId: kWatchGameId);
    }
    _pending.clear();
    final agents = ref.read(agentListProvider);
    logGameResults(
      log: _statsLog,
      gameId: kWatchGameId,
      whiteAgentId: _whiteAgentId,
      blackAgentId: _blackAgentId,
      whiteModelKey: _whiteModel,
      blackModelKey: _blackModel,
      mode: 'standard',
      outcome: scored,
    );
    _reviewLog.record(
      ReviewGame(
        id: '$kWatchGameId-${_clock().millisecondsSinceEpoch}',
        whiteLabel: agents.byId(_whiteAgentId)?.name ?? 'White',
        blackLabel: agents.byId(_blackAgentId)?.name ?? 'Black',
        whiteAgentId: _whiteAgentId,
        blackAgentId: _blackAgentId,
        ucis: orch.moveHistory,
        sans: List<String>.of(_moves),
        fens: List<String>.of(_fens),
        phrases: List<String?>.of(_phrases),
        fallbackFlags: List<bool>.of(_fallbacks),
      ),
    );
    if (mounted) setState(() {});
  }
}
