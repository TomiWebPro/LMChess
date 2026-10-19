# Stockfish binary — `android-armv7/` (placeholder)

This directory holds the Stockfish `sf_19` binary for **Android ARMv7
(NEON)**.
Binaries (~100 MB each, ~680 MiB for all 7 platforms) are **not committed**;
fetch this one locally with:

```sh
dart run tool/download_stockfish.dart android-armv7
```

- Expected file: `stockfish`
- Size: `99697096` bytes (100.0 MB)
- SHA-256: `993a3e8bce85a503abc900056019691057a83e13ae92c1a2cbb089b9680593f3`
- Official asset: `https://github.com/official-stockfish/Stockfish/releases/download/sf_19/stockfish-android-armv7-neon.tar.gz`
- Proxy (when `github.com` is blocked): `https://gh.llkk.cc/https://github.com/official-stockfish/Stockfish/releases/download/sf_19/stockfish-android-armv7-neon.tar.gz`

The script extracts just the binary, checks it with `file` (ELF, Android)
plus a `uci` → `uciok` handshake, runs `chmod +x`, and ensures
`assets/engines/LICENSE.GPLv3` exists. See `docs/ENGINE_RUNTIME.md`.
