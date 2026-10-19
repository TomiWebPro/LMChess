# WintrChess — Investigation Notes (verified where stated)

> Rule: nothing below invents a WintrChess API, protocol detail, license
> term, or capability. Claims fetched live from
> `cdn.jsdelivr.net/gh/wintrcat/wintrchess@master/...` are marked
> **VERIFIED (jsdelivr)** with the exact path. Unverified claims are
> marked **UNVERIFIED** — do not build on them.

## 1. What WintrChess is (VERIFIED)

- **Upstream:** `wintrcat/wintrchess`, branch `master`. **VERIFIED
  (jsdelivr):** `package.json` (root), `shared/package.json`,
  `server/package.json`, `client/package.json`, `Dockerfile`,
  `eslint.config.js`, `LICENSE`.
- **Shape:** TypeScript monorepo with npm workspaces
  `./shared`, `./server`, `./client` (root `package.json` workspaces +
  scripts `start`/`build`/`dev`/`lint`).
- **Server:** Express + MongoDB/Mongoose + chess.js
  (`server/package.json`: `express`, `mongodb`, `mongoose`, `chess.js`,
  `better-auth`, `zod`; `server/src/index.ts`: clustered Express serving
  `client/dist` + `mainRouter`).
- **Client:** React + react-chessboard (`client/package.json`: webpack
  build, `react`, `chess.js`, `@tanstack/react-query`; server serves
  `client/dist` statically).
- **Runtime:** `Dockerfile` is `FROM node:22-alpine`, `npm i`, builds
  `shared` + `server`, then builds `client` and `npm start` on port 8080.
- **Docs:** no root README upstream (fetch 404-class responses for
  `README`-style paths are not pursued; nothing to cite).
- **It is NOT a UCI engine.** It is a chess web app. Locked
  architecture decision (see §7): Stockfish (embedded UCI binary) does
  position EVAL; the WintrChess-derived Dart module
  (`lib/src/review/wintr_review.dart`) does GAME REVIEW consuming evals
  + game events.

## 2. Upstream layout discovery (VERIFIED)

- Shared code lives under a **`src/` infix**: `shared/src/<lib|types|
  constants>/…` with a `@/` tsconfig path alias. Bare `shared/…`
  paths 404; e.g. `shared/lib/reporter/report.ts` → 404 but
  `shared/src/lib/reporter/report.ts` → 200. (Prior "all shared/src/*
  guesses 404" failures were wrong subpaths, not a wrong infix —
  `shared/src/index.ts` genuinely does not exist: no barrel export.)
- Server code lives under `server/src/…` with the same `@/` alias:
  `routes/`, `database/`, `lib/`, `constants/`. Flat route files
  (`server/src/routes/api.ts`, `pages.ts`, `auth.ts`, `internal.ts`)
  404 — each is a directory with an `index.ts`.
- `server/src/routes/api/index.ts` mounts `public`, `account`, and the
  review-relevant `analysis/analyse` + `analysis/archive` routers.

## 3. Upstream review engine: `shared/src/lib/reporter/` (VERIFIED)

Upstream ships a genuine game-review pipeline. Entry point
`server/src/routes/api/analysis/analyse.ts`: `POST /analysis/analyse`
zod-validates a serialized state tree, calls
`getGameAnalysis(stateTree, {includeBrilliant, includeCritical,
includeTheory})` from `shared/lib/reporter/report` (import specifier;
real path `shared/src/lib/reporter/report.ts`), and returns the
analysis with the re-serialized tree.

