/// JSON tool schema for the `make_chess_move` function-calling contract.
///
/// This file is pure Dart (no Flutter imports) so it can be shared by every
/// LLM provider implementation and by unit-testable validation logic.
///
/// Contract summary:
/// * Tool name is [chessMoveToolName] (`make_chess_move`).
/// * Arguments are `from`, `to`, optional `promotion`, optional `phrase`.
/// * Only `from` and `to` are required; everything else is advisory.
/// * [MoveToolCall] is the parsed, validated form of one tool call.
/// * [systemPromptBuilder] produces the system instruction that forces the
///   model to act *only* through this tool (plus a short human-readable
///   phrase for the UI / commentary feed).
library;

/// Canonical tool name shared by all providers (OpenAI tools, Anthropic
/// tools, Gemini function declarations, Ollama, Mock).
const String chessMoveToolName = 'make_chess_move';

/// JSON-Schema definition of the tool parameters.
///
/// This is the single source of truth. Provider-specific envelopes
/// ([makeChessMoveToolJson], [anthropicChessMoveToolJson],
/// [geminiChessMoveDeclarationJson]) all embed this object.
///
/// Deliberately variant-safe: `from`/`to` carry no strict square pattern so
/// chaotic-variant coordinates are not rejected at the schema layer.
/// Legality is enforced later by [validateToolCall]-style checks against the
/// engine-provided legal move list.
const Map<String, Object> makeChessMoveParametersJson = {
  'type': 'object',
  'properties': {
    'from': {
      'type': 'string',
      'description':
          'Origin square of the move in the position\'s coordinate system '
          '(e.g. "e2" in standard chess).',
      'minLength': 2,
      'maxLength': 4,
    },
    'to': {
      'type': 'string',
      'description':
          'Destination square of the move in the position\'s coordinate '
          'system (e.g. "e4" in standard chess).',
      'minLength': 2,
      'maxLength': 4,
    },
    'promotion': {
      'type': 'string',
      'description':
          'Promotion piece for pawn promotions: one of "q", "r", "b", "n". '
          'Omit for all non-promotion moves.',
      'minLength': 1,
      'maxLength': 1,
    },
    'phrase': {
      'type': 'string',
      'description':
          'Very short human-readable comment about the move (a few words). '
          'Shown in the UI; never affects adjudication.',
      'maxLength': 200,
    },
  },
  'required': ['from', 'to'],
  'additionalProperties': false,
};

/// OpenAI / OpenAI-compatible (OpenRouter, Ollama, vLLM, …) tool envelope.
const Map<String, Object> makeChessMoveToolJson = {
  'type': 'function',
  'function': {
    'name': chessMoveToolName,
    'description':
        'Play exactly one chess move on the current board. Call this tool '
        'once per turn with the chosen move. Do not emit any other text.',
    'parameters': makeChessMoveParametersJson,
  },
};

/// Anthropic Messages API tool envelope (`input_schema` style).
const Map<String, Object> anthropicChessMoveToolJson = {
  'name': chessMoveToolName,
  'description':
      'Play exactly one chess move on the current board. Invoke this tool '
      'once per turn with the chosen move. Do not emit any other text.',
  'input_schema': makeChessMoveParametersJson,
};

/// Google Generative Language API function declaration
/// (`functionDeclarations` style).
const Map<String, Object> geminiChessMoveDeclarationJson = {
  'name': chessMoveToolName,
  'description':
      'Play exactly one chess move on the current board. Call this function '
      'once per turn with the chosen move. Do not emit any other text.',
  'parameters': makeChessMoveParametersJson,
};

/// Runtime copy of [anthropicChessMoveToolJson] as `Map<String, Object>`.
///
/// Needed because indexing a const map yields nullable values, so the const
/// itself cannot satisfy `List<Map<String, Object>>` request shapes.
/// Content is identical to [anthropicChessMoveToolJson].
Map<String, Object> anthropicChessMoveToolEnvelope() => {
      'name': chessMoveToolName,
      'description': '${anthropicChessMoveToolJson['description']}',
      'input_schema': makeChessMoveParametersJson,
    };

/// Runtime copy of [geminiChessMoveDeclarationJson] as `Map<String, Object>`.
/// See [anthropicChessMoveToolEnvelope] for why this is not const.
Map<String, Object> geminiChessMoveDeclarationEnvelope() => {
      'name': chessMoveToolName,
      'description': '${geminiChessMoveDeclarationJson['description']}',
      'parameters': makeChessMoveParametersJson,
    };

