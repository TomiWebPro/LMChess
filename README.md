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
version 3 or later (GPL-3.0-or-later)**; the full text is in the root
[`LICENSE`](LICENSE) file. This project links or derives from GPLv3 code,
so the whole distribution is GPLv3:

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

Before distributing binaries, fulfil the GPLv3 Corresponding Source and
Installation Information obligations — see the release checklist in
`docs/ENGINE_RUNTIME.md`.
