/// Deterministic, offline tests for the `tool/download_stockfish.dart`
/// corrupt-archive self-heal (§11.19).
///
/// A cached release archive that is corrupt/truncated (e.g. a killed
/// download) must be discarded and re-downloaded instead of failing forever:
/// `fetchPlatform` now retries exactly once after `extractAndVerify` deletes
/// the unusable archive. All downloads in these tests go to a loopback HTTP
/// server (no external network), and the fake platform carries its own
/// size/SHA-256 so verification is self-contained.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../tool/download_stockfish.dart';
import '../tool/stockfish_platforms.dart';

/// Fake release asset name (must end in `.tar.gz` so the tar code path is
/// used and [PlatformAsset.conventionalMember] resolves).
const String fakeAsset = 'stockfish-fake-host-universal.tar.gz';

/// Deterministic pseudo-random payload.
///
/// > 1 MiB (so `downloadFile`'s error-page guard accepts it) and
/// incompressible (so the tar.gz also stays > 1 MiB), with the exact bytes
/// irrelevant because the fake platform reports the payload's own size and
/// SHA-256.
List<int> fakePayload() {
  final bytes = Uint8List(2200000);
  var state = 0x12345678;
  for (var i = 0; i < bytes.length; i++) {
    state = (state * 1103515245 + 12345) & 0x7fffffff;
    bytes[i] = (state >> 16) & 0xff;
  }
  return bytes;
}

/// A [PlatformAsset] whose binary is exactly [payload] bytes.
PlatformAsset fakePlatform(List<int> payload) => PlatformAsset(
      asset: fakeAsset,
      dir: 'fake-host',
      binary: 'stockfish',
      fileHint: 'data',
      expectedSize: payload.length,
      expectedSha256: hexOf(sha256Bytes(payload)),
    );

/// Builds a real tar.gz holding [payload] under the conventional member.
Future<Uint8List> fakeArchiveBytes(List<int> payload) async {
  final staging = Directory.systemTemp.createTempSync('fake-sf-');
  try {
    final memberFile = File(
      '${staging.path}/${fakePlatform(payload).conventionalMember()}',
    );
    memberFile.parent.createSync(recursive: true);
    memberFile.writeAsBytesSync(payload);
    final result = await Process.run(
      'tar',
      <String>['-czf', '${staging.path}/archive.tar.gz', '-C', staging.path, 'stockfish'],
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return File('${staging.path}/archive.tar.gz').readAsBytesSync();
  } finally {
    staging.deleteSync(recursive: true);
  }
}

/// Serves [body] as the fake release asset; counts requests in [hits].
Future<HttpServer> startServer(List<int> body, List<int> hits) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((HttpRequest request) {
    hits[0]++;
    if (request.uri.path == '/$fakeAsset') {
      request.response.statusCode = HttpStatus.ok;
      request.response.add(body);
    } else {
      request.response.statusCode = HttpStatus.notFound;
    }
    request.response.close();
  });
  return server;
}

/// Fetch options pointing at a loopback server (or unreachable when empty).
FetchOptions optionsFor(String baseUrl) => FetchOptions(
      tag: defaultReleaseTag,
      archiveDir: archiveDir.path,
      enginesDir: enginesDir.path,
      proxyPrefixes: const <String>[],
      force: false,
      redownload: false,
      skipHandshake: true,
      baseUrl: baseUrl,
    );

late Directory archiveDir;
late Directory enginesDir;

