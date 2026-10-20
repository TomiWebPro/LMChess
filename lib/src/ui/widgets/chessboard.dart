/// [Chessboard]: the custom 8×8 board widget for standard and variant games.
///
/// Rendering strategy: a `LayoutBuilder`-driven square area (responsive —
/// it fills the incoming width, clamped by height when bounded, with a 320px
/// fallback for unbounded constraints such as scroll views) containing 64
/// absolutely-positioned cells. Each cell is a `GestureDetector` + layered
/// `Container`s for the square color, state overlays, legal-move hints,
/// coordinate labels, variant badges and the piece glyph.
///
/// Move animation: every square wraps its piece in an [AnimatedSwitcher]
/// keyed by the cell content, so arrivals scale/fade in over 160ms. (An
/// [AnimatedPositioned]-based sliding layer is a drop-in alternative once the
/// engine streams explicit from→to moves; the keyed switcher was chosen
/// because the widget only observes square snapshots.)
///
/// Highlight precedence (first match wins): `inCheck` → `terminalSquare` →
/// [selected] → [lastFrom] → [lastTo]. Selection (blue family) is therefore
/// never confused with the last-move trail (amber family) or check (red),
/// matching the [BoardTheme] accessibility contract.
///
/// Cell value encoding: each entry of [squares] is either
///
/// * a single Unicode glyph (`♚`…`♟` for black, `♔`…`♙` for white), or
/// * a two-character code `'wK'…'bP'` (side + `KQRBNP` letter), e.g. from
///   [Piece.code].
///
/// Variant boards reuse the same 8×8 geometry; chaotic mutations surface via
/// [variantBadges] (square → short label such as `❄` frozen or `💣`
/// volatile), rendered as corner chips so they never collide with glyphs.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../chess/piece.dart';
import '../../theme/board_theme.dart';
import '../../theme/piece_theme.dart';

/// The 64 glyphs the board recognizes, mapping glyph → (glyph, isWhite).
///
/// Both outline (`♔`…`♙`) and filled (`♚`…`♟`) blocks are accepted; filled
/// glyphs always mean black, outline glyphs always mean white.
const Map<String, bool> _glyphSides = <String, bool>{
  '♚': false,
  '♛': false,
  '♜': false,
  '♝': false,
  '♞': false,
  '♟': false,
  '♔': true,
  '♕': true,
  '♖': true,
  '♗': true,
  '♘': true,
  '♙': true,
};

/// Parsed content of one board cell: the glyph to draw and its side.
class CellPiece {
  /// Creates a parsed cell value.
  const CellPiece({required this.glyph, required this.isWhite});

  /// Glyph to render (normalized to the filled variant for consistency).
  final String glyph;

  /// `true` for white pieces.
  final bool isWhite;

  /// Parses a raw [Chessboard.squares] value.
  ///
  /// Accepts single glyphs (side inferred from the Unicode block) and
  /// two-character codes (`'wK'`, `'bP'`, ...). Returns `null` for empty or
  /// unrecognized input, which the board renders as an empty square.
  static CellPiece? parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (raw.length == 1) {
      final side = _glyphSides[raw];
      if (side == null) return null;
      return CellPiece(glyph: raw, isWhite: side);
    }
    if (raw.length == 2) {
      final sideChar = raw[0].toLowerCase();
      final type = PieceTypeX.fromLetter(raw[1]);
      if ((sideChar != 'w' && sideChar != 'b') || type == null) return null;
      return CellPiece(
        glyph: PieceTheme.glyphFor(type),
        isWhite: sideChar == 'w',
      );
    }
    return null;
  }
}

/// Interactive chessboard for 8×8 standard and variant games.
///
/// See the library docs above for rendering, animation, highlight
/// precedence, and the [squares] encoding contract.
class Chessboard extends StatelessWidget {
  /// Creates a chessboard.
  const Chessboard({
    super.key,
    required this.squares,
    this.orientationWhite = true,
    this.selected,
    this.lastFrom,
    this.lastTo,
    this.legalTargets = const <String>[],
    this.inCheck,
    this.terminalSquare,
    this.onTapSquare,
    required this.boardTheme,
    required this.pieceTheme,
    this.variantBadges = const <String, String>{},
    this.interactive = true,
    this.showCoordinates = true,
  });

