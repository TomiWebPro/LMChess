// LLM Chess Arena — application entry point.
//
// Wiring: flutter binding -> ProviderScope -> [ArenaApp] (see
// lib/src/app.dart for the shell, route table, and providers).
// Heavy async init (Hive boxes, secure storage, embedded Stockfish
// first-run extraction) happens lazily inside their owners, so startup
// stays synchronous and the first frame is never blocked behind I/O.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app.dart';
import 'src/diagnostics/backend_log.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Wire the UI-free backend logging contract to the real sink once at
  // startup; backend code resolves currentBackendLog per-call.
  currentBackendLog = AppLog.current;
  runApp(const ProviderScope(child: ArenaApp()));
}