| Exact upstream path (branch `master`) | Status | Summary (first ~60 lines viewed) |
|---|---|---|
| `shared/src/lib/reporter/report.ts` | HIT (1454 B, full) | `getGameAnalysis(rootNode, options)`: walks `getNodeChain`, per node `classify()` (guarded try/catch → `undefined`), `getOpeningName(fen)`, per-move `getMoveAccuracy(prevEval, curEval, colour)`; returns `{estimatedRatings: {white: 2000, black: 1000}, stateTree}`. **The ratings are a hardcoded placeholder.** |
| `shared/src/lib/reporter/expectedPoints.ts` | HIT (1168 B, full) | `getExpectedPoints(evaluation, {moveColour, centipawnGradient: 0.0035})`: mate → certainty convention; cp → `1/(1+exp(-0.0035·value))`. `getExpectedPointsLoss(prev, cur, moveColour)`: mover-signed difference clamped with `Math.max(0, …)`. **Ported** (`whiteExpectedScore`, `moverPointsLoss`, `expectedPointsGradient`). |
| `shared/src/lib/reporter/accuracy.ts` | HIT (1161 B, full) | `getMoveAccuracy = 103.16·exp(-4·pointLoss) − 3.17`; `getGameAccuracy` = per-side `meanBy` over nodes with accuracy. **Ported** (`moveAccuracy` + clamping deviation, `_sideAccuracy`). |
| `shared/src/lib/reporter/classify.ts` | HIT (2298 B, full) | `classify(node, options)`: throws without parent/missing data; forced (≤1 legal move) → theory (opening book) → checkmate→best → top-move→best else `pointLossClassify`; then critical/brilliant upgrades gated by query flags. **Reviewed, NOT ported** — needs live `chess.js` board + opening book; local `quality.dart` tiers are authoritative. Cut points recorded in §5. |
| `shared/src/lib/reporter/classification/pointLoss.ts` | HIT (3433 B, full) | Four-branch classifier (mate↔mate with mate-loss bands; mate→cp with 800/400/200/0 bands; cp→mate; cp→cp with point-loss cuts `0.01/0.045/0.08/0.12/0.22`). **Reviewed, NOT ported** — same reason as `classify.ts`. |
| `shared/src/lib/reporter/classification/brilliant.ts` | HIT (2320 B, full) | Sacrifice detector: critical-candidate gate, no promotions, unsafe-piece tracing (`getUnsafePieces`, `hasDangerLevels`, `isPieceTrapped`, `getAttackingMoves`) before/after. **Reviewed, NOT ported** — needs board internals. |
| `shared/src/lib/reporter/classification/critical.ts` | HIT (1582 B, full) | Only-move detector: critical-candidate gate, no mates-for-mover, no free captures (`isPieceSafe`), second-top-line point loss ≥ 0.1. **Reviewed, NOT ported** — needs engine multi-PV lines. |
| `shared/src/constants/Classification.ts` | HIT (1085 B, full) | Enum `brilliant/critical/best/excellent/okay/inaccuracy/mistake/blunder/theory/forced/risky` + numeric `classifValues` + PGN `$NAG` map (`brilliant→$3, mistake→$2, blunder→$4, inaccuracy→$6, risky→$5, critical→$1`). **Reference only.** |
| `shared/src/types/game/position/Evaluation.ts` | HIT (223 B, full) | zod `{type: "centipawn"\|"mate", value: number}`. Local `EvalResult.scoreCp` folds both into one White-relative int (mates anchored, see `engine_adapter.dart`). |
| `shared/src/types/game/GameAnalysis.ts` | HIT (526 B, full) | zod `{estimatedRatings?: {white, black}, stateTree}`. Ratings optional upstream; **this module reports no ratings** (placeholder not ported). |
| `shared/src/lib/reporter/types/AnalysisOptions.ts` | HIT (154 B, full) | `{includeBrilliant?, includeCritical?, includeTheory?}` — the analyse-route query flags. No equivalent options here (documented in `wintr_review.dart` header). |
| `shared/src/types/game/AnalysedGame.ts` | HIT (384 B, full) | `gameSchema.extend(gameAnalysisSchema.shape)`; `SerializedAnalysedGame = Game & SerializedGameAnalysis`. Archive schema, not review logic. |
| `shared/src/types/game/position/StateTreeNode.ts` | HIT (6516 B, ~60 lines) | zod recursive node (`id/mainline/state/children/parent`); `serializeNode` strips parents (cycle removal) + trims engine lines to 2 via `pickEngineLines`; `deserializeNode` restores parents/lines; `findNodeRecursively`. Transport shape, not portable. |
| `server/src/routes/api/analysis/archive.ts` | HIT (3183 B, full) | Archive CRUD (`GET /analysis/archive`, `POST …/add`, `POST …/delete`): zod-validated, `MAXIMUM_ARCHIVE_SIZE` default 50, gzip + compress-json storage via `@/lib/gameArchive`. Server persistence, not portable. |
| `server/src/lib/gameArchive.ts` | HIT (partial, imports) | `gzipSync/gunzipSync` + `compress-json` + `Buffer` + `omit`. Body not fully viewed (probe budget); treat as UNVERIFIED beyond the import list. |
| `server/src/lib/security/analysis.ts` | HIT (947 B, full) | Route guard: `Cookie` + `AnalysisSession` model check. Auth transport, not portable. |
| `server/src/index.ts` | HIT (1374 B, full) | Cluster-per-core boot, cookie parser, hostname whitelist, static client, `mainRouter`. Confirms web-app shape. |
| `server/src/routes/index.ts` | HIT (311 B, full) | Mounts `internalRouter, apiRouter, authRouter, pagesRouter`. |
| `server/src/routes/api/index.ts` | HIT (359 B, full) | Mounts `publicApiRouter, accountRouter, analyseRouter, archiveRouter` under `/api`. |
| `server/src/routes/pages/index.ts` | HIT (493 B, full) | `accountRouter, featuresRouter, footerRouter`. Not review-relevant. |
| `server/src/routes/auth/index.ts` | HIT (326 B, full) | `captcha, analysisSession, changeUsername` routers. Session model exists; not probed further. |
| `server/src/routes/internal/index.ts` | HIT (617 B, full) | Internal admin routers (login, announcements, news). Not review-relevant. |
| `server/src/constants/Collection.ts` | HIT (397 B, full) | Mongo collections incl. `analysisSessions`, `archivedGames`. Confirms review data is server-persisted. |
| `server/src/database/connect.ts` | HIT (984 B, full) | Mongoose connect + index init. Not review logic. |
| `server/src/lib/security/whitelist.ts` | HIT (613 B, full) | `wintrchess.com` hostname whitelist. Deploy detail. |
| `Dockerfile` | HIT (178 B, full) | `FROM node:22-alpine`, `npm i`, build shared+server, `EXPOSE 8080`, client build at container start. |
| `eslint.config.js` | HIT (1071 B, full) | `typescript-eslint` + stylistic plugin. Tooling only. |
| `LICENSE` | HIT (35149 B, header) | **GPLv3** (FSF header verified; byte size matches the canonical text; identical license already shipped at `assets/engines/LICENSE.GPLv3`). |
| `client/package.json` | HIT (partial) | Webpack + React + chess.js client. Build tooling only. |
| `package.json` / `shared/package.json` / `server/package.json` | HIT (full) | Workspaces; shared deps `chess.js`, `@mliebelt/pgn-parser`, `zod`, `better-auth`; server deps add `express`, `mongoose`, `nodemailer`, `altcha-lib`. |

