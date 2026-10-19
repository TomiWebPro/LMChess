/// [HomeScreen]: the app dashboard (content-only; `AppShell` hosts it).
///
/// Grid of navigation cards for every destination (Play, Watch, Arena,
/// Stats, Review, Agents, Settings) using the [ArenaRoutes] constants, plus
/// a hero strip and quick-status chips. Responsive via a `GridView` whose
/// column count follows the [ArenaBreakpoints] rule (>1100: 4, ≥700: 3,
/// else 2).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui_models.dart';

/// App dashboard with navigation cards to every destination.
class HomeScreen extends ConsumerWidget {
  /// Creates the home screen.
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildHero(theme),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : 800;
              final columns = w > 1100 ? 4 : (w >= 700 ? 3 : 2);
              return GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.25,
                children: const <Widget>[
                  _NavCard(
                    route: ArenaRoutes.play,
                    icon: Icons.sports_esports_outlined,
                    title: 'Play',
                    subtitle: 'Human vs AI over the board',
                  ),
                  _NavCard(
                    route: ArenaRoutes.watch,
                    icon: Icons.visibility_outlined,
                    title: 'Watch',
                    subtitle: 'AI vs AI with live reasoning',
                  ),
                  _NavCard(
                    route: ArenaRoutes.arena,
                    icon: Icons.emoji_events_outlined,
                    title: 'Arena',
                    subtitle: 'Tournaments + mini boards',
                  ),
                  _NavCard(
                    route: ArenaRoutes.stats,
                    icon: Icons.bar_chart_outlined,
                    title: 'Stats',
                    subtitle: 'Outcomes, errors, latency',
                  ),
                  _NavCard(
                    route: ArenaRoutes.review,
                    icon: Icons.replay_outlined,
                    title: 'Review',
                    subtitle: 'Replay, evals, key moments',
                  ),
                  _NavCard(
                    route: ArenaRoutes.agents,
                    icon: Icons.smart_toy_outlined,
                    title: 'Agents',
                    subtitle: 'Providers, models, prompts',
                  ),
                  _NavCard(
                    route: ArenaRoutes.settings,
                    icon: Icons.palette_outlined,
                    title: 'Settings',
                    subtitle: 'Board + piece themes',
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// Hero strip: title, tagline and live status chips.
  Widget _buildHero(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: <Color>[
            theme.colorScheme.primaryContainer,
            theme.colorScheme.tertiaryContainer,
          ],
        ),
      ),
      child: Row(
        children: <Widget>[
          const Text('♞', style: TextStyle(fontSize: 48)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'LLM Chess Arena',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Humans and LLMs play standard and chaotic chess — fully '
                  'observable, tournament-ready, and reviewable.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                const Wrap(
                  spacing: 8,
                  children: <Widget>[
                    Chip(
                      label: Text('Standard 8×8'),
                      visualDensity: VisualDensity.compact,
                    ),
                    Chip(
                      label: Text('Chaotic variants'),
                      visualDensity: VisualDensity.compact,
                    ),
                    Chip(
                      label: Text('Full telemetry'),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One dashboard navigation card pushing [route] on tap.
class _NavCard extends StatelessWidget {
  /// Creates a nav card.
  const _NavCard({
    required this.route,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  /// Route pushed on tap.
  final String route;

  /// Card icon.
  final IconData icon;

  /// Card title.
  final String title;

  /// One-line description.
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.pushNamed(context, route),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 30, color: theme.colorScheme.primary),
              const SizedBox(height: 8),
              Text(title, style: theme.textTheme.titleMedium),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
