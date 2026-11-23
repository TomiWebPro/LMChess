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

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme/registry.dart';
import 'ui/screens/arena_screen.dart';
import 'ui/screens/game_screen.dart';
import 'ui/screens/review_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/screens/stats_screen.dart';
import 'ui/ui_models.dart';
import 'ui/semantics_heal.dart';
import 'ui/widgets/boards.dart';
import 'ui/widgets/tab_visibility.dart';

// Re-export the provider surface so `app.dart` is the single import point.
export 'diagnostics/app_log.dart'
    show AppLog, AppLogLevel, AppLogRecord, appLogProvider;
export 'storage/repository_provider.dart'
    show appRepositoryProvider, eventStoreProvider;
export 'theme/registry.dart' show themeRegistryProvider, themeModeProvider;
export 'ui/ui_models.dart'
    show
        agentListProvider,
        ArenaRoutes,
        AgentConfig,
        AgentListStore;

/// Dev-only kill switch for the Windows accessibility-bridge crash
/// (flutter/flutter#175041). Set via
/// `--dart-define=DISABLE_SEMANTICS=true`. `const` + `bool.fromEnvironment`
/// so release builds pay nothing when unset.
const bool kDisableSemantics = bool.fromEnvironment(
  'DISABLE_SEMANTICS',
  defaultValue: false,
);

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
      // Windows accessibility-bridge guard (flutter/flutter#182444,
      // flutter/flutter#175041): a stray UIA client forces
      // `semanticsEnabled=true` from frame 1 even with no screen reader
      // (verified on this host: bare template app also reports true), so
      // the first incremental update crowns the wrong AXTree root
      // (`0 will not be in the tree`) and the next reparent
      // (`28 will not be ...` — board square d7) kills the process
      // (`Lost connection`). Wrapping the tree in ExcludeSemantics while
      // no screen reader is attached keeps the native tree empty (no
      // updates to reject); real screen-reader users still get full
      // semantics. Dev override `--dart-define=DISABLE_SEMANTICS=true`
      // forces exclusion everywhere.
      builder: (context, child) {
        if (kDisableSemantics) {
          return ExcludeSemantics(child: child ?? const SizedBox.shrink());
        }
        if (defaultTargetPlatform == TargetPlatform.windows &&
            !(MediaQuery.maybeAccessibleNavigationOf(context) ?? false)) {
          return ExcludeSemantics(child: child ?? const SizedBox.shrink());
        }
        return child ?? const SizedBox.shrink();
      },
      home: const AppShell(),
      routes: _routeTable,
    );
  }
}

/// Named route table for deep links.
///
/// Play and Watch are kept as aliases: both resolve to the unified [GameScreen].
Map<String, WidgetBuilder> get _routeTable => <String, WidgetBuilder>{
  ArenaRoutes.play: (_) =>
      const _RoutedScreen(title: 'Game · Human & Engines', child: GameScreen()),
  ArenaRoutes.watch: (_) =>
      const _RoutedScreen(title: 'Game · Human & Engines', child: GameScreen()),
  ArenaRoutes.game: (_) =>
      const _RoutedScreen(title: 'Game · Human & Engines', child: GameScreen()),
  ArenaRoutes.arena: (_) =>
      const _RoutedScreen(title: 'Arena', child: ArenaScreen()),
  ArenaRoutes.stats: (_) =>
      const _RoutedScreen(title: 'Statistics', child: StatsScreen()),
  ArenaRoutes.review: (_) =>
      const _RoutedScreen(title: 'Review', child: ReviewScreen()),
  ArenaRoutes.agents: (_) =>
      const _RoutedScreen(title: 'Settings', child: SettingsScreen()),
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
  _Destination('Game', Icons.sports_esports_outlined, (_) => GameScreen()),
  _Destination('Arena', Icons.emoji_events_outlined, (_) => ArenaScreen()),
  _Destination('Stats', Icons.bar_chart_outlined, (_) => StatsScreen()),
  _Destination('Review', Icons.replay_outlined, (_) => ReviewScreen()),
  _Destination('Settings', Icons.palette_outlined, (_) => SettingsScreen()),
];

