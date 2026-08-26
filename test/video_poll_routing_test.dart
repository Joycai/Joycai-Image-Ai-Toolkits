// Which surface an already-submitted video operation is polled on.
//
// The rule worth pinning is that the *id* decides, not the channel's current
// wiring. Tasks outlive the config that started them: they sit in the `tasks`
// table across an upgrade, and a vendor that gains a native video surface
// must not re-route the operations it started on `/v1/videos` — a `video_…`
// id means nothing to `GET /tasks/{id}`, so every in-flight video from
// before the upgrade would fail permanently.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

void main() {
  late HttpServer server;
  late List<String> paths;

  setUp(() async {
    paths = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      paths.add(request.uri.path);
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'status': 'in_progress'}));
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  LLMModelConfig config(String channelType) => LLMModelConfig(
        modelId: 'wan2.2-t2v-plus',
        channelType: channelType,
        endpoint: 'http://127.0.0.1:${server.port}/v1',
        apiKey: 'k',
      );

  test('a Sora-style id keeps polling the OpenAI video surface', () async {
    // DashScope declares a native video protocol, and its own poll would take
    // this id to `/tasks/video_abc`. The prefix says where it came from.
    await LLMDispatcher()
        .checkOperation(config(Vendors.dashscope), 'video_abc');
    expect(paths.single, '/v1/videos/video_abc');
  });

  test('a native task id still goes to the native surface', () async {
    // The other half of the rule: everything that is *not* a Sora id keeps
    // following the vendor's declared video protocol.
    await LLMDispatcher()
        .checkOperation(config(Vendors.dashscope), 'a1b2c3d4-task');
    expect(paths.single, contains('/tasks/a1b2c3d4-task'));
  });
}
