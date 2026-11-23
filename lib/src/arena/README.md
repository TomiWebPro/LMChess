# `lib/src/arena/` — Tournament orchestration

Role: Schedules tournament games, tracks standings, exports results.

Owns: `tournament.dart`, `scheduler.dart` (bounded pool, fairness),
  `elo.dart` (per-mode ladders), `export.dart` (schema `1.0`, redacted).

Talks to: `stats/` (`GameEventRecord`), `game/` snapshots via injected
  `GameFactory`; export mirrors `backend/openapi.yaml`.

Never imports: `package:flutter`, `ui/`, `game/` orchestrator, `llm/`,
  `chess/`+`variant/` engines, `storage/local_store`, `review/`.

Debug logs: none directly; per-game progress surfaces via `ui/backend/`
  `arena-runner` / `arena-chaos` tags with `tournamentId` correlation.
