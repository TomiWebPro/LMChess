/// [PlayScreen]: human (White) vs AI (Black) over a live board.
///
/// Content-only widget hosted by `AppShell`/routes. Layout pairs a top
/// [PlayerCard] (AI), the [Chessboard], a bottom [PlayerCard] (human) and a
/// [BoardPanelLayout] side panel with **Activity** (streaming
/// [AgentActivityPanel]) and **Moves** ([MoveList] + heuristic [EvalBar] +
/// resign/new-game) tabs — so medium widths automatically get the
/// board+activity tab treatment per the responsive rule.
///
/// Real wiring (no demo stubs):
///
/// * The board mirrors a real [Position] (perft-verified move generation:
///   selection highlights come from `Position.legalMoves(forSquare:)`, so
///   check, pins, en passant and castling are enforced by the engine).
/// * Every move flows through a real [GameOrchestrator] (human White seat +
///   bound AI Black seat, authoritative clock, `positionUpdater:
///   fenAdvance`, persist-then-broadcast [GameEvent] log). Human taps call
///   [GameOrchestrator.applyHumanMove]; the AI side runs
///   [GameOrchestrator.requestAiTurn] with a `providerOverride` from
///   [mockAwareProvider] — mock agents get a fresh legal move per turn, and
///   the full [AgentRunner] validation + seeded-fallback path still runs.
/// * [GameEvent]s map to [ActivityEvent]s via [activityFromGameEvent] for
///   the panel. The local board never applies moves itself: [_syncBoard]
///   replays the orchestrator's `moveHistory` tail onto the mirror engine,
///   so UI and backend can never diverge (both the event listener and the
///   post-turn continuation call it; it is idempotent).
/// * At most one AI turn runs at a time ([_aiInFlight] guard mirrors the
///   orchestrator's `_turnInFlight` rejection on the UI side).
/// * Terminal positions come from [ChessRules.resultOf] mapped through
///   [mapTerminal] into [GameOrchestrator.reportTerminal]. Stats turns are
///   buffered as [PendingTurn]s and flushed to [StatsLog] only at game end
///   (undone/abandoned moves never pollute aggregates); finished games are
///   recorded to [ReviewLog] for the review screen.
/// * There is deliberately **no undo**: the orchestrator log is append-only
///   (`moveApplied` has no inverse), so retracting a round would fork the
///   UI mirror from the backend. Use New game to restart.
/// * Promotion shows the standard Q/R/B/N [promotionDialog]; resign asks
///   for confirmation and calls `orchestrator.resign('w')`.
/// * Premoves (§15.4): while the AI is thinking the human can queue up to
///   five moves (click-click or drag) validated in sequence against the
///   current position; they execute one at a time through the normal
///   human-move path once the AI reply lands. Right-click removes the last
///   premove, Escape / the Clear control empties the queue, and promotion
///   premoves default to queen with no dialog.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../chess/engine.dart' as chess_eng;
import '../../chess/fen.dart';
import '../../chess/piece.dart';
import '../../chess/position.dart';
import '../../chess/square.dart';
import '../../game/clock.dart';
import '../../game/game_state.dart';
import '../../game/orchestrator.dart';
import '../../theme/piece_theme.dart';
import '../../theme/registry.dart';
import '../backend_bridge.dart';
import '../game_mirror.dart';
import '../premove.dart';
import '../ui_models.dart';
import '../widgets/activity_panel.dart';
import '../widgets/boards.dart';
import '../widgets/board_motion.dart';
import '../widgets/chessboard.dart';
import '../widgets/scrub_shortcuts.dart';

/// Game id used for stats/review attribution of the play room.
const String kPlayGameId = 'play-game';

/// Fixed AI seat for the play room (bound per turn from the catalog).
const String kPlayAiAgentId = 'demo-black';

/// Human (White) vs AI (Black) play surface.
class PlayScreen extends ConsumerStatefulWidget {
  /// Creates the play screen.
  const PlayScreen({super.key, this.initialFen});

  /// Starting FEN for testing — skips the first ~40 normal moves.
  final String? initialFen;

