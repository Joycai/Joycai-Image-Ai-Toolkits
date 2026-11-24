import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/l10n/localizations_delegates.dart';
import 'package:joycai_image_ai_toolkits/models/task_item.dart';
import 'package:joycai_image_ai_toolkits/screens/batch/task_queue_card.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../screenshots/harness/suite.dart';

void main() {
  setUpScreenSuite((_) {});
  for (final mode in ['edit', 'extend']) {
    testWidgets('completed $mode task displays source and reopens result in selected mode', (
      tester,
    ) async {
      final path = File('test/support/reference_media/three_seconds.mp4').absolute.path;
      final task = TaskItem(
        id: 'video',
        type: TaskType.videoGenerate,
        imagePaths: [],
        modelId: 'Wan',
        parameters: {
          'videoTask': mode,
          'sourceVideoPath': path,
          'extendDirection': 'forward',
          'prompt': 'sunrise',
        },
        status: TaskStatus.completed,
        resultPaths: [path],
      );
      await pumpWidgetInRealAsync(
        tester,
        ChangeNotifierProvider.value(
          value: AppState(),
          child: MaterialApp(
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    TaskMenuButton(task: task),
                    TaskExpandedDetails(task: task),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await settle(tester);
      expect(find.text(mode == 'edit' ? 'Edit video' : 'Extend video'), findsOneWidget);
      expect(find.text('three_seconds.mp4'), findsNWidgets(2));
      if (mode == 'extend') expect(find.text('Before'), findsOneWidget);
      await inRealAsync(tester, () => tester.tap(find.byType(TaskMenuButton)));
      await settle(tester);
      final label = mode == 'edit' ? 'Edit video' : 'Extend video';
      final menuAction = find.text(label).last;
      await inRealAsyncUntil(
        tester,
        () => tester.tap(menuAction),
        until: () =>
            AppState().workbenchUIState.videoSourceVideoPath != null &&
            !AppState().workbenchUIState.videoSourceProbing,
      );
      expect(AppState().workbenchUIState.videoSourceVideoPath, endsWith('.mp4'));
      AppState().workbenchUIState.clearVideoSourceVideo();
    });
  }
}
