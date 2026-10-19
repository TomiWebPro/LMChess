// SPDX-License-Identifier: GPL-3.0-or-later
// Embedded Stockfish runtime (Stockfish is GPLv3). Attribution:
// EngineAttributions.stockfish; license text: assets/engines/LICENSE.GPLv3;
// source-offer procedure: docs/ENGINE_RUNTIME.md.
// Distribution also subject to the Geographic Use Restriction Addendum v1.0
// (GURAv1), appended in full to the root LICENSE file; it takes precedence
// on conflict.
/// Embedded Stockfish runtime: first-run extraction of bundled binaries.
///
/// # Why extraction is needed
///
/// Flutter ships `assets/engines/...` files **without exec permission**
/// and — on desktop — inside the application bundle where paths are not
/// stable across launches. So on first use [resolveBinary] copies the
/// bundled binary for the current platform into the application-support
/// directory (via `path_provider`), sets the executable bit on
/// Linux/macOS/Android (`chmod +x`), and returns the extracted path,
/// which [UciEngineAdapter] can then spawn.
///
/// # Platform behavior
///
/// * Desktop + Android: extract, `chmod +x`, spawn. Stockfish is a
///   self-contained binary with no shared-library dependencies beyond
///   the system libc.
/// * iOS: Apple forbids executing bundled binaries from an app sandbox,
///   so resolution always fails with an honest "unsupported" error and
///   callers must fall back to [HeuristicEvaluator].
/// * Web: `dart:io` processes do not exist; same honest fallback.
/// * Dev machines: when the bundled asset is absent (e.g. a platform
///   whose binary was not shipped — see `docs/ENGINE_RUNTIME.md`),
///   resolution falls back to a `PATH` lookup (`stockfish`), so desktop
///   development keeps working without the bundle.
///
/// # GPLv3 note
///
/// Stockfish is GPLv3. The license text ships at
/// `assets/engines/LICENSE.GPLv3`, attribution lives in
/// [EngineAttributions.stockfish], and the source-offer procedure is
/// documented in `docs/ENGINE_RUNTIME.md`. Keep all three in sync when
/// refreshing binaries.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'engine_adapter.dart';

/// Locates (and first-run extracts) the embedded Stockfish binary.
abstract class EmbeddedEngine {
  /// Stockfish release these binaries were taken from.
  static const String stockfishVersion = 'sf_19';

  /// Upstream release page for refreshing binaries.
  static const String stockfishReleaseUrl =
      'https://github.com/official-stockfish/Stockfish/releases/tag/sf_19';

  /// Filename of the binary inside each per-platform asset directory.
  static const Map<String, String> _binaryFileNames = <String, String>{
    'linux-x86-64': 'stockfish',
    'linux-arm64': 'stockfish',
    'macos-universal': 'stockfish',
    'windows-x86-64': 'stockfish.exe',
    'windows-arm64': 'stockfish.exe',
    'android-arm64': 'stockfish',
    'android-armv7': 'stockfish',
  };

  /// Pinned extracted-binary size per platform directory, in bytes.
  ///
  /// Mirrored from `tool/download_stockfish.dart` (`platformAssets`) for
  /// [`stockfishVersion`]. Keep both in sync when refreshing binaries. Used
  /// to reject a truncated or substituted bundled asset before it can run.
  static const Map<String, int> _pinnedSizes = <String, int>{
    'linux-x86-64': 103153472,
    'linux-arm64': 100531200,
    'macos-universal': 105458632,
    'windows-x86-64': 103046300,
    'windows-arm64': 100303360,
    'android-arm64': 100695968,
    'android-armv7': 99697096,
  };

