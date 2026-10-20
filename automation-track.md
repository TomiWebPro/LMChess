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
| P0 | Refactors 10.1-10.4 + 10.7 (turn-provider / evaluator / clock / connection-tester seams + stable keys) | PARTIAL (10.1 DONE 2026-10-20: `turnProviderFactoryProvider` + Play/Watch/Arena×2 rewired + `test/turn_provider_seam_test.dart` 8/8; 10.2-10.4 + 10.7 still missing) |
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
- 2026-10-20Z — REFACTOR 10.1 (turn provider seam, §12 order step 1): added
  `TurnProviderFactory` + `turnProviderFactoryProvider` (default
  `resolveTurnProvider`, behavior-preserving) to
  `lib/src/ui/backend_bridge.dart`; rewired 4 direct `resolveTurnProvider`
  calls via `ref.read(turnProviderFactoryProvider)` in Play
  (`play_screen.dart:615`), Watch (`watch_screen.dart:629`), Arena standard
  (`arena_screen.dart:1069`) + Arena chaotic (`arena_screen.dart:1234`).
  New `test/turn_provider_seam_test.dart` (8 tests): default factory pins a
  legal mock move, override observes seed/phrase passthrough, timeout /
  malformed / no-move / thrown failure injection (in-process `MockProvider`,
  no sockets/clocks), default end-to-end stream. Evidence:
  `flutter analyze` clean (5 files); `flutter test
  test/turn_provider_seam_test.dart` 8/8 pass; regression `flutter test
  test/turn_provider_test.dart test/pump_loops_test.dart` 8/8 pass (real
  Play/Watch screens run through the default factory). Note: an early
  `testWidgets` draft deadlocked consuming `MockProvider.streamMove` in
  FakeAsync (`Future.delayed` ticks never fire unpumped) — stream assertions
  moved to plain `test`s; widget test only proves override resolution.
  Commit + push below. Next: 10.2 review-evaluator seam (same pattern).
