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
/// Drag and drop (§15.1) is additive to the click-click tap path. A pan that
/// starts on a draggable square taps it through [onTapSquare] (selecting an
/// own piece through the host screen's existing rules), draws a lifted piece
/// overlay, highlights the hovered square, and on drop over a [legalTargets]
/// square calls [onMoveAttempt] — or, when that callback is absent, taps the
/// destination through [onTapSquare]. The 64 per-square semantics nodes are
/// untouched: the drag layer is `IgnorePointer` + `ExcludeSemantics`, so
/// screen readers keep the same tap actions. Escape, a secondary-button
/// press, or releasing outside the board cancels the drag without a move.
///
/// Highlight precedence (first match wins): `inCheck` → `terminalSquare` →
/// [selected] → `lastFrom` → `lastTo`. Selection (blue family) is therefore
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
/// [variantBadges] (square → short label such as `❄` frozen or `💣` volatile),
/// rendered as corner chips so they never collide with glyphs.
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
/// precedence, drag-and-drop, and the [squares] encoding contract.
class Chessboard extends StatefulWidget {
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
    this.onMoveAttempt,
    this.canDragSquare,
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

  /// Called when a drag ends on a legal destination: `(from, to)`.
  ///
  /// Only fires when [legalTargets] contains the drop square. When `null`,
  /// the board falls back to [onTapSquare] on the destination so hosts that
  /// already implement click-click moves get drag support for free.
  final void Function(String from, String to)? onMoveAttempt;

  /// Optional filter deciding which squares may start a drag.
  ///
  /// Drag is additive to the tap path, so the board does not know which side
  /// the human controls. Hosts pass a predicate (for example “white piece
  /// only”); `null` treats every occupied square as draggable.
  final bool Function(String square)? canDragSquare;

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
  State<Chessboard> createState() => _ChessboardState();
}

