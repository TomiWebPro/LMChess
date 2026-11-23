/// Orchestrator/event mapping extracted from the UI backend bridge.
///
/// Pure adapters from orchestrator and chess-engine verdicts to the activity
/// panel and result shapes: terminal mapping, per-event activity mapping,
/// state predicates, metadata lookup, lifecycle retirement, raw tool-call
/// extraction, and the game-result shorthand.
/// Talks to: `game/orchestrator.dart`+`game_state.dart`, `chess/engine.dart` verdicts, `llm/provider.dart`; feeds `widgets/activity_panel.dart`.
/// Never imports: `package:flutter` widgets/material, `storage/local_store`, `hive` — pure adapters.
library;

import 'dart:async';
import 'dart:convert';

import '../../agent/agent_runner.dart';
import '../../chess/engine.dart' as chess_eng;
import '../../chess/piece.dart';
import '../../diagnostics/app_log.dart';
import '../../game/game_state.dart' as gs;
import '../../game/orchestrator.dart';
import '../../llm/provider.dart';
import '../widgets/activity_panel.dart';

/// Maps a chess-rules terminal verdict to the orchestrator result shape.
///
/// Checkmate/resignation/timeout decide by [chess_eng.GameResult.winner];
/// automatic draws (stalemate, fifty-move, insufficient material,
/// agreement) and aborts map to `'1/2-1/2'`/`'*'` with the termination
/// name as reason.
({String outcome, String reason, String? winnerColor}) mapTerminal(
  chess_eng.GameResult terminal,
) {
  switch (terminal.termination) {
    case chess_eng.GameTermination.checkmate:
    case chess_eng.GameTermination.resignation:
    case chess_eng.GameTermination.timeout:
      final whiteWins = terminal.winner == PieceColor.white;
      return (
        outcome: whiteWins ? '1-0' : '0-1',
        reason: terminal.termination.name,
        winnerColor: whiteWins ? 'w' : 'b',
      );
    case chess_eng.GameTermination.stalemate:
    case chess_eng.GameTermination.fiftyMove:
    case chess_eng.GameTermination.insufficientMaterial:
    case chess_eng.GameTermination.agreement:
      return (
        outcome: '1/2-1/2',
        reason: terminal.termination.name,
        winnerColor: null,
      );
    case chess_eng.GameTermination.aborted:
      return (outcome: '*', reason: 'aborted', winnerColor: null);
  }
}

String? _payloadString(Map<String, Object?> payload, String key) {
  final value = payload[key];
  return value is String ? value : null;
}

