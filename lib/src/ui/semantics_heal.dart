/// One-shot full-tree semantics resends (flutter/flutter#175041).
///
/// The Windows accessibility bridge applies the framework's incremental
/// updates against its own AXTree copy. The very first updates after bridge
/// initialization race the shell's startup storm (all six tabs mounting,
/// autostart swapping setup UI for live UI, post-frame focus landing,
/// streams starting), so the bridge can miss node creations and then reject
/// every later update that references them (`Failed to update ui::AXTree ...
/// will not be in the tree and is not the new root` / `Nodes left pending`),
/// which escalates to a native abort in Debug runs ("Lost connection to
/// device").
///
/// Marking the whole render tree dirty forces the next flush to send a
/// COMPLETE update — every node with data, parents before children — which
/// (re-)establishes every creation the bridge missed. Later incremental
/// updates then merge into a valid tree. This runs once shortly after
/// startup settles and again whenever semantics are (re-)enabled by a newly
/// attached client (UIA smoke, Narrator), so late attachers also get a
/// complete tree. It is a no-op while semantics are disabled or the tree is
/// not attached, and costs one extra semantics pass on a rare event.
library;

import 'package:flutter/rendering.dart';

/// Marks every attached render object as needing a semantics update.
///
/// The next pipeline flush therefore rebuilds and serializes the entire
/// tree instead of an incremental subset. Safe to call any time: detached
/// objects and a missing semantics owner are silently skipped by
/// [RenderObject.markNeedsSemanticsUpdate], and the marking itself schedules
/// the flush frame.
void resendFullSemanticsTree() {
  final binding = RendererBinding.instance;
  late final RenderObjectVisitor visitor;
  visitor = (RenderObject child) {
    child.markNeedsSemanticsUpdate();
    child.visitChildren(visitor);
  };
  for (final view in binding.renderViews) {
    view.markNeedsSemanticsUpdate();
    view.visitChildren(visitor);
  }
}