  @override
  ConsumerState<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends ConsumerState<PlayScreen> {
  /// Mirror engine; only ever advanced by [_syncBoard] from the
  /// orchestrator's authoritative `moveHistory`.
  Position _engine = Position.initial();

  /// SAN history parallel to the orchestrator's UCI history.
  final List<String> _sans = <String>[];

  /// FEN history (`fens[0]` is the start position; one entry per ply + 1).
  List<String> _fens = <String>[standardStartFen];

  /// Agent phrases parallel to the UCI history (`null` for human moves
  /// and unattributed fallbacks).
  final List<String?> _phrases = <String?>[];

  /// Fallback flags parallel to the UCI history.
  final List<bool> _fallbacks = <bool>[];

  /// How many of the orchestrator's UCIs [_engine] has applied.
  int _applied = 0;

  /// Viewed ply for tap-to-seek (`_sans.length` = live).
  int _viewPly = 0;

  /// Selected square, if the human has one picked up.
  String? _selected;

  /// Engine-legal targets for [_selected].
  List<String> _legal = const <String>[];

  /// Last-move trail.
  String? _lastFrom;
  String? _lastTo;

  /// Most recently applied transition, fed to the board's §15.2 motion
  /// layer when the snapshot is live (null while seeking).
  BoardMove? _lastMotion;

  /// Motion for the current scrubbed view (§15.3): non-null only for
  /// adjacent seek steps, so a scrubbed board slides between plies.
  BoardMove? _viewMotion;

  /// Game result (`'1-0'`, `'0-1'`, `'1/2-1/2'`); non-null ends input.
  String? _result;

  /// Streaming activity for the side panel.
  final List<ActivityEvent> _events = <ActivityEvent>[];

  /// Presentation revision for the activity panel.
  ///
  /// Bumped whenever an event is appended so only the panel subtree rebuilds
  /// — streaming turns no longer repaint the 64-square board.
  final ValueNotifier<int> _activityRevision = ValueNotifier<int>(0);

  /// Visible AI-turn error (with a retry), e.g. a turn that produced no move.
  String? _aiError;

  /// Whether an AI turn is in flight (footer spinner).
  bool _thinking = false;

  /// UI-side reentrancy guard (mirrors the orchestrator's turn guard).
  bool _aiInFlight = false;

  /// Stats turns buffered until game end (undo-less but abandon-safe).
  final List<PendingTurn> _pending = <PendingTurn>[];

  /// Agent id / model actually bound for Black (for end markers).
  String _blackAgentId = kPlayAiAgentId;
  String _blackModel = 'mock';

  /// Queued premoves (§15.4), played one per human turn after the AI reply.
  final List<PremoveAttempt> _premoves = <PremoveAttempt>[];

  /// Brief visual explanation shown when the leading premove was discarded
  /// together with everything queued after it.
  String? _premoveNotice;

  /// The live orchestrator (recreated per game).
  GameOrchestrator? _orch;

  /// Subscription mapping [GameEvent]s into [_events].
  StreamSubscription<GameEvent>? _sub;

  /// Per-scope stats store (§13 telemetry isolation).
  late final StatsLog _statsLog;

  /// Per-scope review-game store (§13 telemetry isolation).
  late final ReviewLog _reviewLog;

  @override
  void initState() {
    super.initState();
    _statsLog = ref.read(statsLogProvider);
    _reviewLog = ref.read(reviewLogProvider);
    _newGame();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _orch?.dispose();
    _activityRevision.dispose();
    // No stale queue state may outlive the screen (§15.4: clear on dispose).
    _premoves.clear();
    _premoveNotice = null;
    super.dispose();
  }

  /// Creates a fresh engine mirror + orchestrator and starts the game.
  void _newGame() {
    _sub?.cancel();
    _orch?.dispose();
    final startFen = widget.initialFen ?? standardStartFen;
    _engine = parseFen(startFen);
    _sans.clear();
    _fens = <String>[startFen];
    _phrases.clear();
    _fallbacks.clear();
    _applied = 0;
    _viewPly = 0;
    _selected = null;
    _legal = const <String>[];
    _lastFrom = null;
    _lastTo = null;
    _lastMotion = null;
    _viewMotion = null;
    _result = null;
    _events.clear();
    _thinking = false;
    _aiInFlight = false;
    _aiError = null;
    _pending.clear();
    _premoves.clear();
    _premoveNotice = null;
    _blackAgentId = kPlayAiAgentId;
    _blackModel = 'mock';
    final orch = GameOrchestrator(
      config: const GameConfig(
        mode: GameMode.standard,
        timeControl: TimeControl(
          type: TimeControlType.fixed,
          initialMs: 600000,
        ),
        maxMoves: 200,
      ),
      white: const GameParticipant(label: 'You', isHuman: true),
      black: const GameParticipant(
        agentConfigId: kPlayAiAgentId,
        label: 'AI Opponent',
        isHuman: false,
      ),
      positionUpdater: fenAdvance,
    );
    orch.setPosition(startFen, turn: 'w', legalMoves: legalUcis(_engine));
    orch.startGame();
    _orch = orch;
    _sub = orch.events.listen(_onEvent);
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
    }
    // No whole-screen refresh here: activity rows rebuild through
    // [_activityRevision] and board changes flow through [_syncBoard], so
    // high-frequency stream events no longer repaint the board.
  }

