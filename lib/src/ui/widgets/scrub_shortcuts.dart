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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
      // Keyboard-only scope: must not contribute a Semantics node (see
      // chessboard.dart — default `includeSemantics: true` churns the AX tree
      // and trips flutter/flutter#175041 on Windows).
      includeSemantics: false,
      child: widget.child,
    );
  }
}

/// Step button that auto-repeats while held (§15.3).
///
/// A single tap fires [onStep] once (via the inner [IconButton]); holding
/// the pointer down keeps firing it — first after [holdDelay], then every
/// [repeatInterval] — until release. This is what makes scrubbing a 200-ply
/// game bearable: hold `‹` / `›` instead of tapping 200 times.
///
/// Keyboard hold already auto-repeats (the OS sends repeated [KeyDownEvent]s,
/// which [_ScrubShortcutsState._handleKey] acts on), so this only covers the
/// pointer path. [onStep] hosts clamp + no-op when already at the end, so
/// repeats past the boundary are harmless. `null` [onStep] disables the
/// button and suppresses repeats.
class HoldIconButton extends StatefulWidget {
  /// Creates a hold-to-repeat step button.
  const HoldIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onStep,
    this.holdDelay = const Duration(milliseconds: 350),
    this.repeatInterval = const Duration(milliseconds: 70),
  });

  /// Glyph shown in the button.
  final IconData icon;

  /// Accessibility + hover tooltip.
  final String tooltip;

  /// One step; `null` disables the button.
  final VoidCallback? onStep;

  /// Pause before repeats start.
  final Duration holdDelay;

  /// Cadence once repeating.
  final Duration repeatInterval;

  @override
  State<HoldIconButton> createState() => _HoldIconButtonState();
}

class _HoldIconButtonState extends State<HoldIconButton> {
  Timer? _delayTimer;
  Timer? _repeatTimer;

  @override
  void dispose() {
    _cancelTimers();
    super.dispose();
  }

  void _cancelTimers() {
    _delayTimer?.cancel();
    _delayTimer = null;
    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (widget.onStep == null) return;
    _cancelTimers();
    _delayTimer = Timer(widget.holdDelay, () {
      if (!mounted || widget.onStep == null) return;
      _repeatTimer = Timer.periodic(widget.repeatInterval, (_) {
        if (!mounted) return;
        widget.onStep!();
      });
    });
  }

  void _onPointerUpOrCancel(PointerEvent event) => _cancelTimers();

  @override
  void didUpdateWidget(covariant HoldIconButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onStep == null) _cancelTimers();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUpOrCancel,
      onPointerCancel: _onPointerUpOrCancel,
      child: IconButton(
        tooltip: widget.tooltip,
        onPressed: widget.onStep,
        icon: Icon(widget.icon),
      ),
    );
  }
}
