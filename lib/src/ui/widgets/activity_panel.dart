/// [AgentActivityPanel]: streaming timeline of one agent's LLM activity.
///
/// Renders the `LlmStreamEvent` kinds produced by the agent/LLM layer as
/// icon-coded timeline tiles: lifecycle (`started`/`completed`), progress
/// (`status`), incremental output (`text` deltas), tool traffic (`tool`
/// deltas such as a move-function call being assembled), and telemetry
/// (`usage`, `latency`, `error`).
///
/// Because the domain event types live in modules outside this UI task, this
/// file defines the UI-layer mirror [ActivityEvent]/[ActivityEventKind] with
/// the same kind vocabulary; map domain events onto it at the call site
/// (field names are intentionally identical).
///
/// Behavior notes:
///
/// * **Auto-scroll**: a [ScrollController] pins the list to the newest event
///   whenever [events] grows; the header toggle lets users pause that to
///   inspect earlier output.
/// * **Secret redaction**: every message passes through [redactSecrets]
///   (API keys, bearer tokens, `sk-…`, passwords) before display — tool
///   arguments and error text must never leak credentials.
/// * **Footer**: aggregates token usage and latency plus an `isThinking`
///   spinner so "agent is working" is visible even with no new tiles.
library;

import 'package:flutter/material.dart';

/// Stream-event kinds mirrored from the LLM layer's `LlmStreamEvent`.
///
/// Keep names aligned with the domain type so mapping stays mechanical.
enum ActivityEventKind {
  /// Agent turn started (model + prompt context).
  started,

  /// Human-readable progress note ("evaluating position…").
  status,

  /// Incremental text/token delta from the model.
  textDelta,

  /// Tool-call update: a function call being assembled or invoked
  /// (e.g. `make_move` with candidate UCI).
  toolDelta,

  /// Agent turn completed with its final answer.
  completed,

  /// Token-usage telemetry (prompt/completion/total).
  usage,

  /// Latency telemetry (time-to-first-token, total ms).
  latency,

  /// Failure: illegal move, timeout, provider error, ...
  error,
}

/// One UI-layer activity event (mirror of the domain `LlmStreamEvent`).
class ActivityEvent {
  /// Creates an activity event with an explicit timestamp defaulting to now.
  ActivityEvent({
    required this.kind,
    required this.message,
    DateTime? timestamp,
    this.toolName,
    this.promptTokens,
    this.completionTokens,
    this.latencyMs,
  }) : timestamp = timestamp ?? DateTime.now();

  /// The event kind; drives icon, color and tile shape.
  final ActivityEventKind kind;

  /// Display text (already redacted at render time; callers may pass raw).
  final String message;

  /// When the event occurred.
  final DateTime timestamp;

  /// Tool/function name for [ActivityEventKind.toolDelta], if known.
  final String? toolName;

  /// Prompt tokens for [ActivityEventKind.usage] events.
  final int? promptTokens;

  /// Completion tokens for [ActivityEventKind.usage] events.
  final int? completionTokens;

  /// Latency in ms for [ActivityEventKind.latency] events.
  final int? latencyMs;

  /// `true` for [ActivityEventKind.error].
  bool get isError => kind == ActivityEventKind.error;
}

/// Redacts credential-looking substrings from [input].
///
/// Covers `sk-…` keys, `api_key`/`apikey` assignments, `Bearer` tokens and
/// `password` assignments (case-insensitive, quoted or not). Applied to
/// every tile and to tool-argument previews before display.
String redactSecrets(String input) {
  var out = input;
  out = out.replaceAll(RegExp(r'sk-[A-Za-z0-9\-_]{8,}'), 'sk-[redacted]');
  out = out.replaceAllMapped(
    RegExp(r'''(api[_-]?key\s*[:=]\s*)(["']?)[^\s"']+''', caseSensitive: false),
    (m) => '${m.group(1)}[redacted]',
  );
  out = out.replaceAllMapped(
    RegExp(r'(bearer\s+)[A-Za-z0-9\-._~+/]+=*', caseSensitive: false),
    (m) => '${m.group(1)}[redacted]',
  );
  out = out.replaceAllMapped(
    RegExp(r'''(password\s*[:=]\s*)(["']?)[^\s"']+''', caseSensitive: false),
    (m) => '${m.group(1)}[redacted]',
  );
  return out;
}

