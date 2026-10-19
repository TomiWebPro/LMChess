# Stockfish binary — `linux-arm64/` (placeholder)

This directory holds the Stockfish `sf_19` binary for **Linux ARM64**.
Binaries (~100 MB each, ~680 MiB for all 7 platforms) are **not committed**;
fetch this one locally with:

```sh
dart run tool/download_stockfish.dart linux-arm64
```

- Expected file: `stockfish`
- Size: `100531200` bytes (100.5 MB)
- SHA-256: `bb6599ef38b7a4ae79200a601c40e81a854219a49dba78b1110e7eb4620609bf`
- Official asset: `https://github.com/official-stockfish/Stockfish/releases/download/sf_19/stockfish-linux-arm64-universal.tar.gz`
- Proxy (when `github.com` is blocked): `https://gh.llkk.cc/https://github.com/official-stockfish/Stockfish/releases/download/sf_19/stockfish-linux-arm64-universal.tar.gz`

The script extracts just the binary, checks it with `file` (ELF) plus a
`uci` → `uciok` handshake, runs `chmod +x`, and ensures
`assets/engines/LICENSE.GPLv3` exists. See `docs/ENGINE_RUNTIME.md`.
