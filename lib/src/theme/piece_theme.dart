/// Piece glyph themes: which Unicode chess glyph to draw and, more
/// importantly, which fill/stroke color pairs make white vs. black pieces
/// legible on every [BoardTheme].
///
/// No image assets are needed: pieces render as text glyphs from the
/// platform font (see [PieceTheme.fontFamily]), so a "piece theme" is purely
/// a glyph style + color recipe. The widget always draws the *filled* glyph
/// variants (`♚`…`♟`, U+265A…U+265F) and distinguishes sides by color, which
/// keeps rendering identical across platforms that may lack the outline
/// (`♔`…`♙`) code points in some fonts.
library;

import 'package:flutter/material.dart';

import '../chess/piece.dart';

/// Visual theme for chess pieces: fill/stroke color pairs per side.
///
/// White pieces are drawn as light fills with dark strokes; black pieces as
/// dark fills with light strokes. Every built-in keeps the stroke-to-fill
/// contrast high so pieces stay legible on both light and dark squares of
/// every [BoardTheme], including the low-contrast sepia board.
class PieceTheme {
  /// Creates a piece theme.
  const PieceTheme({
    required this.id,
    required this.name,
    required this.whiteFill,
    required this.whiteStroke,
    required this.blackFill,
    required this.blackStroke,
    this.fontFamily,
  });

  /// Stable machine identifier. Validated by the registry.
  final String id;

  /// Human-readable display name.
  final String name;

  /// Fill color for white pieces (near-white in all built-ins).
  final Color whiteFill;

  /// Stroke/outline color for white pieces (near-black in all built-ins).
  final Color whiteStroke;

  /// Fill color for black pieces (near-black in all built-ins).
  final Color blackFill;

  /// Stroke/outline color for black pieces (light, for dark squares).
  final Color blackStroke;

  /// Optional font family used to render glyphs.
  ///
  /// `null` (the default) uses the platform's default font, which reliably
  /// contains the chess glyph block on Android, iOS, desktop and web.
  /// Set this only to a font known to include U+265A–U+265F.
  final String? fontFamily;

  /// Fill color for [color]'s pieces.
  Color fillFor(PieceColor color) => color.isWhite ? whiteFill : blackFill;

  /// Stroke color for [color]'s pieces.
  Color strokeFor(PieceColor color) =>
      color.isWhite ? whiteStroke : blackStroke;

  /// Returns the Unicode glyph for [type].
  ///
  /// Always the filled ("black") variant — `♚ ♛ ♜ ♝ ♞ ♟` — because side is
  /// conveyed by [fillFor]/[strokeFor] colors instead. This guarantees every
  /// platform renders the same shapes even when its font lacks the outline
  /// (`♔`…`♙`) code points.
  static String glyphFor(PieceType type) => switch (type) {
    PieceType.king => '♚',
    PieceType.queen => '♛',
    PieceType.rook => '♜',
    PieceType.bishop => '♝',
    PieceType.knight => '♞',
    PieceType.pawn => '♟',
  };

  /// Meridian: crisp near-black outlines, the default tournament look.
  ///
  /// Pure-white fills with `#1A1A1A` strokes (white) and `#111111` fills
  /// with soft `#E8E8E8` strokes (black): maximum contrast on all boards.
  static const PieceTheme meridian = PieceTheme(
    id: 'meridian',
    name: 'Meridian',
    whiteFill: Color(0xFFFFFFFF),
    whiteStroke: Color(0xFF1A1A1A),
    blackFill: Color(0xFF111111),
    blackStroke: Color(0xFFE8E8E8),
  );

  /// Alpha: softer charcoal pieces for a calmer board.
  ///
  /// Ivory `#FAF7EF` fills with warm umber strokes (white) and charcoal
  /// `#2B2B2E` fills with silver strokes (black). Slightly lower contrast
  /// than Meridian by design; still safe on every built-in board.
  static const PieceTheme alpha = PieceTheme(
    id: 'alpha',
    name: 'Alpha',
    whiteFill: Color(0xFFFAF7EF),
    whiteStroke: Color(0xFF4A3B2A),
    blackFill: Color(0xFF2B2B2E),
    blackStroke: Color(0xFFC9C9D1),
  );

  /// Flat: solid silhouette pieces with no visible outline.
  ///
  /// Stroke colors equal their fills, producing pure glyph silhouettes.
  /// Highest color-block contrast, but relies entirely on fill vs. square;
  /// prefer Meridian/Alpha on the low-contrast sepia board.
  static const PieceTheme flat = PieceTheme(
    id: 'flat',
    name: 'Flat',
    whiteFill: Color(0xFFFFFFFF),
    whiteStroke: Color(0xFFFFFFFF),
    blackFill: Color(0xFF000000),
    blackStroke: Color(0xFF000000),
  );

  /// All built-in piece themes in display order.
  static const List<PieceTheme> builtins = <PieceTheme>[meridian, alpha, flat];

  /// Looks up a built-in theme by [id], returning [fallback] when unknown.
  static PieceTheme byId(String id, {PieceTheme fallback = meridian}) {
    for (final theme in builtins) {
      if (theme.id == id) return theme;
    }
    return fallback;
  }
}
