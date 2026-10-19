# Engine Runtime — Stockfish binary embedding

How the embedded Stockfish binaries ship, extract at first run, and refresh.
Code reference: `lib/src/review/embedded_engine.dart`
(`EmbeddedEngine`, `EngineAttributions`);
fetcher: `tool/download_stockfish.dart`.

## Packaging strategy (chosen)

- **Binaries are gitignored, not committed.** The 7 `sf_19` binaries total
  ~680 MiB (~96–106 MB each) — too large for git or a blind app bundle.
  Developers keep them locally (`dart run` fetches them); only per-dir
  `README.md` placeholders (exact filename + size + SHA-256 + official URL)
  and `assets/engines/LICENSE.GPLv3` are committed.
- **Keep `linux-x86-64` present locally for dev.** It is handshake-verified
  (`id name Stockfish 19`; `uci` → `uciok`).
- **Fetch, don't re-download.** `tool/download_stockfish.dart` reuses cached
  release archives (`/home/tomi/.ss-tmp/sf/`, `STOCKFISH_ARCHIVE_DIR`), tries
  `github.com` then the `gh.llkk.cc` proxy prefix, extracts just the binary,
  and verifies with `file` + exact size + SHA-256 + UCI handshake.
- **Resolver contract** (`lib/src/review/embedded_engine.dart`, read-only
  reference): asset layout
  `assets/engines/<linux-x86-64|linux-arm64|macos-universal|windows-x86-64|windows-arm64|android-arm64|android-armv7>/stockfish[.exe]`,
  first-run copy to the app-support dir + `chmod +x`, `PATH` fallback to
  `stockfish`, honest unsupported error on web/iOS (heuristic fallback).

## Status (`sf_19`, verified 2026-10-16)

| Platform dir      | Binary         | Size (bytes) | SHA-256 (prefix) | Local |
|-------------------|----------------|-------------:|------------------|-------|
| `linux-x86-64`    | `stockfish`    | 103153472    | `0f83d24c…`      | present, handshake OK |
| `linux-arm64`     | `stockfish`    | 100531200    | `bb6599ef…`      | present (foreign arch) |
| `macos-universal` | `stockfish`    | 105458632    | `8eed6112…`      | present (foreign arch) |
| `windows-x86-64`  | `stockfish.exe`| 103046300    | `45bc8e49…`      | present (un-runnable here) |
| `windows-arm64`   | `stockfish.exe`| 100303360    | `3b5881df…`      | present (un-runnable here) |
| `android-arm64`   | `stockfish`    | 100695968    | `ffd8fc20…`      | present (foreign arch) |
| `android-armv7`   | `stockfish`    | 99697096     | `993a3e8b…`      | present (foreign arch) |

Full hashes live in the per-dir `README.md` files and
`tool/download_stockfish.dart`. `file` fingerprints: Linux ELF x86-64/arm64,
macOS Mach-O universal (x86_64 + arm64), Windows PE32+ (x64/ARM64), Android
ELF aarch64/armv7 (NDK r27c, API 29). Official assets:
`https://github.com/official-stockfish/Stockfish/releases/download/sf_19/<asset>`
(asset names: `stockfish-linux-x86-64-universal.tar.gz`,
`stockfish-linux-arm64-universal.tar.gz`, `stockfish-macos-universal.tar.gz`,
`stockfish-windows-x86-64-universal.zip`,
`stockfish-windows-arm64-universal.zip`,
`stockfish-android-arm64-universal.tar.gz`,
`stockfish-android-armv7-neon.tar.gz`);
proxy prefix when `github.com:443` is blocked:
`https://gh.llkk.cc/https://github.com/official-stockfish/Stockfish/releases/download/sf_19/<asset>`.

## Per-OS embedding behavior

- **Linux (x86-64 / arm64):** asset copied to
  `<app-support>/engines/stockfish`, `chmod +x`, spawned directly.
  Self-contained beyond system libc. Dev fallback: `which stockfish`.
