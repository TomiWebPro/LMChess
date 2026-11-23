# `lib/src/llm/` — Provider interface + adapters

Role: Defines the LLM contract and adapts 5 vendors to one interface.

Owns: `provider.dart`, `tool_schema.dart`, `validation.dart`,
  `prompt_board.dart`, `http_helpers.dart`, 5 vendor providers + mock.

Talks to: `diagnostics/` (`AppLog`); exposes `LlmProvider` consumed by
  `agent/` (`AgentRunner`) and `game/` (`TurnPump` prompt rendering).

Never imports: `package:flutter`, `ui/`, `game/`, `arena/`, `chess/`,
  `variant/`, `storage/`, `review/`, `stats/` — transport only.

Debug logs: `openai-provider`, `anthropic-provider`, `gemini-provider`
  (key redaction warnings only; never request/response bodies).
