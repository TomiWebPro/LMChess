# `lib/src/stats/` — Telemetry contracts

Role: Immutable event log plus metrics with documented denominators.

Owns: `event_log.dart` (`EventStore`, `GameEventRecord`, idempotent
  by `gameId:seq` key), `metrics.dart` (turn/result aggregation).

Talks to: exposes `EventStore` consumed by `game/`
  (persist-then-broadcast), `arena/` (export) and `storage/` (paging).

Never imports: `package:flutter`, `ui/`, `game/`, `arena/`, `llm/`,
  `chess/`, `variant/`, `review/`, `storage/` — pure data contracts.

Debug logs: none — in-memory appends; no `AppLog` tags originate here.
  Screens log flush errors under `ui/backend/` tags instead.
