import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/spec_rate.dart';
import 'package:joycai_image_ai_toolkits/models/token_usage.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/gemini_payload.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/minimax_h3_base_payload.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

/// The reference images a video submit *carried*, as each video surface
/// publishes them ([VideoSubmission.inputImages] → the ticket → the submit's
/// usage row), for a fee group to charge (`D2e`).
///
/// What is pinned per surface is the number that went into the body — after
/// an attachment that cannot be read was dropped, and after the surface's
/// own exclusion (a first frame over references) — because a count taken any
/// earlier bills for frames nobody received.
void main() {
  late HttpServer server;
  late Map<String, dynamic> Function(HttpRequest request) answer;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(answer(request)));
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    LLMService.usageSinkOverride = null;
    LLMService.configResolverOverride = null;
    LLMClientPool.disposeAll();
  });

  String base() => 'http://127.0.0.1:${server.port}';

  LLMModelConfig config(String channelType, String modelId, {String path = '/v1'}) =>
      LLMModelConfig(
        modelId: modelId,
        channelType: channelType,
        endpoint: '${base()}$path',
        apiKey: 'k',
      );

  LLMAttachment frame(LLMReferenceType type) =>
      LLMAttachment.fromBytes(_png, 'image/png', referenceType: type);
  LLMAttachment reference() => LLMAttachment.fromBytes(_png, 'image/png');
  // Neither a path nor bytes: every surface drops it while building the body.
  LLMAttachment unreadable() => LLMAttachment.fromBytes(null, 'image/png');

  Future<LLMOperationTicket> submit(
    LLMModelConfig config,
    List<LLMAttachment> attachments, {
    Map<String, dynamic>? options,
  }) => LLMDispatcher().startLongRunning(config, [
    LLMMessage(role: LLMRole.user, content: 'a cat', attachments: attachments),
  ], options: options);

  test('xAI: the first frame alone, or the references, less one unreadable', () async {
    answer = (_) => {'request_id': 'req_1'};
    final xai = config(Vendors.xaiApi, 'grok-imagine-video-1.5');

    final firstFrame = await submit(xai, [
      frame(LLMReferenceType.firstFrame),
      reference(),
      reference(),
    ]);
    expect(firstFrame.name, 'req_1');
    expect(firstFrame.inputImages, 1, reason: 'references are dropped in favour of the frame');

    final references = await submit(xai, [reference(), unreadable(), reference()]);
    expect(references.inputImages, 2);

    final none = await submit(xai, const []);
    expect(none.inputImages, 0);
  });

  test('OpenAI videos: input_reference plus images[]', () async {
    answer = (_) => {'id': 'video_1'};
    final sora = config(Vendors.openAIRest, 'sora-2');

    final ticket = await submit(sora, [
      frame(LLMReferenceType.firstFrame),
      reference(),
      unreadable(),
    ]);
    expect(ticket.inputImages, 2);
  });

  test('DashScope: every media entry of input.media[]', () async {
    answer = (_) => {
      'output': {'task_id': 'task_1'},
    };
    final wan = config(Vendors.dashscopeNative, 'wan3.0-video', path: '/api/v1');

    final ticket = await submit(wan, [
      frame(LLMReferenceType.firstFrame),
      frame(LLMReferenceType.lastFrame),
      unreadable(),
    ]);
    expect(ticket.inputImages, 2);
  });

  test('MiniMax: what survived the frames-over-references exclusion', () async {
    answer = (_) => {'task_id': 'mm_1'};
    final hailuo = config(Vendors.minimax, 'MiniMax-Hailuo-02');

    final ticket = await submit(hailuo, [
      frame(LLMReferenceType.firstFrame),
      reference(),
      reference(),
    ]);
    expect(ticket.inputImages, 1);
  });

  test(
    'MiniMax H3 local: the same exclusion, with byte attachments written out as files',
    () async {
      answer = (_) => {'id': 'h3_1'};
      final h3 = config(Vendors.minimaxH3Base, 'minimax-h3-base');
      // The protocol writes each byte attachment to the system temp dir so it
      // can travel as a file:// URI, and only the app's start-up sweep reclaims
      // them (after hours). Take back what this test adds — and only that, so
      // a running app's in-flight files are left alone.
      Set<String> tempRefs() => Directory.systemTemp
          .listSync()
          .map((e) => e.path)
          .where((p) => p.split(Platform.pathSeparator).last.startsWith(minimaxH3TempRefPrefix))
          .toSet();
      final before = tempRefs();
      addTearDown(() {
        for (final path in tempRefs().difference(before)) {
          try {
            File(path).deleteSync();
          } catch (_) {}
        }
      });

      final frames = await submit(h3, [
        frame(LLMReferenceType.firstFrame),
        reference(),
        reference(),
      ]);
      expect(frames.name, 'h3_1');
      expect(frames.inputImages, 1, reason: 'references are dropped in favour of the keyframe');

      final references = await submit(h3, [reference(), unreadable(), reference()]);
      expect(references.inputImages, 2);
    },
  );

  test('Veo: first frame, last frame and references are all counted', () {
    final payload = prepareVeoPayload([
      LLMMessage(
        role: LLMRole.user,
        content: 'a cat',
        attachments: [
          frame(LLMReferenceType.firstFrame),
          frame(LLMReferenceType.lastFrame),
          reference(),
          unreadable(),
        ],
      ),
    ], null);
    expect(veoInputImages(payload), 3);
    expect(veoInputImages(const {}), 0);
  });

  test('the submit row carries the count and a per-second group charges it', () async {
    answer = (_) => {'request_id': 'req_2'};
    final rows = <TokenUsage>[];
    LLMService.usageSinkOverride = (row) async => rows.add(row);
    LLMService.configResolverOverride = (_) => LLMModelConfig(
      modelId: 'grok-imagine-video-1.5',
      channelType: Vendors.xaiApi,
      endpoint: '${base()}/v1',
      apiKey: 'k',
      billingMode: 'spec',
      outputUnit: OutputUnit.second,
      outputRates: const [SpecRate(price: 0.08)],
      inputUnitFee: 0.01,
    );

    final ticket = await LLMService().startLongRunning(
      modelIdentifier: 'grok-imagine-video-1.5',
      messages: [
        LLMMessage(role: LLMRole.user, content: 'a cat', attachments: [reference(), reference()]),
      ],
      options: const {'seconds': '1', 'resolution': '480p'},
    );

    expect(ticket.inputImages, 2);
    final row = rows.single;
    expect(row.taskId, LLMService.videoUsageRowId('req_2'));
    expect(row.spec!.inputImages, 2);
    expect(row.spec!.inputUnits, 2);
    // 1 s × $0.08 + 2 × $0.01 — what xAI billed for exactly this request.
    expect(row.cost, closeTo(0.10, 1e-9));
  });
}

/// A 1×1 PNG.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);
