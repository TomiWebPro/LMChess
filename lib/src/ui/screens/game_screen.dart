/// [GameScreen]: unified human/engine game room (replaces Play + Watch).
///
/// One screen covers every seat combination: each side (White/Black) is
/// independently **Human**, **Agent** (catalog LLM), or **Stockfish**
/// (embedded engine, Elo-capped). Human-vs-AI plays like the old play room
/// (tap/drag + premoves while the AI thinks); AI-vs-AI runs the watch-style
/// sequential pump; human-vs-human is local two-player.
///
/// * Seats + time control are picked in the setup card (locked while live).
/// * Time presets: none / bullet / blitz / rapid / custom, with **live**
///   ticking clocks (200 ms ticker repaints only when the shown second
///   changes). Human thinking time is measured from the turn start and
///   charged via `applyHumanMove(elapsedMs:)`; an idle human whose clock
///   hits zero is flagged through `expireIdleTurn`.
/// * Stockfish seats resolve moves through `stockfishMoveProvider` with the
///   live FEN (the LLM provider path cannot carry a FEN), scripted as a
///   one-shot mock so runner validation + fallback attribution still run.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/agent_config.dart' as agent_backend;
import '../../chess/engine.dart' as chess_eng;
import '../../chess/fen.dart';
import '../../chess/piece.dart';
import '../../chess/position.dart';
import '../../chess/square.dart';
import '../../game/clock.dart';
import '../../game/game_state.dart';
import '../../game/orchestrator.dart';
import '../../llm/provider.dart';
import '../../stockfish/stockfish_move.dart';
import '../../theme/piece_theme.dart';
import '../../theme/registry.dart';
import '../backend/activity_mapper.dart';
import '../backend/agent_providers.dart';
import '../backend/board_mapper.dart';
import '../backend/game_pump.dart';
import '../backend/telemetry_logs.dart';
import '../premove.dart';
import '../providers/backend_providers.dart';
import '../providers/orchestrator_adapter.dart';
import '../ui_models.dart';
import '../widgets/activity_panel.dart';
import '../widgets/boards.dart';
import '../widgets/board_motion.dart';
import '../widgets/chessboard.dart';
import '../widgets/scrub_shortcuts.dart';

/// Game id used for stats/review attribution of the game room.
const String kGameId = 'game';

/// Seat kinds per side.
enum SeatKind {
  /// A human moves this side on the board.
  human,

  /// A catalog LLM agent moves this side.
  agent,

  /// The embedded Stockfish engine moves this side.
  stockfish,
}

/// One time-control preset in the setup picker.
class TimePreset {
  /// Creates a preset.
  const TimePreset(this.label, this.control);

  /// Display label.
  final String label;

  /// Control applied on start (`custom` builds its own from the fields).
  final TimeControl control;

  /// Whether this entry reads the custom minutes/increment fields.
  bool get isCustom => label == 'Custom';
}

/// Preset list for the time picker.
const List<TimePreset> kTimePresets = <TimePreset>[
  TimePreset('No clock', TimeControl.none()),
  TimePreset(
    'Bullet 1+0',
    TimeControl(type: TimeControlType.fixed, initialMs: 60000),
  ),
  TimePreset(
    'Blitz 3+2',
    TimeControl(
      type: TimeControlType.increment,
      initialMs: 180000,
      incrementMs: 2000,
    ),
  ),
  TimePreset(
    'Blitz 5+0',
    TimeControl(type: TimeControlType.fixed, initialMs: 300000),
  ),
  TimePreset(
    'Rapid 10+0',
    TimeControl(type: TimeControlType.fixed, initialMs: 600000),
  ),
  TimePreset(
    'Rapid 15+10',
    TimeControl(
      type: TimeControlType.increment,
      initialMs: 900000,
      incrementMs: 10000,
    ),
  ),
  TimePreset('Custom', TimeControl.none()),
];

/// Unified game room: configurable seats + time control over a live board.
class GameScreen extends ConsumerStatefulWidget {
  /// Creates the game screen.
  const GameScreen({
    super.key,
    this.initialFen,
    this.initialSeed,
    this.initialWhiteKind = SeatKind.human,
    this.initialBlackKind = SeatKind.agent,
    this.autostart = true,
  });

  /// Starting FEN for testing.
  final String? initialFen;

  /// Seed for deterministic mock runs.
  final int? initialSeed;

  /// Seat kind White starts with (locked once live).
  final SeatKind initialWhiteKind;

  /// Seat kind Black starts with (locked once live).
  final SeatKind initialBlackKind;

  /// Whether to start a game automatically on mount (play-room behavior).
  final bool autostart;

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  // -- Setup selections (locked while a game is live) -----------------------

  /// Seat kinds per side. Defaults preserve the old play room: human vs AI.
  SeatKind _whiteKind = SeatKind.human;
  SeatKind _blackKind = SeatKind.agent;

  /// Selected catalog agent ids for agent seats.
  String? _whiteAgentId = 'demo-white';
  String? _blackAgentId = 'demo-black';

  /// Elo for ad-hoc Stockfish seats.
  int _whiteElo = 1500;
  int _blackElo = 1500;

  /// Time preset index into [kTimePresets].
  int _presetIndex = 4;

  /// Custom time fields (minutes + increment seconds).
  final TextEditingController _customMinutes = TextEditingController(
    text: '10',
  );
  final TextEditingController _customIncrement = TextEditingController(
    text: '0',
  );

  // -- Live game state -------------------------------------------------------

  /// Turn-pump + recording backend (SRP): sequencing, mirror replay and
  /// stats/review recording. Owns the mirror [Position], journals, pending
  /// turns and seat attribution; the screen keeps layout, input and clocks.
  GamePump? _gamePump;

  /// Fallback mirror for pre-start renders (before the first game starts).
  final Position _fallbackEngine = Position.initial();

  /// Mirror engine; only ever advanced by [GamePump.syncMirror] from the
  /// orchestrator's authoritative `moveHistory`.
  Position get _engine => _gamePump?.mirror ?? _fallbackEngine;

  /// SAN history parallel to the orchestrator's UCI history.
  List<String> get _sans => _gamePump?.sans ?? const <String>[];

  /// FEN history (`fens[0]` is the start position; one entry per ply + 1).
  List<String> get _fens => _gamePump?.fens ?? const <String>[standardStartFen];

  /// Fallback flags parallel to the UCI history.
  List<bool> get _fallbacks => _gamePump?.fallbacks ?? const <bool>[];

  /// Viewed ply for tap-to-seek (`_sans.length` = live).
  int _viewPly = 0;

  /// Total plies the board view has synced to (tracks pump-consumed
  /// advances that a redundant `syncMirror` no longer reports as changed).
  int _syncedTotal = 0;

  /// Selected square, if a human has one picked up.
  String? _selected;

