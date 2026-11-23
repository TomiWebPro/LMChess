# `lib/src/ui/widgets/` — Presentational board widgets

Role: Pure-Flutter rendering: board, motion, panels, shortcuts.

Owns: `chessboard.dart`, `boards.dart`, `board_motion.dart`,
  `activity_panel.dart`, `scrub_shortcuts.dart`, `tab_visibility.dart`.

Talks to: `chess/` value objects (`Move`/`Piece`/`Square`), `theme/`
  registry; driven by `ui/backend/` mappers + `ui_models.dart`.

Never imports: `game/`, `arena/`, `llm/`, `agent/`, `review/`,
  `storage/`, `stats/` — widgets render props, never fetch data.

Debug logs: none — widgets never log; motion/scroll state stays local.
  Diagnostics surface through `ui/backend/` + `AppLog` tags instead.