/// Formats [timestamp] as `HH:MM:SS` for tile clocks.
String formatEventTime(DateTime timestamp) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(timestamp.hour)}:${two(timestamp.minute)}:${two(timestamp.second)}';
}

/// Streaming timeline of an agent's LLM activity.
///
/// Props: [events] (append-only list, oldest first) and [isThinking] (shows
/// the footer spinner). Optional [totalTokens]/[totalLatencyMs] override the
/// footer aggregates computed from usage/latency events.
class AgentActivityPanel extends StatefulWidget {
  /// Creates an activity panel.
  const AgentActivityPanel({
    super.key,
    required this.events,
    this.isThinking = false,
    this.totalTokens,
    this.totalLatencyMs,
  });

  /// Append-only event list, oldest first. The panel watches its length.
  final List<ActivityEvent> events;

  /// Whether the agent is currently thinking (footer spinner + header dot).
  final bool isThinking;

  /// Explicit footer token total; defaults to summing usage events.
  final int? totalTokens;

  /// Explicit footer latency total (ms); defaults to summing latency events.
  final int? totalLatencyMs;

  @override
  State<AgentActivityPanel> createState() => _AgentActivityPanelState();
}

class _AgentActivityPanelState extends State<AgentActivityPanel> {
  final ScrollController _scroll = ScrollController();

  /// When false, new events no longer yank the scroll position (lets the
  /// user read earlier output while the stream continues).
  bool _autoScroll = true;

  @override
  void didUpdateWidget(covariant AgentActivityPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.events.length != oldWidget.events.length && _autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Pins the list to the newest tile; guards while the view is building.
  void _scrollToEnd() {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    if (max <= 0) return;
    _scroll.animateTo(
      max,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: <Widget>[
        _buildHeader(theme),
        Expanded(
          child: widget.events.isEmpty
              ? _buildEmpty(theme)
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: widget.events.length,
                  itemBuilder: (context, i) =>
                      _EventTile(event: widget.events[i]),
                ),
        ),
        _buildFooter(theme),
      ],
    );
  }

