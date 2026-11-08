import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/app_image.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/gallery.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/gallery/image_card.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/preview/media_preview_dialog.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/state/gallery_state.dart';
import 'package:provider/provider.dart';

import '../../screenshots/harness/fixture_env.dart';
import '../../support/real_async.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late FixtureEnv env;
  setUpAll(() => env = installFixtureEnv(binding));
  useRealAsyncAppState();
  tearDownAll(() => env.dispose());

  Future<GalleryState> mount(WidgetTester tester) async {
    final app = AppState();
    final state = app.galleryState
      ..clearDroppedImages()
      ..clearImageSelection()
      ..setViewMode(GalleryViewMode.temp)
      ..addDroppedFiles([
        for (var i = 0; i < 40; i++) AppImage(path: '/nowhere/$i.png', name: '$i.png'),
      ]);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: app),
          ChangeNotifierProvider.value(value: state),
          ChangeNotifierProvider.value(value: app.workbenchUIState),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Column(
              children: [
                TextField(),
                Expanded(child: Gallery()),
                TextButton(onPressed: null, child: Text('End')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return state;
  }

  Future<void> press(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    LogicalKeyboardKey? modifier,
  }) async {
    if (modifier != null) await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(key);
    if (modifier != null) await tester.sendKeyUpEvent(modifier);
    await tester.pumpAndSettle();
  }

  testWidgets('Tab enters once; arrows, contracting ranges and focus-only moves are distinct', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final state = await mount(tester);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(state.selectedImages, isEmpty, reason: 'editing never changes the grid selection');
      await press(tester, LogicalKeyboardKey.tab);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'workbench-pane-grid');
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(state.selectedImages.map((i) => i.name), ['1.png']);
      await press(tester, LogicalKeyboardKey.arrowRight, modifier: LogicalKeyboardKey.shiftLeft);
      expect(state.selectedImages.map((i) => i.name), ['1.png', '2.png']);
      await press(tester, LogicalKeyboardKey.arrowLeft, modifier: LogicalKeyboardKey.shiftLeft);
      expect(state.selectedImages.map((i) => i.name), ['1.png']);
      await press(
        tester,
        LogicalKeyboardKey.arrowRight,
        modifier: Platform.isMacOS ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft,
      );
      expect(state.selectedImages.map((i) => i.name), ['1.png']);
      final focused = tester.getSemantics(find.bySemanticsLabel('2.png').first).getSemanticsData();
      expect(focused.flagsCollection.isFocused, Tristate.isTrue);
      await press(tester, LogicalKeyboardKey.space);
      expect(state.selectedImages.map((i) => i.name), ['1.png', '2.png']);
      await press(tester, LogicalKeyboardKey.tab);
      expect(FocusManager.instance.primaryFocus?.debugLabel, isNot('workbench-pane-grid'));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('offscreen navigation scrolls and deletion leaves a usable adjacent cursor', (
    tester,
  ) async {
    final state = await mount(tester);
    for (var i = 0; i < 10; i++) {
      await press(tester, LogicalKeyboardKey.arrowDown);
    }
    final scroll = tester.widget<CustomScrollView>(find.byType(CustomScrollView)).controller!;
    expect(scroll.offset, greaterThan(0));
    final deleted = state.selectedImages.single.path;
    await press(tester, LogicalKeyboardKey.delete);
    expect(state.currentViewImages.any((i) => i.path == deleted), isFalse);
    await press(tester, LogicalKeyboardKey.space);
    expect(state.selectedImages, hasLength(1));
    expect(state.selectedImages.single.path, isNot(deleted));
    state.clearDroppedImages();
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(state.selectedImages, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('preview returns to the cursor; resize preserves identity; held arrows move', (
    tester,
  ) async {
    final state = await mount(tester);
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.enter);
    expect(find.byType(MediaPreviewDialog), findsOneWidget);
    await press(tester, LogicalKeyboardKey.escape);
    expect(find.byType(MediaPreviewDialog), findsNothing);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'workbench-pane-grid');
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.space);
    expect(state.selectedImages, isEmpty, reason: 'resize keeps the selected active item');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(state.selectedImages.map((i) => i.name), ['3.png']);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('mouse double-click returns keyboard focus to its source item', (tester) async {
    final state = await mount(tester);
    final card = find.byType(ImageCard).at(2);
    await tester.tap(card);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.byType(MediaPreviewDialog), findsOneWidget);
    await press(tester, LogicalKeyboardKey.escape);
    await press(tester, LogicalKeyboardKey.space);
    expect(state.selectedImages.map((i) => i.name), ['2.png']);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