  /// Engine-legal targets for [_selected].
  List<String> _legal = const <String>[];

  /// Last-move trail.
  String? get _lastFrom => _gamePump?.lastFrom;

  /// Last-move trail.
  String? get _lastTo => _gamePump?.lastTo;

  /// Most recently applied transition for the §15.2 motion layer.
  BoardMove? get _lastMotion => _gamePump?.lastMotion;

  /// Motion for the scrubbed view (adjacent steps only).
  BoardMove? _viewMotion;

  /// Game result; non-null ends input.
  String? _result;

  bool _resultDialogShown = false;

  /// Streaming activity for the panel.
  final List<ActivityEvent> _events = <ActivityEvent>[];

  /// Error subset of [_events].
  final List<ActivityEvent> _errors = <ActivityEvent>[];

  /// Presentation revision for the activity panel.
  final ValueNotifier<int> _activityRevision = ValueNotifier<int>(0);

  /// Visible AI-turn error (with retry).
  String? _aiError;

  /// Whether an AI turn is in flight (footer spinner).
  bool _thinking = false;

  /// Sequential-pump reentrancy guard.
  bool _pumping = false;

  /// Queued premoves (single-human games only).
  final List<PremoveAttempt> _premoves = <PremoveAttempt>[];

  /// Discard notice for illegal premoves.
  String? _premoveNotice;

  /// The live orchestrator (recreated per game; null before first start).
  GameOrchestrator? _orch;

  /// `ChangeNotifier` adapter over [_orch] for `Listenable` widgets.
  ///
  /// The orchestrator itself is pure Dart; this forwards its state bumps
  /// (plus events) to Flutter listeners and is recreated/disposed with
  /// each game.
  OrchestratorListenable? _orchListenable;

  /// Subscription mapping [GameEvent]s into [_events].
  StreamSubscription<GameEvent>? _sub;

  /// Wall-clock start of the current side-to-move's thinking time.
  DateTime? _turnStartWall;

  /// Live clock ticker (repaints only when the shown second changes).
  Timer? _ticker;

  /// Last painted clock seconds (avoids rebuilding the board 5×/s).
  int _lastPaintedW = -1;
  int _lastPaintedB = -1;

  /// Whether the idle-flag path already fired for the current turn.
  bool _expireAttempted = false;

  /// Last rendered orchestrator state (cheap lifecycle refreshes).
  OrchestratorState? _lastOrchState;

  /// Per-scope stats/review stores.
  late final StatsLog _statsLog;
  late final ReviewLog _reviewLog;

  /// Wall-clock source for seeds.
  late DateTime Function() _clock;