  /// Appends [event] to the activity panel without rebuilding the board.
  void _addActivity(ActivityEvent event) {
    if (!mounted) return;
    _events.add(event);
    _activityRevision.value++;
  }

  /// Replays unapplied orchestrator UCIs onto the mirror engine.
  ///
  /// Idempotent: both [_onEvent] and the post-turn continuation call it.
  /// After syncing it either finishes terminal games or fires the AI
  /// reply when it is Black's turn.
  void _syncBoard() {
    final orch = _orch;
    if (orch == null) return;
    // Shared replay core: parse/apply/metadata only. The play-specific hooks
    // (cursor reset, legal intake, AI reply) stay here.
    final replay = replayMoves(
      orch: orch,
      engine: _engine,
      applied: _applied,
      onApplied: (index, uci, move, receipt, meta) {
        _sans.add(receipt.san);
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
      setState(() {
        _viewPly = _sans.length;
        _selected = null;
        _legal = const <String>[];
        _viewMotion = null;
      });
      // Fresh legal intake for the next turn (required: the orchestrator
      // clears its legal list on every applied move).
      orch.setPosition(
        _engine.toFen(),
        turn: _engine.sideToMove.isWhite ? 'w' : 'b',
        legalMoves: legalUcis(_engine),
      );
    }
    if (_result != null) return;
    if (chess_eng.ChessRules.resultOf(_engine) != null) {
      _finishGame();
    } else if (orch.turn == 'b' && orch.state == OrchestratorState.waitingAi) {
      _requestAiTurn();
    } else if (_premoves.isNotEmpty &&
        orch.turn == 'w' &&
        orch.state == OrchestratorState.waitingHuman) {
      // Human turn arrived with queued premoves: play them one at a time
      // through the normal human-move path (§15.4). Each application flips
      // the turn back to Black, which requests exactly one AI reply.
      _executePremoves();
    }
  }

  /// Phrase/fallback metadata for `moveApplied` entry [moveIndex]
  /// (1-based, matches the orchestrator's `moveIndex` payload).
  @override
  Widget build(BuildContext context) {
    final boardTheme = ref.watch(
      themeRegistryProvider.select((r) => r.boardTheme),
    );
    final pieceTheme = ref.watch(
      themeRegistryProvider.select((r) => r.pieceTheme),
    );
    final aiAgent = ref.watch(
      agentListProvider.select((s) => s.byId(kPlayAiAgentId)),
    );
    final viewingLive = _viewPly == _sans.length;
    final position = viewingLive
        ? squaresOf(_engine)
        : squaresOfFen(_fens[_viewPly.clamp(0, _fens.length - 1)]);
    final orch = _orch;
    final whiteActive = _result == null && (orch?.turn == 'w') && viewingLive;
    final blackActive = _result == null && (orch?.turn == 'b') && viewingLive;
    return ScrubShortcuts(
      enabled: _orch != null,
      onAction: _onScrubAction,
      onEscape: _premoves.isEmpty ? null : _clearPremoves,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: <Widget>[
            PlayerCard(
              name: 'AI Opponent',
              subtitle: aiAgent == null
                  ? _blackModel
                  : '${aiAgent.summary} · t=${aiAgent.temperature.toStringAsFixed(2)}',
              clockSeconds: orch == null
                  ? null
                  : (orch.clock.remainingB / 1000).ceil(),
              isActive: blackActive,
              isWhite: false,
            ),
            const SizedBox(height: 8),
            if (_result != null) _buildResultBanner(),
            if (_aiError != null && _result == null) _buildAiErrorBanner(),
            Expanded(
              child: BoardPanelLayout(
                boardLabel: 'Board',
                panelLabel: 'Activity',
                board: Chessboard(
                  squares: position,
                  orientationWhite: true,
                  selected: viewingLive ? _selected : null,
                  lastFrom: _lastFrom,
                  lastTo: _lastTo,
                  legalTargets: viewingLive ? _legal : const <String>[],
                  inCheck: viewingLive ? checkSquare(_engine) : null,
                  boardTheme: boardTheme,
                  pieceTheme: pieceTheme,
                  onTapSquare: _result == null && viewingLive ? _onTap : null,
                  canDragSquare: (square) => viewingLive && _isOwnPiece(square),
                  onMoveAttempt: (from, to) {
                    if (_premoveWindow) {
                      _queuePremove(from, to);
                    } else {
                      unawaited(_attemptMove(from, to));
                    }
                  },
                  onRightClick: _premoveWindow && _premoves.isNotEmpty
                      ? _removeLastPremove
                      : null,
                  premoves: _premoveWindow
                      ? <BoardPremove>[
                          for (final p in _premoves)
                            BoardPremove(
                              from: p.from,
                              to: p.to,
                              promotion: p.promotion,
                            ),
                        ]
                      : const <BoardPremove>[],
                  motion: viewingLive ? _lastMotion : _viewMotion,
                ),
                panel: ValueListenableBuilder<int>(
                  valueListenable: _activityRevision,
                  builder: (context, _, _) => DefaultTabController(
                    length: 2,
                    child: Column(
                      children: <Widget>[
                        const TabBar(
                          tabs: <Widget>[
                            Tab(text: 'Activity'),
                            Tab(text: 'Moves'),
                          ],
                        ),
                        Expanded(
                          child: TabBarView(
                            children: <Widget>[
                              AgentActivityPanel(
                                events: _events,
                                isThinking: _thinking,
                              ),
                              _buildMovesPanel(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_premoves.isNotEmpty || _premoveNotice != null) ...[
              const SizedBox(height: 8),
              _buildPremoveBar(),
            ],
            const SizedBox(height: 8),
            PlayerCard(
              name: 'You',
              subtitle: 'Human · White',
              clockSeconds: orch == null
                  ? null
                  : (orch.clock.remainingW / 1000).ceil(),
              isActive: whiteActive,
              isHuman: true,
            ),
          ],
        ),
      ),
    );
  }

  /// Result banner shown once the game ends.
  Widget _buildResultBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Theme.of(context).colorScheme.tertiaryContainer,
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.flag_outlined),
          const SizedBox(width: 8),
          Expanded(child: Text('Game over · $_result')),
          TextButton(
            key: const ValueKey<String>('play-new-game-banner'),
            onPressed: () => setState(_newGame),
            child: const Text('New game'),
          ),
        ],
      ),
    );
  }

  /// Visible error banner for an AI turn that produced no move, with retry.
  ///
  /// Mirrors the watch room's inline failure text; without this the error
  /// would only be visible on the Activity tab.
  Widget _buildAiErrorBanner() {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.errorContainer,
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _aiError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          TextButton(
            key: const ValueKey<String>('play-retry-ai'),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.onErrorContainer,
            ),
            onPressed: _requestAiTurn,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  /// Moves tab: heuristic eval bar, SAN list with tap-to-seek, controls.
  Widget _buildMovesPanel() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          EvalBar(score: _materialPawns(_engine), isHeuristic: true),
          const SizedBox(height: 8),
          MoveList(
            moves: _sans,
            currentIndex: _viewPly - 1,
            errorPlies: <int>{
              for (var i = 0; i < _fallbacks.length; i++)
                if (_fallbacks[i]) i,
            },
            onTapMove: (ply) => _seekViewPly(ply + 1),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey<String>('play-new-game-button'),
                  onPressed: _result != null ? null : () => setState(_newGame),
                  icon: const Icon(Icons.refresh_outlined),
                  label: const Text('New game'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey<String>('play-resign-button'),
                  onPressed: _result != null ? null : _confirmResign,
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('Resign'),
                ),
              ),
            ],
          ),
          if (_viewPly != _sans.length)
            TextButton(
              onPressed: () => _seekViewPly(_sans.length),
              child: const Text('Return to live position'),
            ),
        ],
      ),
    );
  }

  /// Board tap handler: select own piece (engine-legal targets), then
  /// move / capture / reselect. While the AI is thinking (§15.4) taps
  /// instead queue premoves through [_onPremoveTap].
  Future<void> _onTap(String square) async {
    final orch = _orch;
    if (_result != null || orch == null) return;
    if (orch.turn != 'w') {
      _onPremoveTap(square);
      return;
    }
    // Tapped a legal destination → move (promotion dialog at the end rank).
    if (_selected != null && _legal.contains(square)) {
      await _attemptMove(_selected!, square);
      return;
    }
    // Tapped own (white) piece → select with engine-legal targets.
    final tapped = Square.tryParse(square);
    final occupant = tapped == null ? null : _engine.pieceAt(tapped);
    if (occupant != null && occupant.color.isWhite) {
      final targets = <String>[
        for (final m in _engine.legalMoves(forSquare: tapped!)) m.to.name,
      ];
      setState(() {
        _selected = square;
        _legal = targets;
      });
      return;
    }
    // Anything else clears the selection.
    setState(() {
      _selected = null;
      _legal = const <String>[];
    });
  }

  /// Moves the view cursor for scrubbing (§15.3).
  ///
  /// The live game keeps running underneath; only the displayed snapshot
  /// changes. Adjacent steps set [_viewMotion] so the board slides between
  /// plies; multi-ply jumps snap (see [_scrubMotionFor]).
  void _seekViewPly(int target) {
    if (_orch == null) return;
    final clamped = target.clamp(0, _sans.length);
    if (clamped == _viewPly) return;
    final motion = _scrubMotionFor(clamped);
    setState(() {
      _viewPly = clamped;
      _selected = null;
      _legal = const <String>[];
      _viewMotion = motion;
    });
  }

  /// Motion value for a scrub step into [target] (`null` snaps).
  ///
  /// Adjacent steps animate through the §15.2 layer — forward slides the
  /// move's piece, backward slides it back (reversed from/to pair) — while
  /// anything larger returns `null`, so a burst of scrubbing never animates
  /// dozens of intermediate plies (§15.3 large-jump budget rule).
  BoardMove? _scrubMotionFor(int target) {
    final orch = _orch;
    if (orch == null) return null;
    final delta = target - _viewPly;
    if (delta.abs() != 1) return null;
    final ucis = orch.moveHistory;
    final int index;
    if (delta > 0) {
      if (target - 1 < 0 || target - 1 >= ucis.length) return null;
      index = target - 1;
    } else {
      if (_viewPly - 1 < 0 || _viewPly - 1 >= ucis.length) return null;
      index = _viewPly - 1;
    }
    return scrubMotionFor(ucis[index], delta);
  }

  /// Maps scrub key actions onto the view cursor (§15.3).
  void _onScrubAction(ScrubAction action) {
    switch (action) {
      case ScrubAction.stepBack:
        _seekViewPly(_viewPly - 1);
      case ScrubAction.stepForward:
        _seekViewPly(_viewPly + 1);
      case ScrubAction.toStart:
        _seekViewPly(0);
      case ScrubAction.toEnd:
        _seekViewPly(_sans.length);
    }
  }

  /// Attempts a human move from [from] to [to], shared by the click-click tap
  /// path and board drag-and-drop (§15.1).
  ///
  /// Validates against the engine (the board is only a view), asks for a
  /// promotion piece when a pawn reaches the last rank, and applies through
  /// [_applyHumanMove]. A cancelled promotion dialog leaves the position
  /// untouched, which is what a cancelled drag drop needs. While the view is
  /// scrubbed back into the past (§15.3) the board is read-only, so moves are
  /// rejected before validation.
  Future<void> _attemptMove(String from, String to) async {
    final orch = _orch;
    if (_result != null ||
        orch == null ||
        orch.turn != 'w' ||
        _viewPly != _sans.length) {
      return;
    }
    final fromSq = Square.tryParse(from);
    if (fromSq == null) return;
    final legal = _engine
        .legalMoves(forSquare: fromSq)
        .any((m) => m.to.name == to);
    if (!legal) return;
    final occupant = _engine.pieceAt(fromSq);
    String? promotion;
    if (occupant != null &&
        occupant.type == PieceType.pawn &&
        Square.fromName(to).rank == 7) {
      promotion = await promotionDialog(context, isWhite: true);
      if (promotion == null || !mounted) return;
    }
    _applyHumanMove(from, to, promotion);
  }

  /// Whether [square] holds a piece the human may pick up (White).
  ///
  /// Passed to the board so drag-to-move cannot start on an opponent piece;
  /// the board's click path already enforces this through [_onTap].
  bool _isOwnPiece(String square) {
    final tapped = Square.tryParse(square);
    final occupant = tapped == null ? null : _engine.pieceAt(tapped);
    return occupant != null && occupant.color.isWhite;
  }

  /// True while the premove window is open (§15.4): the game is live, the
  /// view is on the live position, no result, and it is NOT the human's
  /// (White) turn — the AI is thinking or about to move.
  bool get _premoveWindow {
    final orch = _orch;
    return orch != null &&
        _result == null &&
        _viewPly == _sans.length &&
        orch.turn != 'w';
  }

  /// The live position with all queued premoves applied as White moves —
  /// the reference for queue-time legality and premove target dots.
  Position get _premoveSimulation =>
      premoveSimulation(_engine, _premoves, color: PieceColor.white);

  /// Board-tap handling during the AI's turn (§15.4 premove window): a
  /// White piece selects it (legal targets shown from the simulation), a
  /// legal destination for the selected piece queues a premove, the same
  /// square again deselects, anything else clears the selection.
  void _onPremoveTap(String square) {
    if (!_premoveWindow) return;
    if (_selected == square) {
      setState(() {
        _selected = null;
        _legal = const <String>[];
      });
      return;
    }
    final tapped = Square.tryParse(square);
    final occupant = tapped == null ? null : _engine.pieceAt(tapped);
    if (occupant != null && occupant.color.isWhite) {
      final sim = _premoveSimulation;
      final targets = <String>[
        for (final move in sim.legalMoves(forSquare: tapped!)) move.to.name,
      ];
      setState(() {
        _selected = square;
        _legal = targets;
      });
      return;
    }
    if (_selected != null) {
      _queuePremove(_selected!, square);
      return;
    }
    setState(() {
      _selected = null;
      _legal = const <String>[];
    });
  }

  /// Queues [from]→[to] as a premove, shared by the click-click and drag
  /// paths. Validated in sequence against the already-queued premoves;
  /// promotion premoves default to queen (never a blocking dialog while
  /// the opponent thinks). Silently rejects illegal taps and the queue cap.
  void _queuePremove(String from, String to) {
    if (!_premoveWindow) return;
    if (_premoves.length >= kMaxPremoves) return;
    final promotion = isPromotionMove(_engine, from, to, PieceColor.white)
        ? 'q'
        : null;
    if (!isLegalPremove(
      _premoveSimulation,
      from,
      to,
      promotion: promotion,
      color: PieceColor.white,
    )) {
      return;
    }
    setState(() {
      _premoves.add(PremoveAttempt(from: from, to: to, promotion: promotion));
      _selected = null;
      _legal = const <String>[];
      _premoveNotice = null;
    });
  }

  /// Plays queued premoves one at a time through the normal human-move path
  /// (§15.4), invoked when the human turn arrives with a non-empty queue.
  ///
  /// The leading premove is re-validated against the LIVE position — the AI
  /// reply may have made it illegal — and the first illegal premove is
  /// discarded together with everything queued after it (brief notice). Each
  /// legal premove applies exactly once via [_applyHumanMove], so the
  /// orchestrator requests exactly one AI turn per applied premove.
  void _executePremoves() {
    final orch = _orch;
    if (orch == null || _result != null || orch.turn != 'w') return;
    if (_premoves.isEmpty) return;
    final head = _premoves.first;
    if (!isLegalPremove(
      _engine,
      head.from,
      head.to,
      promotion: head.promotion,
      color: PieceColor.white,
    )) {
      setState(() {
        _premoveNotice =
            'Illegal premove ${head.from}-${head.to} was discarded.';
        _premoves.clear();
        _selected = null;
        _legal = const <String>[];
      });
      return;
    }
    setState(() {
      _premoves.removeAt(0);
    });
    _applyHumanMove(head.from, head.to, head.promotion);
  }

  /// Removes the last queued premove (right-click).
  void _removeLastPremove() {
    if (_premoves.isEmpty) return;
    setState(() => _premoves.removeLast());
  }

  /// Empties the whole premove queue and clears the discard notice
  /// (Escape / the Clear premoves control).
  void _clearPremoves() {
    if (_premoves.isEmpty && _premoveNotice == null) return;
    setState(() {
      _premoves.clear();
      _premoveNotice = null;
      _selected = null;
      _legal = const <String>[];
    });
  }

  /// Premove status row: “N premoves” chip, Clear control, and the brief
  /// discard notice (§15.4).
  Widget _buildPremoveBar() {
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        if (_premoves.isNotEmpty) ...[
          Chip(
            key: const ValueKey<String>('play-premove-chip'),
            avatar: const Icon(Icons.schedule_outlined, size: 18),
            label: Text(
              '${_premoves.length} '
              '${_premoves.length == 1 ? 'premove' : 'premoves'}',
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            key: const ValueKey<String>('play-clear-premoves'),
            onPressed: _clearPremoves,
            icon: const Icon(Icons.clear_all_outlined, size: 18),
            label: const Text('Clear premoves'),
          ),
        ],
        if (_premoveNotice != null) ...[
          if (_premoves.isNotEmpty) const SizedBox(width: 8),
          Expanded(
            child: Text(
              _premoveNotice!,
              key: const ValueKey<String>('play-premove-notice'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Applies the human's move through the orchestrator.
  ///
  /// The board sync + AI reply happen in [_syncBoard] once the
  /// `moveApplied` event lands; rejections surface as a snackbar and leave
  /// the position untouched.
  void _applyHumanMove(String from, String to, String? promotion) {
    final orch = _orch;
    if (orch == null || _result != null) return;
    final uci = '$from$to${promotion == null ? '' : promotion.toLowerCase()}';
    final ok = orch.applyHumanMove(uci);
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Move rejected by the game.')),
        );
      }
      return;
    }
    _pending.add(PendingTurn.human(mode: 'standard'));
    setState(() {
      _selected = null;
      _legal = const <String>[];
    });
  }

  /// Runs one Black AI turn (guarded against overlap).
  ///
  /// The agent config is rebound from the catalog every turn so setup
  /// edits apply immediately; [mockAwareProvider] scripts mock turns with
  /// a fresh legal move. The applied move (or seeded fallback) lands via
  /// [_syncBoard]; the runner result is buffered for end-of-game stats.
  Future<void> _requestAiTurn() async {
    final orch = _orch;
    if (orch == null || _aiInFlight || _result != null || orch.turn != 'b') {
      return;
    }
    _aiInFlight = true;
    if (mounted) {
      setState(() {
        _thinking = true;
        _aiError = null;
      });
    }
    try {
      final uiAgent =
          ref.read(agentListProvider).byId(kPlayAiAgentId) ??
          AgentConfig(
            id: kPlayAiAgentId,
            name: 'Mock Opponent',
            provider: 'mock',
            model: 'mock',
          );
      final backend = toBackendAgent(uiAgent);
      orch.bindAgent(backend);
      _blackAgentId = backend.id;
      _blackModel = backend.model;
      final before = orch.moveHistory.length;
      final provider = await ref.read(turnProviderFactoryProvider)(
        backend,
        orch.legalMoves,
        phrase: '${uiAgent.name} reply',
      );
      try {
        final result = await orch.requestAiTurn(
          'b',
          providerOverride: provider,
        );
        // A "New game" may have replaced the orchestrator while this turn was
        // in flight; bail out before touching the new game's state.
        if (!mounted || !identical(_orch, orch)) return;
        if (result != null) {
          final grew = orch.moveHistory.length > before;
          _pending.add(
            PendingTurn.ai(
              agentId: backend.id,
              modelKey: backend.model,
              color: 'black',
              mode: 'standard',
              result: result,
              fallback: grew && !result.isSuccess,
            ),
          );
          if (!grew) {
            final message =
                'AI turn produced no move (${result.outcome.kind.name}).';
            _addActivity(
              ActivityEvent(kind: ActivityEventKind.error, message: message),
            );
            if (mounted) setState(() => _aiError = message);
          }
        }
        // The moveApplied listener may not have run yet; sync directly.
        _syncBoard();
      } finally {
        closeProvider(provider);
      }
    } catch (e) {
      // This turn is started fire-and-forget (move dispatch and button); a
      // thrown provider/resolve error must surface in the UI, not escape as
      // an unhandled async error.
      if (mounted && identical(_orch, orch)) {
        final message = 'AI turn crashed: $e';
        _addActivity(
          ActivityEvent(kind: ActivityEventKind.error, message: message),
        );
        setState(() => _aiError = message);
      }
    } finally {
      // Only clear the flags if this turn still belongs to the live game; a
      // stale turn settling after "New game" must not hide the new spinner or
      // release the new game's reentrancy guard.
      if (mounted && identical(_orch, orch)) {
        _aiInFlight = false;
        setState(() => _thinking = false);
      }
    }
  }

  /// Finishes the game: records the result, flushes stats, logs review.
  ///
  /// The outcome prefers the orchestrator's authoritative result; when the
  /// engine sees a terminal position first it is reported in. Buffered
  /// stats turns flush here (once), per-agent end markers follow, and the
  /// full game lands in [ReviewLog].
  void _finishGame() {
    if (_result != null || _orch == null) return;
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
    for (final turn in _pending) {
      turn.flush(log: _statsLog, gameId: kPlayGameId);
    }
    _pending.clear();
    final aiName =
        ref.read(agentListProvider).byId(_blackAgentId)?.name ?? 'AI Opponent';
    logGameResults(
      log: _statsLog,
      gameId: kPlayGameId,
      whiteAgentId: 'human',
      blackAgentId: _blackAgentId,
      whiteModelKey: 'human',
      blackModelKey: _blackModel,
      mode: 'standard',
      outcome: outcome,
    );
    _reviewLog.record(
      ReviewGame(
        id: kPlayGameId,
        whiteLabel: 'You',
        blackLabel: aiName,
        whiteAgentId: 'human',
        blackAgentId: _blackAgentId,
        ucis: orch.moveHistory,
        sans: List<String>.of(_sans),
        fens: List<String>.of(_fens),
        phrases: List<String?>.of(_phrases),
        fallbackFlags: List<bool>.of(_fallbacks),
      ),
    );
    if (mounted) {
      setState(() {
        _result = outcome;
        _thinking = false;
        // Terminal state clears any pending premoves (§15.4).
        _premoves.clear();
        _premoveNotice = null;
      });
    } else {
      _result = outcome;
      _thinking = false;
      _premoves.clear();
      _premoveNotice = null;
    }
  }

  /// Resign confirmation → `orchestrator.resign('w')` (outcome `0-1`).
  Future<void> _confirmResign() async {
    final orch = _orch;
    if (orch == null || _result != null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resign?'),
        content: const Text('This ends the game as a loss (0-1).'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey<String>('play-resign-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Resign'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      orch.resign('w');
    }
  }
}

/// Standard initial position as square → two-char code.
///
/// Kept for the settings preview and review demo line; live screens use
/// [squaresOf] over the real engine instead.
Map<String, String> startingPosition() {
  const back = <String>['R', 'N', 'B', 'Q', 'K', 'B', 'N', 'R'];
  final pos = <String, String>{};
  for (var f = 0; f < 8; f++) {
    pos['${kFiles[f]}1'] = 'w${back[f]}';
    pos['${kFiles[f]}2'] = 'wP';
    pos['${kFiles[f]}7'] = 'bP';
    pos['${kFiles[f]}8'] = 'b${back[f]}';
  }
  return pos;
}

/// Promotion picker (Q/R/B/N); `null` when dismissed.
Future<String?> promotionDialog(BuildContext context, {required bool isWhite}) {
  const options = <String>['Q', 'R', 'B', 'N'];
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Promote to'),
      content: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          for (final o in options)
            IconButton(
              iconSize: 40,
              tooltip: o,
              onPressed: () => Navigator.pop(context, o),
              icon: _promotionGlyph(o, isWhite: isWhite),
            ),
        ],
      ),
    ),
  );
}

