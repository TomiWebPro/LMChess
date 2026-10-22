# Runbook

## Prereqs

- Flutter 3.47+ / Dart 3.13+ (`flutter doctor`)
- Linux desktop needs `clang cmake ninja-build pkg-config libgtk-3-dev`
  plus, for the secure-storage plugin: `libsecret-1-dev libjsoncpp-dev`
  (`sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev
  libsecret-1-dev libjsoncpp-dev`).
- Headless machines: run under `Xvfb` **with a window manager**:
  `Xvfb :91 -screen 0 1600x1000x24 & DISPLAY=:91 openbox & DISPLAY=:91
  LIBGL_ALWAYS_SOFTWARE=1 ./build/linux/x64/release/bundle/llm_chess_arena`.
  Without a WM the GTK/GL surface can stall on a 1280x721-vs-1280x720
  frame-size mismatch (window stays black).

## Commands

```bash
flutter pub get
dart run tool/download_stockfish.dart linux-x86-64   # embedded engine (first time only)
flutter analyze
flutter test                     # boot + e2e smoke tests
flutter run -d linux             # or: windows / macos
flutter build linux --release    # standalone artifact
```

## Demo without keys

1. Open **Agents** → two mock agents exist by default.
2. **Watch** → White=Demo White, Black=Demo Black → Start (a full legal
   game plays, with fallback attribution + stats recorded).
3. **Arena** → pick agents, games, concurrency → run → inspect grid + stats.
4. **Review** any finished game; eval source labels are always shown
   (`stockfish-uci` vs `heuristic`).

## Adding a real model

Agents → New → provider (OpenAI/Anthropic/Gemini/Ollama-compatible) → model,
endpoint, key (secure storage) → **Test connection** → Save.

## Flutter upgrade gate (release block, acceptance criterion 14.8)

Run before cutting any release. The Windows accessibility crash root cause is
tracked upstream in `flutter/flutter#175041`; until a validated Flutter
revision fixes it, keep the semantics hardening and the known-issue note at
the bottom of this section.

1. Check the Flutter engine revision against upstream issue
   `flutter/flutter#175041` — `flutter --version` prints the exact revision;
   confirm whether the fix has landed and in which revision.
2. Upgrade or pin a known-good Flutter version (`flutter upgrade`, or
   `flutter downgrade <known-good>` when the latest is not known-good), then
   `flutter pub get`.
3. Run the full fast suite:
   ```bash
   flutter analyze     # must end with "No issues found!"
   flutter test        # full regression, zero pending timers
   ```
4. Run the Windows integration test (§9.1):
   ```bash
   flutter test integration_test/accessibility_windows_test.dart -d windows
   ```
5. Build the Windows release and run the UIA smoke with 500 random clicks
   (§9.2):
   ```bash
   flutter build windows --release
   powershell -ExecutionPolicy Bypass -File tool/windows_accessibility_smoke.ps1 `
     -Exe build\windows\x64\runner\Release\llm_chess_arena.exe `
     -RandomClicks 500
   ```
6. Repeat the smoke once with Narrator or Inspect.exe attached.
7. Check Event Viewer for any new `flutter_windows.dll` fault
   (`0xC0000005` / `0xC000041D`) from both smoke runs.
8. Only then remove the known-issue note below from the release checklist.

**Known-issue note (do not remove until steps 4–7 pass on the shipped
revision):** the Flutter Windows accessibility bridge has a crash root cause
tracked in `flutter/flutter#175041`; the app-level semantics hardening
(`ExcludeSemantics`/`IndexedStack` hidden-tab guard and stable semantics
roots) is a mitigation, not a fix. The note is referenced by
`docs/FUTURE_WORK.md` §2.6.

## Troubleshooting

- Provider 401 → key wrong; 429 → backoff + lower concurrency.
- **Linux build fails with install `/usr/local` permission errors** after an
  earlier configure failure (e.g. missing `libsecret-1-dev`): the first
  failed configure leaves a CMake cache whose install prefix is not the
  bundle dir. `rm -rf build/linux` and rebuild.
- **Linux build fails on `json.hpp` + clang 21** (`-Wdeprecated-literal-operator`):
  already handled in `linux/CMakeLists.txt`
  (`-Wno-deprecated-literal-operator`); if you regenerate the scaffold,
  re-apply that flag.
- Stockfish not found → `dart run tool/download_stockfish.dart <platform>`
  (see `docs/ENGINE_RUNTIME.md`); heuristic fallback keeps review working.
- `github.com` blocked? The fetch tool falls back to the `gh.llkk.cc` proxy.
- Reformats: `dart format lib test tool`.
- Logs: agent activity panel shows raw deltas + validation + fallback marks.
