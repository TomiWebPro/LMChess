/// Move-quality classification from engine/heuristic score swings.
///
/// # Perspective normalization
///
/// Input scores ([beforeCp]/[afterCp]) are **White-relative** centipawns
/// (see `engine_adapter.dart`). [classify] converts both to the mover's
/// perspective (`mover = moverIsWhite ? cp : -cp`) and defines
///
/// ```
/// lossCp = moverBefore - moverAfter   // >= 0 means the move gave
///                                      // something away
/// ```
///
/// All thresholds below apply to this mover-relative [lossCp] (or the
/// symmetric gain). A move that is good for White reads as a blunder for
/// Black at the same board — the normalization is what makes that work.
///
/// # Calibrated threshold table (mover-relative centipawns)
///
/// | lossCp range | quality (engine-supported)                    |
/// |--------------|-----------------------------------------------|
/// | <= 10        | [MoveQuality.best]                            |
/// | 11 – 25      | [MoveQuality.excellent]                       |
/// | 26 – 60      | [MoveQuality.good]                           |
/// | 61 – 120     | [MoveQuality.inaccuracy]                      |
/// | 121 – 250    | [MoveQuality.mistake]                         |
/// | 251 – 500    | [MoveQuality.blunder]                         |
/// | > 500        | [MoveQuality.superBlunder]                    |
///
/// Special cases (checked first, in order):
///
/// 1. `supported == false` → [MoveQuality.unsupported] (never guess).
/// 2. `exposesOwnKing == true` → [MoveQuality.superBlunder] (self king
///    exposure loses by force under king-capture rules).
/// 3. `isKingCapture == true` (the move decisively enables/captures the
///    enemy king) → [MoveQuality.superBrilliant].
/// 4. Large gains (`gainCp >= 300`, i.e. `lossCp <= -300`) with an
///    otherwise sound move → [MoveQuality.brilliant]; gains in
///    `150..299` → [MoveQuality.superBrilliant] is NOT used (reserved
///    for king captures) — these map to [MoveQuality.best] with a
///    "winning" rationale. (Rationale: keep the top tier semantically
///    tied to the variant's decisive mechanic.)
/// 5. Illegal-but-harmless: [wasIllegalAttempt] alone never changes the
///    tier — only the resulting [lossCp] matters. A recovered illegal
///    attempt that still finds the best move is [MoveQuality.best] with
///    a note in [QualityAssessment.rationale].
library;

/// Quality tier for a single move. Ordered worst → best by index only
/// for [unsupported] (index 0); do not rely on index ordering otherwise.
enum MoveQuality {
  /// No evaluation available (engine/heuristic unsupported or missing).
  unsupported,

  /// Decisive king-capture enabler (chaotic) — reserved tier.
  superBrilliant,

  /// Deep winning sacrifice / large sound gain.
  brilliant,

  /// Engine's top choice (loss <= 10 cp).
  best,

  /// Near-best (loss 11–25 cp).
  excellent,

  /// Solid (loss 26–60 cp).
  good,

  /// Slight slip (loss 61–120 cp).
  inaccuracy,

  /// Clear error (loss 121–250 cp).
  mistake,

  /// Severe error (loss 251–500 cp).
  blunder,

  /// Game-losing swing (loss > 500 cp) or self-king exposure.
  superBlunder,
}

/// Assessment of one move with the evidence behind it.
class QualityAssessment {
  /// Assigned tier.
  final MoveQuality quality;

  /// Mover-relative centipawn loss (`before - after`); null when
  /// either score was missing.
  final int? lossCp;

  /// Short human-readable explanation (already localized-neutral).
  final String rationale;

  /// Raw White-relative inputs, echoed for audit.
  final int? beforeCp;
  final int? afterCp;

  /// False when no evaluation backed this assessment.
  final bool supported;

  /// Extra provenance labels (`illegal-attempt`, `king-capture`,
  /// `instant-loss`, `variant-heuristic`, …). UI-only; never affects tiers.
  final List<String> tags;

  /// Creates an assessment.
  const QualityAssessment({
    required this.quality,
    required this.lossCp,
    required this.rationale,
    this.beforeCp,
    this.afterCp,
    this.supported = true,
    this.tags = const <String>[],
  });

  /// Serializes with stable field ordering.
  Map<String, Object?> toJson() => <String, Object?>{
        'quality': quality.name,
        'lossCp': lossCp,
        'rationale': rationale,
        'beforeCp': beforeCp,
        'afterCp': afterCp,
        'supported': supported,
        'tags': tags,
      };

  @override
  String toString() => 'QualityAssessment($quality, lossCp=$lossCp)';
}

