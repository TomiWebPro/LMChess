// Widget + unit tests for the chessboard motion layer (§15.2).
//
// The board now renders an explicit from→to slide: when `squares` changes
// alongside a `motion` (BoardMove), the moving piece (plus a castling rook)
// slides from the origin to the destination over ~160 ms in an
// `IgnorePointer` + `ExcludeSemantics` overlay above the 64 stable square
// nodes. Captures fade the captured glyph, en passant fades it beside the
// destination, promotions swap at landing, interrupted flights retarget from
// the current visual position, and reduced-motion builds snap. Only the
// overlay rebuilds per frame — the 64 cells stay static behind a
// RepaintBoundary, so the AXTree never changes mid-flight.
//
// Uses deterministic data only — no network, engine process, or wall-clock.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/chess/move.dart'
    show AppliedMove, ChessMove, MoveFlag;
import 'package:llm_chess_arena/src/chess/piece.dart'
    show Piece, PieceColor, PieceType;
import 'package:llm_chess_arena/src/chess/square.dart' show Square;
import 'package:llm_chess_arena/src/theme/board_theme.dart';
import 'package:llm_chess_arena/src/theme/piece_theme.dart';
import 'package:llm_chess_arena/src/ui/widgets/board_motion.dart';
import 'package:llm_chess_arena/src/ui/widgets/chessboard.dart';

import '../support/semantics_invariants.dart';

const Key _overlayKey = ValueKey<String>('chessboard-motion-overlay');
const Key _pieceKey = ValueKey<String>('chessboard-motion-piece');
const Key _rookKey = ValueKey<String>('chessboard-motion-rook');
const Key _capturedKey = ValueKey<String>('chessboard-motion-captured');

/// Host that holds a squares snapshot + optional motion, mirroring how the
/// Play/Watch screens feed the board from retained `AppliedMove` receipts.
class _MotionHost extends StatefulWidget {
  const _MotionHost({super.key, this.disableAnimations = false, this.onTap});

  final bool disableAnimations;
  final ValueChanged<String>? onTap;

  @override
  State<_MotionHost> createState() => _MotionHostState();
}

class _MotionHostState extends State<_MotionHost> {
  Map<String, String> squares = const <String, String>{};
  BoardMove? motion;
  bool orientationWhite = true;