Misses / blocked (do not retry without cause): root `tsconfig.json`,
`shared/src/index.ts`, flat `server/src/routes/{api,pages,auth,
internal}.ts`, `server/src/lib/auth.ts`, `server/src/routes/api/
{public.ts,analysis/index.ts}` (404 = absent); `shared/…` without the
`src/` infix (404); `server/src/routes/api/account.ts` and directory
listings (jsdelivr 403 "package size exceeded 50 MB" — repo too big for
flat listing, NOT evidence of absence); `LICENSE.md` (404 — license
lives at `LICENSE`); GitHub API via proxy rate-limited (avoided).

**Elo / rating / leaderboard search (best-effort, budget-capped):** no
dedicated `elo|rating|leaderboard` module was located. The only rating
signal found is the hardcoded `estimatedRatings: {white: 2000, black:
1000}` placeholder in `report.ts` — i.e. upstream has **no portable
rating logic to port**. Leaderboard/rating-route paths were not probed
(request budget redirected to the reporter core); treat their existence
as UNVERIFIED and out of scope for the review module.

**Deliberately unprobed (out of scope, listed so nobody re-pays the
budget):** reporter utils (`criticalMove`, `pieceSafety`,
`dangerLevels`, `pieceTrapped`, `attackers`, `extractNode`, `opening`),
`types/game/position/{BoardState,EngineLine}.ts`,
`constants/PieceColour.ts`, `lib/reporter/types/ExtractedNode.ts`,
`types/game/Game.ts`, full `gameArchive.ts` body, `auth/
analysisSession` route, anything under `client/`.

## 4. What was ported vs newly implemented

Ported (exact-path citations in `wintr_review.dart` header):