  @override
  void initState() {
    super.initState();
    _clock = ref.read(clockProvider);
    _statsLog = ref.read(statsLogProvider);
    _reviewLog = ref.read(reviewLogProvider);
    _whiteKind = widget.initialWhiteKind;
    _blackKind = widget.initialBlackKind;
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
    if (widget.autostart) {
      // Start past the first frame, not in a microtask: an inline start
      // disposes the setup UI and mounts the live UI (streams, scroll
      // animation, focus, clocks) inside frames 1-3, while the Windows
      // accessibility bridge is still establishing its root — the
      // engine-side AXTree then applies updates that reference nodes it
      // never received and aborts Debug runs
      // (flutter/flutter#175041: `Failed to update ui::AXTree ... not in
      // the tree and is not the new root` + `Lost connection to device`).
      // ReviewScreen follows the same rule for Stockfish. The game still
      // starts before the user can interact.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _orch == null) unawaited(_start());
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _customMinutes.dispose();
    _customIncrement.dispose();
    _orchListenable?.dispose();
    _orchListenable = null;
    unawaited(retireOrchestrator(_orch, _sub));
    _activityRevision.dispose();
    _premoves.clear();
    super.dispose();
  }

  // -- Seat helpers ----------------------------------------------------------

  /// Whether [color] (`w`/`b`) is a human seat.
  bool _isHumanSeat(String color) => color == 'w'
      ? _whiteKind == SeatKind.human
      : _blackKind == SeatKind.human;

  /// Whether [color] is engine-driven (agent or stockfish).
  bool _isEngineSeat(String color) => !_isHumanSeat(color);

  /// Exactly one human seat exists (premove games).
  String? get _soloHumanColor {
    final whiteHuman = _whiteKind == SeatKind.human;
    final blackHuman = _blackKind == SeatKind.human;
    if (whiteHuman && !blackHuman) return 'w';
    if (blackHuman && !whiteHuman) return 'b';
    return null;
  }

  /// Display name for [color]'s seat.
  String _seatName(String color, List<AgentConfig> catalog) {
    final kind = color == 'w' ? _whiteKind : _blackKind;
    switch (kind) {
      case SeatKind.human:
        return color == 'w' ? 'You · White' : 'You · Black';
      case SeatKind.agent:
        final id = color == 'w' ? _whiteAgentId : _blackAgentId;
        for (final a in catalog) {
          if (a.id == id) return a.name;
        }
        return color == 'w' ? 'White (AI)' : 'Black (AI)';
      case SeatKind.stockfish:
        final elo = color == 'w' ? _whiteElo : _blackElo;
        return 'Stockfish $elo';
    }
  }

  /// One-line config subtitle for [color]'s seat.
  String _seatSubtitle(String color, List<AgentConfig> catalog) {
    final kind = color == 'w' ? _whiteKind : _blackKind;
    switch (kind) {
      case SeatKind.human:
        return color == 'w' ? 'Human · White' : 'Human · Black';
      case SeatKind.agent:
        final id = color == 'w' ? _whiteAgentId : _blackAgentId;
        for (final a in catalog) {
          if (a.id == id) {
            return '${a.summary} · t=${a.temperature.toStringAsFixed(2)}';
          }
        }
        return 'AI agent';
      case SeatKind.stockfish:
        final elo = color == 'w' ? _whiteElo : _blackElo;
        return 'Engine · Elo $elo';
    }
  }

  /// Swaps White/Black seats (kinds, agents, Elos). Only when not live.
  void _swapSeats() {
    if (_live) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stop the game to swap seats.')),
      );
      return;
    }
    setState(() {
      final kind = _whiteKind;
      _whiteKind = _blackKind;
      _blackKind = kind;
      final agentId = _whiteAgentId;
      _whiteAgentId = _blackAgentId;
      _blackAgentId = agentId;
      final elo = _whiteElo;
      _whiteElo = _blackElo;
      _blackElo = elo;
      _selected = null;
      _legal = const <String>[];
      _viewMotion = null;
    });
  }

  /// Shows the game-over result as a dialog (not an inline banner).
  void _showResultDialog() {
    if (!mounted || _result == null || _resultDialogShown) return;
    _resultDialogShown = true;
    final result = _result ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Game over'),
          content: Text(result),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Review board'),
            ),
            FilledButton(
              key: const ValueKey<String>('play-new-game-banner'),
              onPressed: () {
                Navigator.pop(context);
                _start();
              },
              child: const Text('New game'),
            ),
          ],
        ),
      );
    });
  }

  /// Shows an AI error as a SnackBar (not an inline banner).
  void _showAiErrorSnack(String message) {
    // Keep [_aiError] as the last-error state for diagnostics; the banner is gone.
    assert(_aiError != null || _aiError == null);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          key: const ValueKey<String>('play-retry-ai'),
          label: 'Retry',
          onPressed: _pump,
        ),
      ),
    );
  }
  /// Synthetic backend config for a Stockfish seat.
  agent_backend.AgentConfig _stockfishBackend(String color) {
    final elo = color == 'w' ? _whiteElo : _blackElo;
    return agent_backend.AgentConfig(
      id: 'stockfish-$color',
      name: 'Stockfish $elo',
      providerId: ProviderId.stockfish,
      model: 'stockfish-elo$elo',
      stockfishElo: elo,
    );
  }

  /// Effective time control for the next game.
  TimeControl get _selectedTimeControl {
    final preset = kTimePresets[_presetIndex];
    if (!preset.isCustom) return preset.control;
    final minutes = int.tryParse(_customMinutes.text.trim()) ?? 10;
    final incSecs = int.tryParse(_customIncrement.text.trim()) ?? 0;
    if (minutes <= 0) return const TimeControl.none();
    if (incSecs > 0) {
      return TimeControl(
        type: TimeControlType.increment,
        initialMs: minutes * 60000,
        incrementMs: incSecs * 1000,
      );
    }
    return TimeControl(type: TimeControlType.fixed, initialMs: minutes * 60000);
  }

  /// Whether a game is currently live (started, not terminal).
  bool get _live {
    final orch = _orch;
    return orch != null && !isTerminalOrchestratorState(orch.state);
  }

  // -- Live clocks -----------------------------------------------------------

  /// Displayed remaining seconds for [color], ticking while it thinks.
  int? _displaySeconds(String color) {
    final orch = _orch;
    if (orch == null) return null;
    if (orch.config.timeControl.type == TimeControlType.none) return null;
    final base = color == 'w' ? orch.clock.remainingW : orch.clock.remainingB;
    final running =
        _live && orch.state != OrchestratorState.paused && orch.turn == color;
    if (running && _turnStartWall != null) {
      final elapsed = DateTime.now().difference(_turnStartWall!).inMilliseconds;
      final liveMs = base - (elapsed < 0 ? 0 : elapsed);
      return (liveMs <= 0 ? 0 : (liveMs / 1000).ceil());
    }
    return (base <= 0 ? 0 : (base / 1000).ceil());
  }

  /// 200 ms ticker: repaints clocks on second change; flags idle humans.
  void _tick() {
    final orch = _orch;
    if (!mounted || orch == null || !_live) return;
    if (orch.config.timeControl.type == TimeControlType.none) return;
    if (orch.state == OrchestratorState.paused) return;
    final w = _displaySeconds('w') ?? -1;
    final b = _displaySeconds('b') ?? -1;
    if (w == 0 || b == 0) {
      // A side hit zero on the display. AI overruns are adjudicated by the
      // orchestrator when the turn settles; idle humans need the explicit
      // idle-expiry path (their time is otherwise never consumed).
      final mover = orch.turn;
      if (_isHumanSeat(mover) &&
          !orch.isBusy &&
          !_expireAttempted &&
          _turnStartWall != null) {
        _expireAttempted = true;
        final elapsed = DateTime.now()
            .difference(_turnStartWall!)
            .inMilliseconds;
        if (orch.expireIdleTurn(elapsed < 0 ? 0 : elapsed)) {
          return; // finish flows through the gameFinished event.
        }
      }
    }
    if (w != _lastPaintedW || b != _lastPaintedB) {
      _lastPaintedW = w;
      _lastPaintedB = b;
      if (mounted) setState(() {});
    }
  }

  // -- Game lifecycle --------------------------------------------------------

  /// Starts a fresh game with the current setup selections.
  Future<void> _start() async {
    final catalog = ref.read(agentListProvider);
    if (_whiteKind == SeatKind.agent && catalog.byId(_whiteAgentId) == null) {
      _snack('Pick a White agent first.');
      return;
    }
    if (_blackKind == SeatKind.agent && catalog.byId(_blackAgentId) == null) {
      _snack('Pick a Black agent first.');
      return;
    }
    await retireOrchestrator(_orch, _sub);
    if (!mounted) return;
    _orchListenable?.dispose();
    _orchListenable = null;
    _sub = null;
    final startFen = widget.initialFen ?? standardStartFen;
    final mirror = parseFen(startFen);
    _viewPly = 0;
    _syncedTotal = 0;
    _selected = null;
    _legal = const <String>[];
    _viewMotion = null;
    _result = null;
    _resultDialogShown = false;
    _events.clear();
    _errors.clear();
    _thinking = false;
    _pumping = false;
    _aiError = null;
    _premoves.clear();
    _premoveNotice = null;
    _expireAttempted = false;
    _lastOrchState = null;
    final timeControl = _selectedTimeControl;
    final orch = GameOrchestrator(
      config: GameConfig(
        mode: GameMode.standard,
        timeControl: timeControl,
        maxMoves: 200,
        seed:
            widget.initialSeed ??
            (_clock().millisecondsSinceEpoch & 0x7fffffff),
      ),
      white: GameParticipant(
        agentConfigId: _participantBinding('w'),
        label: _seatName('w', catalog.agents),
        isHuman: _whiteKind == SeatKind.human,
      ),
      black: GameParticipant(
        agentConfigId: _participantBinding('b'),
        label: _seatName('b', catalog.agents),
        isHuman: _blackKind == SeatKind.human,
      ),
      positionUpdater: fenAdvance,
    );
    orch.setPosition(startFen, turn: 'w', legalMoves: legalUcis(mirror));
    orch.startGame();
    _orch = orch;
    final pump = GamePump(
      orch: orch,
      mirror: mirror,
      log: _statsLog,
      reviews: _reviewLog,
      initialFen: startFen,
    );
    pump.setSeatAttribution(
      whiteId: _seatAttributionId('w', catalog),
      blackId: _seatAttributionId('b', catalog),
      whiteModelKey: _seatModelKey('w', catalog),
      blackModelKey: _seatModelKey('b', catalog),
    );
    _gamePump = pump;
    _turnStartWall = DateTime.now();
    _lastPaintedW = -1;
    _lastPaintedB = -1;
    _sub = orch.events.listen(_onEvent);
    _orchListenable = OrchestratorListenable(orch)..addListener(_onOrchState);
    if (mounted) setState(() {});
    _pump();
  }

  /// State-listener refresh: mirrors the lifecycle branch of [_onEvent] so
  /// `Listenable` consumers stay in sync even for state bumps without a
  /// mapped activity row.
  void _onOrchState() {
    if (!mounted) return;
    if (_orch?.state != _lastOrchState) {
      _lastOrchState = _orch?.state;
      setState(() {});
    }
  }

  /// Participant binding id for [color] (null for human seats).
  String? _participantBinding(String color) {
    final kind = color == 'w' ? _whiteKind : _blackKind;
    switch (kind) {
      case SeatKind.human:
        return null;
      case SeatKind.agent:
        return color == 'w' ? _whiteAgentId : _blackAgentId;
      case SeatKind.stockfish:
        return 'stockfish-$color';
    }
  }

  /// Stats attribution id for [color].
  String _seatAttributionId(String color, AgentListStore catalog) {
    final kind = color == 'w' ? _whiteKind : _blackKind;
    switch (kind) {
      case SeatKind.human:
        return 'human';
      case SeatKind.agent:
        return color == 'w'
            ? (_whiteAgentId ?? 'unknown')
            : (_blackAgentId ?? 'unknown');
      case SeatKind.stockfish:
        final elo = color == 'w' ? _whiteElo : _blackElo;
        return 'stockfish-elo$elo';
    }
  }

  /// Model key for [color].
  String _seatModelKey(String color, AgentListStore catalog) {
    final kind = color == 'w' ? _whiteKind : _blackKind;
    switch (kind) {
      case SeatKind.human:
        return 'human';
      case SeatKind.agent:
        final id = color == 'w' ? _whiteAgentId : _blackAgentId;
        return catalog.byId(id)?.model ?? 'agent';
      case SeatKind.stockfish:
        final elo = color == 'w' ? _whiteElo : _blackElo;
        return 'stockfish-elo$elo';
    }
  }

  /// Shows a transient message.
  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Pauses the clock/turn intake.
  void _pause() {
    _orch?.pause();
    if (mounted) setState(() {});
  }

  /// Resumes a paused game and restarts the pump.
  void _resume() {
    _orch?.resume();
    _turnStartWall = DateTime.now();
    _expireAttempted = false;
    if (mounted) setState(() {});
    _pump();
  }

  /// Aborts the game without a winner.
  void _stop() {
    _orch?.stop();
    if (mounted) setState(() {});
  }

  /// Maps one orchestrator event into the activity panel, then syncs.
  void _onEvent(GameEvent event) {
    final activity = activityFromGameEvent(event);
    if (activity != null) _addActivity(activity);
    if (event.type == 'moveApplied') {
      _syncBoard();
    } else if (event.type == 'gameFinished' ||
        event.type == 'terminalReported' ||
        event.type == 'resigned' ||
        event.type == 'flagFall') {
      _finishGame();
    } else if (_orch?.state != _lastOrchState) {
      _lastOrchState = _orch?.state;
      if (mounted) setState(() {});
    }
  }

  /// Appends [event] to the activity panel (and error subset).
  void _addActivity(ActivityEvent event) {
    if (!mounted) return;
    _events.add(event);
    if (event.isError) _errors.add(event);
    _activityRevision.value++;
  }

  /// Replays unapplied orchestrator UCIs onto the mirror engine.
  ///
  /// Sequencing + journals live in [GamePump]; this only mirrors the result
  /// into UI state (view cursor, position intake, clocks) and branches to
  /// finish/pump/premove.
  void _syncBoard() {
    final orch = _orch;
    final pump = _gamePump;
    if (orch == null || pump == null) return;
    final sync = pump.syncMirror();
    if (sync.hasError) {
      _addActivity(
        ActivityEvent(
          kind: ActivityEventKind.error,
          message: 'Mirror sync failed on ${sync.failedUci}: ${sync.error}',
        ),
      );
    }
    // The pump (`pumpAiTurn`/`applyHumanMove`) already replays new moves
    // onto the mirror, so this second sync usually reports no change — but
    // the view cursor and the orchestrator's legal list still need the
    // advance. Relying on `sync.changed` alone strands `legalMoves` empty
    // (`_applyMove` clears it; only `setPosition` repopulates it) and the
    // pump loop then breaks silently on `legalMoves.isEmpty`.
    final total = _sans.length;
    final advanced = total > _syncedTotal;
    final wasLive = _viewPly >= _syncedTotal;
    _syncedTotal = total;
    if (advanced && wasLive && mounted) {
      setState(() {
        _viewPly = total;
        _selected = null;
        _legal = const <String>[];
        _viewMotion = null;
      });
    }
    if (!sync.hasError &&
        mounted &&
        _result == null &&
        (advanced || orch.legalMoves.isEmpty)) {
      // Rejected (no-op) while a turn is in flight; the post-turn sync
      // lands it.
      orch.setPosition(
        _engine.toFen(),
        turn: _engine.sideToMove.isWhite ? 'w' : 'b',
        legalMoves: legalUcis(_engine),
      );
      _turnStartWall = DateTime.now();
      _expireAttempted = false;
    }
    if (_result != null) return;
    if (chess_eng.ChessRules.resultOf(_engine) != null) {
      _finishGame();
    } else if (_isEngineSeat(orch.turn)) {
      if (orch.state == OrchestratorState.waitingAi) _pump();
    } else {
      // Human turn with queued premoves: play them one at a time.
      final solo = _soloHumanColor;
      if (solo != null &&
          _premoves.isNotEmpty &&
          orch.turn == solo &&
          orch.state == OrchestratorState.waitingHuman) {
        _executePremoves();
      }
    }
  }

  /// Sequential turn loop for engine seats.
  ///
  /// Provider resolution stays here (needs `Ref`/catalog); one-turn
  /// sequencing, buffering and mirror sync live in [GamePump].
  Future<void> _pump() async {
    final orch = _orch;
    final pump = _gamePump;
    if (_pumping || orch == null || pump == null) return;
    _pumping = true;
    try {
      while (mounted && identical(_orch, orch) && identical(_gamePump, pump)) {
        if (isTerminalOrchestratorState(orch.state)) break;
        if (orch.state == OrchestratorState.paused) break;
        if (orch.state != OrchestratorState.waitingAi) break;
        final color = orch.turn;
        if (!_isEngineSeat(color)) break;
        if (orch.legalMoves.isEmpty) break;
        final catalog = ref.read(agentListProvider);
        final agent_backend.AgentConfig backend = _backendFor(color, catalog);
        if (!mounted ||
            !identical(_orch, orch) ||
            !identical(_gamePump, pump)) {
          return;
        }
        if (mounted) {
          setState(() {
            _thinking = true;
            _aiError = null;
          });
        }
        LlmProvider provider;
        try {
          provider = await _providerFor(color, backend, orch);
        } catch (e) {
          if (mounted && identical(_orch, orch) && identical(_gamePump, pump)) {
            final message = 'AI turn crashed: $e';
            _addActivity(
              ActivityEvent(kind: ActivityEventKind.error, message: message),
            );
            setState(() => _aiError = message);
            _showAiErrorSnack(message);
          }
          break;
        }
        final outcome = await pump.pumpAiTurn(
          color: color,
          backend: backend,
          provider: provider,
        );
        if (!mounted ||
            !identical(_orch, orch) ||
            !identical(_gamePump, pump)) {
          return;
        }
        if (outcome.crashError != null) {
          _addActivity(
            ActivityEvent(
              kind: ActivityEventKind.error,
              message: outcome.crashError!,
            ),
          );
          if (mounted) {
            setState(() => _aiError = outcome.crashError);
            _showAiErrorSnack(outcome.crashError!);
          }
          break;
        }
        if (outcome.result == null) break;
        if (outcome.sync.hasError) {
          _addActivity(
            ActivityEvent(
              kind: ActivityEventKind.error,
              message:
                  'Mirror sync failed on '
                  '${outcome.sync.failedUci}: ${outcome.sync.error}',
            ),
          );
        }
        if (outcome.noMoveMessage != null) {
          _addActivity(
            ActivityEvent(
              kind: ActivityEventKind.error,
              message: outcome.noMoveMessage!,
            ),
          );
          if (mounted) {
            setState(() => _aiError = outcome.noMoveMessage);
            _showAiErrorSnack(outcome.noMoveMessage!);
          }
        }
        _syncBoard();
        if (mounted) setState(() => _thinking = false);
      }
    } finally {
      _pumping = false;
      // A Start issued while this loop owned the guard retires `orch` and
      // kicks its own `_pump()`, which was dropped at the guard check above
      // — hand the guard over so the new game does not sit idle.
      if (mounted && (!identical(_orch, orch) || !identical(_gamePump, pump))) {
        unawaited(_pump());
      }
      if (mounted) setState(() => _thinking = false);
    }
  }

  /// Backend config bound for [color]'s engine seat.
  agent_backend.AgentConfig _backendFor(String color, AgentListStore catalog) {
    final kind = color == 'w' ? _whiteKind : _blackKind;
    if (kind == SeatKind.stockfish) return _stockfishBackend(color);
    final id = color == 'w' ? _whiteAgentId : _blackAgentId;
    final uiAgent =
        catalog.byId(id) ??
        AgentConfig(
          id: id ?? 'unknown',
          name: 'Unknown agent',
          provider: 'mock',
          model: 'mock',
        );
    return toBackendAgent(uiAgent);
  }

  /// Turn provider for [color]: Stockfish picker or catalog factory.
  Future<LlmProvider> _providerFor(
    String color,
    agent_backend.AgentConfig backend,
    GameOrchestrator orch,
  ) async {
    if (backend.providerId == ProviderId.stockfish) {
      final label = color == 'w' ? 'Stockfish White' : 'Stockfish Black';
      return stockfishMoveProvider(
        _engine.toFen(),
        orch.legalMoves,
        elo: backend.stockfishElo,
        phrase: '$label reply',
      );
    }
    final uiName = color == 'w'
        ? ref.read(agentListProvider).byId(_whiteAgentId)?.name
        : ref.read(agentListProvider).byId(_blackAgentId)?.name;
    return ref.read(turnProviderFactoryProvider)(
      backend,
      orch.legalMoves,
      seed: widget.initialSeed,
      phrase: '${uiName ?? backend.name} reply',
    );
  }

  /// Finishes the game: records the result, flushes stats, logs review.
  ///
  /// Terminal detection + buffering + recording live in [GamePump]; this
  /// only mirrors the outcome into UI state.
  void _finishGame() {
    if (_result != null || _orch == null || _gamePump == null) return;
    final pump = _gamePump!;
    final catalog = ref.read(agentListProvider);
    final outcome = pump.flushGameEnd(
      whiteLabel: _seatName('w', catalog.agents),
      blackLabel: _seatName('b', catalog.agents),
    );
    if (outcome == null) return;
    if (mounted) {
      setState(() {
        _result = outcome;
        _thinking = false;
        _premoves.clear();
        _premoveNotice = null;
      });
    } else {
      _result = outcome;
      _thinking = false;
    }
    _showResultDialog();
  }

  // -- Human input -----------------------------------------------------------

  /// Whether [square] holds a piece the user may pick up.
  ///
  /// On a human turn: own pieces of the side to move. During the premove
  /// window (solo-human game, engine thinking): the waiting human's pieces,
  /// so premoves can be queued by drag as well as by tap.
  bool _isOwnPiece(String square) {
    final orch = _orch;
    if (orch == null || _result != null) return false;
    final tapped = Square.tryParse(square);
    final occupant = tapped == null ? null : _engine.pieceAt(tapped);
    if (occupant == null) return false;
    if (_isHumanSeat(orch.turn)) {
      return orch.turn == 'w'
          ? occupant.color.isWhite
          : !occupant.color.isWhite;
    }
    final solo = _soloHumanColor;
    if (solo != null && _premoveWindow) {
      return solo == 'w' ? occupant.color.isWhite : !occupant.color.isWhite;
    }
    return false;
  }

  /// True while the premove window is open: solo-human game, live view, and
  /// the engine side is thinking.
  bool get _premoveWindow {
    final orch = _orch;
    final solo = _soloHumanColor;
    return orch != null &&
        solo != null &&
        _result == null &&
        _viewPly == _sans.length &&
        orch.turn != solo &&
        _live;
  }

  /// The live position with queued premoves applied (queue-time legality).
  Position get _premoveSimulation {
    final solo = _soloHumanColor ?? 'w';
    return premoveSimulation(
      _engine,
      _premoves,
      color: solo == 'w' ? PieceColor.white : PieceColor.black,
    );
  }

  /// Board tap handler: human moves on their turn, premoves otherwise.
  Future<void> _onTap(String square) async {
    final orch = _orch;
    if (_result != null || orch == null) return;
    if (!_isHumanSeat(orch.turn)) {
      _onPremoveTap(square);
      return;
    }
    if (_selected != null && _legal.contains(square)) {
      await _attemptMove(_selected!, square);
      return;
    }
    final tapped = Square.tryParse(square);
    final occupant = tapped == null ? null : _engine.pieceAt(tapped);
    final ownColorIsWhite = orch.turn == 'w';
    if (occupant != null && occupant.color.isWhite == ownColorIsWhite) {
      final targets = <String>[
        for (final m in _engine.legalMoves(forSquare: tapped!)) m.to.name,
      ];
      setState(() {
        _selected = square;
        _legal = targets;
      });
      return;
    }
    setState(() {
      _selected = null;
      _legal = const <String>[];
    });
  }

  /// Attempts a human move from [from] to [to].
  Future<void> _attemptMove(
    String from,
    String to, {
    bool isDrag = false,
  }) async {
    final orch = _orch;
    if (_result != null ||
        orch == null ||
        !_isHumanSeat(orch.turn) ||
        _viewPly != _sans.length) {
      return;
    }
    final mover = orch.turn;
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
        ((mover == 'w' && Square.fromName(to).rank == 7) ||
            (mover == 'b' && Square.fromName(to).rank == 0))) {
      promotion = await promotionDialog(context, isWhite: mover == 'w');
      if (promotion == null || !mounted) return;
    }
    final start = _turnStartWall;
    final elapsedMs = start == null
        ? 0
        : DateTime.now().difference(start).inMilliseconds.clamp(0, 1 << 31);
    _applyHumanMove(from, to, promotion, mover, elapsedMs, isDrag: isDrag);
  }

  /// Applies the human's move through the orchestrator.
  ///
  /// Move application + stats buffering + mirror sync live in [GamePump];
  /// this only mirrors the result into UI state.
  bool _applyHumanMove(
    String from,
    String to,
    String? promotion,
    String mover,
    int elapsedMs, {
    bool isDrag = false,
  }) {
    final orch = _orch;
    final pump = _gamePump;
    if (orch == null || pump == null || _result != null) return false;
    final uci = '$from$to${promotion == null ? '' : promotion.toLowerCase()}';
    final outcome = pump.applyHumanMove(
      uci: uci,
      moverColor: mover,
      elapsedMs: elapsedMs,
      suppressMotion: isDrag,
    );
    if (!outcome.ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Move rejected by the game.')),
        );
      }
      return false;
    }
    if (outcome.sync.hasError) {
      _addActivity(
        ActivityEvent(
          kind: ActivityEventKind.error,
          message:
              'Mirror sync failed on '
              '${outcome.sync.failedUci}: ${outcome.sync.error}',
        ),
      );
    }
    setState(() {
      _selected = null;
      _legal = const <String>[];
    });
    _syncBoard();
    return true;
  }

  /// Board-tap handling during the engine's turn (premove window).
  void _onPremoveTap(String square) {
    if (!_premoveWindow) return;
    final solo = _soloHumanColor!;
    final soloWhite = solo == 'w';
    if (_selected == square) {
      setState(() {
        _selected = null;
        _legal = const <String>[];
      });
      return;
    }
    final tapped = Square.tryParse(square);
    final occupant = tapped == null ? null : _engine.pieceAt(tapped);
    if (occupant != null && occupant.color.isWhite == soloWhite) {
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

  /// Queues [from]→[to] as a premove (promotion defaults to queen).
  void _queuePremove(String from, String to) {
    if (!_premoveWindow) return;
    final solo = _soloHumanColor!;
    if (_premoves.length >= kMaxPremoves) return;
    final soloColor = solo == 'w' ? PieceColor.white : PieceColor.black;
    final promotion = isPromotionMove(_engine, from, to, soloColor)
        ? 'q'
        : null;
    if (!isLegalPremove(
      _premoveSimulation,
      from,
      to,
      promotion: promotion,
      color: soloColor,
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

  /// Plays queued premoves one at a time through the human-move path.
  void _executePremoves() {
    final orch = _orch;
    final solo = _soloHumanColor;
    if (orch == null || solo == null || _result != null || orch.turn != solo) {
      return;
    }
    if (_premoves.isEmpty) return;
    final head = _premoves.first;
    final soloColor = solo == 'w' ? PieceColor.white : PieceColor.black;
    if (!isLegalPremove(
      _engine,
      head.from,
      head.to,
      promotion: head.promotion,
      color: soloColor,
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
    final start = _turnStartWall;
    final elapsedMs = start == null
        ? 0
        : DateTime.now().difference(start).inMilliseconds.clamp(0, 1 << 31);
    _applyHumanMove(head.from, head.to, head.promotion, solo, elapsedMs);
  }

  /// Removes the last queued premove.
  void _removeLastPremove() {
    if (_premoves.isEmpty) return;
    setState(() => _premoves.removeLast());
  }

  /// Empties the premove queue.
  void _clearPremoves() {
    if (_premoves.isEmpty && _premoveNotice == null) return;
    setState(() {
      _premoves.clear();
      _premoveNotice = null;
      _selected = null;
      _legal = const <String>[];
    });
  }

  /// Moves the view cursor for scrubbing.
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

  /// Motion value for a scrub step (`null` snaps on multi-ply jumps).
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

  /// Maps scrub key actions onto the view cursor.
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

  // -- Build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final boardTheme = ref.watch(
      themeRegistryProvider.select((r) => r.boardTheme),
    );
    final pieceTheme = ref.watch(
      themeRegistryProvider.select((r) => r.pieceTheme),
    );
    final catalog = ref.watch(agentListProvider);
    final orch = _orch;
    final viewingLive = _viewPly == _sans.length;
    final position = viewingLive
        ? squaresOf(_engine)
        : squaresOfFen(_fens[_viewPly.clamp(0, _fens.length - 1)]);
    final mover = orch?.turn;
    final blackActive = _result == null && mover == 'b' && viewingLive;
    final whiteActive = _result == null && mover == 'w' && viewingLive;
    final blackCard = PlayerCard(
      key: const ValueKey<String>('seat-card-black'),
      name: _seatName('b', catalog.agents),
      subtitle: _seatSubtitle('b', catalog.agents),
      clockSeconds: _displaySeconds('b'),
      isActive: blackActive,
      isHuman: _blackKind == SeatKind.human,
      isWhite: false,
      onTap: _swapSeats,
    );
    final whiteCard = PlayerCard(
      key: const ValueKey<String>('seat-card-white'),
      name: _seatName('w', catalog.agents),
      subtitle: _seatSubtitle('w', catalog.agents),
      clockSeconds: _displaySeconds('w'),
      isActive: whiteActive,
      isHuman: _whiteKind == SeatKind.human,
      onTap: _swapSeats,
    );
    final interactive =
        _result == null && viewingLive && mover != null && _isHumanSeat(mover);
    final boardWidget = Chessboard(
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
          unawaited(_attemptMove(from, to, isDrag: true));
        }
      },
      onRightClick: _premoveWindow && _premoves.isNotEmpty
          ? _removeLastPremove
          : null,
      premoves: _premoveWindow
          ? <BoardPremove>[
              for (final p in _premoves)
                BoardPremove(from: p.from, to: p.to, promotion: p.promotion),
            ]
          : const <BoardPremove>[],
      motion: viewingLive ? _lastMotion : _viewMotion,
      interactive: interactive || _premoveWindow,
    );
    final panelWidget = ValueListenableBuilder<int>(
      valueListenable: _activityRevision,
      builder: (context, _, _) {
        final liveOrch = _orch;
        final busy =
            _pumping ||
            _thinking ||
            (liveOrch != null &&
                (liveOrch.state == OrchestratorState.streaming ||
                    liveOrch.state == OrchestratorState.validating ||
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
                    AgentActivityPanel(events: _events, isThinking: busy),
                    _buildMovesPanel(),
                    _buildErrors(_errors),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );

    Widget buildBoardWithOverlay() {
      final boardStack = Stack(
        children: <Widget>[
          Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: boardWidget,
            ),
          ),
          if (!viewingLive && _sans.isNotEmpty)
            Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: Center(
                child: FilledButton.tonal(
                  onPressed: () => _seekViewPly(_sans.length),
                  child: const Text('Return to live position'),
                ),
              ),
            ),
          Positioned(
            top: 8,
            right: 8,
            child: _buildTransportOverlay(catalog.agents),
          ),
        ],
      );
      return boardStack;
    }

    Widget buildPremoveFixed() {
      return SizedBox(
        height: 36,
        child: (_premoves.isEmpty && _premoveNotice == null)
            ? const SizedBox.shrink()
            : _buildPremoveBar(),
      );
    }

    Widget buildSetupFab(List<AgentConfig> agents) {
      return FloatingActionButton(
        key: const ValueKey<String>('game-setup-button'),
        tooltip: 'Game setup',
        onPressed: () => _openSetupDialog(agents),
        child: const Icon(Icons.tune_outlined),
      );
    }

    return ScrubShortcuts(
      enabled: _orch != null,
      onAction: _onScrubAction,
      onEscape: _premoves.isEmpty ? null : _clearPremoves,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final targetWide = constraints.maxWidth > ArenaBreakpoints.wide;
            return DebouncedBreakpoint<bool>(
              target: targetWide,
              builder: (context, wide) {
                final boardColumn = Column(
                  children: <Widget>[
                    blackCard,
                    const SizedBox(height: 8),
                    Expanded(child: buildBoardWithOverlay()),
                    buildPremoveFixed(),
                    const SizedBox(height: 8),
                    whiteCard,
                  ],
                );
                if (wide) {
                  return Stack(
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Expanded(child: boardColumn),
                          const SizedBox(width: 16),
                          SizedBox(width: 400, child: panelWidget),
                        ],
                      ),
                      Positioned(
                        right: 16,
                        bottom: 16,
                        child: buildSetupFab(catalog.agents),
                      ),
                    ],
                  );
                }
                return Stack(
                  children: <Widget>[
                    SingleChildScrollView(
                      child: Column(
                        children: <Widget>[
                          blackCard,
                          const SizedBox(height: 8),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: constraints.maxWidth,
                              maxHeight: constraints.maxWidth.isFinite
                                  ? constraints.maxWidth.clamp(200.0, 560.0)
                                  : 560.0,
                            ),
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: Stack(
                                children: <Widget>[
                                  boardWidget,
                                  if (!viewingLive && _sans.isNotEmpty)
                                    Positioned(
                                      top: 8,
                                      left: 0,
                                      right: 0,
                                      child: Center(
                                        child: FilledButton.tonal(
                                          onPressed: () =>
                                              _seekViewPly(_sans.length),
                                          child: const Text(
                                              'Return to live position'),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          buildPremoveFixed(),
                          const SizedBox(height: 8),
                          whiteCard,
                          const SizedBox(height: 8),
                          SizedBox(height: 480, child: panelWidget),
                          const SizedBox(height: 80),
                        ],
                      ),
                    ),
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: buildSetupFab(catalog.agents),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// Transport overlay: pause/resume/stop without a top bar.
  Widget _buildTransportOverlay(List<AgentConfig> agents) {
    final orch = _orch;
    if (orch == null) {
      return FilledButton.icon(
        onPressed: _start,
        icon: const Icon(Icons.play_arrow, size: 18),
        label: const Text('Start'),
      );
    }
    final terminal = isTerminalOrchestratorState(orch.state);
    final paused = orch.state == OrchestratorState.paused;
    if (terminal) {
      return FilledButton.icon(
        onPressed: _start,
        icon: const Icon(Icons.play_arrow, size: 18),
        label: const Text('Start'),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (!paused)
          IconButton.filledTonal(
            tooltip: 'Pause',
            onPressed: _pause,
            icon: const Icon(Icons.pause_outlined),
          ),
        if (paused)
          IconButton.filledTonal(
            tooltip: 'Resume',
            onPressed: _resume,
            icon: const Icon(Icons.play_arrow),
          ),
        IconButton.filledTonal(
          tooltip: 'Stop',
          onPressed: _stop,
          icon: const Icon(Icons.stop_outlined),
        ),
      ],
    );
  }
  /// Opens the game-setup dialog (seats + time control).
  Future<void> _openSetupDialog(List<AgentConfig> agents) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, dialogSetState) {
          void refresh(void Function() fn) {
            setState(fn);
            dialogSetState(() {});
          }

          return AlertDialog(
            title: const Text('Game setup'),
            content: SingleChildScrollView(
              child: _buildSetupContent(agents, onChanged: refresh),
            ),
            actions: <Widget>[
              if (_live)
                OutlinedButton.icon(
                  onPressed: () {
                    _stop();
                    dialogSetState(() {});
                  },
                  icon: const Icon(Icons.stop_outlined),
                  label: const Text('Stop game'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
              FilledButton.icon(
                key: const ValueKey<String>('game-setup-start'),
                onPressed: _live
                    ? null
                    : () {
                        Navigator.pop(dialogContext);
                        _start();
                      },
                icon: const Icon(Icons.play_arrow),
                label: Text(_orch == null ? 'Start' : 'New game'),
              ),
            ],
          );
        },
      ),
    );
    if (mounted) setState(() {});
  }

  /// Setup dialog content: seat selectors + time control.
  Widget _buildSetupContent(
    List<AgentConfig> agents, {
    required void Function(void Function()) onChanged,
  }) {
    final theme = Theme.of(context);
    final locked = _live;
    Widget kindDrop(String color) {
      final value = color == 'w' ? _whiteKind : _blackKind;
      return DropdownMenu<SeatKind>(
        width: 170,
        label: Text(color == 'w' ? 'White' : 'Black'),
        initialSelection: value,
        enabled: !locked,
        dropdownMenuEntries: const <DropdownMenuEntry<SeatKind>>[
          DropdownMenuEntry(value: SeatKind.human, label: 'Human'),
          DropdownMenuEntry(value: SeatKind.agent, label: 'Agent'),
          DropdownMenuEntry(value: SeatKind.stockfish, label: 'Stockfish'),
        ],
        onSelected: (v) {
          if (v == null) return;
          onChanged(() {
            if (color == 'w') {
              _whiteKind = v;
            } else {
              _blackKind = v;
            }
            _selected = null;
            _legal = const <String>[];
          });
        },
      );
    }

    Widget agentDrop(String color) {
      final value = color == 'w' ? _whiteAgentId : _blackAgentId;
      return SizedBox(
        width: 220,
        child: DropdownButtonFormField<String>(
          initialValue: agents.any((a) => a.id == value) ? value : null,
          decoration: InputDecoration(
            labelText: color == 'w' ? 'White agent' : 'Black agent',
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          items: <DropdownMenuItem<String>>[
            for (final a in agents)
              DropdownMenuItem(value: a.id, child: Text(a.name)),
          ],
          onChanged: locked
              ? null
              : (v) => onChanged(() {
                  if (color == 'w') {
                    _whiteAgentId = v;
                  } else {
                    _blackAgentId = v;
                  }
                }),
        ),
      );
    }

    Widget eloSlider(String color) {
      final value = (color == 'w' ? _whiteElo : _blackElo).toDouble().clamp(
        400.0,
        3000.0,
      );
      return SizedBox(
        width: 300,
        child: Row(
          children: <Widget>[
            SizedBox(width: 70, child: Text('Elo ${value.round()}')),
            Expanded(
              child: Slider(
                value: value,
                min: 400,
                max: 3000,
                divisions: 26,
                label: '${value.round()}',
                onChanged: locked
                    ? null
                    : (v) => onChanged(() {
                        if (color == 'w') {
                          _whiteElo = v.round();
                        } else {
                          _blackElo = v.round();
                        }
                      }),
              ),
            ),
          ],
        ),
      );
    }

    Widget seatRow(String color) {
      final kind = color == 'w' ? _whiteKind : _blackKind;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          SizedBox(width: 170, child: kindDrop(color)),
          if (kind == SeatKind.agent) agentDrop(color),
          if (kind == SeatKind.stockfish) eloSlider(color),
          if (kind == SeatKind.human)
            Text(
              'Human plays on the board',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      );
    }

    final preset = kTimePresets[_presetIndex];
    return SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (locked)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Game is live — seats and clock are locked. Stop the game to change them.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          Text('White', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          seatRow('w'),
          const SizedBox(height: 12),
          Text('Black', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          seatRow('b'),
          const SizedBox(height: 12),
          Text('Clock', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              SizedBox(
                width: 170,
                child: DropdownMenu<int>(
                  label: const Text('Time'),
                  initialSelection: _presetIndex,
                  enabled: !locked,
                  dropdownMenuEntries: <DropdownMenuEntry<int>>[
                    for (var i = 0; i < kTimePresets.length; i++)
                      DropdownMenuEntry(value: i, label: kTimePresets[i].label),
                  ],
                  onSelected: (v) => onChanged(() => _presetIndex = v ?? 4),
                ),
              ),
              if (preset.isCustom) ...<Widget>[
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _customMinutes,
                    enabled: !locked,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Minutes',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _customIncrement,
                    enabled: !locked,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '+sec/move',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ] else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: Text(
                    _describeControl(preset.control),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Human description of a time control.
  String _describeControl(TimeControl control) {
    switch (control.type) {
      case TimeControlType.none:
        return 'Untimed — clocks hidden.';
      case TimeControlType.fixed:
        return '${control.initialMs ~/ 60000} min each, no increment.';
      case TimeControlType.increment:
        return '${control.initialMs ~/ 60000} min each '
            '+ ${((control.incrementMs ?? 0) / 1000).round()}s/move.';
      case TimeControlType.delay:
        return '${control.initialMs ~/ 60000} min each, '
            '${((control.delayMs ?? 0) / 1000).round()}s delay.';
    }
  }

  /// Moves tab: eval bar, SAN list with tap-to-seek, controls.
  Widget _buildMovesPanel() {
    final total = _sans.length;
    final atStart = _viewPly <= 0 || total == 0;
    final atLive = _viewPly >= total;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          EvalBar(score: _materialPawns(_engine), isHeuristic: true),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              IconButton(
                tooltip: 'First position',
                onPressed: atStart ? null : () => _seekViewPly(0),
                icon: const Icon(Icons.first_page),
              ),
              HoldIconButton(
                tooltip: 'Previous ply (hold to scrub)',
                onStep: atStart ? null : () => _seekViewPly(_viewPly - 1),
                icon: Icons.chevron_left,
              ),
              Expanded(
                child: Text(
                  total == 0 ? 'No moves yet' : 'Ply $_viewPly / $total',
                  textAlign: TextAlign.center,
                ),
              ),
              HoldIconButton(
                tooltip: 'Next ply (hold to scrub)',
                onStep: atLive ? null : () => _seekViewPly(_viewPly + 1),
                icon: Icons.chevron_right,
              ),
              IconButton(
                tooltip: 'Return to live position',
                onPressed: atLive ? null : () => _seekViewPly(total),
                icon: const Icon(Icons.last_page),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: MoveList(
              moves: _sans,
              currentIndex: _viewPly - 1,
              errorPlies: <int>{
                for (var i = 0; i < _fallbacks.length; i++)
                  if (_fallbacks[i]) i,
              },
              onTapMove: (ply) => _seekViewPly(ply + 1),
              maxHeight: double.infinity,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey<String>('play-new-game-button'),
                  onPressed: _live ? null : _start,
                  icon: const Icon(Icons.refresh_outlined),
                  label: const Text('New game'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey<String>('play-resign-button'),
                  onPressed: _canResign ? _confirmResign : null,
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('Resign'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Whether resignation is currently meaningful (a live human seat).
  bool get _canResign {
    final orch = _orch;
    if (orch == null || _result != null || !_live) return false;
    return _whiteKind == SeatKind.human || _blackKind == SeatKind.human;
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

  /// Premove status row.
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

  /// Resign confirmation → resigns the side to move (or the human seat).
  Future<void> _confirmResign() async {
    final orch = _orch;
    if (orch == null || _result != null) return;
    final color = _isHumanSeat(orch.turn)
        ? orch.turn
        : (_whiteKind == SeatKind.human ? 'w' : 'b');
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resign?'),
        content: Text(
          color == 'w'
              ? 'This ends the game as a loss for White (0-1).'
              : 'This ends the game as a loss for Black (1-0).',
        ),
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
      orch.resign(color);
    }
  }
}

/// Standard initial position as square → two-char code.
///
/// Kept for the settings preview; live screens use [squaresOf] over the
/// real engine instead.
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

/// Material balance (White-relative pawns) for the heuristic eval bar.
double _materialPawns(Position position) {
  var total = 0;
  for (final entry in position.board.entries) {
    final v = entry.value.type.value;
    total += entry.value.color.isWhite ? v : -v;
  }
  return (total.toDouble() * 0.4).clamp(-8.0, 8.0).toDouble();
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
