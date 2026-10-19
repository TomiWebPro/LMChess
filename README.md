# LLM Chess Arena

Flutter standalone (offline-first) platform where humans and LLM agents play
**standard** and **chaotic (illegal-move)** chess with full observability:
streaming commentary, tool calls, validation, fallback accounting, arena
tournaments, statistics, and post-game review.

See `ARCHITECTURE.md` for decisions, `docs/` for run/test guides.

## Run (Linux desktop; same for macOS/Windows/Android/iOS/Web)

```bash
cd llm_chess_arena
flutter pub get
dart run tool/download_stockfish.dart linux-x86-64   # embedded engine (first time only)
flutter analyze
flutter test                     # boot + e2e smoke tests
flutter run -d linux             # or: windows / macos
flutter build linux --release    # standalone artifact
```

> **Web (`chrome`) and iOS** run without the embedded engine — Stockfish
> cannot execute there, so game review falls back to the heuristic estimator
> (heuristic-only; see `docs/ENGINE_RUNTIME.md`). Keep the run/test commands
> above in sync with `docs/RUNBOOK.md`.

No API keys needed: `MockProvider` plays scripted demo games. Add OpenAI /
Anthropic / Gemini / Ollama keys in **Agents** screen (stored in secure storage,
never exported).

## Getting the Stockfish engine

The engine binaries are **not committed** to this repository (~100 MB each,
~680 MiB for all 7 platforms — see `docs/ENGINE_RUNTIME.md` for the
bundling rationale). Every platform has a per-directory `README.md` with the
exact expected size and SHA-256 for that binary.

**Easiest path — let the bundled fetcher do it** (verifies size, SHA-256 and
a `uci` → `uciok` handshake, then `chmod +x`):

```bash
dart run tool/download_stockfish.dart linux-x86-64   # one platform
dart run tool/download_stockfish.dart --all           # every platform
dart run tool/download_stockfish.dart --list          # show URLs + status
```

**Manual download** — grab the release archive for your platform from the
official Stockfish releases and extract the binary into
`assets/engines/<platform>/`:

