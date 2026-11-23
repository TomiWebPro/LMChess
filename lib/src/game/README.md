# `lib/src/game/` — Game orchestration core

Role: Owns clocks, game state, and the AI/human turn state machine.

Owns: `clock.dart`, `game_state.dart`, `orchestrator.dart`,
  `turn_pump.dart` (AI-turn pipeline extracted from the orchestrator).

Talks to: `agent/` (`AgentRunner`), `llm/` (prompts/validation),
  `stats/` (`GameEventRecord`, persist-then-broadcast ordering).

Never imports: `ui/` widgets/screens, `chess/`+`variant/` engines
  (position is an opaque `String`), `storage/local_store`, `arena/`.

Debug logs: none directly; turns surface via `ui/backend/` tags with
  `gameId`/`seq` correlation IDs (see BackendLog convention).
