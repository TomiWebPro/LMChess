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
| P0 | `test/support/arena_test_harness.dart` | DONE 2026-10-20: `useDesktopSurface`, `pumpArenaApp`, `pumpSteps`, `disposeApp`, `resetTelemetry` (clears StatsLog + QualityLog + ReviewLog + VariantReviewLog), `fakeAgent`/`fakeAgents` (mock ProviderId), `fakeOverrides` (turn provider factory → legal UCI MockProvider + clock fixed UTC), `expectNoException`. New `test/support/integration_test.dart` (18 tests): telemetry clear/reset, fake agents valid, fake overrides resolve in ProviderScope, surface sizing, app shell renders, semantics tree invariants/capture/parentMap/noReparenting/captureSafe, expectNoException, disposeApp. Evidence: `flutter analyze` clean; `flutter test test/support/integration_test.dart` 18/18 pass; full regression `flutter test` 203/203 pass (201 old + 18 new); note: integration test placed inside `test/support/` so relative imports resolve correctly — no longer separate flat file) |
| P0 | `test/support/semantics_invariants.dart` | DONE 2026-10-20: `captureSemantics(tester)` returns root + reachable nodes; `parentMap(capture)` → `Map<int,int?>`; `expectSemanticsTreeInvariants(tester)` checks unique ids, non-null parents, owner match; `expectNoReparenting(before, after)` flags changed parent ids; `expectSquareSemantics(expectedCount, requireUniqueSquares)` counts & validates square labels; `expectNoExceptionWithSemanticsDump(context)` prints tree on failure; `captureSemanticsSafe(tester)` wraps ensureSemantics in try/finally. New integration test covers all functions. Evidence: `flutter analyze` clean; `flutter test test/support/integration_test.dart` 18/18 pass; full regression `flutter test` 203/203 pass. Next: chessboard + shell navigation tests (P0 §6.1–6.3). |
| P0 | `test/ui/chessboard_test.dart` | DONE 2026-10-20: 26 tests covering §6.3 — rendering (initial board semantics labels, constrained sizing, coordinate labels on/off, both orientations, all built-in themes), interactions (empty/opponent/piece taps, select/deselect/reslect, opponent piece, empty square with selection), every-labels-reachable via semantics tap, semantic+gesture handler parity, overlay states (selected/inCheck/terminal/legalTargets/highlight-precedence/lastMove), edge cases (non-interactive/onTapSquare=null disabling buttons, rapid content swaps across 10 alternations without exception, variant badges not changing layout, all 64 label strings present, code vs unicode glyph equivalence, responsive sizing down to 120px). Evidence: `flutter analyze` clean; `flutter test test/ui/chessboard_test.dart` 26/26 pass; full regression `flutter test` 229/229 pass (203 old + 26 new). Next: shell navigation tests (§6.1, P0). |
| P0 | `test/ui/shell_navigation_test.dart` | DONE 2026-10-20: 16 widget tests covering §6.1 — wide rail navigation (8 destinations open correctly, rail has 8 items, state survives Home→Play→Home round-trip, all 8 render without exception, home-card taps via _openRoute), narrow layout (AppBar/rail/NavigationBar presence toggle, More sheet lists Stats/Review/Agents/Settings and selects Review, Drawer present on Scaffold with non-null drawer in narrow mode, narrow renders all 7 navigable screens without crash), state preservation (IndexedStack survives 11-step path, resize 699→700→1100→699 preserves mounted Play tab with zero exceptions, 20 rapid switches through 8 destinations without error), semantics isolation (hidden Home tab contributes 0 square nodes vs Play's occupied-square count, no duplicate semantics ids across multi-tab switch sequences, parentMap invariant stable across Play→Watch→Arena→Home transitions, hidden-tab rule 0→positive→0→positive toggling). Evidence: `flutter analyze` clean; `flutter test test/ui/shell_navigation_test.dart` 16/16 pass; full regression `flutter test` 245/245 pass (229 old + 16 new). Next: play_screen_test.dart (§6.4, P0). |
| P0 | `test/ui/play_screen_test.dart` | DONE 2026-10-20: 25 widget tests covering §6.4 — board interaction (select/deselect/respect own piece, opponent tap, empty square tap, legal move via coordinate tap, illegal destination), promotion dialog stability (renders when pawn reaches back rank, Q/R/B/N options appear, correct piece on queen promotion), resign flow (Resign button in moves panel, resign dialog structure, terminal state no crash), move list after human move shows entries, Activity/Moves tab switching, provider error handling (timeout → AI error handled, throws → app stays alive, no-move → no infinite spinner, successful retry clears error, thrown failure graceful), lifecycle (replacement widget mid-turn safe, dispose drains timers, narrow layout renders, theme change stable, player cards render two). Uses deterministic fakes (MockProvider with stepDelay=0, fixed clock UTC), never hits real network/engine/wall-clock. Evidence: `flutter analyze` clean; `flutter test test/ui/play_screen_test.dart` 25/25 pass; full regression `flutter test` 270/270 pass (245 old + 25 new). Next: semantics_stability_test.dart (§7, P0). |
| P0 | `test/ui/semantics_stability_test.dart` | TODO |
| P0 | `test/ui/monkey_tap_test.dart` | TODO |
| P0 | `integration_test/accessibility_windows_test.dart` | TODO (no `integration_test/` dir 2026-10-20) |
| P0 | `tool/windows_accessibility_smoke.ps1` | TODO |
| P0 | Refactors 10.1-10.4 + 10.7 (turn-provider / evaluator / clock / connection-tester seams + stable keys) | PARTIAL (10.1 DONE 2026-10-20; 10.2 DONE 2026-10-20: `ReviewEvaluatorFactory` + `reviewEvaluatorFactoryProvider` rewired in ReviewScreen + VariantReplayScreen, `test/review_evaluator_seam_test.dart` 8/8; 10.3 DONE 2026-10-20: `clockProvider` default `DateTime.now`, wired into WatchScreen (`_startWatchGame` seed + `_flushToReviewLog` id) and ArenaScreen (`_startChaosPump` seed + `_chaosRun` startedAt/finishedAt), new `test/clock_seam_test.dart` 8/8; 10.4 DONE 2026-10-20: `ConnectionTester` typedef + `connectionTesterProvider` (default wraps `testAgentConnection` with internal `SecureKeyStore`), wired into AgentSetupScreen (`_tester` captured in initState via `ref.read(connectionTesterProvider)`), new `test/connection_tester_seam_test.dart` 8/8; 10.7 DONE 2026-10-20: ValueKeys on Play-screen duplicate-label controls + `test/ui/stable_keys_test.dart` 4/4) |
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
- 2026-10-20Z — REFACTOR 10.2 (review evaluator seam, §12 order step 2): added
  `ReviewEvaluatorFactory` typedef + `reviewEvaluatorFactoryProvider`
  (default `resolveReviewEvaluator`) to
  `lib/src/ui/backend_bridge.dart`; rewired direct `resolveReviewEvaluator()`
  calls via `_evalFactory` in ReviewScreen (`review_screen.dart:251`,
  initState captured with `ref.read`) and VariantReplayScreen
  (`variant_replay_screen.dart:74`, initState added with `ref.read`).
  New `test/review_evaluator_seam_test.dart` (8 tests): default non-null
  factory, override returns heuristic-only handle, factory capture, thrown
  failure injection, nested ProviderScope resolution, container lifecycle.
  Evidence: `flutter analyze` clean (3 new files); `flutter test
  test/review_evaluator_seam_test.dart` 8/8 pass; regression
  `flutter test test/variant_review_test.dart test/variant_quality_test.dart
  test/turn_provider_seam_test.dart` 23/23 pass. Next: 10.3 clock seam.
- 2026-10-20Z — REFACTOR 10.3 (clock seam, §12 order step 3): added
  `clockProvider = Provider<DateTime Function()>((ref) => DateTime.now)` to
  `lib/src/ui/backend_bridge.dart`; wired into WatchScreen (`_clock` in
  `initState`, replacing `_watchSeed = DateTime.now()…` and review game id
  `'$kWatchGameId-${DateTime.now()…}'`) and ArenaScreen (`_clock` in
  `initState`, replacing chaos seed, `startedAt`, and `finishedAt`). New
  `test/clock_seam_test.dart` (8 tests): default returns valid DateTime,
  override fixes UTC, deterministic ms-epoch, masked seed stable, nested
  scope shadowing, shared reference. Evidence: `flutter analyze` clean (5
  files); `flutter test test/clock_seam_test.dart` 8/8 pass; full regression
  `flutter test` 173/173 pass (all existing + new). Next: 10.4 connection
  tester seam.
- 2026-10-20Z — REFACTOR 10.4 (connection tester seam, §12 order step 4): added
  `ConnectionTester` typedef + `connectionTesterProvider` (default wraps
  `testAgentConnection` with internal `const SecureKeyStore()`) to
  `lib/src/ui/backend_bridge.dart`; rewired AgentSetupScreen (`_tester` captured
  in `initState` via `ref.read(connectionTesterProvider)`, call-site uses
  `_tester(probe, inlineSecret: ...)` instead of direct
  `testAgentConnection(probe, _keyStore, ...)`). New
  `test/connection_tester_seam_test.dart` (8 tests): default factory resolves,
  override fixed-success, override fixed-false, inlineSecret passthrough verify,
  thrown failure injection, nested scope shadowing, per-container independence,
  real-network timeout bounded. Evidence: `flutter analyze` clean (3 new/changed
  files); `flutter test test/connection_tester_seam_test.dart` 8/8 pass; full
  regression `flutter test` 181/181 pass (173 old + 8 new). Next: 10.7 stable
  keys (duplicate-label fix for banner/play/New game controls).
- 2026-10-20Z — REFACTOR 10.7 (stable keys, §12 order step 5): added
  `ValueKey<String>` constants to every Play-screen control that previously had
  a duplicate label text, enabling `find.byKey()` in future tests instead of
  ambiguous `find.text()` lookups. Files changed:
  `lib/src/ui/screens/play_screen.dart` — 5 keys added:
  `'play-new-game-banner'` (result-banner TextButton),
  `'play-retry-ai'` (AI error banner TextButton),
  `'play-new-game-button'` (moves-panel OutlinedButton.icon),
  `'play-resign-button'` (moves-panel OutlinedButton.icon),
  `'play-resign-confirm'` (resign-dialog FilledButton).
  New `test/ui/stable_keys_test.dart` (4 tests): uniqueness of all five Play
  keys + six planned Watch/Arena keys, cross-screen non-collision, ValueKey
  parse integrity with overridden providers. Evidence:
  `flutter analyze` clean (2 items); `flutter test
  test/ui/stable_keys_test.dart` 4/4 pass; full regression
  `flutter test` 185/185 pass (181 old + 4 new). Next: harness + semantics
  checker (§5.1–5.2).
- 2026-10-20Z — INFRA P0 (§5.1–5.3 harness + semantics, §12 order step 2):
  created `test/support/arena_test_harness.dart` (surface size setup,
  `pumpArenaApp` with overrides, `pumpSteps`, `disposeApp`,
  `resetTelemetry` clearing StatsLog + QualityLog + ReviewLog + VariantReviewLog,
  `fakeAgent`/`fakeAgents` mock AgentConfig, `fakeOverrides` turning AI turns
  into deterministic MockProvider with legal UCI + fixed clock UTC) and
  `test/support/semantics_invariants.dart` (`captureSemantics`, `parentMap`,
  `expectSemanticsTreeInvariants` — unique ids / non-null parents / owner match,
  `expectNoReparenting`, `expectSquareSemantics`, `expectNoExceptionWithSemanticsDump`,
  `captureSemanticsSafe`). Integration test `test/support/integration_test.dart`
  (18 tests): telemetry clear/reset, fake agents valid, fake overrides resolve
  in ProviderScope, surface sizing, app shell renders, all semantics functions
  exercised on simple trees. Evidence: `flutter analyze` clean (0 issues);
  `flutter test test/support/integration_test.dart` 18/18 pass; full regression
  `flutter test` 203/203 pass (201 old + 18 new). Next: chessboard + shell
  navigation widget tests (§6.1–6.3, P0).
- 2026-10-20Z — UI P0 §6.3 (`test/ui/chessboard_test.dart`, ~20 tests): created
  26 widget tests covering all chessboard interaction scenarios from the spec.
  Rendering: initial board semantics labels, constrained 400×400 sizing (64 cells),
  coordinate labels default/on/off, orientationWhite=false flips view, all 4 built-in
  themes. Interactions: tap empty/opponent/piece squares, select/deselect/reslect,
  every label reachable via semantics tap, semantic+gesture handler parity (each fires
  exactly once). Overlays: selected/inCheck/terminal/legalTargets/highlight-precedence
  check>terminal>selection>lastFrom>lastTo/lastMove trail without crashes or exception.
  Edge cases: non-interactive disables buttons, onTapSquare=null disables buttons,
  rapid 10× empty↔full swaps no leaked state, variant badges no layout change, all
  64 square labels present, piece-code vs unicode-glyph equivalence, 120px minimum
  constraint. Evidence: `flutter analyze` clean; `flutter test test/ui/chessboard_test.dart`
  26/26 pass; full regression `flutter test` 229/229 pass (203 old + 26 new). Next:
  shell_navigation_test.dart (§6.1, P0).
- 2026-10-20Z — UI P0 §6.1 (`test/ui/shell_navigation_test.dart`, 16 tests): created widget tests covering all shell navigation scenarios from the spec. Wide layout: rail navigates to all 8 destinations, rail has exactly 8 items, tab state survives Home→Play→Home round-trips, all destinations render without exception, home-card taps route via _openRoute instead of Navigator.push. Narrow layout: AppBar/rail/NavigationBar toggle correctly at <700px breakpoint, More sheet lists Stats/Review/Agents/Settings with tap-to-select, Drawer is non-null on Scaffold, narrow renders all screens without crash. State preservation: IndexedStack survives 11-step path, resize 699→700→1100→699 preserves mounted Play tab across layout rebuilds, 20 rapid destination switches produce zero exceptions. Semantics isolation: hidden tabs contribute zero square-label nodes while selected tabs show occupied-square count, no duplicate semantics ids across multi-tab sequences, parentMap invariant stable across transitions. Evidence: `flutter analyze` clean; `flutter test test/ui/shell_navigation_test.dart` 16/16 pass; full regression `flutter test` 245/245 pass (229 old + 16 new). Next: play_screen_test.dart (§6.4, P0).
- 2026-10-20Z — UI P0 §6.4 (`test/ui/play_screen_test.dart`, 25 tests): created widget tests covering Play screen interactions from the spec. Board: select/deselect/respect own piece, opponent piece tap, empty square tap, legal move via coordinate tap with mock auto-reply, illegal destination no crash. Promotion: dialog renders when pawn reaches back rank, Q/R/B/N options present, queen produces correct piece. Resign: button exists in moves panel, dialog structure verified, terminal state stable. Move list: entries generated after human move. Tabs: Activity↔Moves switching clean. Error banners: timeout handled, throws handled, no-move doesn't spin forever, retry succeeds, internal crash graceful. Lifecycle: replacement widget mid-turn safe, dispose drains timers, narrow layout renders, theme change stable, player cards render. Uses deterministic fakes only — never touches real network, engine, or wall-clock. Evidence: `flutter analyze` clean; `flutter test test/ui/play_screen_test.dart` 25/25 pass; full regression `flutter test` 270/270 pass (245 old + 25 new). Next: semantics_stability_test.dart (§7, P0).
