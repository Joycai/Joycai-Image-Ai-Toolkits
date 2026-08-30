import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_family.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/anthropic_chat_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/dashscope_chat_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/gemini_chat_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/openai_chat_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

/// Pins the M1 error-handling fixes (docs/reviews/2026-08-ai-capability-review.md
/// B1/B2/B5): the Gemini SSE line rules, the status-first response decode, and
/// the structured retry decision.
void main() {
  group('geminiChunksFromSseLine (B1)', () {
    const chunk =
        '{"candidates":[{"content":{"parts":[{"text":"hi"}],"role":"model"}}]}';

    test('data: with a space parses', () {
      final chunks = geminiChunksFromSseLine('data: $chunk').toList();
      expect(chunks, hasLength(1));
      expect(chunks.single.textPart, 'hi');
    });

    test('data: without a space parses — SSE makes the space optional', () {
      // The old inline parser only stripped "data: " (with space); a relay
      // emitting "data:{...}" fed the whole prefixed line to jsonDecode.
      final chunks = geminiChunksFromSseLine('data:$chunk').toList();
      expect(chunks, hasLength(1));
      expect(chunks.single.textPart, 'hi');
    });

    test('keep-alive comments, [DONE] and event: lines are ignored, not fatal',
        () {
      // Every one of these used to kill the stream: jsonDecode threw a
      // FormatException, which implements Exception, which the old catch
      // rethrew — while its comment claimed the line would be skipped.
      expect(geminiChunksFromSseLine(': keep-alive'), isEmpty);
      expect(geminiChunksFromSseLine('data: [DONE]'), isEmpty);
      expect(geminiChunksFromSseLine('event: message'), isEmpty);
      expect(geminiChunksFromSseLine('not json at all'), isEmpty);
      expect(geminiChunksFromSseLine(''), isEmpty);
    });

    test('an in-chunk error envelope still throws', () {
      expect(
        () => geminiChunksFromSseLine(
                'data: {"error":{"code":429,"message":"quota"}}')
            .toList(),
        throwsA(isA<LLMApiException>()
            .having((e) => e.isEnvelope, 'isEnvelope', isTrue)),
      );
    });
  });

  group('resolveImageRef', () {
    void log(String message, {String level = 'INFO'}) {}

    test('a truncated data URI is skipped, not a crash', () async {
      // A comma-less ref shorter than the 32-char log excerpt used to throw
      // RangeError out of the log line itself, aborting the whole generation
      // instead of skipping the one bad image. All three image surfaces
      // await this helper in an unguarded loop.
      final client = http.Client();
      addTearDown(client.close);
      expect(await resolveImageRef('data:image/png', client, log), isNull);
      expect(await resolveImageRef('data:', client, log), isNull);
      expect(
          await resolveImageRef(
              'data:image/png;base64-but-no-comma-and-quite-long-indeed',
              client,
              log),
          isNull);
    });
  });

  group('decodeJsonBody (B2)', () {
    test('non-2xx throws with the status code — even for an HTML body', () {
      // The old Gemini order (jsonDecode first) turned a gateway's HTML 502
      // into "FormatException: Unexpected character"; the real status never
      // appeared and the retry policy could not see the 5xx.
      final response = http.Response('<html>502 Bad Gateway</html>', 502);
      expect(
        () => decodeJsonBody(response, apiName: 'Test'),
        throwsA(isA<LLMApiException>()
            .having((e) => e.statusCode, 'statusCode', 502)
            .having((e) => e.message, 'message', contains('502'))),
      );
    });

    test('non-2xx with a JSON error body surfaces the provider message', () {
      final response = http.Response(
          '{"error":{"code":400,"message":"Invalid argument","status":"INVALID_ARGUMENT"}}',
          400);
      expect(
        () => decodeJsonBody(response),
        throwsA(isA<LLMApiException>()
            .having((e) => e.statusCode, 'statusCode', 400)
            .having((e) => e.message, 'message', contains('Invalid argument'))),
      );
    });

    test('2xx non-JSON body names the real problem instead of crashing', () {
      final response = http.Response('<html>login page</html>', 200);
      expect(
        () => decodeJsonBody(response),
        throwsA(isA<LLMApiException>()
            .having((e) => e.message, 'message', contains('non-JSON'))),
      );
    });

    test('2xx JSON array body is a shape error, not a NoSuchMethodError', () {
      final response = http.Response('[1,2,3]', 200);
      expect(() => decodeJsonBody(response), throwsA(isA<LLMApiException>()));
    });

    test('200 with an error envelope throws (envelope, no status code)', () {
      final response = http.Response('{"error":{"message":"expired key"}}', 200);
      expect(
        () => decodeJsonBody(response),
        throwsA(isA<LLMApiException>()
            .having((e) => e.isEnvelope, 'isEnvelope', isTrue)
            .having((e) => e.statusCode, 'statusCode', isNull)),
      );
    });

    test('a clean 200 returns the decoded map', () {
      final response = http.Response('{"candidates":[]}', 200);
      expect(decodeJsonBody(response), {'candidates': []});
    });

    test('201/202 are inside the success window (submit/poll surfaces)', () {
      expect(decodeJsonBody(http.Response('{"id":"v1"}', 201)), {'id': 'v1'});
      expect(decodeJsonBody(http.Response('{"status":"pending"}', 202)),
          {'status': 'pending'});
    });

    test('checkEnvelope: false hands a failed-job body to the caller', () {
      // Poll surfaces own the {status: failed, error: {...}} case — their
      // status machine names the operation; the generic envelope check would
      // fire first and discard that context.
      final response =
          http.Response('{"status":"failed","error":{"message":"boom"}}', 200);
      expect(decodeJsonBody(response, checkEnvelope: false),
          containsPair('status', 'failed'));
      expect(() => decodeJsonBody(response), throwsA(isA<LLMApiException>()));
    });
  });

  group('VendorProfile.downloadHeaders', () {
    test('google-keyed vendors get x-goog-api-key, bearer vendors a bearer',
        () {
      expect(Vendors.byId(Vendors.officialGoogle).downloadHeaders('k'),
          {'x-goog-api-key': 'k'});
      expect(Vendors.byId(Vendors.googleRest).downloadHeaders('k'),
          {'x-goog-api-key': 'k'});
      expect(Vendors.byId(Vendors.openAIRest).downloadHeaders('k'),
          {'Authorization': 'Bearer k'});
      // newapi-gemini serves the Gemini family behind bearer auth — keying
      // off the *protocol family* (the old executor branch) would have sent
      // it x-goog-api-key, which the relay silently ignores → 403.
      expect(Vendors.byId(Vendors.newApiGemini).downloadHeaders('k'),
          {'Authorization': 'Bearer k'});
    });

    test('an empty key sends no auth header at all', () {
      expect(Vendors.byId(Vendors.openAIRest).downloadHeaders(''), isEmpty);
    });
  });

  group('ModelFamilyClassifier named predicates', () {
    test('niji / text-only / mock rules live in the rule table', () {
      expect(ModelFamilyClassifier.isNijiVariant('Niji-6'), isTrue);
      expect(ModelFamilyClassifier.isNijiVariant('mj_fast'), isFalse);
      expect(ModelFamilyClassifier.isTextOnlyChat('deepseek-chat'), isTrue);
      expect(ModelFamilyClassifier.isTextOnlyChat('gpt-4o'), isFalse);
      expect(ModelFamilyClassifier.isMockModel('mock-video'), isTrue);
      expect(ModelFamilyClassifier.isMockModel('sora-2'), isFalse);
    });
  });

  group('LLMService.isRetryable (B5)', () {
    test('structured 5xx and 429 retry; other codes do not', () {
      expect(LLMService.isRetryable(LLMApiException('x', statusCode: 502)),
          isTrue);
      expect(LLMService.isRetryable(LLMApiException('x', statusCode: 429)),
          isTrue);
      expect(LLMService.isRetryable(LLMApiException('x', statusCode: 400)),
          isFalse);
      expect(LLMService.isRetryable(LLMApiException('x', statusCode: 401)),
          isFalse);
    });

    test('envelope errors never retry — the transport succeeded', () {
      expect(
          LLMService.isRetryable(
              LLMApiException('API error in response body: quota',
                  isEnvelope: true)),
          isFalse);
    });

    test('numbers in error prose are not status codes', () {
      // The old regex grabbed the first three-digit number anywhere, so this
      // 400-class message was retried as if it were a 5xx.
      expect(
          LLMService.isRetryable(Exception(
              'API error in response body: rate limited, retry after 500ms')),
          isFalse);
      expect(
          LLMService.isRetryable(
              Exception('model "gpt-500-turbo" does not exist')),
          isFalse);
    });

    test('legacy "... failed: <status>" prose still recognized', () {
      expect(
          LLMService.isRetryable(
              Exception('xAI Images API failed: 503 - upstream down')),
          isTrue);
      expect(
          LLMService.isRetryable(
              Exception('xAI Images API failed: 422 - bad prompt')),
          isFalse);
    });
  });

  group('the non-streaming deadline', () {
    LLMModelConfig config(String modelId, String channelType) => LLMModelConfig(
          modelId: modelId,
          channelType: channelType,
          endpoint: 'https://example.invalid/v1',
          apiKey: 'k',
        );

    test('a generation that ran long is never retried', () {
      // The whole failure this replaced: three identical Opus requests, 122 s
      // apart, each producing a complete 6 K-token answer that arrived after
      // the client had already given up on it.
      expect(
          LLMService.isRetryable(
              const LLMDeadlineExceeded(Duration(seconds: 120))),
          isFalse);
    });

    test('a stalled stream still is — it means the connection died', () {
      // Same word, opposite meaning: on the streaming path the guard is per
      // chunk, so it expiring is "no bytes for two minutes", not "still
      // writing".
      expect(LLMService.isRetryable(TimeoutException('no chunks')), isTrue);
    });

    test('says what happened and that nothing was retried', () {
      final message =
          const LLMDeadlineExceeded(Duration(seconds: 388)).toString();
      expect(message, contains('388'));
      expect(message, contains('billed'));
      expect(message, contains('retried'));
    });

    test('scales with the output cap the caller asked for', () {
      final dispatcher = LLMDispatcher();
      final small = dispatcher.generateTimeout(
          config('gpt-4o', Vendors.openAIRest),
          options: const {'maxTokens': 1000});
      final large = dispatcher.generateTimeout(
          config('gpt-4o', Vendors.openAIRest),
          options: const {'maxTokens': 32000});
      expect(large, greaterThan(small));
    });

    test('never drops below the historical 120 s floor', () {
      // Short calls must be unaffected: this change is about long answers.
      expect(
        LLMDispatcher().generateTimeout(config('gpt-4o', Vendors.openAIRest),
            options: const {'maxTokens': 1}),
        const Duration(seconds: 120),
      );
    });

    test('a caller that knows its answer is long is believed over the guess',
        () {
      // ① and ③ send no cap, so without this the deadline is sized against a
      // 4096 stand-in — roughly half a measured submit_prompt.
      final dispatcher = LLMDispatcher();
      final guessed =
          dispatcher.generateTimeout(config('gpt-4o', Vendors.openAIRest));
      final told = dispatcher.generateTimeout(
          config('gpt-4o', Vendors.openAIRest),
          options: const {expectedOutputTokensKey: 8192});

      expect(told, greaterThan(guessed));
      // Same figure ④ already gets from its own default, so the two families
      // no longer disagree about how long the same work takes.
      expect(told,
          dispatcher.generateTimeout(config('claude-opus-4-8', Vendors.anthropicRest)));
    });

    test('an explicit maxTokens still wins — it is what the wire carries', () {
      expect(
        LLMDispatcher().generateTimeout(config('gpt-4o', Vendors.openAIRest),
            options: const {'maxTokens': 1000, expectedOutputTokensKey: 100000}),
        const Duration(seconds: 120),
      );
    });

    test('is capped, so a misconfigured cap cannot mean an hour', () {
      expect(
        LLMDispatcher().generateTimeout(config('gpt-4o', Vendors.openAIRest),
            options: const {'maxTokens': 10000000}),
        const Duration(minutes: 10),
      );
    });

    test('a 6 K-token answer gets a deadline it can actually meet', () {
      // The Prompt Assistant's submit_prompt runs 6-7 K tokens; under the old
      // flat guard every single delivery timed out mid-write.
      final deadline = LLMDispatcher().generateTimeout(
          config('claude-opus-4-8', Vendors.anthropicRest));
      expect(deadline, greaterThan(const Duration(minutes: 4)));
    });

    test('Midjourney keeps precedence over the scaling rule', () {
      // Its generate() contains a poll loop, so the output cap says nothing
      // about how long it runs.
      expect(
        LLMDispatcher().generateTimeout(
            config('anything', Vendors.midjourneyProxy),
            options: const {'maxTokens': 1}),
        const Duration(minutes: 11),
      );
    });
  });

  group('tool calls over the streaming surface', () {
    LLMModelConfig config(String channelType) => LLMModelConfig(
          modelId: 'some-model',
          channelType: channelType,
          endpoint: 'https://example.invalid/v1',
          apiKey: 'k',
        );

    test('④ carries them, so a tool-bearing request may stream', () {
      // Which is the point: the streaming guard resets on every chunk, while
      // the non-streaming one has to cover a whole 6-7 K-token generation.
      expect(LLMDispatcher().streamSupportsTools(config(Vendors.anthropicRest)),
          isTrue);
      expect(
          LLMDispatcher().streamSupportsTools(config(Vendors.newApiAnthropic)),
          isTrue);
    });

    test('③ carries them too — its parser is shared with the sync path', () {
      // No accumulator was needed: a functionCall arrives whole inside a
      // streamed candidate, thoughtSignature included.
      expect(LLMDispatcher().streamSupportsTools(config(Vendors.googleRest)),
          isTrue);
      expect(
          LLMDispatcher().streamSupportsTools(config(Vendors.officialGoogle)),
          isTrue);
    });

    test('① carries them since it grew an accumulator', () {
      // The one that mattered most in practice: nearly every relay channel
      // resolves to ①, so until `StreamingToolCallAccumulator` existed every
      // assistant turn on a relay was silently downgraded to the synchronous
      // path and had to fit a 6-7 K-token answer inside one deadline.
      for (final vendor in [Vendors.openAIRest, Vendors.newApiOpenAI]) {
        expect(LLMDispatcher().streamSupportsTools(config(vendor)), isTrue,
            reason: '$vendor should stream its tool calls');
      }
    });

    test('Midjourney keeps the downgrade — it has no accumulator', () {
      // Claiming the capability without one answers a tool-bearing request as
      // though no tools existed, which is the failure an agent loop cannot
      // detect. The guard has to keep failing for something.
      expect(
          LLMDispatcher().streamSupportsTools(config(Vendors.midjourneyProxy)),
          isFalse);
    });

    test('the protocols agree with the routing table', () {
      // The dispatcher answers per family by hand, so it can drift from what
      // the protocols actually implement. This is the pin against that.
      expect(AnthropicChatProtocol().streamingDeclaresTools, isTrue);
      expect(GeminiChatProtocol().streamingDeclaresTools, isTrue);
      expect(OpenAIChatProtocol().streamingDeclaresTools, isTrue);
      expect(DashScopeChatProtocol().streamingDeclaresTools, isTrue);
    });
  });

  group('the streaming idle guard', () {
    // _idleGuarded is private, so this exercises the shape it has to have
    // rather than the function itself: the first chunk gets a longer budget
    // than the ones after it, and a stall cancels the subscription.
    test('a slow first chunk is not a dead connection', () async {
      // The failure this prevents: a large prompt still prefilling behind a
      // queue looks identical to a dead socket, and calling it dead re-sends
      // the whole request — the waste this change set removed.
      var cancelled = false;
      final controller = StreamController<int>(onCancel: () => cancelled = true);

      final collected = <int>[];
      final done = LLMService.idleGuardedForTest(
        controller.stream,
        first: const Duration(milliseconds: 400),
        subsequent: const Duration(milliseconds: 80),
      ).forEach(collected.add);

      // Later than `subsequent` allows, earlier than `first` does.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      controller.add(1);
      await controller.close();
      await done;

      expect(collected, [1]);
      expect(cancelled, isTrue, reason: 'the subscription must be torn down');
    });

    test('a gap after the first chunk fails fast', () async {
      final controller = StreamController<int>();
      final guarded = LLMService.idleGuardedForTest(
        controller.stream,
        first: const Duration(seconds: 5),
        subsequent: const Duration(milliseconds: 80),
      );

      final collected = <int>[];
      final done = guarded.forEach(collected.add);
      controller.add(1);
      // ...and then nothing, for longer than `subsequent`.

      await expectLater(done, throwsA(isA<TimeoutException>()));
      expect(collected, [1]);
      await controller.close();
    });

    test('a stalled stream is actually cancelled, unlike the sync path', () async {
      // Future.timeout on the non-streaming path leaves its request running
      // upstream and billing. This one does not.
      var cancelled = false;
      final controller = StreamController<int>(onCancel: () => cancelled = true);

      final done = LLMService.idleGuardedForTest(
        controller.stream,
        first: const Duration(milliseconds: 60),
        subsequent: const Duration(milliseconds: 60),
      ).forEach((_) {});

      await expectLater(done, throwsA(isA<TimeoutException>()));
      expect(cancelled, isTrue);
      await controller.close();
    });
  });
}
