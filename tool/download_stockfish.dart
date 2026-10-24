/// Stockfish binary fetcher for `assets/engines/`.
///
/// Usage:
/// ```sh
/// dart run tool/download_stockfish.dart --list
/// dart run tool/download_stockfish.dart linux-x86-64
/// dart run tool/download_stockfish.dart --all
/// ```
///
/// Binaries (~100 MB each, ~680 MiB for all 7 platforms) are gitignored and
/// NOT committed. This script fetches the missing ones: it reuses a cached
/// release archive when present (see `--archive-dir`), otherwise downloads
/// the official release asset — trying `github.com` directly first, then the
/// `gh.llkk.cc` proxy prefix (override with `STOCKFISH_PROXY`, or `direct`
/// to skip the proxy). It extracts just the binary, runs `chmod +x` (POSIX),
/// then verifies with `file`, an exact size + SHA-256 check, and a
/// `uci` → `uciok` handshake. It also writes `assets/engines/LICENSE.GPLv3`
/// from the archive's `Copying.txt` when absent.
///
/// Foreign-architecture binaries cannot be executed on this host, so their
/// handshake is best-effort (warning, not failure); the binary for the
/// current host is handshake-gated strictly. After refreshing binaries, keep
/// the GPLv3 set in sync: `assets/engines/LICENSE.GPLv3`,
/// `EngineAttributions.stockfish`, and `docs/ENGINE_RUNTIME.md`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'stockfish_platforms.dart';

/// Default proxy prefix tried when `github.com` is unreachable.
/// Set `STOCKFISH_PROXY=direct` (or empty) to try the official URL only.
const String defaultProxyPrefix = 'https://gh.llkk.cc/';

// Platform table (asset/dir/binary/fileHint/size/SHA-256), the release tag,
// upstream URLs, and license constants are imported from
// `stockfish_platforms.dart`, shared with `refresh_stockfish.dart`.

/// Asset directory name for the current host, or null (web/iOS/unknown).
String? hostAssetDir() {
  final abi = Abi.current();
  if (abi == Abi.linuxX64) {
    return 'linux-x86-64';
  }
  if (abi == Abi.linuxArm64) {
    return 'linux-arm64';
  }
  if (abi == Abi.macosX64 || abi == Abi.macosArm64) {
    return 'macos-universal';
  }
  if (abi == Abi.windowsX64) {
    return 'windows-x86-64';
  }
  if (abi == Abi.windowsArm64) {
    return 'windows-arm64';
  }
  if (abi == Abi.androidArm64) {
    return 'android-arm64';
  }
  if (abi == Abi.androidArm) {
    return 'android-armv7';
  }
  return null;
}

/// SHA-256 (FIPS 180-4), dependency-free so the tool stays pure-Dart.
Uint8List sha256Bytes(List<int> input) {
  const List<int> k = <int>[
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
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

/// Hex-encodes [digest] (lowercase).
String hexOf(Uint8List digest) {
  final buf = StringBuffer();
  for (final byte in digest) {
    buf.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buf.toString();
}

/// Runs a UCI handshake: sends `uci`, waits for `uciok`, then quits.
///
/// Async stdin teardown errors (broken pipe when the binary exits
/// immediately, e.g. a foreign-arch binary that cannot exec on this host)
/// are swallowed; they surface as a failed handshake, not a crash.
Future<bool> uciHandshake(
  String path, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  var ok = false;
  await runZonedGuarded<Future<void>>(() async {
    ok = await _uciHandshakeOnce(path, timeout: timeout);
  }, (Object _, StackTrace _) {});
  return ok;
}

/// Single UCI handshake attempt (see [uciHandshake]).
Future<bool> _uciHandshakeOnce(
  String path, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  late final Process process;
  try {
    process = await Process.start(path, const <String>[]);
  } on Object {
    return false;
  }
  final seen = Completer<bool>();
  final subscription = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((String line) {
        if (line.trim() == 'uciok' && !seen.isCompleted) {
          seen.complete(true);
        }
      });
  unawaited(process.stderr.drain<void>());
  unawaited(
    process.exitCode.then<void>((int code) {
      if (!seen.isCompleted) {
        seen.complete(false);
      }
    }),
  );
  var wrote = false;
  try {
    process.stdin.writeln('uci');
    wrote = true;
  } on Object {
    wrote = false;
  }
  var ok = false;
  if (wrote) {
    try {
      ok = await seen.future.timeout(timeout, onTimeout: () => false);
    } on Object {
      ok = false;
    }
    try {
      process.stdin.writeln('quit');
    } on Object {
      // Engine already gone; nothing to do.
    }
  }
  await subscription.cancel();
  process.kill();
  try {
    await process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () => -1,
    );
  } on Object {
    // Ignore teardown races.
  }
  return ok;
}

/// Downloads [uri] to [dest]. Throws on non-200 or tiny (error-page) bodies.
Future<void> downloadFile(Uri uri, File dest) async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 30);
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw StateError('GET $uri -> HTTP ${response.statusCode}');
    }
    final sink = dest.openWrite();
    await response.pipe(sink);
    if (dest.lengthSync() < 1048576) {
      throw StateError(
        'download from $uri is ${dest.lengthSync()} bytes; '
        'likely an error page, not the release asset',
      );
    }
  } finally {
    client.close(force: true);
  }
}