- **macOS (universal):** one `Mach-O universal` binary covers Intel + Apple
  Silicon; same copy + `chmod +x` flow.
- **Windows (x86-64 / arm64):** `stockfish.exe` copied, no `chmod` needed;
  spawn via `Process.start`. See AV note below.
- **Android (arm64 / armv7-NEON):** asset extracted to app-support and
  `chmod +x`'d; `android:extractNativeLibs`-style exec restrictions do not
  apply since the binary runs from the app's private files dir, not the APK
  lib dir. armv7 uses the `-neon` build.
- **iOS:** Apple forbids executing bundled binaries from the sandbox —
  `resolveBinary` throws `UnsupportedError`; callers use the heuristic
  estimator.
- **Web:** no `dart:io` processes — same honest fallback as iOS.

## First-run paths

1. `EmbeddedEngine.bundledAssetPath()` picks
   `assets/engines/<dir>/stockfish[.exe]` for the OS/arch.
2. `rootBundle` copy → `<app-support>/engines/stockfish[.exe]`
   (`path_provider`), re-copy when byte length differs (upgrade check).
3. `chmod +x` on non-Windows; missing asset → `PATH` lookup (`stockfish`);
   neither → human-readable `StateError` pointing here.

## Bundle size warning

Each binary is ~96–106 MB; shipping all 7 adds ~680 MiB to the app.
Prefer per-target bundling (only the binary matching the build target) over
`assets/engines/` wholesale. Store limits (notably Google Play ~150 MB base /
expansion-file rules and Apple cellular-download thresholds) make the full
set unshippable as one artifact — split per ABI or offer the engine as an
optional download instead.

**Pubspec detail:** a bare `assets/engines/` entry bundles only the files
directly in that directory, so every platform subdirectory that should
ship must be listed explicitly (`assets/engines/<platform>/`); otherwise
the runtime resolver finds no `assets/engines/<platform>/stockfish` in
`flutter_assets` and silently degrades to heuristic evaluation. For
release builds, delete the entries (and directories) for platforms you do
not ship. This is exactly how the per-target trimming is done today.

## Refresh procedure (new Stockfish release)

1. `dart run tool/refresh_stockfish.dart <sf_TAG>` (prints URLs) or pass
   `--tag=<sf_TAG>` / `STOCKFISH_TAG` to `tool/download_stockfish.dart`.
2. `dart run tool/download_stockfish.dart --redownload --all` (or per dir);
   each binary is size + SHA-256 + `file` + handshake verified.
3. Update expected size/hash constants in `tool/download_stockfish.dart`,
   the per-dir `README.md` files, and this doc's table.
4. Sync the GPLv3 set: `assets/engines/LICENSE.GPLv3` (from the archive's
   `Copying.txt`), `EngineAttributions.stockfish`
   (`lib/src/review/embedded_engine.dart`), and the checklist below.
5. Re-run `flutter pub get` + `dart analyze tool`; handshake-test at least
   the host binary (`printf 'uci\nquit\n' | ./stockfish` → `uciok`).

## Troubleshooting

- **Windows AV false positives:** unsigned chess-engine binaries are
  occasionally flagged. Sign the binary/build, submit to the vendor's
  false-positive portal, and document the expected SHA-256 (per-dir README)
  so users can verify.
- **macOS quarantine:** ad-hoc downloads get `com.apple.quarantine`;
  clear with `xattr -d com.apple.quarantine <binary>` (store builds signed
  + notarized are unaffected).
- **Android exec failures:** ensure the copy lives under app-private files
  with `chmod +x` applied at runtime; `file` must show an Android
  (not GNU/Linux) ELF matching the device ABI.
- **iOS / Web:** no embedded execution — the heuristic estimator is the
  intended path, not a bug.
- **Handshake timeout on desktop:** check `chmod +x`, missing system libc
  (`ldd stockfish`), or an aggressive AV sandbox; `PATH` fallback
  (`stockfish`) covers dev machines.

## GPLv3 checklist (Stockfish `sf_19`)

