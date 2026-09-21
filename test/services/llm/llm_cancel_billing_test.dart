import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/token_usage.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A cancel that lands after upstream already did the (billed) work must not
/// erase that work from the books:
///
/// - A stream that ran to its end is recorded in usage before the cancel is
///   reported — the same order request() keeps.
/// - A video submit is aborted only while its body uploads. Once the body is
///   out the job may already exist upstream, so the submit finishes and its
///   ticket comes back (and is billed); aborting there lost the only id the
///   executor could cancel the job by.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  // Same setup as openai_stream_regressions_test.dart: the protocols touch
  // AppState, whose singletons open the database and reach path_provider.
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final home = Directory.systemTemp.createTempSync('joycai_cancel_billing');

  late HttpServer server;
  late List<TokenUsage> rows;
  final held = <HttpRequest>[];

  LLMModelConfig configFor(String modelId) => LLMModelConfig(
        modelId: modelId,
        channelType: Vendors.openAIRest,
        endpoint: 'http://127.0.0.1:${server.port}/v1',
        apiKey: 'k',
      );

  setUp(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => home.path,
    );
    HttpOverrides.global = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    rows = [];
    LLMService.usageSinkOverride = (row) async => rows.add(row);
  });

  tearDown(() async {
    LLMService.usageSinkOverride = null;
    LLMService.configResolverOverride = null;
    for (final request in held) {
      try {
        await request.response.close();
      } catch (_) {}
    }
    held.clear();
    await server.close(force: true);
    LLMClientPool.disposeAll();
  });

  test('a stream that finished is billed even when cancel lands at its end',
      () async {
    server.listen((request) async {
      await request.drain<void>();
      request.response.headers.contentType =
          ContentType('text', 'event-stream');
      for (final line in [
        'data: {"choices":[{"delta":{"content":"done"},"finish_reason":"stop"}]}',
        'data: {"choices":[],"usage":{"prompt_tokens":3,"completion_tokens":2}}',
        'data: [DONE]',
      ]) {
        request.response.write('$line\n\n');
      }
      await request.response.close();
    });
    LLMService.configResolverOverride = (_) => configFor('test-model');

    var cancelled = false;
    final consumed = () async {
      await for (final _ in LLMService().requestStream(
        modelIdentifier: 'test-model',
        messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
        options: {llmCancellationProbeKey: () => cancelled},
      )) {
        cancelled = true; // The user presses stop as the output arrives.
      }
    }();

    await expectLater(consumed, throwsA(isA<LLMCancelled>()));
    expect(rows, hasLength(1),
        reason: 'the finished stream was billed and must be recorded');
    expect(rows.single.inputTokens, 3);
  });

  test('a cancel after the submit body is sent keeps the job ticket',
      () async {
    var cancelled = false;
    server.listen((request) async {
      await request.drain<void>();
      // The job now exists upstream; the user cancels before the id returns.
      cancelled = true;
      await Future<void>.delayed(const Duration(milliseconds: 700));
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'id': 'video_1'}));
      await request.response.close();
    });
    LLMService.configResolverOverride = (_) => configFor('sora-2');

    final ticket = await LLMService().startLongRunning(
      modelIdentifier: 'sora-2',
      messages: [LLMMessage(role: LLMRole.user, content: 'a cat')],
      options: {llmCancellationProbeKey: () => cancelled},
    );

    expect(ticket.name, 'video_1',
        reason: 'the id is what the executor cancels the upstream job by');
    expect(rows, hasLength(1), reason: 'the accepted submit is billed');
  });

  test('a cancel while the submit body uploads still aborts it', () async {
    var cancelled = false;
    server.listen((request) {
      // Never read: the body cannot finish uploading.
      held.add(request);
      cancelled = true;
    });
    LLMService.configResolverOverride = (_) => configFor('sora-2');

    // A reference image far larger than the loopback socket buffers can
    // absorb: PNG magic, then padding.
    final frame = Uint8List(32 << 20)
      ..setAll(0, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    final submit = LLMService().startLongRunning(
      modelIdentifier: 'sora-2',
      messages: [
        LLMMessage(role: LLMRole.user, content: 'a cat', attachments: [
          LLMAttachment.fromBytes(frame, 'image/png',
              referenceType: LLMReferenceType.firstFrame),
        ]),
      ],
      options: {llmCancellationProbeKey: () => cancelled},
    );

    await expectLater(submit.timeout(const Duration(seconds: 10)),
        throwsA(isA<LLMCancelled>()));
    expect(rows, isEmpty, reason: 'no job was created, nothing is billed');
  });
}
