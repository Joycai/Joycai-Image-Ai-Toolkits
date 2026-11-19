@Tags(['screenshots'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/app_image.dart';
import 'package:joycai_image_ai_toolkits/models/llm_channel.dart';
import 'package:joycai_image_ai_toolkits/models/llm_model.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/gallery/image_card.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/preview/media_preview_dialog.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/video/video_config_panel.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/video/video_workbench_view.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/workbench_layout.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:joycai_image_ai_toolkits/services/media/reference_media_probe.dart';
import 'package:joycai_image_ai_toolkits/services/media/video_source_probe.dart';
import 'package:joycai_image_ai_toolkits/services/media/video_thumbnail_service.dart';
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
    VideoThumbnailService.instance.extractorOverride = (source, destination) async {
      await File(env.sourceDir.listSync().first.path).copy(destination);
      return true;
    };
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
    for (final references in [false, true]) {
      for (final size in kShotSizes) {
        for (final brightness in Brightness.values) {
          testWidgets('Wan $suffix refs=$references ${size.label} ${brightness.name}', (
            tester,
          ) async {
            await shoot(
              tester,
              env: env,
              screen: AppScreen.workbench,
              size: size,
              brightness: brightness,
              locale: const Locale('en'),
              suffix: references ? 'wan3_references' : 'wan3_video',
              before: (_) async {
                final app = AppState();
                app.setWorkbenchTab(5);
                app.isConsoleExpanded = false;
                await app.updateVideoConfig(modelId: models[suffix].toString());
                final model = app.videoModels.firstWhere((m) => m.id == models[suffix]);
                await app.setVideoParam(model, 'videoTask', 'generate');
                await app.setVideoParam(model, 'seconds', '-1');
                await app.setVideoParam(model, 'seed', '2147483647');
                final state = app.workbenchUIState;
                state.setVideoFirstFrame(null);
                state.setVideoLastFrame(null);
                for (final audio in [false, true]) {
                  for (final path in [
                    ...(audio ? state.videoReferenceAudios : state.videoReferenceVideos),
                  ]) {
                    state.removeVideoReferenceFile(path, audio: audio);
                  }
                  if (references) {
                    state.addVideoReferenceFiles([
                      audio ? 'forest_ambience.wav' : 'camera_motion.mp4',
                    ], audio: audio);
                  }
                }
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
                if (references) {
                  final heading = AppLocalizations.of(tester.element(panel))!
                      .generationReferenceMedia;
                  await Scrollable.ensureVisible(
                    tester.element(find.text(heading).last),
                    alignment: 0.2,
                  );
                  await settle(tester);
                } else if (size.label == 'mobile') {
                  await tester.ensureVisible(find.text('Duration').last);
                  await settle(tester);
                }
              },
            );
          });
        }
      }
    }
  }
  for (final locale in [
    const Locale('en'),
    const Locale('zh'),
    const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    const Locale('ja'),
  ]) {
    for (final scenario in [
      'edit_empty',
      'edit',
      'edit_invalid',
      'extend_backward',
      'extend_forward',
      'extend_bidirectional',
    ]) {
      for (final size in kShotSizes) {
        for (final brightness in Brightness.values) {
          testWidgets('Wan $scenario ${locale.toLanguageTag()} ${size.label} ${brightness.name}', (
            tester,
          ) async {
            await shoot(
              tester,
              env: env,
              screen: AppScreen.workbench,
              size: size,
              brightness: brightness,
              locale: locale,
              suffix: 'wan3_${scenario}_${locale.toLanguageTag()}',
              before: (_) async {
                final app = AppState();
                app.setWorkbenchTab(5);
                app.isConsoleExpanded = false;
                await app.updateVideoConfig(
                  modelId: models[''].toString(),
                  prompt: locale.languageCode == 'zh'
                      ? '让小猫缓缓走向夕阳'
                      : locale.languageCode == 'ja'
                      ? '猫が夕日に向かってゆっくり歩く'
                      : 'The cat walks slowly into the sunset',
                );
                final model = app.videoModels.firstWhere((m) => m.id == models['']);
                final state = app.workbenchUIState;
                state.setVideoFirstFrame(null);
                state.setVideoLastFrame(null);
                for (final image in [...state.videoReferenceImages]) {
                  state.removeVideoReferenceImage(image);
                }
                for (final audio in [false, true]) {
                  for (final path in [
                    ...(audio ? state.videoReferenceAudios : state.videoReferenceVideos),
                  ]) {
                    state.removeVideoReferenceFile(path, audio: audio);
                  }
                }
                await app.setVideoParam(
                  model,
                  'videoTask',
                  scenario.startsWith('edit') ? 'edit' : 'extend',
                );
                await app.setVideoParam(
                  model,
                  'seconds',
                  scenario.endsWith('forward') ? '10' : '-1',
                );
                if (scenario.startsWith('extend')) {
                  await app.setVideoParam(model, 'extendDirection', scenario.substring(7));
                }
                state.clearVideoSourceVideo();
                if (scenario != 'edit_empty') {
                  await state.setVideoSourceVideo(
                    File('test/support/reference_media/three_seconds.mp4').absolute.path,
                  );
                }
                if (scenario == 'edit') {
                  state.addVideoReferenceImage(
                    AppImage(path: env.sourceDir.listSync().first.path, name: 'reference.png'),
                  );
                }
                if (scenario == 'edit_invalid') {
                  state.videoSourceProbe = const VideoSourceProbe(
                    info: ReferenceMediaInfo(
                      'video/mp4',
                      width: 1280,
                      height: 720,
                      seconds: 20,
                      fps: 30,
                    ),
                  );
                }
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
                await settle(tester);
                final panel = find.byType(VideoConfigPanel).last;
                final label = AppLocalizations.of(tester.element(panel))!.sourceVideo;
                final source = find
                    .descendant(of: panel, matching: find.textContaining(label))
                    .first;
                await Scrollable.ensureVisible(tester.element(source), alignment: .15);
                await settle(tester);
              },
            );
          });
        }
      }
    }
  }
  for (final locale in [
    const Locale('en'),
    const Locale('zh'),
    const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    const Locale('ja'),
  ]) {
    for (final size in kShotSizes) {
      for (final brightness in Brightness.values) {
        for (final surface in ['player', 'preview']) {
          testWidgets('video $surface ${locale.toLanguageTag()} ${size.label} ${brightness.name}', (
            tester,
          ) async {
            final path = File('test/support/reference_media/three_seconds.mp4').absolute.path;
            await shoot(
              tester,
              env: env,
              screen: AppScreen.workbench,
              size: size,
              brightness: brightness,
              locale: locale,
              suffix: 'wan3_${surface}_${locale.toLanguageTag()}',
              before: (_) async {
                final app = AppState();
                app.setWorkbenchTab(5);
                app.workbenchUIState.setLastGeneratedVideoPath(surface == 'player' ? path : null);
                app.workbenchUIState.videoPanelHandled = app.workbenchUIState.videoPanelRequest;
                app.workbenchUIState.clearVideoSourceVideo();
              },
              after: (_) async {
                if (surface == 'preview') {
                  showMediaPreview(
                    tester.element(find.byType(Scaffold).first),
                    galleryImages: [AppImage.fromFile(File(path))],
                    initialIndex: 0,
                  );
                } else {
                  final player = find.byType(VideoWorkbenchOverlay);
                  final more = find.descendant(of: player, matching: find.byIcon(Icons.more_horiz));
                  if (more.evaluate().isNotEmpty) await tester.tap(more);
                }
                await settle(tester);
              },
            );
          });
        }
      }
    }
  }
}
