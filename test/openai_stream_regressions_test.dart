import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_descriptor.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/openai_chat_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

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
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory home;
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

  setUp(() async {
    // generateStream touches AppState, whose construction reaches
    // path_provider — same mock the debug-logger test uses.
    home = Directory.systemTemp.createTempSync('joycai_stream');
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
    // Best-effort: AppState's singletons keep files open for the process's
    // lifetime, and a locked file must not fail the suite.
    try {
      if (home.existsSync()) home.deleteSync(recursive: true);
    } on FileSystemException {
      // Left for the OS temp cleaner.
    }
  });

  test('tool-call fragments keep the stream audibly alive', () async {
    sseLines = [
      'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1",'
          '"function":{"name":"submit_prompt","arguments":"{\\"p"}}]}}]}',
      'data: {"choices":[{"delta":{"tool_calls":[{"index":0,'
          '"function":{"arguments":"\\":1}"}}]}}]}',
      'data: [DONE]',
    ];

    final chunks = await OpenAIChatProtocol()
        .generateStream(target(), [LLMMessage(role: LLMRole.user, content: 'hi')])
        .toList();

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
      'data: {"choices":[{"delta":{"content":"answer"}}]}',
      'data: [DONE]',
    ];

    final chunks = await OpenAIChatProtocol()
        .generateStream(target(), [LLMMessage(role: LLMRole.user, content: 'hi')])
        .toList();

    final reasoning = chunks.singleWhere((c) => c.reasoningPart != null);
    expect(reasoning.reasoningPart, 'thinking');
    expect(reasoning.reasoningFieldName, 'reasoning_content',
        reason: 'the echo-back key must reach the stream consumer, or the '
            'replayed history drops the reasoning and DeepSeek rejects the '
            'next request of a tool conversation');

    // The alternate spelling is remembered as itself, not normalized.
    sseLines = [
      'data: {"choices":[{"delta":{"reasoning":"hmm"}}]}',
      'data: [DONE]',
    ];
    final alt = (await OpenAIChatProtocol()
            .generateStream(target(), [LLMMessage(role: LLMRole.user, content: 'hi')])
            .toList())
        .singleWhere((c) => c.reasoningPart != null);
    expect(alt.reasoningFieldName, 'reasoning');
  });

  test('inline <think> reasoning carries no field name', () async {
    // Inline reasoning has no echo obligation — a field name here would make
    // the payload builder invent a key DeepSeek never sent.
    sseLines = [
      'data: {"choices":[{"delta":{"content":"<think>pondering</think>done"}}]}',
      'data: [DONE]',
    ];

    final chunks = await OpenAIChatProtocol()
        .generateStream(target(), [LLMMessage(role: LLMRole.user, content: 'hi')])
        .toList();

    final reasoning = chunks.where((c) => c.reasoningPart != null);
    expect(reasoning, isNotEmpty);
    expect(reasoning.every((c) => c.reasoningFieldName == null), isTrue);
  });
}
