/// [ArenaApp] root: MaterialApp, providers, responsive shell, route table.
///
/// * **Providers**: [themeRegistryProvider]/[themeModeProvider] (declared in
///   `theme/registry.dart`) and [agentListProvider] (declared in
///   `ui/ui_models.dart`) are the app's ProviderScope-ready surface. They
///   live next to their stores to avoid import cycles and are re-exported
///   here so `app.dart` is the single import for the whole provider catalog.
///   All are plain `ChangeNotifierProvider`/`StateProvider`s — no codegen
///   required.
/// * **Responsive shell** ([AppShell]): `width ≥ 700` gets a [NavigationRail];
///   below that a bottom bar plus a navigation drawer (the `<700 single
///   column + drawer` rule at app level; the board+panel rule lives in
///   `BoardPanelLayout`).
/// * **Routes** ([ArenaRoutes] + [_routeTable]): the home cards push named
///   routes wrapped in [_RoutedScreen] (Scaffold + AppBar); the shell embeds
///   the same content widgets directly.
///
/// Wrap [ArenaApp] in a `ProviderScope` at `main()`:
/// `runApp(const ProviderScope(child: ArenaApp()))`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme/registry.dart';
import 'ui/screens/agent_setup_screen.dart';
import 'ui/screens/arena_screen.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/play_screen.dart';
import 'ui/screens/review_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/screens/stats_screen.dart';
import 'ui/screens/watch_screen.dart';
import 'ui/ui_models.dart';
import 'ui/widgets/tab_visibility.dart';

// Re-export the provider surface so `app.dart` is the single import point.
export 'theme/registry.dart' show themeRegistryProvider, themeModeProvider;
export 'ui/ui_models.dart'
    show
        agentListProvider,
        ArenaRoutes,
        AgentConfig,
        AgentListStore;

/// Application root widget.
///
/// Reads [themeModeProvider] for light/dark and builds the seeded color
/// schemes; hosts [AppShell] as home and serves the named [_routeTable].
class ArenaApp extends ConsumerWidget {
  /// Creates the app root.
  const ArenaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'LLM Chess Arena',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: mode,
      home: const AppShell(),
      routes: _routeTable,
    );
  }
}

/// Named route table for home-card navigation.
///
/// Each entry wraps the content screen in [_RoutedScreen] so pushed routes
/// get an AppBar + back button; the shell embeds the bare screens.
Map<String, WidgetBuilder> get _routeTable => <String, WidgetBuilder>{
  ArenaRoutes.play: (_) =>
      const _RoutedScreen(title: 'Play · Human vs AI', child: PlayScreen()),
  ArenaRoutes.watch: (_) =>
      const _RoutedScreen(title: 'Watch · AI vs AI', child: WatchScreen()),
  ArenaRoutes.arena: (_) =>
      const _RoutedScreen(title: 'Arena', child: ArenaScreen()),
  ArenaRoutes.stats: (_) =>
      const _RoutedScreen(title: 'Statistics', child: StatsScreen()),
  ArenaRoutes.review: (_) =>
      const _RoutedScreen(title: 'Review', child: ReviewScreen()),
  ArenaRoutes.agents: (_) =>
      const _RoutedScreen(title: 'Agents', child: _AgentListScreen()),
  ArenaRoutes.settings: (_) =>
      const _RoutedScreen(title: 'Settings', child: SettingsScreen()),
};

/// Scaffold wrapper (AppBar + body) for named routes.
class _RoutedScreen extends StatelessWidget {
  /// Creates a routed wrapper with [title] and content [child].
  const _RoutedScreen({required this.title, required this.child});

  /// AppBar title.
  final String title;

  /// Content screen.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: child,
    );
  }
}

/// One shell destination: label, icon and content builder.
class _Destination {
  /// Creates a destination.
  const _Destination(this.label, this.icon, this.screen);

  /// Nav label.
  final String label;

  /// Nav icon.
  final IconData icon;

  /// Content builder.
  final WidgetBuilder screen;
}

/// Shell destinations in nav order.
final List<_Destination> _destinations = <_Destination>[
  _Destination('Home', Icons.home_outlined, (_) => HomeScreen()),
  _Destination('Play', Icons.sports_esports_outlined, (_) => PlayScreen()),
  _Destination('Watch', Icons.visibility_outlined, (_) => WatchScreen()),
  _Destination('Arena', Icons.emoji_events_outlined, (_) => ArenaScreen()),
  _Destination('Stats', Icons.bar_chart_outlined, (_) => StatsScreen()),
  _Destination('Review', Icons.replay_outlined, (_) => ReviewScreen()),
  _Destination('Agents', Icons.smart_toy_outlined, (_) => _AgentListScreen()),
  _Destination('Settings', Icons.palette_outlined, (_) => SettingsScreen()),
];

