/// [SettingsScreen]: theme switchers + agents + app brightness + license info.
///
/// Board-theme and piece-theme radio lists bound to [ThemeRegistry]
/// (`useBoardTheme`/`usePieceTheme`), a light/dark/system segmented control
/// bound to [themeModeProvider], and a live mini-[Chessboard] preview so
/// every combination can be judged in place. Custom-theme management UI can
/// call `addCustomBoardTheme`/`removeCustomBoardTheme` later; the registry
/// already validates those paths.
///
/// The **License & attributions** section surfaces the GPLv3 base license,
/// the GURAv1 geographic-use restriction, and the Stockfish / WintrChess
/// credits. These are GPLv3 obligations, not decoration: the engine
/// attribution and the geographic restriction must be visible to every
/// user of a distributed build, not only to repository readers.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../review/embedded_engine.dart' show EngineAttributions;
import '../../theme/registry.dart';
import '../ui_models.dart' show agentListProvider;
import '../widgets/chessboard.dart';
import 'agent_setup_screen.dart';
import 'game_screen.dart' show startingPosition;

/// App settings: theme switchers with a live board preview.
class SettingsScreen extends ConsumerWidget {
  /// Creates the settings screen.
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = ref.watch(themeRegistryProvider);
    final mode = ref.watch(themeModeProvider);
    final theme = Theme.of(context);
    final agents = ref.watch(agentListProvider).agents;
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
              const SizedBox(height: 24),
              Text('Agents', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Text(
                    '${agents.length} agents',
                    style: theme.textTheme.titleMedium,
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('New agent')),
                          body: const SafeArea(child: AgentSetupScreen()),
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('New agent'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (agents.isEmpty)
                const Text('No agents yet — create one to get started.')
              else
                for (final a in agents)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.smart_toy_outlined),
                      title: Text(a.name),
                      subtitle: Text(
                        '${a.summary} · t=${a.temperature.toStringAsFixed(2)}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          IconButton(
                            tooltip: 'Edit',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => Scaffold(
                                  appBar: AppBar(title: Text('Edit ${a.name}')),
                                  body: AgentSetupScreen(agentId: a.id),
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (dialogContext) => AlertDialog(
                                  title: const Text('Delete agent?'),
                                  content: Text(
                                    'Are you sure you want to delete "${a.name}"?',
                                  ),
                                  actions: <Widget>[
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(dialogContext, false),
                                      child: const Text('Cancel'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(dialogContext, true),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true) {
                                ref.read(agentListProvider).removeAgent(a.id);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
              const SizedBox(height: 24),
              Text('License & attributions', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              _buildLicenseSection(theme),
            ],
          ),
        ),
      ),
    );
  }

  /// License, geographic-use restriction, and third-party credits.
  ///
  /// Rendered verbatim from [EngineAttributions] so the strings the
  /// attribution ledger declares are exactly what the user sees — a
  /// hand-written duplicate would drift and could go stale.
  Widget _buildLicenseSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          EngineAttributions.geographicUseRestriction,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Text(EngineAttributions.stockfish, style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        Text(
          'WintrChess — https://github.com/wintrcat/wintrchess (GPLv3), by '
          'the WintrChess authors. The game-review pipeline is a derived '
          "work: it ports the review math from WintrChess' "
          'shared/src/lib/reporter/ (expected-points model, per-move '
          'accuracy formula, analysis pipeline shape). See '
          'lib/src/review/wintrchess_notes.md for the full ported-vs-new '
          'ledger.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Text(
          'Full license texts (GPLv3 + Geographic Use Restriction Addendum '
          'v1.0) ship in the LICENSE file of the project source.',
          style: theme.textTheme.bodySmall,
        ),
      ],
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
