/// Variant-specific move classification.
///
/// The standard [classify] table still applies, but the chaotic rules add two
/// explicit tiers the user asked for:
///
/// * **super brilliant** — an illegal attempt resolved into a decisive
///   improvement (enemy king captured, or a non-standard interpretation that
///   gains at least [superBrilliantGain] cp from a non-winning position);
/// * **super blunder** — the mover loses on the spot (last king captured,
///   last king capturable next, or mate against the mover from a non-lost
///   position).
///
/// Scores are White-relative centipawns; this function normalizes to the
/// mover before comparing, exactly like [classify].
library;

import 'quality.dart';

/// Centipawn delta that qualifies a non-standard illegal interpretation as
/// "super brilliant" for `super brilliant` labeling.
const int superBrilliantGain = 300;

/// A position at or above this mover-relative score is already winning, so a
/// further gain is not labeled super brilliant.
const int alreadyWinningCp = 900;

/// Mate anchors used by Stockfish projections.
const int variantMateScore = 90000;

/// Classifies one variant ply.
QualityAssessment classifyVariantMove({
  required int? beforeCp,
  required int? afterCp,
  required bool moverIsWhite,
  required bool supported,
  required bool attemptWasStandardLegal,
  required bool interpretationIsNonStandard,
  required bool capturesKing,
  required bool enemyKingTerminalLoss,
  required bool moverKingTerminalLoss,
  required bool kingCapturableNext,
  required bool mateAgainstMover,
  required bool wasAlreadyLost,
  required bool wasAlreadyWinning,
  required int moverKingsAfter,
  required String source,
}) {
  final tags = <String>[
    if (!attemptWasStandardLegal) 'illegal-attempt',
    if (interpretationIsNonStandard) 'interpreted',
    if (source == 'variant-heuristic') 'variant-heuristic',
    if (wasAlreadyLost) 'already-lost',
  ];

  if (!supported) {
    return QualityAssessment(
      quality: MoveQuality.unsupported,
      lossCp: null,
      rationale: 'No evaluation backed this variant position; '
          'no quality judgment is made (source: $source).',
      beforeCp: beforeCp,
      afterCp: afterCp,
      supported: false,
      tags: tags,
    );
  }

  final loss = _loss(beforeCp, afterCp, moverIsWhite);
  if (loss == null) {
    return QualityAssessment(
      quality: MoveQuality.unsupported,
      lossCp: null,
      rationale: 'Missing before/after scores; no quality judgment is made.',
      beforeCp: beforeCp,
      afterCp: afterCp,
      supported: false,
      tags: tags,
    );
  }

  // Both last kings gone: a terminal draw, not a blunder or brilliance.
  if (enemyKingTerminalLoss && moverKingTerminalLoss) {
    return QualityAssessment(
      quality: MoveQuality.best,
      lossCp: loss,
      rationale: 'Both last kings captured — terminal draw.',
      beforeCp: beforeCp,
      afterCp: afterCp,
      tags: <String>[...tags, 'terminal-draw'],
    );
  }

  if (enemyKingTerminalLoss || capturesKing) {
    return QualityAssessment(
      quality: MoveQuality.superBrilliant,
      lossCp: loss,
      rationale: enemyKingTerminalLoss
          ? 'Captured the enemy\'s last king — terminal win.'
          : 'Captured an enemy king; the variant\'s decisive mechanic.',
      beforeCp: beforeCp,
      afterCp: afterCp,
      tags: <String>[
        ...tags,
        'king-capture',
        if (enemyKingTerminalLoss) 'terminal-win',
      ],
    );
  }

  if (moverKingTerminalLoss) {
    return QualityAssessment(
      quality: MoveQuality.superBlunder,
      lossCp: loss,
      rationale: 'The mover\'s last king is gone — instant loss.',
      beforeCp: beforeCp,
      afterCp: afterCp,
      tags: <String>[...tags, 'instant-loss', 'terminal-loss'],
    );
  }

  if (!wasAlreadyLost &&
      moverKingsAfter == 1 &&
      (kingCapturableNext || mateAgainstMover)) {
    return QualityAssessment(
      quality: MoveQuality.superBlunder,
      lossCp: loss,
      rationale: kingCapturableNext
          ? 'The mover\'s last king is capturable next — instant loss.'
          : 'Mate against the mover from a non-lost position.',
      beforeCp: beforeCp,
      afterCp: afterCp,
      tags: <String>[...tags, 'instant-loss'],
    );
  }

  if (!attemptWasStandardLegal &&
      interpretationIsNonStandard &&
      !wasAlreadyWinning &&
      loss <= -superBrilliantGain) {
    return QualityAssessment(
      quality: MoveQuality.superBrilliant,
      lossCp: loss,
      rationale: 'An illegal attempt resolved into a decisive '
          '${-loss} cp improvement.',
      beforeCp: beforeCp,
      afterCp: afterCp,
      tags: <String>[...tags, 'super-brilliant'],
    );
  }

  final tier = _tierFor(loss);
  return QualityAssessment(
    quality: tier,
    lossCp: loss,
    rationale: _rationaleFor(tier, loss, tags),
    beforeCp: beforeCp,
    afterCp: afterCp,
    tags: tags,
  );
}

int? _loss(int? beforeCp, int? afterCp, bool moverIsWhite) {
  if (beforeCp == null || afterCp == null) return null;
  final before = moverIsWhite ? beforeCp : -beforeCp;
  final after = moverIsWhite ? afterCp : -afterCp;
  return before - after;
}

MoveQuality _tierFor(int loss) {
  if (loss <= 10) return MoveQuality.best;
  if (loss <= 25) return MoveQuality.excellent;
  if (loss <= 60) return MoveQuality.good;
  if (loss <= 120) return MoveQuality.inaccuracy;
  if (loss <= 250) return MoveQuality.mistake;
  if (loss <= 500) return MoveQuality.blunder;
  return MoveQuality.superBlunder;
}

String _rationaleFor(MoveQuality tier, int loss, List<String> tags) {
  final suffix = tags.contains('variant-heuristic')
      ? ' (variant heuristic, not Stockfish)'
      : '';
  if (loss < 0) {
    return '${tier.name}: improved by ${-loss} cp$suffix.';
  }
  return '${tier.name}: lost $loss cp$suffix.';
}
