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
/// Move animation (§15.2) is an explicit from→to motion layer driven by a
/// [BoardMove] passed through the [Chessboard.motion] parameter: when the
/// [squares] snapshot changes alongside a new transition, the moving piece
/// (plus a castling rook) slides from the origin to the destination over
/// ~160 ms (ease-out) in a separate `IgnorePointer` + `ExcludeSemantics`
/// overlay above the 64 stable square nodes. Captures fade the captured
/// glyph on its square, en passant fades it beside the destination, and
/// promotions swap the piece at the end of the slide. Interrupting a flight
/// retargets from the current visual position instead of jumping, and
/// reduced-motion builds (`MediaQuery.disableAnimations`) snap instead of
/// animating. Only the overlay layer rebuilds per frame — the 64 cells stay
/// static behind a `RepaintBoundary`.
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

import '../../chess/move.dart';
import '../../chess/piece.dart';
import '../../theme/board_theme.dart';
import '../../theme/piece_theme.dart';
import 'board_motion.dart';

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
    this.motion,
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

  /// Optional from→to transition to animate on the next [squares] change
  /// (§15.2 motion layer).
  ///
  /// When non-null and the snapshot changes, the board slides the moving
  /// piece over ~160 ms in an `IgnorePointer` + `ExcludeSemantics` overlay;
  /// see the library docs for capture/en-passant/castle/promotion handling.
  /// `null` keeps the board a static snapshot renderer (Arena mini-boards,
  /// settings previews). Hosts pass `null` while seeking so scrubbed
  /// snapshots snap instead of animating stale moves.
  final BoardMove? motion;

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

