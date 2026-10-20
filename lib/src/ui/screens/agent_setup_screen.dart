/// [AgentSetupScreen]: create/edit form for one [AgentConfig].
///
/// Fields: display name, provider dropdown, model id, temperature slider,
/// max tokens, system prompt, user-prompt template (`{fen}`/`{moves}`) and a
/// **write-only API-key field**.
///
/// Validation runs through the single [AgentConfig.validate] path (no
/// duplicated per-field rules); saving upserts into [agentListProvider] and
/// pops back (create and edit behave the same).
///
/// **API keys**: the secret is written to [SecureKeyStore] under an opaque
/// [AgentConfig.apiKeyRef] and is never displayed again, logged, or stored in
/// the catalog. A masked "stored" indicator + a Clear action call
/// [SecureKeyStore.deleteApiKey]. **Test connection** resolves the key
/// (including a just-typed, not-yet-saved one) and probes the real provider
/// endpoint via [testAgentConnection] — no simulated latency.
///
/// Construct with [agentId] to edit, or `null` to create (a uuid is minted
/// on save).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../storage/secure_key_store.dart';
import '../backend_bridge.dart';
import '../ui_models.dart';

/// Supported provider keys for the setup form dropdown.
const List<String> kAgentProviders = <String>[
  'openai',
  'anthropic',
  'gemini',
  'custom',
  'demo',
];

/// Create/edit form for one agent configuration.
class AgentSetupScreen extends ConsumerStatefulWidget {
  /// Creates the setup screen; [agentId] `null` means "create new".
  const AgentSetupScreen({super.key, this.agentId});

  /// Id of the agent to edit, or `null` to create one.
  final String? agentId;

  @override
  ConsumerState<AgentSetupScreen> createState() => _AgentSetupScreenState();
}

class _AgentSetupScreenState extends ConsumerState<AgentSetupScreen> {
  /// Shared secure-storage handle (`const`-constructible).
  static const SecureKeyStore _keyStore = SecureKeyStore();

  late final TextEditingController _name;
  late final TextEditingController _model;
  late final TextEditingController _maxTokens;
  late final TextEditingController _system;
  late final TextEditingController _userTemplate;

  /// Write-only API-key entry (never echoed back after a save).
  late final TextEditingController _apiKey;

  /// Opaque secure-storage ref currently associated with the agent.
  String? _apiKeyRef;

  /// Whether a secret exists in secure storage for [_apiKeyRef].
  bool _hasStoredKey = false;

  late String _provider;
  late double _temperature;

  /// Test-connection state: `true` while probing.
  bool _testing = false;

  /// Human-readable test-connection outcome shown in the banner.
  String? _testResult;

  /// Whether the last test succeeded (drives banner color).
  bool _testOk = false;