/// Lists archive members (`stockfish/...` entries).
Future<List<String>> listMembers(File archive) async {
  if (archive.path.endsWith('.zip')) {
    final result = await Process.run('unzip', <String>['-l', archive.path]);
    if (result.exitCode != 0) {
      throw StateError('unzip -l failed: ${result.stderr}');
    }
    final names = <String>[];
    for (final line in (result.stdout as String).split('\n')) {
      if (!line.contains('stockfish/')) {
        continue;
      }
      final token = line.trim().split(RegExp(r'\s+')).last;
      if (token.startsWith('stockfish/')) {
        names.add(token);
      }
    }
    return names;
  }
  final result = await Process.run('tar', <String>['-tzf', archive.path]);
  if (result.exitCode != 0) {
    throw StateError('tar -tzf failed: ${result.stderr}');
  }
  return (result.stdout as String)
      .split('\n')
      .map((String line) => line.trim())
      .where((String line) => line.startsWith('stockfish/'))
      .toList();
}

/// Picks the binary member from [names] when the conventional name misses
/// (largest doc-excluded entry; official archives hold exactly one binary).
String? pickBinaryMember(List<String> names) {
  final candidates = names
      .where(
        (String name) =>
            !name.endsWith('/') &&
            !name.contains('wiki/') &&
            !name.contains('scripts/') &&
            !name.contains('src/') &&
            !name.endsWith('.txt') &&
            !name.endsWith('.md') &&
            !name.endsWith('.cff'),
      )
      .toList();
  return candidates.isEmpty ? null : candidates.first;
}

/// Streams one archive [member] into [dest] via `tar`/`unzip`.
Future<void> extractMember(File archive, String member, File dest) async {
  final exe = archive.path.endsWith('.zip') ? 'unzip' : 'tar';
  final args = archive.path.endsWith('.zip')
      ? <String>['-p', archive.path, member]
      : <String>['-xzOf', archive.path, member];
  final process = await Process.start(exe, args);
  final sink = dest.openWrite();
  var pipeFailed = false;
  try {
    await process.stdout.pipe(sink);
  } on Object {
    pipeFailed = true;
  }
  final code = await process.exitCode;
  final err = await process.stderr.transform(utf8.decoder).join();
  if (pipeFailed || code != 0) {
    if (dest.existsSync()) {
      dest.deleteSync();
    }
    throw StateError(
      '$exe extract of $member failed '
      '(exit $code): ${err.trim()}',
    );
  }
}

/// Returns `file -b` output for [path], or null when `file` is unavailable.
Future<String?> fileDescription(String path) async {
  try {
    final result = await Process.run('file', <String>[
      '-b',
      path,
    ]).timeout(const Duration(seconds: 30));
    if (result.exitCode != 0) {
      return null;
    }
    return (result.stdout as String).trim();
  } on Object {
    return null;
  }
}

