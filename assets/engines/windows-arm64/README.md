# Stockfish binary — `windows-arm64/` (placeholder)

This directory holds the Stockfish `sf_19` binary for **Windows ARM64**.
Binaries (~100 MB each, ~680 MiB for all 7 platforms) are **not committed**;
fetch this one locally with:

```sh
dart run tool/download_stockfish.dart windows-arm64
```

- Expected file: `stockfish.exe`
- Size: `100303360` bytes (100.3 MB)
- SHA-256: `3b5881df3d6f92817cf6664a6a18a473b50d424c71a1247fe4268090db281413`
- Official asset: `https://github.com/official-stockfish/Stockfish/releases/download/sf_19/stockfish-windows-arm64-universal.zip`
- Proxy (when `github.com` is blocked): `https://gh.llkk.cc/https://github.com/official-stockfish/Stockfish/releases/download/sf_19/stockfish-windows-arm64-universal.zip`

The script extracts just the binary, checks it with `file` (PE32+) plus a
`uci` → `uciok` handshake, and ensures `assets/engines/LICENSE.GPLv3`
exists. See `docs/ENGINE_RUNTIME.md`.
