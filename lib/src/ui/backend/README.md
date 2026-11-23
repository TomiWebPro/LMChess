# `lib/src/ui/backend/` — Pure-Dart UI use-cases

Role: All screen sequencing as testable pure-Dart pumps and mappers.

Owns: `game_pump.dart`, `arena_runner.dart`, `activity_mapper.dart`,
  `board_mapper.dart`, `agent_providers.dart`, `review_*` (2), `telemetry_logs.dart`.

Talks to: `game/`, `arena/`, `agent/`, `llm/`, `review/`, `stats/`,
  `storage/` (via `AppRepository` seam only) — never widgets.

Never imports: `package:flutter` widgets/material, `storage/local_store`,
  `hive` — enforced by `test/architecture_test.dart` (ui-store rule).

Debug logs: `backend-bridge`, `arena-runner`, `arena-chaos`,
  `connection-tester` — every record carries `gameId`/`tournamentId`/`seq`.