  /// Pinned extracted-binary SHA-256 per platform directory (hex, lowercase).
  ///
  /// Mirrored from `tool/download_stockfish.dart` (`platformAssets`). The
  /// tool lives outside `lib/` (and must not be imported from app code), so a
  /// small local mirror is the pragmatic way to enforce the same digest check
  /// at first-run extraction. See `docs/ENGINE_RUNTIME.md` for the refresh
  /// procedure.
  static const Map<String, String> _pinnedSha256 = <String, String>{
    'linux-x86-64':
        '0f83d24cc46d2c66c60f16001af5444873bc112b7d028594513426894c12da19',
    'linux-arm64':
        'bb6599ef38b7a4ae79200a601c40e81a854219a49dba78b1110e7eb4620609bf',
    'macos-universal':
        '8eed61129d1493c5d1f2fd9323f0c54c47ac49319911fbde18c6b9c87e8b13c5',
    'windows-x86-64':
        '45bc8e4969147db9c2eb533810637994619bff0eacc81ccfd9854394901bcbd0',
    'windows-arm64':
        '3b5881df3d6f92817cf6664a6a18a473b50d424c71a1247fe4268090db281413',
    'android-arm64':
        'ffd8fc2004d3d19f9fdab95d84c92709aea92e8d3af405eda0b281b23cf1daf8',
    'android-armv7':
        '993a3e8bce85a503abc900056019691057a83e13ae92c1a2cbb089b9680593f3',
  };

  /// Platforms this app ships (or intends to ship) binaries for.
  ///
  /// Exposed for the support-matrix table in `docs/ENGINE_RUNTIME.md`
  /// and any settings UI that lists engine availability.
  static List<String> get shippedPlatforms =>
      _binaryFileNames.keys.toList(growable: false);

  /// Maps an OS/arch pair to the bundled asset directory name.
  ///
  /// Returns e.g. `'linux-x86-64'` for Linux x64, or null when no
  /// binary exists for the pair (iOS, web, unshipped arch combos).
  /// Pure function of its inputs so it stays unit-testable without
  /// touching the platform.
  static String? assetDirForOs({required String os, Abi? arch}) {
    final resolved = arch ?? Abi.current();
    switch (os) {
      case 'linux':
        if (resolved == Abi.linuxX64) return 'linux-x86-64';
        if (resolved == Abi.linuxArm64) return 'linux-arm64';
        return null;
      case 'macos':
        // One universal binary covers both Intel and Apple Silicon.
        if (resolved == Abi.macosX64 || resolved == Abi.macosArm64) {
          return 'macos-universal';
        }
        return null;
      case 'windows':
        if (resolved == Abi.windowsX64) return 'windows-x86-64';
        if (resolved == Abi.windowsArm64) return 'windows-arm64';
        return null;
      case 'android':
        if (resolved == Abi.androidArm64) return 'android-arm64';
        if (resolved == Abi.androidArm) return 'android-armv7';
        return null;
      default:
        return null;
    }
  }

  /// Flutter asset path of the engine binary for an OS/arch pair.
  ///
  /// Returns e.g. `'assets/engines/linux-x86-64/stockfish'`, or null
  /// when the pair has no bundled binary.
  static String? bundledAssetPath({String? os, Abi? arch}) {
    if (kIsWeb) return null;
    final dir =
        assetDirForOs(os: os ?? Platform.operatingSystem, arch: arch);
    if (dir == null) return null;
    return 'assets/engines/$dir/${_binaryFileNames[dir]}';
  }

  /// Memoized result of a default (unparameterized) [resolveBinary] call.
  ///
  /// Extraction hashes the ~100 MB binary; the resolved path is stable for
  /// the life of the isolate, so repeated connects must not re-hash.
  static Future<String>? _defaultResolution;

  /// Resolves a runnable Stockfish binary path for this device.
  ///
  /// 1. Picks the bundled asset for the current platform
  ///    ([bundledAssetPath], overridable via [os]/[arch] for tooling).
  /// 2. Copies it with `rootBundle` into the application-support
  ///    directory on first run, verifying its pinned size + SHA-256 and
  ///    `chmod +x`-ing it on non-Windows OSes.
  /// 3. Falls back to a `PATH` lookup (`stockfish`) when the asset is
  ///    missing or fails verification, logging a warning (never silently),
  ///    so dev machines without the bundle still work.
  ///
  /// Throws [UnsupportedError] on web/iOS (execution impossible — use
  /// the heuristic fallback) and [StateError] when neither the bundle
  /// nor `PATH` yields a binary; the message is human-readable and
  /// suitable for a settings-screen error line.
  static Future<String> resolveBinary({String? os, Abi? arch}) {
    if (os == null && arch == null) {
      return _defaultResolution ??= _resolveBinary(os: os, arch: arch);
    }
    return _resolveBinary(os: os, arch: arch);
  }

