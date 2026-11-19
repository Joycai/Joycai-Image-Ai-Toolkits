import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/app_image.dart';
import 'package:joycai_image_ai_toolkits/models/llm_channel.dart';
import 'package:joycai_image_ai_toolkits/models/llm_model.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/video/video_config_panel.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_button.dart';

import '../../screenshots/harness/fixture_env.dart';
import '../../screenshots/harness/fixture_seed.dart';
import '../../screenshots/harness/shoot.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late FixtureEnv env;
  late int model;
  late AppImage reference;
  setUpAll(() async {
    env = installFixtureEnv(binding);
    await seedFixtures(env);
    reference = AppImage(path: env.sourceDir.listSync().first.path, name: 'frame.png');
    final app = AppState();
    await app.loadSettings();
    final channel = await app.addChannel(
      LLMChannel(
        displayName: 'DashScope',
        endpoint: 'https://dashscope.aliyuncs.com/api/v1',
        apiKey: '',
        type: Vendors.dashscopeNative,
      ),
    );
    model = await app.addModel(
      LLMModel(modelId: 'wan3.0-video', modelName: 'Wan', tag: 'video', channelId: channel),
    );
  });
  tearDownAll(() => env.dispose());

  testWidgets('Wan enables media-only input, removal disables it, oversized prompt cannot queue', (
    tester,
  ) async {
    await mountApp(
      tester,
      env: env,
      screen: AppScreen.workbench,
      size: const Size(1440, 1200),
      label: 'wan_prompt_inputs',
      before: (_) async {
        final app = AppState();
        app.setWorkbenchTab(5);
        await app.updateVideoConfig(modelId: model.toString(), prompt: '');
      },
    );
    final panel = find.byType(VideoConfigPanel);
    final l10n = AppLocalizations.of(tester.element(panel))!;
    AppButton button() => tester
        .widgetList<AppButton>(find.descendant(of: panel, matching: find.byType(AppButton)))
        .firstWhere((b) => b.label == l10n.generateVideo);
    expect(button().onPressed, isNull);
    final app = AppState();
    final state = app.workbenchUIState;
    state.setVideoFirstFrame(reference);
    await tester.pump();
    expect(button().onPressed, isNotNull);
    state.setVideoFirstFrame(null);
    await tester.pump();
    expect(button().onPressed, isNull);
    state.addVideoReferenceImage(reference);
    await tester.pump();
    expect(button().onPressed, isNotNull);
    state.removeVideoReferenceImage(reference);
    await tester.pump();
    expect(button().onPressed, isNull);
    for (final audio in [false, true]) {
      final path = audio ? 'reference.wav' : 'reference.mp4';
      state.addVideoReferenceFiles([path], audio: audio);
      await tester.pump();
      expect(button().onPressed, isNotNull);
      expect(find.text(l10n.generationReferenceMediaLimits(10, 5, 5, 20, 1, 15)), findsOneWidget);
      state.removeVideoReferenceFile(path, audio: audio);
      await tester.pump();
      expect(button().onPressed, isNull);
    }
    final prompt = find.descendant(of: panel, matching: find.byType(TextField)).last;
    tester.widget<TextField>(prompt).controller!.text = ' ';
    await tester.pump();
    expect(button().onPressed, isNull);
    tester.widget<TextField>(prompt).controller!.text = 'a' * 20001;
    await tester.pump();
    final count = app.taskQueue.queue.length;
    button().onPressed!();
    await tester.pump();
    expect(find.text(l10n.generationPromptTooLong(20000)), findsOneWidget);
    expect(app.taskQueue.queue.length, count);
    tester.widget<TextField>(prompt).controller!.text = 'a cat';
    await tester.pump();
    expect(button().onPressed, isNotNull);
  });

  test('empty prompt with only audio/video reaches the persisted queue', () async {
    final app = AppState();
    app.taskQueue.updateConcurrency(0); // No executor or upstream request.
    for (final (key, extension) in [
      ('referenceVideoPaths', 'mp4'),
      ('referenceAudioPaths', 'wav'),
    ]) {
      final count = app.taskQueue.queue.length;
      await app.submitVideoTask(model, {
        'prompt': '',
        key: [File('test/support/reference_media/three_seconds.$extension').absolute.path],
      });
      expect(app.taskQueue.queue.length, count + 1);
      final task = app.taskQueue.queue.firstWhere(
        (t) =>
            ((t.parameters['generation'] as Map?)?['media'] as List?)?.any(
              (m) => m['role'] == (extension == 'mp4' ? 'referenceVideo' : 'referenceAudio'),
            ) ==
            true,
      );
      expect(task.imagePaths, isEmpty);
      expect((task.parameters['generation'] as Map)['prompt'], '');
      expect((task.parameters['generation'] as Map)['media'], hasLength(1));
    }
  });
}
