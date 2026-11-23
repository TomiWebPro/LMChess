# `lib/src/variant/` — Chaotic chess kernel

Role: Pure-Dart chaotic (illegal-move) chess rules on stable piece IDs.

Owns: `variant_board.dart`, `interpretation.dart`, `strategies.dart`,
  `selection.dart`, `evaluator.dart`, `chaotic_engine.dart`, `variant_replay.dart`.

Talks to: `chess/` value objects (`Piece`/`Square`/`Move`); consumed via
  opaque variant-JSON payloads by `game/`, `review/` and `ui/backend/`.

Never imports: `package:flutter`, `ui/`, `game/`, `arena/`, `llm/`,
  `storage/`, `review/`, `stats/` — same kernel rule as `chess/`.

Debug logs: none — pure functions; no `AppLog` tags originate here.
  Move `tag:` fields are data labels, not log tags.
