# Stockfish binary — `windows-x86-64/` (placeholder)

This directory holds the Stockfish `sf_19` binary for **Windows x86-64**.
Binaries (~100 MB each, ~680 MiB for all 7 platforms) are **not committed**;
fetch this one locally with:

```sh
dart run tool/download_stockfish.dart windows-x86-64
```

- Expected file: `stockfish.exe`
- Size: `103046300` bytes (103.0 MB)
- SHA-256: `45bc8e4969147db9c2eb533810637994619bff0eacc81ccfd9854394901bcbd0`
- Official asset: `https://github.com/official-stockfish/Stockfish/releases/download/sf_19/stockfish-windows-x86-64-universal.zip`
- Proxy (when `github.com` is blocked): `https://gh.llkk.cc/https://github.com/official-stockfish/Stockfish/releases/download/sf_19/stockfish-windows-x86-64-universal.zip`

The script extracts just the binary, checks it with `file` (PE32+) plus a
`uci` → `uciok` handshake, and ensures `assets/engines/LICENSE.GPLv3`
exists. See `docs/ENGINE_RUNTIME.md`.
