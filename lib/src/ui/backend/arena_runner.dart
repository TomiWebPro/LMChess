/// Single-game tournament execution for the arena.
///
/// [ArenaRunner] owns exactly one job: run one scheduled [Pairing] to a
/// [GameResultSummary] (which wraps the terminal [TournamentGameResult]).
/// The arena screen keeps config state, scheduler invocation, grid rendering
/// and standings/Elo; it delegates the per-game pump to this runner and only
/// applies the [ArenaGameSnapshot]s it receives via [onProgress].
///
/// * **Standard** games run a full [GameOrchestrator] (two AI seats) with the
///   same sequential pump the watch room uses: bind the roster config, one
///   `requestAiTurn` with a caller-supplied provider override, replay the UCI
///   history onto a mirror [Position] (idempotent sync), feed the fresh legal
///   list back via `setPosition`, and report engine terminals.
/// * **Chaotic** games run [AgentRunner.runTurn] directly against a
///   [VariantBoard] JSON payload, validate against a pseudo-legal attempt
///   list, interpret every attempt through [ChaoticRules.interpret] and
///   adjudicate king captures with [ChaoticRules.gameOver]. Definitive
///   failures fall back to a seeded attempt (explicitly marked, unattributed).
///
/// Finished games flush buffered [PendingTurn]s to [StatsLog], write
/// per-agent W/L/D markers and land in [ReviewLog] (standard) or
/// [VariantReviewLog] (chaotic, lossless). Elo stays with the screen.
///
/// The runner never touches `BuildContext`/`Widget`: outward communication
/// is the returned [GameResultSummary] plus the optional [onProgress]
/// snapshots the screen renders into its own live models.
/// Talks to: `game/` orchestrator+clock+state, `arena/` scheduler+tournament, `chess/`+`variant/`, `llm/`, `telemetry_logs.dart`.
/// Never imports: `package:flutter` widgets/material, `storage/local_store`, `hive` — no `BuildContext`/`Widget`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import '../../agent/agent_config.dart' as backend_cfg;
import '../../agent/agent_runner.dart';
import '../../arena/scheduler.dart';
import '../../arena/tournament.dart';
import '../../chess/engine.dart' as chess_eng;
import '../../chess/fen.dart';
import '../../chess/move.dart';
import '../../chess/piece.dart';
import '../../chess/position.dart';
import '../../diagnostics/backend_log.dart';
import '../../game/clock.dart';
import '../../game/game_state.dart';
import '../../game/orchestrator.dart';
import '../../llm/anthropic_provider.dart';
import '../../llm/gemini_provider.dart';
import '../../llm/openai_provider.dart';
import '../../llm/prompt_board.dart';
import '../../llm/provider.dart';
import 'board_mapper.dart';
import 'review_resolver.dart';
import 'telemetry_logs.dart';
import '../../variant/chaotic_engine.dart';
import '../../variant/interpretation.dart';
import '../../variant/variant_board.dart';
import '../../variant/variant_replay.dart';

/// Turn-provider factory the pumps resolve each AI turn through.
///
/// Structurally identical to the UI seam (`TurnProviderFactory`) but declared
/// here so the arena layer does not import Riverpod/UI providers.
typedef ArenaTurnProviderFactory = Future<LlmProvider> Function(
  backend_cfg.AgentConfig config,
  List<String> legalUcis, {
  int? seed,
  String? phrase,
});

/// Immutable per-ply snapshot of a running tournament game.
///
/// The runner emits copies (never live references) after every ply and once
/// more with the terminal [outcome]/[reason]; the screen copies them into
/// its own live models and re-renders.
class ArenaGameSnapshot {
  /// Creates a snapshot. Lists/maps must already be copies.
  const ArenaGameSnapshot({
    required this.squares,
    required this.ucis,
    required this.sans,
    required this.fens,
    required this.phrases,
    required this.fallbacks,
    required this.interpretations,
    required this.variantPlies,
    this.initialBoard,
    this.startedAt,
    this.lastFrom,
    this.lastTo,
    this.inCheck,
    this.terminalSquare,
    this.outcome = '*',
    this.reason = '',
  });

