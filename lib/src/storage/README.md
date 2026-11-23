# `lib/src/storage/` — Persistence behind interfaces

Role: Persists agents/games/evals behind `AppRepository` + `EventStore`.

Owns: `repository.dart`, `local_store.dart` (Hive), `memory_store.dart`,
  `redaction.dart`, `secure_key_store.dart`, `storage_reports.dart`.

Talks to: `stats/` (`EventStore`/`GameEventRecord`), `arena/` export
  redaction; UI reaches it only via `repository_provider.dart` seam.

Never imports: `ui/` screens/widgets, `game/`, `arena/` runners, `llm/`,
  `chess/`+`variant/` engines, `review/` — JSON payloads stay opaque.

Debug logs: `LocalAppStore` (init/migration/write failures; secrets
  redacted before logging — see `arena/export.dart`).
