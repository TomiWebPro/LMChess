# LLM Chess Arena — Architecture

> Standalone-Flutter-first, backend-ready modular platform for LLMs playing
> standard + chaotic (illegal-move) chess with full observability.

## Decision log (defaults chosen to unblock implementation)

| Decision | Choice | Why |
|---|---|---|
| App shape | Standalone Flutter (offline-first), backend contracts in-Dart | Prompt requires "standalone in flutter"; a deployable server would block delivery. All persistence/orchestration runs locally behind `AppRepository`/`EventStore` interfaces identical to the future REST/WS API. `backend/` holds the OpenAPI stub + data contracts so a server can be dropped in later without touching domain logic. |
| State mgmt | `flutter_riverpod` (no codegen) | Maintainable, testable, matches prompt; no established alternative in repo (greenfield). |
| Chess rules | Hand-written pure-Dart move generator | Guarantees variant isolation, null-safety, no dependency on third-party chess packages whose castling/EP edge cases vary. Verified by regression tests (`test/chess_rules_test.dart`: perft node counts + FEN/SAN round-trips). |
| Variant model | `VariantBoard` with stable piece IDs, custom JSON | FEN cannot express duplicated/missing kings or spawned pieces; FEN used only when `canRepresentAsFen()` is true. |
| Secrets | `flutter_secure_storage`; never in logs/exports | Keys stay on device (later: server only). Export redacts `apiKey*`. |
| Clocks | Orchestrator-owned, runs during whole agent turn | Deterministic timeout-vs-move race handling. |
| Fallback | Seeded uniform-random legal move, recorded as fallback | Tournament reproducibility; never attributed to agent. |
| Evaluation | `PositionEvaluator` interface; **embedded Stockfish sf_19** (7 platform binaries, first-run extraction) with heuristic fallback; WintrChess-derived review module for game review | Stockfish = eval truth (labeled `stockfish-uci`); upstream `wintrcat/wintrchess` verified as a GPLv3 TypeScript web app, not a UCI engine — see `lib/src/review/wintrchess_notes.md` and `docs/ENGINE_RUNTIME.md`. Heuristic is always labeled `heuristic`. |
| Ratings | Per-mode Elo tables with game-count confidence | Standard and chaotic skill do not transfer; no combined leaderboard. |

## Module map (independent layers, shared kernel)

```
lib/src/chess/      standard rules: piece/square/move/position/fen/san/engine
lib/src/variant/    chaotic: board/interpretation/strategies/selection/evaluator/engine
lib/src/llm/        provider interface, tool schema, validation, 5 adapters
lib/src/agent/      AgentConfig, ProviderFactory, AgentRunner (retry/timeout, no fallback)
lib/src/game/       clock, game_state, orchestrator (state machine, atomic transitions)
lib/src/arena/      tournament, scheduler (bounded pool), elo, export (v1.0 redacted)
lib/src/stats/      event_log (idempotent), metrics (denominators documented)
lib/src/review/     engine_adapter, quality labels, wintrchess notes
lib/src/storage/    AppRepository, LocalAppStore (Hive), migrations/retention hooks
lib/src/theme/      board/piece themes + registry
lib/src/ui/         widgets (chessboard/activity/boards) + 9 screens + app shell
backend/            OpenAPI stub mirroring AppRepository; server roadmap
```

Dependency rule: `chess` ← `variant` ← `game` ← `ui`; `llm`/`agent` independent of
game rules; `stats`/`review`/`arena` consume events only. No layer imports `ui`.
This is enforced by convention and code review, not by tooling — there is no
import-lint gate configured (`analysis_options.yaml` covers lints, not layering).

## Data contracts

- Tool call: `make_chess_move{from,to,promotion?,phrase}` — see `tool_schema.dart`.
- Events are immutable, idempotent by key (`gameId:seq`), persisted before broadcast.
- Tournament export schema `1.0` — see `lib/src/arena/export.dart` + `backend/openapi.yaml`.
- Ratings versioned per mode; model identity = `provider/model/promptHash/toolSchema/ruleset`.

## What is intentionally deferred

- Real server (Postgres/Redis/auth/WS) — contracts ready, see `backend/SERVER_ROADMAP.md`.
- Public leaderboard website — export format ready.
- Nothing on the test side is deferred: smoke tests (`test/boot_smoke_test.dart`
  + `test/e2e_smoke_test.dart`), the per-screen widget suites under
  `test/ui/`, and the semantics/telemetry harness in `test/support/` are all
  written and gated by CI (`.github/workflows/ci.yaml` ubuntu-gate).
