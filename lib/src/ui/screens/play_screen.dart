/// [PlayScreen]: compatibility alias of the unified [GameScreen].
///
/// The old human-vs-AI play room is now the [GameScreen] with White=Human,
/// Black=Agent (auto-started). This alias keeps existing imports, tests and
/// deep links working.
library;

import 'game_screen.dart';

/// Game id used for stats/review attribution (unified room id).
const String kPlayGameId = 'game';

/// Default AI seat for the play alias.
const String kPlayAiAgentId = 'demo-black';

/// Human (White) vs AI (Black) play surface (unified game room).
class PlayScreen extends GameScreen {
  /// Creates the play screen.
  const PlayScreen({super.key, super.initialFen})
    : super(
        initialWhiteKind: SeatKind.human,
        initialBlackKind: SeatKind.agent,
        autostart: true,
      );
}