/// Classifies a move from White-relative engine scores.
///
/// * [beforeCp]: position score before the move (White-relative).
/// * [afterCp]: position score after the move (White-relative).
/// * [moverIsWhite]: whose move it was (drives normalization).
/// * [wasIllegalAttempt]: the turn included >= 1 illegal attempt. Never
///   auto-penalizes: only [lossCp] moves the tier; the flag appends a
///   note to the rationale.
/// * [isKingCapture]: the move decisively captures/enables capture of
///   the enemy king → [MoveQuality.superBrilliant].
/// * [exposesOwnKing]: the move exposes the mover's own king to capture
///   → [MoveQuality.superBlunder]. Defaults to false.
/// * [supported]: false when no evaluation backs the scores →
///   [MoveQuality.unsupported] regardless of inputs.
QualityAssessment classify({
  required int? beforeCp,
  required int? afterCp,
  required bool moverIsWhite,
  required bool wasIllegalAttempt,
  required bool isKingCapture,
  required bool supported,
  bool exposesOwnKing = false,
}) {
  if (!supported) {
    return QualityAssessment(
      quality: MoveQuality.unsupported,
      lossCp: null,
      rationale: 'Position evaluation is not supported for this variant; '
          'no quality judgment is made.',
      beforeCp: beforeCp,
      afterCp: afterCp,
      supported: false,
    );
  }
  if (exposesOwnKing) {
    return QualityAssessment(
      quality: MoveQuality.superBlunder,
      lossCp: _loss(beforeCp, afterCp, moverIsWhite),
      rationale: 'Move exposes the mover\'s own king to capture, '
          'which loses by force under king-capture rules.',
      beforeCp: beforeCp,
      afterCp: afterCp,
    );
  }
  if (isKingCapture) {
    return QualityAssessment(
      quality: MoveQuality.superBrilliant,
      lossCp: _loss(beforeCp, afterCp, moverIsWhite),
      rationale: 'Decisive king capture (or forced enabler) — '
          'the game-winning mechanic.',
      beforeCp: beforeCp,
      afterCp: afterCp,
    );
  }

  final loss = _loss(beforeCp, afterCp, moverIsWhite);
  if (loss == null) {
    return const QualityAssessment(
      quality: MoveQuality.unsupported,
      lossCp: null,
      rationale: 'Missing before/after scores; no quality judgment is made.',
      supported: false,
    );
  }

  final illegalNote = wasIllegalAttempt
      ? ' (turn included an illegal attempt, recovered).'
      : '';

  // Large sound gains: brilliant, but the top tier stays reserved for
  // king captures (see library docs).
  if (loss <= -300) {
    return QualityAssessment(
      quality: MoveQuality.brilliant,
      lossCp: loss,
      rationale: 'Found a large winning swing of ${-loss} cp.$illegalNote',
      beforeCp: beforeCp,
      afterCp: afterCp,
    );
  }
  if (loss <= 10) {
    return QualityAssessment(
      quality: MoveQuality.best,
      lossCp: loss,
      rationale: loss < 0
          ? 'Best move, improving by ${-loss} cp.$illegalNote'
          : 'Best move (loss $loss cp).$illegalNote',
      beforeCp: beforeCp,
      afterCp: afterCp,
    );
  }
  if (loss <= 25) {
    return QualityAssessment(
      quality: MoveQuality.excellent,
      lossCp: loss,
      rationale: 'Excellent — only $loss cp conceded.$illegalNote',
      beforeCp: beforeCp,
      afterCp: afterCp,
    );
  }
  if (loss <= 60) {
    return QualityAssessment(
      quality: MoveQuality.good,
      lossCp: loss,
      rationale: 'Good — $loss cp conceded.$illegalNote',
      beforeCp: beforeCp,
      afterCp: afterCp,
    );
  }
  if (loss <= 120) {
    return QualityAssessment(
      quality: MoveQuality.inaccuracy,
      lossCp: loss,
      rationale: 'Inaccuracy — $loss cp conceded.$illegalNote',
      beforeCp: beforeCp,
      afterCp: afterCp,
    );
  }
  if (loss <= 250) {
    return QualityAssessment(
      quality: MoveQuality.mistake,
      lossCp: loss,
      rationale: 'Mistake — $loss cp conceded.$illegalNote',
      beforeCp: beforeCp,
      afterCp: afterCp,
    );
  }
  if (loss <= 500) {
    return QualityAssessment(
      quality: MoveQuality.blunder,
      lossCp: loss,
      rationale: 'Blunder — $loss cp conceded.$illegalNote',
      beforeCp: beforeCp,
      afterCp: afterCp,
    );
  }
  return QualityAssessment(
    quality: MoveQuality.superBlunder,
    lossCp: loss,
    rationale: 'Game-losing swing — $loss cp conceded.$illegalNote',
    beforeCp: beforeCp,
    afterCp: afterCp,
  );
}

/// Mover-relative loss, or null when either score is missing.
int? _loss(int? beforeCp, int? afterCp, bool moverIsWhite) {
  if (beforeCp == null || afterCp == null) return null;
  final before = moverIsWhite ? beforeCp : -beforeCp;
  final after = moverIsWhite ? afterCp : -afterCp;
  return before - after;
}