/// Fetch/verify options for one run.
class FetchOptions {
  /// Release tag (default [defaultReleaseTag]).
  final String tag;

  /// Directory holding (or receiving) release archives.
  final String archiveDir;

  /// `assets/engines/` directory receiving binaries.
  final String enginesDir;

  /// Proxy prefixes to try after the official URL; empty = direct only.
  final List<String> proxyPrefixes;

  /// Re-extract even when the binary already verifies.
  final bool force;

  /// Re-download the archive even when cached.
  final bool redownload;

  /// Skip the UCI handshake (useful for foreign-arch binaries).
  final bool skipHandshake;

  /// Overrides the download base URL (single candidate under that base;
  /// tests/debugging only — e.g. a loopback server).
  final String? baseUrl;

  /// Creates fetch options.
  const FetchOptions({
    required this.tag,
    required this.archiveDir,
    required this.enginesDir,
    required this.proxyPrefixes,
    required this.force,
    required this.redownload,
    required this.skipHandshake,
    this.baseUrl,
  });
}

/// One-line status for the final summary table.
class FetchResult {
  /// Platform directory name.
  final String dir;

  /// True when the binary is present and verified.
  final bool ok;

  /// Human-readable detail (e.g. `present`, `fetched`, failure reason).
  final String detail;

  /// Creates a result row.
  const FetchResult(this.dir, this.ok, this.detail);
}

/// Download URL candidates for [platform]: official first, then each proxy.
///
/// [baseOverride] (used by tests to point at a loopback server) replaces the
/// candidate list with a single URL under that base.
List<Uri> candidateUrls(
  PlatformAsset platform,
  String tag,
  List<String> proxyPrefixes, {
  String? baseOverride,
}) {
  if (baseOverride != null) {
    final base = baseOverride.endsWith('/')
        ? baseOverride
        : '$baseOverride/';
    return <Uri>[Uri.parse('$base${platform.asset}')];
  }
  final urls = <Uri>[Uri.parse('${releaseBase(tag)}/${platform.asset}')];
  for (final proxy in proxyPrefixes) {
    if (proxy.isEmpty) continue;
    final prefix = proxy.endsWith('/') ? proxy : '$proxy/';
    urls.add(Uri.parse('$prefix${releaseBase(tag)}/${platform.asset}'));
    urls.add(Uri.parse('$prefix$latestBase/${platform.asset}'));
  }
  return urls;
}

/// Ensures the release archive for [platform] exists in [options.archiveDir],
/// downloading through the URL candidates when missing (or [redownload]).
Future<File> ensureArchive(PlatformAsset platform, FetchOptions options) async {
  final archive = File('${options.archiveDir}/${platform.asset}');
  if (archive.existsSync() && !options.redownload) {
    stdout.writeln('  archive cached: ${archive.path}');
    return archive;
  }
  Directory(options.archiveDir).createSync(recursive: true);
  var lastError = 'no URL candidates';
  for (final url in candidateUrls(
    platform,
    options.tag,
    options.proxyPrefixes,
    baseOverride: options.baseUrl,
  )) {
    stdout.writeln('  downloading $url ...');
    try {
      await downloadFile(url, archive).timeout(const Duration(minutes: 20));
      stdout.writeln(
        '  saved ${(archive.lengthSync() / 1048576).toStringAsFixed(1)} MiB',
      );
      return archive;
    } on Object catch (e) {
      lastError = e.toString();
      stdout.writeln('  failed: $lastError');
      if (archive.existsSync()) {
        archive.deleteSync();
      }
    }
  }
  throw StateError('all download candidates failed: $lastError');
}

