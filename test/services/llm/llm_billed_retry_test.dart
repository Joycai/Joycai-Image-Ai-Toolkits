import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

/// B1: a retry on a route that bills at acceptance re-buys the generation.
/// The workbench's Retry Count reaches image tasks, so the retry loop has to
/// know which routes those are and retry only failures provably before
/// acceptance (standards 13 §4.3, 14 §3, 06 §3).
void main() {
  LLMModelConfig config(String modelId, String channelType, {String? tag}) =>
      LLMModelConfig(
        modelId: modelId,
        channelType: channelType,
        endpoint: 'https://example.invalid/v1',
        apiKey: 'k',
        tag: tag,
      );

  group('LLMDispatcher.isBilledOnSubmit', () {
    final dispatcher = LLMDispatcher();

    test('native image surfaces and Midjourney are billed routes', () {
      expect(dispatcher.isBilledOnSubmit(config('gpt-image-1', Vendors.openAIRest)),
          isTrue);
      expect(dispatcher.isBilledOnSubmit(config('qwen-image', Vendors.dashscope)),
          isTrue);
      expect(dispatcher.isBilledOnSubmit(config('image-01', Vendors.minimax)),
          isTrue);
      expect(
          dispatcher.isBilledOnSubmit(config('midjourney', Vendors.midjourneyProxy)),
          isTrue);
    });

    test('an image model riding the chat face is billed too', () {
      // A relay model the user declared an image model: served through chat,
      // paid as a generation all the same.
      expect(
          dispatcher.isBilledOnSubmit(
              config('nano-banana-pro', Vendors.newApiOpenAI, tag: 'image')),
          isTrue);
    });

    test('chat models keep the ordinary retry policy', () {
      expect(dispatcher.isBilledOnSubmit(config('gpt-4o', Vendors.openAIRest)),
          isFalse);
      expect(
          dispatcher.isBilledOnSubmit(
              config('claude-sonnet-4-5', Vendors.anthropicRest)),
          isFalse);
    });
  });

  group('LLMService.shouldRetry on a billed route', () {
    bool billed(Object e) => LLMService.shouldRetry(e, billedOnSubmit: true);
    bool chat(Object e) => LLMService.shouldRetry(e, billedOnSubmit: false);

    test('a relay 5xx after upstream may have drawn is not re-sent', () {
      for (final code in [500, 502, 503, 524]) {
        final e = LLMApiException('failed: $code', statusCode: code);
        expect(billed(e), isFalse, reason: '$code on a billed route');
        expect(chat(e), isTrue, reason: '$code on chat keeps retrying');
      }
    });

    test('a torn-down connection or a stalled stream is not re-sent', () {
      expect(billed(Exception('Connection closed before full header')), isFalse);
      expect(billed(TimeoutException('no chunk')), isFalse);
      expect(chat(Exception('Connection closed before full header')), isTrue);
    });

    test('failures provably before acceptance still retry', () {
      expect(billed(LLMApiException('slow down', statusCode: 429)), isTrue);
      expect(
          billed(http.ClientException(
              'SocketException: Connection refused (OS Error: errno = 111)')),
          isTrue);
      expect(
          billed(http.ClientException(
              "Failed host lookup: 'relay.example.com'")),
          isTrue);
    });

    test('deadline, cancel and abandoned jobs never retry anywhere', () {
      for (final e in <Object>[
        const LLMDeadlineExceeded(Duration(minutes: 5)),
        const LLMCancelled(),
        const LLMJobAbandoned('t1', 'gave up on t1'),
      ]) {
        expect(billed(e), isFalse, reason: '$e');
        expect(chat(e), isFalse, reason: '$e');
      }
    });
  });

  group('single-shot first-chunk guard', () {
    test('expiring on a single-shot route is a deadline, not a timeout',
        () async {
      final never = StreamController<int>();
      addTearDown(never.close);
      final guarded = LLMService.idleGuardedForTest(never.stream,
          first: const Duration(milliseconds: 30),
          subsequent: const Duration(milliseconds: 30),
          firstIsDeadline: true);
      await expectLater(guarded.toList(), throwsA(isA<LLMDeadlineExceeded>()));
    });

    test('a live stream keeps the retryable TimeoutException', () async {
      final never = StreamController<int>();
      addTearDown(never.close);
      final guarded = LLMService.idleGuardedForTest(never.stream,
          first: const Duration(milliseconds: 30),
          subsequent: const Duration(milliseconds: 30));
      await expectLater(guarded.toList(), throwsA(isA<TimeoutException>()));
    });
  });
}