class _ChessboardState extends State<Chessboard> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'chessboard-drag');

  /// Origin square of the in-flight drag, or `null` when not dragging.
  String? _dragFrom;

  /// Square currently under the dragged piece.
  String? _dragOver;

  /// Pointer position in board-local coordinates while dragging.
  Offset? _dragPointer;

  /// Pointer-down position and square, used to detect the drag threshold.
  Offset? _pressPosition;
  String? _pressSquare;

  bool get _dragging => _dragFrom != null;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

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
        final canDrag = widget.interactive && widget.onTapSquare != null;
        final dragPiece = _dragFrom == null
            ? null
            : CellPiece.parse(widget.squares[_dragFrom]);
        return Focus(
          focusNode: _focusNode,
          canRequestFocus: canDrag,
          skipTraversal: true,
          onKeyEvent: _handleKeyEvent,
          child: Center(
            child: SizedBox(
              width: size,
              height: size,
              child: MouseRegion(
                cursor: _dragging
                    ? SystemMouseCursors.grabbing
                    : (canDrag ? SystemMouseCursors.grab : MouseCursor.defer),
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (event) => _handlePointerDown(event, size),
                  onPointerMove: (event) => _handlePointerMove(event, size),
                  onPointerUp: (event) => _handlePointerUp(event, size),
                  onPointerCancel: (_) => _cancelDrag(),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: kElevationToShadow[4],
                      color: widget.boardTheme.darkSquare,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        children: <Widget>[
                          for (var displayRow = 0; displayRow < 8; displayRow++)
                            for (
                              var displayCol = 0;
                              displayCol < 8;
                              displayCol++
                            )
                              _buildCell(displayRow, displayCol, cell),
                          // Lifted piece follows the pointer. IgnorePointer +
                          // ExcludeSemantics keep the drag purely visual so
                          // neither hit testing nor the 64 square semantics
                          // nodes change mid-gesture.
                          if (_dragging &&
                              dragPiece != null &&
                              _dragPointer != null)
                            Positioned(
                              key: const ValueKey<String>(
                                'chessboard-drag-overlay',
                              ),
                              left: _dragPointer!.dx - cell / 2,
                              top: _dragPointer!.dy - cell / 2,
                              width: cell,
                              height: cell,
                              child: IgnorePointer(
                                child: ExcludeSemantics(
                                  child: Transform.scale(
                                    scale: 1.08,
                                    child: Center(
                                      child: _buildGlyph(
                                        dragPiece,
                                        cell,
                                        lifted: true,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
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
    final file = widget.orientationWhite ? displayCol : 7 - displayCol;
    final rank = widget.orientationWhite ? 7 - displayRow : displayRow;
    final square = squareName(file, rank);
    final isLight = (file + rank).isOdd;

    final base = isLight
        ? widget.boardTheme.lightSquare
        : widget.boardTheme.darkSquare;
    final overlay = _overlayFor(square);
    final raw = widget.squares[square];
    final piece = CellPiece.parse(raw);
    final isTarget = widget.legalTargets.contains(square);
    final isDragOver = _dragging && _dragOver == square;
    final badge = widget.variantBadges[square];
    final labelColor = widget.boardTheme.labelColorFor(isLight);
    final canTap = widget.interactive && widget.onTapSquare != null;

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
        onTap: canTap ? () => widget.onTapSquare!(square) : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: canTap ? () => widget.onTapSquare!(square) : null,
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
              if (isDragOver)
                Container(
                  key: ValueKey<String>('drag-hover-$square'),
                  decoration: BoxDecoration(
                    color: widget.boardTheme.captureRing.withValues(
                      alpha: 0.18,
                    ),
                    border: Border.all(
                      color: widget.boardTheme.captureRing.withValues(
                        alpha: 0.9,
                      ),
                      width: math.max(2, cell * 0.04),
                    ),
                  ),
                ),
              if (isTarget && piece == null)
                Center(
                  child: Container(
                    width: cell * 0.28,
                    height: cell * 0.28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.boardTheme.legalDot.withValues(alpha: 0.85),
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
                        color: widget.boardTheme.captureRing.withValues(
                          alpha: 0.9,
                        ),
                        width: math.max(2, cell * 0.05),
                      ),
                    ),
                  ),
                ),
              // Piece glyph with move-animation: keyed by content so any
              // arrival/departure scales + fades over 160ms. While a drag is
              // in flight the source glyph is transparent (same key, so the
              // visual snaps back without a spurious switcher transition).
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
                        child: Opacity(
                          opacity: _dragFrom == square ? 0 : 1,
                          child: _buildGlyph(piece, cell),
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
              if (widget.showCoordinates) ...<Widget>[
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

  /// Renders one piece glyph with the theme fill/stroke treatment.
  Widget _buildGlyph(CellPiece piece, double cell, {bool lifted = false}) {
    return Text(
      piece.glyph,
      style: TextStyle(
        fontFamily: widget.pieceTheme.fontFamily,
        fontSize: cell * 0.72,
        height: 1,
        color: piece.isWhite
            ? widget.pieceTheme.whiteFill
            : widget.pieceTheme.blackFill,
        // Simulated outline via offset shadows in the stroke color; cheap and
        // asset-free. A lifted piece adds one soft drop shadow.
        shadows: <Shadow>[
          for (final dx in <double>[-1, 1])
            for (final dy in <double>[-1, 1])
              Shadow(
                offset: Offset(dx * cell * 0.025, dy * cell * 0.025),
                blurRadius: cell * 0.015,
                color: piece.isWhite
                    ? widget.pieceTheme.whiteStroke
                    : widget.pieceTheme.blackStroke,
              ),
          if (lifted)
            Shadow(
              offset: Offset(0, cell * 0.05),
              blurRadius: cell * 0.12,
              color: Colors.black.withValues(alpha: 0.45),
            ),
        ],
      ),
    );
  }

  /// Handles a pointer-down: remembers the press for tap-vs-drag detection
  /// and treats a secondary-button press as “cancel the current drag”.
  void _handlePointerDown(PointerDownEvent event, double size) {
    if ((event.buttons & kSecondaryButton) != 0) {
      _cancelDrag();
      return;
    }
    _pressPosition = event.localPosition;
    _pressSquare = _squareAt(event.localPosition, size);
  }

  /// Starts a drag once the pointer travels past [kTouchSlop], then tracks the
  /// hovered square and lifted piece position for every subsequent move.
  void _handlePointerMove(PointerMoveEvent event, double size) {
    if (_dragging) {
      setState(() {
        _dragPointer = event.localPosition;
        _dragOver = _squareAt(event.localPosition, size);
      });
      return;
    }
    final press = _pressSquare;
    final start = _pressPosition;
    if (press == null || start == null) return;
    if ((event.localPosition - start).distance < kTouchSlop) return;
    _startDrag(press, event.localPosition, size);
  }

  /// Begins a drag from [from] at [position].
  ///
  /// The host is notified through [Chessboard.onTapSquare] so its existing
  /// selection/legal-target logic runs unchanged. Squares that are already
  /// legal targets are left to the tap path: tapping a target must keep
  /// performing the click-click move.
  void _startDrag(String from, Offset position, double size) {
    _pressPosition = null;
    _pressSquare = null;
    if (!widget.interactive || widget.onTapSquare == null) return;
    if (widget.legalTargets.contains(from)) return;
    if (CellPiece.parse(widget.squares[from]) == null) return;
    final canDrag = widget.canDragSquare;
    if (canDrag != null && !canDrag(from)) return;
    setState(() {
      _dragFrom = from;
      _dragPointer = position;
      _dragOver = _squareAt(position, size);
    });
    _focusNode.requestFocus();
    if (widget.selected != from) widget.onTapSquare!.call(from);
  }

  /// Completes a drag: a legal drop calls [Chessboard.onMoveAttempt] (or the
  /// click-click fallback), everything else snaps back without a move.
  void _handlePointerUp(PointerUpEvent event, double size) {
    _pressPosition = null;
    _pressSquare = null;
    final from = _dragFrom;
    if (from == null) return;
    final to = _squareAt(event.localPosition, size);
    final isLegal = to != null && widget.legalTargets.contains(to);
    setState(() {
      _dragFrom = null;
      _dragOver = null;
      _dragPointer = null;
    });
    if (!isLegal) return;
    final attempt = widget.onMoveAttempt;
    if (attempt != null) {
      attempt(from, to);
    } else {
      widget.onTapSquare?.call(to);
    }
  }

  /// Cancels the in-flight drag without a move (Esc, right-click, pointer
  /// cancellation).
  void _cancelDrag() {
    if (!_dragging) return;
    setState(() {
      _dragFrom = null;
      _dragOver = null;
      _dragPointer = null;
      _pressPosition = null;
      _pressSquare = null;
    });
  }

  /// Escape aborts a drag while the board owns focus.
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        _dragging) {
      _cancelDrag();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Maps a board-local pointer position to a square, honoring orientation.
  ///
  /// Returns `null` when the pointer is outside the board bounds (drop
  /// outside / drag cancel).
  String? _squareAt(Offset position, double size) {
    if (position.dx < 0 ||
        position.dy < 0 ||
        position.dx >= size ||
        position.dy >= size) {
      return null;
    }
    final cell = size / 8;
    final displayCol = (position.dx / cell).floor().clamp(0, 7);
    final displayRow = (position.dy / cell).floor().clamp(0, 7);
    final file = widget.orientationWhite ? displayCol : 7 - displayCol;
    final rank = widget.orientationWhite ? 7 - displayRow : displayRow;
    return squareName(file, rank);
  }

  /// Overlay color for [square] following highlight precedence:
  /// check → terminal → selection → last-move trail.
  Color? _overlayFor(String square) {
    if (widget.inCheck != null && square == widget.inCheck) {
      return widget.boardTheme.check;
    }
    if (widget.terminalSquare != null && square == widget.terminalSquare) {
      return widget.boardTheme.terminal;
    }
    if (widget.selected != null && square == widget.selected) {
      return widget.boardTheme.selection;
    }
    if (widget.lastFrom != null && square == widget.lastFrom) {
      return widget.boardTheme.lastMoveFrom;
    }
    if (widget.lastTo != null && square == widget.lastTo) {
      return widget.boardTheme.lastMoveTo;
    }
    return null;
  }

  /// Screen-reader label for a square.
  String _semanticLabel(String square, String? raw) {
    final piece = CellPiece.parse(raw);
    if (piece == null) return 'Empty square $square';
    return '${piece.isWhite ? 'White' : 'Black'} piece on $square';
  }
}