/// Verifies [binary] against size, SHA-256, `file` hint, and UCI handshake.
///
/// The handshake is strict for the current host platform and best-effort
/// (warning) for foreign architectures that cannot execute here.
Future<bool> verifyBinary(
  PlatformAsset platform,
  File binary,
  FetchOptions options,
) async {
  final size = binary.lengthSync();
  if (size != platform.expectedSize) {
    stdout.writeln('  size mismatch: got $size, want ${platform.expectedSize}');
    return false;
  }
  stdout.writeln('  size ok ($size bytes); hashing ...');
  final digest = hexOf(sha256Bytes(binary.readAsBytesSync()));
  if (digest != platform.expectedSha256) {
    stdout.writeln(
      '  sha256 mismatch:\n    got  $digest\n'
      '    want ${platform.expectedSha256}',
    );
    return false;
  }
  stdout.writeln('  sha256 ok');
  final description = await fileDescription(binary.path);
  if (description == null) {
    stdout.writeln('  warning: `file` unavailable; type check skipped');
  } else if (!description.contains(platform.fileHint)) {
    stdout.writeln(
      '  file mismatch: got "$description", want ${platform.fileHint}',
    );
    return false;
  } else {
    stdout.writeln('  file ok ($description)');
  }
  final isHost = hostAssetDir() == platform.dir;
  if (options.skipHandshake) {
    stdout.writeln('  handshake skipped (--skip-handshake)');
    return true;
  }
  stdout.writeln('  UCI handshake ...');
  final ok = await uciHandshake(binary.path);
  if (ok) {
    stdout.writeln('  handshake ok (uciok)');
    return true;
  }
  if (isHost) {
    stdout.writeln('  handshake FAILED on host platform');
    return false;
  }
  stdout.writeln(
    '  warning: handshake failed (foreign-arch binary, '
    'cannot execute on this host); size+sha+type still verify it',
  );
  return true;
}

/// Fetches (if needed) and verifies one platform binary.
Future<FetchResult> fetchPlatform(
  PlatformAsset platform,
  FetchOptions options,
) async {
  stdout.writeln('[${platform.dir}]');
  final dest = File('${options.enginesDir}/${platform.dir}/${platform.binary}');
  dest.parent.createSync(recursive: true);
  if (dest.existsSync() && !options.force) {
    if (await verifyBinary(platform, dest, options)) {
      return FetchResult(platform.dir, true, 'present');
    }
    stdout.writeln('  existing binary invalid; re-fetching ...');
  }
  // Self-healing fetch (§11.19): when the cached archive is unusable
  // (corrupt/truncated, e.g. from a killed download) [extractAndVerify]
  // deletes it, so the second attempt re-downloads cleanly instead of
  // failing forever against the same bad cache. A pure download failure is
  // deliberately NOT retried — the same URLs would only double the hang.
  File? obtained;
  try {
    final archive = await ensureArchive(platform, options);
    obtained = archive;
    await extractAndVerify(platform, archive, dest, options);
    return FetchResult(platform.dir, true, 'fetched');
  } on Object catch (e) {
    if (obtained == null) {
      return FetchResult(platform.dir, false, e.toString());
    }
    stdout.writeln('  cached archive unusable ($e); re-downloading once ...');
  }
  try {
    final archive = await ensureArchive(platform, options);
    await extractAndVerify(platform, archive, dest, options);
    return FetchResult(
      platform.dir,
      true,
      'fetched (re-downloaded: cached archive was corrupt)',
    );
  } on Object catch (e) {
    return FetchResult(platform.dir, false, e.toString());
  }
}

/// Extracts and verifies [platform] from [archive] into [dest].
///
/// Returns normally on success. On ANY failure — a corrupt/truncated archive
/// that cannot even be listed, a failed member extraction, or a binary that
/// fails verification after extraction — it deletes [archive] and any partial
/// [dest] and throws, so a later attempt re-downloads cleanly: a bad cached
/// archive is never reused (§11.19).
Future<void> extractAndVerify(
  PlatformAsset platform,
  File archive,
  File dest,
  FetchOptions options,
) async {
  dest.parent.createSync(recursive: true);
  final String member;
  try {
    var candidate = platform.conventionalMember();
    final members = await listMembers(archive);
    if (!members.contains(candidate)) {
      final discovered = pickBinaryMember(members);
      if (discovered == null) {
        throw StateError('binary not found in archive');
      }
      stdout.writeln('  conventional member missing; using $discovered');
      candidate = discovered;
    }
    member = candidate;
  } on Object {
    _discardArchive(archive, dest);
    rethrow;
  }
  stdout.writeln('  extracting $member ...');
  try {
    await extractMember(archive, member, dest);
    if (!Platform.isWindows) {
      final chmod = await Process.run('chmod', <String>['+x', dest.path]);
      if (chmod.exitCode != 0) {
        throw StateError('chmod +x failed');
      }
    }
    if (await verifyBinary(platform, dest, options)) {
      return;
    }
    stdout.writeln('  verification failed after extraction; treating the archive as corrupt');
  } on Object {
    _discardArchive(archive, dest);
    rethrow;
  }
}