- [x] `assets/engines/LICENSE.GPLv3` ships (copied from `Copying.txt`); the
      full text is also now in the repository-root `LICENSE` file.
- [x] The root `LICENSE` is the GPLv3 base license **plus the full text of
      the Geographic Use Restriction Addendum v1.0 (GURAv1)** appended
      after it. The addendum applies *in addition to* the base license and
      takes precedence on conflict. There is no separate addendum file —
      everything license-related lives in `LICENSE`.
- [x] `EngineAttributions.stockfish` string shown on the settings/about
      screen (name + version + URL + license + source pointer). The string
      lives in `lib/src/review/embedded_engine.dart` and is rendered
      verbatim in the **License & attributions** section of the settings
      screen (`lib/src/ui/screens/settings_screen.dart`), together with the
      GURAv1 geographic-use restriction and the WintrChess credit.
- [ ] Source offer: this doc points at
      `https://github.com/official-stockfish/Stockfish` (tag `sf_19`);
      keep a copy of the corresponding source/archives with releases.

### Release checklist (before distributing binaries)

The license/attribution material is in place, but shipping binaries triggers
the GPLv3 **Corresponding Source** and **Installation Information**
obligations. Before cutting a release:

- Publish or archive the exact Corresponding Source for the shipped build
  (this repository's Dart source plus any modified Stockfish), and reference
  it from the app's about/attribution screen.
- Provide Installation Information sufficient to install a modified version
  on the same device (relevant for locked-down targets such as Android/iOS,
  where the engine runs from the app sandbox).
- Verify the `EngineAttributions.stockfish` string is actually rendered on
  the settings/about screen (it is — see the checklist above).
- Ship the GURAv1 addendum text alongside the GPLv3 base license so every
  recipient sees the geographic restriction it is under. Both texts are
  already in the root `LICENSE` file; keep them together in every
  distribution of this software.

## WintrChess-derived review module

Role split (locked architecture decision): **Stockfish does position
evaluation; the WintrChess-derived Dart module does game review.**
Upstream `wintrcat/wintrchess` is a TypeScript web app (Express +
MongoDB + chess.js server, React client), **not a UCI engine**, and a
Node server cannot run inside the Flutter standalone. The port keeps the
genuinely portable review math and re-implements the rest on local
contracts; see `lib/src/review/wintrchess_notes.md` for the exact
upstream paths, the ported-vs-new ledger, and what was deliberately not
ported.

- Code: `lib/src/review/wintr_review.dart` (`WintrReviewService`) —
  consumes per-move inputs (FENs, mover, illegal-attempt/king-capture
  flags, phrase/commentary) plus any [PositionEvaluator] and produces
  per-move `QualityAssessment`s, key moments, and a `ReviewReport`.
- Evaluation source policy: heuristic by default (always available);
  embedded Stockfish when the platform supports it. The `source` field
  (`'heuristic'` | `'stockfish-uci'` | `'wintrchess'`) must be rendered
  next to every score — never present heuristic numbers as engine
  analysis.
- Refresh procedure (upstream reference): fetch paths via
  `https://cdn.jsdelivr.net/gh/wintrcat/wintrchess@master/<path>`
  (`github.com` may be blocked); review-relevant code lives under
  `shared/src/lib/reporter/`, `shared/src/lib/classification/`, and
  `shared/src/constants/Classification.ts`.

### License checklist (WintrChess port — GPLv3)

- [x] Upstream is GPLv3: the derived Dart module ships under GPLv3 with
      attribution in `lib/src/review/wintr_review.dart`'s header, and the
      WintrChess authors are credited by name in the README
      *Acknowledgements* section.
- [x] `assets/engines/LICENSE.GPLv3` (and the repository-root `LICENSE`)
      covers both Stockfish and the WintrChess-derived module (same license
      family).
- [x] The GURAv1 addendum is appended in full to the root `LICENSE` file,
      after the GPLv3 base license.
- [ ] Source offer: this repository's own source (including the derived
      module) is the corresponding source for the app build.
- [ ] Keep `wintrchess_notes.md` citations current when refreshing.