  /// Whether a save is in flight. Guards the Save/Create button so a
  /// double-tap cannot pass the async secure-storage await twice and pop two
  /// routes (or mint two key refs).
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = ref.read(agentListProvider).byId(widget.agentId);
    _name = TextEditingController(text: existing?.name ?? '');
    _model = TextEditingController(text: existing?.model ?? '');
    _maxTokens = TextEditingController(text: '${existing?.maxTokens ?? 1024}');
    _system = TextEditingController(text: existing?.systemPrompt ?? '');
    _userTemplate = TextEditingController(
      text: existing?.userPromptTemplate ?? '',
    );
    _apiKey = TextEditingController();
    _apiKeyRef = existing?.apiKeyRef;
    _provider = existing?.provider ?? kAgentProviders.first;
    _temperature = existing?.temperature ?? 0.7;
    _loadKeyPresence();
  }

  @override
  void dispose() {
    _name.dispose();
    _model.dispose();
    _maxTokens.dispose();
    _system.dispose();
    _userTemplate.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  /// Checks (best-effort) whether a secret is already stored for the ref.
  Future<void> _loadKeyPresence() async {
    final ref0 = _apiKeyRef;
    if (ref0 == null || ref0.isEmpty) return;
    var has = false;
    try {
      has = (await _keyStore.readApiKey(ref0))?.isNotEmpty ?? false;
    } catch (_) {
      has = false; // No secure backend (e.g. widget tests) → treat as none.
    }
    if (!mounted) return;
    setState(() => _hasStoredKey = has);
  }

  /// Builds the config from the form fields (without an API-key ref).
  AgentConfig _formConfig({String? apiKeyRef}) {
    return AgentConfig(
      id: widget.agentId ?? const Uuid().v4(),
      name: _name.text.trim(),
      provider: _provider,
      model: _model.text.trim(),
      temperature: _temperature,
      maxTokens: int.tryParse(_maxTokens.text.trim()) ?? 0,
      systemPrompt: _system.text,
      userPromptTemplate: _userTemplate.text,
      apiKeyRef: apiKeyRef,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.agentId != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                isEdit ? 'Edit agent' : 'New agent',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Display name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _provider,
                      decoration: const InputDecoration(
                        labelText: 'Provider',
                        border: OutlineInputBorder(),
                      ),
                      items: <DropdownMenuItem<String>>[
                        for (final p in kAgentProviders)
                          DropdownMenuItem(value: p, child: Text(p)),
                      ],
                      onChanged: (v) =>
                          setState(() => _provider = v ?? _provider),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _model,
                      decoration: const InputDecoration(
                        labelText: 'Model id',
                        hintText: 'gpt-4o',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Temperature ${_temperature.toStringAsFixed(2)}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Slider(
                      value: _temperature,
                      min: 0,
                      max: 2,
                      divisions: 40,
                      label: _temperature.toStringAsFixed(2),
                      onChanged: (v) => setState(() => _temperature = v),
                    ),
                  ),
                ],
              ),
              TextFormField(
                controller: _maxTokens,
                decoration: const InputDecoration(
                  labelText: 'Max tokens',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _system,
                decoration: const InputDecoration(
                  labelText: 'System prompt',
                  border: OutlineInputBorder(),
                ),
                maxLines: 4,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _userTemplate,
                decoration: const InputDecoration(
                  labelText: 'User prompt template',
                  hintText: 'Position: {fen}. Moves: {moves}',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              _buildKeySection(theme),
              const SizedBox(height: 16),
              if (_testResult != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: _testOk
                        ? theme.colorScheme.secondaryContainer
                        : theme.colorScheme.errorContainer,
                  ),
                  child: Text(
                    _testResult!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: _testOk
                          ? theme.colorScheme.onSecondaryContainer
                          : theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              if (_testResult != null) const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _testing ? null : _testConnection,
                      icon: _testing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.wifi_tethering_outlined),
                      label: const Text('Test connection'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(isEdit ? 'Save' : 'Create'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Write-only API-key field + masked "stored" indicator and Clear action.
  ///
  /// The raw secret is never rendered back: only a boolean "stored" state is
  /// shown. Entering a value replaces the stored secret on save; Clear
  /// deletes it immediately.
  Widget _buildKeySection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('API key', style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        // No extra Semantics(textField: true) wrapper: TextField/EditableText
        // already publishes a text-field node with this label, and nesting a
        // second one produced an ambiguous double text-field node in the
        // accessibility tree.
        TextField(
          controller: _apiKey,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'API key (write-only, stored securely)',
            helperText: 'Encrypted on device; never shown again.',
            helperMaxLines: 2,
            border: const OutlineInputBorder(),
            suffixIcon: _hasStoredKey
                ? IconButton(
                    tooltip: 'Clear stored key',
                    onPressed: _testing ? null : _clearApiKey,
                    icon: const Icon(Icons.delete_outline),
                  )
                : null,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: <Widget>[
            Icon(
              _hasStoredKey ? Icons.lock_outline : Icons.lock_open_outlined,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _hasStoredKey
                    ? 'A key is stored securely (••••••••). Enter a new key '
                        'to replace it, or use the delete action to clear it.'
                    : 'No key stored. Keys are optional for demo/mock and '
                        'local Ollama agents.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Builds the config from the form, stores a typed key if present, and
  /// upserts into the catalog. Pops afterwards (create and edit alike).
  Future<void> _save() async {
    if (_saving) return;
    final config = _formConfig();
    final problems = config.validate();
    if (problems.isNotEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(problems.join(' '))));
      return;
    }
    setState(() => _saving = true);
    try {
      final secret = _apiKey.text.trim();
      var keyRef = _apiKeyRef;
      var hasKey = _hasStoredKey;
      if (secret.isNotEmpty) {
        keyRef ??= const Uuid().v4();
        try {
          await _keyStore.writeApiKey(keyRef, secret);
          hasKey = true;
        } catch (_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not save the API key to secure storage.'),
            ),
          );
          return;
        }
      }
      if (!mounted) return;
      final saved = config.copyWith(apiKeyRef: hasKey ? keyRef : null);
      ref.read(agentListProvider).upsertAgent(saved);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Saved ${saved.name}')));
      Navigator.maybeOf(context)?.pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Deletes the stored secret (immediately) and clears the local indicator.
  Future<void> _clearApiKey() async {
    final ref0 = _apiKeyRef;
    setState(() {
      _apiKey.clear();
      _apiKeyRef = null;
      _hasStoredKey = false;
      _testResult = null;
    });
    if (ref0 == null) return;
    try {
      await _keyStore.deleteApiKey(ref0);
    } catch (_) {
      // Best-effort: the local state is already cleared.
    }
  }

  /// Real connectivity probe: resolves the key and pings the provider
  /// endpoint via [testAgentConnection]. Never logs the key.
  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final probe = _formConfig(apiKeyRef: _hasStoredKey ? _apiKeyRef : null);
    bool ok;
    try {
      ok = await testAgentConnection(
        probe,
        _keyStore,
        inlineSecret: _apiKey.text.trim(),
      );
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    final label =
        probe.model.isEmpty ? '(no model)' : probe.model;
    setState(() {
      _testing = false;
      _testOk = ok;
      _testResult = ok
          ? 'Connection OK for ${probe.provider}/$label.'
          : 'Connection failed for ${probe.provider}/$label — check the '
              'model id, base URL and API key, then retry.';
    });
  }
}
