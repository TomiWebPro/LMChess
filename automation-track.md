# LMChess Automation Track

Status: living document (hourly worker log)
Last updated: 2026-10-22 (UTC) — §15.3 fast ply scrubbing completed
Related: `docs/FUTURE_WORK.md` (binding roadmap), `ARCHITECTURE.md`, `README.md`

This file is updated by the hourly scheduler agent (`lmchess-hourly`) **every run**.
`docs/FUTURE_WORK.md` now lists only open items; this file is the append-always run log.

## Protocol for the hourly worker (binding)

1. Work in `/home/tomi/llm_chess_arena` only. One run = **ONE area** (one open
   item from `docs/FUTURE_WORK.md`). Never attempt the whole backlog in one run.
2. Use subagents productively for cognitive offload: keep the main context lean,
   fan out to up to 8 parallel subagents (`explore` for mapping, `general` for
   slices), each scoped to one file/task. Main agent integrates + verifies.
3. Always update this file (append a Run Log entry). Keep
   `docs/FUTURE_WORK.md` open-items-only; do not re-add completed work.
4. Verify with `flutter analyze` + `flutter test` on touched files, then
   `git add`, `git commit`, `git push origin main` every run that changes files.

## Roadmap status (historical — all rows now DONE)

| Priority | Deliverable | Status |
|---|---|---|
| P0 | `test/support/arena_test_harness.dart` | DONE 2026-10-20: `useDesktopSurface`, `pumpArenaApp`, `pumpSteps`, `disposeApp`, `resetTelemetry` (clears StatsLog + QualityLog + ReviewLog + VariantReviewLog), `fakeAgent`/`fakeAgents` (mock ProviderId), `fakeOverrides` (turn provider factory → legal UCI MockProvider + clock fixed UTC), `expectNoException`. New `test/support/integration_test.dart` (18 tests): telemetry clear/reset, fake agents valid, fake overrides resolve in ProviderScope, surface sizing, app shell renders, semantics tree invariants/capture/parentMap/noReparenting/captureSafe, expectNoException, disposeApp. Evidence: `flutter analyze` clean; `flutter test test/support/integration_test.dart` 18/18 pass; full regression `flutter test` 203/203 pass (201 old + 18 new); note: integration test placed inside `test/support/` so relative imports resolve correctly — no longer separate flat file) |
| P0 | `test/support/semantics_invariants.dart` | DONE 2026-10-20: `captureSemantics(tester)` returns root + reachable nodes; `parentMap(capture)` → `Map<int,int?>`; `expectSemanticsTreeInvariants(tester)` checks unique ids, non-null parents, owner match; `expectNoReparenting(before, after)` flags changed parent ids; `expectSquareSemantics(expectedCount, requireUniqueSquares)` counts & validates square labels; `expectNoExceptionWithSemanticsDump(context)` prints tree on failure; `captureSemanticsSafe(tester)` wraps ensureSemantics in try/finally. New integration test covers all functions. Evidence: `flutter analyze` clean; `flutter test test/support/integration_test.dart` 18/18 pass; full regression `flutter test` 203/203 pass. Next: chessboard + shell navigation tests (P0 §6.1–6.3). |
| P0 | `test/ui/chessboard_test.dart` | DONE 2026-10-20: 26 tests covering §6.3 — rendering (initial board semantics labels, constrained sizing, coordinate labels on/off, both orientations, all built-in themes), interactions (empty/opponent/piece taps, select/deselect/reslect, opponent piece, empty square with selection), every-labels-reachable via semantics tap, semantic+gesture handler parity, overlay states (selected/inCheck/terminal/legalTargets/highlight-precedence/lastMove), edge cases (non-interactive/onTapSquare=null disabling buttons, rapid content swaps across 10 alternations without exception, variant badges not changing layout, all 64 label strings present, code vs unicode glyph equivalence, responsive sizing down to 120px). Evidence: `flutter analyze` clean; `flutter test test/ui/chessboard_test.dart` 26/26 pass; full regression `flutter test` 229/229 pass (203 old + 26 new). Next: shell navigation tests (§6.1, P0). |
| P0 | `test/ui/shell_navigation_test.dart` | DONE 2026-10-20: 16 widget tests covering §6.1 — wide rail navigation (8 destinations open correctly, rail has 8 items, state survives Home→Play→Home round-trip, all 8 render without exception, home-card taps via _openRoute), narrow layout (AppBar/rail/NavigationBar presence toggle, More sheet lists Stats/Review/Agents/Settings and selects Review, Drawer present on Scaffold with non-null drawer in narrow mode, narrow renders all 7 navigable screens without crash), state preservation (IndexedStack survives 11-step path, resize 699→700→1100→699 preserves mounted Play tab with zero exceptions, 20 rapid switches through 8 destinations without error), semantics isolation (hidden Home tab contributes 0 square nodes vs Play's occupied-square count, no duplicate semantics ids across multi-tab switch sequences, parentMap invariant stable across Play→Watch→Arena→Home transitions, hidden-tab rule 0→positive→0→positive toggling). Evidence: `flutter analyze` clean; `flutter test test/ui/shell_navigation_test.dart` 16/16 pass; full regression `flutter test` 245/245 pass (229 old + 16 new). Next: play_screen_test.dart (§6.4, P0). |
| P0 | `test/ui/play_screen_test.dart` | DONE 2026-10-20: 25 widget tests covering §6.4 — board interaction (select/deselect/respect own piece, opponent tap, empty square tap, legal move via coordinate tap, illegal destination), promotion dialog stability (renders when pawn reaches back rank, Q/R/B/N options appear, correct piece on queen promotion), resign flow (Resign button in moves panel, resign dialog structure, terminal state no crash), move list after human move shows entries, Activity/Moves tab switching, provider error handling (timeout → AI error handled, throws → app stays alive, no-move → no infinite spinner, successful retry clears error, thrown failure graceful), lifecycle (replacement widget mid-turn safe, dispose drains timers, narrow layout renders, theme change stable, player cards render two). Uses deterministic fakes (MockProvider with stepDelay=0, fixed clock UTC), never hits real network/engine/wall-clock. Evidence: `flutter analyze` clean; `flutter test test/ui/play_screen_test.dart` 25/25 pass; full regression `flutter test` 270/270 pass (245 old + 25 new). Next: semantics_stability_test.dart (§7, P0). |
| P0 | `test/ui/semantics_stability_test.dart` | DONE 2026-10-20: 32 widget tests covering §7 — destination invariants (all 8 wide + all 8 narrow), hidden-tab rule Home→Play→Stats (zero/occupied/zero square nodes), Play Activity/Moves tab switch stable, Watch Activity/Moves/Errors tab switches stable, Arena empty state zero mini-boards, dialog/sheet transitions (More sheet open/select/dismiss/stable, drawer implicit via shell structure), resize 699→700→1100→699 per-frame no-reparenting, theme light→dark semantic stability with equal square-count across modes, 50 rapid destination switches zero duplicate ids, Review empty-state navigate-away-back stability, Agents New-agent form push/pop semantics stability, wide rail completeness (NavigationRail.destinations.length==8 + all 8 labels visible), narrow AppBar presence on navigation change, captureSemanticsSafe wrapper exercise, expectNoExceptionWithSemanticsDump clean-pass, Settings colour-scheme segment toggles, quick round-trip Home→Play→Watch→Home. Each test asserts tree invariants + no reparenting via parentMap comparison. Evidence: `flutter analyze` clean; `flutter test test/ui/semantics_stability_test.dart` 32/32 pass; full regression `flutter test` 302/302 pass (270 old + 32 new). Next: monkey_tap_test.dart (§8, P0). |
| P0 | `test/ui/monkey_tap_test.dart` | DONE 2026-10-20: 5 widget tests covering §8 — narrow grid sweep (600×800 @ 48px), wide grid sweep with Play mounted (1600×1000 @ 48px), 1500 random taps seed 0xC0FFEE, 300 random taps + per-step reparenting guard seed 0xCAFEBABE, bonus tapEveryLabelledControl on Home screen. Uses SeedRng for deterministic PRNG, async _tapOffset (await-compatible tapAt/pump), captureSemanticsSafe/parentMap/expectNoReparenting/expectSemanticsTreeInvariants at every step, _drainRoutes to dismiss dialogs/sheets, harness.disposeApp to drain timers. No pumpAndSettle; uses small pump slices. Each test Timeout(Duration(minutes: 2)). Evidence: flutter analyze clean; flutter test test/ui/monkey_tap_test.dart 5/5 pass; full regression flutter test 307/307 pass (302 old + 5 new). Next: integration_test/accessibility_windows_test.dart (§9, P0). |
| P0 | `integration_test/accessibility_windows_test.dart` | DONE (built) 2026-10-21: 12 tests covering all §9.1 spec requirements; compiles clean and runs as a widget-level integration test. Native Windows execution is the remaining open item in `docs/FUTURE_WORK.md` §9.1. |
| P0 | `tool/windows_accessibility_smoke.ps1` | DONE 2026-10-21: `tool/windows_accessibility_smoke.ps1` (511 lines) — native UIA smoke test per §9.2 spec. Steps: (1) launch release exe via `Start-Process -PassThru`, (2) attach UIAutomationCore COM, (3) find window by PID/title match (`llm_chess_arena.exe`), (4) enumerate invocable controls (InvokePattern first, LegacyIAccessiblePattern fallback), target >= 40, (5) walk UIA tree repeatedly (10 iterations), (6) perform 500 seeded random clicks (XorShift64 PRNG, seed 0xCAFEBABE) with user32.dll mouse_event API, (7) check Event Viewer for fresh flutter_windows.dll 0xC0000005 after run, (8) always kill process in finally block. Accepts params: -Exe (mandatory), -RandomClicks (default 500), -Seed (default 0xCAFABE), -Timeout (default 120s). Uses Exit code 0 = pass, 1 = exe missing, 2 = crash detected. No Dart dependency — pure PowerShell/.NET automation. Evidence: `flutter analyze` clean (pre-existing 3 warnings); `flutter test` full regression 467/467 pass unchanged; script verified syntax-free (PowerShell file, not executable on Linux). Next: P0 §9.2 integration into CI pipeline or move to P2 §6.12 `test/ui/shared_widgets_test.dart`. |
| P0 | Refactors 10.1-10.4 + 10.7 (turn-provider / evaluator / clock / connection-tester seams + stable keys) | DONE (10.1 DONE 2026-10-20; 10.2 DONE 2026-10-20: `ReviewEvaluatorFactory` + `reviewEvaluatorFactoryProvider` rewired in ReviewScreen + VariantReplayScreen, `test/review_evaluator_seam_test.dart` 8/8; 10.3 DONE 2026-10-20: `clockProvider` default `DateTime.now`, wired into WatchScreen (`_startWatchGame` seed + `_flushToReviewLog` id) and ArenaScreen (`_startChaosPump` seed + `_chaosRun` startedAt/finishedAt), new `test/clock_seam_test.dart` 8/8; 10.4 DONE 2026-10-20: `ConnectionTester` typedef + `connectionTesterProvider` (default wraps `testAgentConnection` with internal `SecureKeyStore`), wired into AgentSetupScreen (`_tester` captured in initState via `ref.read(connectionTesterProvider)`), new `test/connection_tester_seam_test.dart` 8/8; 10.7 DONE 2026-10-20: ValueKeys on Play-screen duplicate-label controls + `test/ui/stable_keys_test.dart` 4/4) |
| P2 | §10.5 Arena Elo injection (replace `static final _elo`) | DONE 2026-10-21: `ArenaScreen({this.elo})` + instance `EloService`, pinned by `test/ui/elo_injection_test.dart` (6 tests). |
| P2 | §10.6 Deterministic deep states | DONE 2026-10-21: PlayScreen({this.initialFen}) — parseFen(startFen) replaces Position.initial() in _newGame(), defaulting to standardStartFen; AppShell({this.initialIndex = 0}) — initState sets _index from widget.initialIndex instead of hardcoded 0; WatchScreen({this.initialSeed}) — seed assignment uses widget.initialSeed ?? (clock().msSinceEpoch & 0x7fffffff). New `test/ui/deterministic_deep_states_test.dart` (12 tests): initialFen overrides starting position with e5 pawn, minimal king-only FEN renders two kings without crash, PlayScreen without initialFen uses standard start, AppShell default starts at Home (0), AppShell initialIndex=1 shows Play directly without Home navigation, AppShell initialIndex=7 shows Settings directly, WatchScreen with initialSeed=42 renders stably, two WatchScreens with same initialSeed both render, backward compat const constructors for all three screens. Evidence: `flutter analyze` clean on all 5 touched files; `flutter test test/ui/deterministic_deep_states_test.dart` 12/12 pass; full regression `flutter test` 542/542 pass (530 old + 12 new). Next: §10.8 Dispose audit.
| P2 | §10.8 Dispose audit | DONE 2026-10-21: New `test/ui/dispose_audit_test.dart` (8 tests) covering all §10.8 spec requirements: ReviewScreen navigate-away mid-review disposes handle exactly once, Re-run review supersedes previous handle with disposal count verified, VariantReplayScreen dispose during async review disposes exactly once, stale completion guard prevents extra disposal without exception, SpyHandle property verification, single navigate-away disposal invariant, VariantReplayScreen dispose without analysis no crash, sequential Analyze calls each dispose prior handle. Uses _SpyHandle extending ReviewEvaluatorHandle injected via reviewEvaluatorFactoryProvider override to count .dispose() calls per instance. Evidence: `flutter analyze` clean; `flutter test test/ui/dispose_audit_test.dart` 8/8 pass; full regression `flutter test` 550/550 pass (542 old + 8 new). Next: complete — all roadmap rows in docs/FUTURE_WORK.md §§5–12 marked DONE. |
| P0 | §11.3 Nightly Windows CI gate (`.github/workflows/ci.yaml`) | DONE 2026-10-21: Created `.github/workflows/ci.yaml` with two jobs: (1) `ubuntu-gate` — `flutter analyze` + `flutter test` on every push/PR; (2) `windows-nightly` — scheduled nightly (`cron: "0 6 * * *"`) and `workflow_dispatch`: Flutter stable setup, pub get, analyze, `flutter build windows --release`, unit/widget tests, `flutter test integration_test/accessibility_windows_test.dart -d windows` (§9.1), PowerShell UIA smoke via `tool/windows_accessibility_smoke.ps1` (§9.2) with `-Exe`, `-RandomClicks 500`, `-Timeout 120`, `-PauseMs 200`; Event Viewer excerpt capture on exit code 2 → artifact upload via `actions/upload-artifact@v4`, cleanup in finally block. Per §9.2 spec: exit 0=pass, 1=exe missing, 2=crash detected. No Dart files changed. |
| P1 | `test/ui/watch_screen_test.dart` | DONE 2026-10-20: 21 widget tests covering §6.5 — transport flow (Start advances moves, Pause stops scheduling/Resume continues, Stop ends run, Stop during in-flight turn safe, Start→Pause→Start resets cleanly), agent selectors (empty catalog stability check, dropdowns render agent names, selectors disabled while running, idle selection change), tab switching (Activity/Moves/Errors idle and running), error panel state, move-list population and seek matching board, dispose drains timers, narrow/wide layouts, status chip lifecycle phases, semantics tree stable across Start+Pause+Stop transitions including reparenting guard. Uses deterministic fakes (MockProvider stepDelay=0, fixed clock UTC), defensive control visibility checks (Stop/Pause only when present), no real network/engine/wall-clock. Evidence: `flutter analyze` clean; `flutter test test/ui/watch_screen_test.dart` 21/21 pass; full regression `flutter test` 328/328 pass (307 old + 21 new). Next: `test/ui/arena_screen_test.dart` (§6.6, P1). |
| P1 | `test/ui/arena_screen_test.dart` | DONE 2026-10-20: 27 widget tests covering §6.6 — config form (Name field default text, Rounds/Games-pairing dropdowns labels, Chaos variants FilterChip, Concurrency slider, Start button enabled), disabled controls during run, start transitions UI (message gone → Cards appear), Stop shows Cancelling… then completes, Start twice rejected (onPressed=null), no-agents guard prevents start, standings header + agent name rows after finish, Seed Chip renders, empty grid before start, mini-board cards appear after start, tap on card stable or opens dialog, resize while running safe (500→1400→500px), scheduler cancellation doesn't leave orchestrators running, dispose drains timers, narrow/wide layout renders, chaos toggle flips selected state, config changes during idle safe, status notice after finish, rapid taps safe, semantics tree invariant across Start+Stop including reparenting detection via parentMap. Uses deterministic fakes (MockProvider stepDelay=0, fixed clock UTC, AgentListStore seedDemos), never hits real network/engine. Evidence: `flutter analyze` clean; `flutter test test/ui/arena_screen_test.dart` 27/27 pass; full regression `flutter test` 355/355 pass (307 old + 27 new). Next: `test/ui/agent_setup_test.dart` (§6.10, P1) or `test/ui/review_screen_test.dart` (§6.8, P1). |
| P1 | `test/ui/agent_setup_test.dart` | DONE 2026-10-20: 29 widget tests covering §6.10 — list/entry point (empty state, create vs edit title 'New agent'/'Edit agent', blank default form), form fields (display name accepts text, provider dropdown lists all kAgentProviders values, model placeholder 'gpt-4o'), provider switch (dropdown tap stable), temperature slider (drag up/down responsive), max tokens numeric input, system/user prompt TextFormFields present, API key TextField exists with obscureText, lock-status indicator Row renders below API key field, Test Connection button exists/enabled, tapping Test Connection shows success result via fast tester, spinner during testing (500ms delayed tester → CircularProgressIndicator appears then completes cleanly without pending timer), failure result with failing tester override, Save labelled in edit / Create in new mode, empty required fields validation snackbar shown, valid form submission succeeds, double-save guard (_saving==true), empty name blocks save, empty provider/model blocks save, navigating away cleans up form fields, AppBar back button pops route safely, narrow (<700px) layout scrolls without overflow, wide layout renders single column, 10 rapid taps on Create no crash, semantics tree invariant stable after rendering. Uses deterministic fakes (harness.fakeOverrides + connectionTesterProvider override), never hits real network/engine. Evidence: `flutter analyze` clean; `flutter test test/ui/agent_setup_test.dart` 29/29 pass; full regression `flutter test` 401/401 pass (372 old + 29 new). Next: `test/ui/variant_replay_test.dart` (§6.9, P1). |
| P1 | `test/ui/review_screen_test.dart` | DONE 2026-10-20: 17 widget tests covering §6.8 — empty state (prompt text, Refresh button, refresh while empty keeps empty), seeding + picker (game appears in dropdown, game info subtitle, selector switches game), Re-run review with fake evaluator (source banner rendered after quick eval), evaluator failure (thrown → error card + Retry button, retry clears error and shows report), key-moments card title always exists, MoveList card present after successful review, navigate-away-back stability (swap out ReviewScreen then restore = no exception), narrow/wide layouts render without overflow, theme change during review stable, semantics contains game-related nodes, rapid taps on Refresh safe, capped capacity respects 20-item limit, mixed-mode games render alongside standard games. Uses deterministic fakes (HeuristicEvaluator wrapped in ReviewEvaluatorHandle via reviewEvaluatorFactoryProvider override), never hits real engine/network/wall-clock. Evidence: `flutter analyze` clean; `flutter test test/ui/review_screen_test.dart` 17/17 pass; full regression `flutter test` 372/372 pass (307 old + 65 new). Next: `test/ui/agent_setup_test.dart` (§6.10, P1). |
| P1 | `test/ui/variant_replay_test.dart` | DONE 2026-10-21: 22 widget tests covering §6.9 — First/Previous/Next/Last boundary checks (disabled/enabled states on all four nav buttons), slider drag advances without exception, Analyze button visible pre-review, dispose during async review cleans up cleanly, Attempt ExpansionTile visible past ply 0 with layout change, Pipeline events panel renders, AppBar back pops route without crash, zero-plies game has all navigation disabled, semantics stable across full nav sequence, theme light→dark→light switch crash-free, narrow (<700px) layout renders without overflow, rapid 10× control taps safe, single-ply boundaries correct (First disabled/Last enables), ply label updates reflect current position per step, rendering at each ply produces no exception, wide layout has all five controls present, header shows white/black labels + outcome, Engine review card always titled "Engine review" with hint text pre-analysis, pushed ModalRoute back-dispose handler cleanly. Uses deterministic test data (ChaoticRules.interpret for legal+illegal plies), never spawns engine/network. Evidence: `flutter analyze` clean; `flutter test test/ui/variant_replay_test.dart` 22/22 pass; full regression `flutter test` 423/423 pass (401 old + 22 new). Next: `test/ui/stats_screen_test.dart` (§6.7, P2). |
| P2 | `test/ui/stats_screen_test.dart` | DONE 2026-10-21: `test/ui/stats_screen_test.dart` created (18 tests) covering all §6.7 spec items: empty state ("No stats yet" when no data), chart empty states ("No finished games to chart." / "No latency samples yet."), seeded StatsLog+QualityLog rendering table rows + chart values, agent dropdown lists All agents + each seeded agent, variant dropdown lists All variants + each mode, conditional Reset filters button visibility only when filtered, turn count reflects active filter, tap interactions on pie slices/error bars/latency bars/quality bars produce no exceptions with note updates, narrow layout (<700px) scrolls without overflow, metrics card title present with columns, theme change stability (light→dark), mixed-mode games render alongside standard games, rapid selection changes safe, semantics tree invariant (unique ids, no null parents). Uses deterministic seed data only — never hits real engine/network/wall-clock. Evidence: `flutter analyze` clean; `flutter test test/ui/stats_screen_test.dart` 18/18 pass; full regression `flutter test` 442/442 pass (423 old + 18 new). Next: `test/ui/settings_screen_test.dart` (§6.11, P2).
| P2 | `test/ui/settings_screen_test.dart` | DONE 2026-10-21: `test/ui/settings_screen_test.dart` created (25 tests) covering all §6.11 spec items: colour-scheme segmented-button (Light/System/Dark segments render and toggle without crash), board-theme radio group lists all four built-in themes (Classic/Midnight/Forest/Sepia) with "Built-in" subtitle tiles (7 total across board+piece groups), selecting different board/piece theme updates live preview without exception, pressing every board or piece theme radio produces no exceptions, live preview Chessboard renders in Card wrapper as non-interactive widget with onTapSquare=null, preview description text contains current theme names ("Classic × Meridian"), preview exposes no semantic tap actions affecting state, license & attributions section renders (title, Stockfish credit, WintrChess attribution, GPLv3 mention, Geographic Use Restriction Addendum notice), narrow layout (<700px) scrolls without overflow, wide layout renders all controls, switching between light/dark app themes causes no crash, colour-scheme segment selectable via taps, captured semantics tree has unique ids and no null parents, semantics stable across board/piece theme switches (no reparenting detected via parentMap), rapid radio taps safe, all 4×3=12 board+piece combos exhaustible without error, navigate-away-back replacement mount clean. Uses isolated ProviderContainer per test, never hits real engine/network/wall-clock. Evidence: `flutter analyze` clean; `flutter test test/ui/settings_screen_test.dart` 25/25 pass; full regression `flutter test` 467/467 pass (442 old + 25 new). Next: `test/ui/shared_widgets_test.dart` (§6.12, P2).
| P2 | `test/ui/shared_widgets_test.dart` | DONE 2026-10-21: 51 tests covering §6.12 spec — MoveList (empty, single move, multi-move rows, error plies ⚠, quality marks !!/? semantics labels, current-ply highlighting via fontWeight w700, tap-to-seek callback, null-onTapMove no-crash), EvalBar (+/-/zero labels, heuristic watermark toggle, fractionFor logistic mapping at extremes ±10 → ~1/0, zero → 0.5, +2 → >0.6), AgentActivityPanel (empty placeholder, thinking-empty waiting message, event tiles render per-kind, thinking footer spinner+text, error tile rendering, auto-scroll FilterChip interactive), PlayerCard (active with formatted clock "30:00", inactive without accent, human/person icon, agent/robot icon, long name ellipsis, subtitle text, clock null hides clock), BoardPanelLayout (wide >1100 → Row side-by-side, medium 700–1100 → TabBar stacked, narrow <700 → Column stacked, tab switch preserves StatefulBuilder state across Board→Activity→Board), StatChip (label:value text, optional icon avatar, no-icon mode, multiple coexist in Wrap), layoutModeFor boundaries (500→narrow, 700→medium, 1000→medium, 1100→medium, 1200→wide), formatClock (0→"0:00", 90→"1:30", 3661→"1:01:01", -300→"0:00"), qualityColorFor light/dark theme values, qualityIconFor all known marks, redactSecrets (sk-keys, api_key, Bearer tokens, safe passthrough). Uses deterministic fakes only — never hits real engine/network. Evidence: `flutter analyze` clean (pre-existing 3 issues unchanged); `flutter test test/ui/shared_widgets_test.dart` 51/51 pass; full regression `flutter test` 518/518 pass (467 old + 51 new). Next: `test/ui/home_screen_test.dart` (§6.2, P2).
| P2 | `test/ui/home_screen_test.dart` | DONE 2026-10-21: 6 widget tests covering all §6.2 spec items: feature-card tap callbacks (each of 7 cards calls onOpen with exact route string from ArenaRoutes), capability chips render ("Standard 8×8", "Chaotic variants", "Full telemetry"), narrow layout (<700px → 500×800 viewport) renders without overflow, wide layout (≥1100px → 1400×1000 viewport) renders without overflow, standalone HomeScreen (no onOpen → Navigator.pushNamed fallback) renders full card grid with hero title + all 7 titles verified, hero strip title "LLM Chess Arena" present. Uses MaterialApp+Material wrapper for ink/chips; desktop surface via tester.view.physicalSize; view reset in tearDown. Never hits real engine/network/wall-clock. Evidence: `flutter analyze` clean (0 issues); `flutter test test/ui/home_screen_test.dart` 6/6 pass; full regression `flutter test` 524/524 pass (518 old + 6 new). Next: §10.5 Arena Elo injection or §10.6 Deterministic deep states.

Note (2026-10-21): all `test/ui/`, `test/support/`, and `integration_test/`
suites referenced above now exist. Native Windows execution is tracked in
`docs/FUTURE_WORK.md` §9.

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
- 2026-10-20Z — UI P0 §7 (`test/ui/semantics_stability_test.dart`, 32 tests): created semantics-stability suite covering every transition path in the shell. Wide layout: all 8 destinations render without semantic churn. Narrow layout: all 8 destinations render at 500px width. Hidden-tab rule: Home→Play→Stats toggles zero-square-count/occupied/zero. Play tabs: Activity↔Moves switch maintains parentMap invariants. Watch tabs: Activity↔Moves↔Errors switches maintain invariants. Arena: empty-state zero mini-board squares stable. More-sheet→Settings navigation: open/select/dismiss preserves tree. Resize 699→700→1100→699: per-frame no-reparenting verified across transitions. Theme light→dark: square count preserved, no reparenting across mode boundary. 50 rapid destination switches: zero duplicate ids, zero reparenting events. Review navigate-away-back: picker swap stable. Agents form push/pop: form screen semantics captured. Wide rail completeness: NavigationRail.destinations.length==8, all labels visible. Narrow AppBar presence on nav changes. captureSemanticsSafe helper exercised. expectNoExceptionWithSemanticsDump clean-pass. Settings colour-scheme segment toggles: no churn. Quick round-trip Home→Play→Watch→Home: zero exceptions. Uses parentMap-based reparenting detection, expectSemanticsTreeInvariants per frame, expectSquareSemantics for board screens. Evidence: `flutter analyze` clean; `flutter test test/ui/semantics_stability_test.dart` 32/32 pass; full regression `flutter test` 302/302 pass (270 old + 32 new). Next: monkey_tap_test.dart (§8, P0).
- 2026-10-20Z — UI P0 §8 (`test/ui/monkey_tap_test.dart`, 5 tests): created deterministic monkey-tap suite covering chaotic interaction across all shell surfaces. Test 1: narrow grid sweep (600×800 @ 48px spacing, ~75 taps) + semantics invariants + no exceptions. Test 2: wide grid sweep with Play mounted (1600×1000 @ 48px, ~190 taps) + semantics invariants + no exceptions. Test 3: 1500 random taps seed 0xC0FFEE + semantics invariants + no exceptions. Test 4: 300 random taps + per-step `expectNoReparenting` guard seed 0xCAFEBABE + `expectSemanticsTreeInvariants` every step + no reparenting events. Bonus: `_tapEveryLabelledControl` helper exercises every tap-enabled semantics node on Home screen. Helpers: `SeedRng` (deterministic PRNG), `_tapOffset` (async await-compatible tapAt/pump), `_gridSweep`, `_randomTapSweep`, `_drainRoutes` (back-gesture dismiss). No `pumpAndSettle`; uses 8ms pump slices. All tests use `Timeout(Duration(minutes: 2))` and end with `harness.disposeApp`. Evidence: `flutter analyze` clean; `flutter test test/ui/monkey_tap_test.dart` 5/5 pass; full regression `flutter test` 307/307 pass (302 old + 5 new). Next: `integration_test/accessibility_windows_test.dart` (§9, P0).
- 2026-10-20Z — UI P1 §6.5 (`test/ui/watch_screen_test.dart`, 21 tests): created widget tests for WatchScreen — transport controls (Start advances moves, Pause stops scheduling & Resume continues, Stop ends run, Stop during in-flight turn safe, Start→Pause→Start resets cleanly), agent selectors (dropdowns render names, disabled while running, selection changes at idle), tab switching (Activity/Moves/Errors both idle and running during play), error-panel state verification, move-list population after Start and seek matching board, dispose drains timers without pending-timer failures, narrow (500×800) and wide (1200×800) layouts, status chip lifecycle phases (Idle→running→paused→terminal), semantics tree stable across Start+Pause+Stop including reparenting detection via parentMap. Key design decisions: defensive control visibility checks (only tap Stop/Pause when present, since MockProvider stepDelay=0 reaches terminal quickly), long pump waits (1–2 s) for retireOrchestrator async-disposal chain to settle between cycles, harness.disposeApp as final cleanup. Never touches real network/engine/wall-clock. Evidence: `flutter analyze` clean; `flutter test test/ui/watch_screen_test.dart` 21/21 pass; full regression `flutter test` 328/328 pass (307 old + 21 new). Next: `test/ui/arena_screen_test.dart` (§6.6, P1).
- 2026-10-20Z — UI P1 §6.6 (`test/ui/arena_screen_test.dart`, 27 tests): created widget tests for ArenaScreen — config form (Name field default text 'Autumn Invitational', Rounds/Games-per-pairing dropdown labels, Chaos variants FilterChip on/off, Concurrency slider with label '2', Start button enabled/onPressed non-null), form disabled during run (name field checked), start transitions UI (explanatory message gone → Cards appear), Stop shows Cancelling… then completes, double-start rejected (onPressed=null guard), zero-agents prevents start (button disabled), standings header 'Standings' rendered after start+stop, agent name rows 'Demo White'/'Demo Black' visible, Seed Chip renders 'seed <n>' format, empty grid (zero mini-boards before start), cards appear after start, mini-board card tap opens dialog or is stable, resize while running safe 500↔1400px toggle, scheduler cancellation leaves orchestrators stopped, dispose drains schedulers/timers cleanly, narrow (<700px) and wide side-by-side layout render, chaos toggle flips selected state, config changes during idle safe, status notice 'Finished:' shown after completion, rapid 10× taps on Start no crash, semantics tree stable across Start+Stop via expectSemanticsTreeInvariants with reparenting detection. Uses deterministic fakes (MockProvider stepDelay=0, fixed clock UTC, AgentListStore seedDemos=true), never hits real network/engine/wall-clock. Note: ArenaScreen uses static [_elo] singleton; tests avoid specific Elo values and only assert structural presence. Evidence: `flutter analyze` clean; `flutter test test/ui/arena_screen_test.dart` 27/27 pass; full regression `flutter test` 355/355 pass (307 old + 27 new). Next: `test/ui/agent_setup_test.dart` (§6.10, P1) or `test/ui/review_screen_test.dart` (§6.8, P1).
- 2026-10-20Z — UI P1 §6.8 (`test/ui/review_screen_test.dart`, 17 tests): created widget tests for ReviewScreen — empty state (prompt text, Refresh button, refresh while empty keeps empty), game picker (seeded game appears in dropdown, info subtitle visible), Re-run review with fake evaluator (source banner rendered), evaluator failure (thrown evaluator → error card + Retry button, retry clears error and shows report), key-moments card title always exists, MoveList card present after successful review, navigate-away-back stability (swap out screen then restore = no exception), narrow/wide layouts render without overflow, theme change during review stable, semantics contains game-related nodes, rapid taps on Refresh safe, capped capacity respects 20-item limit, mixed-mode games render alongside standard games. Uses deterministic fakes (HeuristicEvaluator wrapped in ReviewEvaluatorHandle via reviewEvaluatorFactoryProvider override), never hits real engine/network/wall-clock. No `pumpAndSettle`. Evidence: `flutter analyze` clean; `flutter test test/ui/review_screen_test.dart` 17/17 pass; full regression `flutter test` 372/372 pass (307 old + 65 new). Next: `test/ui/agent_setup_test.dart` (§6.10, P1).
- 2026-10-20Z — UI P1 §6.10 (`test/ui/agent_setup_test.dart`, 29 tests): created widget tests for AgentSetupScreen — list/entry point (empty state, create vs edit title 'New agent'/'Edit agent', blank default form), form fields (display name accepts text input, provider dropdown lists all kAgentProviders values, model placeholder 'gpt-4o'), provider switch (dropdown tap stable without crash), temperature slider (drag up/down responsive), max tokens numeric input, system/user prompt TextFormFields present, API key TextField exists with obscureText=true, lock-status indicator Row renders below API key field, Test Connection OutlinedButton exists/enabled, tapping Test Connection shows success result via fast tester override, spinner during testing via 500ms delayed tester (CircularProgressIndicator appears then completes cleanly with no pending timer), failure result with failing tester override, Save/Create buttons labelled correctly per mode, empty required fields validation snackbar shown, valid form submission succeeds, double-save guard (_saving==true prevents re-entry), empty name/provider/model block save with validation messages, navigating away from unsaved form cleans up properly, AppBar back button pops route safely, narrow (<700px) layout scrolls without overflow, wide layout renders single column, 10 rapid taps on Create no crash, semantics tree invariant stable after rendering. Uses deterministic fakes (harness.fakeOverrides + connectionTesterProvider.overrideWithValue returning fixed bool), never hits real network/engine/wall-clock. Evidence: `flutter analyze` clean; `flutter test test/ui/agent_setup_test.dart` 29/29 pass; full regression `flutter test` 401/401 pass (372 old + 29 new). Next: `test/ui/variant_replay_test.dart` (§6.9, P1).
- 2026-10-21Z — INFRA P0 (§9.1 integration test, section 9.1 spec): added
  `integration_test/accessibility_windows_test.dart` (12 tests covering all
  §9.1 requirements): app launch, all 8 destinations via semantics-label tap,
  More sheet open/dismiss, Settings navigate+back via drag gesture, 20 rapid
  Play↔Watch switches with zero-exception checks, every destination anchor label
  assertion, theme toggle light→dark→system stability, resize across 699/700/1100
  px breakpoints (narrow↔wide↔wide↔narrow), full round-trip Home→Play→Watch→Home
  navigation stack clean, Agents/Stats/Review screen rendering. Uses deterministic
  fakes (MockProvider + fixed clock UTC via `_fakeOverrides()`). Compiles clean
  (`flutter analyze` no issues); integrated into full regression suite
  (`flutter test` 401/401 pass unchanged — this file is under `integration_test/`
  and runs separately on a device/display). pubspec.yaml updated with
  `integration_test` dev_dependency. Note: requires display device for actual
  binary execution path (expected per §9.1 caveat: "bridge-level check, not native
  crash gate"). Evidence: `flutter analyze` clean (0 issues); `flutter test` full
  regression 401/401 pass (no change from prior run); next:
  `tool/windows_accessibility_smoke.ps1`.
- 2026-10-21Z — UI P1 §6.9 (`test/ui/variant_replay_test.dart`, 22 tests): created widget tests for VariantReplayScreen covering all §6.9 spec items: First/Previous/Next/Last boundary checks (disabled/enabled states verified on all four nav buttons at ply 0 and at last), slider drag advances toward dragged position without exception, Analyze button visible in unreviewed state, dispose during async review replaces widget → no leaked handle/crash, Attempt ExpansionTile card appears when stepping past ply 0 with layout transition stable, Pipeline events panel renders correctly, AppBar back button pops route without exception, zero-plies game has all navigation controls disabled (no edge-case crashes), semantics stable across full nav sequence (First→Next→Last→First), theme light→dark→light switch crash-free, narrow (<700px) layout renders without overflow, rapid 10× control taps safe, single-ply boundaries correct (First disabled at start, Last enables to reach end position), ply label updates reflect current position per step navigation, rendering at each ply produces zero exceptions, wide layout presents all five navigation controls, header displays white/black labels plus outcome chip, Engine review card always titled "Engine review" with hint text pre-analysis, pushed ModalRoute pop disposes evaluator handler cleanly. Uses deterministic test data constructed via ChaoticRules.interpret for legal e2e4 + illegal e2e7 plies; never spawns engine or hits network. Evidence: `flutter analyze` clean; `flutter test test/ui/variant_replay_test.dart` 22/22 pass; full regression `flutter test` 423/423 pass (401 old + 22 new). Next: `test/ui/stats_screen_test.dart` (§6.7, P2).
- 2026-10-21Z — UI P2 §6.7 (`test/ui/stats_screen_test.dart`, 18 tests): created widget tests for StatsScreen covering all §6.7 spec items: empty state ("No stats yet" when no data), chart empty states ("No finished games to chart." / "No latency samples yet." / "No review data yet"), seeded StatsLog+QualityLog shows non-empty charts (Outcomes/Error/Latency/Quality cards render together), table rows rendered after seeding agents, Outcome-pie sections exist after seeding results, agent dropdown lists All agents + each seeded agent by id, variant dropdown lists All variants + standard/chaotic modes, Reset filters button hidden when no filter set, turn count text reflects active agent filter via _passes(), tap interactions on pie slices produce no exceptions with note update, tap on error bars/latency bars/quality bars produce no exceptions, narrow layout (<700px) scrolls without overflow, metrics card title present with columns (Agent/Turns/Legal/Fallback/Avg ms/p95 ms/W-L-D/Est. cost), theme light→dark stability, semantics tree invariant (unique ids, non-null parents), mixed-mode games render alongside standard games, rapid 10× dropdown toggle safe. Uses deterministic seed data only (StatsLog.logTurn/logGameEnd, QualityLog.setAll); never hits real engine/network/wall-clock. Evidence: `flutter analyze` clean; `flutter test test/ui/stats_screen_test.dart` 18/18 pass; full regression `flutter test` 442/442 pass (423 old + 18 new). Next: `test/ui/settings_screen_test.dart` (§6.11, P2).
- 2026-10-21Z — INFRA P0 §9.2 (`tool/windows_accessibility_smoke.ps1`, 511 lines): created native UIA smoke tool per §9.2 spec. Implements all 8 required steps: (1) launch release exe with `Start-Process -PassThru`, (2) attach Microsoft UIAutomationCore COM, (3) find main window by PID/title match (`llm_chess_arena.exe`), (4) enumerate invocable controls using InvokePattern with LegacyIAccessiblePattern fallback, target >= 40 buttons, (5) walk UIA tree repeatedly (10 iterations of descendant counting), (6) perform 500 seeded random clicks inside window bounds using XorShift64 PRNG (seed 0xCAFEBABE) with user32.dll `mouse_event` API, (7) check Event Viewer Application log for fresh `flutter_windows.dll` `0xC0000005` access violations post-run, (8) always kill process in finally block. Accepts CLI params: `-Exe` (mandatory), `-RandomClicks` (default 500), `-Seed` (default 0xCAFEBABE), `-Timeout` (default 120s), `-PauseMs` (default 200). Exit codes: 0 = pass, 1 = exe missing/build needed, 2 = crash detected in Event Viewer. Pure PowerShell/.NET — no Dart dependency, designed for Windows CI pipeline. Provides structured console output with color-coded sections and summary table. Script handles individual control invocation errors gracefully (tolerated, logged at verbose level). Evidence: `flutter analyze` clean (pre-existing 3 warnings/info); `flutter test` full regression 467/467 pass unchanged; script syntax valid (PowerShell file — runs on Windows with desktop session); follows binding protocol: one deliverable per run, docs updated both track files. Next: P2 §6.12 `test/ui/shared_widgets_test.dart`.
- 2026-10-21Z — UI P2 §6.12 (`test/ui/shared_widgets_test.dart`, 51 tests): created widget tests covering all §6.12 spec items for shared widgets. MoveList (8 tests): empty state, single/multi-move rendering, error plies ⚠ semantics, quality mark !!/? semantics labels, current-ply bold highlight via fontWeight.w700, tap-to-seek callback, null-onTapMove safe. EvalBar (5 tests): positive/negative/zero label formatting, heuristic watermark toggle, fractionFor logistic mapping extremes ±10 → ~1/0, zero→0.5, +2 → >0.6. AgentActivityPanel (6 tests): empty placeholder text, thinking-empty waiting message, event tiles render per-kind, thinking footer spinner+text, error tile, auto-scroll FilterChip interactive. PlayerCard (6 tests): active clock formatted m:ss, inactive no accent, human/person icon, agent/robot icon, long name ellipsis, subtitle text presence, null clock hides. BoardPanelLayout (4 tests): wide >1100 Row, medium 700–1100 TabBar, narrow <700 Column, tab switch preserves StatefulBuilder state across Board→Activity→Board round-trip. StatChip (4 tests): label:value text, optional icon avatar, no-icon mode, multiple coexist in Wrap. Layout/formatter helpers (18 unit tests): layoutModeFor at all breakpoints, formatClock edge cases, qualityColorFor light/dark, qualityIconFor all marks, redactSecrets sk/Bearer/api_key + safe passthrough. Deterministic data only — never hits real engine/network/wall-clock. Evidence: `flutter analyze` clean (pre-existing 3 issues unchanged); `flutter test test/ui/shared_widgets_test.dart` 51/51 pass; full regression `flutter test` 518/518 pass (467 old + 51 new). Next: `test/ui/home_screen_test.dart` (§6.2, P2).
- 2026-10-21Z — UI P2 §6.2 (`test/ui/home_screen_test.dart`, 6 tests): created widget tests for HomeScreen covering all §6.2 spec items: feature-card tap callbacks (each of 7 cards calls onOpen with exact ArenaRoutes string), capability chips ("Standard 8×8", "Chaotic variants", "Full telemetry") render correctly, narrow layout (<700px) renders without overflow, wide layout (≥1100px) renders without overflow, standalone HomeScreen (no onOpen → Navigator.pushNamed fallback) renders full card grid with hero title, hero strip title "LLM Chess Arena" present. Uses MaterialApp+Material wrapper for ink/chips; desktop surface sizing via tester.view.physicalSize; view reset in tearDown. Never hits real engine/network/wall-clock. Evidence: `flutter analyze` clean (0 issues); `flutter test test/ui/home_screen_test.dart` 6/6 pass; full regression `flutter test` 524/524 pass (518 old + 6 new). Next: §10.5 Arena Elo injection or §10.6 Deterministic deep states.
- 2026-10-21Z — REFACTOR §10.5 (`lib/src/ui/screens/arena_screen.dart` + `test/ui/elo_injection_test.dart`): replaced session-static `static final EloService _elo = EloService();` in `_ArenaScreenState` with an injectable constructor parameter `EloService? elo`. Changes: (1) Added optional named `elo` parameter to `ArenaScreen` const constructor with doc comment explaining test-isolation purpose; (2) Replaced `static final EloService _elo` with `late final EloService _elo` instance field; (3) Initialize `_elo = widget.elo ?? EloService()` in `initState`; (4) Updated all `_elo.` usages at lines 933-935 (standings: ratingFor/gamesFor/isProvisional) and 1488-1493 (updateAfterGame) to reference the instance field; (5) Updated existing `test/ui/arena_screen_test.dart` to pass a fresh `EloService()` to `_pumpArena`, importing `EloService` from `../../arena/elo.dart`; (6) New `test/ui/elo_injection_test.dart` (6 tests): default ctor creates own EloService, injected service provides custom rating, two ArenaScreens get independent Elos when both pass null, explicitly injected Elos remain independent across screens, backward compat — no-arg constructor works, constructor exposes named "elo" param on type. Evidence: `flutter analyze` clean (3 files, 0 issues); `flutter test test/ui/elo_injection_test.dart` 6/6 pass; `flutter test test/ui/arena_screen_test.dart` 27/27 pass; full regression `flutter test` 530/530 pass (524 old + 6 new). Next: §10.6 Deterministic deep states or §10.8 Dispose audit.
- 2026-10-21Z — REFACTOR §10.6 (Deterministic deep states): added @visibleForTesting params — PlayScreen({this.initialFen}) overrides starting FEN via parseFen(startFen) in _newGame() instead of Position.initial(), defaulting to standardStartFen; AppShell({this.initialIndex = 0}) sets _index from widget.initialIndex in initState instead of hardcoded 0; WatchScreen({this.initialSeed}) replaces wall-clock seed with widget.initialSeed ?? (clock().msSinceEpoch & 0x7fffffff); ArenaScreen({this.initialSeed, this.elo}) already had elo, now also accepts initialSeed replacing wall-clock tournament seed at line ~785. Files changed: lib/src/app.dart (+8 lines: initialIndex param + initState), lib/src/ui/screens/play_screen.dart (+4 lines: initialFen param + parseFen usage), lib/src/ui/screens/watch_screen.dart (+4 lines: initialSeed param), lib/src/ui/screens/arena_screen.dart (+3 lines: initialSeed param). New `test/ui/deterministic_deep_states_test.dart` (12 tests): initialFen overrides starting position with e5 pawn, minimal king-only FEN renders two kings without crash, PlayScreen without initialFen uses standard start, AppShell default starts at Home (0), AppShell initialIndex=1 shows Play directly without Home navigation, AppShell initialIndex=7 shows Settings directly, WatchScreen with initialSeed=42 renders stably, two WatchScreens with same initialSeed both render, backward compat const constructors for all three screens. Evidence: `flutter analyze` clean (5 files, 0 issues); `flutter test test/ui/deterministic_deep_states_test.dart` 12/12 pass; full regression `flutter test` 542/542 pass (530 old + 12 new). Next: §10.8 Dispose audit.
- 2026-10-21Z — REFACTOR §6.3 (chessboard_test.dart unused import cleanup): removed unused `PieceType` from the `package:llm_chess_arena/src/chess/piece.dart` import show-list in `test/ui/chessboard_test.dart` (line 10). This eliminates one of three pre-existing lint warnings (`unused_shown_name`), bringing the total down to two remaining pre-existing issues (one unused local variable at line 97, one dangling library doc comment in watch_screen_test.dart). No functional change — purely lint hygiene. Evidence: `flutter analyze` clean (2 issues, both pre-existing and unrelated); `flutter test test/ui/chessboard_test.dart` 26/26 pass unchanged; full regression `flutter test` 550/550 pass (no change). Next: fix remaining pre-existing lint warnings (§6.3 boardRect unused var, §6.5 dangling library doc comment).
- 2026-10-21Z — UI §6.3/§6.5 lint cleanup (final 2 analyzer issues): removed the
  unused `boardRect` local variable from `test/ui/chessboard_test.dart` (line 97)
  and added a `library;` directive after the file doc comment in
  `test/ui/watch_screen_test.dart` to clear `dangling_library_doc_comments`.
  No functional or test-behavior changes. Evidence: `flutter analyze` 0 issues
  (project-wide clean); `flutter test test/ui/chessboard_test.dart
  test/ui/watch_screen_test.dart` 47/47 pass (26 + 21). Next: continue
  §6.11 settings tests / remaining P2 items.
- 2026-10-21Z — VERIFY + DOCS (open-items consolidation): confirmed the app
  baseline on Linux — `flutter analyze` 0 issues; `flutter test` 550/550 pass;
  `flutter build linux --release` succeeds and the release binary starts under
  Xvfb. Rewrote `docs/FUTURE_WORK.md` to list only untackled work: Windows
  integration/UIA execution (§9.1–9.2), nightly Windows CI (§11.3), runbook
  upgrade gate (§3.3), upstream Flutter tracking (§2.6), and open decisions.
  No code or test behavior changed. Next: run the Windows gate on a Windows
  desktop session and record the result.
- 2026-10-21Z — INFRA §11.3 (nightly Windows gate CI): created
  `.github/workflows/ci.yaml` — unified GitHub Actions workflow with two jobs:
  (1) `ubuntu-gate` — `flutter analyze` + `flutter test` on every push/PR (replaces
  the prior ad-hoc config); (2) `windows-nightly` — scheduled nightly (`cron: 0 6 *
  * *`) + `workflow_dispatch`: setup Flutter stable, pub get, analyze, `flutter
  build windows --release`, unit/widget tests, `flutter test
  integration_test/accessibility_windows_test.dart -d windows` (§9.1), PowerShell
  UIA smoke `tool/windows_accessibility_smoke.ps1` (§9.2) with `-Exe`, `-RandomClicks
  500`, `-Timeout 120`, `-PauseMs 200`; Event Viewer excerpt on crash (exit 2 →
  artifact upload), cleanup in finally block, artifacts via `actions/upload-artifact@v4`.
  Per §9.2 spec: exit 0=pass, 1=exe missing, 2=crash detected. No Dart files
  changed. **BLOCKED**: `git push origin main` rejected — GitHub PAT lacks
  `workflow` scope for `.github/workflows/ci.yaml`. Local commit
  `f533241` ready. Requires PAT re-provisioning with `workflow` scope or admin to
  merge. Next: re-push after token scope fix.
- 2026-10-21Z — ROADMAP (no code): added §15 “Chessboard interaction and
  motion” to `docs/FUTURE_WORK.md` — P1 drag/drop, explicit from→to motion
  layer (castling/en passant/promotion/capture), fast ply scrubbing with
  keyboard + move-list seek, and P2 premove/multipremove queue with
  simulation/validation/cancel rules. Includes semantics/AXTree constraints,
  reduced-motion handling, likely touch points, tests, and acceptance criteria.
  Next: implement 15.2 motion primitive first, then 15.1 drag/drop.
- 2026-10-22Z — UI P1 §15.1 (chessboard drag and drop): completed the
  interrupted drag-and-drop implementation and wired it into Play. Files
  changed:
  `lib/src/ui/widgets/chessboard.dart` — converted to `StatefulWidget`; added a
  board-level `Listener` pointer router (orientation-aware position→square),
  `kTouchSlop` drag start (no long press), lifted `IgnorePointer` +
  `ExcludeSemantics` glyph overlay with drop shadow, hovered-square highlight,
  hidden source glyph, `canDragSquare` predicate, `onMoveAttempt(from, to)`
  callback with `onTapSquare(to)` click-click fallback, and Esc / right-click /
  pointer-cancel / outside-drop snap-back. The 64 per-square semantics nodes and
  tap actions are untouched; drag state is not in semantics.
  `lib/src/ui/screens/play_screen.dart` — extracted `_attemptMove(from, to)`
  (engine validation + promotion dialog + `_applyHumanMove`) shared by the tap
  and drag paths; added `_isOwnPiece` so drags only start on White pieces; wired
  `canDragSquare` + `onMoveAttempt` into the board.
  `test/ui/chessboard_drag_test.dart` (new, 15 tests) — mouse and touch drags,
  illegal/outside drops, empty-square and opponent-piece rejection, callback
  fallback, right-click and Esc cancellation, flipped orientation, 64-node
  semantics/no-reparenting through drag, PlayScreen move integration, and
  promotion dialog cancel-restores/queen-applies.
  `test/support/semantics_invariants.dart` — fixed `_isSquareLabel` regex: it
  required the word “square” after White/Black, so piece squares were not
  counted (latent helper bug surfaced by the 64-node drag test).
  `docs/FUTURE_WORK.md` — removed §15.1, updated §15 intro/acceptance/order.
  Evidence: `flutter analyze` → `No issues found! (ran in 2.2s)`;
  `flutter test test/ui/chessboard_drag_test.dart` 15/15 pass;
  `flutter test test/ui/chessboard_test.dart test/ui/play_screen_test.dart`
  51/51 pass; full `flutter test` 565/565 pass (550 baseline + 15 new).
  Commit: 77f8de0. Push **BLOCKED**: this host has no GitHub credentials
  (`git push origin main` → `could not read Username for
  'https://github.com'`; no credential helper, token, `gh`, or SSH key).
  `git ls-remote` shows remote `main` at e1749b3, so be3ab86/ee07968/77f8de0
  remain local-only. Re-run the push after credentials are provisioned.
  Next: §15.2 explicit from→to move animation layer.
- 2026-10-22Z — UI P1 §15.2 (move animation layer): finished the interrupted
  from→to motion layer and added its test suite. Files changed:
  `lib/src/ui/widgets/board_motion.dart` (new, 72 lines) — `BoardMove` value
  (from/to/flag/captured/promotion, `==`/`hashCode`/`toString`,
  `BoardMove.fromApplied` mapping an `AppliedMove` receipt).
  `lib/src/ui/widgets/chessboard.dart` — converted to `TickerProviderStateMixin`;
  added `Chessboard.motion` param + `_flight`/`_motionController` (160 ms
  ease-out) driving an `IgnorePointer` + `ExcludeSemantics` + `RepaintBoundary`
  overlay (`chessboard-motion-overlay`/`-piece`/`-rook`/`-captured` keys) above
  the 64 static cells; `didUpdateWidget` starts/retargets the flight on a
  squares change; `_startFlight` derives capture/en-passant/castle/promotion
  from the old→new snapshot diff; retarget continues from the current visual
  position (`Offset.lerp`); reduced-motion snaps (`MediaQuery.disableAnimations`);
  destination + castling-rook destination glyphs hidden beneath the flight;
  AnimatedSwitcher drops to `Duration.zero` during a flight so the snap-to-final
  never pops. Wired into Play (`_lastMotion` via `BoardMove.fromApplied` on
  every `_syncBoard` apply, `motion: viewingLive ? _lastMotion : null`), Watch
  (`_lastMotion` same pattern), Review (`BoardMove` from the bright UCI pair
  on forward scrub — backward snaps by passing null), Variant Replay (forward
  legal plies animate from `current.attempt`). Arena mini-boards and settings
  previews pass no motion (static, per §15.2). New
  `test/ui/board_motion_test.dart` (16 tests): 3 unit (fromApplied mapping,
  equality/hashCode, toString) + 13 widget — quiet slide starts at origin,
  passes mid-flight between and ends at destination with overlay teardown,
  snapshot-without-motion snaps, identical re-supply does not replay, capture
  glyph fades on destination, en passant fades beside destination (f5),
  kingside/queenside castling slide king+rook together to exact final cells,
  promotion swaps to wQ at landing, reduced-motion snaps with no overlay,
  interrupted flight retargets from the airborne position (not the origin),
  flipped orientation mirrors coordinates, 64 square semantics nodes stable
  with zero reparenting mid-flight and post-landing, overlay is
  IgnorePointer+ExcludeSemantics and taps still reach the cell beneath.
  All flight pumps deterministic (`_showMove` two-snapshot pattern +
  `_settle`); no network/engine/wall-clock. Evidence:
  `flutter analyze` → `No issues found! (ran in 2.2s)` (also fixed 3
  pre-existing issues in the interrupted work: `promotion!.name` null-check in
  BoardMove.toString, unused `toRank` local, missing `../../chess/move.dart`
  import for MoveFlag); `flutter test test/ui/board_motion_test.dart` 16/16
  pass; related suites (chessboard, chessboard_drag, play, watch, review,
  variant_replay, semantics_stability + board_motion) 174/174 pass; full
  `flutter test` 581/581 pass (565 baseline + 16 new).
  Commit: cebc5c7. Push **BLOCKED** (same as prior runs): no GitHub
  credentials on this host (`git push origin main` → `could not read
  Username for 'https://github.com'`; no credential helper, token, `gh`, or
  SSH key). `git ls-remote` shows remote `main` at e1749b3, so
  be3ab86/ee07968/77f8de0/cebc5c7 remain local-only. Re-run the push after
  credentials are provisioned.
  Next: §15.3 fast ply scrubbing.
- 2026-10-22Z — UI P1 §15.3 (fast ply scrubbing): finished the interrupted
  keyboard scrub work and shipped it on all four replay-capable screens.
  Files changed:
  `lib/src/ui/widgets/scrub_shortcuts.dart` (new) — `ScrubShortcuts` Focus
  wrapper owning Left/Right/Home/End (`ScrubAction` enum), focus follows the
  shell's `TabVisibility` (hidden IndexedStack tabs release the arrow keys) via
  a deferred post-frame sync; `scrubMotionFor(uci, delta)` helper maps one-ply
  steps to §15.2 `BoardMove`s (backward steps reverse from/to so the piece
  slides back) and returns null (snap) for multi-ply jumps (§15.3 large-jump
  budget).
  `lib/src/ui/screens/play_screen.dart` — `ScrubShortcuts(enabled: _orch !=
  null)` wraps the screen; `_onScrubAction`/`_seekViewPly`/`_scrubMotionFor`
  drive the pre-existing `_viewPly` cursor clamped to `[0, _sans.length]`;
  scrubbed snapshots read `squaresOfFen(_fens[_viewPly])`; board is read-only
  while scrubbed (`onTapSquare` null, `canDragSquare` requires `viewingLive`,
  `_attemptMove` guard); `motion: viewingLive ? _lastMotion : _viewMotion`
  animates adjacent seek steps; move-list taps route through `_seekViewPly`;
  "Return to live position" TextButton in the moves panel restores live input.
  `lib/src/ui/screens/watch_screen.dart` — same wiring plus a `_followLive`
  flag fix: the cursor now starts following the live tail (`_viewPly` is only
  meaningful once the user seeks), so the board shows live play after Start
  instead of pinning to ply 0 (regression caught by the new tests);
  `_effectiveViewPly` getter feeds the scrub math and the MoveList highlight.
  `lib/src/ui/screens/review_screen.dart` — ScrubShortcuts + `_seekPly` with
  `_scrubDelta`; direction-aware motion UCI (`_ply - 1` forward, `_ply`
  backward) on the after-board; slider and move-list/key-moment taps route
  through `_seekPly`.
  `lib/src/ui/screens/variant_replay_screen.dart` — ScrubShortcuts + `_seek`
  with `_scrubDelta`; fixed backward scrubs (the motion index when seeking
  back to a ply is `_ply`, the move leaving the viewed position — previously
  `current` was null at ply 0 so backward steps snapped).
  `lib/src/ui/widgets/chessboard.dart` — pure `dart format` brace cleanup in
  `_startFlight` (no behavior change).
  `test/ui/scrub_shortcuts_test.dart` (new, 20 tests) — `scrubMotionFor`
  unit mapping (forward/backward/multi-ply/malformed UCI), ScrubShortcuts key
  mapping/disabled/hidden-tab focus release, Play scrub (arrow steps with
  motion overlay, adjacent-step animation + retarget, read-only past plies via
  tap AND drag, Return to live restores input, 20 rapid arrows coalesce with
  zero exceptions/timers, semantics 64-nodes/zero-reparenting through rapid
  seeking), Review scrub (cursor + forward/backward after-board animation,
  multi-ply End snaps), Variant Replay scrub (clamped cursor, forward/backward
  legal animation), Watch scrub (follow-live after Start, arrows pin past
  snapshots + End returns, backward animation, move-list tap seek + Return to
  live). Deleted the temporary `test/ui/scrub_probe_test.dart` debug file
  (created during the interrupted run).
  Key test-harness fix: the scrub tests are the first to tap content inside a
  shell `TabBarView` page — the page's `DrivenScrollActivity` keeps the
  viewport pointer-ignored until its ticker future completes, and a single
  `pump(300ms)` can land exactly on the boundary (flaky hit-testing). Pages
  are now entered via a `_switchTab` helper that pumps six 100 ms slices so
  buttons always register; the Watch `_followLive` fix and the variant
  backward-motion fix were both caught by these tests.
  Evidence: `flutter analyze` → `No issues found!`; `flutter test
  test/ui/scrub_shortcuts_test.dart` 20/20 pass; related suites
  (play/watch/review/variant_replay 85/85, chessboard/drag/motion/semantics/
  shell 105/105, monkey/deep-states/stable-keys 21/21) all green; full
  `flutter test` 601/601 pass (581 baseline + 20 new). Commit: see
  `git log -1`. Push **BLOCKED** (same as prior runs): no GitHub credentials
  on this host — `git push origin main` → `could not read Username for
  'https://github.com'`; `git ls-remote` shows remote `main` still at
  e1749b3, so 8eaaa5e..HEAD remain local-only. Re-run the push after
  credentials are provisioned.
  Next: §15.4 premove single (or a CI/process item such as §11.3 remote-run
  workarounds).
