// Variant classification: normal tiers, super brilliant, super blunder.
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/review/quality.dart';
import 'package:llm_chess_arena/src/review/variant_quality.dart';

QualityAssessment _classify({
  int? before = 0,
  int? after = 0,
  bool moverIsWhite = true,
  bool supported = true,
  bool legal = true,
  bool nonStandard = false,
  bool captures = false,
  bool enemyTerminal = false,
  bool moverTerminal = false,
  bool capturableNext = false,
  bool mateAgainst = false,
  bool alreadyLost = false,
  bool alreadyWinning = false,
  int moverKingsAfter = 1,
  String source = 'stockfish-uci',
}) =>
    classifyVariantMove(
      beforeCp: before,
      afterCp: after,
      moverIsWhite: moverIsWhite,
      supported: supported,
      attemptWasStandardLegal: legal,
      interpretationIsNonStandard: nonStandard,
      capturesKing: captures,
      enemyKingTerminalLoss: enemyTerminal,
      moverKingTerminalLoss: moverTerminal,
      kingCapturableNext: capturableNext,
      mateAgainstMover: mateAgainst,
      wasAlreadyLost: alreadyLost,
      wasAlreadyWinning: alreadyWinning,
      moverKingsAfter: moverKingsAfter,
      source: source,
    );

void main() {
  test('standard loss thresholds', () {
    // White mover: loss = afterCp negated relative to before.
    expect(_classify(after: -10).quality, MoveQuality.best);
    expect(_classify(after: -11).quality, MoveQuality.excellent);
    expect(_classify(after: -26).quality, MoveQuality.good);
    expect(_classify(after: -61).quality, MoveQuality.inaccuracy);
    expect(_classify(after: -121).quality, MoveQuality.mistake);
    expect(_classify(after: -251).quality, MoveQuality.blunder);
    expect(_classify(after: -501).quality, MoveQuality.superBlunder);
  });

  test('an illegal but decisive interpretation is super brilliant', () {
    final quality = _classify(
      before: 0,
      after: 400,
      legal: false,
      nonStandard: true,
    );
    expect(quality.quality, MoveQuality.superBrilliant);
    expect(quality.tags, contains('illegal-attempt'));
    expect(quality.tags, contains('super-brilliant'));
  });

  test('a merely good illegal interpretation is not super brilliant', () {
    final quality = _classify(
      before: 0,
      after: 299,
      legal: false,
      nonStandard: true,
    );
    expect(quality.quality, MoveQuality.best);
  });

  test('already winning positions do not earn super brilliant', () {
    final quality = _classify(
      before: 1000,
      after: 1400,
      legal: false,
      nonStandard: true,
      alreadyWinning: true,
    );
    expect(quality.quality, isNot(MoveQuality.superBrilliant));
  });

  test('king capture and terminal king loss map to the super tiers', () {
    expect(_classify(captures: true).quality, MoveQuality.superBrilliant);
    expect(_classify(enemyTerminal: true).quality, MoveQuality.superBrilliant);
    expect(_classify(moverTerminal: true).quality, MoveQuality.superBlunder);
    expect(
      _classify(moverTerminal: true).tags,
      contains('instant-loss'),
    );
  });

  test('a last king capturable next is an instant-loss super blunder', () {
    final quality = _classify(capturableNext: true);
    expect(quality.quality, MoveQuality.superBlunder);
    expect(quality.tags, contains('instant-loss'));
  });

  test('already lost positions do not get a second super-blunder', () {
    final quality = _classify(
      capturableNext: true,
      alreadyLost: true,
      after: -10,
    );
    expect(quality.quality, isNot(MoveQuality.superBlunder));
    expect(quality.tags, contains('already-lost'));
  });

  test('both last kings gone is a terminal draw, not a blunder', () {
    final quality = _classify(
      enemyTerminal: true,
      moverTerminal: true,
    );
    expect(quality.quality, MoveQuality.best);
    expect(quality.tags, contains('terminal-draw'));
  });

  test('heuristic source is labeled and never claims engine truth', () {
    final quality = _classify(source: 'variant-heuristic');
    expect(quality.tags, contains('variant-heuristic'));
    expect(quality.rationale.toLowerCase(), contains('not stockfish'));
  });

  test('unsupported positions are never guessed', () {
    final quality = _classify(supported: false);
    expect(quality.quality, MoveQuality.unsupported);
    expect(quality.supported, isFalse);
  });
}
