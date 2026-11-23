# `lib/src/stockfish/` — Stockfish gameplay seat

Role: One-shot Stockfish-backed provider for Human-vs-CPU seats.

Owns: `stockfish_move.dart` (per-turn factory scripting a `MockProvider`
  with the engine pick at an Elo-capped personality).

Talks to: `llm/` (`MockProvider`, tool-call encoding), `review/`
  (`embedded_engine.dart`, `stockfish_evaluator.dart`); used by pumps.

Never imports: `package:flutter`, `ui/`, `game/`, `arena/`, `storage/`,
  `chess/` engine directly — FEN arrives per turn from the caller.

Debug logs: none directly — engine chatter surfaces under review tags
  (`embedded-engine`, `engine-adapter`, `engine-stdout/stderr`).
