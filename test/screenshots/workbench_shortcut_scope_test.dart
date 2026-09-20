// The workbench gallery answering the same keys the file browser does.
//
//   flutter test test/screenshots/workbench_shortcut_scope_test.dart
//
// Beside the screenshot harness because it needs the real app tree: what is
// under test is where a key lands after travelling up the screen's actual
// focus chain. Asserts, so it stays in the gate and is not tagged
// `screenshots`.
//
// The point of the round is that one key means one thing on both screens.
// These are the browser's cases, run against the gallery — plus the one
// deliberate exception, `Delete` in the temporary workspace (plan D2).

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:joycai_image_ai_toolkits/models/app_image.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/image_card.dart';
import 'package:joycai_image_ai_toolkits/services/files/trash_service.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/state/gallery_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/dialogs/file_rename_dialog.dart';
import 'package:joycai_image_ai_toolkits/widgets/files/transfer_dialog_parts.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_dialog.dart';

import 'harness/fixture_env.dart';
import 'harness/fixture_seed.dart';
import 'harness/shoot.dart';
import 'harness/suite.dart';

void main() {
  final TestWidgetsFlutterBinding binding = TestWidgetsFlutterBinding.ensureInitialized();
  late FixtureEnv env;

  setUpAll(() async {
    TrashService.overrideSupport(true);
    env = installFixtureEnv(binding);
    await seedFixtures(env);
    await AppState().loadSettings();
    await Future<void>.delayed(const Duration(seconds: 1));
  });

  tearDownAll(() {
    TrashService.overrideSupport(null);
    env.dispose();
  });

  final LogicalKeyboardKey primary =
      Platform.isMacOS ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;

  Future<void> pressChord(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(primary);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(primary);
    await settle(tester);
  }

  /// A workbench with a clean gallery selection, on the source view.
  Future<GalleryState> mountGallery(WidgetTester tester, String label) async {
    final gallery = AppState().galleryState;
    gallery.clearImageSelection();
    gallery.setViewMode(GalleryViewMode.all);
    await mountApp(
      tester,
      env: env,
      screen: AppScreen.workbench,
      size: const Size(1440, 900),
      label: label,
    );
    expect(find.byType(ImageCard), findsWidgets);
    return gallery;
  }

  testWidgets('Cmd+A selects the gallery, Escape clears it', (WidgetTester tester) async {
    final gallery = await mountGallery(tester, 'workbench-select-all');

    // No click first: the gallery is the screen's active region from the
    // start, so the keys work on a freshly opened screen.
    await pressChord(tester, LogicalKeyboardKey.keyA);
    expect(gallery.selectedImages, isNotEmpty);
    expect(
      gallery.selectedImages.length,
      gallery.galleryImages.where((i) => !i.path.endsWith('.mp4')).length,
      reason: 'select-all takes everything the grid is showing but the videos',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(gallery.selectedImages, isEmpty);
  });

  testWidgets('Shift+click extends the selection from the last plain click',
      (WidgetTester tester) async {
    final gallery = await mountGallery(tester, 'workbench-shift-click');

    final cards = find.byType(ImageCard);
    await tester.tap(cards.at(0));
    await settle(tester);
    expect(gallery.selectedImages, hasLength(1));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(cards.at(2));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await settle(tester);

    expect(gallery.selectedImages.length, greaterThan(1),
        reason: 'the span between the two clicks joins the selection');
    final paths = gallery.selectedImages.map((i) => i.path).toList();
    expect(paths.toSet(), hasLength(paths.length), reason: 'no duplicates');
  });

  testWidgets('F2 renames the one selected picture', (WidgetTester tester) async {
    final gallery = await mountGallery(tester, 'workbench-rename');

    await tester.tap(find.byType(ImageCard).first);
    await settle(tester);
    expect(gallery.selectedImages, hasLength(1));

    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await settle(tester, 12);
    expect(find.byType(FileRenameDialog), findsOneWidget);
  });

  testWidgets('Delete opens the shared confirmation outside the temp workspace',
      (WidgetTester tester) async {
    await mountGallery(tester, 'workbench-delete-key');

    await tester.tap(find.byType(ImageCard).first);
    await settle(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await settle(tester);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await settle(tester, 12);

    expect(find.byType(AppDialog), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppDialog),
        matching: find.byType(TransferDialogHeading),
      ),
      findsOneWidget,
      reason: 'the same dialog the file browser opens — one key, one meaning',
    );
  });

  testWidgets('Delete in the temporary workspace takes the picture out of the basket, '
      'and asks nothing', (WidgetTester tester) async {
    final gallery = AppState().galleryState;
    gallery.clearImageSelection();
    gallery.clearDroppedImages();

    // Two real files from the fixture, put in the basket.
    final sources = Directory(env.browserDir.path)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.png'))
        .take(2)
        .map((f) => AppImage.fromFile(f))
        .toList();
    expect(sources, hasLength(2), reason: 'the fixture must have two pictures');
    gallery.addDroppedFiles(sources);
    gallery.setViewMode(GalleryViewMode.temp);

    await mountApp(
      tester,
      env: env,
      screen: AppScreen.workbench,
      size: const Size(1440, 900),
      label: 'workbench-delete-temp',
    );
    expect(find.byType(ImageCard), findsWidgets);

    await tester.tap(find.byType(ImageCard).first);
    await settle(tester);
    final AppImage picked = gallery.selectedImages.single;

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await settle(tester, 12);

    // D2, the one key in this round that means two things: in the basket it
    // takes things out, which costs nothing and needs no confirmation.
    expect(find.byType(AppDialog), findsNothing,
        reason: 'removing from the workspace is lossless, so nothing to confirm');
    expect(gallery.droppedImages.map((i) => i.path), isNot(contains(picked.path)));
    expect(File(picked.path).existsSync(), isTrue,
        reason: 'and the file on disk is untouched — that is the whole '
            'difference between the two meanings');

    gallery.clearDroppedImages();
    gallery.setViewMode(GalleryViewMode.all);
  });
}
