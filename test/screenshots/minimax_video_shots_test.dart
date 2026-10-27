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
  late int model;
  setUpScreenSuite((e) => env = e);
  setUpAll(() async {
    final app = AppState();
    final channel = await app.addChannel(
      LLMChannel(
        displayName: 'MiniMax',
        endpoint: 'https://api.minimax.cn/v1',
        apiKey: '',
        type: Vendors.minimax,
      ),
    );
    model = await app.addModel(
      LLMModel(
        modelId: 'MiniMax-H3-Max',
        modelName: 'MiniMax H3 Max',
        tag: 'video',
        channelId: channel,
      ),
    );
  });
  for (final locale in [
    const Locale('zh'),
    const Locale('en'),
    const Locale('ja'),
    const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ]) {
    for (final size in kShotSizes) {
      for (final brightness in Brightness.values) {
        for (final showMedia in [false, true]) {
          testWidgets(
            'H3 Max ${locale.toLanguageTag()} ${size.label} ${brightness.name} media=$showMedia',
            (tester) async {
              await shoot(
                tester,
                env: env,
                screen: AppScreen.workbench,
                size: size,
                brightness: brightness,
                locale: locale,
                suffix: 'h3_${locale.toLanguageTag()}${showMedia ? '_media' : ''}',
                before: (_) async {
                  final app = AppState();
                  app.setWorkbenchTab(5);
                  app.isConsoleExpanded = false;
                  await app.updateVideoConfig(modelId: model.toString());
                  final state = app.workbenchUIState;
                  state.setVideoFirstFrame(null);
                  state.setVideoLastFrame(null);
                  state.addVideoReferenceFiles(['/sample/dance_reference.mp4'], audio: false);
                  state.addVideoReferenceFiles(['/sample/voice_reference.wav'], audio: true);
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
                  if (showMedia) {
                    final caption = AppLocalizations.of(tester.element(panel))!
                        .generationReferenceMedia;
                    await Scrollable.ensureVisible(
                      tester.element(find.text(caption).last),
                      alignment: 0,
                    );
                    await settle(tester);
                  }
                },
              );
            },
          );
        }
      }
    }
  }
}
