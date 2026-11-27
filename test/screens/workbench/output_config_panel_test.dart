import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/core/constants.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/l10n/localizations_delegates.dart';
import 'package:joycai_image_ai_toolkits/models/app_image.dart';
import 'package:joycai_image_ai_toolkits/models/image_output_config.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/workbench_config_panel.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/state/gallery_state.dart';
import 'package:joycai_image_ai_toolkits/state/workbench_ui_state.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../screenshots/harness/fixture_env.dart';
import '../../screenshots/harness/fixture_seed.dart';
import '../../support/real_async.dart';

void main() {
  final TestWidgetsFlutterBinding binding = TestWidgetsFlutterBinding.ensureInitialized();
  late FixtureEnv env;

  setUpAll(() async {
    env = installFixtureEnv(binding);
    await seedFixtures(env);
    final appState = AppState();
    await appState.loadSettings();
    await Future<void>.delayed(const Duration(seconds: 1));
  });

  tearDownAll(() => env.dispose());

  Widget wrapPanel({Brightness brightness = Brightness.light}) {
    final appState = AppState();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: appState),
        ChangeNotifierProvider<GalleryState>.value(value: appState.galleryState),
        ChangeNotifierProvider<WorkbenchUIState>.value(value: appState.workbenchUIState),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        theme: buildAppTheme(accent: AppConstants.presetThemes['Rose']!, brightness: brightness),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SizedBox(width: 340, height: 820, child: WorkbenchConfigPanel()),
        ),
      ),
    );
  }

  testWidgets('multi-output list toggles, duplicates, deletes, and updates CTA', (tester) async {
    tester.view.physicalSize = const Size(800, 960);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final appState = AppState();
    final gpt = appState.imageModels.firstWhere((m) => m.modelId == 'gpt-image-2.6-flare');
    final gemini = appState.imageModels.firstWhere((m) => m.modelId == 'gemini-nano-banana-2.1');

    appState.clearImageSelection();
    await inRealAsync(tester, () => appState.updateWorkbenchConfig(prompt: 'Test multi output'));
    appState.setImageOutputConfigsForTest([
      ImageOutputConfig(
        id: 'cfg_1',
        modelDbId: gpt.id,
        modelIdFallback: gpt.modelId,
        alias: '主图',
        params: const {'size': '1024x1536', 'quality': 'high'},
      ),
      ImageOutputConfig(
        id: 'cfg_2',
        modelDbId: gemini.id,
        modelIdFallback: gemini.modelId,
        enabled: false,
        alias: '备选',
      ),
    ]);

    await pumpWidgetInRealAsync(tester, wrapPanel());
    await tester.pumpAndSettle();

    expect(find.text('1/2 已启用'), findsOneWidget);
    expect(find.text('处理提示词'), findsOneWidget);

    // Enable second config -> CTA updates to multi-output count.
    await tester.ensureVisible(find.byType(Switch).last);
    await inRealAsync(tester, () async {
      await tester.tap(find.byType(Switch).last);
    });
    await tester.pumpAndSettle();
    expect(find.text('2/2 已启用'), findsOneWidget);
    expect(find.text('处理提示词 · 2 项输出'), findsOneWidget);

    // Duplicate first config -> 3/3 enabled.
    await tester.ensureVisible(find.byIcon(Icons.content_copy_outlined).first);
    await inRealAsync(tester, () async {
      await tester.tap(find.byIcon(Icons.content_copy_outlined).first);
    });
    await tester.pumpAndSettle();
    expect(find.text('3/3 已启用'), findsOneWidget);

    // Delete all configs -> empty state & disabled CTA.
    for (int i = 0; i < 3; i++) {
      await tester.ensureVisible(find.byIcon(Icons.delete_outline).first);
      await inRealAsync(tester, () async {
        await tester.tap(find.byIcon(Icons.delete_outline).first);
      });
      await tester.pumpAndSettle();
    }
    expect(find.text('暂无输出配置'), findsOneWidget);
    expect(find.text('请先添加输出配置'), findsOneWidget);
  });

  testWidgets('output config dialog edits alias and parameters cleanly', (tester) async {
    tester.view.physicalSize = const Size(800, 960);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final appState = AppState();
    final gpt = appState.imageModels.firstWhere((m) => m.modelId == 'gpt-image-2.6-flare');
    final initial = ImageOutputConfig(
      id: 'cfg_edit',
      modelDbId: gpt.id,
      modelIdFallback: gpt.modelId,
      alias: '旧别名',
    );
    appState.setImageOutputConfigsForTest([initial]);

    await pumpWidgetInRealAsync(tester, wrapPanel());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.tune_outlined).first);
    await tester.pumpAndSettle();

    expect(find.text('编辑输出'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '新别名');
    await tester.pump();

    await inRealAsync(tester, () => tester.tap(find.text('保存')));
    await tester.pumpAndSettle();

    expect(appState.imageOutputConfigs.single.alias, '新别名');
  });

  testWidgets('per-config reference warning appears only on incompatible output rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 960);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final appState = AppState();
    final gpt = appState.imageModels.firstWhere((m) => m.modelId == 'gpt-image-2.6-flare');
    final imagen = appState.imageModels.where((m) => m.modelId.contains('imagen')).firstOrNull;
    if (imagen == null) return;

    appState.clearImageSelection();
    appState.toggleImageSelection(AppImage(path: env.sourceDir.path, name: 'ref.png'));
    appState.setImageOutputConfigsForTest([
      ImageOutputConfig(id: 'compat', modelDbId: gpt.id, modelIdFallback: gpt.modelId),
      ImageOutputConfig(id: 'incompat', modelDbId: imagen.id, modelIdFallback: imagen.modelId),
    ]);

    await pumpWidgetInRealAsync(tester, wrapPanel());
    await tester.pumpAndSettle();

    expect(find.text('该模型不支持参考图，所选图片将被忽略。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('generation settings dialog hosts relocated streaming and compress toggles', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 960);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final appState = AppState();
    await inRealAsync(
      tester,
      () => appState.updateWorkbenchConfig(useStream: true, compressReferenceImages: false),
    );

    await pumpWidgetInRealAsync(tester, wrapPanel(brightness: Brightness.dark));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('生成设置'));
    await tester.pumpAndSettle();

    expect(find.text('请求与传输'), findsOneWidget);
    expect(find.text('使用流式传输'), findsOneWidget);
    expect(find.text('压缩参考图'), findsOneWidget);

    final streamSwitch = find.descendant(
      of: find.byKey(const ValueKey('use_stream_row')),
      matching: find.byType(Switch),
    );
    final compressSwitch = find.descendant(
      of: find.byKey(const ValueKey('compress_reference_images_row')),
      matching: find.byType(Switch),
    );

    await inRealAsync(tester, () async {
      await tester.tap(streamSwitch);
      await tester.tap(compressSwitch);
    });
    await tester.pumpAndSettle();

    expect(appState.useStream, isFalse);
    expect(appState.compressReferenceImages, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('submitImageOutputs validates all enabled configs before queueing', (tester) async {
    final appState = AppState();
    final gpt = appState.imageModels.firstWhere((m) => m.modelId == 'gpt-image-2.6-flare');
    final initialCount = appState.taskQueue.queue.length;

    appState.clearImageSelection();
    appState.setImageOutputConfigsForTest([
      ImageOutputConfig(
        id: 'ok_cfg',
        modelDbId: gpt.id,
        modelIdFallback: gpt.modelId,
        enabled: true,
      ),
      ImageOutputConfig(
        id: 'bad_cfg',
        modelDbId: gpt.id,
        modelIdFallback: gpt.modelId,
        enabled: true,
        params: const {'background': 'transparent', 'outputFormat': 'jpeg'},
      ),
      ImageOutputConfig(
        id: 'disabled_bad_cfg',
        modelDbId: gpt.id,
        modelIdFallback: gpt.modelId,
        enabled: false,
        params: const {'background': 'transparent', 'outputFormat': 'jpeg'},
      ),
    ]);

    late final dynamic res;
    await runAsyncRethrowing(tester, () async {
      res = await appState.submitImageOutputs(prompt: 'test validation');
    });

    expect(res.submitted, 0);
    expect(res.failure, isNotNull);
    expect(res.failure.diagnostic.code, 'transparentJpeg');
    expect(appState.taskQueue.queue.length, initialCount);

    // Disable bad_cfg, keeping only ok_cfg enabled; verify disabled_bad_cfg is skipped.
    appState.setImageOutputConfigsForTest([
      appState.imageOutputConfigs[0],
      appState.imageOutputConfigs[1].copyWith(enabled: false),
      appState.imageOutputConfigs[2],
    ]);

    late final dynamic okRes;
    await runAsyncRethrowing(tester, () async {
      okRes = await appState.submitImageOutputs(prompt: 'test valid submit');
    });
    expect(okRes.failure, isNull);
    expect(okRes.submitted, 1);
    expect(appState.taskQueue.queue.length, initialCount + 1);
  });
}
