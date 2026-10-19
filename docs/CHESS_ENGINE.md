# Standard Chess Engine (`lib/src/chess`)

Pure-Dart standard-chess domain: no Flutter imports, null-safe, only
`collection`/`meta`-level dependencies (`package:meta` for `@immutable`).
Variant rules (chaotic chess, …) live in `lib/src/variant` and are
deliberately decoupled from this engine.

## Files

| File | Contents |
|---|---|
| `piece.dart` | `PieceType`, `PieceColor` (+`opposite`, coordinate helpers), immutable `Piece` with FEN char + unicode symbol |
| `square.dart` | Immutable `Square(file, rank)`, `fromName`/`fromIndex`, `offset`, `colorIsLight`, `Comparable` |
| `move.dart` | `ChessMove{from,to,promotion}` + UCI, `MoveFlag`, `AppliedMove` receipt (captured piece, check/mate/stale, SAN) |
| `position.dart` | Mutable `Position`, full move generation, `apply` |
| `fen.dart` | `parseFen` / `toFen` (all 6 fields) |
| `san.dart` | `toSan` / `parseSan` |
| `engine.dart` | `ChessRules` facade, `GameTermination`/`GameResult`, `perft` debugger |

## Representation

- **Coordinates:** 0-based, **a1 = (file 0, rank 0)**. White advances
  towards increasing rank. The `+1` for display ranks appears only at
  the FEN/SAN/ascii boundary.
- **Board:** `Map<Square, Piece>` holding only occupied squares — a
  clarity-first "mailbox". No bitboards. Cloning copies the map
  structure; `Piece`/`Square` instances are immutable and shared.
- **Castling rights:** `Set<String>` subset of `{'K','Q','k','q'}` (FEN
  meaning). Rights are only ever removed: king move forfeits both of
  its color; moving from, or capturing on, an original rook corner
  forfeits the matching right.
- **En passant:** `Square?` target behind a just-double-pushed pawn,
  cleared on any other move. Generation additionally verifies the
  pushed pawn stands beside the capturer, so hand-built positions with
  stale EP squares behave sanely.
- **Clocks:** `halfmoveClock` (reset on pawn move/capture, fifty-move
  trigger at ≥ 100), `fullmoveNumber` (incremented after Black's move).
- **`Position` is mutable** (`apply` mutates, returns `AppliedMove`);
  `clone()` before speculative play (search, perft, SAN probing).

## Move-generation algorithm

Two phases, per call to `legalMoves({forSquare})`:

1. **Pseudo-legal generation** per piece: pawn pushes (single/double),
   diagonal captures, en passant, all four promotions (quiet + capture);
   knight/king steps; bishop/rook/queen rays (blocked by first piece,
   enemy-king captures excluded as unreachable); castling with rights,
   king/rook presence, empty between-squares, and no-attack on the
   king's path squares (e/g/e–c incl. transit squares).
2. **King-safety filter:** each candidate is replayed on a copied board
   (incl. EP victim removal and rook relocation) and rejected if the
   mover's king is attacked afterwards. This one filter covers pins,
   discovered checks, king flights into attack, and the rare
   en-passant rank pin — no special cases.

**Attack detection** (`isSquareAttacked`) is geometric and independent
of move generation (pawn/knight/king offsets + ray walks), so it stays
valid on simulated boards. Complexity is O(pieces × rays) — plenty for
game play, LLM move validation, and perft ≤ 4–5.

## FEN coverage

`parseFen` requires all six fields and is strict (throws
`FormatException`): 8 ranks summing to 8 files, `w`/`b`, castling subset
of `KQkq` without repeats (`-` = none), EP `-` or a square on rank 3/6,
clocks with halfmove ≥ 0 and fullmove ≥ 1. `toFen` emits canonical
`KQkq` order and round-trips canonical input. History is not part of
FEN — parsed positions start with empty history.

## SAN coverage

Single generator (in `position.dart`, via `apply`); `san.dart::toSan`
delegates through clone+apply. Output: `O-O`/`O-O-O`, piece letters,
file/rank/full disambiguation per the standard rule, `x` captures,
destination squares, `=Q` promotions, `+`/`#` suffixes; en passant
looks like an ordinary pawn capture (no `e.p.` marker). `parseSan`
matches generated SANs of all legal moves (by construction complete),
and additionally accepts `0-0` zeros, `!`/`?`/`+`/`#` suffixes,
move-number prefixes, `=`-less promotions (`e8Q`), and long algebraic
(`e2e4`, `e7e8q`). Throws `FormatException`/`StateError` otherwise.

## Validation

`perft(Position, depth)` counts legal leaf nodes; verify against:

- Startpos: depth 1–4 → **20 / 400 / 8902 / 197281**
- Kiwipete
  (`r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1`):
  depth 1–3 → **48 / 2039 / 97862**

## What is NOT supported

- **No Chess960.** Castling assumes standard king/rook home squares.
- **Repetition is keyed, not counted.** `Position.repetitionKey` exposes the
  board + side to move + castling rights + en-passant square so a game
  controller can count threefold/fivefold; the engine itself does not store
  repetition history. There is no 50-move *claim* flow — controllers own
  draw claims. `ChessRules.resultOf` reports only the automatic triggers:
  checkmate, stalemate, fifty-move at 100 halfmoves (claimable in FIDE
  terms), seventy-five-move at 150 halfmoves (automatic), and insufficient
  material.
- **No partial legality shortcuts:** `apply` throws `StateError` on
  illegal moves rather than coercing; callers must check `isLegal` or
  handle the error (important for LLM-generated moves).
- Insufficient material covers K-vs-K, K+minor-vs-K, and KB-vs-KB on
  same-colored bishops. KNN-vs-K and similar (mate possible, not
  forceable) are *not* auto-draws here.

## Cross-module compatibility (UI + variant controller)

`lib/src/ui` (board widget) and `lib/src/variant` (chaotic controller)
import this package directly, so parts of the API are shared contracts:

- `piece.dart`: `PieceTypeX` (name + nullable `fromLetter`), `Piece.code`
  (`'wK'` cell encoding), `PieceColor.code` (`'w'`/`'b'`, round-trips
  with `tryParse`), `PieceColor.opponent`, `PieceType.symbol`,
  `ChessPiece` (= `Piece`), `kFiles`/`kRanks`/`squareName`/`parseSquare`.
- `square.dart`: `Square.tryParse` (nullable, for user/LLM input).
- `position.dart`: `pieces` view, `whiteKingside/...` getters,
  `isLegalMove` / `applyMoveResult` / `PositionApplyResult` (rook transit
  for id-preserving conversion and castling animation), constructor
  aliases (`pieces:`, four castling booleans).
- `fen.dart`: `position.toFen()` extension alongside top-level `toFen`.

Enum value order follows the engine spec (pawn first) — consumers match
on names, never `.index`. Do not rename these members without updating
the callers; `dart analyze lib` covers all three directories.
