/// Shared mirror-replay core for the play/watch/arena game pumps.
///
/// Every pump owns an authoritative [GameOrchestrator] plus a mirror
/// [Position]; the visible board may only advance by replaying the
/// orchestrator's `moveHistory` tail. [replayMoves] is exactly that replay and
/// nothing else. It deliberately does **not** own the loop: the three pumps
/// still differ on turn sequencing (play interleaves a human seat, watch
/// honours pause/resume, arena checks cancellation and per-game isolation) and
/// on post-sync hooks (setPosition/terminal reporting/AI reply/arena touch).
/// Keeping those local is what makes the shared core safe to reuse.
library;

import '../chess/move.dart';
import '../chess/position.dart';
import '../game/orchestrator.dart';
import 'backend_bridge.dart';

/// Phrase/fallback attribution for one applied ply (see [appliedMetaFor]).
typedef AppliedMoveMeta = ({String? phrase, bool isFallback});

/// Callback invoked once per newly applied move, in history order.
typedef MirrorMoveCallback = void Function(
  int moveIndex,
  String uci,
  ChessMove move,
  AppliedMove receipt,
  AppliedMoveMeta meta,
);

/// Outcome of one replay pass.
class MirrorReplayResult {
  /// Creates a replay result.
  const MirrorReplayResult({
    required this.applied,
    required this.changed,
    this.failedUci,
    this.error,
  });

  /// Number of orchestrator UCIs the mirror has applied after the pass.
  ///
  /// On a callback failure this still counts the applied move: the mirror is
  /// already advanced, so keeping the cursor in step avoids re-applying it.
  final int applied;

  /// Whether at least one move was applied during this pass.
  final bool changed;

  /// UCI that failed to parse/apply (or whose recorder threw), if any.
  final String? failedUci;

  /// The failure, or `null` on a clean pass.
  ///
  /// Callers decide how fatal it is: play/watch log an activity row and stop
  /// the pass; arena treats it as an infra failure (mirror desync).
  final Object? error;

  /// Whether the pass stopped on a failure.
  bool get hasError => error != null;
}

/// Replays `orch.moveHistory` from [applied] onto [engine].
///
/// Idempotent: a cursor already at the history length applies nothing and
/// reports `changed == false`. Never throws for a bad UCI or illegal move —
/// the failure is returned in [MirrorReplayResult.error] with the cursor left
/// at the first move that could not be applied.
///
/// [onApplied] runs after the mirror has advanced, so it may inspect
/// `engine.toFen()`/`checkSquare(engine)` for the position *after* the move.
/// A throwing recorder is reported too, with [MirrorReplayResult.applied]
/// already advanced (the mirror is consistent; only the journal entry is
/// missing).
MirrorReplayResult replayMoves({
  required GameOrchestrator orch,
  required Position engine,
  required int applied,
  required MirrorMoveCallback onApplied,
}) {
  final history = orch.moveHistory;
  var next = applied;
  var changed = false;
  while (next < history.length) {
    final uci = history[next];
    final ChessMove move;
    final AppliedMove receipt;
    final AppliedMoveMeta meta;
    try {
      move = ChessMove.fromUci(uci);
      receipt = engine.apply(move);
      meta = appliedMetaFor(orch, next + 1);
    } catch (e) {
      return MirrorReplayResult(
        applied: next,
        changed: changed,
        failedUci: uci,
        error: e,
      );
    }
    final index = next;
    next++;
    changed = true;
    try {
      onApplied(index, uci, move, receipt, meta);
    } catch (e) {
      return MirrorReplayResult(
        applied: next,
        changed: changed,
        failedUci: uci,
        error: e,
      );
    }
  }
  return MirrorReplayResult(applied: next, changed: changed);
}
