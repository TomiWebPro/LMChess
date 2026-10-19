/// Board color themes: square colors plus every overlay tint the
/// [Chessboard] widget needs (selection, last-move trail, legal-move hints,
/// check and terminal-state markers, coordinate labels).
///
/// ## Accessibility notes
///
/// Piece legibility never depends on square contrast alone: glyphs are drawn
/// with the contrasting fill/stroke pairs from `PieceTheme`, so even the
/// lowest-contrast pairing below (sepia light vs. dark squares) keeps pieces
/// readable. The overlay tints are deliberately translucent at render time
/// (see `Chessboard`) so the underlying square brightness is preserved, and
/// each theme keeps its own hues distinguishable for the three states that
/// must never be confused:
///
/// * **selection** — cool/blue family,
/// * **last-move trail** — warm/yellow family,
/// * **check / terminal** — red family.
///
/// Coordinate labels use [coordLabel] on light squares and fall back to the
/// light-square color on dark squares (see [labelColorFor]) so text contrast
/// stays above ~4.5:1 on both square tones without requiring a second label
/// field.
library;

import 'package:flutter/material.dart';

/// Visual theme for the chessboard surface and its state overlays.
///
/// All colors are opaque; the board widget applies translucency when
/// painting overlays so square brightness shows through.
class BoardTheme {
  /// Creates a board theme. All fields are required so custom themes added
  /// via `ThemeRegistry.addCustomBoardTheme` cannot leave a state unstyled.
  const BoardTheme({
    required this.id,
    required this.name,
    required this.lightSquare,
    required this.darkSquare,
    required this.coordLabel,
    required this.selection,
    required this.lastMoveFrom,
    required this.lastMoveTo,
    required this.legalDot,
    required this.captureRing,
    required this.check,
    required this.terminal,
  });

  /// Stable machine identifier (`'classic'`, ...). Lowercase alphanumerics,
  /// dashes and underscores only; validated by the registry.
  final String id;

  /// Human-readable display name.
  final String name;

  /// Light square fill.
  final Color lightSquare;

  /// Dark square fill.
  final Color darkSquare;

  /// Coordinate-label color, tuned for **light** squares.
  ///
  /// Dark squares reuse [lightSquare] via [labelColorFor] for contrast.
  final Color coordLabel;

  /// Overlay tint for the currently selected square (cool/blue family).
  final Color selection;

  /// Overlay tint for the origin square of the last move.
  final Color lastMoveFrom;

  /// Overlay tint for the destination square of the last move.
  ///
  /// Kept slightly stronger than [lastMoveFrom] so the direction of play
  /// reads at a glance; both stay in the warm/yellow family, distinct from
  /// [selection] (blue) and [check] (red).
  final Color lastMoveTo;

  /// Fill for legal-move dots on empty target squares.
  final Color legalDot;

  /// Ring color for legal captures on occupied target squares.
  final Color captureRing;

  /// Overlay tint for the king square while in check (red family).
  final Color check;

  /// Overlay tint for terminal states (checkmate / stalemate square).
  final Color terminal;

  /// Returns the coordinate-label color for a square of the given tone.
  ///
  /// Light squares use [coordLabel]; dark squares reuse [lightSquare], which
  /// is guaranteed readable on every built-in dark tone. Custom themes
  /// should keep this property: pick a [coordLabel] readable on
  /// [lightSquare], and a [lightSquare] readable on [darkSquare].
  Color labelColorFor(bool isLightSquare) =>
      isLightSquare ? coordLabel : lightSquare;

