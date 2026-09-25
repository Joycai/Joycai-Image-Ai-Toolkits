// The 「反馈给助手」 dialog (`A1 · 3b`) over the workbench gallery: the glass
// shell with the run recap, the verdict tiles, the reason pills under a
// thumbs down, and the note. Dark Rose with 「满意」 chosen and light Blue with
// 「不满意」 and two reasons on, as the design draws them; desktop.
//
//   flutter test test/screenshots/app_screens_result_feedback_test.dart

@Tags(<String>['screenshots'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/constants.dart';
import 'package:joycai_image_ai_toolkits/models/app_image.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/assistant/result_feedback_dialog.dart';

import 'harness/fixture_env.dart';
import 'harness/shoot.dart';
import 'harness/suite.dart';

void main() {
  late FixtureEnv env;
  setUpScreenSuite((FixtureEnv e) => env = e);

  Future<void> open(WidgetTester tester, {required bool satisfied}) async {
    final BuildContext context = tester.element(find.byType(Scaffold).first);
    final AppImage image = AppImage.fromFile(File(env.fixtureImagePaths.first));
    // Not awaited: the dialog stays up for the shot.
    // ignore: unawaited_futures
    showResultFeedbackDialog(
      context,
      image: image,
      promptVersion: 3,
      runMeta: 'gpt-image-1 · 今天 14:02',
      promptText: '深红丝绒背景，香水瓶居中，顶光，浅景深，商业静物摄影，8k',
    );
    await settle(tester);
    await tester.tap(find.byIcon(satisfied ? Icons.thumb_up_outlined : Icons.thumb_down_outlined));
    await settle(tester);
    if (!satisfied) {
      await tester.tap(find.text('与提示不符'));
      await tester.tap(find.text('色彩 / 光线'));
      await settle(tester);
      await tester.enterText(find.byType(TextField).last, '背景偏灰，不是提示里说的青绿渐变；鞋带处细节糊掉了，光也偏软');
      await settle(tester);
    }
  }

  testWidgets('workbench · resultFeedback satisfied @ desktop dark rose', (
    WidgetTester tester,
  ) async {
    await shoot(
      tester,
      env: env,
      screen: AppScreen.workbench,
      size: kShotSizes.last,
      brightness: Brightness.dark,
      accent: AppConstants.presetThemes['Rose'],
      suffix: 'resultFeedback-satisfied',
      after: (WidgetTester tester) => open(tester, satisfied: true),
    );
  });

  testWidgets('workbench · resultFeedback unsatisfied @ desktop light', (
    WidgetTester tester,
  ) async {
    await shoot(
      tester,
      env: env,
      screen: AppScreen.workbench,
      size: kShotSizes.last,
      brightness: Brightness.light,
      suffix: 'resultFeedback-unsatisfied',
      after: (WidgetTester tester) => open(tester, satisfied: false),
    );
  });
}
