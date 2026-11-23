/// Turn-pump + recording backend for the game room (SRP extraction).
///
/// [GamePump] owns the game room's sequencing job: advancing the mirror
/// [Position] from the orchestrator's authoritative `moveHistory`,
/// running one AI/human turn, and flushing stats/review records. It never
/// touches `BuildContext`/widgets — it communicates out via return values
/// plus the injected [StatsLog]/[ReviewLog]. The screen keeps layout, input
/// handling and the live clock ticker, and calls into [GamePump].
/// Talks to: `game/orchestrator.dart`, `agent/*`, `chess/engine.dart`, `llm/provider.dart`, `telemetry_logs.dart`, `review_resolver.dart`.
/// Never imports: `package:flutter` widgets/material (no `BuildContext`), `storage/local_store`, `hive`.
library;

import '../../agent/agent_config.dart' as agent_backend;
import '../../agent/agent_runner.dart';
import '../../chess/engine.dart' as chess_eng;
import '../../chess/fen.dart';
import '../../chess/position.dart';
import '../../diagnostics/backend_log.dart';
import '../../game/orchestrator.dart';
import '../../llm/provider.dart';
import '../game_mirror.dart';
import '../widgets/board_motion.dart';
import 'activity_mapper.dart';
import 'agent_providers.dart' show closeProvider;
import 'review_resolver.dart';
import 'telemetry_logs.dart';

/// Outcome of one [GamePump.syncMirror] pass.
class MirrorSyncOutcome {
  /// Creates a sync outcome.
  const MirrorSyncOutcome({
    required this.applied,
    required this.changed,
    this.failedUci,
    this.error,
  });

  /// Mirror cursor after the pass.
  final int applied;

  /// Whether at least one move was applied.
  final bool changed;

  /// UCI that failed to apply, if any.
  final String? failedUci;

  /// The failure, or `null` on a clean pass.
  final Object? error;

  /// Whether the pass stopped on a failure.
  bool get hasError => error != null;
}

/// Outcome of one [GamePump.pumpAiTurn] call.
class PumpAiTurnOutcome {
  /// Creates an AI-turn outcome.
  const PumpAiTurnOutcome({
    required this.result,
    required this.grew,
    required this.fallback,
    required this.sync,
    this.crashError,
    this.noMoveMessage,
  });

  /// Runner result, or `null` when the turn was rejected/discarded.
  final AgentTurnResult? result;

  /// Whether the orchestrator history grew.
  final bool grew;

  /// Whether a seeded fallback supplied the move.
  final bool fallback;

  /// Mirror sync performed after the turn.
  final MirrorSyncOutcome sync;

  /// `'AI turn crashed: …'` when `requestAiTurn` threw, else `null`.
  final String? crashError;

  /// `'AI turn produced no move (…)'` when history did not grow, else `null`.
  final String? noMoveMessage;
}

/// Outcome of one [GamePump.applyHumanMove] call.
class HumanMoveOutcome {
  /// Creates a human-move outcome.
  const HumanMoveOutcome({required this.ok, required this.sync});

  /// Whether the orchestrator accepted the move.
  final bool ok;

  /// Mirror sync performed after an accepted move.
  final MirrorSyncOutcome sync;
}

/// One job: advance turns and record them.
///
/// Owns the mirror [Position] (mutated in place by [syncMirror]), the
/// replay cursor, the SAN/phrase/fallback/FEN journals, the last-move trail,
/// the buffered [PendingTurn]s and the seat attribution ids/models. The
/// screen reads these for rendering and drives the loop; this class never
/// touches widgets, `BuildContext` or the activity feed — failures are
/// returned so the screen can log them.
class GamePump {
  /// Creates a pump for [orch] with [mirror] at the start position.
  /// [backendLog] injects the UI-free logger (per-call override wins;
  /// defaults to [currentBackendLog]).
  GamePump({
    required this.orch,
    required this.mirror,
    required this.log,
    required this.reviews,
    this.gameId = 'game',
    this.backendLog,
    String? initialFen,
  }) : fens = <String>[initialFen ?? mirror.toFen()];

  /// Authoritative turn source (recreated per game; pump is recreated too).
  final GameOrchestrator orch;

  /// Visible board state; only advanced by [syncMirror].
  final Position mirror;

  /// Stats backend (turn/result records flush here at game end).
  final StatsLog log;

  /// Review backend (finished games record here at game end).
  final ReviewLog reviews;

  /// Game id for stats/review attribution.
  final String gameId;

  /// UI-free logger (per-call override wins; defaults to [currentBackendLog]).
  final BackendLog? backendLog;

  /// SAN history parallel to the orchestrator's UCI history.
  final List<String> sans = <String>[];

  /// Agent phrases parallel to the UCI history.
  final List<String?> phrases = <String?>[];

  /// Fallback flags parallel to the UCI history.
  final List<bool> fallbacks = <bool>[];

  /// FEN history (`fens[0]` is the start position; one entry per ply + 1).
  final List<String> fens;

