import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/app_image.dart';
import 'package:joycai_image_ai_toolkits/models/llm_channel.dart';
import 'package:joycai_image_ai_toolkits/models/llm_model.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/video/video_config_panel.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';

import '../../screenshots/harness/fixture_env.dart';
import '../../screenshots/harness/fixture_seed.dart';
import '../../screenshots/harness/shoot.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late FixtureEnv env;
  late int model;
  setUpAll(() async {
    env = installFixtureEnv(binding);
    await seedFixtures(env);
    final app = AppState();
    await app.loadSettings();
    final channel = await app.addChannel(
      LLMChannel(
        displayName: 'xAI',
        endpoint: 'https://api.x.ai/v1',
        apiKey: '',
        type: Vendors.xaiApi,
      ),
    );
    model = await app.addModel(
      LLMModel(
        modelId: 'grok-imagine-video-1.5-lite',
        modelName: 'Lite',
        tag: 'video',
        channelId: channel,
      ),
    );
  });
  tearDownAll(() => env.dispose());

  testWidgets('Lite hides empty references but preserves unsupported selections for removal', (
    tester,
  ) async {
    await mountApp(
      tester,
      env: env,
      screen: AppScreen.workbench,
      size: const Size(1440, 1200),
      label: 'grok_lite_inputs',
      before: (_) async {
        final app = AppState();
        app.setWorkbenchTab(5);
        await app.updateVideoConfig(modelId: model.toString());
      },
    );
    final panel = find.byType(VideoConfigPanel);
    final l10n = AppLocalizations.of(tester.element(panel))!;
    final caption = find.descendant(of: panel, matching: find.text(l10n.referenceImages));
    expect(caption, findsNothing);
    final image = AppImage(path: '/missing-reference.png', name: 'reference.png');
    final state = AppState().workbenchUIState;
    state.addVideoReferenceImage(image);
    await tester.pump();
    expect(caption, findsOneWidget);
    expect(find.text(l10n.referenceImagesNotSupported), findsWidgets);
    state.removeVideoReferenceImage(image);
    await tester.pump();
    expect(caption, findsNothing);
  });
}
