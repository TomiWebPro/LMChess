/// UI-to-backend bridge: barrel preserving the pre-split import surface.
///
/// Split (Phase 1): implementation lives in `backend/` modules. This file
/// only re-exports so existing screens keep working while they migrate to
/// narrow imports. New code should import the narrow module directly.
///
/// * `backend/agent_providers.dart` — provider mapping/resolution/seams
/// * `backend/board_mapper.dart` — Position/VariantBoard/FEN rendering
/// * `backend/activity_mapper.dart` — event/terminal/orchestrator mapping
/// * `backend/telemetry_logs.dart` — StatsLog/QualityLog/ReviewLog, PendingTurn
/// * `backend/review_resolver.dart` — ReviewGame, evaluator resolution
/// * `backend/game_pump.dart` — GamePump: one-turn advance + mirror sync
/// * `backend/arena_runner.dart` — ArenaRunner: one pairing to result
/// * `backend/review_loader.dart` — ReviewLoader: game to ReviewView
/// * `providers/backend_providers.dart` — Riverpod providers
///   (`turnProviderFactoryProvider`, `reviewEvaluatorFactoryProvider`,
///   `clockProvider`, `connectionTesterProvider`, `statsLogProvider`,
///   `qualityLogProvider`, `reviewLogProvider`, `variantReviewLogProvider`)
///   + `StoreChangeAdapter`/`*Listenable` widget adapters. Re-exports the
///   pure backend logic types too, so importers of this barrel keep working
///   with zero edits.
library;

export 'backend/activity_mapper.dart';
export 'backend/agent_providers.dart';
export 'backend/arena_runner.dart';
export 'backend/board_mapper.dart';
export 'backend/game_pump.dart';
export 'backend/review_loader.dart';
export 'backend/review_resolver.dart';
export 'backend/telemetry_logs.dart';
export 'providers/backend_providers.dart';