class _ChessboardState extends State<Chessboard>
    with TickerProviderStateMixin {
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

  /// In-flight move animation (§15.2 motion layer), or `null` when idle.
  _BoardFlight? _flight;

  /// Drives the §15.2 motion slide; reused (and retargeted) across flights.
  late final AnimationController _motionController;

  /// Curved (ease-out) view of the motion controller.
  late final Animation<double> _motionCurve;

  /// Cell size from the last laid-out frame, used to compute square centers
  /// and to retarget an interrupted flight from its current visual position.
  double _lastCell = 0;

  @override
  void initState() {
    super.initState();
    _motionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && _flight != null) {
          if (mounted) {
            setState(() => _flight = null);
          } else {
            _flight = null;
          }
        }
      });
    _motionCurve = CurvedAnimation(
      parent: _motionController,
      curve: Curves.easeOut,
    );
  }

  @override
  void didUpdateWidget(covariant Chessboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final motion = widget.motion;
    if (motion == null) return;
    if (motion == oldWidget.motion && widget.squares == oldWidget.squares) {
      return;
    }
    _startFlight(motion, oldWidget.squares);
  }

  @override
  void dispose() {
    _motionController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Begins (or retargets) the §15.2 sliding-piece animation for [move].
  ///
  /// Everything the overlay renders is derived from the old→new [squares]
  /// diff: the moving piece's raw value at [BoardMove.from], a fading
  /// captured glyph (at the destination, or beside it for en passant), a
  /// castling rook when the king moved two files with its rook shadowing,
  /// and the promotion swap that happens naturally at landing. Reduced-motion
  /// builds snap: the freshly-shipped snapshot already shows the final
  /// position, so no flight is created.
  void _startFlight(BoardMove move, Map<String, String> oldSquares) {
    final fromRaw = oldSquares[move.from.name];
    if (fromRaw == null || fromRaw.isEmpty) return;
    if (MediaQuery.disableAnimationsOf(context)) return;

    final from = move.from.name;
    final to = move.to.name;
    final fromPos = parseSquare(from);
    final toPos = parseSquare(to);
    if (fromPos == null || toPos == null) return;
    final fromFile = fromPos.$1;
    final fromRank = fromPos.$2;
    final toFile = toPos.$1;
    final movingGlyph = CellPiece.parse(fromRaw);
    final isKing = movingGlyph != null &&
        (fromRaw == 'wK' || fromRaw == 'bK');

    // A diff component is "the build-up": any retarget continues from the
    // current visual position rather than jumping back to the new origin.
    Offset? startForThis;
    final old = _flight;
    if (old != null && _motionController.isAnimating) {
      final t = _motionCurve.value;
      final oldToCenter = _squareCenter(old.to, _lastCell);
      startForThis = Offset.lerp(old.startOffset, oldToCenter, t);
    }

    String? capturedSquare;
    String? capturedRaw;
    final looksLikeEnPassant =
        move.flag == MoveFlag.enPassant ||
        (movingGlyph != null &&
            (fromRaw == 'wP' || fromRaw == 'bP') &&
            toFile != fromFile &&
            oldSquares[to] == null &&
            oldSquares[squareName(toFile, fromRank)] != null);
    if (looksLikeEnPassant) {
      capturedSquare = squareName(toFile, fromRank);
      capturedRaw = oldSquares[capturedSquare];
    } else if (oldSquares[to] != null) {
      capturedSquare = to;
      capturedRaw = oldSquares[to];
    }

    String? rookFrom;
    String? rookTo;
    String? rookRaw;
    if (isKing && (toFile - fromFile).abs() == 2) {
      final kingside = toFile > fromFile;
      final rFrom = squareName(kingside ? 7 : 0, fromRank);
      final rTo = squareName(kingside ? 5 : 3, fromRank);
      final rRaw = oldSquares[rFrom];
      if (rRaw != null &&
          widget.squares[rTo] == rRaw &&
          widget.squares[rFrom] == null) {
        rookFrom = rFrom;
        rookTo = rTo;
        rookRaw = rRaw;
      }
    }

    setState(() {
      _flight = _BoardFlight(
        from: from,
        to: to,
        fromRaw: fromRaw,
        startOffset: startForThis ?? _squareCenter(from, _lastCell),
        capturedSquare: capturedSquare,
        capturedRaw: capturedRaw,
        rookFrom: rookFrom,
        rookTo: rookTo,
        rookRaw: rookRaw,
      );
    });
    _motionController.forward(from: 0);
  }

  /// Center of [square] in board-local coordinates for the given cell size.
  Offset _squareCenter(String square, double cell) {
    final pos = parseSquare(square);
    if (pos == null) return Offset.zero;
    final displayCol = widget.orientationWhite ? pos.$1 : 7 - pos.$1;
    final displayRow = widget.orientationWhite ? 7 - pos.$2 : pos.$2;
    return Offset(
      (displayCol + 0.5) * cell,
      (displayRow + 0.5) * cell,
    );
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
        _lastCell = cell;
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
                      child: RepaintBoundary(
                        child: Stack(
                          children: <Widget>[
                            for (
                              var displayRow = 0;
                              displayRow < 8;
                              displayRow++
                            )
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
                            // §15.2 motion layer: the sliding piece (and any
                            // castling rook) live above the 64 cells. Only
                            // this subtree rebuilds per frame; the cells are
                            // static for the flight's duration. IgnorePointer
                            // + ExcludeSemantics keep hit testing and the AX
                            // tree identical to the idle board.
                            if (_flight != null)
                              Positioned.fill(
                                key: const ValueKey<String>(
                                  'chessboard-motion-overlay',
                                ),
                                child: IgnorePointer(
                                  child: ExcludeSemantics(
                                    child: RepaintBoundary(
                                      child: AnimatedBuilder(
                                        animation: _motionCurve,
                                        builder: (context, _) =>
                                            _buildFlightLayer(cell),
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
    final hiddenByFlight = _flight?.hides(square) ?? false;
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
              // During a §15.2 motion flight the destination (and a castling
              // rook's destination) keep their final glyph but stay
              // transparent — same key again, so landing restores them with
              // no switcher pop — while the switcher duration drops to zero
              // so the snap-to-hidden happens instantly beneath the sliding
              // overlay.
              AnimatedSwitcher(
                duration: _flight != null
                    ? Duration.zero
                    : const Duration(milliseconds: 160),
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: Tween<double>(begin: 0.6, end: 1).animate(animation),
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: piece == null
                    ? SizedBox(key: ValueKey<String>('empty-$square'))
                    : Center(
                        key: ValueKey<String>('piece-$square-$raw'),
                        child: Opacity(
                          opacity:
                              (_dragFrom == square || hiddenByFlight) ? 0 : 1,
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

  /// Builds the per-frame §15.2 overlay: the sliding moving piece, a
  /// castling rook, and a fading captured glyph (capture at the destination,
  /// en passant beside it).
  Widget _buildFlightLayer(double cell) {
    final flight = _flight!;
    final t = _motionCurve.value;
    final pieces = <Widget>[];
    final toCenter = _squareCenter(flight.to, cell);
    final pos = Offset.lerp(flight.startOffset, toCenter, t);
    if (pos != null) {
      pieces.add(
        _motionPiece('chessboard-motion-piece', flight.fromRaw, pos, cell),
      );
    }
    final rFrom = flight.rookFrom;
    final rTo = flight.rookTo;
    final rRaw = flight.rookRaw;
    if (rFrom != null && rTo != null && rRaw != null) {
      final rPos = Offset.lerp(
        _squareCenter(rFrom, cell),
        _squareCenter(rTo, cell),
        t,
      );
      if (rPos != null) {
        pieces.add(_motionPiece('chessboard-motion-rook', rRaw, rPos, cell));
      }
    }
    final cSquare = flight.capturedSquare;
    final cRaw = flight.capturedRaw;
    final capturedGlyph = CellPiece.parse(cRaw);
    if (cSquare != null && capturedGlyph != null) {
      final cCenter = _squareCenter(cSquare, cell);
      pieces.add(
        Positioned(
          key: const ValueKey<String>('chessboard-motion-captured'),
          left: cCenter.dx - cell / 2,
          top: cCenter.dy - cell / 2,
          width: cell,
          height: cell,
          child: Center(
            child: Opacity(
              opacity: 1 - t,
              child: Transform.scale(
                scale: 1 - 0.3 * t,
                child: _buildGlyph(capturedGlyph, cell),
              ),
            ),
          ),
        ),
      );
    }
    return Stack(children: pieces);
  }

  /// One flying glyph positioned by [center] with the lifted treatment.
  Widget _motionPiece(String key, String raw, Offset center, double cell) {
    final glyph = CellPiece.parse(raw);
    if (glyph == null) return const SizedBox.shrink();
    return Positioned(
      key: ValueKey<String>(key),
      left: center.dx - cell / 2,
      top: center.dy - cell / 2,
      width: cell,
      height: cell,
      child: Center(
        child: _buildGlyph(glyph, cell, lifted: true),
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

/// One in-flight §15.2 move transition.
///
/// All values are derived by [_ChessboardState._startFlight] from the
/// old→new squares diff; the overlay only consumes these, so the 64 cells
/// stay static for the whole flight.
class _BoardFlight {
  /// Creates a flight.
  _BoardFlight({
    required this.from,
    required this.to,
    required this.fromRaw,
    required this.startOffset,
    this.capturedSquare,
    this.capturedRaw,
    this.rookFrom,
    this.rookTo,
    this.rookRaw,
  });

  /// Origin square (the piece's start in the old snapshot).
  final String from;

  /// Destination square.
  final String to;

  /// Raw value of the moving piece (from the old snapshot).
  final String fromRaw;

  /// Board-local position the slide starts from — the origin square center,
  /// or the interrupted flight's current visual position on a retarget.
  final Offset startOffset;

  /// Square where a captured glyph fades (destination for captures, beside
  /// it for en passant), or `null`.
  final String? capturedSquare;

  /// Raw value of the fading captured piece.
  final String? capturedRaw;

  /// Castling rook origin square, or `null`.
  final String? rookFrom;

  /// Castling rook destination square, or `null`.
  final String? rookTo;

  /// Raw value of the castling rook.
  final String? rookRaw;

  /// Whether [square] must hide its static glyph during this flight (the
  /// destination, and a castling rook's destination).
  bool hides(String square) =>
      square == to || (rookTo != null && square == rookTo);
}
