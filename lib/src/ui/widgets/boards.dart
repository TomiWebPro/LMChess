/// Small shared widgets used across play/watch/arena/review screens, plus
/// the responsive board+panel layout contract.
///
/// ## Responsive rule (applies everywhere a board meets a side panel)
///
/// * **Wide** (`width > 1100`): board and panel side-by-side in a [Row].
/// * **Medium** (`700–1100`): stacked with tabs — a [TabBar] switches between
///   the board and the panel in [BoardPanelLayout].
/// * **Narrow** (`< 700`): single scrollable column, board first. App-level
///   navigation additionally collapses into a drawer (see `AppShell`).
///
/// Use [layoutModeFor] / [ArenaBreakpoints] when a screen needs a custom
/// arrangement instead of [BoardPanelLayout].
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Width breakpoints for the board+panel responsive rule.
///
/// * [wide]: above this, board and panel sit side-by-side.
/// * [medium]: at or above this (and at most [wide]), stacked with tabs.
///   Below it, single column (+ app drawer for navigation).
class ArenaBreakpoints {
  /// Side-by-side threshold.
  static const double wide = 1100;

  /// Tabbed/stacked threshold.
  static const double medium = 700;
}

/// Responsive modes derived from [layoutModeFor].
enum ArenaLayoutMode {
  /// `width > 1100`: board + panel side-by-side.
  wide,

  /// `700 ≤ width ≤ 1100`: board/panel stacked behind tabs.
  medium,

  /// `width < 700`: single column; navigation moves to a drawer.
  narrow,
}

/// Maps a layout width to its [ArenaLayoutMode].
ArenaLayoutMode layoutModeFor(double width) {
  if (width > ArenaBreakpoints.wide) return ArenaLayoutMode.wide;
  if (width >= ArenaBreakpoints.medium) return ArenaLayoutMode.medium;
  return ArenaLayoutMode.narrow;
}

/// Formats a clock value in seconds as `m:ss` (or `h:mm:ss` past one hour).
String formatClock(int totalSeconds) {
  final s = math.max(0, totalSeconds);
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }
  return '$m:${sec.toString().padLeft(2, '0')}';
}

/// Responsive board + side-panel scaffold used by play/watch screens.
///
/// * wide → `Row(board flex 3, panel 400px)`;
/// * medium → tabs switching board ↔ panel;
/// * narrow → scrollable column (board, then panel).
class BoardPanelLayout extends StatelessWidget {
  /// Creates a responsive board/panel layout.
  const BoardPanelLayout({
    super.key,
    required this.board,
    required this.panel,
    this.boardLabel = 'Board',
    this.panelLabel = 'Panel',
    this.panelWidth = 400,
  });

  /// The board widget (usually [Chessboard]).
  final Widget board;

  /// The side-panel widget (activity tabs, history, ...).
  final Widget panel;

  /// Tab label for the board in medium mode.
  final String boardLabel;

  /// Tab label for the panel in medium mode.
  final String panelLabel;

  /// Fixed panel width in wide mode.
  final double panelWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mode = layoutModeFor(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 800,
        );
        switch (mode) {
          case ArenaLayoutMode.wide:
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(flex: 3, child: board),
                const SizedBox(width: 16),
                SizedBox(width: panelWidth, child: panel),
              ],
            );
          case ArenaLayoutMode.medium:
            return DefaultTabController(
              length: 2,
              child: Column(
                children: <Widget>[
                  TabBar(
                    tabs: <Widget>[
                      Tab(text: boardLabel),
                      Tab(text: panelLabel),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: <Widget>[
                        SingleChildScrollView(child: board),
                        panel,
                      ],
                    ),
                  ),
                ],
              ),
            );
          case ArenaLayoutMode.narrow:
            // Narrow screens stack board over panel. The panel gets a
            // BOUNDED slice of the height (panels commonly contain
            // Expanded/TabBarView content, which cannot live inside an
            // unbounded scroll view); the board scrolls if it overflows
            // its share instead.
            return Column(
              children: <Widget>[
                Flexible(
                  flex: 3,
                  child: SingleChildScrollView(child: board),
                ),
                const SizedBox(height: 12),
                Flexible(flex: 4, child: panel),
              ],
            );
        }
      },
    );
  }
}

