import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_descriptor.dart';
import 'package:joycai_image_ai_toolkits/services/llm/output_spec.dart'
    show inputImageCountKey, reportedCostKey;
import 'package:joycai_image_ai_toolkits/services/llm/protocols/dashscope_chat_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The ① face's end-of-stream rule (batch A), mirrored on DashScope's native
/// chat stream, which shares its tool-call accumulator: a stream that closes
/// without a finish reason never executes a half-built call, and cut-off text
/// is delivered as truncated. Same loopback harness as
/// `openai_stream_regressions_test.dart`.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final home = Directory.systemTemp.createTempSync('joycai_ds_stream');

  late HttpServer server;
  late List<String> sseLines;

  LLMTarget target() {
    final config = LLMModelConfig(
      modelId: 'qwen-plus',
      channelType: Vendors.dashscopeNative,
      endpoint: 'http://${server.address.host}:${server.port}/api/v1',
      apiKey: 'k',
    );
    return LLMTarget(
      config: config,
      vendor: Vendors.byId(config.channelType),
      model: ModelDescriptor.of(config.modelId),
    );
  }

  Future<List<LLMResponseChunk>> run() => DashScopeChatProtocol()
      .generateStream(target(), [LLMMessage(role: LLMRole.user, content: 'hi')])
      .toList();

  String frame(String message, {String finish = 'null'}) =>
      'data: {"output":{"choices":[{"message":$message,'
      '"finish_reason":"$finish"}]}}';

  setUp(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => home.path,
    );
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

  test('a stream cut mid tool call fails instead of executing it', () async {
    sseLines = [
      frame('{"role":"assistant","content":"","tool_calls":[{"index":0,'
          '"id":"call_1","function":{"name":"submit_prompt",'
          '"arguments":"{\\"prompt\\": \\"half"}}]}'),
    ];
    await expectLater(
      run(),
      throwsA(isA<LLMApiException>()
          .having((e) => e.message, 'message', contains('truncated'))),
    );
  });

  test('text cut before its finish reason is delivered as truncated',
      () async {
    sseLines = [
      frame('{"role":"assistant","content":"the answer so f"}'),
    ];
    final chunks = await run();
    expect(chunks.map((c) => c.textPart).nonNulls.join(), 'the answer so f');
    final metadata = chunks.map((c) => c.metadata).nonNulls.single;
    expect(metadata['finish_reason'], 'length');
    expect(metadata['stream_incomplete'], isTrue);
  });

  test('a finished stream is not marked incomplete', () async {
    sseLines = [
      frame('{"role":"assistant","content":"done"}', finish: 'stop'),
    ];
    final metadata =
        (await run()).map((c) => c.metadata).nonNulls.single;
    expect(metadata, {'finish_reason': 'stop'});
  });

  test('a usage frame naming the app\'s own keys is not taken at its word',
      () async {
    // The usage recorder reads these two keys for every vendor; the stream
    // face spreads the frame's usage block, so it must go through
    // `upstreamUsage` like the synchronous face does.
    sseLines = [
      'data: {"output":{"choices":[{"message":{"role":"assistant",'
          '"content":"done"},"finish_reason":"stop"}]},'
          '"usage":{"input_tokens":3,"output_tokens":1,'
          '"$reportedCostKey":99,"$inputImageCountKey":7}}',
    ];
    final metadata =
        (await run()).map((c) => c.metadata).nonNulls.single;
    expect(metadata['input_tokens'], 3);
    expect(metadata.containsKey(reportedCostKey), isFalse);
    expect(metadata.containsKey(inputImageCountKey), isFalse);
  });
}