  /// Un-memoized implementation of [resolveBinary] (see its docs).
  static Future<String> _resolveBinary({String? os, Abi? arch}) async {
    if (kIsWeb) {
      throw UnsupportedError(await explanatoryError(osOverride: os));
    }
    final operatingSystem = os ?? Platform.operatingSystem;
    if (operatingSystem == 'ios') {
      throw UnsupportedError(await explanatoryError(osOverride: os));
    }
    final assetDir = assetDirForOs(os: operatingSystem, arch: arch);
    final assetPath = assetDir == null
        ? null
        : bundledAssetPath(os: operatingSystem, arch: arch);
    if (assetPath != null && assetDir != null) {
      try {
        return await _extractAsset(assetPath, assetDir);
      } on Object catch (error) {
        // Asset missing or unreadable (e.g. unshipped platform dir with
        // only a README placeholder) or failed size/digest verification.
        // Warn loudly — never silently — before falling back to PATH, so a
        // missing or corrupted bundle is visible instead of masked.
        debugPrint(
          'LLM Chess Arena: embedded Stockfish for "$assetDir" could not be '
          'extracted/verified ($error); falling back to PATH `stockfish`.',
        );
      }
    }
    final onPath = await _findOnPath('stockfish');
    if (onPath != null) return onPath;
    throw StateError(await explanatoryError(osOverride: os));
  }

  /// True when [resolveBinary] would succeed on this device.
  ///
  /// Performs the same first-run extraction as [resolveBinary], so a
  /// `true` result leaves the binary extracted and ready to spawn.
  static Future<bool> isAvailable() async {
    try {
      await resolveBinary();
      return true;
    } on Object {
      return false;
    }
  }

  /// Human-readable reason the embedded engine cannot run, or `''`.
  ///
  /// Returns `''` when [isAvailable] is true. Never throws; safe to
  /// call from settings/about UI on any platform including web/iOS,
  /// where it yields the honest "unsupported, heuristic fallback"
  /// message instead of failing.
  static Future<String> explanatoryError({String? osOverride}) async {
    if (kIsWeb) {
      return 'Stockfish cannot run on Web (no child processes); '
          'using the heuristic estimator instead.';
    }
    final operatingSystem = osOverride ?? _safeOperatingSystem();
    if (operatingSystem == 'ios') {
      return 'Stockfish cannot run on iOS (executing bundled binaries '
          'is forbidden by the app sandbox); using the heuristic '
          'estimator instead.';
    }
    String? assetPath;
    try {
      assetPath = bundledAssetPath(os: operatingSystem);
    } on Object {
      assetPath = null;
    }
    final onPath = await _findOnPath('stockfish');
    if (onPath != null) {
      return '';
    }
    if (assetPath == null) {
      return 'No Stockfish binary is bundled for this platform '
          '($operatingSystem) and none was found on PATH; using the '
          'heuristic estimator instead. See docs/ENGINE_RUNTIME.md.';
    }
    return 'The bundled Stockfish binary ($assetPath) could not be '
        'extracted and no `stockfish` was found on PATH; using the '
        'heuristic estimator instead. See docs/ENGINE_RUNTIME.md.';
  }

  /// Serializes first-run extractions within this isolate.
  ///
  /// Two concurrent [resolveBinary] callers must never write the same
  /// target file at once; chaining onto this future is a simple in-isolate
  /// mutex.
  static Future<void> _extractQueue = Future<void>.value();