/// Player identity + config + clock card.
///
/// Shows a human/bot avatar, display [name], one-line config [subtitle]
/// (e.g. `gpt-4 · t=0.7`), and a [clockSeconds] countdown. The active side's
/// card gets an accent border via [isActive].
class PlayerCard extends StatelessWidget {
  /// Creates a player card.
  const PlayerCard({
    super.key,
    required this.name,
    this.subtitle = '',
    this.clockSeconds,
    this.isActive = false,
    this.isHuman = false,
    this.isWhite = true,
  });

  /// Display name (agent id or "You").
  final String name;

  /// One-line config summary (`model · params`).
  final String subtitle;

  /// Remaining clock in seconds; `null` hides the clock.
  final int? clockSeconds;

  /// Whether this side is to move (accent border + clock emphasis).
  final bool isActive;

  /// Avatar style: person for humans, robot for agents.
  final bool isHuman;

  /// Shows a white/black pip for side identity.
  final bool isWhite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: isActive ? 2 : 1,
        ),
        color: isActive
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
            : theme.colorScheme.surface,
      ),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 18,
            child: Icon(
              isHuman ? Icons.person : Icons.smart_toy_outlined,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isWhite ? Colors.white : Colors.black,
                        border: Border.all(color: Colors.grey),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        name,
                        style: theme.textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (clockSeconds != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isActive
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                formatClock(clockSeconds!),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                  color: isActive
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurface,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// SAN move list with quality/error icons and tap-to-seek.
///
/// [moves] are SAN plies (`['e4', 'e5', 'Nf3', …]`); [currentIndex] is the
/// viewed ply (`-1` = start). [qualityMarks] maps ply → mark (`'!!'`, `'!'`,
/// `'!?'`, `'?'`, `'??'`) and [errorPlies] flags engine/illegal-move plies.
/// Tapping a move calls [onTapMove] with its ply index.
class MoveList extends StatelessWidget {
  /// Creates a move list.
  const MoveList({
    super.key,
    required this.moves,
    this.currentIndex = -1,
    this.qualityMarks = const <int, String>{},
    this.errorPlies = const <int>{},
    this.onTapMove,
    this.maxHeight = 220,
  });

  /// SAN plies in order.
  final List<String> moves;

  /// Viewed ply index; `-1` means the initial position.
  final int currentIndex;

  /// Optional quality marks per ply.
  final Map<int, String> qualityMarks;

  /// Plies flagged with errors (illegal attempt, engine fault, ...).
  final Set<int> errorPlies;

  /// Tap-to-seek callback with the tapped ply index.
  final ValueChanged<int>? onTapMove;

  /// Scroll viewport cap so the list never pushes panels off-screen.
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    if (moves.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'No moves yet.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    final rows = (moves.length / 2).ceil();
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: rows,
        itemBuilder: (context, row) {
          final white = row * 2;
          final black = white + 1;
          return Container(
            color: row.isEven
                ? Colors.transparent
                : Theme.of(context).colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.35),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 40,
                  child: Text(
                    '${row + 1}.',
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Expanded(child: _moveCell(context, white)),
                Expanded(
                  child: black < moves.length
                      ? _moveCell(context, black)
                      : const SizedBox(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// One clickable ply cell with quality/error adornments.
  Widget _moveCell(BuildContext context, int ply) {
    final theme = Theme.of(context);
    final isCurrent = ply == currentIndex;
    final mark = qualityMarks[ply];
    final isError = errorPlies.contains(ply);
    return InkWell(
      onTap: onTapMove == null ? null : () => onTapMove!(ply),
      child: Container(
        // Interactive target at/above the 48px minimum touch size.
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: isCurrent ? theme.colorScheme.primaryContainer : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Flexible(
              child: Text(
                moves[ply],
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: isCurrent ? FontWeight.w700 : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Marks are text (not icon-only) so meaning survives without
            // relying on color alone.
            if (mark != null) ...<Widget>[
              const SizedBox(width: 4),
              Semantics(
                container: true,
                excludeSemantics: true,
                label: 'move quality $mark',
                child: Text(
                  mark,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: qualityColorFor(
                      mark,
                      brightness: theme.brightness,
                    ),
                  ),
                ),
              ),
            ],
            if (isError) ...<Widget>[
              const SizedBox(width: 4),
              Semantics(
                container: true,
                excludeSemantics: true,
                label: 'error',
                child: Text(
                  '⚠',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Icon for a move-quality mark (`'!!'`, `'!'`, `'!?'`, `'?'`, `'??'`).
IconData qualityIconFor(String mark) {
  return switch (mark) {
    '!!' => Icons.star,
    '!' => Icons.check_circle_outline,
    '!?' => Icons.lightbulb_outline,
    '?' => Icons.warning_amber_outlined,
    '??' => Icons.cancel_outlined,
    _ => Icons.circle_outlined,
  };
}

/// Color for a move-quality mark.
///
/// [brightness] selects a light- or dark-theme-appropriate shade so the mark
/// keeps contrast on both `colorScheme` surfaces (dark themes get lighter
/// tints). Defaults to the light palette for callers without a `ThemeData`.
Color qualityColorFor(String mark, {Brightness brightness = Brightness.light}) {
  final dark = brightness == Brightness.dark;
  return switch (mark) {
    '!!' => dark ? const Color(0xFFFFCA28) : const Color(0xFFB8860B),
    '!' => dark ? const Color(0xFF81C784) : const Color(0xFF2E7D32),
    '!?' => dark ? const Color(0xFF64B5F6) : const Color(0xFF1565C0),
    '?' => dark ? const Color(0xFFFFB74D) : const Color(0xFFE65100),
    '??' => dark ? const Color(0xFFEF9A9A) : const Color(0xFFC62828),
    _ => dark ? const Color(0xFFBDBDBD) : const Color(0xFF616161),
  };
}

/// White-relative evaluation bar.
///
/// [score] is pawns from White's perspective (positive favors White); it is
/// mapped through a logistic curve so `+2` already reads as decisive.
/// [isHeuristic] overlays a `heuristic` watermark reminding viewers this is
/// a rules-based estimate, not engine search.
class EvalBar extends StatelessWidget {
  /// Creates an eval bar.
  const EvalBar({
    super.key,
    required this.score,
    this.isHeuristic = true,
    this.height = 22,
  });

  /// White-relative score in pawns.
  final double score;

  /// Whether the score is a heuristic estimate (shows the watermark).
  final bool isHeuristic;

  /// Bar height.
  final double height;

  /// Logistic mapping from pawn score to white fraction (0..1).
  static double fractionFor(double pawns) {
    final f = 1 / (1 + math.pow(10, -pawns / 4));
    return f.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = fractionFor(score);
    final label = score >= 0
        ? '+${score.toStringAsFixed(1)}'
        : score.toStringAsFixed(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          height: height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            // Outline keeps the black/white bar (semantic chess-side tones)
            // visible against dark surfaces too.
            border: Border.all(color: theme.colorScheme.outline),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Container(color: const Color(0xFF2B2B2E)),
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: fraction,
                child: Container(color: const Color(0xFFF5F5F5)),
              ),
              Center(
                child: Container(width: 2, color: theme.colorScheme.error),
              ),
              if (isHeuristic)
                Center(
                  child: Text(
                    'heuristic',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text('Eval $label (White-relative)', style: theme.textTheme.labelSmall),
      ],
    );
  }
}

/// One-line `label: value` statistic chip with an optional icon.
class StatChip extends StatelessWidget {
  /// Creates a stat chip.
  const StatChip({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.color,
  });

  /// Chip label (`'Accuracy'`).
  final String label;

  /// Chip value (`'92%'`).
  final String value;

  /// Optional leading icon.
  final IconData? icon;

  /// Optional icon/accent color.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Chip(
      avatar: icon == null
          ? null
          : Icon(icon, size: 16, color: color ?? theme.colorScheme.primary),
      label: Text('$label: $value'),
      visualDensity: VisualDensity.compact,
    );
  }
}
