/// Semantics-invariant helpers for widget tests.
///
/// These assertions mirror the preconditions the Windows embedder relies on
/// inside `AccessibilityBridge::CreateRemoveReparentedNodesUpdate`:
/// one root, unique ids, non-null parents (except root), no reparenting.
/// When an update violates any of these, the framework throws — but on
/// Windows the native crash can skip Dart entirely, so the checks live in
/// fast widget tests that run every PR.
///
/// **Usage pattern:**
/// ```dart
/// testWidgets('...', (tester) async {
///   await tester.pumpWidget(...);
///   final before = captureSemantics(tester);
///
///   // … perform a transition …
///   await tester.pump();
///
///   expectSemanticsTreeInvariants(tester);
///   expectNoReparenting(before.parentMap, parentMap(tester));
/// });
/// ```
///
/// ## Important details
///
/// * Call `tester.ensureSemantics()` before walking the tree; dispose the
///   handle in `try / finally`, never in `addTearDown` — end-of-test
///   verification runs before tear-downs.
/// * `SemanticsOwner` has no public enumeration API; this walks only nodes
///   reachable from the root. True unreachable-node detection needs an engine
///   hook and is out of scope.
/// * Arena's mini-board grid legitimately repeats square labels. Scope
///   uniqueness to single-board screens; use `expectedCount = 64 *
///   visibleBoards` and `requireUniqueSquares: false` for Arena.
/// * Hidden-tab children wrapped in `ExcludeSemantics(excluding: true)` must
///   contribute zero nodes.
// ignore_for_file: dangling_library_doc_comments

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Capture the semantics tree reachable from the root.
///
/// Returns a snapshot containing the root node and all reachable nodes plus
/// their immediate parents (see [parentMap]). Always calls
/// `ensureSemantics` first; the caller must NOT also call `ensureSemantics`
/// again within the same test or it will leak handles.
({SemanticsNode root, List<SemanticsNode> nodes}) captureSemantics(
  WidgetTester tester,
) {
  assert(
    tester.binding.renderViews.first.owner?.semanticsOwner != null,
    'Call ensureSemantics() before captureSemantics().',
  );
  final owner = tester.binding.renderViews.first.owner!.semanticsOwner!;
  final root = owner.rootSemanticsNode!;

  final nodes = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    nodes.add(node);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(root);
  return (root: root, nodes: nodes);
}

/// Build a map from each node id to its parent id.
///
/// The root node maps to `null`. This is used by [expectNoReparenting] to
/// detect when a previously-stable node changed parent between frames.
Map<int, int?> parentMap(
  ({SemanticsNode root, List<SemanticsNode> nodes}) capture,
) {
  return {for (final node in capture.nodes) node.id: node.parent?.id};
}

