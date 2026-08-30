// Which surface an already-submitted video operation is polled on.
//
// The rule worth pinning is that the operation's *provenance* decides, not
// the channel's current wiring. Tasks outlive the config that started them:
// they sit in the `tasks` table across an upgrade, and a vendor that gains a
// native video surface must not re-route the operations it started on
// `/v1/videos` — a `video_…` id means nothing to `GET /tasks/{id}`, so every
// in-flight video from before the upgrade would fail permanently.
//
// Since schema v38 the submit ticket's surface is persisted with the task and
// passed back as `surfaceId`, which routes ahead of everything else. The
// id-prefix guards below it remain as the fallback for pre-v38 rows and any
// caller without a surface.
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

  test('the guard holds on a channel re-pointed at a ④ vendor', () async {
    // The ① branch had this rule from the start; the anthropic branch did
    // not, so editing a channel's supplier to minimax-anthropic mid-poll
    // handed the in-flight `video_…` id to MiniMax's /v2 query, where it
    // resolves to nothing and the task fails permanently.
    await LLMDispatcher()
        .checkOperation(config(Vendors.minimaxAnthropic), 'video_abc');
    expect(paths.single, endsWith('/videos/video_abc'));
  });

  test('the guard holds on a channel re-pointed at dashscope-native', () async {
    await LLMDispatcher()
        .checkOperation(config(Vendors.dashscopeNative), 'video_abc');
    expect(paths.single, endsWith('/videos/video_abc'));
  });

  test('a persisted surface outranks the channel wiring and the id shape', () async {
    // No `video_` prefix, and the channel's own declaration says
    // `video-synthesis` — the recorded provenance alone sends the poll to
    // the ① surface it names.
    await LLMDispatcher().checkOperation(
      config(Vendors.dashscope),
      'task-from-a-relay',
      surfaceId: 'openai-videos',
    );
    expect(paths.single, '/v1/videos/task-from-a-relay');
  });

  test('a persisted surface holds across a vendor re-point', () async {
    // The submit ran on dashscope-video; the channel was then re-pointed at
    // a ④ vendor. The ticket's surface keeps the poll on `video-synthesis`'
    // task endpoint instead of MiniMax's query.
    await LLMDispatcher().checkOperation(
      config(Vendors.minimaxAnthropic),
      'a1b2c3d4-task',
      surfaceId: 'dashscope-video',
    );
    expect(paths.single, contains('/tasks/a1b2c3d4-task'));
  });

  test('an unrecognized surface degrades to the legacy routing', () async {
    // A row written by a newer build must not fail — it falls through to the
    // id-prefix guard, which still lands this id correctly.
    await LLMDispatcher().checkOperation(
      config(Vendors.dashscope),
      'video_abc',
      surfaceId: 'surface-from-the-future',
    );
    expect(paths.single, '/v1/videos/video_abc');
  });

  test('cancel follows the surface and answers null when it has no cancel', () async {
    // The ① surface implements no cancel. The channel's current vendor
    // (minimax-anthropic) declares one — but the job never ran there, so a
    // pinned surface must answer null rather than fall back and delete a
    // stranger's task. No request may go out at all.
    final action = await LLMDispatcher().cancelOperation(
      config(Vendors.minimaxAnthropic),
      'video_abc',
      surfaceId: 'openai-videos',
    );
    expect(action, isNull);
    expect(paths, isEmpty);
  });

  test('a ④ vendor still polls its own ids natively', () async {
    try {
      await LLMDispatcher()
          .checkOperation(config(Vendors.minimaxAnthropic), '260900000000000');
    } on Exception {
      // The stub's body is not a MiniMax task object; only the routing —
      // which path the poll went out on — is what this test pins.
    }
    expect(paths.single, isNot(contains('/videos/')));
  });
}