/// Promotion glyph drawn as a filled shape over a contrasting outline.
///
/// A plain colored glyph relies on a single drop shadow and disappears in
/// the wrong dialog tone; the explicit stroke layer keeps white pieces
/// legible on light surfaces (and black pieces on dark ones) without assets.
Widget _promotionGlyph(String letter, {required bool isWhite}) {
  final glyph = PieceTheme.glyphFor(PieceTypeX.fromLetter(letter)!);
  final fill = isWhite ? Colors.white : Colors.black;
  final stroke = isWhite ? Colors.black : Colors.white;
  return Stack(
    alignment: Alignment.center,
    children: <Widget>[
      Text(
        glyph,
        style: TextStyle(
          fontSize: 40,
          height: 1,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = stroke,
        ),
      ),
      Text(glyph, style: TextStyle(fontSize: 40, height: 1, color: fill)),
    ],
  );
}

/// Material balance (White-relative pawns) for the heuristic eval bar.
///
/// A deliberately naive estimator over the real position — the bar's
/// `heuristic` watermark (see [EvalBar]) marks it as such.
double _materialPawns(Position position) {
  var total = 0;
  for (final entry in position.board.entries) {
    final v = entry.value.type.value;
    total += entry.value.color.isWhite ? v : -v;
  }
  return (total.toDouble() * 0.4).clamp(-8.0, 8.0);
}