/// Builds the system prompt for one agent turn.
///
/// Deliberately **mode-agnostic**: standard and chaotic turns get the same
/// instructions (only the side-to-move label differs), so the model's natural
/// output is comparable across variants. The current board is supplied by the
/// user prompt; this prompt only explains how to express a move.
///
/// The model is told to act **only** through [chessMoveToolName] and to attach
/// a short `phrase` for display. Reasoning text outside the tool call is
/// tolerated by the streaming pipeline but never treated as a move.
String systemPromptBuilder({required String color}) {
  final side =
      color.trim().toLowerCase().startsWith('b') ? 'Black' : 'White';
  return 'You are playing a chess game as $side.\n'
      'On each turn you will be shown the current board from your side: your '
      'pieces are at the bottom.\n'
      'Make exactly one move by calling the "$chessMoveToolName" tool.\n'
      'Tool arguments:\n'
      '- "from" (required): origin square, e.g. "e2".\n'
      '- "to" (required): destination square, e.g. "e4".\n'
      '- "promotion" (optional): "q", "r", "b" or "n", only when a pawn '
      'reaches the last rank.\n'
      '- "phrase" (optional): a few words describing the move for spectators.\n'
      'Tool call examples:\n'
      '{"from":"e2","to":"e4"}\n'
      '{"from":"a7","to":"a8","promotion":"q","phrase":"Promote"}\n'
      'Move notation:\n'
      '- Castling: move the king two squares toward the rook (e1g1 or e1c1 '
      'for White; e8g8 or e8c8 for Black). Do not move the rook in the call.\n'
      '- En passant: give the capturing pawn\'s origin and destination (for '
      'example e5d6); the destination square is empty. It is available only '
      'when an en passant target is listed.\n'
      '- Promotion: set "promotion" to "q", "r", "b" or "n"; do not append it '
      'to "to".\n'
      'Call the tool exactly once per turn. Do not write the move as plain '
      'text and do not call any other tool.';
}

/// Parsed form of one `make_chess_move` tool call.
///
/// Instances are produced by [MoveToolCall.fromJson] (which throws
/// [FormatException] on malformed input — callers that must not throw
/// should go through `validateToolCall` instead) and consumed by the
/// agent runner / orchestrator after legality checks.
class MoveToolCall {
  /// Origin square, e.g. `'e2'`.
  final String from;

  /// Destination square, e.g. `'e4'`.
  final String to;

  /// Promotion piece (`'q'`, `'r'`, `'b'`, `'n'`), or `null`.
  final String? promotion;

  /// Short human-readable comment for the UI. Never adjudicated.
  final String? phrase;

  /// Creates a move tool call. Empty [from]/[to] are rejected.
  MoveToolCall({
    required String from,
    required String to,
    this.promotion,
    this.phrase,
  })  : from = from.trim(),
        to = to.trim() {
    if (this.from.isEmpty || this.to.isEmpty) {
      throw FormatException('MoveToolCall requires non-empty from/to.');
    }
  }

  /// UCI-style rendering of the move, e.g. `e2e4` or `e7e8q`.
  String get uci => '$from$to${promotion ?? ''}';

  /// Serializes to the tool-argument JSON shape.
  Map<String, Object?> toJson() {
    return {
      'from': from,
      'to': to,
      if (promotion != null) 'promotion': promotion,
      if (phrase != null) 'phrase': phrase,
    };
  }

  /// Parses tool-argument JSON.
  ///
  /// Accepts any [Map] (keys/values are read defensively). Throws
  /// [FormatException] when `from`/`to` are missing or not strings.
  /// `promotion`/`phrase` are optional; non-string values for them are
  /// coerced with `toString()` when non-null.
  factory MoveToolCall.fromJson(Map json) {
    final from = json['from'];
    final to = json['to'];
    if (from is! String || from.trim().isEmpty) {
      throw FormatException('Missing or invalid required arg "from": $from');
    }
    if (to is! String || to.trim().isEmpty) {
      throw FormatException('Missing or invalid required arg "to": $to');
    }
    final promotion = json['promotion'];
    final phrase = json['phrase'];
    var toText = to.trim();
    var promotionText = promotion?.toString();
    // Accept a UCI promotion suffix in `to` (e.g. {"to":"e8q"}) because some
    // models encode it that way; canonical form keeps it in `promotion`.
    if ((promotionText == null || promotionText.trim().isEmpty) &&
        toText.length == 3) {
      final suffix = toText.substring(2).toLowerCase();
      if (const <String>{'q', 'r', 'b', 'n'}.contains(suffix)) {
        promotionText = suffix;
        toText = toText.substring(0, 2);
      }
    }
    return MoveToolCall(
      from: from.trim(),
      to: toText,
      promotion: promotionText,
      phrase: phrase?.toString(),
    );
  }

  /// Copies with selectively replaced fields.
  MoveToolCall copyWith({
    String? from,
    String? to,
    String? promotion,
    String? phrase,
  }) {
    return MoveToolCall(
      from: from ?? this.from,
      to: to ?? this.to,
      promotion: promotion ?? this.promotion,
      phrase: phrase ?? this.phrase,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MoveToolCall &&
          other.from == from &&
          other.to == to &&
          other.promotion == promotion &&
          other.phrase == phrase;

  @override
  int get hashCode => Object.hash(from, to, promotion, phrase);

  @override
  String toString() {
    final suffix = phrase?.isEmpty == false ? ', phrase: "$phrase"' : '';
    return 'MoveToolCall($uci$suffix)';
  }
}