  void show(
    Map<String, String> next,
    BoardMove? nextMotion, {
    bool white = true,
  }) {
    setState(() {
      squares = next;
      motion = nextMotion;
      orientationWhite = white;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQueryData(disableAnimations: widget.disableAnimations),
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 400,
              child: Chessboard(
                squares: squares,
                motion: motion,
                orientationWhite: orientationWhite,
                boardTheme: BoardTheme.classic,
                pieceTheme: PieceTheme.meridian,
                interactive: true,
                onTapSquare: widget.onTap,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Screen-space center of a square on the 400×400 host board.
Offset _centerOf(
  WidgetTester tester,
  String square, {
  bool orientationWhite = true,
}) {
  final rect = tester.getRect(find.byType(Chessboard));
  final file = 'abcdefgh'.indexOf(square[0]);
  final rank = int.parse(square[1]) - 1;
  final col = orientationWhite ? file : 7 - file;
  final row = orientationWhite ? 7 - rank : rank;
  final cell = rect.width / 8;
  return rect.topLeft + Offset((col + 0.5) * cell, (row + 0.5) * cell);
}

Future<_MotionHostState> _pumpHost(
  WidgetTester tester, {
  bool disableAnimations = false,
  ValueChanged<String>? onTap,
}) async {
  final key = GlobalKey<_MotionHostState>();
  await tester.pumpWidget(
    _MotionHost(key: key, disableAnimations: disableAnimations, onTap: onTap),
  );
  await tester.pump();
  return key.currentState!;
}

/// Applies a transition: first renders the starting snapshot, then the
/// destination snapshot together with the [move] (exactly how the Play/Watch
/// screens feed the board from retained `AppliedMove` receipts).
Future<void> _showMove(
  WidgetTester tester,
  _MotionHostState host,
  Map<String, String> initial,
  Map<String, String> after,
  BoardMove move, {
  bool white = true,
}) async {
  host.show(initial, null, white: white);
  await tester.pump();
  host.show(after, move, white: white);
  await tester.pump();
}

/// Runs out a flight to completion and flushes the removal frame: the
/// controller reaches 1.0 ~160 ms after its first tick, and the overlay is
/// torn down on a follow-up frame, so two 160 ms pumps plus a settle pump
/// guarantee a fully-static destination snapshot.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 160));
  await tester.pump(const Duration(milliseconds: 160));
  await tester.pump();
}

void main() {
  group('§15.2 BoardMove value semantics', () {
    test('fromApplied maps an AppliedMove receipt', () {
      const receipt = AppliedMove(
        move: ChessMove(Square(4, 1), Square(4, 3), promotion: PieceType.queen),
        flag: MoveFlag.promotion,
        captured: Piece(PieceType.pawn, PieceColor.black),
        isCheck: true,
        isCheckmate: false,
        isStalemate: false,
        san: 'e2-e4=Q+',
      );
      final move = BoardMove.fromApplied(receipt);
      expect(move.from, const Square(4, 1));
      expect(move.to, const Square(4, 3));
      expect(move.flag, MoveFlag.promotion);
      expect(move.captured, const Piece(PieceType.pawn, PieceColor.black));
      expect(move.promotion, PieceType.queen);
    });

    test('equality covers from/to/flag/captured/promotion', () {
      const a = BoardMove(
        from: Square(4, 1),
        to: Square(4, 3),
        flag: MoveFlag.normal,
      );
      const b = BoardMove(
        from: Square(4, 1),
        to: Square(4, 3),
        flag: MoveFlag.normal,
      );
      const c = BoardMove(
        from: Square(4, 1),
        to: Square(4, 3),
        flag: MoveFlag.capture,
        captured: Piece(PieceType.pawn, PieceColor.black),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
      expect(a.hashCode == c.hashCode, isFalse);
    });

    test('toString shows the origin→destination pair and flag', () {
      const move = BoardMove(
        from: Square(4, 1),
        to: Square(4, 3),
        flag: MoveFlag.castleKingside,
      );
      expect(move.toString(), contains('e2→e4'));
      expect(move.toString(), contains('castleKingside'));
    });
  });

  group('§15.2 flight mechanics', () {
    testWidgets('quiet move slides from origin to destination then lands',
        (tester) async {
      final host = await _pumpHost(tester);
      await _showMove(
        tester,
        host,
        const <String, String>{'e2': 'wP'},
        const <String, String>{'e4': 'wP'},
        const BoardMove(from: Square(4, 1), to: Square(4, 3)),
      );

      // Flight starts at the origin square center.
      expect(find.byKey(_overlayKey), findsOneWidget);
      expect(find.byKey(_pieceKey), findsOneWidget);
      final startCenter = tester.getCenter(find.byKey(_pieceKey));
      final e2 = _centerOf(tester, 'e2');
      final e4 = _centerOf(tester, 'e4');
      expect((startCenter - e2).distance, lessThan(0.5));

      // Mid-flight: strictly between origin and destination, nearer e4
      // (ease-out means the piece has covered most of the distance).
      await tester.pump(const Duration(milliseconds: 80));
      final midCenter = tester.getCenter(find.byKey(_pieceKey));
      expect(midCenter.dy, greaterThan(e4.dy + 1));
      expect(midCenter.dy, lessThan(e2.dy - 1));
      expect(midCenter.dy, lessThan((e2.dy + e4.dy) / 2));

      // Completion: overlay gone, static glyph at destination.
      await _settle(tester);
      expect(find.byKey(_overlayKey), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('piece-e4-wP')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('snapshot change without motion snaps (seeking path)',
        (tester) async {
      final host = await _pumpHost(tester);
      host.show(const <String, String>{'e2': 'wP'}, null);
      await tester.pump();
      expect(find.byKey(_overlayKey), findsNothing);

      host.show(const <String, String>{'e4': 'wP'}, null);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(_overlayKey), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('piece-e4-wP')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('re-supplying the same transition does not replay it',
        (tester) async {
      final host = await _pumpHost(tester);
      const move = BoardMove(from: Square(4, 1), to: Square(4, 3));
      await _showMove(
        tester,
        host,
        const <String, String>{'e2': 'wP'},
        const <String, String>{'e4': 'wP'},
        move,
      );
      await _settle(tester);
      expect(find.byKey(_overlayKey), findsNothing);

      // A fresh instance with equal values and unchanged squares: the origin
      // is empty in the current snapshot, so no flight is created.
      host.show(
        const <String, String>{'e4': 'wP'},
        const BoardMove(from: Square(4, 1), to: Square(4, 3)),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(_overlayKey), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('capture fades the captured glyph on the destination square',
        (tester) async {
      final host = await _pumpHost(tester);
      await _showMove(
        tester,
        host,
        const <String, String>{'e2': 'wN', 'e4': 'bP'},
        const <String, String>{'e4': 'wN'},
        const BoardMove(
          from: Square(4, 1),
          to: Square(4, 3),
          flag: MoveFlag.capture,
          captured: Piece(PieceType.pawn, PieceColor.black),
        ),
      );

      expect(find.byKey(_capturedKey), findsOneWidget);
      final cCenter = tester.getCenter(find.byKey(_capturedKey));
      final e4 = _centerOf(tester, 'e4');
      expect((cCenter - e4).distance, lessThan(0.5));

      await _settle(tester);
      expect(find.byKey(_capturedKey), findsNothing);
      expect(find.byKey(_overlayKey), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('en passant fades the captured pawn beside the destination',
        (tester) async {
      final host = await _pumpHost(tester);
      // White pawn e5→f6 captures the black pawn on f5.
      await _showMove(
        tester,
        host,
        const <String, String>{'e5': 'wP', 'f5': 'bP'},
        const <String, String>{'f6': 'wP'},
        const BoardMove(
          from: Square(4, 4),
          to: Square(5, 5),
          flag: MoveFlag.enPassant,
        ),
      );

      expect(find.byKey(_capturedKey), findsOneWidget);
      final cCenter = tester.getCenter(find.byKey(_capturedKey));
      final f5 = _centerOf(tester, 'f5');
      final f6 = _centerOf(tester, 'f6');
      expect((cCenter - f5).distance, lessThan(0.5));
      expect((cCenter - f6).distance, greaterThan(10));

      await _settle(tester);
      expect(find.byKey(_capturedKey), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('piece-f6-wP')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('kingside castling slides king and rook together',
        (tester) async {
      final host = await _pumpHost(tester);
      await _showMove(
        tester,
        host,
        const <String, String>{'e1': 'wK', 'h1': 'wR'},
        const <String, String>{'g1': 'wK', 'f1': 'wR'},
        const BoardMove(from: Square(4, 0), to: Square(6, 0)),
      );

      expect(find.byKey(_pieceKey), findsOneWidget); // king
      expect(find.byKey(_rookKey), findsOneWidget); // rook
      final king = tester.getCenter(find.byKey(_pieceKey));
      final rook = tester.getCenter(find.byKey(_rookKey));
      final e1 = _centerOf(tester, 'e1');
      final g1 = _centerOf(tester, 'g1');
      final h1 = _centerOf(tester, 'h1');
      final f1 = _centerOf(tester, 'f1');
      expect((king - e1).distance, lessThan(0.5));
      expect((rook - h1).distance, lessThan(0.5));

      // Mid-flight: both pieces move toward their destinations.
      await tester.pump(const Duration(milliseconds: 80));
      final midKing = tester.getCenter(find.byKey(_pieceKey));
      final midRook = tester.getCenter(find.byKey(_rookKey));
      expect(midKing.dx, greaterThan(e1.dx + 1));
      expect(midKing.dx, lessThan(g1.dx));
      expect(midRook.dx, lessThan(h1.dx - 1));
      expect(midRook.dx, greaterThan(f1.dx));

      await _settle(tester);
      expect(find.byKey(_overlayKey), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('piece-g1-wK')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('piece-f1-wR')),
        findsOneWidget,
      );
      expect(
        (tester.getCenter(find.byKey(const ValueKey<String>('piece-g1-wK'))) -
                g1)
            .distance,
        lessThan(0.5),
      );
      expect(
        (tester.getCenter(find.byKey(const ValueKey<String>('piece-f1-wR'))) -
                f1)
            .distance,
        lessThan(0.5),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('queenside castling slides king and rook together',
        (tester) async {
      final host = await _pumpHost(tester);
      await _showMove(
        tester,
        host,
        const <String, String>{'e1': 'wK', 'a1': 'wR'},
        const <String, String>{'c1': 'wK', 'd1': 'wR'},
        const BoardMove(from: Square(4, 0), to: Square(2, 0)),
      );

      expect(find.byKey(_pieceKey), findsOneWidget); // king
      expect(find.byKey(_rookKey), findsOneWidget); // rook
      final king = tester.getCenter(find.byKey(_pieceKey));
      final rook = tester.getCenter(find.byKey(_rookKey));
      final e1 = _centerOf(tester, 'e1');
      final c1 = _centerOf(tester, 'c1');
      final a1 = _centerOf(tester, 'a1');
      final d1 = _centerOf(tester, 'd1');
      expect((king - e1).distance, lessThan(0.5));
      expect((rook - a1).distance, lessThan(0.5));

      // Mid-flight: both pieces move toward their destinations.
      await tester.pump(const Duration(milliseconds: 80));
      final midKing = tester.getCenter(find.byKey(_pieceKey));
      final midRook = tester.getCenter(find.byKey(_rookKey));
      expect(midKing.dx, lessThan(e1.dx - 1));
      expect(midKing.dx, greaterThan(c1.dx));
      expect(midRook.dx, greaterThan(a1.dx + 1));
      expect(midRook.dx, lessThan(d1.dx));

      await _settle(tester);
      expect(find.byKey(_overlayKey), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('piece-c1-wK')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('piece-d1-wR')),
        findsOneWidget,
      );
      expect(
        (tester.getCenter(find.byKey(const ValueKey<String>('piece-c1-wK'))) -
                c1)
            .distance,
        lessThan(0.5),
      );
      expect(
        (tester.getCenter(find.byKey(const ValueKey<String>('piece-d1-wR'))) -
                d1)
            .distance,
        lessThan(0.5),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('promotion swaps the piece at landing', (tester) async {
      final host = await _pumpHost(tester);
      await _showMove(
        tester,
        host,
        const <String, String>{'e7': 'wP'},
        const <String, String>{'e8': 'wQ'},
        const BoardMove(
          from: Square(4, 6),
          to: Square(4, 7),
          flag: MoveFlag.promotion,
          promotion: PieceType.queen,
        ),
      );

      // Mid-flight the overlay still shows the pawn from the old snapshot.
      expect(find.byKey(_pieceKey), findsOneWidget);
      await _settle(tester);
      expect(find.byKey(_overlayKey), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('piece-e8-wQ')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('reduced motion snaps instead of animating', (tester) async {
      final host = await _pumpHost(tester, disableAnimations: true);
      await _showMove(
        tester,
        host,
        const <String, String>{'e2': 'wP'},
        const <String, String>{'e4': 'wP'},
        const BoardMove(from: Square(4, 1), to: Square(4, 3)),
      );
      await tester.pump(const Duration(milliseconds: 80));

      expect(find.byKey(_overlayKey), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('piece-e4-wP')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('interrupted flight retargets from the current visual position',
        (tester) async {
      final host = await _pumpHost(tester);
      await _showMove(
        tester,
        host,
        const <String, String>{'e2': 'wP'},
        const <String, String>{'e4': 'wP'},
        const BoardMove(from: Square(4, 1), to: Square(4, 3)),
      );
      await tester.pump(const Duration(milliseconds: 80));

      // Interrupt with a new transition e4→e6 while the first is airborne.
      host.show(
        const <String, String>{'e6': 'wP'},
        const BoardMove(from: Square(4, 3), to: Square(4, 5)),
      );
      await tester.pump();

      final e2 = _centerOf(tester, 'e2');
      final e4 = _centerOf(tester, 'e4');
      final e6 = _centerOf(tester, 'e6');
      // The new flight must start where the old one was, not at e2 or e4.
      final retargeted = tester.getCenter(find.byKey(_pieceKey));
      expect(retargeted.dy, lessThan(e2.dy));
      expect(retargeted.dy, greaterThan(e4.dy + 5));
      expect(retargeted.dy, greaterThan(e6.dy));

      await _settle(tester);
      expect(find.byKey(_overlayKey), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('piece-e6-wP')),
        findsOneWidget,
      );
      expect(
        (tester.getCenter(find.byKey(const ValueKey<String>('piece-e6-wP'))) -
                e6)
            .distance,
        lessThan(0.5),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('flipped orientation animates through mirrored coordinates',
        (tester) async {
      final host = await _pumpHost(tester);
      await _showMove(
        tester,
        host,
        const <String, String>{'e2': 'wP'},
        const <String, String>{'e4': 'wP'},
        const BoardMove(from: Square(4, 1), to: Square(4, 3)),
        white: false,
      );

      final e2 = _centerOf(tester, 'e2', orientationWhite: false);
      final e4 = _centerOf(tester, 'e4', orientationWhite: false);
      final start = tester.getCenter(find.byKey(_pieceKey));
      expect((start - e2).distance, lessThan(0.5));

      await tester.pump(const Duration(milliseconds: 80));
      final mid = tester.getCenter(find.byKey(_pieceKey));
      expect(mid.dy, greaterThan(e2.dy));
      expect(mid.dy, lessThan(e4.dy));

      await _settle(tester);
      expect(find.byKey(_overlayKey), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('piece-e4-wP')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('§15.2 semantics + hit-testing safety', () {
    testWidgets('64 square nodes stay stable through a flight with zero '
        'reparenting', (tester) async {
      final host = await _pumpHost(tester);
      host.show(const <String, String>{'e2': 'wP'}, null);
      await tester.pump();

      final handle = tester.ensureSemantics();
      final before = captureSemantics(tester);
      expectSemanticsTreeInvariants(tester);
      expectSquareSemantics(tester, expectedCount: 64);

      await _showMove(
        tester,
        host,
        const <String, String>{'e2': 'wP'},
        const <String, String>{'e4': 'wP'},
        const BoardMove(from: Square(4, 1), to: Square(4, 3)),
      );
      expect(find.byKey(_overlayKey), findsOneWidget);

      // Mid-flight: tree identical, overlay contributes no nodes.
      await tester.pump(const Duration(milliseconds: 80));
      expectSemanticsTreeInvariants(tester);
      expectSquareSemantics(tester, expectedCount: 64);
      expectNoReparenting(
        parentMap(before),
        parentMap(captureSemantics(tester)),
      );

      await _settle(tester);
      expectSemanticsTreeInvariants(tester);
      expectSquareSemantics(tester, expectedCount: 64);
      expectNoReparenting(
        parentMap(before),
        parentMap(captureSemantics(tester)),
      );
      handle.dispose();
      expect(tester.takeException(), isNull);
    });

    testWidgets('overlay is IgnorePointer + ExcludeSemantics; taps still reach '
        'cells', (tester) async {
      final tapped = <String>[];
      final host = await _pumpHost(tester, onTap: tapped.add);
      await _showMove(
        tester,
        host,
        const <String, String>{'e2': 'wP'},
        const <String, String>{'e4': 'wP'},
        const BoardMove(from: Square(4, 1), to: Square(4, 3)),
      );

      // The overlay subtree must be wrapped in both guards.
      final overlayFinder = find.byKey(_overlayKey);
      expect(
        find.descendant(
          of: overlayFinder,
          matching: find.byType(IgnorePointer),
        ),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: overlayFinder,
          matching: find.byType(ExcludeSemantics),
        ),
        findsWidgets,
      );

      // Tapping the destination cell mid-flight must reach the cell beneath.
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(_centerOf(tester, 'e4'));
      await tester.pump();
      expect(tapped, contains('e4'));

      await _settle(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
