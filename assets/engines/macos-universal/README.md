# Stockfish binary — `macos-universal/` (placeholder)

This directory holds the Stockfish `sf_19` binary for **macOS universal
(Intel + Apple Silicon)**.
Binaries (~100 MB each, ~680 MiB for all 7 platforms) are **not committed**;
fetch this one locally with:

```sh
dart run tool/download_stockfish.dart macos-universal
```

- Expected file: `stockfish`
- Size: `105458632` bytes (105.5 MB)
- SHA-256: `8eed61129d1493c5d1f2fd9323f0c54c47ac49319911fbde18c6b9c87e8b13c5`
- Official asset: `https://github.com/official-stockfish/Stockfish/releases/download/sf_19/stockfish-macos-universal.tar.gz`
- Proxy (when `github.com` is blocked): `https://gh.llkk.cc/https://github.com/official-stockfish/Stockfish/releases/download/sf_19/stockfish-macos-universal.tar.gz`

The script extracts just the binary, checks it with `file` (Mach-O
universal) plus a `uci` → `uciok` handshake, runs `chmod +x`, and ensures
`assets/engines/LICENSE.GPLv3` exists. See `docs/ENGINE_RUNTIME.md`.