/// Assert the core invariants the Windows embedder assumes.
///
/// Checks three things:
/// 1. Every reachable node has a unique id.
/// 2. Every non-root node has a non-null parent.
/// 3. Every node's `owner` matches the root owner.
void expectSemanticsTreeInvariants(WidgetTester tester) {
  final owner = tester.binding.renderViews.first.owner!.semanticsOwner;
  final root = owner?.rootSemanticsNode;
  expect(root, isNotNull, reason: 'semantics root should exist');

  if (root == null) return;

  final ids = <int>{};
  final nodes = <SemanticsNode>[];

  void visit(SemanticsNode node) {
    nodes.add(node);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(root);

  for (final node in nodes) {
    expect(ids.add(node.id), isTrue,
        reason: 'duplicate semantics id ${node.id} "${node.label}"');
    expect(node.owner, same(root.owner),
        reason: 'node ${node.id} owner mismatch');
    if (!identical(node, root)) {
      expect(node.parent, isNotNull,
          reason: 'node ${node.id} "${node.label}" has a null parent');
    }
  }

  void checkParent(SemanticsNode parent) {
    parent.visitChildren((child) {
      expect(identical(child.parent, parent), isTrue,
          reason: 'node ${child.id} reports parent ${child.parent?.id}, '
                  'expected ${parent.id}');
      checkParent(child);
      return true;
    });
  }

  checkParent(root);
}

/// Assert that no node changed parent between [before] and [after].
///
/// Both maps come from [parentMap]. Any node whose entry differs is flagged
/// as a reparenting event. Nodes present in [before] but not [after] are
/// ignored (they may have been removed). Nodes in [after] but not [before]
/// are silently accepted (new nodes are fine).
void expectNoReparenting(Map<int, int?> before, Map<int, int?> after) {
  for (final entry in before.entries) {
    if (!after.containsKey(entry.key)) continue;
    expect(
      entry.value,
      after[entry.key],
      reason: 'node ${entry.key} reparented: '
              '${entry.value} -> ${after[entry.key]}',
    );
  }
}

/// Assert the expected number of square nodes on a chessboard screen.
///
/// [expectedCount] is typically `64` for single-board screens (Play, Watch,
/// Review) and `64 * visibleBoards` for Arena mini-boards.
///
/// When [requireUniqueSquares] is `true` (single-board screens), duplicate
/// square labels are rejected. For Arena mini-boards set it to `false`.
///
/// Square labels follow the pattern `Empty square <sq>`, `White piece on <sq>`,
/// or `Black piece on <sq>`.
void expectSquareSemantics(
  WidgetTester tester, {
  required int expectedCount,
  bool requireUniqueSquares = true,
}) {
  final capture = captureSemantics(tester);
  final squares = capture.nodes.where((node) {
    final data = node.getSemanticsData();
    return _isSquareLabel(data.label);
  }).toList();

  expect(
    squares.length,
    expectedCount,
    reason: 'expected $expectedCount square semantics nodes, '
            'got ${squares.length}',
  );

  if (requireUniqueSquares) {
    final labels = <String>{};
    for (final sq in squares) {
      final data = sq.getSemanticsData();
      final label = data.label;
      expect(labels.add(label), isTrue,
          reason: 'duplicate square label "$label"');
    }
  }
}

bool _isSquareLabel(String label) {
  // Matches "Empty square e4", "White piece on d5", "Black piece on g7".
  final regex = RegExp(r'^(?:Empty|White|Black) square .+$');
  return regex.hasMatch(label);
}

/// Catch expectations by printing the semantics tree dump before failing.
///
/// Use at the end of tests where a semantics crash would leave no Dart
/// stack trace: the dump makes it possible to see what the tree looked like
/// at failure time.
///
/// [context] is a short description of what was happening when the exception
/// occurred.
void expectNoExceptionWithSemanticsDump(
  WidgetTester tester,
  String context,
) {
  expect(tester.takeException(), isNull, reason: 'exception during $context');
  if (tester.takeException() != null) {
    // Print the semantics tree for diagnostics.
    final owner = tester.binding.renderViews.first.owner?.semanticsOwner;
    if (owner != null && owner.rootSemanticsNode != null) {
      debugPrint(_dumpTree(owner.rootSemanticsNode!, ''));
    }
  }
}

/// Recursively dump semantics nodes for diagnostic purposes.
String _dumpTree(SemanticsNode node, String indent) {
  final data = node.getSemanticsData();
  final label = data.label;
  var out = '$indent[${node.id}] label="$label"\n';
  node.visitChildren((child) {
    out += _dumpTree(child, '  $indent');
    return true;
  });
  return out;
}

/// A lightweight wrapper around [captureSemantics] that also calls
/// `ensureSemantics` in a try/finally block.
///
/// Prefer calling `ensureSemantics` separately when you need semantics
/// for other reasons (e.g., `tester.semantics.tap`) — this function
/// exists for standalone invariant checks.
({SemanticsNode root, List<SemanticsNode> nodes}) captureSemanticsSafe(
  WidgetTester tester,
) {
  final handle = tester.ensureSemantics();
  try {
    return captureSemantics(tester);
  } finally {
    handle.dispose();
  }
}
