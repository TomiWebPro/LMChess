/// Board rendering for LLM prompts.
///
/// Both game modes use this one renderer, so an agent sees the **same**
/// prompt format for a standard and a chaotic position at the same ply. The
/// prompt payload is a plain square→piece-letter map, never FEN or variant
/// JSON, and never a list of legal moves: the model is asked to produce its
/// natural move and the engine validates or interprets it afterwards.
library;

/// Renders [squares] as an ASCII board from the side-to-move's perspective.
///
/// * [squares] maps square names (`'e4'`) to one piece letter
///   (`PNBRQK` = White, `pnbrqk` = Black). Missing/unknown entries render as
///   `.` so a malformed board can never break the prompt.
/// * The mover's home rank is always at the bottom: White sees ranks 8→1
///   top→bottom with files a→h; Black sees ranks 1→8 with files h→a (a true
///   180° rotation).
/// * Files are labelled at the top and bottom, ranks on the left.
String renderBoardForPrompt({
  required Map<String, String> squares,
  required String sideToMove,
}) {
  final black = sideToMove.trim().toLowerCase().startsWith('b');
  final files = black
      ? const <String>['h', 'g', 'f', 'e', 'd', 'c', 'b', 'a']
      : const <String>['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
  final ranks = black
      ? const <int>[1, 2, 3, 4, 5, 6, 7, 8]
      : const <int>[8, 7, 6, 5, 4, 3, 2, 1];
  final header = '    ${files.join(' ')}';
  final buffer = StringBuffer()
    ..writeln(header)
    ..writeln('  +-----------------+');
  for (final rank in ranks) {
    final row = <String>[
      for (final file in files) _cell(squares['$file$rank']),
    ];
    buffer.writeln('$rank | ${row.join(' ')} |');
  }
  buffer
    ..writeln('  +-----------------+')
    ..write(header);
  return buffer.toString();
}

/// One board cell: a known piece letter, or `.` for empty/malformed.
String _cell(String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return '.';
  final letter = value[0];
  return RegExp(r'^[KQRBNPkqrbnp]$').hasMatch(letter) ? letter : '.';
}

/// One piece letter for prompt maps (`PNBRQK` White, `pnbrqk` Black).
String promptPieceLetter(String typeLetter, {required bool isWhite}) {
  final letter = typeLetter.trim();
  if (letter.isEmpty) return '';
  return isWhite ? letter.toUpperCase() : letter.toLowerCase();
}
