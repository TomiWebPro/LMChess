/// Flutter adapter for [GameOrchestrator].
///
/// The game layer is pure Dart: [GameOrchestrator] exposes
/// `addStateListener`/`removeStateListener` plus the broadcast [GameEvent]
/// stream. Widgets that need a [Listenable] (e.g. `ListenableBuilder`)
/// wrap the orchestrator in [OrchestratorListenable], which forwards both
/// state bumps and events to [notifyListeners] and detaches on [dispose].
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../game/orchestrator.dart';

/// A `ChangeNotifier` view over a [GameOrchestrator].
///
/// Subscribes to the orchestrator's pure-Dart state listeners and its
/// broadcast [GameOrchestrator.events] stream; every notification forwards
/// to [notifyListeners]. Disposing detaches from the orchestrator (removes
/// the state listener, cancels the event subscription) without disposing
/// the orchestrator itself — the owner still owns its lifecycle.
class OrchestratorListenable extends ChangeNotifier {
  /// Creates an adapter bound to [orch].
  OrchestratorListenable(this.orch) {
    orch.addStateListener(_onOrchState);
    _eventsSub = orch.events.listen((_) => _onOrchEvent());
  }

  /// The wrapped orchestrator (owner retains disposal responsibility).
  final GameOrchestrator orch;

  StreamSubscription<GameEvent>? _eventsSub;
  bool _disposed = false;

  void _onOrchState() {
    if (!_disposed) notifyListeners();
  }

  void _onOrchEvent() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    orch.removeStateListener(_onOrchState);
    _eventsSub?.cancel();
    _eventsSub = null;
    super.dispose();
  }
}