  /// Copies a bundled asset into the support dir and makes it runnable.
  ///
  /// The bundled bytes are verified against the pinned size + SHA-256 for
  /// [assetDir] (see [_pinnedSizes]/[_pinnedSha256]) so a truncated,
  /// corrupted, or substituted asset can never be executed. The target is
  /// rewritten only when its on-disk digest does not already match, and the
  /// write is atomic (temp file + rename). `chmod +x` failures are surfaced
  /// rather than ignored.
  static Future<String> _extractAsset(String assetPath, String assetDir) {
    final result = _extractQueue.then(
      (_) => _extractAssetLocked(assetPath, assetDir),
    );
    // Keep the queue alive (and chainable) even when this extraction fails.
    _extractQueue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  /// Body of [_extractAsset], run under the [_extractQueue] guard.
  static Future<String> _extractAssetLocked(
    String assetPath,
    String assetDir,
  ) async {
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final pinnedSize = _pinnedSizes[assetDir];
    final pinnedSha = _pinnedSha256[assetDir];
    if (pinnedSize != null && bytes.length != pinnedSize) {
      throw StateError(
        'bundled engine "$assetDir" is ${bytes.length} bytes; expected '
        '$pinnedSize (pinned ${EmbeddedEngine.stockfishVersion}). '
        'Re-fetch with tool/download_stockfish.dart.',
      );
    }
    if (pinnedSha != null) {
      final digest = _sha256Hex(bytes);
      if (digest != pinnedSha) {
        throw StateError(
          'bundled engine "$assetDir" sha256 $digest does not match pinned '
          '$pinnedSha; refusing to run a modified binary.',
        );
      }
    }
    final fileName = assetPath.split('/').last;
    final support = await getApplicationSupportDirectory();
    final enginesDir = Directory('${support.path}/engines');
    await enginesDir.create(recursive: true);
    final target = File('${enginesDir.path}/$fileName');
    if (!await _isFreshBinary(target, pinnedSha, bytes.length)) {
      // Atomic replace: write a sibling temp file, then rename over target.
      final temp = File(
        '${target.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
      );
      try {
        await temp.writeAsBytes(bytes, flush: true);
        await temp.rename(target.path);
      } catch (_) {
        if (await temp.exists()) {
          await temp.delete();
        }
        rethrow;
      }
    }
    if (!Platform.isWindows) {
      final chmod = await Process.run('chmod', <String>['+x', target.path]);
      if (chmod.exitCode != 0) {
        throw StateError(
          'chmod +x failed for ${target.path} '
          '(exit ${chmod.exitCode}): ${chmod.stderr}',
        );
      }
    }
    return target.path;
  }

  /// True when [target] already holds exactly [size] bytes and, when a
  /// [pinnedSha] is known, the pinned digest.
  ///
  /// A length-only check is insufficient: a same-sized corrupted or
  /// replaced file would pass it, so the cached copy is hashed.
  static Future<bool> _isFreshBinary(
    File target,
    String? pinnedSha,
    int size,
  ) async {
    if (!await target.exists()) return false;
    if (await target.length() != size) return false;
    if (pinnedSha == null) return true;
    return _sha256Hex(await target.readAsBytes()) == pinnedSha;
  }

  /// Looks up [binary] on `PATH` (`where` on Windows, `which` else).
  ///
  /// Returns the first hit or null. Never throws.
  static Future<String?> _findOnPath(String binary) async {
    try {
      final probe = Platform.isWindows ? 'where' : 'which';
      final result = await Process.run(probe, <String>[binary]);
      if (result.exitCode != 0) return null;
      final firstLine =
          (result.stdout as String).split(RegExp(r'\r?\n')).first.trim();
      return firstLine.isEmpty ? null : firstLine;
    } on Object {
      return null;
    }
  }

  /// Reads [Platform.operatingSystem] without throwing on web stubs.
  static String _safeOperatingSystem() {
    try {
      return Platform.operatingSystem;
    } on Object {
      return 'web';
    }
  }
}

/// Attribution strings for bundled engines (settings/about screen).
///
/// Stockfish is GPLv3: keep [stockfish] in sync with
/// `assets/engines/LICENSE.GPLv3` and `docs/ENGINE_RUNTIME.md`.
abstract class EngineAttributions {
  /// Stockfish name, version, license, copyright, and source URL.
  static const String stockfish =
      'Stockfish ${EmbeddedEngine.stockfishVersion} '
      '(https://github.com/official-stockfish/Stockfish) '
      'by the Stockfish developers — licensed under GPLv3 '
      '(see assets/engines/LICENSE.GPLv3). '
      'Corresponding source available per docs/ENGINE_RUNTIME.md.';

