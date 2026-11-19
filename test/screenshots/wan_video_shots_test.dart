@Tags(['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/llm_channel.dart';
import 'package:joycai_image_ai_toolkits/models/llm_model.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/gallery/image_card.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/video/video_config_panel.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/workbench_layout.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:provider/provider.dart';

import 'harness/fixture_env.dart';
import 'harness/shoot.dart';
import 'harness/suite.dart';

void main() {
  late FixtureEnv env;
  final models = <String, int>{};
  setUpScreenSuite((e) => env = e);
  setUpAll(() async {
    final app = AppState();
    final channel = await app.addChannel(
      LLMChannel(
        displayName: 'DashScope',
        endpoint: 'https://dashscope.aliyuncs.com/api/v1',
        apiKey: '',
        type: Vendors.dashscopeNative,
      ),
    );
    for (final suffix in ['']) {
      models[suffix] = await app.addModel(
        LLMModel(
          modelId: 'wan3.0-video$suffix',
          modelName: 'Wan 3.0 video$suffix',
          tag: 'video',
          channelId: channel,
        ),
      );
    }
  });
  for (final suffix in ['']) {
    for (final size in kShotSizes) {
      for (final brightness in Brightness.values) {
        testWidgets('Wan $suffix ${size.label} ${brightness.name}', (tester) async {
          await shoot(
            tester,
            env: env,
            screen: AppScreen.workbench,
            size: size,
            brightness: brightness,
            locale: const Locale('en'),
            suffix: 'wan3_video',
            before: (_) async {
              final app = AppState();
              app.setWorkbenchTab(5);
              app.isConsoleExpanded = false;
              await app.updateVideoConfig(modelId: models[suffix].toString());
              final state = app.workbenchUIState;
              state.setVideoFirstFrame(null);
              state.setVideoLastFrame(null);
            },
            after: (tester) async {
              final layout = tester
                  .element(find.byType(ImageCard).first)
                  .read<WorkbenchLayoutState>();
              if (layout.rightPanelDetached) {
                await actInRealAsync(tester, () async {
                  layout.openRightPanel();
                });
              }
              final panel = find.byType(VideoConfigPanel).last;
              final text = AppLocalizations.of(tester.element(panel))!.modelSelection;
              await tester.tap(find.descendant(of: panel, matching: find.text(text)).last);
              await settle(tester);
              if (size.label == 'mobile') {
                await tester.ensureVisible(find.text('Watermark').last);
                await settle(tester);
              }
            },
          );
        });
      }
    }
  }
}
