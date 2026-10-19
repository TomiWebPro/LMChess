# Chaotic / Illegal-Move Variant

This document describes the variant engine in `lib/src/variant/`: the board
model, the interpretation pipeline, determinism guarantees, serialization, and
why FEN is deliberately **not** the canonical format.

## 1. Idea

In the chaotic variant, an attempted move is *never rejected*. When it is
legal under standard rules it applies normally; when it is illegal, the engine
produces a set of "creative readings" (teleport, capture-regardless, ripple,
conjuring, …), scores them with a heuristic, and picks one per the active
selection policy. Every step is logged into human-readable `events` so games
stay reviewable.

## 2. Board model (`variant_board.dart`)

`VariantBoard` maps `Square → VariantPiece`. Each piece has a **stable id**
(`VariantPiece.id`) that survives moves, shifts and promotion; only genuinely
new pieces (conjured/duplicated) get fresh ids.

### Invariants

| # | Invariant | Enforcement |
|---|-----------|-------------|
| 1 | At most one piece per square | Structural: the board *is* a `Map`; re-validated by `ChaoticRules` |
| 2 | Stable piece ids | `clone()` preserves ids; movers keep ids; new ids via deterministic `freshDerivedId` |
| 3 | 0..n kings allowed | No king-count checks anywhere on the board |
| 4 | Boards are effectively immutable | `squares` is unmodifiable; transforms build new boards |

King capture is **tracked externally**: `ChaoticRules.isKingCaptured` /
`gameOver` diff king presence before/after. The board never declares a winner.

Other fields: `sideToMove` (the mover), `moveNumber` (variant ply counter —
copied from the standard fullmove number on import, +1 per interpretation),
`halfmove` (best-effort clock), `castlingInvalid` (castling meaningless),
`notes` (annotation trail).

## 3. Pipeline (`chaotic_engine.dart` → `strategies.dart` → `selection.dart`)

```
AttemptedMove ──▶ tryStandardApply ── legal? ──yes──▶ single `standard` candidate
      │                                              (wasLegal: true)
      │ no
      ▼
InterpretationRegistry.generateAll (12 strategies, 0..3 candidates each)
      │ dedupe by layout hash, deterministic (strategyId, hash) order
      ▼
invariant validation (reject, never throw)
      ▼
VariantEvaluator.score (mover perspective) + king-capture diffing
      ▼
selectInterpretation(policy, seed) ──▶ InterpretedResult
```

### Legality check

`tryStandardApply` converts the board via `toStandardPosition()`. Boards that
are not exactly representable (wrong king counts, too many pieces/pawns) skip
standard rules entirely and go straight to interpretation. Id-preserving
rebuild keeps mover/rook ids and promotion identity.

### Strategies

| id | One-line reading |
|----|------------------|
| `directTeleport` | Teleport to the target, capturing enemies only |
| `captureRegardless` | Capture whatever is there, even own pieces/kings |
| `pushThroughBlocker` | Shove the first blocker aside, then complete the move |
| `moveBlockerInstead` | The blocker moves instead of the requested piece |
| `moveOpponentPiece` | Nearest enemy piece is marched to the target |
| `addPieceAtDestination` | Conjure a mover-coloured pawn on an empty target |
| `duplicateMover` | Original stays, a copy appears on the target |
| `removeBlocker` | Vaporize the blocker; advance (A) or hold (B) |
| `removeDestination` | Vaporize the target occupant from afar |
| `castleLikeDisplacement` | King and nearest rook shuffle castle-style |
| `closestLegalMove` | Nearest *legal* move; geometric fallback off-convertible |
| `multiPieceRipple` | Mover takes the target; occupant ripples to nearest empty |

Scope limits: pure functions, ≤3 candidates each, mislabeled output and
per-strategy crashes are contained by the registry (a crashing strategy
contributes nothing). See file docs for per-strategy preconditions.

### Selection (`selection.dart`)

- `bestStrategic` (default): king capture first, then highest score.
- `mostLiteral`: smallest `boardDiff` (changed squares) vs the parent.
- `mostChaotic`: largest `boardDiff`.
- `random`: seeded `Random(seed)` pick.
- `humanSelected`: UI-reserved; headless runs deterministically fall back to
  `bestStrategic`.

**Determinism contract:** same `(candidates, policy, moverColor, seed,
originalBoard)` ⇒ same output. Tie-breaks use `reproducibilityKey`
(`<strategyId>|<layout hash>`) ordering.

### Evaluator (`evaluator.dart`)

Hand-written heuristic: material (P100 N320 B330 R500 Q900 K20000), ±100000
for a missing king, pseudo-mobility, centralization, enemy-king threats.
**This is a fallback heuristic, not a chess engine. Never present its output
as Stockfish (or any engine) evaluation** — label it "heuristic" in the UI.

### Game over

Terminal when a side's king set is exhausted (zero kings left); the
surviving side wins, and both sides exhausted is a draw. Checked via
`ChaoticRules.gameOver`. On boards with several kings per side, capturing
one king is *scored* (credited during interpretation selection) but does not
end the game until that side has none left.

## 4. Serialization: custom JSON, not FEN

FEN assumes a legal-ish standard position: exactly one king per side, ≤8
pawns per side, no back-rank pawns, no piece identity, no annotations. Chaotic
boards routinely violate all of these. Canonical persistence is therefore
`VariantBoard.toJson()` / `fromJson()`, which round-trips ids, 0..n kings,
counters, flags and notes, and rejects duplicate squares/ids.

`canRepresentAsFen()` / `tryToFen()` are a best-effort bridge for convertible
positions only (export, debugging, standard legality checks). They return
`null` — never a misleading FEN — for anything else.

## 5. File map

| File | Contents |
|------|----------|
| `lib/src/chess/*` (chess track) | Shared primitives this engine builds on: `PieceType`, `PieceColor`, `Piece` (+ `ChessPiece` typedef), `Square`, `Position` (standard rules), `ChessMove`/`AppliedMove`. Owned by the chess-engine track; the variant only consumes their public API and degrades gracefully if standard legality ever throws (see robustness note in `chaotic_engine.dart`). |
| `lib/src/variant/variant_board.dart` | `VariantPiece`, `VariantBoard`, custom JSON, FEN bridge (rendered locally), `applyStandardMove`, plus variant-level parsing/geometry helpers (`tryParseSquare`, `parsePieceType`, `parsePieceColor`, `allSquares`, `squareNeighbors`, `chebyshevDistance`) that supplement the minimal shared `Square` API |
| `lib/src/variant/interpretation.dart` | `AttemptedMove`, `UnscoredInterpretation`, `CandidateInterpretation`, `InterpretedResult`, `Strategy` |
| `lib/src/variant/strategies.dart` | 12 strategies + `InterpretationRegistry` |
| `lib/src/variant/selection.dart` | `SelectionPolicy`, `boardDiff`, `selectInterpretation` |
| `lib/src/variant/evaluator.dart` | `VariantEvaluator` heuristic |
| `lib/src/variant/chaotic_engine.dart` | `ChaoticRules` facade, `StandardApplyResult`, `GameOverResult` |
