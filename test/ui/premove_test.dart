// Widget + unit tests for §15.4 premove and multipremove.
//
// Covers the premove domain helpers (pure Dart), the queue UI (ghost
// pieces, numbered markers, "N premoves" chip, Clear control), queue
// entry via click-click and drag, cancellation (right-click last, Escape
// all), execution one-per-human-turn through the normal move path, the
// illegal-premove discard notice, promotion-premove queen default without
// a dialog, the five-move cap, new-game/terminal/dispose clearing, scrub
// interplay, and semantics stability (ghosts are ExcludeSemantics). Uses
// deterministic fakes only — no network, engine process, or wall-clock.

import 'package:flutter/gestures.dart' show PointerDeviceKind, kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/chess/fen.dart';
import 'package:llm_chess_arena/src/chess/piece.dart';
import 'package:llm_chess_arena/src/chess/position.dart';
import 'package:llm_chess_arena/src/chess/square.dart';
import 'package:llm_chess_arena/src/llm/mock_provider.dart';
import 'package:llm_chess_arena/src/llm/tool_schema.dart' show MoveToolCall;
import 'package:llm_chess_arena/src/llm/validation.dart' show FailureKind;
import 'package:llm_chess_arena/src/ui/backend_bridge.dart'
    show clockProvider, turnProviderFactoryProvider;
import 'package:llm_chess_arena/src/ui/premove.dart';
import 'package:llm_chess_arena/src/ui/screens/play_screen.dart'
    show PlayScreen;
import 'package:llm_chess_arena/src/ui/widgets/chessboard.dart' show Chessboard;

import '../support/arena_test_harness.dart' as harness;
import '../support/semantics_invariants.dart';

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

/// Mutable per-test AI-turn bookkeeping: how many turns the factory was
/// asked for, plus an optional scripted legal reply per turn (fallback:
/// the engine's first legal UCI) so execution tests are deterministic.
class _AiScript {
  _AiScript({this.replies});
  final List<String>? replies;
  int turns = 0;
  int scriptIndex = 0;
}

/// Overrides: fake AI turns stream scripted legal moves with a small
/// stepDelay (so the premove window stays open during the test's queue
/// taps) and the clock is fixed UTC.
List<Override> _premoveOverrides({
  required _AiScript script,
  Duration stepDelay = const Duration(milliseconds: 50),
}) => <Override>[
  turnProviderFactoryProvider.overrideWithValue((
    config,
    legalUcis, {
    seed,
    phrase,
  }) async {
    script.turns++;
    String? uci;
    final replies = script.replies;
    if (replies != null && script.scriptIndex < replies.length) {
      uci = replies[script.scriptIndex++];
    } else if (legalUcis.isNotEmpty) {
      uci = legalUcis.first;
    }
    if (uci == null) {
      return MockProvider(
        script: <Object>[FailureKind.incompleteResponse],
        model: config.model,
        stepDelay: stepDelay,
      );
    }
    return MockProvider(
      script: <Object>[
        MoveToolCall(
          from: uci.substring(0, 2),
          to: uci.substring(2, 4),
          promotion: uci.length > 4 ? uci.substring(4, 5) : null,
          phrase: phrase,
        ),
      ],
      model: config.model,
      stepDelay: stepDelay,
    );
  }),
  clockProvider.overrideWithValue(() => DateTime.utc(2026, 1, 1)),
];