/// Deletes the unusable [archive] and any partially extracted [dest] binary
/// so the next attempt re-downloads instead of reusing a corrupt cache.
void _discardArchive(File archive, File dest) {
  stdout.writeln('  discarding unusable archive and any partial binary');
  if (archive.existsSync()) {
    archive.deleteSync();
  }
  if (dest.existsSync()) {
    dest.deleteSync();
  }
}

/// Writes `LICENSE.GPLv3` from the first archive holding `Copying.txt`.
Future<bool> ensureLicense(List<File> archives, String enginesDir) async {
  final dest = File('$enginesDir/$licenseFileName');
  if (dest.existsSync()) {
    return true;
  }
  for (final archive in archives) {
    if (!archive.existsSync()) {
      continue;
    }
    try {
      final members = await listMembers(archive);
      if (!members.contains(licenseMember)) {
        continue;
      }
      await extractMember(archive, licenseMember, dest);
      stdout.writeln('wrote $licenseFileName from ${archive.path}');
      return true;
    } on Object {
      continue;
    }
  }
  stdout.writeln(
    'warning: $licenseFileName missing and no archive '
    'provided it; fetch any platform first',
  );
  return false;
}

/// Default `assets/engines/` directory for this checkout.
String defaultEnginesDir() {
  try {
    final scriptPath = Platform.script.toFilePath();
    final toolDir = File(scriptPath).parent;
    if (toolDir.path.endsWith('tool')) {
      return '${toolDir.parent.path}/assets/engines';
    }
  } on Object {
    // Fall through to the cwd-relative default.
  }
  return 'assets/engines';
}

/// Default archive cache: explicit `STOCKFISH_ARCHIVE_DIR`, else a per-user
/// cache directory under `$HOME/.cache` (created on demand).
String defaultArchiveDir() {
  final env = Platform.environment['STOCKFISH_ARCHIVE_DIR'];
  if (env != null && env.isNotEmpty) {
    return env;
  }
  final home =
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Directory.systemTemp.path;
  return '$home/.cache/stockfish-archives';
}

/// Resolves the proxy prefixes to try.
///
/// Precedence: explicit `--proxy` flags (repeatable) → `STOCKFISH_PROXY`
/// (comma/space separated; `direct`/empty disables) → [defaultProxyPrefix].
/// Note `HttpClient` does not read `HTTP(S)_PROXY`, so this flag/env is the
/// explicit override.
List<String> resolveProxies({List<String> cliProxies = const <String>[]}) {
  if (cliProxies.isNotEmpty) return cliProxies;
  final env = Platform.environment['STOCKFISH_PROXY'];
  if (env == null) return <String>[defaultProxyPrefix];
  final prefixes = env
      .split(RegExp(r'[,\s]+'))
      .where((p) => p.isNotEmpty)
      .where((p) => p != 'direct')
      .toList();
  return prefixes;
}