  /// Current board for rendering (`'e4' → 'wP'`).
  final Map<String, String> squares;

  /// Played attempts in UCI order (chaotic plies are attempt UCIs).
  final List<String> ucis;

  /// Move labels parallel to [ucis] (SAN for standard, UCI for chaotic).
  final List<String> sans;

  /// FEN history parallel to [ucis] (+1, start first); standard only.
  final List<String> fens;

  /// Agent phrases parallel to [ucis] (`null` for fallbacks).
  final List<String?> phrases;

  /// Fallback flags parallel to [ucis].
  final List<bool> fallbacks;

  /// Chaotic only: interpretation strategy id per ply.
  final List<String> interpretations;

  /// Chaotic only: lossless replay records parallel to [ucis].
  final List<VariantPlyRecord> variantPlies;

  /// Chaotic only: starting board for replay.
  final VariantBoard? initialBoard;

  /// Chaotic only: wall-clock start.
  final DateTime? startedAt;

  /// Last-move trail / check highlights (standard only for check squares).
  final String? lastFrom;
  final String? lastTo;
  final String? inCheck;
  final String? terminalSquare;

  /// Terminal outcome (`'1-0'`, `'0-1'`, `'1/2-1/2'`, `'*'`) and reason.
  final String outcome;
  final String reason;
}

/// Progress callback the runner invokes after every ply and at termination.
typedef ArenaProgressCallback = void Function(ArenaGameSnapshot snapshot);

/// Runs one tournament pairing to a [GameResultSummary].
///
/// Owns the mode-specific pump plus stats/review writes. Elo stays with the
/// caller (screen), which maps [GameResultSummary.result] through its own
/// Elo vocabulary.
class ArenaRunner {
  /// Creates a runner writing turns to [log], standard games to [reviews]
  /// and chaotic replays to [variantReviews]. [backendLog] injects the
  /// UI-free logger (per-call override wins; defaults to
  /// [currentBackendLog]).
  const ArenaRunner({
    required this.log,
    required this.reviews,
    required this.variantReviews,
    this.backendLog,
  });

  /// Stats backend (turn/result records).
  final StatsLog log;

  /// Standard-game review store (FEN-based).
  final ReviewLog reviews;

  /// Chaotic-variant replay store (lossless board chain).
  final VariantReviewLog variantReviews;

  /// UI-free logger (per-call override wins; defaults to [currentBackendLog]).
  final BackendLog? backendLog;

