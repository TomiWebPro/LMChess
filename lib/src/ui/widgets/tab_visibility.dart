/// Visibility marker for the responsive shell's tab stack.
///
/// `IndexedStack` keeps every tab mounted so state survives tab switches, so a
/// screen must not assume that being built means being on screen. Screens that
/// own expensive or long-running work (for example Review spawning Stockfish)
/// read [TabVisibility.of] and suspend while hidden.
///
/// Screens rendered outside the shell (pushed routes, dialogs, tests) have no
/// ancestor and default to visible, preserving their standalone behavior.
library;

import 'package:flutter/widgets.dart';

/// Whether the nearest shell tab is currently visible.
class TabVisibility extends InheritedWidget {
  /// Creates a visibility scope for one shell tab.
  const TabVisibility({
    super.key,
    required this.isVisible,
    required super.child,
  });

  /// `true` when this tab is the selected `IndexedStack` child.
  final bool isVisible;

  /// Reads the nearest scope, defaulting to `true` when there is none.
  static bool of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<TabVisibility>();
    return scope?.isVisible ?? true;
  }

  @override
  bool updateShouldNotify(TabVisibility oldWidget) =>
      isVisible != oldWidget.isVisible;
}
