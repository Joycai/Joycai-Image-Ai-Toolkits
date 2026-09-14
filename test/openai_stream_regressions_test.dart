import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_descriptor.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/gemini_chat_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/openai_chat_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Pins the two stream-level obligations that came due when
/// `streamingDeclaresTools` flipped ① onto the streaming path — both silent
/// when broken:
///
/// - A chunk must be yielded while `tool_calls` fragments arrive. The
///   consumer's idle guard resets only on chunks it receives, so a model
///   answering with one long tool call and no text looked like a dead
///   connection at exactly the moment it was delivering, timed out, and was
///   re-sent — billed again each time.
/// - The reasoning field *name* must ride the chunks. The stream consumer
///   assembles the LLMResponse, and without the name the ① payload builder
///   drops tool-turn reasoning from replayed history — which DeepSeek
///   rejects with a 400 on the next request of the conversation.
///
/// And the end-of-stream integrity rules of the 2026-09-14 audit (batch A):
/// the finish reason reaches metadata without usage, a stream cut before its
/// finish reason never executes a half-built call, and a stream of empty
/// chunks is not a successful reply.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  // generateStream touches AppState, whose singletons open the app database
  // in a fire-and-forget future. Without an FFI-backed factory that open
  // fails on the CI runner and the async error is pinned on whichever test
  // finished first ("failed after test completion") — same setup as
  // llm_config_resolver_test.dart.
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // generateStream touches AppState, whose construction reaches
  // path_provider — same mock the debug-logger test uses. One directory for
  // the whole suite, created before any test and never deleted mid-run: the
  // singletons open the app database lazily in a fire-and-forget future, and
  // a per-test tearDown that removes the directory races that open. On
  // Windows the delete failed on locked files and the race stayed invisible;
  // on the Linux CI runner it succeeded, the open found no directory
  // (SqliteException 14), and the async error was pinned on whichever test
  // finished first. systemTemp is left to the OS cleaner.
  final home = Directory.systemTemp.createTempSync('joycai_stream');

  late HttpServer server;
  late List<String> sseLines;

  LLMTarget target() {
    final config = LLMModelConfig(
      modelId: 'test-model',
      channelType: Vendors.openAIRest,
      endpoint: 'http://${server.address.host}:${server.port}/v1',
      apiKey: 'k',
    );
    return LLMTarget(
      config: config,
      vendor: Vendors.byId(config.channelType),
      model: ModelDescriptor.of(config.modelId),
    );
  }

  Future<List<LLMResponseChunk>> run() => OpenAIChatProtocol()
      .generateStream(target(), [LLMMessage(role: LLMRole.user, content: 'hi')])
      .toList();

  setUp(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => home.path,
    );
    // The test binding swaps HttpClient for a stub that answers 400 to
    // everything; this suite talks to its own loopback server, so restore
    // real networking.
    HttpOverrides.global = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType =
          ContentType('text', 'event-stream');
      for (final line in sseLines) {
        request.response.write('$line\n\n');
      }
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    LLMClientPool.disposeAll();
  });

  test('tool-call fragments keep the stream audibly alive', () async {
    sseLines = [
      'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1",'
          '"function":{"name":"submit_prompt","arguments":"{\\"p"}}]}}]}',
      'data: {"choices":[{"delta":{"tool_calls":[{"index":0,'
          '"function":{"arguments":"\\":1}"}}]}}]}',
      'data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}',
      'data: [DONE]',
    ];

    final chunks = await run();

    // One keepalive per tool-bearing frame: no text, no call yet — just a
    // pulse for the idle guard.
    final keepalives = chunks.where((c) =>
        c.textPart == null &&
        c.reasoningPart == null &&
        c.imagePart == null &&
        c.toolCallPart == null &&
        c.metadata == null &&
        !c.isDone);
    expect(keepalives.length, 2,
        reason: 'each tool_calls frame must yield a chunk or the idle guard '
            'times the stream out mid-delivery');

    // The call itself still arrives whole, after the loop.
    final call = chunks.singleWhere((c) => c.toolCallPart != null).toolCallPart!;
    expect(call.name, 'submit_prompt');
    expect(call.arguments, {'p': 1});
  });

  test('the reasoning field name survives the streaming path', () async {
    sseLines = [
      'data: {"choices":[{"delta":{"reasoning_content":"thinking"}}]}',
      'data: {"choices":[{"delta":{"content":"answer"},"finish_reason":"stop"}]}',
      'data: [DONE]',
    ];

    final chunks = await run();

    final reasoning = chunks.singleWhere((c) => c.reasoningPart != null);
    expect(reasoning.reasoningPart, 'thinking');
    expect(reasoning.reasoningFieldName, 'reasoning_content',
        reason: 'the echo-back key must reach the stream consumer, or the '
            'replayed history drops the reasoning and DeepSeek rejects the '
            'next request of a tool conversation');

    // The alternate spelling is remembered as itself, not normalized.
    sseLines = [
      'data: {"choices":[{"delta":{"reasoning":"hmm"},"finish_reason":"stop"}]}',
      'data: [DONE]',
    ];
    final alt = (await run()).singleWhere((c) => c.reasoningPart != null);
    expect(alt.reasoningFieldName, 'reasoning');
  });

  test('inline <think> reasoning carries no field name', () async {
    // Inline reasoning has no echo obligation — a field name here would make
    // the payload builder invent a key DeepSeek never sent.
    sseLines = [
      'data: {"choices":[{"delta":{"content":"<think>pondering</think>done"},'
          '"finish_reason":"stop"}]}',
      'data: [DONE]',
    ];

    final chunks = await run();

    final reasoning = chunks.where((c) => c.reasoningPart != null);
    expect(reasoning, isNotEmpty);
    expect(reasoning.every((c) => c.reasoningFieldName == null), isTrue);
  });

  group('end-of-stream integrity', () {
    test('a finish reason reaches metadata even when no usage was sent',
        () async {
      // llama.cpp, LM Studio and many relays send no usage block; the
      // metadata chunk used to be gated on usage alone, so `length` never
      // reached the truncation warning on exactly those hosts.
      sseLines = [
        'data: {"choices":[{"delta":{"content":"as far as I got"},'
            '"finish_reason":"length"}]}',
        'data: [DONE]',
      ];
      final metadata = (await run()).map((c) => c.metadata).nonNulls.single;
      expect(metadata, {'finish_reason': 'length'});
    });

    test('content_filter without usage reaches the content-block check',
        () async {
      sseLines = [
        'data: {"choices":[{"delta":{"content":"partial"},'
            '"finish_reason":"content_filter"}]}',
        'data: [DONE]',
      ];
      final metadata = (await run()).map((c) => c.metadata).nonNulls.single;
      expect(contentBlockedFailure(metadata), isNotNull);
    });

    test('a stream cut mid tool call fails instead of executing it', () async {
      // No finish_reason, arguments cut mid-JSON: flush() would decode them
      // to {} with a WARN and the agent loop would run the call.
      sseLines = [
        'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1",'
            '"function":{"name":"submit_prompt","arguments":"{\\"prompt\\": \\"half"}}]}}]}',
      ];
      await expectLater(
        run(),
        throwsA(isA<LLMApiException>().having(
            (e) => e.message, 'message', contains('truncated'))),
      );
    });

    test('text cut before its finish reason is delivered as truncated',
        () async {
      sseLines = [
        'data: {"choices":[{"delta":{"content":"the answer so f"}}]}',
      ];
      final chunks = await run();
      expect(chunks.map((c) => c.textPart).nonNulls.join(), 'the answer so f');
      final metadata = chunks.map((c) => c.metadata).nonNulls.single;
      expect(metadata['finish_reason'], 'length');
      expect(metadata['stream_incomplete'], isTrue);
    });

    test('chunks with nothing in them are not a successful empty reply',
        () async {
      sseLines = [
        'data: {"choices":[{"delta":{"role":"assistant"}}]}',
        'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}',
        'data: {"choices":[],"usage":{"prompt_tokens":9,"completion_tokens":0}}',
        'data: [DONE]',
      ];
      await expectLater(
        run(),
        throwsA(isA<LLMApiException>()
            .having((e) => e.message, 'message', contains('no content'))
            .having((e) => e.message, 'message', contains('stop'))),
      );
    });

    test('inline <think> text never joins the echoable reasoning field',
        () async {
      // The field's text goes back under `reasoning_content`; an inline span
      // merged into it would be replayed into a key the host reads as its own.
      sseLines = [
        '{"choices":[{"message":{"role":"assistant",'
            '"reasoning_content":"native thought",'
            '"content":"<think>inline thought</think>answer"},'
            '"finish_reason":"stop"}]}',
      ];
      final response = await OpenAIChatProtocol().generate(
          target(), [LLMMessage(role: LLMRole.user, content: 'hi')]);
      expect(response.text, 'answer');
      expect(response.reasoningFieldName, 'reasoning_content');
      expect(response.reasoningContent, 'native thought');
    });

    test('an empty reasoning_content does not hide a non-empty reasoning',
        () async {
      // `reasoning_content ?? reasoning` picked "" because "" is not null;
      // the thought was dropped and the echo key was wrong.
      sseLines = [
        '{"choices":[{"message":{"role":"assistant","reasoning_content":"",'
            '"reasoning":"real thought","content":"answer"},'
            '"finish_reason":"stop"}]}',
      ];
      final response = await OpenAIChatProtocol().generate(
          target(), [LLMMessage(role: LLMRole.user, content: 'hi')]);
      expect(response.reasoningContent, 'real thought');
      expect(response.reasoningFieldName, 'reasoning');

      sseLines = [
        'data: {"choices":[{"delta":{"reasoning_content":"","reasoning":"hmm"}}]}',
        'data: {"choices":[{"delta":{"content":"ok"},"finish_reason":"stop"}]}',
        'data: [DONE]',
      ];
      final streamed = (await run()).singleWhere((c) => c.reasoningPart != null);
      expect(streamed.reasoningPart, 'hmm');
      expect(streamed.reasoningFieldName, 'reasoning');
    });

    test('DeepSeek cache hits reach the cached-token field', () async {
      // DeepSeek reports them as top-level `prompt_cache_hit_tokens`, which
      // the usage recorder does not read — every hit was billed as full input.
      sseLines = [
        '{"choices":[{"message":{"role":"assistant","content":"answer"},'
            '"finish_reason":"stop"}],"usage":{"prompt_tokens":100,'
            '"completion_tokens":5,"prompt_cache_hit_tokens":80,'
            '"prompt_cache_miss_tokens":20}}',
      ];
      final response = await OpenAIChatProtocol().generate(
          target(), [LLMMessage(role: LLMRole.user, content: 'hi')]);
      expect(response.metadata['prompt_tokens_details'], {'cached_tokens': 80});
      expect(response.metadata['prompt_cache_hit_tokens'], 80,
          reason: 'the raw field rides along untouched');

      sseLines = [
        'data: {"choices":[{"delta":{"content":"ok"},"finish_reason":"stop"}]}',
        'data: {"choices":[],"usage":{"prompt_tokens":50,"completion_tokens":1,'
            '"prompt_cache_hit_tokens":30}}',
        'data: [DONE]',
      ];
      final metadata = (await run()).map((c) => c.metadata).nonNulls.single;
      expect(metadata['prompt_tokens_details'], {'cached_tokens': 30});

      // A host that already reports the OpenAI spelling keeps its own value.
      sseLines = [
        '{"choices":[{"message":{"role":"assistant","content":"answer"},'
            '"finish_reason":"stop"}],"usage":{"prompt_tokens":100,'
            '"prompt_tokens_details":{"cached_tokens":64},'
            '"prompt_cache_hit_tokens":80}}',
      ];
      final both = await OpenAIChatProtocol().generate(
          target(), [LLMMessage(role: LLMRole.user, content: 'hi')]);
      expect(both.metadata['prompt_tokens_details'], {'cached_tokens': 64});
    });

    test('a reasoning field records the model that produced it', () async {
      // The replay scope: the payload builder echoes the field only to this
      // model (reasoning 03 §5).
      sseLines = [
        '{"choices":[{"message":{"role":"assistant",'
            '"reasoning_content":"thought","content":"answer"},'
            '"finish_reason":"stop"}]}',
      ];
      final response = await OpenAIChatProtocol().generate(
          target(), [LLMMessage(role: LLMRole.user, content: 'hi')]);
      expect(response.rawThinkingModelId, 'test-model');

      sseLines = [
        '{"choices":[{"message":{"role":"assistant","content":"answer"},'
            '"finish_reason":"stop"}]}',
      ];
      final plain = await OpenAIChatProtocol().generate(
          target(), [LLMMessage(role: LLMRole.user, content: 'hi')]);
      expect(plain.rawThinkingModelId, isNull);
    });

    test('the synchronous path refuses an empty message too', () async {
      sseLines = [
        '{"choices":[{"message":{"role":"assistant","content":""},'
            '"finish_reason":"stop"}],"usage":{"prompt_tokens":4}}',
      ];
      await expectLater(
        OpenAIChatProtocol().generate(
            target(), [LLMMessage(role: LLMRole.user, content: 'hi')]),
        throwsA(isA<LLMApiException>()
            .having((e) => e.message, 'message', contains('no content'))),
      );

      // …while an empty `length` ending is still delivered.
      sseLines = [
        '{"choices":[{"message":{"role":"assistant","content":""},'
            '"finish_reason":"length"}]}',
      ];
      final truncated = await OpenAIChatProtocol().generate(
          target(), [LLMMessage(role: LLMRole.user, content: 'hi')]);
      expect(truncated.metadata['finish_reason'], 'length');
    });

    test('③ a stream that decodes to no chunk at all is a failure', () async {
      // ① had `sawChunk`, ④ `sawMessage`, DashScope `sawFrame`; ③ ended an
      // HTML-behind-200 or keep-alive-only stream as a successful empty reply.
      sseLines = [': keep-alive', '<html>not the API</html>'];
      final config = LLMModelConfig(
        modelId: 'gemini-2.5-flash',
        channelType: Vendors.googleRest,
        endpoint: 'http://${server.address.host}:${server.port}/v1beta',
        apiKey: 'k',
      );
      final gemini = LLMTarget(
        config: config,
        vendor: Vendors.byId(config.channelType),
        model: ModelDescriptor.of(config.modelId),
      );
      await expectLater(
        GeminiChatProtocol().generateStream(
            gemini, [LLMMessage(role: LLMRole.user, content: 'hi')]).toList(),
        throwsA(isA<LLMApiException>()
            .having((e) => e.isNonJsonBody, 'isNonJsonBody', isTrue)),
      );
    });

    test('an empty reply that ran out of tokens is still a length ending',
        () async {
      // All budget spent elsewhere: routed to the truncation handling, not
      // reported as a broken endpoint.
      sseLines = [
        'data: {"choices":[{"delta":{},"finish_reason":"length"}]}',
        'data: [DONE]',
      ];
      final metadata = (await run()).map((c) => c.metadata).nonNulls.single;
      expect(metadata['finish_reason'], 'length');
    });
  });
}