int? _payloadInt(Map<String, Object?> payload, String key) {
  final value = payload[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}

/// Maps one orchestrator [GameEvent] to an [ActivityEvent] for the panel.
///
/// Returns `null` for `positionSet` (per-move intake noise), for the
/// redundant `aiStream/started` + `aiStream/done` lifecycle bookends, for
/// `toolCallCompleted` (the move is implied by the board and the Moves tab,
/// so the raw JSON tile is a big box with no readable info), for
/// `aiTurnStarted`/`gameStarted`/`moveApplied` (STARTED/DONE tiles restate
/// what the board, clock and Moves tab already show — the feed keeps the
/// thinking stream: STATUS, TEXT with usage folded in, and errors), and
/// for `turnSummary` (metrics telemetry already consumed by StatsLog;
/// rendering its type name as a tile adds no human-readable info).
/// Everything else keeps its message, tokens and latency.
ActivityEvent? activityFromGameEvent(GameEvent event) {
  final p = event.payload;
  switch (event.type) {
    case 'positionSet':
    case 'turnSummary':
    case 'gameStarted':
    case 'aiTurnStarted':
    case 'moveApplied':
    case 'aiStream':
      final kind = _payloadString(p, 'kind') ?? '';
      final message =
          _payloadString(p, 'message') ?? _payloadString(p, 'text') ?? '';
      switch (kind) {
        case 'started':
        case 'done':
          return null;
        case 'status':
          return ActivityEvent(
            kind: ActivityEventKind.status,
            message: message,
          );
        case 'textDelta':
          return ActivityEvent(
            kind: ActivityEventKind.textDelta,
            message: _payloadString(p, 'text') ?? message,
          );
        case 'toolCallDelta':
          // Intermediate fragment — the completed call below carries the
          // full args, so showing both doubles the TOOL tiles for no gain.
          return null;
        case 'toolCallCompleted':
          // Dropped: the move is visible on the board and in the Moves
          // tab, so a raw `{"from":..,"to":..}` JSON tile adds a big box
          // with no human-readable information.
          return null;
        case 'usage':
          return ActivityEvent(
            kind: ActivityEventKind.usage,
            message: message.isEmpty ? 'turn usage' : message,
            promptTokens: _payloadInt(p, 'tokensIn'),
            completionTokens: _payloadInt(p, 'tokensOut'),
          );
        case 'latency':
          return ActivityEvent(
            kind: ActivityEventKind.latency,
            message: message.isEmpty ? 'turn latency' : message,
            latencyMs: _payloadInt(p, 'latencyMs'),
          );
        case 'error':
        case 'errorRetry':
          return ActivityEvent(kind: ActivityEventKind.error, message: message);
        default:
          return ActivityEvent(
            kind: ActivityEventKind.status,
            message: message.isEmpty ? 'stream: $kind' : message,
          );
      }
    case 'fallbackApplied':
      return ActivityEvent(
        kind: ActivityEventKind.status,
        message:
            'Fallback ${_payloadString(p, 'chosenUci') ?? '?'} after '
            '${_payloadString(p, 'reason') ?? 'failure'} '
            '(seeded, unattributed)',
      );
    case 'aiTurnFailed':
      return ActivityEvent(
        kind: ActivityEventKind.error,
        message:
            'AI turn failed (${_payloadString(p, 'kind') ?? 'error'}): '
                    '${_payloadString(p, 'error') ?? ''}'
                .trim(),
      );
    case 'turnRejected':
    case 'humanMoveRejected':
    case 'startRejected':
      return ActivityEvent(
        kind: ActivityEventKind.error,
        message: 'Rejected (${_payloadString(p, 'reason') ?? event.type})',
      );
    case 'paused':
      return ActivityEvent(
        kind: ActivityEventKind.status,
        message: 'Game paused',
      );
    case 'resumed':
      return ActivityEvent(
        kind: ActivityEventKind.status,
        message: 'Game resumed',
      );
    case 'resigned':
      return ActivityEvent(
        kind: ActivityEventKind.completed,
        message:
            'Resigned (${_payloadString(p, 'color') ?? '?'}); '
            'winner ${_payloadString(p, 'winner') ?? '?'}',
      );
    case 'flagFall':
      return ActivityEvent(
        kind: ActivityEventKind.completed,
        message:
            'Flag: ${_payloadString(p, 'color') ?? '?'} lost on time; '
            'winner ${_payloadString(p, 'winner') ?? '?'}',
      );
    case 'terminalReported':
    case 'gameFinished':
      final outcome = _payloadString(p, 'outcome');
      final reason = _payloadString(p, 'reason');
      return ActivityEvent(
        kind: ActivityEventKind.completed,
        message:
            'Game finished${outcome == null ? '' : ' $outcome'}'
            '${reason == null ? '' : ' ($reason)'}',
      );
    default:
      return ActivityEvent(kind: ActivityEventKind.status, message: event.type);
  }
}

/// Whether an orchestrator lifecycle state is terminal (finished/failed).
bool isTerminalOrchestratorState(gs.OrchestratorState state) {
  return state == gs.OrchestratorState.finished ||
      state == gs.OrchestratorState.failed;
}

/// Phrase/fallback metadata for the orchestrator's `moveApplied` entry
/// [moveIndex] (1-based, matching the event payload's `moveIndex`).
///
/// **Design note (shared pump):** play/watch/arena each carry their own
/// sequential "pump" loop (bind agent → request turn → replay UCIs onto a
/// mirror position → report terminal). The replay step itself is shared via
/// `game_mirror.dart`'s `replayMoves` (parse/apply/metadata + failure
/// reporting); the loops and their post-sync hooks (finish/AI-reply/arena
/// touch) stay local because they diverge on chaotic handling, cancellation
/// and per-turn stats buffering. `test/game_mirror_test.dart` locks the
/// shared core's behavior for all three recording shapes.
///
/// Scans [orch]'s persisted [GameOrchestrator.eventLog] backwards for the
/// matching event and returns its `phrase` (null when absent or when the
/// move was an unattributed fallback). The phrase is only ever attributed
/// to an agent when `isFallback` is false — mirrors the private lookups
/// watch/play keep for their own sync loops.
({String? phrase, bool isFallback}) appliedMetaFor(
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

/// Retires an orchestrator replaced by a newer game: stops it first (so
/// a late in-flight turn discards against the terminal state instead of
/// touching listeners), cancels the event subscription, then disposes.
///
/// Late turns on a stopped game hit the `_isTerminal` guard in
/// `requestAiTurn`/`_applyMove` paths and are discarded — they never emit
/// into [_events] sinks or the mirror engine, so orphaned pump loops exit
/// on their identity check without side effects.
Future<void> retireOrchestrator(
  GameOrchestrator? orch,
  StreamSubscription<GameEvent>? sub,
) async {
  await sub?.cancel();
  if (orch != null && !isTerminalOrchestratorState(orch.state)) {
    orch.stop(reason: 'superseded');
  }
  orch?.dispose();
}

/// Extracts the raw tool-call JSON from the last completed call in [result].
///
/// Replay/audit uses the exact model payload, not a re-serialized move. Falls
/// back to [AgentTurnResult.selectedMove] when the event stream did not retain
/// the raw string. Never throws; unparseable JSON yields a null map but keeps
/// the raw string (the parse failure is surfaced via a `dart:developer` log).
({String? rawToolArgsJson, Map<String, Object?>? rawToolCallJson})
rawToolCallFrom(AgentTurnResult? result) {
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
      AppLog.current.warning(
        'rawToolCallFrom: unparseable tool-call JSON — keeping the raw '
        'string, decoded map is null',
        tag: 'backend-bridge',
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

/// Game-layer result constructor shorthand (avoids importing
/// `game_state.dart` in every screen).
gs.GameResult gameResult({
  required String outcome,
  required String reason,
  String? winnerColor,
}) {
  return gs.GameResult(
    outcome: outcome,
    reason: reason,
    winnerColor: winnerColor,
  );
}
