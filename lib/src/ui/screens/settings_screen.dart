/// [SettingsScreen]: theme switchers + app brightness (content-only).
///
/// Board-theme and piece-theme radio lists bound to [ThemeRegistry]
/// (`useBoardTheme`/`usePieceTheme`), a light/dark/system segmented control
/// bound to [themeModeProvider], and a live mini-[Chessboard] preview so
/// every combination can be judged in place. Custom-theme management UI can
/// call `addCustomBoardTheme`/`removeCustomBoardTheme` later; the registry
/// already validates those paths.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/registry.dart';
import '../widgets/chessboard.dart';
import 'play_screen.dart' show startingPosition;

/// App settings: theme switchers with a live board preview.
class SettingsScreen extends ConsumerWidget {
  /// Creates the settings screen.
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = ref.watch(themeRegistryProvider);
    final mode = ref.watch(themeModeProvider);
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Appearance', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 12),
              _buildPreview(registry),
              const SizedBox(height: 16),
              Text('Color scheme', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              SegmentedButton<ThemeMode>(
                segments: const <ButtonSegment<ThemeMode>>[
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode_outlined),
                    label: Text('Light'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.settings_outlined),
                    label: Text('System'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode_outlined),
                    label: Text('Dark'),
                  ),
                ],
                selected: <ThemeMode>{mode},
                onSelectionChanged: (s) =>
                    ref.read(themeModeProvider.notifier).state = s.first,
              ),
              const SizedBox(height: 16),
              Text('Board theme', style: theme.textTheme.titleMedium),
              RadioGroup<String>(
                groupValue: registry.boardTheme.id,
                onChanged: (v) {
                  if (v != null) {
                    ref.read(themeRegistryProvider).useBoardTheme(v);
                  }
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (final t in registry.boardThemes)
                      RadioListTile<String>(
                        title: Text(t.name),
                        subtitle: Text(
                          registry.isBuiltInBoard(t.id) ? 'Built-in' : 'Custom',
                        ),
                        value: t.id,
                        secondary: _swatch(t.lightSquare, t.darkSquare),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text('Piece theme', style: theme.textTheme.titleMedium),
              RadioGroup<String>(
                groupValue: registry.pieceTheme.id,
                onChanged: (v) {
                  if (v != null) {
                    ref.read(themeRegistryProvider).usePieceTheme(v);
                  }
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (final p in registry.pieceThemes)
                      RadioListTile<String>(
                        title: Text(p.name),
                        subtitle: Text(
                          registry.isBuiltInPiece(p.id) ? 'Built-in' : 'Custom',
                        ),
                        value: p.id,
                        secondary: Text(
                          '♞',
                          style: TextStyle(fontSize: 28, color: p.blackFill),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Live preview of the active board+piece combination.
  Widget _buildPreview(ThemeRegistry registry) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 180,
              child: Chessboard(
                squares: startingPosition(),
                boardTheme: registry.boardTheme,
                pieceTheme: registry.pieceTheme,
                interactive: false,
                onTapSquare: null,
                showCoordinates: false,
                lastFrom: 'e2',
                lastTo: 'e4',
                selected: 'g1',
                legalTargets: const <String>['f3', 'h3'],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${registry.boardTheme.name} × ${registry.pieceTheme.name}\n'
                'Preview shows selection, last-move trail and legal hints '
                'together so clashes are visible immediately.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Two-tone square swatch for a board-theme radio row.
  Widget _swatch(Color light, Color dark) {
    return SizedBox(
      width: 40,
      height: 24,
      child: Row(
        children: <Widget>[
          Expanded(child: Container(color: light)),
          Expanded(child: Container(color: dark)),
        ],
      ),
    );
  }
}
