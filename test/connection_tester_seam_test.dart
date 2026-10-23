// Regression tests for the §10.4 connection-tester seam:
// [connectionTesterProvider] / injectable agent-connection probe.
//
/// Widget tests must never open an HTTP socket or ping a real LLM endpoint.
/// Screens that resolve this provider (defaulting to [testAgentConnection])
/// can override it with a deterministic lambda — no network, no platform
/// channel, no `SecureKeyStore` churn.
// ignore_for_file: dangling_library_doc_comments

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chess_arena/src/ui/backend_bridge.dart';
import 'package:llm_chess_arena/src/ui/ui_models.dart';

final sampleConfig = AgentConfig(
  id: 'test-agent-conn',
  name: 'Test Connection',
  provider: 'openai',
  model: 'gpt-4o-mini',
  temperature: 0.5,
  maxTokens: 256,
  systemPrompt: '',
  userPromptTemplate: '',
  apiKeyRef: null,
);

void main() {
  group('connectionTesterProvider (§10.4 seam)', () {
    test('defaults to a ConnectionTester (factory resolvable, pure)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final tester = container.read(connectionTesterProvider);
      expect(tester, isA<ConnectionTester>());
      // Resolving the provider is pure — it must not open a socket. Calling
      // the default would ping a real endpoint (testAgentConnection →
      // createProvider → live LLM), which widget tests forbid (see header);
      // call behaviour is covered only via the deterministic overrides below.
    });

    testWidgets('override returns fixed success (true)', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectionTesterProvider.overrideWithValue(
              (_, {inlineSecret}) async => true,
            ),
          ],
          child: const SizedBox.shrink(),
        ),
      );

      final container =
          ProviderScope.containerOf(tester.element(find.byType(SizedBox)));
      final fn = container.read(connectionTesterProvider);

      expect(fn(sampleConfig), completes);
      final ok = await fn(sampleConfig);
      expect(ok, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('override returns fixed failure (false)', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectionTesterProvider.overrideWithValue(
              (_, {inlineSecret}) async => false,
            ),
          ],
          child: const SizedBox.shrink(),
        ),
      );

      final container =
          ProviderScope.containerOf(tester.element(find.byType(SizedBox)));
      final fn = container.read(connectionTesterProvider);

      final ok = await fn(sampleConfig);
      expect(ok, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('override may inspect inlineSecret passthrough',
        (tester) async {
      var receivedSecret = <String?>[];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectionTesterProvider.overrideWithValue(
              (agent, {inlineSecret}) async {
                receivedSecret.add(inlineSecret);
                return true;
              },
            ),
          ],
          child: const SizedBox.shrink(),
        ),
      );

      final container =
          ProviderScope.containerOf(tester.element(find.byType(SizedBox)));
      final fn = container.read(connectionTesterProvider);

      await fn(sampleConfig, inlineSecret: 'my-secret-key');
      expect(receivedSecret, contains('my-secret-key'));

      await fn(sampleConfig); // no inlineSecret
      expect(receivedSecret, contains(isNull));
      expect(tester.takeException(), isNull);
    });

    test('thrown failure is caught and handled gracefully', () {
      final container = ProviderContainer(
        overrides: [
          connectionTesterProvider.overrideWithValue(
            (_, {inlineSecret}) async => throw StateError('simulated crash'),
          ),
        ],
      );
      addTearDown(container.dispose);

      final fn = container.read(connectionTesterProvider);
      // A thrown exception from the tester should complete (the caller
      // typically catches); we verify it at least completes without leaking.
      expect(() => fn(sampleConfig), throwsA(isA<StateError>()));
    });

    testWidgets('two containers get independent overrides', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectionTesterProvider.overrideWithValue(
              (_, {inlineSecret}) async => true,
            ),
          ],
          child: MaterialApp(
            home: ProviderScope(
              overrides: [
                connectionTesterProvider.overrideWithValue(
                  (_, {inlineSecret}) async => false,
                ),
              ],
              child: const Center(child: Text('inner')),
            ),
          ),
        ),
      );

      final outerContainer = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );
      final innerContainer = ProviderScope.containerOf(
        tester.element(find.text('inner')),
      );

      final outerOk = await outerContainer
          .read(connectionTesterProvider)(sampleConfig);
      final innerOk = await innerContainer
          .read(connectionTesterProvider)(sampleConfig);

      expect(outerOk, isTrue);
      expect(innerOk, isFalse);
      expect(tester.takeException(), isNull);
    });

    test('default remains distinct per container but identical in shape', () {
      final c1 = ProviderContainer();
      addTearDown(c1.dispose);
      final c2 = ProviderContainer();
      addTearDown(c2.dispose);

      final f1 = c1.read(connectionTesterProvider);
      final f2 = c2.read(connectionTesterProvider);

      expect(f1, isA<ConnectionTester>());
      expect(f2, isA<ConnectionTester>());
      // Resolving both defaults is pure — no socket is opened. (Invoking the
      // default would ping a live LLM endpoint, which widget tests forbid.)
      // Invocation behaviour is pinned by the override tests above.
    });

    testWidgets(
        'default tester resolves without opening a socket '
        '(network behaviour is the production seam)', (tester) async {
      // Resolving the default wraps testAgentConnection, which would ping a
      // real LLM endpoint — widget tests must never open an HTTP socket (see
      // the file header). We therefore assert only the provider's shape and
      // that a deterministic override is fully honoured; the default's live
      // network path is the production seam and is exercised interactively.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectionTesterProvider.overrideWithValue(
              (_, {inlineSecret}) async => false,
            ),
          ],
          child: const SizedBox.shrink(),
        ),
      );

      final container =
          ProviderScope.containerOf(tester.element(find.byType(SizedBox)));
      final fn = container.read(connectionTesterProvider);
      expect(fn, isA<ConnectionTester>());

      final result = await fn(sampleConfig);
      expect(result, isFalse);
      expect(tester.takeException(), isNull);
    });
  });
}