  /// Header: live indicator, event count, auto-scroll toggle.
  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: <Widget>[
          Semantics(
            label: widget.isThinking ? 'Agent is thinking' : 'Agent idle',
            liveRegion: true,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.isThinking
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              widget.isThinking ? 'Agent thinking…' : 'Agent activity',
              style: theme.textTheme.titleSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${widget.events.length}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          FilterChip(
            label: const Text('Auto-scroll'),
            selected: _autoScroll,
            onSelected: (v) {
              setState(() => _autoScroll = v);
              if (v) _scrollToEnd();
            },
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  /// Placeholder shown before the first event arrives.
  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          widget.isThinking
              ? 'Waiting for the first stream event…'
              : 'No activity yet. Start a game to watch the agent think.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  /// Footer: token total, latency total, thinking spinner.
  Widget _buildFooter(ThemeData theme) {
    final tokens = widget.totalTokens ?? _sumTokens(widget.events);
    final latency = widget.totalLatencyMs ?? _sumLatency(widget.events);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.token_outlined, size: 16),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '$tokens tokens',
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.timer_outlined, size: 16),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '${latency}ms',
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Spacer(),
          if (widget.isThinking) ...<Widget>[
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'thinking',
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Sums prompt+completion tokens across usage events.
int _sumTokens(List<ActivityEvent> events) {
  var total = 0;
  for (final e in events) {
    if (e.kind == ActivityEventKind.usage) {
      total += (e.promptTokens ?? 0) + (e.completionTokens ?? 0);
    }
  }
  return total;
}

/// Sums latency across latency events.
int _sumLatency(List<ActivityEvent> events) {
  var total = 0;
  for (final e in events) {
    if (e.kind == ActivityEventKind.latency) total += e.latencyMs ?? 0;
  }
  return total;
}

/// One timeline tile: icon rail + kind-colored card + timestamp.
class _EventTile extends StatelessWidget {
  /// Creates a tile for [event].
  const _EventTile({required this.event});

  /// The event to render (message is redacted at build time).
  final ActivityEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = _styleFor(event.kind, theme);
    final message = redactSecrets(event.message);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Icon(style.icon, size: 16, color: style.color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: style.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: style.color.withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          style.label +
                              (event.toolName != null
                                  ? ' · ${event.toolName}'
                                  : ''),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: style.color,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        formatEventTime(event.timestamp),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  if (event.kind == ActivityEventKind.toolDelta ||
                      event.kind == ActivityEventKind.textDelta)
                    Text(
                      message,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    )
                  else
                    Text(message, style: theme.textTheme.bodySmall),
                  if (event.kind == ActivityEventKind.usage &&
                      (event.promptTokens != null ||
                          event.completionTokens != null))
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'prompt ${event.promptTokens ?? 0} · '
                        'completion ${event.completionTokens ?? 0}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  if (event.kind == ActivityEventKind.latency &&
                      event.latencyMs != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '${event.latencyMs} ms',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Icon/label/color recipe per event kind.
  _KindStyle _styleFor(ActivityEventKind kind, ThemeData theme) {
    final cs = theme.colorScheme;
    return switch (kind) {
      ActivityEventKind.started => _KindStyle(
        Icons.play_arrow,
        'STARTED',
        cs.primary,
        cs.primaryContainer.withValues(alpha: 0.4),
      ),
      ActivityEventKind.status => _KindStyle(
        Icons.info_outline,
        'STATUS',
        cs.onSurfaceVariant,
        cs.surfaceContainerHighest.withValues(alpha: 0.5),
      ),
      ActivityEventKind.textDelta => _KindStyle(
        Icons.text_fields,
        'TEXT',
        cs.tertiary,
        cs.tertiaryContainer.withValues(alpha: 0.35),
      ),
      ActivityEventKind.toolDelta => _KindStyle(
        Icons.build_outlined,
        'TOOL',
        cs.secondary,
        cs.secondaryContainer.withValues(alpha: 0.35),
      ),
      ActivityEventKind.completed => _KindStyle(
        Icons.check_circle_outline,
        'DONE',
        cs.primary,
        cs.primaryContainer.withValues(alpha: 0.4),
      ),
      ActivityEventKind.usage => _KindStyle(
        Icons.token_outlined,
        'USAGE',
        cs.onSurfaceVariant,
        cs.surfaceContainerHighest.withValues(alpha: 0.4),
      ),
      ActivityEventKind.latency => _KindStyle(
        Icons.timer_outlined,
        'LATENCY',
        cs.onSurfaceVariant,
        cs.surfaceContainerHighest.withValues(alpha: 0.4),
      ),
      ActivityEventKind.error => _KindStyle(
        Icons.error_outline,
        'ERROR',
        cs.error,
        cs.errorContainer.withValues(alpha: 0.5),
      ),
    };
  }
}

/// Icon/label/color recipe for one [ActivityEventKind].
class _KindStyle {
  /// Creates a kind style.
  const _KindStyle(this.icon, this.label, this.color, this.background);

  /// Leading icon.
  final IconData icon;

  /// Uppercase kind tag shown above the message.
  final String label;

  /// Accent color (icon, tag, tile border).
  final Color color;

  /// Tile background wash.
  final Color background;
}