  /// How many of the orchestrator's UCIs [mirror] has applied.
  int applied = 0;

  /// Last-move trail.
  String? lastFrom;

  /// Last-move trail.
  String? lastTo;

  /// Most recently applied transition for the motion layer.
  BoardMove? lastMotion;

  /// Drag-initiated moves snap instead of replaying the slide.
  bool suppressNextMotion = false;

  /// Stats turns buffered until game end.
  final List<PendingTurn> pending = <PendingTurn>[];

  /// Bound seat identities for end markers.
  String whiteSeatId = 'human';

  /// Bound seat identities for end markers.
  String blackSeatId = 'demo-black';

  /// Model keys for end markers.
  String whiteModel = 'human';

  /// Model keys for end markers.
  String blackModel = 'mock';

  /// Sets the seat attribution captured at game start.
  void setSeatAttribution({
    required String whiteId,
    required String blackId,
    required String whiteModelKey,
    required String blackModelKey,
  }) {
    whiteSeatId = whiteId;
    blackSeatId = blackId;
    whiteModel = whiteModelKey;
    blackModel = blackModelKey;
  }

  /// Replays unapplied orchestrator UCIs onto [mirror].
  ///
  /// Mirrors the old screen `_syncBoard` replay block exactly (journal
  /// order, FEN snapshots, trail, motion suppression, cursor advance).
  /// Callers log [MirrorSyncOutcome.error] to their activity feed.
  MirrorSyncOutcome syncMirror() {
    final replay = replayMoves(
      orch: orch,
      engine: mirror,
      applied: applied,
      onApplied: (index, uci, move, receipt, meta) {
        sans.add(receipt.san);
        phrases.add(meta.isFallback ? null : meta.phrase);
        fallbacks.add(meta.isFallback);
        fens.add(mirror.toFen());
        lastFrom = move.from.name;
        lastTo = move.to.name;
        if (suppressNextMotion) {
          lastMotion = null;
          suppressNextMotion = false;
        } else {
          lastMotion = BoardMove.fromApplied(receipt);
        }
      },
    );
    applied = replay.applied;
    if (!replay.changed) {
      suppressNextMotion = false;
    }
    return MirrorSyncOutcome(
      applied: replay.applied,
      changed: replay.changed,
      failedUci: replay.failedUci,
      error: replay.error,
    );
  }

  /// Runs one engine-seat turn: bind, request, buffer, sync.
  ///
  /// [provider] must already be resolved by the caller (the screen owns the
  /// `Ref`/catalog seam); it is always closed before returning. Seat
  /// attribution updates before the request, matching the old pump loop.
  /// Never throws for runner failures — they are returned as [crashError].
  /// [backendLog]/[tournamentId] attach the logger and correlation IDs for
  /// this call (game id comes from [gameId]).
  Future<PumpAiTurnOutcome> pumpAiTurn({
    required String color,
    required agent_backend.AgentConfig backend,
    required LlmProvider provider,
    BackendLog? backendLog,
    String? tournamentId,
  }) async {
    final effectiveLog = backendLog ?? this.backendLog ?? currentBackendLog;
    effectiveLog.debug(
      'pump ai start color=$color seq=$applied',
      tag: 'game-pump',
      gameId: gameId,
      tournamentId: tournamentId,
    );
    orch.bindAgent(backend);
    if (color == 'w') {
      whiteSeatId = backend.id;
      whiteModel = backend.model;
    } else {
      blackSeatId = backend.id;
      blackModel = backend.model;
    }
    final before = orch.moveHistory.length;
    AgentTurnResult? result;
    try {
      try {
        result = await orch.requestAiTurn(
          color,
          providerOverride: provider,
          log: effectiveLog,
          gameId: gameId,
          tournamentId: tournamentId,
          seq: before,
        );
      } finally {
        closeProvider(provider);
      }
    } catch (e) {
      effectiveLog.error(
        'pump ai failed kind=crash color=$color seq=$before',
        tag: 'game-pump',
        gameId: gameId,
        tournamentId: tournamentId,
        error: e,
      );
      return PumpAiTurnOutcome(
        result: null,
        grew: false,
        fallback: false,
        sync: MirrorSyncOutcome(applied: applied, changed: false),
        crashError: 'AI turn crashed: $e',
      );
    }
    if (result == null) {
      effectiveLog.debug(
        'pump ai end no-move color=$color seq=$before',
        tag: 'game-pump',
        gameId: gameId,
        tournamentId: tournamentId,
      );
      return PumpAiTurnOutcome(
        result: null,
        grew: false,
        fallback: false,
        sync: MirrorSyncOutcome(applied: applied, changed: false),
      );
    }
    final grew = orch.moveHistory.length > before;
    final fallback = grew && !result.isSuccess;
    if (!grew) {
      effectiveLog.warning(
        'pump ai failed kind=${result.outcome.kind.name} color=$color '
        'seq=$before',
        tag: 'game-pump',
        gameId: gameId,
        tournamentId: tournamentId,
      );
    } else {
      effectiveLog.debug(
        'pump ai end grew=true fallback=$fallback color=$color seq=$before',
        tag: 'game-pump',
        gameId: gameId,
        tournamentId: tournamentId,
      );
    }
    pending.add(
      PendingTurn.ai(
        agentId: backend.id,
        modelKey: backend.model,
        color: color == 'w' ? 'white' : 'black',
        mode: 'standard',
        result: result,
        fallback: fallback,
      ),
    );
    final sync = syncMirror();
    final String? noMove = grew
        ? null
        : 'AI turn produced no move (${result.outcome.kind.name}).';
    return PumpAiTurnOutcome(
      result: result,
      grew: grew,
      fallback: fallback,
      sync: sync,
      noMoveMessage: noMove,
    );
  }

