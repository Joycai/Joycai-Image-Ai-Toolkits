@Tags(<String>['screenshots'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/tasks/task_queue_service.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';

import 'harness/fixture_env.dart';
import 'harness/shoot.dart';
import 'harness/suite.dart';

void main() {
  late FixtureEnv env;
  setUpScreenSuite((e) => env = e);
  for (final size in kShotSizes) {
    for (final brightness in Brightness.values) {
      testWidgets('GPT preview ${size.label} ${brightness.name}', (tester) async {
        await shoot(
          tester,
          env: env,
          screen: AppScreen.tasks,
          size: size,
          brightness: brightness,
          locale: const Locale('en'),
          suffix: 'gptPreview',
          before: (_) async {
            final task = TaskItem(
              id: 'gpt-preview',
              modelId: 'gpt-image-2.5-sunburst',
              imagePaths: [],
              parameters: {'prompt': 'A poster'},
              status: TaskStatus.processing,
              imagePreview: await File(env.fixtureImagePaths.first).readAsBytes(),
            );
            AppState().taskQueue.setQueueForTest([task]);
            AppState().isConsoleExpanded = false;
          },
        );
      });
    }
  }
}