  /// Distribution-level addendum that modifies the project's GPLv3 base
  /// license (Geographic Use Restriction Addendum v1.0).
  ///
  /// Shown on the settings/about screen so every user can see the
  /// geographic restriction the distribution is under, not just
  /// repository readers. Keep in sync with the root `LICENSE` file (the
  /// addendum is appended after the GPLv3 text) and the README license
  /// section.
  static const String geographicUseRestriction =
      'Distributed under the GNU General Public License v3.0 or later, as '
      'modified by the Geographic Use Restriction Addendum v1.0 (GURAv1) — '
      'permissions are revoked in Brazil, California, Texas, Utah, '
      'Louisiana, Colorado, Illinois and New York (USA), and for holders of '
      'citizenship, residency or residential permits there. See the LICENSE '
      'file in the project source.';

  /// Heuristic estimator attribution (built-in, no third-party code).
  static const String heuristic =
      'Built-in heuristic estimator (material + positional terms) — '
      'not engine analysis.';
}

// ---------------------------------------------------------------------------
// Pinned-digest helpers.
//
// SHA-256 (FIPS 180-4), dependency-free — mirrored from
// `tool/download_stockfish.dart` (which verifies the same digests when
// fetching). App code must not import `tool/`, so the algorithm is kept
// here as a small copy. Keep the two implementations in step, or move this
// to a shared `lib/` utility if it ever grows.
// ---------------------------------------------------------------------------

/// SHA-256 digest of [input] as uppercase-free lowercase hex.
String _sha256Hex(List<int> input) {
  final digest = _sha256Bytes(input);
  final buf = StringBuffer();
  for (final byte in digest) {
    buf.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buf.toString();
}

/// SHA-256 digest bytes of [input] (FIPS 180-4, pure Dart).
Uint8List _sha256Bytes(List<int> input) {
  const List<int> k = <int>[
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];
  var h0 = 0x6a09e667;
  var h1 = 0xbb67ae85;
  var h2 = 0x3c6ef372;
  var h3 = 0xa54ff53a;
  var h4 = 0x510e527f;
  var h5 = 0x9b05688c;
  var h6 = 0x1f83d9ab;
  var h7 = 0x5be0cd19;

  int rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xffffffff;

  final bitLen = input.length * 8;
  final paddedLen = ((input.length + 8) ~/ 64 + 1) * 64;
  final padded = Uint8List(paddedLen);
  padded.setAll(0, input);
  padded[input.length] = 0x80;
  final view = ByteData.sublistView(padded);
  view.setUint32(paddedLen - 8, (bitLen >> 32) & 0xffffffff);
  view.setUint32(paddedLen - 4, bitLen & 0xffffffff);

  final w = List<int>.filled(64, 0);
  for (var off = 0; off < paddedLen; off += 64) {
    for (var i = 0; i < 16; i++) {
      w[i] = view.getUint32(off + i * 4);
    }
    for (var i = 16; i < 64; i++) {
      final s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
    }
    var a = h0;
    var b = h1;
    var c = h2;
    var d = h3;
    var e = h4;
    var f = h5;
    var g = h6;
    var h = h7;
    for (var i = 0; i < 64; i++) {
      final s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      final ch = (e & f) ^ ((~e) & g);
      final t1 = (h + s1 + ch + k[i] + w[i]) & 0xffffffff;
      final s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final t2 = (s0 + maj) & 0xffffffff;
      h = g;
      g = f;
      f = e;
      e = (d + t1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & 0xffffffff;
    }
    h0 = (h0 + a) & 0xffffffff;
    h1 = (h1 + b) & 0xffffffff;
    h2 = (h2 + c) & 0xffffffff;
    h3 = (h3 + d) & 0xffffffff;
    h4 = (h4 + e) & 0xffffffff;
    h5 = (h5 + f) & 0xffffffff;
    h6 = (h6 + g) & 0xffffffff;
    h7 = (h7 + h) & 0xffffffff;
  }
  final out = Uint8List(32);
  final outView = ByteData.sublistView(out);
  outView.setUint32(0, h0);
  outView.setUint32(4, h1);
  outView.setUint32(8, h2);
  outView.setUint32(12, h3);
  outView.setUint32(16, h4);
  outView.setUint32(20, h5);
  outView.setUint32(24, h6);
  outView.setUint32(28, h7);
  return out;
}