  /// Applies a human UCI through the orchestrator, buffers stats, syncs.
  ///
  /// Returns `ok: false` (no buffering, no sync) when the orchestrator
  /// rejects the move — the caller surfaces the rejection. [suppressMotion]
  /// marks drag-initiated moves to snap instead of replaying the slide.
  /// [backendLog]/[tournamentId] attach the logger and correlation IDs.
  HumanMoveOutcome applyHumanMove({
    required String uci,
    required String moverColor,
    required int elapsedMs,
    bool suppressMotion = false,
    BackendLog? backendLog,
    String? tournamentId,
  }) {
    final effectiveLog = backendLog ?? this.backendLog ?? currentBackendLog;
    effectiveLog.debug(
      'pump human start uci=$uci seq=$applied',
      tag: 'game-pump',
      gameId: gameId,
      tournamentId: tournamentId,
    );
    if (suppressMotion) {
      suppressNextMotion = true;
    }
    final ok = orch.applyHumanMove(uci, elapsedMs: elapsedMs);
    if (!ok) {
      suppressNextMotion = false;
      effectiveLog.debug(
        'pump human rejected uci=$uci seq=$applied',
        tag: 'game-pump',
        gameId: gameId,
        tournamentId: tournamentId,
      );
      return HumanMoveOutcome(
        ok: false,
        sync: MirrorSyncOutcome(applied: applied, changed: false),
      );
    }
    pending.add(
      PendingTurn(
        agentId: 'human',
        modelKey: 'human',
        color: moverColor == 'w' ? 'white' : 'black',
        mode: 'standard',
        human: true,
      ),
    );
    final sync = syncMirror();
    effectiveLog.debug(
      'pump human end uci=$uci seq=$applied',
      tag: 'game-pump',
      gameId: gameId,
      tournamentId: tournamentId,
    );
    return HumanMoveOutcome(ok: true, sync: sync);
  }

  /// Finishes the game: reports engine terminals, flushes stats, logs review.
  ///
  /// Returns the score outcome (`'1-0'`/`'0-1'`/`'1/2-1/2'`/`'*'`), or `null`
  /// when no terminal is available yet. Idempotent w.r.t. buffering: the
  /// pending list is cleared after flushing. [backendLog]/[tournamentId]
  /// attach the logger and correlation IDs.
  String? flushGameEnd({
    required String whiteLabel,
    required String blackLabel,
    BackendLog? backendLog,
    String? tournamentId,
  }) {
    final effectiveLog = backendLog ?? this.backendLog ?? currentBackendLog;
    effectiveLog.debug(
      'pump flush start seq=$applied',
      tag: 'game-pump',
      gameId: gameId,
      tournamentId: tournamentId,
    );
    var outcome = orch.result?.outcome;
    if (outcome == null) {
      final terminal = chess_eng.ChessRules.resultOf(mirror);
      if (terminal == null) {
        effectiveLog.debug(
          'pump flush end no-terminal seq=$applied',
          tag: 'game-pump',
          gameId: gameId,
          tournamentId: tournamentId,
        );
        return null;
      }
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
    for (final turn in pending) {
      turn.flush(log: log, gameId: gameId);
    }
    pending.clear();
    logGameResults(
      log: log,
      gameId: gameId,
      whiteAgentId: whiteSeatId,
      blackAgentId: blackSeatId,
      whiteModelKey: whiteModel,
      blackModelKey: blackModel,
      mode: 'standard',
      outcome: outcome,
    );
    reviews.record(
      ReviewGame(
        id: '$gameId-${DateTime.now().millisecondsSinceEpoch}',
        whiteLabel: whiteLabel,
        blackLabel: blackLabel,
        whiteAgentId: whiteSeatId,
        blackAgentId: blackSeatId,
        ucis: orch.moveHistory,
        sans: List<String>.of(sans),
        fens: List<String>.of(fens),
        phrases: List<String?>.of(phrases),
        fallbackFlags: List<bool>.of(fallbacks),
      ),
    );
    effectiveLog.debug(
      'pump flush end outcome=$outcome seq=$applied',
      tag: 'game-pump',
      gameId: gameId,
      tournamentId: tournamentId,
    );
    return outcome;
  }
}