- `shared/src/lib/reporter/expectedPoints.ts` → `expectedPointsGradient`
  (0.0035), `whiteExpectedScore`, `moverPointsLoss` (mover negation =
  upstream's `flipPieceColour` handling; zero clamp kept).
- `shared/src/lib/reporter/accuracy.ts` → `moveAccuracy`
  (103.16/−4/−3.17, plus a 0..100 clamp deviation documented in code)
  and per-side accuracy means (`ReviewReport.whiteAccuracy/
  blackAccuracy`, upstream `getGameAccuracy` semantics).
- `shared/src/lib/reporter/report.ts` → the pipeline shape of
  `WintrReviewService.reviewGame` (ordered walk → classify vs previous
  eval → accuracy → one summary object).

Newly implemented from local contracts (no upstream equivalent):

- Tiering delegates to `quality.dart classify` (mover-relative `lossCp`
  thresholds, `superBrilliant`/`superBlunder` king-capture mechanics,
  `exposesOwnKing`, illegal-attempt notes) — upstream tiers
  (`Classification.ts`) and cut points (`pointLoss.ts`:
  0.01/0.045/0.08/0.12/0.22) are recorded here for calibration
  reference only and are NOT the verdict path.
- Top-3 swing key moments (`KeyMoment`: rank by |lossCp|, chronological
  output), `qualityCounts`, one-paragraph `summary`, `ReviewMoveInput`
  (FEN-before + FEN-after-or-variant-JSON + game events), `ReviewedMove`
  / `ReviewReport{toJson}` models.
- Upstream concepts explicitly dropped with reasons: brilliant/critical
  heuristics (need live board + multi-PV), theory/forced (need opening
  book + legal-move counts), `estimatedRatings` placeholder (fabricated
  ratings would be dishonest), mate-type eval branch (folded into
  `scoreCp` mate anchors), analyse-route query flags (server transport).

## 5. Reference: upstream tier cut points (NOT the verdict path)

For future calibration discussion only. Upstream cp→cp
(`pointLossClassify`): best < 0.01, excellent < 0.045, okay < 0.08,
inaccuracy < 0.12, mistake < 0.22, else blunder; mate-involved branches
use mate-loss / absolute-value bands (see §3 row). Local verdicts come
from `quality.dart` (§4).

## 6. License obligations (GPLv3 — VERIFIED via `LICENSE` header)

- WintrChess is **GPLv3**. The review port is a modified variant of
  GPLv3 logic (algorithm port, no upstream code vendored) and stays
  **GPLv3**: do not relicense, do not add proprietary restrictions.
- Checklist, kept in sync: (1) license text shipped at
  `assets/engines/LICENSE.GPLv3`; (2) attribution to
  `wintrcat/wintrchess` (branch `master`) in `wintr_review.dart`
  header + §3 table above; (3) source offer / source availability for
  the modified module (see `docs/ENGINE_RUNTIME.md`); (4) exact-path
  citations on every ported formula so derivation stays auditable.
- **Policy: do NOT bundle any WintrChess binary or source** — nothing
  upstream is vendored; the port is algorithms-only. (There is no UCI
  binary upstream to bundle in the first place — §7.)
- The sibling Stockfish binary keeps its own GPLv3 set in sync
  (`assets/engines/LICENSE.GPLv3`, `EngineAttributions.stockfish`,
  source-offer note) — owned by the engine-runtime agent, not this
  module.

## 7. WHY the review port lives in-Dart

Node/Express cannot run inside a Flutter standalone app: upstream
review (`getGameAnalysis`) executes server-side on Node with MongoDB
persistence (`archivedGames`, `analysisSessions`), a `chess.js` board,
and an HTTP session guard — none of which exist on-device, and none
of which can run on Flutter Web (`dart:io` processes unavailable).
Porting the portable math (expected-points model, accuracy formula,
pipeline shape) into dependency-free pure Dart gives offline,
cross-platform game review; the non-portable parts (board tracing,
opening book, multi-PV heuristics, persistence, HTTP) stay server-side
upstream and are re-solved locally via `quality.dart`, Stockfish evals,
and game events.

## 8. Locked architecture (do not relitigate)

- **Eval:** `StockfishEvaluator` (embedded UCI, standard FEN only) with
  `HeuristicEvaluator` fallback; `EvalResult` carries White-relative
  `scoreCp` + `source` (`heuristic|wintrchess|stockfish-uci`).
- **Review:** `WintrReviewService` (`wintr_review.dart`) consumes evals
  + game events → per-move `QualityAssessment`, top-3 `KeyMoment`s,
  `ReviewReport{toJson}`.
- `WintrChessAdapter` (`engine_adapter.dart`) is RESERVED for a future
  upstream UCI binary; there is none today. Review never touches it.

## 9. Upstream refresh procedure

See `docs/ENGINE_RUNTIME.md` ("Upstream refresh" section): probe via
`cdn.jsdelivr.net/gh/wintrcat/wintrchess@master/<path>` (200 = real,
~71–101 B 404 bodies = missing, 403 "package size exceeded" = repo
too big for listings, not absence). GitHub API via proxy is
rate-limited — avoid. `data.jsdelivr` flat listing 403s — do not use.

## 10. Open questions log (UNVERIFIED — do not build on)

- [ ] Leaderboard / rating-route existence (unprobed; out of scope).
- [ ] Reporter `utils/*` internals (out of scope unless brilliant/
  critical heuristics are ever re-targeted at a local board).
- [ ] `gameArchive.ts` body beyond imports (server persistence detail).
- [ ] `WintrChessAdapter` stays reserved until `wintrchess_notes.md`
  (this file) confirms a UCI-speaking upstream binary exists — no such
  evidence today.