| Platform | Directory | Official release asset |
|---|---|---|
| Linux x86-64 | `linux-x86-64/` | [`stockfish-linux-x86-64-universal.tar.gz`](https://github.com/official-stockfish/Stockfish/releases/download/sf_19/stockfish-linux-x86-64-universal.tar.gz) |
| Linux ARM64 | `linux-arm64/` | [`stockfish-linux-arm64-universal.tar.gz`](https://github.com/official-stockfish/Stockfish/releases/download/sf_19/stockfish-linux-arm64-universal.tar.gz) |
| macOS (Intel + Apple Silicon) | `macos-universal/` | [`stockfish-macos-universal.tar.gz`](https://github.com/official-stockfish/Stockfish/releases/download/sf_19/stockfish-macos-universal.tar.gz) |
| Windows x86-64 | `windows-x86-64/` | [`stockfish-windows-x86-64-universal.zip`](https://github.com/official-stockfish/Stockfish/releases/download/sf_19/stockfish-windows-x86-64-universal.zip) |
| Windows ARM64 | `windows-arm64/` | [`stockfish-windows-arm64-universal.zip`](https://github.com/official-stockfish/Stockfish/releases/download/sf_19/stockfish-windows-arm64-universal.zip) |
| Android ARM64 | `android-arm64/` | [`stockfish-android-arm64-universal.tar.gz`](https://github.com/official-stockfish/Stockfish/releases/download/sf_19/stockfish-android-arm64-universal.tar.gz) |
| Android ARMv7 (NEON) | `android-armv7/` | [`stockfish-android-armv7-neon.tar.gz`](https://github.com/official-stockfish/Stockfish/releases/download/sf_19/stockfish-android-armv7-neon.tar.gz) |

Release tag: [`sf_19`](https://github.com/official-stockfish/Stockfish/releases/tag/sf_19)
· Upstream project: <https://github.com/official-stockfish/Stockfish> (GPLv3)

If `github.com` is blocked, prefix the URL with the proxy
`https://gh.llkk.cc/` (the fetch tool does this automatically) — e.g.
`https://gh.llkk.cc/https://github.com/official-stockfish/Stockfish/releases/download/sf_19/stockfish-linux-x86-64-universal.tar.gz`.

After extracting, the file must be named `stockfish` (or `stockfish.exe` on
Windows) and live directly in `assets/engines/<platform>/`. The app
verifies its pinned size + SHA-256 before running it, so a partial or
modified download is rejected rather than executed.

Without the binary the app still works: game review falls back to the
built-in heuristic estimator (scores are always labeled `heuristic` vs
`stockfish-uci`).

## Embedded Stockfish + review

- Stockfish `sf_19` ships as a per-platform binary asset
  (`assets/engines/<platform>/stockfish[.exe]`), extracted on first run;
  see `docs/ENGINE_RUNTIME.md`. Binaries are gitignored (~100 MB each) —
  fetch with `dart run tool/download_stockfish.dart <platform>`.
- Game review uses the WintrChess-derived module
  (`lib/src/review/wintr_review.dart`, GPLv3 — see
  `lib/src/review/wintrchess_notes.md`); Stockfish performs position
  evaluation, heuristic fallback everywhere else, and every score is
  labeled with its source.

## Layout

- `lib/src/chess|variant|llm|agent|game|arena|stats|review|storage|theme|ui`
- `backend/openapi.yaml` — future-server contracts (mirrors local store)
- `docs/CHESS_ENGINE.md docs/VARIANT.md docs/ENGINE_RUNTIME.md docs/RUNBOOK.md`

## License

LLM Chess Arena is distributed under the **GNU General Public License,
version 3 or later (GPL-3.0-or-later)** — the full text is in the root
[`LICENSE`](LICENSE) file — **as modified by the Geographic Use Restriction
Addendum v1.0 (GURAv1)**, whose text is in the root
[`Geographic Use Restriction Addendum v1.0`](Geographic%20Use%20Restriction%20Addendum%20v1.0)
file and which takes precedence over the base license in the event of
conflict.

The addendum is a statement of non-compliance with government-mandated
OS-level age verification (see
[TomiWebPro/Geographic-Use-Restriction-Addendum](https://github.com/TomiWebPro/Geographic-Use-Restriction-Addendum)).
It revokes the base license's permissions — for everyone — in **Brazil**,
**California**, **Texas**, **Utah**, **Louisiana**, **Colorado**,
**Illinois**, and **New York** (USA), and for anyone holding citizenship,
residency, or a residential permit in those jurisdictions. Because it
discriminates by geography, this distribution is **not** OSI-approved open
source; outside the restricted jurisdictions the GPLv3 terms continue to
apply in full.

This project links and derives from GPLv3 code, so the whole distribution
stays under GPLv3:

- **Stockfish** (`sf_19`) — the embedded evaluation engine
  (`assets/engines/<platform>/stockfish[.exe]`) — is
  [GPLv3](https://github.com/official-stockfish/Stockfish/blob/master/Copying.txt)
  by the Stockfish developers:
  <https://github.com/official-stockfish/Stockfish>. The license text also
  ships at `assets/engines/LICENSE.GPLv3`, and attribution strings live in
  `EngineAttributions` (`lib/src/review/embedded_engine.dart`).
- **WintrChess-derived review module**
  (`lib/src/review/wintr_review.dart`) is derived from
  [wintrcat/wintrchess](https://github.com/wintrcat/wintrchess) (GPLv3); the
  derivation statement is in the file header and the attribution ledger is
  in `lib/src/review/wintrchess_notes.md`.

### Acknowledgements

- **Stockfish** — the chess engine that evaluates every position.
  <https://github.com/official-stockfish/Stockfish> (GPLv3). The engine
  binaries are not committed here; each platform's `assets/engines/<platform>/README.md`
  records the exact expected size and SHA-256, and the upstream release
  links are in the [engine download section](#getting-the-stockfish-engine)
  above.
- **WintrChess** — <https://github.com/wintrcat/wintrchess> (GPLv3), by the
  WintrChess authors. The game-review pipeline in
  `lib/src/review/wintr_review.dart` is a **derived work**: it ports the
  review math from WintrChess' `shared/src/lib/reporter/` — the
  expected-points model, the per-move accuracy formula, and the analysis
  pipeline shape. Thanks to the WintrChess team for the review design that
  made the in-app reviewer possible. The full ported-vs-new ledger, with
  exact upstream paths and the reasons for every deliberate omission, is in
  `lib/src/review/wintrchess_notes.md`; the derivation statement itself is
  in the `wintr_review.dart` file header.
- **The Geographic Use Restriction Addendum** — by
  [TomiWebPro](https://github.com/TomiWebPro/Geographic-Use-Restriction-Addendum)
  (MIT).

Before distributing binaries, fulfil the GPLv3 Corresponding Source and
Installation Information obligations — see the release checklist in
`docs/ENGINE_RUNTIME.md`.