/// Phone bottom-bar slots: the four daily destinations (Game, Arena, Stats,
/// Review). Indices into [_destinations].
const List<int> _phoneBarIndices = <int>[0, 1, 2, 3];

/// Phone "More" overflow: everything not on the bottom bar (Settings).
/// Indices into [_destinations].
const List<int> _phoneOverflowIndices = <int>[4];

/// Responsive app shell: rail (≥700px) vs. bottom bar + drawer (<700px).
class AppShell extends StatefulWidget {
  /// Creates the app shell.
  const AppShell({super.key, this.initialIndex = 0});

  /// Destination index to start on — tests set this to reach a tab directly.
  final int initialIndex;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// Selected destination index.
  int _index = 0;

  /// Delayed full-tree semantics resend (see [resendFullSemanticsTree]).
  Timer? _semanticsHealTimer;

  /// Re-enable listener for late-attaching clients (see below).
  VoidCallback? _semanticsHealListener;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    // The bridge initializes while the startup storm is still moving nodes,
    // so its first updates can miss creations (flutter/flutter#175041).
    // Re-send the complete tree once startup settles: this heals any missed
    // creations and all later incremental updates merge into a valid tree.
    _semanticsHealTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) resendFullSemanticsTree();
    });
    // A newly attached client (UIA smoke, Narrator) enables semantics long
    // after startup; hand it a complete tree instead of a partial one.
    _semanticsHealListener = () {
      if (mounted && SemanticsBinding.instance.semanticsEnabled) {
        resendFullSemanticsTree();
      }
    };
    SemanticsBinding.instance
        .addSemanticsEnabledListener(_semanticsHealListener!);
  }

  @override
  void dispose() {
    _semanticsHealTimer?.cancel();
    final listener = _semanticsHealListener;
    if (listener != null) {
      SemanticsBinding.instance.removeSemanticsEnabledListener(listener);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final targetWide = constraints.maxWidth >= 700;
        // Debounce the rail-vs-bar switch: a live window drag fires
        // LayoutBuilder dozens of times per second, and swapping the nav
        // chrome on every intermediate width churns the semantics tree
        // (flutter/flutter#175041). Hold the old chrome until the width
        // settles, so a drag is size-only updates plus one structural
        // switch at most.
        return DebouncedBreakpoint<bool>(
          target: targetWide,
          builder: (context, wide) {
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
                    child: _destinations[i].screen(context),
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
            // The phone bar holds the four daily destinations (Game, Arena,
            // Stats, Review); the "More" sheet holds Settings.
            selectedIndex: _phoneBarSelectedIndex(_index),
            onDestinationSelected: (i) {
              if (i == _phoneBarIndices.length) {
                _openMore();
              } else {
                setState(() => _index = _phoneBarIndices[i]);
              }
            },
            destinations: const <NavigationDestination>[
              NavigationDestination(
                icon: Icon(Icons.sports_esports_outlined),
                label: 'Game',
              ),
              NavigationDestination(
                icon: Icon(Icons.emoji_events_outlined),
                label: 'Arena',
              ),
              NavigationDestination(
                icon: Icon(Icons.bar_chart_outlined),
                label: 'Stats',
              ),
              NavigationDestination(
                icon: Icon(Icons.replay_outlined),
                label: 'Review',
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
      },
    );
  }

  /// Phone bottom-bar highlight for shell destination [_index]: the bar
  /// slot, or the "More" slot when the destination lives in the overflow
  /// sheet, drawer or rail.
  static int _phoneBarSelectedIndex(int index) {
    final slot = _phoneBarIndices.indexOf(index);
    return slot == -1 ? _phoneBarIndices.length : slot;
  }

  /// Opens a sheet listing the destination the phone bottom bar folds into
  /// "More" (Settings) and selects the tapped one.
  Future<void> _openMore() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            for (final i in _phoneOverflowIndices)
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
