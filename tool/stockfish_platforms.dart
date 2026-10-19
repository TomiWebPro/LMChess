/// Shared Stockfish platform table for the `tool/` scripts.
///
/// Single source of truth for the release tag, upstream URLs, workspace
/// layout, and the pinned size/SHA-256 of each extracted `sf_19` binary.
/// Imported by both [download_stockfish.dart] and [refresh_stockfish.dart]
/// so the two never drift (the refresh helper previously duplicated the
/// platform list without hashes).
library;

/// Release tag to fetch (e.g. `sf_19`). Overridable via `--tag=` or the
/// `STOCKFISH_TAG` environment variable in the downloader.
const String defaultReleaseTag = 'sf_19';

/// Upstream release-assets base URL for [tag].
String releaseBase(String tag) =>
    'https://github.com/official-stockfish/Stockfish/releases/download/$tag';

/// Tag-independent "latest" download base URL (proxy fallback only).
const String latestBase =
    'https://github.com/official-stockfish/Stockfish/releases/latest/download';

/// License member inside every release archive.
const String licenseMember = 'stockfish/Copying.txt';

/// License destination under the engines asset directory.
const String licenseFileName = 'LICENSE.GPLv3';

/// One fetchable Stockfish platform: release asset and bundle layout.
class PlatformAsset {
  /// Release asset filename (under [releaseBase]).
  final String asset;

  /// Directory under `assets/engines/` receiving the binary.
  final String dir;

  /// Binary filename inside [dir].
  final String binary;

  /// Expected `file -b` token (`ELF`, `Mach-O`, `PE32`).
  final String fileHint;

  /// Expected extracted binary size in bytes.
  final int expectedSize;

  /// Expected SHA-256 of the extracted binary (hex, lowercase).
  final String expectedSha256;

  /// Creates a platform row.
  const PlatformAsset({
    required this.asset,
    required this.dir,
    required this.binary,
    required this.fileHint,
    required this.expectedSize,
    required this.expectedSha256,
  });

  /// Conventional archive member holding the binary, e.g.
  /// `stockfish/stockfish-linux-x86-64-universal`.
  String conventionalMember() {
    final base = asset.endsWith('.tar.gz')
        ? asset.substring(0, asset.length - 7)
        : asset.substring(0, asset.length - 4);
    final suffix = asset.endsWith('.zip') ? '.exe' : '';
    return 'stockfish/$base$suffix';
  }
}

/// Platform asset table: asset file -> workspace dir -> binary + hashes.
///
/// Sizes/hashes below are the extracted `sf_19` binaries (verified locally).
const List<PlatformAsset> platformAssets = <PlatformAsset>[
  PlatformAsset(
    asset: 'stockfish-linux-x86-64-universal.tar.gz',
    dir: 'linux-x86-64',
    binary: 'stockfish',
    fileHint: 'ELF',
    expectedSize: 103153472,
    expectedSha256:
        '0f83d24cc46d2c66c60f16001af5444873bc112b7d028594513426894c12da19',
  ),
  PlatformAsset(
    asset: 'stockfish-linux-arm64-universal.tar.gz',
    dir: 'linux-arm64',
    binary: 'stockfish',
    fileHint: 'ELF',
    expectedSize: 100531200,
    expectedSha256:
        'bb6599ef38b7a4ae79200a601c40e81a854219a49dba78b1110e7eb4620609bf',
  ),
  PlatformAsset(
    asset: 'stockfish-macos-universal.tar.gz',
    dir: 'macos-universal',
    binary: 'stockfish',
    fileHint: 'Mach-O',
    expectedSize: 105458632,
    expectedSha256:
        '8eed61129d1493c5d1f2fd9323f0c54c47ac49319911fbde18c6b9c87e8b13c5',
  ),
  PlatformAsset(
    asset: 'stockfish-windows-x86-64-universal.zip',
    dir: 'windows-x86-64',
    binary: 'stockfish.exe',
    fileHint: 'PE32',
    expectedSize: 103046300,
    expectedSha256:
        '45bc8e4969147db9c2eb533810637994619bff0eacc81ccfd9854394901bcbd0',
  ),
  PlatformAsset(
    asset: 'stockfish-windows-arm64-universal.zip',
    dir: 'windows-arm64',
    binary: 'stockfish.exe',
    fileHint: 'PE32',
    expectedSize: 100303360,
    expectedSha256:
        '3b5881df3d6f92817cf6664a6a18a473b50d424c71a1247fe4268090db281413',
  ),
  PlatformAsset(
    asset: 'stockfish-android-arm64-universal.tar.gz',
    dir: 'android-arm64',
    binary: 'stockfish',
    fileHint: 'ELF',
    expectedSize: 100695968,
    expectedSha256:
        'ffd8fc2004d3d19f9fdab95d84c92709aea92e8d3af405eda0b281b23cf1daf8',
  ),
  PlatformAsset(
    asset: 'stockfish-android-armv7-neon.tar.gz',
    dir: 'android-armv7',
    binary: 'stockfish',
    fileHint: 'ELF',
    expectedSize: 99697096,
    expectedSha256:
        '993a3e8bce85a503abc900056019691057a83e13ae92c1a2cbb089b9680593f3',
  ),
];

/// Looks up a platform by its asset directory name, or null.
PlatformAsset? findPlatform(String dir) {
  for (final platform in platformAssets) {
    if (platform.dir == dir) {
      return platform;
    }
  }
  return null;
}
