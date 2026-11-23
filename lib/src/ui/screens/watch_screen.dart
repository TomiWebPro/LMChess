/// [WatchScreen]: compatibility alias of the unified [GameScreen].
///
/// The old AI-vs-AI watch room is now the [GameScreen] with both seats on
/// agents (manual start). This alias keeps existing imports, tests and deep
/// links working.
library;

import 'game_screen.dart';

/// Game id used by the watch alias stats/review attribution.
const String kWatchGameId = 'game';

/// AI-vs-AI watch room (unified game room).
class WatchScreen extends GameScreen {
  /// Creates the watch screen.
  const WatchScreen({super.key, super.initialSeed})
    : super(
        initialWhiteKind: SeatKind.agent,
        initialBlackKind: SeatKind.agent,
        autostart: false,
      );
}
