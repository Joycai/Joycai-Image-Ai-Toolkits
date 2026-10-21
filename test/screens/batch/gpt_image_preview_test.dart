import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/tasks/task_queue_service.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';

import '../../screenshots/harness/fixture_env.dart';
import '../../screenshots/harness/fixture_seed.dart';
import '../../screenshots/harness/shoot.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late FixtureEnv env;
  late Uint8List bytes;
  setUpAll(() async {
    env = installFixtureEnv(binding);
    await seedFixtures(env);
    await AppState().loadSettings();
    bytes = await File(env.fixtureImagePaths.first).readAsBytes();
  });
  tearDownAll(() => env.dispose());
  for (final size in [const Size(390, 844), const Size(1440, 900)]) {
    testWidgets('preview updates and disappears on completion at ${size.width}', (tester) async {
      final task = TaskItem(
        id: 'preview',
        imagePaths: [],
        modelId: 'gpt-image-2',
        parameters: {},
        status: TaskStatus.processing,
        imagePreview: bytes,
      );
      await mountApp(
        tester,
        env: env,
        screen: AppScreen.tasks,
        size: size,
        label: 'gpt-preview',
        locale: const Locale('en'),
        before: (_) async {
          AppState().taskQueue.setQueueForTest([task]);
        },
      );
      final preview = find.byWidgetPredicate((w) => w is Image && w.image is ResizeImage);
      expect(find.text('Generation preview · not saved'), findsOneWidget);
      final first = tester.widget<Image>(preview.first).image as ResizeImage;
      expect((first.imageProvider as MemoryImage).bytes, same(bytes));
      final next = Uint8List.fromList(bytes);
      task.imagePreview = next;
      AppState().taskQueue.setQueueForTest([task]);
      await tester.pump();
      final second = tester.widget<Image>(preview.first).image as ResizeImage;
      expect((second.imageProvider as MemoryImage).bytes, same(next));
      expect(task.resultPaths, isEmpty);
      task.status = TaskStatus.completed;
      task.imagePreview = null;
      AppState().taskQueue.setQueueForTest([task]);
      await tester.pump();
      expect(find.text('Generation preview · not saved'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
