@Tags(['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/llm_channel.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/gallery/image_card.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/workbench_layout.dart';
import 'package:joycai_image_ai_toolkits/services/tasks/task_queue_service.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:provider/provider.dart';

import 'harness/fixture_env.dart';
import 'harness/shoot.dart';
import 'harness/suite.dart';

void main() {
  late FixtureEnv env;
  setUpScreenSuite((e) => env = e);
  for (final locale in [
    const Locale('en'),
    const Locale('zh'),
    const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    const Locale('ja'),
  ]) {
    for (final size in kShotSizes) {
      for (final brightness in Brightness.values) {
        testWidgets('batch tasks ${locale.toLanguageTag()} ${size.label} ${brightness.name}', (
          tester,
        ) async {
          await shoot(
            tester,
            env: env,
            screen: AppScreen.tasks,
            size: size,
            brightness: brightness,
            locale: locale,
            suffix: 'batch_${locale.toLanguageTag()}',
            before: (_) async {
              AppState().isConsoleExpanded = false;
              AppState().taskQueue.setQueueForTest([
                for (final (id, status, state) in [
                  (
                    'waiting',
                    TaskStatus.awaitingRemote,
                    <String, dynamic>{'phase': 'remote', 'remoteStatus': 'in_progress'},
                  ),
                  ('cancel', TaskStatus.awaitingRemote, <String, dynamic>{'cancelRequested': true}),
                  (
                    'retry',
                    TaskStatus.awaitingRemote,
                    <String, dynamic>{'lastError': 'Connection unavailable', 'paused': true},
                  ),
                  ('done', TaskStatus.completed, <String, dynamic>{'settled': true}),
                ])
                  TaskItem(
                    id: id,
                    modelId: 'gpt-image-2.5-sunburst',
                    imagePaths: [],
                    parameters: {'prompt': 'A tree at sunrise'},
                    executionMode: TaskExecutionMode.batch,
                    status: status,
                    batchState: {
                      'batchId': 'batch_example_$id',
                      'lastSuccessfulCheckAt': '2026-10-26T07:30:00Z',
                      ...state,
                    },
                  ),
                TaskItem(
                  id: 'immediate',
                  modelId: 'gpt-image-2',
                  imagePaths: [],
                  parameters: {},
                  status: TaskStatus.completed,
                ),
              ]);
            },
          );
        });
        testWidgets('batch workbench ${locale.toLanguageTag()} ${size.label} ${brightness.name}', (
          tester,
        ) async {
          await shoot(
            tester,
            env: env,
            screen: AppScreen.workbench,
            size: size,
            brightness: brightness,
            locale: locale,
            suffix: 'batch_${locale.toLanguageTag()}',
            before: (_) async {
              final app = AppState();
              final model = app.imageModels.firstWhere((m) => m.modelId == 'gpt-image-2.5-flare');
              final old = app.allChannels.firstWhere((c) => c.id == model.channelId);
              await app.updateChannel(
                old.id!,
                LLMChannel(
                  id: old.id,
                  displayName: old.displayName,
                  endpoint: 'https://api.openai.com/v1',
                  apiKey: old.apiKey,
                  type: old.type,
                ),
              );
              app.lastSelectedModelId = model.id.toString();
              app.setWorkbenchTab(0);
              app.isConsoleExpanded = false;
              app.setUseImageBatch(true);
            },
            after: (tester) async {
              final layout = tester
                  .element(find.byType(ImageCard).first)
                  .read<WorkbenchLayoutState>();
              if (layout.rightPanelDetached) {
                await actInRealAsync(tester, () async => layout.openRightPanel());
              }
              await settle(tester);
              await tester.ensureVisible(
                find.text(lookupAppLocalizations(locale).batchSubmit).first,
              );
              await settle(tester);
            },
          );
        });
      }
    }
  }
}