/// Responsive app shell: rail (≥700px) vs. bottom bar + drawer (<700px).
class AppShell extends StatefulWidget {
  /// Creates the app shell.
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// Selected destination index.
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 700;
        final body = IndexedStack(
          index: _index,
          children: <Widget>[
            for (var i = 0; i < _destinations.length; i++)
              // Hidden tabs stay mounted so their state survives tab
              // switches, but they must not leak semantics into the
              // accessibility tree. `RenderIndexedStack.index` only calls
              // markNeedsLayout (never markNeedsSemanticsUpdate), so a switch
              // can leave the engine holding the previous child's nodes and
              // the next update is diffed against a stale tree — the source
              // of the "… will not be in the tree and is not the new root"
              // AXTree errors. Toggling ExcludeSemantics.excluding forces a
              // matching semantics update on every switch, and TickerMode
              // stops hidden tabs' animations from mutating semantics.
              ExcludeSemantics(
                key: ValueKey<String>(_destinations[i].label),
                excluding: i != _index,
                child: TickerMode(
                  enabled: i == _index,
                  child: TabVisibility(
                    isVisible: i == _index,
                    child: i == 0
                        // The dashboard selects shell destinations instead
                        // of pushing a second live instance of the same
                        // screen (which doubled board/stream work).
                        ? HomeScreen(onOpen: _openRoute)
                        : _destinations[i].screen(context),
                  ),
                ),
              ),
          ],
        );
        return Scaffold(
          appBar: wide
              ? null
              : AppBar(title: Text(_destinations[_index].label)),
          drawer: wide ? null : Drawer(
            child: ListView(
              children: <Widget>[
                const DrawerHeader(
                  child: Text(
                    '♞ LLM Chess Arena',
                    style: TextStyle(fontSize: 20),
                  ),
                ),
                for (var i = 0; i < _destinations.length; i++)
                  ListTile(
                    leading: Icon(_destinations[i].icon),
                    title: Text(_destinations[i].label),
                    selected: i == _index,
                    onTap: () {
                      setState(() => _index = i);
                      Navigator.pop(context);
                    },
                  ),
              ],
            ),
          ),
          // One stable tree: `body` always lives in the Expanded at index 2,
          // so crossing the 700px breakpoint swaps only the leading chrome
          // instead of tearing down and re-inflating every tab (which also
          // silently killed running games).
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (wide)
                NavigationRail(
                  selectedIndex: _index,
                  labelType: NavigationRailLabelType.all,
                  destinations: <NavigationRailDestination>[
                    for (final d in _destinations)
                      NavigationRailDestination(
                        icon: Icon(d.icon),
                        label: Text(d.label),
                      ),
                  ],
                  onDestinationSelected: (i) => setState(() => _index = i),
                )
              else
                const SizedBox.shrink(),
              if (wide)
                const VerticalDivider(width: 1)
              else
                const SizedBox.shrink(),
              Expanded(child: body),
            ],
          ),
          bottomNavigationBar: wide ? null : NavigationBar(
            // The bottom bar folds Stats/Review/Agents/Settings into "More";
            // mirror the real section instead of clamping everything above
            // the first four to Home.
            selectedIndex: _index <= 3 ? _index : 4,
            onDestinationSelected: (i) {
              if (i == 4) {
                _openMore();
              } else {
                setState(() => _index = i);
              }
            },
            destinations: const <NavigationDestination>[
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.sports_esports_outlined),
                label: 'Play',
              ),
              NavigationDestination(
                icon: Icon(Icons.visibility_outlined),
                label: 'Watch',
              ),
              NavigationDestination(
                icon: Icon(Icons.emoji_events_outlined),
                label: 'Arena',
              ),
              NavigationDestination(
                icon: Icon(Icons.more_horiz),
                label: 'More',
              ),
            ],
          ),
        );
      },
    );
  }

  /// Shell destination index for each named route used by the home cards.
  static const Map<String, int> _routeToIndex = <String, int>{
    ArenaRoutes.play: 1,
    ArenaRoutes.watch: 2,
    ArenaRoutes.arena: 3,
    ArenaRoutes.stats: 4,
    ArenaRoutes.review: 5,
    ArenaRoutes.agents: 6,
    ArenaRoutes.settings: 7,
  };

  /// Selects the shell destination matching [route] (home-card navigation).
  void _openRoute(String route) {
    final index = _routeToIndex[route];
    if (index != null) setState(() => _index = index);
  }

  /// Opens a sheet listing the destinations the bottom bar folds into
  /// "More" (Stats, Review, Agents, Settings) and selects the tapped one.
  Future<void> _openMore() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            for (var i = 4; i < _destinations.length; i++)
              ListTile(
                leading: Icon(_destinations[i].icon),
                title: Text(_destinations[i].label),
                selected: i == _index,
                // Switch while the sheet still owns the modal barrier, so the
                // IndexedStack change never lands in the same frame as the
                // sheet's exit animation (which would churn root semantics).
                onTap: () {
                  setState(() => _index = i);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// Agent catalog screen: list, delete, create and edit.
///
/// Create/edit push [AgentSetupScreen] as a MaterialPageRoute (carrying
/// [AgentConfig.id] for edits) so the form stays a plain constructor-widget
/// while remaining reachable from both the shell and named routes.
class _AgentListScreen extends ConsumerWidget {
  /// Creates the agent list screen.
  const _AgentListScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agents = ref.watch(agentListProvider).agents;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                '${agents.length} agents',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(
                      appBar: null,
                      body: SafeArea(child: AgentSetupScreen()),
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
                        onPressed: () =>
                            ref.read(agentListProvider).removeAgent(a.id),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
