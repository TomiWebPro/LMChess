/// Board-mapping helpers for the UI layer.
///
/// Renders [Position], FEN, and stored payload shapes as `Chessboard`
/// `squares` maps, plus legality/check queries and FEN advancement.
/// Talks to: `chess/` (`fen.dart`, `move.dart`, `piece.dart`, `position.dart`), `variant/variant_board.dart`; renders `Chessboard` squares.
/// Never imports: `package:flutter`, `game/`, `arena/`, `storage/`, `llm/` — pure mapping helpers.
library;

import 'dart:convert';

import '../../chess/fen.dart';
import '../../chess/move.dart';
import '../../chess/piece.dart';
import '../../chess/position.dart';
import '../../variant/variant_board.dart';

/// Renders [position] as a [Chessboard] `squares` map (`'e4' → 'wP'`).
///
/// Uses [Piece.code] (`'wK'`…`'bP'`), one of the two encodings the board
/// accepts (the other being raw glyphs).
Map<String, String> squaresOf(Position position) {
  return <String, String>{
    for (final entry in position.board.entries)
      entry.key.name: entry.value.code,
  };
}

/// Renders a [VariantBoard] as a [Chessboard] `squares` map.
///
/// Uses the same `wK`…`bP` encoding as [squaresOf], including duplicate/missing
/// kings (the board does not assume exactly one king per side).
Map<String, String> squaresOfVariantBoard(VariantBoard board) {
  return <String, String>{
    for (final entry in board.squares.entries)
      entry.key.name:
          '${colorCode(entry.value.color)}${entry.value.type.letter}',
  };
}

/// Renders a FEN string as a [Chessboard] `squares` map without a
/// [Position] (used for seek/replay over stored FEN histories).
///
/// Parses only the placement field; returns an empty map (never throws)
/// for malformed input so seek never crashes on a bad snapshot.
Map<String, String> squaresOfFen(String fen) {
  try {
    final placement = fen.trim().split(RegExp(r'\s+')).first;
    final rows = placement.split('/');
    if (rows.length != 8) return <String, String>{};
    final out = <String, String>{};
    for (var i = 0; i < 8; i++) {
      var file = 0;
      final row = rows[i];
      final rank = 7 - i;
      for (var j = 0; j < row.length && file < 8; j++) {
        final ch = row[j];
        final digit = int.tryParse(ch);
        if (digit != null) {
          file += digit;
          continue;
        }
        final upper = ch.toUpperCase();
        if ('PNBRQK'.contains(upper)) {
          final isWhite = ch == upper;
          out['${kFiles[file]}${rank + 1}'] = '${isWhite ? 'w' : 'b'}$upper';
        }
        file++;
      }
    }
    return out;
  } catch (_) {
    return <String, String>{};
  }
}

/// Renders a stored position payload as a [Chessboard] `squares` map.
///
/// Dispatches on shape: a payload starting with `{` is parsed as chaotic
/// [VariantBoard] JSON (`'e4' → 'wP'` via [colorCode] + the piece letter);
/// anything else goes through [squaresOfFen]. Never throws: malformed
/// variant JSON or FEN yields an empty map so replay views degrade to an
/// empty board instead of crashing.
Map<String, String> squaresOfPayload(String payload) {
  final trimmed = payload.trim();
  if (trimmed.startsWith('{')) {
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) return const <String, String>{};
      final board = VariantBoard.fromJson(Map<String, Object?>.from(decoded));
      return <String, String>{
        for (final entry in board.squares.entries)
          entry.key.name:
              '${colorCode(entry.value.color)}${entry.value.type.letter}',
      };
    } catch (_) {
      return const <String, String>{};
    }
  }
  return squaresOfFen(trimmed);
}

/// Legal UCIs for the side to move in [position] (the list
/// [GameOrchestrator.setPosition] requires before any turn may start).
List<String> legalUcis(Position position) {
  return <String>[for (final m in position.legalMoves()) m.uci];
}

/// King square to highlight when the side to move is in check, else null.
String? checkSquare(Position position) {
  if (!position.isInCheck(position.sideToMove)) return null;
  return position.kingSquare(position.sideToMove)?.name;
}

/// Advances an opaque FEN position by one UCI move.
///
/// This is the [PositionUpdater] every screen hands its orchestrator:
/// parse → apply (throws [StateError] on illegal input, which the
/// orchestrator converts to a `failed` state) → serialize. All turn
/// inputs are engine-legal by construction, so the throw path only fires
/// on programming errors.
String fenAdvance(String positionFen, String uci) {
  final position = parseFen(positionFen);
  position.apply(ChessMove.fromUci(uci));
  return position.toFen();
}