/// Pumps a bare PlayScreen (no shell navigation) inside MaterialApp.
Future<_AiScript> _pumpPreplay(
  WidgetTester tester, {
  String? fen,
  List<String>? replyScript,
}) async {
  final script = _AiScript(replies: replyScript);
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: _premoveOverrides(script: script),
      child: MaterialApp(
        home: Scaffold(body: PlayScreen(initialFen: fen)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return script;
}

/// Plays the human's opening move from [from] to [to] and lets the AI turn
/// start streaming (the premove window opens as soon as Black's turn begins).
Future<void> _playMove(WidgetTester tester, String from, String to) async {
  await tester.tap(find.bySemanticsLabel('White piece on $from'));
  await tester.pump();
  await tester.tap(find.bySemanticsLabel('Empty square $to'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// Queues a premove via the click-click path during the AI's turn.
Future<void> _queuePremove(WidgetTester tester, String from, String to) async {
  await tester.tap(find.bySemanticsLabel('White piece on $from'));
  await tester.pump();
  await tester.tap(find.bySemanticsLabel('Empty square $to'));
  await tester.pump();
}

/// Queues a premove via the drag path during the AI's turn.
Future<void> _dragPre(WidgetTester tester, String from, String to) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.bySemanticsLabel('White piece on $from')),
    kind: PointerDeviceKind.mouse,
  );
  await gesture.moveTo(
    tester.getCenter(find.bySemanticsLabel('Empty square $to')),
  );
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

/// Drains all AI turns and pending timers, then disposes the app.
Future<void> _settle(WidgetTester tester, {int steps = 12}) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  await harness.disposeApp(tester);
}

void main() {
  setUp(harness.resetTelemetry);

  group('§15.4 premove domain', () {
    test('PremoveAttempt composes UCI', () {
      const plain = PremoveAttempt(from: 'd2', to: 'd4');
      const promo = PremoveAttempt(from: 'a7', to: 'a8', promotion: 'q');
      expect(plain.uci, 'd2d4');
      expect(promo.uci, 'a7a8q');
    });

    test('PremoveAttempt equality and hashCode', () {
      const a = PremoveAttempt(from: 'd2', to: 'd4');
      const b = PremoveAttempt(from: 'd2', to: 'd4');
      const c = PremoveAttempt(from: 'd2', to: 'd4', promotion: 'q');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
      expect(a, isNot(equals(const PremoveAttempt(from: 'e2', to: 'e4'))));
    });

    test('promotionTypeFor maps letters and rejects others', () {
      expect(promotionTypeFor('q'), PieceType.queen);
      expect(promotionTypeFor('r'), PieceType.rook);
      expect(promotionTypeFor('b'), PieceType.bishop);
      expect(promotionTypeFor('n'), PieceType.knight);
      expect(promotionTypeFor('Q'), PieceType.queen);
      expect(promotionTypeFor(null), isNull);
      expect(promotionTypeFor('x'), isNull);
    });

    test('isPromotionMove detects pawn promotions only', () {
      expect(
        isPromotionMove(Position.initial(), 'e2', 'e4', PieceColor.white),
        isFalse,
      );
      final near = parseFen('6k1/P7/8/8/8/8/8/6K1 w - - 0 1');
      expect(isPromotionMove(near, 'a7', 'a8', PieceColor.white), isTrue);
      final black = parseFen('6k1/8/8/8/8/8/p7/6K1 b - - 0 1');
      expect(isPromotionMove(black, 'a2', 'a1', PieceColor.black), isTrue);
      final rook = parseFen('6k1/8/8/8/8/8/7R/6K1 w - - 0 1');
      expect(isPromotionMove(rook, 'h2', 'h8', PieceColor.white), isFalse);
    });

    test('premoveSimulation with no premoves leaves the board unchanged '
        'and gives the mover the turn', () {
      final pos = parseFen(
        'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1',
      );
      final sim = premoveSimulation(
        pos,
        const <PremoveAttempt>[],
        color: PieceColor.white,
      );
      expect(sim.sideToMove, PieceColor.white);
      expect(sim.toFen(), contains('4P3'));
    });

    test('premoveSimulation applies one premove', () {
      final sim = premoveSimulation(Position.initial(), const <PremoveAttempt>[
        PremoveAttempt(from: 'e2', to: 'e4'),
      ], color: PieceColor.white);
      expect(sim.sideToMove, PieceColor.white);
      expect(sim.pieceAt(Square.fromName('e4'))?.type, PieceType.pawn);
      expect(sim.pieceAt(Square.fromName('e2')), isNull);
    });

    test('premoveSimulation applies a legal chain in sequence', () {
      final sim = premoveSimulation(Position.initial(), const <PremoveAttempt>[
        PremoveAttempt(from: 'e2', to: 'e4'),
        PremoveAttempt(from: 'd2', to: 'd4'),
        PremoveAttempt(from: 'g1', to: 'f3'),
      ], color: PieceColor.white);
      expect(sim.sideToMove, PieceColor.white);
      expect(sim.pieceAt(Square.fromName('e4'))?.type, PieceType.pawn);
      expect(sim.pieceAt(Square.fromName('d4'))?.type, PieceType.pawn);
      expect(sim.pieceAt(Square.fromName('f3'))?.type, PieceType.knight);
    });

    test('premoveSimulation drops everything after the first illegal '
        'premove', () {
      final sim = premoveSimulation(Position.initial(), const <PremoveAttempt>[
        PremoveAttempt(from: 'e2', to: 'e4'),
        PremoveAttempt(from: 'e2', to: 'e5'), // e2 is empty now.
      ], color: PieceColor.white);
      expect(sim.sideToMove, PieceColor.white);
      expect(sim.pieceAt(Square.fromName('e4'))?.type, PieceType.pawn);
      expect(sim.pieceAt(Square.fromName('e2')), isNull);
    });

    test('isLegalPremove accepts legal and rejects illegal premoves', () {
      final sim = premoveSimulation(
        Position.initial(),
        const <PremoveAttempt>[],
        color: PieceColor.white,
      );
      expect(isLegalPremove(sim, 'e2', 'e4', color: PieceColor.white), isTrue);
      expect(isLegalPremove(sim, 'e2', 'e5', color: PieceColor.white), isFalse);
      // An opponent piece cannot be moved as a white premove.
      expect(isLegalPremove(sim, 'e7', 'e5', color: PieceColor.white), isFalse);
    });

    test('isLegalPremove rejects king-exposing moves', () {
      // White king e1, white rook e2, black rook e8: the rook is pinned.
      final pos = parseFen('4r1k1/8/8/8/8/8/4R3/4K3 w - - 0 1');
      final sim = premoveSimulation(
        pos,
        const <PremoveAttempt>[],
        color: PieceColor.white,
      );
      // Moving off the pin file exposes the king.
      expect(isLegalPremove(sim, 'e2', 'd2', color: PieceColor.white), isFalse);
      // Sliding along the pin file keeps the king shielded.
      expect(isLegalPremove(sim, 'e2', 'e4', color: PieceColor.white), isTrue);
    });

    test('premoveSimulation applies a promotion premove as queen', () {
      final pos = parseFen('6k1/P7/8/8/8/8/8/6K1 w - - 0 1');
      final sim = premoveSimulation(pos, const <PremoveAttempt>[
        PremoveAttempt(from: 'a7', to: 'a8', promotion: 'q'),
      ], color: PieceColor.white);
      expect(sim.sideToMove, PieceColor.white);
      expect(sim.pieceAt(Square.fromName('a8'))?.type, PieceType.queen);
      expect(sim.pieceAt(Square.fromName('a8'))?.color, PieceColor.white);
    });
  });

  group('§15.4 premove queue (widget)', () {
    testWidgets('tap to queue a premove during the AI turn', (tester) async {
      await _pumpPreplay(tester);
      await _playMove(tester, 'e2', 'e4');
      await _queuePremove(tester, 'd2', 'd4');
      expect(
        find.byKey(const ValueKey<String>('chessboard-premove-ghost-d2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('chessboard-premove-marker-d4')),
        findsOneWidget,
      );
      expect(find.text('1 premove'), findsOneWidget);
      await _settle(tester);
    });

    testWidgets('a second premove queues in sequence with numbering', (
      tester,
    ) async {
      await _pumpPreplay(tester);
      await _playMove(tester, 'e2', 'e4');
      await _queuePremove(tester, 'd2', 'd4');
      await _queuePremove(tester, 'g1', 'f3');
      expect(find.text('2 premoves'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey<String>('chessboard-premove-marker-d4'),
          ),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey<String>('chessboard-premove-marker-f3'),
          ),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
      await _settle(tester);
    });

    testWidgets('an illegal tap does not queue a premove', (tester) async {
      await _pumpPreplay(tester);
      await _playMove(tester, 'e2', 'e4');
      await _queuePremove(tester, 'd2', 'd5'); // pawns never move three.
      expect(
        find.byKey(const ValueKey<String>('chessboard-premove-overlay')),
        findsNothing,
      );
      expect(find.text('1 premove'), findsNothing);
      await _settle(tester);
    });

    testWidgets('drag during the AI turn queues a premove', (tester) async {
      await _pumpPreplay(tester);
      await _playMove(tester, 'e2', 'e4');
      await _dragPre(tester, 'd2', 'd4');
      expect(
        find.byKey(const ValueKey<String>('chessboard-premove-ghost-d2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('chessboard-premove-marker-d4')),
        findsOneWidget,
      );
      expect(find.text('1 premove'), findsOneWidget);
      await _settle(tester);
    });

    testWidgets('right-click removes the last premove', (tester) async {
      await _pumpPreplay(tester);
      await _playMove(tester, 'e2', 'e4');
      await _queuePremove(tester, 'd2', 'd4');
      await _queuePremove(tester, 'g1', 'f3');
      await tester.tapAt(
        tester.getCenter(find.byType(Chessboard)),
        buttons: kSecondaryButton,
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('chessboard-premove-ghost-g1')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('chessboard-premove-ghost-d2')),
        findsOneWidget,
      );
      expect(find.text('1 premove'), findsOneWidget);
      await _settle(tester);
    });

    testWidgets('Escape clears all premoves', (tester) async {
      await _pumpPreplay(tester);
      await _playMove(tester, 'e2', 'e4');
      await _queuePremove(tester, 'd2', 'd4');
      await _queuePremove(tester, 'g1', 'f3');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('chessboard-premove-overlay')),
        findsNothing,
      );
      expect(find.text('2 premoves'), findsNothing);
      await _settle(tester);
    });

    testWidgets('the Clear premoves control empties the queue', (tester) async {
      await _pumpPreplay(tester);
      await _playMove(tester, 'e2', 'e4');
      await _queuePremove(tester, 'd2', 'd4');
      await _queuePremove(tester, 'g1', 'f3');
      await tester.tap(
        find.byKey(const ValueKey<String>('play-clear-premoves')),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('chessboard-premove-overlay')),
        findsNothing,
      );
      expect(find.text('2 premoves'), findsNothing);
      await _settle(tester);
    });

    testWidgets('a single premove executes after the AI reply', (tester) async {
      final script = await _pumpPreplay(
        tester,
        replyScript: const <String>['e7e5', 'g8f6'],
      );
      await _playMove(tester, 'e2', 'e4');
      await _queuePremove(tester, 'd2', 'd4');
      expect(script.turns, 1); // only the first AI turn requested so far.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(script.turns, 2);
      expect(find.bySemanticsLabel('White piece on d4'), findsOneWidget);
      await _settle(tester);
      expect(script.turns, 2); // no extra AI turn once the queue drained.
    });

    testWidgets('a multi-premove chain executes one premove per human turn', (
      tester,
    ) async {
      final script = await _pumpPreplay(
        tester,
        replyScript: const <String>['e7e5', 'b8c6', 'g8f6'],
      );
      await _playMove(tester, 'e2', 'e4');
      await _queuePremove(tester, 'd2', 'd4');
      await _queuePremove(tester, 'g1', 'f3');
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(script.turns, 3); // one AI turn per applied White move.
      expect(find.bySemanticsLabel('White piece on d4'), findsOneWidget);
      expect(find.bySemanticsLabel('White piece on f3'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('chessboard-premove-overlay')),
        findsNothing,
      );
      await _settle(tester);
      expect(script.turns, 3); // chain fully drained, no further AI turns.
    });

    testWidgets('an illegal leading premove is discarded with a notice', (
      tester,
    ) async {
      final script = await _pumpPreplay(
        tester,
        fen: 'rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 1',
        replyScript: const <String>['d5e4'], // captures the e4 pawn.
      );
      await _playMove(tester, 'a2', 'a3');
      await _queuePremove(tester, 'e4', 'e5');
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(script.turns, 1);
      expect(find.text('Illegal premove e4-e5 was discarded.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('chessboard-premove-overlay')),
        findsNothing,
      );
      await _settle(tester);
      expect(script.turns, 1); // discard never requests another AI turn.
    });

    testWidgets('promotion premoves default to queen with no dialog', (
      tester,
    ) async {
      await _pumpPreplay(
        tester,
        fen: '6k1/P7/8/8/8/8/2P5/6K1 w - - 0 1',
        replyScript: const <String>['g8f8'],
      );
      await _playMove(tester, 'c2', 'c3');
      await tester.tap(find.bySemanticsLabel('White piece on a7'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Empty square a8'));
      await tester.pump();
      expect(find.text('Promote to'), findsNothing); // no blocking dialog.
      expect(find.text('1 premove'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey<String>('chessboard-premove-marker-a8'),
          ),
          matching: find.text('1q'),
        ),
        findsOneWidget,
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      final board = tester.widget<Chessboard>(find.byType(Chessboard));
      expect(board.squares['a8'], 'wQ');
      await _settle(tester);
    });

    testWidgets('tapping the selected piece again deselects it', (
      tester,
    ) async {
      await _pumpPreplay(tester);
      await _playMove(tester, 'e2', 'e4');
      await tester.tap(find.bySemanticsLabel('White piece on d2'));
      await tester.pump();
      var board = tester.widget<Chessboard>(find.byType(Chessboard));
      expect(board.selected, 'd2');
      await tester.tap(find.bySemanticsLabel('White piece on d2'));
      await tester.pump();
      board = tester.widget<Chessboard>(find.byType(Chessboard));
      expect(board.selected, isNull);
      expect(board.legalTargets, isEmpty);
      await _settle(tester);
    });

    testWidgets('tapping an opponent piece during the AI turn is safe', (
      tester,
    ) async {
      await _pumpPreplay(tester);
      await _playMove(tester, 'e2', 'e4');
      await tester.tap(find.bySemanticsLabel('Black piece on e7'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey<String>('chessboard-premove-overlay')),
        findsNothing,
      );
      await _settle(tester);
    });

    testWidgets('the queue is capped at five premoves', (tester) async {
      await _pumpPreplay(tester);
      await _playMove(tester, 'e2', 'e4');
      await _queuePremove(tester, 'd2', 'd4');
      await _queuePremove(tester, 'g1', 'f3');
      await _queuePremove(tester, 'b1', 'c3');
      await _queuePremove(tester, 'h2', 'h4');
      await _queuePremove(tester, 'a2', 'a4');
      expect(find.text('5 premoves'), findsOneWidget);
      // A sixth premove is rejected by the cap.
      await tester.tap(find.bySemanticsLabel('White piece on g2'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Empty square g4'));
      await tester.pump();
      expect(find.text('5 premoves'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('chessboard-premove-ghost-g2')),
        findsNothing,
      );
      await _settle(tester, steps: 16);
    });

    testWidgets('new game clears the premove queue', (tester) async {
      await _pumpPreplay(tester);
      await _playMove(tester, 'e2', 'e4');
      await _queuePremove(tester, 'd2', 'd4');
      expect(find.text('1 premove'), findsOneWidget);
      await tester.tap(find.text('Moves'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(
        find.byKey(const ValueKey<String>('play-new-game-button')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('1 premove'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('chessboard-premove-overlay')),
        findsNothing,
      );
      await _settle(tester);
    });

    testWidgets('a terminal state clears the premove queue', (tester) async {
      await _pumpPreplay(tester);
      await _playMove(tester, 'e2', 'e4');
      await _queuePremove(tester, 'd2', 'd4');
      await tester.tap(find.text('Moves'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(
        find.byKey(const ValueKey<String>('play-resign-button')),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(
        find.byKey(const ValueKey<String>('play-resign-confirm')),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('1 premove'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('chessboard-premove-overlay')),
        findsNothing,
      );
      await _settle(tester);
    });

    testWidgets('semantics tree stays stable with queued premoves', (
      tester,
    ) async {
      await _pumpPreplay(tester);
      await _playMove(tester, 'e2', 'e4');
      await _queuePremove(tester, 'd2', 'd4');
      await _queuePremove(tester, 'g1', 'f3');
      expect(
        find.byKey(const ValueKey<String>('chessboard-premove-overlay')),
        findsOneWidget,
      );
      expectSemanticsTreeInvariants(tester);
      expectSquareSemantics(tester, expectedCount: 64);
      await _settle(tester);
    });

    testWidgets('right-click with an empty queue does nothing', (tester) async {
      await _pumpPreplay(tester);
      await _playMove(tester, 'e2', 'e4');
      await tester.tapAt(
        tester.getCenter(find.byType(Chessboard)),
        buttons: kSecondaryButton,
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey<String>('chessboard-premove-overlay')),
        findsNothing,
      );
      await _settle(tester);
    });

    testWidgets('premove ghosts hide while the view is scrubbed', (
      tester,
    ) async {
      await _pumpPreplay(tester);
      await _playMove(tester, 'e2', 'e4');
      await _queuePremove(tester, 'd2', 'd4');
      expect(
        find.byKey(const ValueKey<String>('chessboard-premove-ghost-d2')),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('chessboard-premove-ghost-d2')),
        findsNothing,
      );
      expect(find.text('1 premove'), findsOneWidget); // queue survives.
      await _settle(tester);
    });
  });
}
