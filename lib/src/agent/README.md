# `lib/src/agent/` — Agent config + turn runner

Role: Binds model configs to providers and runs one agent turn.

Owns: `agent_config.dart` (config, factory, key resolution),
  `agent_runner.dart` (retry/timeout; never falls back itself).

Talks to: `llm/` (`LlmProvider`, tool schema, validation) and
  `diagnostics/` (`AppLog`); consumed by `game/` and `ui/backend/`.

Never imports: `package:flutter`, `ui/`, `game/`, `arena/`, `chess/`,
  `variant/`, `storage/`, `review/`, `stats/` — no game knowledge.

Debug logs: `resolveApiKey` (missing-key warnings; keys never logged).
  Turn outcomes are logged by callers with `gameId`/`seq` correlation.
