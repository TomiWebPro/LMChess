/// Shared UI-layer models and Riverpod providers: the agent catalog and the
/// named-route constants.
///
/// These are deliberately lightweight, codegen-free stores (plain
/// [ChangeNotifier]s behind `ChangeNotifierProvider`s) so the UI compiles
/// standalone. They mirror the domain layer's vocabulary — when the backend
/// modules land, replace the bodies with adapters instead of changing the
/// screens:
///
/// * [AgentConfig]/[AgentListStore]/[agentListProvider] — configured agents.
/// * [ArenaRoutes] — the app route table constants.
///
/// NOTE: the former [EventStore]/[eventStoreProvider] and
/// `OrchestratorStore`/`orchestratorProvider` UI shadows were removed — they
/// had zero screen consumers (the real event store is
/// `stats/event_log.dart`'s `EventStore`, surfaced through
/// `backend_bridge.dart`'s telemetry singletons). Keeping unused mutable
/// providers invites accidental drift, so the surface is intentionally the
/// agent catalog plus route constants only.
///
/// Declared here (rather than `app.dart`) so screens can consume providers
/// without import cycles; `app.dart` re-exports them as the app's provider
/// surface.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Named routes for the app shell and deep links.
class ArenaRoutes {
  /// Home dashboard.
  static const String home = '/';

  /// Agent configuration.
  static const String agents = '/agents';

  /// Human vs AI.
  static const String play = '/play';

  /// AI vs AI watch room.
  static const String watch = '/watch';

  /// Tournament arena.
  static const String arena = '/arena';

  /// Statistics dashboards.
  static const String stats = '/stats';

  /// Game review.
  static const String review = '/review';

  /// Theme + app settings.
  static const String settings = '/settings';
}

/// Configuration of one LLM (or human-proxy) agent.
///
/// Mirrors the agent-setup form fields; the orchestrator backend is expected
/// to accept the same shape when wiring up real play.
class AgentConfig {
  /// Creates an agent config.
  AgentConfig({
    required this.id,
    required this.name,
    required this.provider,
    required this.model,
    this.temperature = 0.7,
    this.maxTokens = 1024,
    this.systemPrompt = '',
    this.userPromptTemplate = '',
    this.apiKeyRef,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Stable id (uuid in practice, editable in demos).
  final String id;

  /// Display name.
  String name;

  /// Provider key (`'openai'`, `'anthropic'`, `'gemini'`, `'custom'`, ...).
  String provider;

  /// Model id (`'gpt-4o'`, ...).
  String model;

  /// Sampling temperature 0..2.
  double temperature;

  /// Max completion tokens.
  int maxTokens;

  /// System prompt.
  String systemPrompt;

  /// User-prompt template (`{fen}` / `{moves}` placeholders).
  String userPromptTemplate;

  /// Opaque secure-storage reference for this agent's API key (never the key
  /// itself). `null` means "no key stored" (local Ollama / mock / demo).
  /// The secret lives in `SecureKeyStore` under this ref; the catalog only
  /// ever persists the ref.
  String? apiKeyRef;

  /// Creation timestamp.
  final DateTime createdAt;

  /// One-line `provider/model` summary for cards and dropdowns.
  String get summary => '$provider/$model';

  /// Copies with selective overrides.
  AgentConfig copyWith({
    String? name,
    String? provider,
    String? model,
    double? temperature,
    int? maxTokens,
    String? systemPrompt,
    String? userPromptTemplate,
    String? apiKeyRef,
  }) {
    return AgentConfig(
      id: id,
      name: name ?? this.name,
      provider: provider ?? this.provider,
      model: model ?? this.model,
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      userPromptTemplate: userPromptTemplate ?? this.userPromptTemplate,
      apiKeyRef: apiKeyRef ?? this.apiKeyRef,
      createdAt: createdAt,
    );
  }

  /// Validates the config, returning human-readable problems (empty = ok).
  List<String> validate() {
    final problems = <String>[];
    if (name.trim().isEmpty) problems.add('Name is required.');
    if (provider.trim().isEmpty) problems.add('Provider is required.');
    if (model.trim().isEmpty) problems.add('Model is required.');
    if (temperature < 0 || temperature > 2) {
      problems.add('Temperature must be within 0..2.');
    }
    if (maxTokens <= 0) problems.add('Max tokens must be positive.');
    return problems;
  }
}

/// In-memory agent catalog with two seeded demo agents.
///
/// The seeds keep selectors and watch rooms usable before the backend is
/// wired; remove them once persistent storage lands.
class AgentListStore extends ChangeNotifier {
  /// Creates the store, seeding two demo agents when [seedDemos] is true.
  AgentListStore({bool seedDemos = true}) {
    if (seedDemos) {
      _agents.addAll(<AgentConfig>[
        AgentConfig(
          id: 'demo-white',
          name: 'Demo White',
          provider: 'demo',
          model: 'demo-1',
          systemPrompt: 'You play White. Prefer classical openings.',
        ),
        AgentConfig(
          id: 'demo-black',
          name: 'Demo Black',
          provider: 'demo',
          model: 'demo-1',
          systemPrompt: 'You play Black. Prefer counterplay.',
        ),
      ]);
    }
  }

  final List<AgentConfig> _agents = <AgentConfig>[];

  /// All agents, unmodifiable.
  List<AgentConfig> get agents => List<AgentConfig>.unmodifiable(_agents);

  /// Looks up an agent by [id], or `null` when unknown.
  AgentConfig? byId(String? id) {
    if (id == null) return null;
    for (final a in _agents) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// Inserts or replaces [agent] by id.
  void upsertAgent(AgentConfig agent) {
    final index = _agents.indexWhere((a) => a.id == agent.id);
    if (index < 0) {
      _agents.add(agent);
    } else {
      _agents[index] = agent;
    }
    notifyListeners();
  }

  /// Removes the agent with [id]. Returns `true` when something was removed.
  bool removeAgent(String id) {
    final index = _agents.indexWhere((a) => a.id == id);
    if (index < 0) return false;
    _agents.removeAt(index);
    notifyListeners();
    return true;
  }
}

/// Provider for the shared [AgentListStore].
final ChangeNotifierProvider<AgentListStore> agentListProvider =
    ChangeNotifierProvider<AgentListStore>((ref) => AgentListStore());

