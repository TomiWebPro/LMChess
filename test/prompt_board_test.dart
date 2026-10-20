// Prompt contract: both game modes see the same board-only prompt.
//
// These tests pin the research contract: no legal-move list, no FEN/JSON, no
// mode label, no clocks, and a perspective-correct board with the mover's
// pieces at the bottom. Standard and chaotic requests at the same position
// must produce byte-identical prompts.
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/agent/agent_runner.dart';
import 'package:llm_chess_arena/src/llm/prompt_board.dart';
import 'package:llm_chess_arena/src/llm/tool_schema.dart';

const Map<String, String> _corners = <String, String>{
  'e1': 'K',
  'e8': 'k',
  'a1': 'R',
  'h8': 'r',
};

const String _board =
    '    a b c d e f g h\n'
    '  +-----------------+\n'
    '8 | r . . . k . . r |\n'
    '7 | . . . . . . . . |\n'
    '6 | . . . . . . . . |\n'
    '5 | . . . . . . . . |\n'
    '4 | . . . . . . . . |\n'
    '3 | . . . . . . . . |\n'
    '2 | . . . . . . . . |\n'
    '1 | R . . . K . . . |\n'
    '  +-----------------+\n'
    '    a b c d e f g h';

AgentTurnRequest _request(String mode, {bool acceptAnyMove = false}) =>
    AgentTurnRequest(
      positionFenOrJson: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR '
          'w KQkq - 0 1',
      legalMovesUci: const <String>['e2e4', 'd2d4'],
      boardText: _board,
      mode: mode,
      color: 'w',
      acceptAnyMove: acceptAnyMove,
    );

void main() {
  group('renderBoardForPrompt', () {
    test('White sees ranks 8..1 and files a..h', () {
      final text = renderBoardForPrompt(
        squares: _corners,
        sideToMove: 'white',
      );
      final lines = text.split('\n');
      expect(lines.first.trim(), 'a b c d e f g h');
      expect(lines.last.trim(), 'a b c d e f g h');
      expect(
        lines
            .where((line) => RegExp(r'^[1-8] \|').hasMatch(line))
            .map((line) => line[0])
            .join(),
        '87654321',
      );
      expect(lines.firstWhere((l) => l.startsWith('8 |')), contains('r'));
      expect(lines.firstWhere((l) => l.startsWith('1 |')), contains('R'));
    });

    test('Black sees ranks 1..8 and files h..a (180° rotation)', () {
      final text = renderBoardForPrompt(
        squares: _corners,
        sideToMove: 'black',
      );
      final lines = text.split('\n');
      expect(lines.first.trim(), 'h g f e d c b a');
      expect(lines.last.trim(), 'h g f e d c b a');
      expect(
        lines
            .where((line) => RegExp(r'^[1-8] \|').hasMatch(line))
            .map((line) => line[0])
            .join(),
        '12345678',
      );
      // Black's home rank (8) is at the bottom; White's (1) at the top.
      expect(lines.firstWhere((l) => l.startsWith('1 |')), contains('R'));
      expect(lines.firstWhere((l) => l.startsWith('8 |')), contains('r'));
      // Files are mirrored: the h-file is leftmost.
      final rank8 = lines.firstWhere((l) => l.startsWith('8 |'));
      expect(rank8.indexOf('r'), lessThan(rank8.indexOf('k')));
    });

    test('malformed entries render as empty squares', () {
      final text = renderBoardForPrompt(
        squares: const <String, String>{'e4': '', 'd4': 'xx', 'c4': 'Q'},
        sideToMove: 'white',
      );
      final rank4 = text.split('\n').firstWhere((l) => l.startsWith('4 |'));
      expect(rank4, contains('Q'));
      expect(rank4, contains('.'));
    });
  });

  group('agent prompt', () {
    test('standard and chaotic prompts are byte-identical', () {
      const runner = AgentRunner();
      final standard = runner.buildUserPrompt(_request('standard'));
      final chaotic = runner.buildUserPrompt(
        _request('chaotic', acceptAnyMove: true),
      );
      expect(standard, chaotic);
    });

    test('prompt is board-only: no legal list, FEN/JSON, mode or clocks', () {
      final prompt = const AgentRunner().buildUserPrompt(_request('standard'));
      expect(prompt, contains(_board));
      expect(prompt, contains('Side to move: White'));
      expect(prompt, contains('Castling rights: -'));
      expect(prompt, contains('En passant target: -'));
      expect(prompt, isNot(contains('Legal moves')));
      expect(prompt, isNot(contains('e2e4')));
      expect(prompt, isNot(contains('rnbqkbnr')));
      expect(prompt, isNot(contains('Mode')));
      expect(prompt, isNot(contains('Clocks')));
    });

    test('system prompt teaches every tool argument and is mode-agnostic', () {
      final prompt = systemPromptBuilder(color: 'w');
      expect(prompt, contains(chessMoveToolName));
      expect(prompt, contains('"from"'));
      expect(prompt, contains('"to"'));
      expect(prompt, contains('"promotion"'));
      expect(prompt, contains('"phrase"'));
      expect(prompt, contains('{"from":"e2","to":"e4"}'));
      expect(prompt, contains('"promotion":"q"'));
      expect(prompt, contains('e1g1'));
      expect(prompt, contains('e5d6'));
      expect(prompt.toLowerCase(), isNot(contains('chaotic')));
      expect(prompt.toLowerCase(), isNot(contains('standard')));
      expect(prompt.toLowerCase(), isNot(contains('legal move')));
    });

    test('promotion suffix in "to" is normalized into the field', () {
      final call = MoveToolCall.fromJson(<String, Object?>{
        'from': 'e7',
        'to': 'e8q',
      });
      expect(call.to, 'e8');
      expect(call.promotion, 'q');
      expect(call.uci, 'e7e8q');

      // A 3-character variant coordinate ending in a digit is left alone.
      final variant = MoveToolCall.fromJson(<String, Object?>{
        'from': 'a7',
        'to': 'a10',
      });
      expect(variant.to, 'a10');
      expect(variant.promotion, isNull);
    });
  });
}