void main() {
  setUp(() {
    archiveDir = Directory.systemTemp.createTempSync('sf-archive-');
    enginesDir = Directory.systemTemp.createTempSync('sf-engines-');
  });
  tearDown(() {
    archiveDir.deleteSync(recursive: true);
    enginesDir.deleteSync(recursive: true);
  });

  test(
    'corrupt cached archive is discarded, re-downloaded, and verified (§11.19)',
    () async {
      final payload = fakePayload();
      final platform = fakePlatform(payload);
      // A corrupt archive is already in the cache (e.g. a killed download).
      File('${archiveDir.path}/$fakeAsset')
          .writeAsBytesSync(utf8.encode('garbage: not a tar archive'));
      final hits = <int>[0];
      final server = await startServer(await fakeArchiveBytes(payload), hits);
      addTearDown(() => server.close(force: true));

      final result =
          await fetchPlatform(platform, optionsFor('http://127.0.0.1:${server.port}'));

      expect(result.ok, isTrue, reason: result.detail);
      expect(result.detail, contains('re-downloaded'));
      expect(hits[0], 1, reason: 'recovery must re-download exactly once');
      // The recovered archive is the valid one and the binary verifies.
      final archive = File('${archiveDir.path}/$fakeAsset');
      expect(archive.existsSync(), isTrue);
      expect(await listMembers(archive), contains(platform.conventionalMember()));
      final binary =
          File('${enginesDir.path}/${platform.dir}/${platform.binary}');
      expect(binary.existsSync(), isTrue);
      expect(await verifyBinary(platform, binary, optionsFor('')), isTrue);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('re-download failure is bounded (one retry) and leaves no corrupt cache',
      () async {
    final payload = fakePayload();
    final platform = fakePlatform(payload);
    // The server also serves garbage (> 1 MiB so downloadFile accepts it),
    // so the re-downloaded archive fails extraction the same way.
    final hits = <int>[0];
    final server = await startServer(payload, hits);
    addTearDown(() => server.close(force: true));
    File('${archiveDir.path}/$fakeAsset')
        .writeAsBytesSync(utf8.encode('garbage: not a tar archive'));

    final result =
        await fetchPlatform(platform, optionsFor('http://127.0.0.1:${server.port}'));

    expect(result.ok, isFalse, reason: 'expected a bounded failure');
    expect(hits[0], 1, reason: 'exactly one re-download attempt, then stop');
    // No corrupt archive remains: a later run starts from a clean cache.
    expect(File('${archiveDir.path}/$fakeAsset').existsSync(), isFalse);
    expect(
      File('${enginesDir.path}/${platform.dir}/${platform.binary}').existsSync(),
      isFalse,
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a pure download failure is NOT retried (no double hang)', () async {
    final payload = fakePayload();
    final platform = fakePlatform(payload);
    // Nothing listens on port 1: the single candidate URL is unreachable, so
    // `ensureArchive` throws before any archive exists and `fetchPlatform`
    // must fail immediately instead of repeating the download.
    final result =
        await fetchPlatform(platform, optionsFor('http://127.0.0.1:1'));
    expect(result.ok, isFalse);
    expect(result.detail, contains('all download candidates failed'));
    expect(File('${archiveDir.path}/$fakeAsset').existsSync(), isFalse);
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('baseOverride yields a single candidate under the given base', () {
    final platform = fakePlatform(fakePayload());
    final urls = candidateUrls(
      platform,
      defaultReleaseTag,
      const <String>[],
      baseOverride: 'http://127.0.0.1:8080',
    );
    expect(urls, hasLength(1));
    expect(urls.single.toString(), 'http://127.0.0.1:8080/$fakeAsset');
    // Without an override the official release base comes first.
    final plain = candidateUrls(platform, defaultReleaseTag, const <String>[]);
    expect(
      plain.first.toString(),
      '${releaseBase(defaultReleaseTag)}/$fakeAsset',
    );
  });

  test('extractAndVerify succeeds on a valid cached archive (no download)',
      () async {
    final payload = fakePayload();
    final platform = fakePlatform(payload);
    final archive = File('${archiveDir.path}/$fakeAsset')
      ..writeAsBytesSync(await fakeArchiveBytes(payload));
    final dest = File('${enginesDir.path}/${platform.dir}/${platform.binary}');

    await extractAndVerify(platform, archive, dest, optionsFor(''));

    expect(dest.existsSync(), isTrue);
    expect(await verifyBinary(platform, dest, optionsFor('')), isTrue);
    // The valid archive is NOT discarded.
    expect(archive.existsSync(), isTrue);
  }, timeout: const Timeout(Duration(minutes: 1)));
}
