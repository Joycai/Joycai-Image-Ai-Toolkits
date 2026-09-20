// `A3d 4c`: the assistant's 「管理预设」 lands on the presets — the library's
// system templates, filtered to refiner — and only for that one visit.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/screens/prompts/prompts_screen.dart';
import 'package:joycai_image_ai_toolkits/screens/prompts/widgets/prompts_header.dart';
import 'package:joycai_image_ai_toolkits/services/tasks/task_queue_service.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/state/log_state.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/private_data_dir.dart';

void main() {
  usePrivateDataDir('joycai_prompts_template_request_test');
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // After `setUpAll`: the queue reads the database as it is made.
  late final queue = TaskQueueService();

  Future<void> pumpLibrary(WidgetTester tester, AppState app, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // Real async throughout: the screen and the queue both read the database
    // as they start, and sqflite's lock timer would outlive a fake-async test.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: app),
            // The screen's run console follows the queue and the log.
            ChangeNotifierProvider<LogState>.value(value: LogState()),
            ChangeNotifierProvider<TaskQueueService>.value(value: queue),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            // Keyed, so that a second pump mounts the screen again, the way the
            // shell does on every navigation.
            home: Scaffold(body: PromptsScreen(key: UniqueKey())),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
  }

  String? shownType(WidgetTester tester) {
    final found = find.byType(PromptTemplateTypeSegmented);
    if (found.evaluate().isEmpty) return null;
    return tester.widget<PromptTemplateTypeSegmented>(found.first).value;
  }

  test('a request is handed over once', () {
    final app = AppState()..requestSystemTemplates('refiner');
    expect(app.takeSystemTemplateRequest(), 'refiner');
    expect(app.takeSystemTemplateRequest(), isNull);
  });

  for (final (name, size) in [
    ('desktop', const Size(1440, 900)),
    ('phone', const Size(390, 800)),
  ]) {
    testWidgets('$name: a request opens the templates on that type, once', (
      tester,
    ) async {
      final app = AppState()..requestSystemTemplates('refiner');

      await pumpLibrary(tester, app, size);
      expect(shownType(tester), 'refiner');
      expect(tester.takeException(), isNull);

      // The next visit is the user's own: back on their prompts, unfiltered.
      await pumpLibrary(tester, app, size);
      expect(shownType(tester), isNot('refiner'));
    });
  }
}
