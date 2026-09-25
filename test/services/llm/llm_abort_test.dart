import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_descriptor.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/openai_videos_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

/// Cancel and timeout used to leave a non-streaming request running upstream:
/// the client is pooled, so it cannot be closed for one request. The shared
/// send helper takes an abort trigger from the options, and LLMService chains
/// its own cancellation into the options without replacing the caller's
/// probe (pitfalls 11 §H72).
void main() {
  group('sendJsonRequest', () {
    test('the shared builder makes streaming JSON requests abortable too', () {
      final trigger = Completer<void>().future;
      final request = buildJsonRequest(
        'POST',
        Uri.parse('https://example.invalid/v1/stream'),
        headers: const {'Content-Type': 'application/json'},
        body: '{"stream":true}',
        options: {llmAbortTriggerKey: trigger},
      );

      expect(request, isA<http.AbortableRequest>());
      expect(request.abortTrigger, same(trigger));
      expect(request.body, '{"stream":true}');
    });

    test('an abort stops a request the server never answers — through the '
        'pooled client', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final seen = Completer<void>();
      final held = <HttpRequest>[];
      server.listen((req) {
        held.add(req); // Never answered.
        if (!seen.isCompleted) seen.complete();
      });
      addTearDown(() async {
        for (final r in held) {
          try {
            await r.response.close();
          } catch (_) {}
        }
        await server.close(force: true);
      });

      final config = LLMModelConfig(
        modelId: 'm',
        channelType: 'openai-api-rest',
        endpoint: 'http://127.0.0.1:${server.port}/v1',
        apiKey: 'k',
      );
      final client = config.createClient();
      addTearDown(client.close);

      final abort = Completer<void>();
      final sent = sendJsonRequest(
        client,
        Uri.parse('${config.endpoint}/chat/completions'),
        headers: const {'Content-Type': 'application/json'},
        body: '{}',
        options: {llmAbortTriggerKey: abort.future},
      );
      await seen.future.timeout(const Duration(seconds: 5));
      final started = DateTime.now();
      abort.complete();

      await expectLater(sent, throwsA(isA<http.RequestAbortedException>()));
      expect(DateTime.now().difference(started), lessThan(const Duration(seconds: 5)));
    });

    test('without a trigger it sends what client.post sends', () async {
      http.BaseRequest? viaHelper;
      http.BaseRequest? viaPost;
      String? helperBody;
      String? postBody;
      final helperClient = MockClient((req) async {
        viaHelper = req;
        helperBody = req.body;
        return http.Response('{}', 200);
      });
      final postClient = MockClient((req) async {
        viaPost = req;
        postBody = req.body;
        return http.Response('{}', 200);
      });
      final url = Uri.parse('https://example.invalid/v1/x');
      const headers = {'Content-Type': 'application/json', 'X-Custom': 'y'};
      final body = jsonEncode({'a': 'ü'});

      final r = await sendJsonRequest(helperClient, url, headers: headers, body: body);
      await postClient.post(url, headers: headers, body: body);

      expect(r.statusCode, 200);
      expect(viaHelper!.method, viaPost!.method);
      expect(viaHelper!.url, viaPost!.url);
      expect(viaHelper!.headers, viaPost!.headers);
      expect(helperBody, postBody);
    });
  });

  test('abortTriggerOf reads only a Future<void>', () {
    final f = Completer<void>().future;
    expect(abortTriggerOf({llmAbortTriggerKey: f}), same(f));
    expect(abortTriggerOf({llmAbortTriggerKey: 'nope'}), isNull);
    expect(abortTriggerOf(null), isNull);
  });

  test('an in-flight video status poll is abortable', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final seen = Completer<void>();
    final held = <HttpRequest>[];
    server.listen((req) {
      held.add(req);
      if (!seen.isCompleted) seen.complete();
    });
    addTearDown(() async {
      for (final request in held) {
        try {
          await request.response.close();
        } catch (_) {}
      }
      LLMClientPool.disposeAll();
      await server.close(force: true);
    });

    final config = LLMModelConfig(
      modelId: 'sora-2',
      channelType: Vendors.openAIRest,
      endpoint: 'http://127.0.0.1:${server.port}/v1',
      apiKey: 'k',
    );
    final target = LLMTarget(
      config: config,
      vendor: Vendors.byId(config.channelType),
      model: ModelDescriptor.of(config.modelId),
    );
    final abort = Completer<void>();
    final polling = OpenAIVideosProtocol().poll(
      target,
      'video_1',
      options: {llmAbortTriggerKey: abort.future},
    );
    await seen.future.timeout(const Duration(seconds: 5));
    abort.complete();

    await expectLater(polling, throwsA(isA<http.RequestAbortedException>()));
  });

  group('LLMService.chainCancellationProbe', () {
    test('the caller\'s probe is still consulted (chained, not replaced)', () {
      var callerCalls = 0;
      var callerSays = false;
      var hookSays = false;
      final options = <String, dynamic>{
        'retryCount': 1,
        llmCancellationProbeKey: () {
          callerCalls++;
          return callerSays;
        },
      };
      final chained = LLMService.chainCancellationProbe(options, () => hookSays)!;
      final probe = chained[llmCancellationProbeKey] as bool Function();

      expect(probe(), isFalse);
      expect(callerCalls, 1, reason: 'the caller probe must be asked');
      callerSays = true;
      expect(probe(), isTrue);
      callerSays = false;
      hookSays = true;
      expect(probe(), isTrue);
      expect(chained['retryCount'], 1);
      expect(
        options[llmCancellationProbeKey],
        isNot(same(probe)),
        reason: 'the caller map is not mutated',
      );
    });

    test('only the isCancelled hook still yields a probe', () {
      var hook = false;
      final chained = LLMService.chainCancellationProbe(null, () => hook)!;
      final probe = chained[llmCancellationProbeKey] as bool Function();
      expect(probe(), isFalse);
      hook = true;
      expect(probe(), isTrue);
    });

    test('with no cancellation at all the options are handed back as-is', () {
      final options = <String, dynamic>{'x': 1};
      expect(LLMService.chainCancellationProbe(options, null), same(options));
      expect(LLMService.chainCancellationProbe(null, null), isNull);
    });
  });
}
