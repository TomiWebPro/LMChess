// Regression tests for the §10.1 turn-provider seam:
// [turnProviderFactoryProvider] / [TurnProviderFactory].
//
// Widget tests must never open a socket, spawn a process, or wait on the
// wall clock. Play, Watch, and Arena resolve their per-turn provider through
// this provider (defaulting to [resolveTurnProvider]) so tests can override
// it with an immediately-answering [MockProvider] — including scripted
// timeout, malformed-response, no-move, and thrown failures.
//
// Note on async zones: [MockProvider.streamMove] replays with
// `Future.delayed` ticks, which never fire inside a widget test's FakeAsync
// zone unless pumped. Stream consumption therefore happens in plain `test`s
// (real async, `stepDelay: Duration.zero`); the one `testWidgets` below only
// proves the override resolves from a real pumped widget tree.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/agent/agent_config.dart';
import 'package:llm_chess_arena/src/llm/mock_provider.dart';
import 'package:llm_chess_arena/src/llm/provider.dart'
    show AgentRequest, LlmProvider, ProviderId, StreamEventKind;
import 'package:llm_chess_arena/src/llm/tool_schema.dart';
import 'package:llm_chess_arena/src/llm/validation.dart';
import 'package:llm_chess_arena/src/ui/backend_bridge.dart';

AgentConfig _mockConfig() => const AgentConfig(
      id: 'mock-seam',
      name: 'Mock Seam',
      providerId: ProviderId.mock,
      model: 'mock',
    );

const _request = AgentRequest(
  systemPrompt: 'play chess',
  userPrompt: 'e2e4?',
);

/// Collects the terminal event kind of one [provider] turn.
///
/// Must run in real async (plain `test`), never inside `testWidgets`:
/// the mock's replay ticks are `Future.delayed`, which FakeAsync parks
/// until pumped.
Future<StreamEventKind> _terminalKind(LlmProvider provider) async {
  var terminal = StreamEventKind.done;
  await for (final event in provider.streamMove(_request)) {
    if (event.kind == StreamEventKind.error ||
        event.kind == StreamEventKind.errorRetry) {
      terminal = event.kind;
    }
  }
  return terminal;
}

/// Override factory returning an immediately-answering scripted mock.
TurnProviderFactory _scripted(List<Object> script) =>
    (config, legalUcis, {seed, phrase}) => Future.value(
          MockProvider(script: script, stepDelay: Duration.zero),
        );

void main() {
  group('turnProviderFactoryProvider (§10.1 seam)', () {
    test('defaults to resolveTurnProvider (mock agent gets a legal move)',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final factory = container.read(turnProviderFactoryProvider);
      final provider = await factory(
        _mockConfig(),
        const <String>['e2e4', 'd2d4'],
      );

      expect(provider, isA<MockProvider>());
      final mock = provider as MockProvider;
      expect(mock.script, hasLength(1));
      final call = mock.script.single as MoveToolCall;
      expect(const <String>['e2e4', 'd2d4'], contains(call.uci));
    });

    test('override observes the seed and phrase passthrough', () async {
      AgentConfig? seenConfig;
      List<String>? seenUcis;
      int? seenSeed;
      String? seenPhrase;
      final container = ProviderContainer(
        overrides: [
          turnProviderFactoryProvider.overrideWithValue(
            (config, legalUcis, {seed, phrase}) {
              seenConfig = config;
              seenUcis = legalUcis;
              seenSeed = seed;
              seenPhrase = phrase;
              return Future.value(MockProvider(
                script: <Object>[
                  MoveToolCall(from: 'g1', to: 'f3', phrase: phrase),
                ],
              ));
            },
          ),
        ],
      );
      addTearDown(container.dispose);

      final provider = await container.read(turnProviderFactoryProvider)(
        _mockConfig(),
        const <String>['g1f3'],
        seed: 42,
        phrase: 'knight out',
      );

      expect(seenConfig?.id, 'mock-seam');
      expect(seenUcis, const <String>['g1f3']);
      expect(seenSeed, 42);
      expect(seenPhrase, 'knight out');
      expect(provider, isA<MockProvider>());
    });

    testWidgets('override resolves from a real pumped widget tree',
        (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            turnProviderFactoryProvider.overrideWithValue(
              (config, legalUcis, {seed, phrase}) {
                calls++;
                return Future.value(MockProvider(
                  script: <Object>[
                    MoveToolCall(from: 'e2', to: 'e4', phrase: phrase),
                  ],
                  stepDelay: Duration.zero,
                ));
              },
            ),
          ],
          child: const SizedBox.shrink(),
        ),
      );

      // No stream consumption here (see file docs): just prove the pumped
      // tree serves the override and the factory answers immediately.
      final container =
          ProviderScope.containerOf(tester.element(find.byType(SizedBox)));
      final provider = await container.read(turnProviderFactoryProvider)(
        _mockConfig(),
        const <String>['e2e4'],
      );
      expect(calls, 1);
      expect(provider, isA<MockProvider>());
      expect(tester.takeException(), isNull);
    });

    test('override injects a timeout failure (no network, no clock)',
        () async {
      final container = ProviderContainer(
        overrides: [
          turnProviderFactoryProvider
              .overrideWithValue(_scripted(const <Object>[FailureKind.timeout])),
        ],
      );
      addTearDown(container.dispose);

      final provider = await container.read(turnProviderFactoryProvider)(
        _mockConfig(),
        const <String>['e2e4'],
      );
      expect(await _terminalKind(provider), StreamEventKind.errorRetry);
    });

    test('override injects a malformed response failure', () async {
      final container = ProviderContainer(
        overrides: [
          // `valid` carries no move: surfaces as an `internal` error.
          turnProviderFactoryProvider.overrideWithValue(
              _scripted(const <Object>[FailureKind.valid])),
        ],
      );
      addTearDown(container.dispose);

      final provider = await container.read(turnProviderFactoryProvider)(
        _mockConfig(),
        const <String>['e2e4'],
      );
      expect(await _terminalKind(provider), StreamEventKind.error);
    });

    test('override injects a no-move (exhausted script) failure', () async {
      final container = ProviderContainer(
        overrides: [
          turnProviderFactoryProvider.overrideWithValue(
              _scripted(const <Object>[FailureKind.incompleteResponse])),
        ],
      );
      addTearDown(container.dispose);

      final provider = await container.read(turnProviderFactoryProvider)(
        _mockConfig(),
        const <String>['e2e4'],
      );
      expect(await _terminalKind(provider), StreamEventKind.errorRetry);
    });

    test('override injects a thrown failure', () async {
      final container = ProviderContainer(
        overrides: [
          turnProviderFactoryProvider.overrideWithValue(
            (config, legalUcis, {seed, phrase}) =>
                Future<LlmProvider>.error(StateError('backend down')),
          ),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(turnProviderFactoryProvider)(
          _mockConfig(),
          const <String>['e2e4'],
        ),
        throwsStateError,
      );
    });

    test('default factory still streams a legal mock move end-to-end',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final provider = await container.read(turnProviderFactoryProvider)(
        _mockConfig(),
        const <String>['e2e4'],
      );
      expect(await _terminalKind(provider), StreamEventKind.done);
    });
  });
}