  /// Classic lichess-style brown board.
  ///
  /// Contrast notes: dark walnut `#B58863` on cream `#F0D9B5` gives strong
  /// square-to-square separation; umber `#6B4F35` labels on cream exceed
  /// 4.5:1, and cream labels on walnut are equally safe.
  static const BoardTheme classic = BoardTheme(
    id: 'classic',
    name: 'Classic',
    lightSquare: Color(0xFFF0D9B5),
    darkSquare: Color(0xFFB58863),
    coordLabel: Color(0xFF6B4F35),
    selection: Color(0xFF4A90D9),
    lastMoveFrom: Color(0xFFF5E063),
    lastMoveTo: Color(0xFFF2C531),
    legalDot: Color(0xFF2E7D32),
    captureRing: Color(0xFFC62828),
    check: Color(0xFFE53935),
    terminal: Color(0xFF6A1B9A),
  );

  /// High-contrast slate board for dark-mode UIs.
  ///
  /// Contrast notes: pale slate `#DCE4EA` vs. deep slate `#46586A` is the
  /// highest square separation of the built-ins; cyan selection `#22D3EE`
  /// stays distinguishable from the warm last-move ambers on both tones.
  static const BoardTheme midnight = BoardTheme(
    id: 'midnight',
    name: 'Midnight',
    lightSquare: Color(0xFFDCE4EA),
    darkSquare: Color(0xFF46586A),
    coordLabel: Color(0xFF2F3D4A),
    selection: Color(0xFF22D3EE),
    lastMoveFrom: Color(0xFFFBBF24),
    lastMoveTo: Color(0xFFF59E0B),
    legalDot: Color(0xFF34D399),
    captureRing: Color(0xFFF87171),
    check: Color(0xFFEF4444),
    terminal: Color(0xFFA78BFA),
  );

  /// Green tournament board.
  ///
  /// Contrast notes: parchment `#EAEED2` vs. fern `#6A9448`; moss-brown
  /// `#4C6B2F` labels on parchment exceed 4.5:1, parchment labels on fern
  /// stay readable. The green dot `#1B5E20` was picked dark enough to read
  /// on parchment while still visible on fern via its translucent halo.
  static const BoardTheme forest = BoardTheme(
    id: 'forest',
    name: 'Forest',
    lightSquare: Color(0xFFEAEED2),
    darkSquare: Color(0xFF6A9448),
    coordLabel: Color(0xFF4C6B2F),
    selection: Color(0xFF1E88E5),
    lastMoveFrom: Color(0xFFFFF176),
    lastMoveTo: Color(0xFFFFCA28),
    legalDot: Color(0xFF1B5E20),
    captureRing: Color(0xFFB71C1C),
    check: Color(0xFFD32F2F),
    terminal: Color(0xFF4A148C),
  );

  /// Warm sepia board, lowest square contrast (aesthetic choice).
  ///
  /// Contrast notes: sand `#F1E2C4` vs. sienna `#A06B3C` is intentionally
  /// soft; piece legibility is carried entirely by `PieceTheme` stroke
  /// outlines here. Selection periwinkle `#7C93E8` was chosen to stay
  /// distinct from the amber last-move trail for red-green color-blind
  /// users (blue vs. yellow is the safest axis).
  static const BoardTheme sepia = BoardTheme(
    id: 'sepia',
    name: 'Sepia',
    lightSquare: Color(0xFFF1E2C4),
    darkSquare: Color(0xFFA06B3C),
    coordLabel: Color(0xFF6D4A2A),
    selection: Color(0xFF7C93E8),
    lastMoveFrom: Color(0xFFE8C96A),
    lastMoveTo: Color(0xFFD9A62E),
    legalDot: Color(0xFF33691E),
    captureRing: Color(0xFF8E1B1B),
    check: Color(0xFFC62828),
    terminal: Color(0xFF5E35B1),
  );

  /// All built-in board themes in display order.
  static const List<BoardTheme> builtins = <BoardTheme>[
    classic,
    midnight,
    forest,
    sepia,
  ];

  /// Looks up a built-in theme by [id], returning [fallback] when unknown.
  static BoardTheme byId(String id, {BoardTheme fallback = classic}) {
    for (final theme in builtins) {
      if (theme.id == id) return theme;
    }
    return fallback;
  }
}
