# Stockfish binary — `android-arm64/` (placeholder)

This directory holds the Stockfish `sf_19` binary for **Android ARM64**.
Binaries (~100 MB each, ~680 MiB for all 7 platforms) are **not committed**;
fetch this one locally with:

```sh
dart run tool/download_stockfish.dart android-arm64
```

- Expected file: `stockfish`
- Size: `100695968` bytes (100.7 MB)
- SHA-256: `ffd8fc2004d3d19f9fdab95d84c92709aea92e8d3af405eda0b281b23cf1daf8`
- Official asset: `https://github.com/official-stockfish/Stockfish/releases/download/sf_19/stockfish-android-arm64-universal.tar.gz`
- Proxy (when `github.com` is blocked): `https://gh.llkk.cc/https://github.com/official-stockfish/Stockfish/releases/download/sf_19/stockfish-android-arm64-universal.tar.gz`

The script extracts just the binary, checks it with `file` (ELF, Android)
plus a `uci` → `uciok` handshake, runs `chmod +x`, and ensures
`assets/engines/LICENSE.GPLv3` exists. See `docs/ENGINE_RUNTIME.md`.
