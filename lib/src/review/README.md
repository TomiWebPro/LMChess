# `lib/src/review/` — Post-game evaluation

Role: Turns finished games into engine evaluations + quality labels.

Owns: `engine_adapter.dart`, `embedded_engine.dart`, `quality.dart`,
  `stockfish_evaluator.dart`, `variant_*` (3 files), `wintr_review.dart`.

Talks to: `chess/` + `variant/` positions, `diagnostics/` (`AppLog`);
  consumed by `ui/backend/` (`review_resolver`/`review_loader`).

Never imports: `ui/` widgets/screens, `game/`, `arena/`, `storage/`,
  `llm/`, `stats/` — review reads history, never drives turns.

Debug logs: `engine-adapter`, `engine-stdout`, `engine-stderr`,
  `heuristic-evaluator`, `embedded-engine`, `variant-review`, `variant-projection`.
