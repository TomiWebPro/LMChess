# `lib/src/ui/providers/` — Flutter Riverpod adapters

Role: Thin `Provider`/`Notifier` adapters over `ui/backend/` use-cases.

Owns: `backend_providers.dart` (Riverpod barrel re-exporting backend
  seams), `orchestrator_adapter.dart` (`Listenable` over orchestrator).

Talks to: `ui/backend/*` pure use-cases + `storage/AppRepository`;
  screens consume state only through these provider seams.

Never imports: `storage/local_store`, `hive`, `llm/` vendors, `arena/`
  runners — Flutter glue + re-exports only, no sequencing logic.

Debug logs: none directly — delegates to `ui/backend/` tags with
  `gameId`/`tournamentId`/`seq` correlation IDs.
