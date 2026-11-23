# `lib/src/chess/` — Standard rules kernel

Role: Pure-Dart standard chess rules; no I/O, clocks, network, or UI.

Owns: `piece.dart`, `square.dart`, `move.dart`, `position.dart`,
  `fen.dart`, `san.dart`, `engine.dart` (legal-move helper only).

Talks to: sibling value objects (`Position`/`Move`/`Piece`); `game/`,
  `variant/` and `ui/backend/` consume via FEN strings + legal-move lists.

Never imports: `package:flutter`, `ui/`, `game/`, `arena/`, `llm/`,
  `storage/`, `review/`, `stats/` — the kernel has no outward edges.

Debug logs: none — pure functions; no `AppLog` tags originate here.
  Callers log FEN/legal-list handoffs under their own tags.
