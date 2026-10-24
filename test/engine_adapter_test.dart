// Deterministic offline tests for the position-evaluation adapters in
// `lib/src/review/engine_adapter.dart`.
//
// Covers `HeuristicEvaluator` only: it is the pure-Dart, process-free
// surface (the `UciEngineAdapter` child-process paths are exercised by the
// self-gating real-engine `test/e2e_smoke_test.dart`). These tests must
// never spawn a process, open a socket, or read the wall clock.
//
// The malformed-JSON case pins the §11.34 fix: an unparseable variant
// JSON degrades to `unsupported` (never a fabricated score) while the
// decode failure is logged instead of silently swallowed.

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/review/engine_adapter.dart';

void main() {
  group('HeuristicEvaluator', () {
    final evaluator = HeuristicEvaluator();

    test('scores a standard FEN placement as supported', () async {
      final result = await evaluator.evaluate(
        'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      );
      expect(result.supported, isTrue);
      expect(result.scoreCp, isNotNull);
      expect(result.source, EngineSources.heuristic);
    });

    test('accepts variant JSON carrying a fen field', () async {
      final result =
          await evaluator.evaluate('{"fen":"8/8/8/8/8/8/8/8 w - - 0 1"}');
      expect(result.supported, isTrue);
      expect(result.scoreCp, isNotNull);
      expect(result.source, EngineSources.heuristic);
    });

    test('malformed variant JSON degrades to unsupported without throwing',
        () async {
      // `{"fen": unclosed` fails jsonDecode; the failure is logged and the
      // position degrades to unsupported rather than crashing or fabricating
      // a score.
      final result = await evaluator.evaluate('{"fen": unclosed');
      expect(result.supported, isFalse);
      expect(result.scoreCp, isNull);
      expect(result.source, EngineSources.heuristic);
    });

    test('variant JSON with an invalid placement is unsupported', () async {
      // `{"fen":"8/8"}` decodes fine but has only 2 of 8 FEN rows.
      final result = await evaluator.evaluate('{"fen":"8/8"}');
      expect(result.supported, isFalse);
      expect(result.scoreCp, isNull);
    });

    test('chaotic board without FEN interop is out of scope', () async {
      // No `fen` field: documented out of scope (class doc says a `fen`
      // field is required; `pieces`-only boards are unsupported).
      final result = await evaluator.evaluate('{"pieces":{"k":"e1"}}');
      expect(result.supported, isFalse);
      expect(result.scoreCp, isNull);
    });

    test('empty input is unsupported', () async {
      final result = await evaluator.evaluate('');
      expect(result.supported, isFalse);
      expect(result.scoreCp, isNull);
    });

    test('non-JSON garbage without a placement is unsupported', () async {
      final result = await evaluator.evaluate('not a fen');
      expect(result.supported, isFalse);
      expect(result.scoreCp, isNull);
    });
  });
}
