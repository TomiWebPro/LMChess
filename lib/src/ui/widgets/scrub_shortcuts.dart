/// Keyboard ply-scrubbing shortcuts for replay-capable screens (§15.3).
///
/// Wraps a screen subtree in a [Focus] node that owns the arrow keys
/// (Left/Right = one ply backward/forward, Home/End = start/live end). Focus
/// is awarded while the nearest shell tab is visible ([TabVisibility]) and
/// released when the tab is hidden, so a board hidden inside the shell's
/// IndexedStack never steals keys from the tab that is on screen. Screens
/// rendered outside the shell (pushed routes, dialogs, tests, a bare
/// `VariantReplayScreen`) have no [TabVisibility] ancestor and default to
/// visible, so the shortcuts are active immediately.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../chess/square.dart';
import 'board_motion.dart';
import 'tab_visibility.dart';

/// One scrubbing intent mapped from a key press.
enum ScrubAction {
  /// Step one ply backward (Left arrow).
  stepBack,

  /// Step one ply forward (Right arrow).
  stepForward,

  /// Jump to the start position (Home).
  toStart,

  /// Jump to the live/last position (End).
  toEnd,
}

/// Motion value for a one-ply scrub step, or `null` to snap.
///
/// [uci] is the transition actually played to reach the view (the move into
/// the current ply). [delta] is the signed ply change of the step (`+1`
/// forward, `-1` backward). Steps larger than one ply return `null`, so a
/// long move-list jump snaps instead of animating every intermediate ply
/// (§15.3 "large jumps": animate the final transition only, or cap the
/// animation budget). Backward steps reverse the from/to pair so the board's
/// §15.2 motion layer slides the piece back to its previous square.
BoardMove? scrubMotionFor(String? uci, int delta) {
  if (uci == null || uci.length < 4 || delta.abs() != 1) return null;
  final from = Square.tryParse(uci.substring(0, 2));
  final to = Square.tryParse(uci.substring(2, 4));
  if (from == null || to == null) return null;
  return delta > 0
      ? BoardMove(from: from, to: to)
      : BoardMove(from: to, to: from);
}

/// Owns arrow/Home/End keys for one replay-capable screen. See the library
/// doc for the focus-visibility contract.
class ScrubShortcuts extends StatefulWidget {
  /// Creates a scrub-shortcut scope around [child].
  const ScrubShortcuts({
    super.key,
    required this.enabled,
    required this.onAction,
    this.onEscape,
    required this.child,
  });

  /// Whether arrow/Home/End keys are acted on right now. The focus node is
  /// still managed while disabled, but key events are ignored.
  final bool enabled;

  /// Receives the mapped [ScrubAction] for each handled key press.
  final ValueChanged<ScrubAction> onAction;

  /// Optional handler for Escape while the scope owns focus.
  ///
  /// Independent of the scrub arrow keys; hosts that keep a cancel-able
  /// transient state (for example a premove queue on the play screen) wire
  /// Escape here. `null` leaves the key unhandled.
  final VoidCallback? onEscape;

  /// The subtree that owns the shortcuts.
  final Widget child;

  @override
  State<ScrubShortcuts> createState() => _ScrubShortcutsState();
}

class _ScrubShortcutsState extends State<ScrubShortcuts> {
  final FocusNode _node = FocusNode(debugLabel: 'scrub-shortcuts');

  /// Whether the nearest shell tab is visible (defaults to true outside the
  /// shell).
  bool _visible = true;

  /// Whether focus has been synchronized at least once; the first pass must
  /// run even when visibility did not change.
  bool _everSynced = false;

  @override
  void initState() {
    super.initState();
    _node.onKeyEvent = _handleKey;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TabVisibility.of(context);
    final changed = visible != _visible || !_everSynced;
    _visible = visible;
    if (changed) {
      _everSynced = true;
      _syncFocus();
    }
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  /// Focus follows tab visibility: the visible scrub host owns the arrow
  /// keys; hidden tabs release them so keys reach the tab that is on screen.
  /// Deferred until after the frame so a tab switch that rebuilds several
  /// shortcuts in one frame settles in child order.
  void _syncFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_visible) {
        if (!_node.hasFocus) _node.requestFocus();
      } else if (_node.hasFocus) {
        _node.unfocus();
      }
    });
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!_visible || !widget.enabled) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      final onEscape = widget.onEscape;
      if (onEscape != null) {
        onEscape();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final action = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => ScrubAction.stepBack,
      LogicalKeyboardKey.arrowRight => ScrubAction.stepForward,
      LogicalKeyboardKey.home => ScrubAction.toStart,
      LogicalKeyboardKey.end => ScrubAction.toEnd,
      _ => null,
    };
    if (action == null) return KeyEventResult.ignored;
    widget.onAction(action);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _node,
      canRequestFocus: true,
      skipTraversal: true,
      child: widget.child,
    );
  }
}