/// Prints usage.
void printUsage(String tag, String archiveDir, String enginesDir) {
  stdout.writeln(
    'Stockfish binary fetcher — release $tag\n'
    'Usage: dart run tool/download_stockfish.dart [options] [platform ...]\n'
    '  platform: one or more of ${platformAssets.map((PlatformAsset p) => p.dir).join(', ')}\n'
    '  (no platform = status report only; nothing is downloaded)\n'
    'Options:\n'
    '  --all               fetch every missing platform binary\n'
    '  --list              list platforms, URLs, and local status\n'
    '  --tag=TAG           release tag (default $tag)\n'
    '  --archive-dir=DIR   archive cache (default $archiveDir)\n'
    '  --engines-dir=DIR   engines dir (default $enginesDir)\n'
    '  --force             re-extract even when the binary verifies\n'
    '  --redownload        re-download archives even when cached\n'
    '  --base-url=URL      override the download base (single candidate;\n'
    '                      tests/debugging only)\n'
    '  --skip-handshake    skip the UCI handshake check\n'
    '  --proxy=PREFIX      proxy prefix to try after the official URL;\n'
    '                      repeatable (default "$defaultProxyPrefix")\n'
    '  --no-proxy          official URL only (no fallback proxy)\n'
    '  --help              this text\n'
    'Env: STOCKFISH_TAG, STOCKFISH_ARCHIVE_DIR, STOCKFISH_PROXY '
    '(comma/space separated; "$defaultProxyPrefix" default, '
    '"direct"/empty to disable).',
  );
}

/// Prints the platform/URL/status table for `--list` and the status report.
void printTable(String enginesDir, String tag, List<String> proxyPrefixes) {
  stdout.writeln(
    'Stockfish $tag — platform status '
    '(engines: $enginesDir)\n',
  );
  stdout.writeln(
    '${'dir'.padRight(17)}${'binary'.padRight(14)}'
    '${'size'.padRight(10)}status',
  );
  for (final platform in platformAssets) {
    final dest = File('$enginesDir/${platform.dir}/${platform.binary}');
    final present = dest.existsSync();
    final status = present
        ? 'present (${dest.lengthSync()} bytes)'
        : 'MISSING (run: dart run tool/download_stockfish.dart ${platform.dir})';
    stdout.writeln(
      '${platform.dir.padRight(17)}'
      '${platform.binary.padRight(14)}'
      '${'${(platform.expectedSize / 1048576).toStringAsFixed(1)} MiB'.padRight(10)}'
      '$status',
    );
    stdout.writeln('  official: ${releaseBase(tag)}/${platform.asset}');
    for (final proxy in proxyPrefixes) {
      if (proxy.isEmpty) continue;
      final prefix = proxy.endsWith('/') ? proxy : '$proxy/';
      stdout.writeln(
        '  proxy:    $prefix${releaseBase(tag)}/${platform.asset}',
      );
    }
    stdout.writeln('  sha256:   ${platform.expectedSha256}');
  }
}

/// External executable this tool needs, plus why.
class _ToolRequirement {
  /// Executable name on `PATH`.
  final String name;

  /// Human-readable reason shown when it is missing.
  final String reason;

  /// Creates a requirement row.
  const _ToolRequirement(this.name, this.reason);
}

/// Returns `true` when [tool] can be spawned (checks `PATH`).
Future<bool> _toolAvailable(String tool) async {
  try {
    await Process.run(tool, const <String>[
      '--version',
    ]).timeout(const Duration(seconds: 15));
    return true;
  } on ProcessException {
    return false;
  } on Object {
    return false;
  }
}

/// Preflights the external tools needed to fetch [selected].
///
/// Returns human-readable problems (empty = ready). `file` is optional (its
/// absence only downgrades the type check to a warning).
Future<List<String>> preflightTools(List<PlatformAsset> selected) async {
  final required = <_ToolRequirement>[
    const _ToolRequirement('tar', 'to read/extract .tar.gz release assets'),
    if (selected.any((p) => p.asset.endsWith('.zip')))
      const _ToolRequirement('unzip', 'to read/extract .zip release assets'),
    if (!Platform.isWindows)
      const _ToolRequirement('chmod', 'to mark binaries executable'),
  ];
  final problems = <String>[];
  for (final requirement in required) {
    if (!await _toolAvailable(requirement.name)) {
      problems.add(
        '`${requirement.name}` not found on PATH '
        '(${requirement.reason}). Install it or choose assets that do '
        'not need it.',
      );
    }
  }
  if (!await _toolAvailable('file')) {
    stdout.writeln(
      'warning: `file` not found; binary type check will be '
      'skipped (size + SHA-256 + UCI handshake still run).',
    );
  }
  return problems;
}

