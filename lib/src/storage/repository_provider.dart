/// Riverpod wiring for the backend seam.
///
/// Screens and future server code depend on [AppRepository]/[EventStore]
/// only — never on [LocalAppStore] or Hive directly. Override
/// [appRepositoryProvider] in tests or in `main()` once the durable store
/// (or the HTTP implementation against `backend/openapi.yaml`) is ready:
///
/// ```dart
/// ProviderScope(
///   overrides: [
///     appRepositoryProvider.overrideWithValue(LocalAppStore()..init()),
///   ],
///   child: const ArenaApp(),
/// )
/// ```
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../stats/event_log.dart';
import 'memory_store.dart';
import 'repository.dart';

/// Shared [AppRepository]. Defaults to in-memory so the app boots with no I/O.
///
/// Swap for [LocalAppStore] (durable) or the future HTTP implementation
/// without touching screens: they only see this provider.
final Provider<AppRepository> appRepositoryProvider = Provider<AppRepository>(
  (ref) => MemoryAppRepository(),
);

/// Live event stream derived from the repository.
///
/// Convenience so consumers that only need append/read do not depend on
/// the full CRUD surface.
final Provider<EventStore> eventStoreProvider = Provider<EventStore>(
  (ref) => ref.watch(appRepositoryProvider).events,
);