  /// Square → raw piece value (glyph or two-char code). Missing keys and
  /// unparseable values render as empty squares.
  final Map<String, String> squares;

  /// `true` shows White at the bottom; `false` flips to Black's view.
  final bool orientationWhite;

  /// Currently selected square (selection/blue highlight), if any.
  final String? selected;

  /// Origin square of the last move (amber trail, weaker end).
  final String? lastFrom;

  /// Destination square of the last move (amber trail, stronger end).
  final String? lastTo;

  /// Legal destinations for the selected piece: dots on empty squares,
  /// capture rings on occupied ones.
  final List<String> legalTargets;

  /// King square to mark as in check (red overlay). Takes precedence over
  /// selection and last-move highlights.
  final String? inCheck;

  /// Square marking a terminal state (checkmate/stalemate king square,
  /// purple overlay). Extension prop beyond the base spec; `null` disables.
  final String? terminalSquare;

  /// Called with the tapped square name (`'e4'`). `null` disables taps
  /// (same as [interactive] `false`); used for mini/preview boards.
  final ValueChanged<String>? onTapSquare;

  /// Board colors and overlay tints.
  final BoardTheme boardTheme;

  /// Piece glyph colors.
  final PieceTheme pieceTheme;

  /// Variant mutation badges: square → short label (`❄`, `💣`, ...).
  final Map<String, String> variantBadges;

  /// Master tap switch; `false` renders a non-interactive board.
  final bool interactive;

