/// Stockfish refresh helper: re-download embedded binaries for a release.
///
/// Usage: `dart run tool/refresh_stockfish.dart [sf_TAG]`
/// (default tag: [defaultReleaseTag]).
///
/// For each platform in [platformAssets] this prints the official
/// release-asset URL, the pinned size/SHA-256, the destination directory
/// under `assets/engines/`, and the post-download verification steps
/// (archive type check, binary presence, UCI handshake). It does NOT
/// download anything itself: release hosts are often unreachable from CI,
/// so the actual fetch goes through whatever proxy or mirror the operator
/// has (see `docs/ENGINE_RUNTIME.md` for the tested proxy pattern).
///
/// The platform table (URLs, sizes, hashes) lives in
/// `tool/stockfish_platforms.dart` and is shared with
/// `tool/download_stockfish.dart` so the two scripts cannot drift.
///
/// After refreshing binaries, keep the GPLv3 set in sync:
/// `assets/engines/LICENSE.GPLv3`, `EngineAttributions.stockfish`
/// (`lib/src/review/embedded_engine.dart`), and the source-offer note
/// in `docs/ENGINE_RUNTIME.md`.
library;

import 'dart:io';

import 'stockfish_platforms.dart';

/// Prints refresh instructions for [tag] (see library docs).
void main(List<String> args) {
  final tag = args.isEmpty ? defaultReleaseTag : args.first;
  stdout.writeln('Stockfish refresh — release $tag\n');
  for (final platform in platformAssets) {
    stdout.writeln('[${platform.dir}]');
    stdout.writeln('  url:    ${releaseBase(tag)}/${platform.asset}');
    stdout.writeln('  size:   ${platform.expectedSize} bytes');
    stdout.writeln('  sha256: ${platform.expectedSha256}');
    stdout.writeln(
      '  dest:   assets/engines/${platform.dir}/'
      '${platform.binary}',
    );
    stdout.writeln(
      '  verify: `file` reports ${platform.fileHint} for the '
      'host, then `printf \'uci\\nquit\\n\' | ./<binary>` prints `uciok`.',
    );
  }
  stdout.writeln(
    '\nThen sync LICENSE.GPLv3 + EngineAttributions.stockfish '
    '+ docs/ENGINE_RUNTIME.md (GPLv3 set).',
  );
}
