/// Riverpod providers for the UI-to-backend bridge (Flutter allowed here).
///
/// Backend logic lives in pure-Dart `../backend/` modules; this file owns
/// everything Riverpod (and everything `ChangeNotifier`):
///
/// * `backend/agent_providers.dart` — provider mapping/resolution/seams
///   (pure functions + typedefs; re-exported below for compat)
/// * `backend/review_resolver.dart` — review game/evaluator resolution
///   (re-exported below for compat)
/// * `backend/telemetry_logs.dart` — StatsLog/QualityLog/ReviewLog/
///   VariantReviewLog stores (re-exported below for compat)
///
/// Screens must import providers (and `Listenable` adapters) from here —
/// never from `../backend/`. The `ui/backend_bridge.dart` barrel re-exports
/// this file so existing `backend_bridge` importers keep working.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../storage/secure_key_store.dart';
import '../backend/agent_providers.dart';
import '../backend/review_resolver.dart';
import '../backend/telemetry_logs.dart';

// Re-exported logic types so screens can import this file alone.
// NOTE: removed — screens must import narrow `../backend/*.dart` for logic
// types (clear file roles) and this file only for providers/adapters.
// Keeping re-exports caused `unnecessary_import` lints in screens.

/// Provider for the [TurnProviderFactory]; defaults to [resolveTurnProvider].
final turnProviderFactoryProvider = Provider<TurnProviderFactory>(
  (ref) => resolveTurnProvider,
);

/// Injectable wall-clock source for seeds and timestamps (§10.3 seam).
///
/// Defaults to `DateTime.now` so production behaviour is unchanged; widget
/// tests override it with a fixed `DateTime.utc(2026, 1, 1)` so every seed
/// and timestamp becomes deterministic — no wall-clock dependency, no
/// pending-timer failures caused by stale `pumpAndSettle`.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Provider for the [ConnectionTester]; defaults to a wrapper around
/// [testAgentConnection].
///
/// The default binder resolves [SecureKeyStore] internally so callers don't
/// need to pass one — production code uses the same key resolution path
/// (`SecureKeyReaderAdapter`). Widget tests override the provider with a
/// fixed-success/fixed-failure lambda.
final connectionTesterProvider = Provider<ConnectionTester>(
  (ref) =>
      (agent, {inlineSecret}) => testAgentConnection(
        agent,
        const SecureKeyStore(),
        inlineSecret: inlineSecret,
      ),
);

/// Default resolves [resolveReviewEvaluator]; tests override to avoid
/// spawning Stockfish or waiting on network/time in widget tests.
final reviewEvaluatorFactoryProvider = Provider<ReviewEvaluatorFactory>(
  (ref) => resolveReviewEvaluator,
);

/// The app's shared [StatsLog], isolated per `ProviderScope`.
///
/// Screens read/write turns through this provider; tests get a fresh scope
/// (or override this provider) instead of clearing process-global state.
final statsLogProvider = Provider<StatsLog>((ref) {
  final log = StatsLog();
  ref.onDispose(log.dispose);
  return log;
});

/// The app's shared [QualityLog], isolated per `ProviderScope`.
final qualityLogProvider = Provider<QualityLog>((ref) {
  final log = QualityLog();
  ref.onDispose(log.dispose);
  return log;
});

/// The app's shared [ReviewLog], isolated per `ProviderScope`.
final reviewLogProvider = Provider<ReviewLog>((ref) {
  final log = ReviewLog();
  ref.onDispose(log.dispose);
  return log;
});

/// The app's shared [VariantReviewLog], isolated per `ProviderScope`.
final variantReviewLogProvider = Provider<VariantReviewLog>((ref) {
  final log = VariantReviewLog();
  ref.onDispose(log.dispose);
  return log;
});

/// Thin `ChangeNotifier` view over a pure-Dart telemetry store.
///
/// Mirrors `OrchestratorListenable` (`providers/orchestrator_adapter.dart`):
/// subscribes to the store's synchronous listeners and forwards every bump
/// to [notifyListeners] so `ListenableBuilder` rebuilds with the same timing
/// as the old `ChangeNotifier` stores. Detaching on [dispose] removes the
/// store listener without disposing the store itself — the provider owns the
/// store lifecycle.
class StoreChangeAdapter extends ChangeNotifier {
  /// Creates an adapter bound to the store's listener hooks.
  StoreChangeAdapter({
    required void Function(void Function()) addListener,
    required this._removeListener,
  }) {
    addListener(_bump);
  }

  /// Detaches from the store (does not dispose it).
  final void Function(void Function()) _removeListener;
  bool _disposed = false;

  /// Forwards one store bump to [notifyListeners].
  void _bump() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _removeListener(_bump);
    super.dispose();
  }
}

/// Cached adapters: one stable `Listenable` per store instance, so widgets
/// can call these helpers on every build without losing subscriptions.
final Expando<StoreChangeAdapter> _adapters = Expando<StoreChangeAdapter>(
  'telemetryListenable',
);

/// `ListenableBuilder`-ready view over [log] (stable per instance).
Listenable statsLogListenable(StatsLog log) =>
    _adapters[log] ??= StoreChangeAdapter(
      addListener: log.addListener,
      removeListener: log.removeListener,
    );

/// `ListenableBuilder`-ready view over [log] (stable per instance).
Listenable qualityLogListenable(QualityLog log) =>
    _adapters[log] ??= StoreChangeAdapter(
      addListener: log.addListener,
      removeListener: log.removeListener,
    );

/// `ListenableBuilder`-ready view over [log] (stable per instance).
Listenable reviewLogListenable(ReviewLog log) =>
    _adapters[log] ??= StoreChangeAdapter(
      addListener: log.addListener,
      removeListener: log.removeListener,
    );

/// `ListenableBuilder`-ready view over [log] (stable per instance).
Listenable variantReviewLogListenable(VariantReviewLog log) =>
    _adapters[log] ??= StoreChangeAdapter(
      addListener: log.addListener,
      removeListener: log.removeListener,
    );
