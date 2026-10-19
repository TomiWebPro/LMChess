# Stockfish binary — `linux-x86-64/` (placeholder)

This directory holds the Stockfish `sf_19` binary for **Linux x86-64**.
Binaries (~100 MB each, ~680 MiB for all 7 platforms) are **not committed**;
fetch this one locally with:

```sh
dart run tool/download_stockfish.dart linux-x86-64
```

- Expected file: `stockfish`
- Size: `103153472` bytes (103.2 MB)
- SHA-256: `0f83d24cc46d2c66c60f16001af5444873bc112b7d028594513426894c12da19`
- Official asset: `https://github.com/official-stockfish/Stockfish/releases/download/sf_19/stockfish-linux-x86-64-universal.tar.gz`
- Proxy (when `github.com` is blocked): `https://gh.llkk.cc/https://github.com/official-stockfish/Stockfish/releases/download/sf_19/stockfish-linux-x86-64-universal.tar.gz`

The script extracts just the binary, checks it with `file` (ELF) plus a
`uci` → `uciok` handshake, runs `chmod +x`, and ensures
`assets/engines/LICENSE.GPLv3` exists. See `docs/ENGINE_RUNTIME.md`.