  /// Whether to draw file/rank coordinate labels on the rim squares.
  final bool showCoordinates;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Responsive square sizing: fill the width, clamp by bounded height
        // (e.g. side-by-side layouts), fall back to 320px when unbounded
        // (scroll views, dialogs) so the board never collapses or explodes.
        double size = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 320;
        if (constraints.maxHeight.isFinite) {
          size = math.min(size, constraints.maxHeight);
        }
        size = math.max(size, 120);
        final cell = size / 8;
        return Center(
          child: SizedBox(
            width: size,
            height: size,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: kElevationToShadow[4],
                color: boardTheme.darkSquare,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  children: <Widget>[
                    for (var displayRow = 0; displayRow < 8; displayRow++)
                      for (var displayCol = 0; displayCol < 8; displayCol++)
                        _buildCell(displayRow, displayCol, cell),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Builds one absolutely-positioned cell for display coordinates.
  Widget _buildCell(int displayRow, int displayCol, double cell) {
    // Map display position back to logical file/rank honoring orientation.
    final file = orientationWhite ? displayCol : 7 - displayCol;
    final rank = orientationWhite ? 7 - displayRow : displayRow;
    final square = squareName(file, rank);
    final isLight = (file + rank).isOdd;

    final base = isLight ? boardTheme.lightSquare : boardTheme.darkSquare;
    final overlay = _overlayFor(square);
    final raw = squares[square];
    final piece = CellPiece.parse(raw);
    final isTarget = legalTargets.contains(square);
    final badge = variantBadges[square];
    final labelColor = boardTheme.labelColorFor(isLight);
    final canTap = interactive && onTapSquare != null;

    return Positioned(
      left: displayCol * cell,
      top: displayRow * cell,
      width: cell,
      height: cell,
      // One real semantics node per square. `container` keeps the 64 cells
      // from collapsing into a single ancestor node, while `excludeSemantics`
      // hides the piece glyph / coordinate labels — so the per-cell
      // AnimatedSwitcher can animate without adding or removing semantics
      // nodes mid-frame (which produced engine AXTree deserialization
      // errors). The tap action is declared here so it survives the
      // descendant exclusion.
      child: Semantics(
        container: true,
        excludeSemantics: true,
        button: canTap,
        label: _semanticLabel(square, raw),
        onTap: canTap ? () => onTapSquare!(square) : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: canTap ? () => onTapSquare!(square) : null,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Container(color: base),
              if (overlay != null)
                Container(
                  // Translucent so the square tone shows through; keeps the
                  // blue/amber/red families distinguishable per the theme
                  // accessibility contract.
                  color: overlay.withValues(alpha: 0.55),
                ),
              if (isTarget && piece == null)
                Center(
                  child: Container(
                    width: cell * 0.28,
                    height: cell * 0.28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: boardTheme.legalDot.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              if (isTarget && piece != null)
                Center(
                  child: Container(
                    width: cell * 0.92,
                    height: cell * 0.92,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: boardTheme.captureRing.withValues(alpha: 0.9),
                        width: math.max(2, cell * 0.05),
                      ),
                    ),
                  ),
                ),
              // Piece glyph with move-animation: keyed by content so any
              // arrival/departure scales + fades over 160ms.
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: Tween<double>(begin: 0.6, end: 1).animate(animation),
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: piece == null
                    ? SizedBox(key: ValueKey<String>('empty-$square'))
                    : Center(
                        key: ValueKey<String>('piece-$square-$raw'),
                        child: Text(
                          piece.glyph,
                          style: TextStyle(
                            fontFamily: pieceTheme.fontFamily,
                            fontSize: cell * 0.72,
                            height: 1,
                            color: piece.isWhite
                                ? pieceTheme.whiteFill
                                : pieceTheme.blackFill,
                            // Simulated outline via offset shadows in the
                            // stroke color; cheap and asset-free.
                            shadows: <Shadow>[
                              for (final dx in <double>[-1, 1])
                                for (final dy in <double>[-1, 1])
                                  Shadow(
                                    offset: Offset(
                                      dx * cell * 0.025,
                                      dy * cell * 0.025,
                                    ),
                                    blurRadius: cell * 0.015,
                                    color: piece.isWhite
                                        ? pieceTheme.whiteStroke
                                        : pieceTheme.blackStroke,
                                  ),
                            ],
                          ),
                        ),
                      ),
              ),
              if (badge != null)
                Positioned(
                  right: cell * 0.04,
                  top: cell * 0.04,
                  child: Container(
                    padding: EdgeInsets.all(cell * 0.03),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(cell * 0.08),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(fontSize: cell * 0.2, height: 1),
                    ),
                  ),
                ),
              if (showCoordinates) ...<Widget>[
                // Rank numbers down the left edge (top of each cell).
                if (displayCol == 0)
                  Positioned(
                    left: cell * 0.06,
                    top: cell * 0.04,
                    child: Text(
                      '${rank + 1}',
                      style: TextStyle(
                        color: labelColor,
                        fontSize: cell * 0.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                // File letters along the bottom edge (right of each cell).
                if (displayRow == 7)
                  Positioned(
                    right: cell * 0.08,
                    bottom: cell * 0.04,
                    child: Text(
                      kFiles[file],
                      style: TextStyle(
                        color: labelColor,
                        fontSize: cell * 0.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Overlay color for [square] following highlight precedence:
  /// check → terminal → selection → last-move trail.
  Color? _overlayFor(String square) {
    if (inCheck != null && square == inCheck) return boardTheme.check;
    if (terminalSquare != null && square == terminalSquare) {
      return boardTheme.terminal;
    }
    if (selected != null && square == selected) return boardTheme.selection;
    if (lastFrom != null && square == lastFrom) return boardTheme.lastMoveFrom;
    if (lastTo != null && square == lastTo) return boardTheme.lastMoveTo;
    return null;
  }

  /// Screen-reader label for a square.
  String _semanticLabel(String square, String? raw) {
    final piece = CellPiece.parse(raw);
    if (piece == null) return 'Empty square $square';
    return '${piece.isWhite ? 'White' : 'Black'} piece on $square';
  }
}