  /// Standard pump: orchestrator + mirror engine (watch-room pattern).
  ///
  /// [backendLog] overrides [backendLog]/[currentBackendLog] for this call;
  /// the pairing's game/tournament ids are the correlation IDs.
  Future<GameResultSummary> runStandard({
    required TournamentConfig config,
    required Pairing pairing,
    required Map<String, backend_cfg.AgentConfig> agents,
    required int seed,
    required ArenaTurnProviderFactory turnProviderFactory,
    bool Function()? isCancelled,
    ArenaProgressCallback? onProgress,
    void Function(GameOrchestrator?)? onOrchestrator,
    BackendLog? backendLog,
  }) async {
    final effectiveLog = backendLog ?? this.backendLog ?? currentBackendLog;
    effectiveLog.debug(
      'arena standard start seed=$seed',
      tag: 'arena-runner',
      gameId: pairing.gameId,
      tournamentId: config.id,
    );
    final white = agents[pairing.whiteAgentId];
    final black = agents[pairing.blackAgentId];
    if (white == null || black == null) {
      effectiveLog.warning(
        'arena standard failed kind=missingAgent',
        tag: 'arena-runner',
        gameId: pairing.gameId,
        tournamentId: config.id,
      );
      return GameResultSummary(
        gameId: pairing.gameId,
        whiteAgentId: pairing.whiteAgentId,
        blackAgentId: pairing.blackAgentId,
        infraFailure: 'agent config missing from the roster snapshot',
      );
    }
    bool cancelled() => isCancelled?.call() ?? false;
    final engine = Position.initial();
    final ucis = <String>[];
    final sans = <String>[];
    final fens = <String>[standardStartFen];
    final phrases = <String?>[];
    final fallbacks = <bool>[];
    var squares = squaresOf(engine);
    String? lastFrom;
    String? lastTo;
    String? inCheck;
    String? terminalSquare;
    var applied = 0;
    final pending = <PendingTurn>[];

    void emit({String outcome = '*', String reason = ''}) {
      onProgress?.call(
        ArenaGameSnapshot(
          squares: Map<String, String>.of(squares),
          ucis: List<String>.of(ucis),
          sans: List<String>.of(sans),
          fens: List<String>.of(fens),
          phrases: List<String?>.of(phrases),
          fallbacks: List<bool>.of(fallbacks),
          interpretations: const <String>[],
          variantPlies: const <VariantPlyRecord>[],
          lastFrom: lastFrom,
          lastTo: lastTo,
          inCheck: inCheck,
          terminalSquare: terminalSquare,
          outcome: outcome,
          reason: reason,
        ),
      );
    }

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
    onOrchestrator?.call(orch);
    orch.setPosition(
      standardStartFen,
      turn: 'w',
      legalMoves: legalUcis(engine),
    );
    orch.startGame();
    try {
      while (!cancelled()) {
        if (_isTerminal(orch.state)) break;
        if (orch.state != OrchestratorState.waitingAi) break;
        if (orch.legalMoves.isEmpty) break;
        final color = orch.turn;
        final backend = color == 'w' ? white : black;
        orch.bindAgent(backend);
        final before = orch.moveHistory.length;
        final provider = await turnProviderFactory(
          backend,
          orch.legalMoves,
          seed: _turnSeed(seed, before),
          phrase: '${backend.name} move',
        );
        AgentTurnResult? result;
        try {
          result = await orch.requestAiTurn(
            color,
            providerOverride: provider,
            log: effectiveLog,
            gameId: pairing.gameId,
            tournamentId: config.id,
            seq: before,
          );
        } finally {
          _closeProvider(provider);
        }
        final replay = _replayStandard(
          orch: orch,
          engine: engine,
          applied: applied,
          onApplied: (index, uci, move, receipt, meta) {
            sans.add(receipt.san);
            ucis.add(uci);
            phrases.add(meta.isFallback ? null : meta.phrase);
            fallbacks.add(meta.isFallback);
            fens.add(engine.toFen());
            squares = squaresOf(engine);
            lastFrom = move.from.name;
            lastTo = move.to.name;
            inCheck = checkSquare(engine);
          },
        );
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
              log: log,
              gameId: pairing.gameId,
              tournamentId: config.id,
            );
          }
          final detail = replay.hasError
              ? 'mirror desync at ply $applied: ${replay.error}'
              : 'mirror desync at ply $applied';
          effectiveLog.error(
            'arena standard failed kind=mirrorDesync ply=$applied',
            tag: 'arena-runner',
            gameId: pairing.gameId,
            tournamentId: config.id,
            error: replay.error,
          );
          emit(reason: detail);
          return GameResultSummary(
            gameId: pairing.gameId,
            whiteAgentId: pairing.whiteAgentId,
            blackAgentId: pairing.blackAgentId,
            infraFailure: detail,
          );
        }
        if (!_isTerminal(orch.state)) {
          orch.setPosition(
            engine.toFen(),
            turn: engine.sideToMove.isWhite ? 'w' : 'b',
            legalMoves: legalUcis(engine),
          );
        }
        final terminal = chess_eng.ChessRules.resultOf(engine);
        if (terminal != null && !_isTerminal(orch.state)) {
          if (terminal.termination == chess_eng.GameTermination.checkmate) {
            terminalSquare = engine.kingSquare(engine.sideToMove)?.name;
          }
          final mapped = _mapTerminal(terminal);
          orch.reportTerminal(
            GameResult(
              outcome: mapped.outcome,
              reason: mapped.reason,
              winnerColor: mapped.winnerColor,
            ),
          );
        }
        emit();
      }
    } finally {
      onOrchestrator?.call(null);
      orch.dispose();
    }
    if (orch.state == OrchestratorState.failed) {
      for (final turn in pending) {
        turn.flush(log: log, gameId: pairing.gameId, tournamentId: config.id);
      }
      final detail = orch.failureMessage ?? 'orchestrator failed';
      effectiveLog.error(
        'arena standard failed kind=orchestratorFailed seq=$applied',
        tag: 'arena-runner',
        gameId: pairing.gameId,
        tournamentId: config.id,
      );
      emit(reason: detail);
      return GameResultSummary(
        gameId: pairing.gameId,
        whiteAgentId: pairing.whiteAgentId,
        blackAgentId: pairing.blackAgentId,
        infraFailure: detail,
      );
    }
    final outcome = orch.result?.outcome ?? '*';
    final reason = orch.result?.reason ?? '';
    final mapped = _mapOutcome(outcome, reason);
    for (final turn in pending) {
      turn.flush(log: log, gameId: pairing.gameId, tournamentId: config.id);
    }
    logGameResults(
      log: log,
      gameId: pairing.gameId,
      whiteAgentId: pairing.whiteAgentId,
      blackAgentId: pairing.blackAgentId,
      tournamentId: config.id,
      whiteModelKey: agents[pairing.whiteAgentId]?.model ?? '',
      blackModelKey: agents[pairing.blackAgentId]?.model ?? '',
      mode: config.mode,
      outcome: outcome,
    );
    reviews.record(
      ReviewGame(
        id: pairing.gameId,
        whiteLabel: white.name,
        blackLabel: black.name,
        whiteAgentId: pairing.whiteAgentId,
        blackAgentId: pairing.blackAgentId,
        mode: config.mode,
        ucis: List<String>.of(ucis),
        sans: List<String>.of(sans),
        fens: List<String>.of(fens),
        phrases: List<String?>.of(phrases),
        fallbackFlags: List<bool>.of(fallbacks),
      ),
    );
    emit(outcome: outcome, reason: reason);
    effectiveLog.debug(
      'arena standard end outcome=$outcome seq=$applied',
      tag: 'arena-runner',
      gameId: pairing.gameId,
      tournamentId: config.id,
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
  Future<GameResultSummary> runChaotic({
    required TournamentConfig config,
    required Pairing pairing,
    required Map<String, backend_cfg.AgentConfig> agents,
    required int seed,
    required ArenaTurnProviderFactory turnProviderFactory,
    AgentRunner? chaosRunner,
    DateTime Function()? clock,
    bool Function()? isCancelled,
    ArenaProgressCallback? onProgress,
    BackendLog? backendLog,
  }) async {
    final effectiveLog = backendLog ?? this.backendLog ?? currentBackendLog;
    effectiveLog.debug(
      'arena chaotic start seed=$seed',
      tag: 'arena-runner',
      gameId: pairing.gameId,
      tournamentId: config.id,
    );
    final white = agents[pairing.whiteAgentId];
    final black = agents[pairing.blackAgentId];
    if (white == null || black == null) {
      effectiveLog.warning(
        'arena chaotic failed kind=missingAgent',
        tag: 'arena-runner',
        gameId: pairing.gameId,
        tournamentId: config.id,
      );
      return GameResultSummary(
        gameId: pairing.gameId,
        whiteAgentId: pairing.whiteAgentId,
        blackAgentId: pairing.blackAgentId,
        infraFailure: 'agent config missing from the roster snapshot',
      );
    }
    bool cancelled() => isCancelled?.call() ?? false;
    DateTime now() => (clock ?? DateTime.now)();
    final runner = chaosRunner ?? const AgentRunner();
    var board = VariantBoard.fromStandard(Position.initial());
    final pending = <PendingTurn>[];
    final initialBoard = board;
    final variantPlies = <VariantPlyRecord>[];
    final startedAt = now().toUtc();
    final ucis = <String>[];
    final sans = <String>[];
    final phrases = <String?>[];
    final fallbacks = <bool>[];
    final interpretations = <String>[];
    var squares = _variantSquares(board);
    String? lastFrom;
    String? lastTo;
    var ply = 0;
    var outcome = '*';
    var reason = '';

    void emit() {
      onProgress?.call(
        ArenaGameSnapshot(
          squares: Map<String, String>.of(squares),
          ucis: List<String>.of(ucis),
          sans: List<String>.of(sans),
          fens: const <String>[],
          phrases: List<String?>.of(phrases),
          fallbacks: List<bool>.of(fallbacks),
          interpretations: List<String>.of(interpretations),
          variantPlies: List<VariantPlyRecord>.of(variantPlies),
          initialBoard: initialBoard,
          startedAt: startedAt,
          lastFrom: lastFrom,
          lastTo: lastTo,
          outcome: outcome,
          reason: reason,
        ),
      );
    }

    emit();
    while (true) {
      if (cancelled()) {
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
      final backend = moverColor.isWhite ? white : black;
      final attempts = _variantAttempts(board);
      if (attempts.isEmpty) {
        reason = 'noAttempts';
        break;
      }
      final turnSeed = _turnSeed(seed, ply);
      final provider = await turnProviderFactory(
        backend,
        attempts,
        seed: turnSeed,
        phrase: '${backend.name} move',
      );
      AgentTurnResult? result;
      final promptState = _variantPromptState(board);
      try {
        result = await runner.runTurn(
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
      } catch (error, stackTrace) {
        // Runner internals only; treated as provider error. Log the failure
        // so a genuine runner bug is distinguishable from a provider outage
        // in the stats (both degrade to the same seeded fallback below).
        result = null;
        effectiveLog.error(
          'arena chaotic turn failed kind=providerError ply=$ply — '
          'degrading to a seeded fallback attempt',
          tag: 'arena-chaos',
          gameId: pairing.gameId,
          tournamentId: config.id,
          error: error,
          stackTrace: stackTrace,
        );
      } finally {
        _closeProvider(provider);
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
            mode: config.mode,
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
              mode: config.mode,
              result: result,
              fallback: true,
            ),
          );
        } else {
          log.logTurn(
            gameId: pairing.gameId,
            agentId: backend.id,
            tournamentId: config.id,
            modelKey: backend.model,
            color: colorName,
            mode: config.mode,
            providerError: true,
          );
        }
      }
      final boardBefore = board;
      final rawTool = _rawToolCallFrom(
        result,
        backendLog: effectiveLog,
        gameId: pairing.gameId,
        tournamentId: config.id,
      );
      final selectedMove = result?.selectedMove;
      final attemptFrom =
          selectedMove?.from ??
          (attemptUci.length >= 2 ? attemptUci.substring(0, 2) : '');
      final attemptTo =
          selectedMove?.to ??
          (attemptUci.length >= 4 ? attemptUci.substring(2, 4) : '');
      final attemptPromotion =
          selectedMove?.promotion ??
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
      variantPlies.add(
        VariantPlyRecord(
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
          selected: VariantInterpretationRecord.fromCandidate(
            interpreted.selected,
          ),
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
        ),
      );
      board = interpreted.selected.resultingBoard;
      ply++;
      ucis.add(attemptUci);
      sans.add(attemptUci); // Chaotic plies have no SAN; UCI is honest.
      phrases.add(wasFallback ? null : phrase);
      fallbacks.add(wasFallback);
      interpretations.add(
        '${interpreted.selected.strategyId}'
        '${interpreted.selected.capturesKing ? ' · king captured' : ''}',
      );
      squares = _variantSquares(board);
      // Exact trail only for standard-legal attempts; an interpretation
      // (teleport, closest-legal, …) may have moved another piece.
      if (interpreted.wasLegal) {
        lastFrom = attemptUci.substring(0, 2);
        lastTo = attemptUci.substring(2, 4);
      } else {
        lastFrom = null;
        lastTo = null;
      }
      emit();
    }
    final mapped = _mapOutcome(outcome, reason);
    for (final turn in pending) {
      turn.flush(log: log, gameId: pairing.gameId, tournamentId: config.id);
    }
    logGameResults(
      log: log,
      gameId: pairing.gameId,
      whiteAgentId: pairing.whiteAgentId,
      blackAgentId: pairing.blackAgentId,
      tournamentId: config.id,
      whiteModelKey: agents[pairing.whiteAgentId]?.model ?? '',
      blackModelKey: agents[pairing.blackAgentId]?.model ?? '',
      mode: config.mode,
      outcome: outcome,
    );
    // Chaotic games land in the lossless variant replay log (board chain +
    // attempts + readings); the FEN-based review log is standard-only.
    variantReviews.record(
      VariantGameRecord(
        id: pairing.gameId,
        tournamentId: config.id,
        whiteLabel: white.name,
        blackLabel: black.name,
        whiteAgentId: pairing.whiteAgentId,
        blackAgentId: pairing.blackAgentId,
        seed: seed,
        initialBoard: initialBoard,
        plies: List<VariantPlyRecord>.of(variantPlies),
        outcome: outcome,
        reason: reason,
        startedAt: startedAt,
        finishedAt: now().toUtc(),
      ),
    );
    emit();
    effectiveLog.debug(
      'arena chaotic end outcome=$outcome seq=$ply',
      tag: 'arena-runner',
      gameId: pairing.gameId,
      tournamentId: config.id,
    );
    return GameResultSummary(
      gameId: pairing.gameId,
      whiteAgentId: pairing.whiteAgentId,
      blackAgentId: pairing.blackAgentId,
      result: mapped,
    );
  }

  /// Replays unapplied orchestrator UCIs onto the mirror engine.
  _ReplayOutcome _replayStandard({
    required GameOrchestrator orch,
    required Position engine,
    required int applied,
    required void Function(
      int moveIndex,
      String uci,
      ChessMove move,
      AppliedMove receipt,
      ({String? phrase, bool isFallback}) meta,
    )
    onApplied,
  }) {
    var next = applied;
    final history = orch.moveHistory;
    while (next < history.length) {
      final uci = history[next];
      final ChessMove move;
      final AppliedMove receipt;
      final ({String? phrase, bool isFallback}) meta;
      try {
        move = ChessMove.fromUci(uci);
        receipt = engine.apply(move);
        meta = _appliedMetaFor(orch, next + 1);
      } catch (e) {
        return _ReplayOutcome(applied: next, error: e);
      }
      final index = next;
      next++;
      try {
        onApplied(index, uci, move, receipt, meta);
      } catch (e) {
        return _ReplayOutcome(applied: next, error: e);
      }
    }
    return _ReplayOutcome(applied: next);
  }

  /// Phrase/fallback metadata for the orchestrator's `moveApplied` entry
  /// [moveIndex] (1-based, matching the event payload's `moveIndex`).
  ({String? phrase, bool isFallback}) _appliedMetaFor(
    GameOrchestrator orch,
    int moveIndex,
  ) {
    for (var i = orch.eventLog.length - 1; i >= 0; i--) {
      final event = orch.eventLog[i];
      if (event.type == 'moveApplied' &&
          event.payload['moveIndex'] == moveIndex) {
        final phrase = event.payload['phrase'];
        return (
          phrase: phrase is String ? phrase : null,
          isFallback: event.payload['isFallback'] == true,
        );
      }
    }
    return (phrase: null, isFallback: false);
  }

  /// Maps a chess-rules terminal verdict to the orchestrator result shape.
  ({String outcome, String? winnerColor, String reason}) _mapTerminal(
    chess_eng.GameResult terminal,
  ) {
    switch (terminal.termination) {
      case chess_eng.GameTermination.checkmate:
      case chess_eng.GameTermination.resignation:
      case chess_eng.GameTermination.timeout:
        final whiteWins = terminal.winner == PieceColor.white;
        return (
          outcome: whiteWins ? '1-0' : '0-1',
          winnerColor: whiteWins ? 'w' : 'b',
          reason: terminal.termination.name,
        );
      case chess_eng.GameTermination.stalemate:
      case chess_eng.GameTermination.fiftyMove:
      case chess_eng.GameTermination.insufficientMaterial:
      case chess_eng.GameTermination.agreement:
        return (
          outcome: '1/2-1/2',
          winnerColor: null,
          reason: terminal.termination.name,
        );
      case chess_eng.GameTermination.aborted:
        return (outcome: '*', winnerColor: null, reason: 'aborted');
    }
  }

  /// Extracts the raw tool-call JSON from the last completed call in
  /// [result]. Falls back to [AgentTurnResult.selectedMove] when the event
  /// stream did not retain the raw string. Never throws. [backendLog] and
  /// the correlation IDs route the unparseable-JSON warning.
  ({String? rawToolArgsJson, Map<String, Object?>? rawToolCallJson})
  _rawToolCallFrom(
    AgentTurnResult? result, {
    BackendLog? backendLog,
    String? gameId,
    String? tournamentId,
  }) {
    if (result == null) {
      return (rawToolArgsJson: null, rawToolCallJson: null);
    }
    for (var i = result.events.length - 1; i >= 0; i--) {
      final event = result.events[i];
      if (event.kind != StreamEventKind.toolCallCompleted) continue;
      final raw = event.toolArgsJson;
      if (raw == null || raw.isEmpty) continue;
      Object? decoded;
      try {
        decoded = jsonDecode(raw);
      } catch (error) {
        decoded = null;
        (backendLog ?? this.backendLog ?? currentBackendLog).warning(
          'rawToolCallFrom failed kind=unparseable — keeping raw string',
          tag: 'arena-runner',
          gameId: gameId,
          tournamentId: tournamentId,
          error: error,
        );
      }
      return (
        rawToolArgsJson: raw,
        rawToolCallJson: decoded is Map
            ? Map<String, Object?>.from(decoded)
            : null,
      );
    }
    final move = result.selectedMove;
    return (
      rawToolArgsJson: move == null ? null : jsonEncode(move.toJson()),
      rawToolCallJson: move?.toJson(),
    );
  }

  /// Whether [state] is terminal (finished/failed).
  bool _isTerminal(OrchestratorState state) =>
      state == OrchestratorState.finished || state == OrchestratorState.failed;

  /// Closes network providers the pump created for `providerOverride` turns.
  ///
  /// The runner only closes providers it created itself; [MockProvider] has
  /// nothing to close.
  void _closeProvider(LlmProvider provider) {
    if (provider is OpenAiProvider) {
      provider.close();
    } else if (provider is AnthropicProvider) {
      provider.close();
    } else if (provider is GeminiProvider) {
      provider.close();
    }
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
    final castling = <String>['K', 'Q', 'k', 'q'].where(rights.contains).join();
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

  /// Renders a [VariantBoard] as a `Chessboard`-style `squares` map.
  Map<String, String> _variantSquares(VariantBoard board) {
    return <String, String>{
      for (final e in board.squares.entries)
        e.key.name: '${colorCode(e.value.color)}${e.value.type.letter}',
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
}

/// Outcome of one mirror-replay pass.
class _ReplayOutcome {
  /// Creates a replay outcome.
  const _ReplayOutcome({required this.applied, this.error});

  /// Number of orchestrator UCIs the mirror has applied after the pass.
  final int applied;

  /// The failure, or `null` on a clean pass.
  final Object? error;

  /// Whether the pass stopped on a failure.
  bool get hasError => error != null;
}
