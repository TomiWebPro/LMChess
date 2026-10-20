# LMChess Automation Track

Status: living document (hourly worker log)
Last updated: 2026-10-20 (UTC)
Related: `docs/FUTURE_WORK.md` (binding roadmap), `ARCHITECTURE.md`, `README.md`

This file is updated by the hourly scheduler agent (`lmchess-hourly`) **every run**.
`docs/FUTURE_WORK.md` is append-mostly; this file is the append-always run log.

## Protocol for the hourly worker (binding)

1. Work in `/home/tomi/llm_chess_arena` only. One run = **ONE area** (one roadmap
   row / one test file / one refactor from `docs/FUTURE_WORK.md` §12 order).
   Never attempt the whole roadmap in one run.
2. Use subagents productively for cognitive offload: keep the main context lean,
   fan out to up to 8 parallel subagents (`explore` for mapping, `general` for
   slices), each scoped to one file/task. Main agent integrates + verifies.
3. Always update this file (append a Run Log entry). Append-only edits to
   `docs/FUTURE_WORK.md` (dated note + `Last updated:` bump, no rewrites).
4. Verify with `flutter analyze` + `flutter test` on touched files, then
   `git add`, `git commit`, `git push origin main` every run that changes files.

## Roadmap status (mirrors `docs/FUTURE_WORK.md` §12)

| Priority | Deliverable | Status |
|---|---|---|
| P0 | `test/support/arena_test_harness.dart` | TODO (missing 2026-10-20) |
| P0 | `test/support/semantics_invariants.dart` | TODO (missing 2026-10-20) |
| P0 | `test/ui/chessboard_test.dart` | TODO |
| P0 | `test/ui/shell_navigation_test.dart` | TODO |
| P0 | `test/ui/play_screen_test.dart` | TODO |
| P0 | `test/ui/semantics_stability_test.dart` | TODO |
| P0 | `test/ui/monkey_tap_test.dart` | TODO |
| P0 | `integration_test/accessibility_windows_test.dart` | TODO (no `integration_test/` dir 2026-10-20) |
| P0 | `tool/windows_accessibility_smoke.ps1` | TODO |
| P0 | Refactors 10.1-10.4 + 10.7 (turn-provider / evaluator / clock / connection-tester seams + stable keys) | PARTIAL (some seams exist e.g. turn_provider_test; needs audit) |
| P1 | `test/ui/watch_screen_test.dart` | TODO |
| P1 | `test/ui/arena_screen_test.dart` | TODO |
| P1 | `test/ui/agent_setup_test.dart` | TODO |
| P1 | `test/ui/review_screen_test.dart` | TODO |
| P1 | `test/ui/variant_replay_test.dart` | TODO (note: `test/variant_replay_test.dart` exists flat, needs move/expand per plan) |
| P2 | `test/ui/stats_screen_test.dart` | TODO |
| P2 | `test/ui/settings_screen_test.dart` | TODO |
| P2 | `test/ui/shared_widgets_test.dart` | TODO |
| P2 | `test/ui/home_screen_test.dart` | TODO |

Note (2026-10-20): flat `test/*_test.dart` files exist (agent_runner, game_mirror,
pump_loops, robustness, semantics_smoke, variant_*) from commit `61d58d7`, but the
`test/ui/`, `test/support/`, `integration_test/` layout from FUTURE_WORK §§5-11
does not exist yet. Worker should verify and record actual state each run.

## Run Log (append-only, newest at bottom)

- 2026-10-20Z — INIT: created this file, scheduled `lmchess-hourly` (`--every 1h`,
  model `commandcode/muse-spark-1.3-contributor`). No code changed. Next: P0 harness + refactors audit.