/// Entry point: parses args, fetches requested platforms, prints a summary.
Future<void> main(List<String> args) async {
  var tag = Platform.environment['STOCKFISH_TAG'] ?? defaultReleaseTag;
  var archiveDir = defaultArchiveDir();
  var enginesDir = defaultEnginesDir();
  final cliProxies = <String>[];
  var noProxy = false;
  var all = false;
  var list = false;
  var force = false;
  var redownload = false;
  var skipHandshake = false;
  String? baseUrl;
  final wanted = <String>[];
  for (final arg in args) {
    if (arg == '--all') {
      all = true;
    } else if (arg == '--list') {
      list = true;
    } else if (arg == '--force') {
      force = true;
    } else if (arg == '--redownload') {
      redownload = true;
    } else if (arg == '--skip-handshake') {
      skipHandshake = true;
    } else if (arg == '--no-proxy' || arg == '--direct') {
      noProxy = true;
    } else if (arg == '--help' || arg == '-h') {
      printUsage(tag, archiveDir, enginesDir);
      return;
    } else if (arg.startsWith('--tag=')) {
      tag = arg.substring('--tag='.length);
    } else if (arg.startsWith('--archive-dir=')) {
      archiveDir = arg.substring('--archive-dir='.length);
    } else if (arg.startsWith('--engines-dir=')) {
      enginesDir = arg.substring('--engines-dir='.length);
    } else if (arg.startsWith('--base-url=')) {
      baseUrl = arg.substring('--base-url='.length);
    } else if (arg.startsWith('--proxy=')) {
      cliProxies.add(arg.substring('--proxy='.length));
    } else if (arg.startsWith('--')) {
      stderr.writeln('unknown option: $arg');
      printUsage(tag, archiveDir, enginesDir);
      exitCode = 2;
      return;
    } else {
      wanted.add(arg);
    }
  }
  final proxyPrefixes = noProxy
      ? <String>[]
      : resolveProxies(cliProxies: cliProxies);
  if (list || (wanted.isEmpty && !all)) {
    printTable(enginesDir, tag, proxyPrefixes);
    if (!list) {
      stdout.writeln(
        '\nNothing to do; pass platform dirs or --all. '
        'See --help.',
      );
    }
    return;
  }
  final selected = <PlatformAsset>[];
  if (all) {
    selected.addAll(platformAssets);
  } else {
    for (final name in wanted) {
      final platform = findPlatform(name);
      if (platform == null) {
        stderr.writeln('unknown platform: $name');
        printUsage(tag, archiveDir, enginesDir);
        exitCode = 2;
        return;
      }
      selected.add(platform);
    }
  }
  final problems = await preflightTools(selected);
  if (problems.isNotEmpty) {
    for (final problem in problems) {
      stderr.writeln('error: $problem');
    }
    exitCode = 2;
    return;
  }
  final options = FetchOptions(
    tag: tag,
    archiveDir: archiveDir,
    enginesDir: enginesDir,
    proxyPrefixes: proxyPrefixes,
    force: force,
    redownload: redownload,
    skipHandshake: skipHandshake,
    baseUrl: baseUrl,
  );
  final results = <FetchResult>[];
  for (final platform in selected) {
    results.add(await fetchPlatform(platform, options));
    stdout.writeln('');
  }
  final archives = selected
      .map((PlatformAsset p) => File('$archiveDir/${p.asset}'))
      .toList();
  await ensureLicense(archives, enginesDir);
  stdout.writeln('summary:');
  var failed = 0;
  for (final result in results) {
    stdout.writeln(
      '  ${result.dir.padRight(17)} '
      '${result.ok ? 'OK' : 'FAIL'}  ${result.detail}',
    );
    if (!result.ok) {
      failed++;
    }
  }
  if (failed > 0) {
    exitCode = 1;
  }
}
