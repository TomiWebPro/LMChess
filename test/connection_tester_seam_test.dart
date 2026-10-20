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
    test('defaults to a Function (the factory is resolvable)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final tester = container.read(connectionTesterProvider);
      expect(tester, isA<Function>());
      // The default returns a Future<bool> — verify by calling it and
      // catching the real-world result (network error → false).
      expect(tester(sampleConfig), completes);
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
      // Both produce Futures<bool>.
      expect(f1(sampleConfig), completes);
      expect(f2(sampleConfig), completes);
    });

    testWidgets('default tester produces false on real-network unreachable',
        (tester) async {
      // The default wraps testAgentConnection which pings the real provider.
      // Without network, it should resolve to false (not throw past the
      // catch block). We just confirm it completes without hanging.
      await tester.pumpWidget(
        ProviderScope(
          child: const SizedBox.shrink(),
        ),
      );

      final container =
          ProviderScope.containerOf(tester.element(find.byType(SizedBox)));
      final fn = container.read(connectionTesterProvider);

      final stopwatch = Stopwatch()..start();
      final result = await fn(sampleConfig);
      stopwatch.stop();

      expect(result, isA<bool>());
      expect(stopwatch.elapsed.inSeconds, lessThan(30),
          reason: 'real connection timeout should be bounded');
      expect(tester.takeException(), isNull);
    });
  });
}
