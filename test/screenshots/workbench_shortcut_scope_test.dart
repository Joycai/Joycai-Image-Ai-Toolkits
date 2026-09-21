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

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/app_image.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/image_card.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/workbench_glass_toolbar.dart';
import 'package:joycai_image_ai_toolkits/services/files/trash_service.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/state/gallery_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/glass/glass_controls.dart';
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

  /// Shift+click, with the modifier still down when the tap actually lands.
  ///
  /// A card carries a double-tap recognizer, so its `onTap` fires only after
  /// the double-tap window closes (~300ms) — release Shift on the next line
  /// and the click resolves as a plain one. The app reads the modifier at
  /// `onTap` time, so a real user has to keep Shift down for that beat too.
  Future<void> shiftClick(WidgetTester tester, Finder card) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(card);
    await settle(tester);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await settle(tester);
  }

  /// [real] runs the chord through [actInRealAsync], which the keys that
  /// reach the database need — the ones that persist a setting, and the ones
  /// that bring a panel on screen which loads its prompts on mount. Either
  /// starts sqflite's ten-second lock watchdog, and under fake async that is
  /// a timer still pending when the test ends — and a pending timer fails a
  /// `testWidgets` on something other than its subject.
  Future<void> pressChord(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool shift = false,
    bool alt = false,
    bool real = false,
  }) async {
    Future<void> send() async {
      await tester.sendKeyDownEvent(primary);
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(key);
      if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(primary);
    }

    if (real) {
      await actInRealAsync(tester, send);
    } else {
      await send();
      await settle(tester);
    }
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

  testWidgets('the screen-level keys: refresh, the two columns, the tools',
      (WidgetTester tester) async {
    final appState = AppState();
    await mountGallery(tester, 'workbench-screen-keys');
    addTearDown(() {
      appState.setSidebarExpanded(true);
      appState.setConfigPanelExpanded(true);
      appState.setWorkbenchTab(0);
    });

    // `⌘\` — the folder column, the same app-level preference the browser
    // and the toolbar button drive.
    expect(appState.isSidebarExpanded, isTrue);
    await pressChord(tester, LogicalKeyboardKey.backslash, real: true);
    expect(appState.isSidebarExpanded, isFalse);
    await pressChord(tester, LogicalKeyboardKey.backslash, real: true);
    expect(appState.isSidebarExpanded, isTrue);

    // `⇧⌘\` — the parameter column, and a visible way back once it is gone.
    expect(appState.isConfigPanelExpanded, isTrue);
    await pressChord(tester, LogicalKeyboardKey.backslash, shift: true, real: true);
    expect(appState.isConfigPanelExpanded, isFalse);
    expect(find.byIcon(Icons.tune), findsOneWidget,
        reason: 'the toolbar offers the column back');

    await actInRealAsync(tester, () => tester.tap(find.byIcon(Icons.tune)));
    expect(appState.isConfigPanelExpanded, isTrue);

    // `⌘⌥1…4` — the tools, in `WorkbenchTab` order. The fifth (the
    // assistant) is left out of this loop on purpose: arriving there starts
    // a knowledge-base re-check whose timers outlive the test, and a pending
    // timer fails a `testWidgets` on something other than its subject. The
    // registry's fifth chord is covered by `app_shortcuts_test`.
    for (final (index, key) in <LogicalKeyboardKey>[
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
    ].indexed) {
      await pressChord(tester, key, alt: true, real: true);
      expect(appState.workbenchTabIndex, index,
          reason: 'Cmd+Alt+${index + 1} is tool $index');
    }

    await actInRealAsync(tester, () async => appState.setWorkbenchTab(0));
  });

  testWidgets('the way back to the parameter column is offered only where '
      'there is a column', (WidgetTester tester) async {
    final appState = AppState();
    await mountGallery(tester, 'workbench-tune-scope');
    addTearDown(() {
      appState.setConfigPanelExpanded(true);
      appState.setWorkbenchTab(0);
    });

    // `⇧⌘\` collapses the column app-wide, so the toolbar owes the user a
    // visible way back — on the tabs that have one.
    await pressChord(tester, LogicalKeyboardKey.backslash, shift: true, real: true);
    expect(appState.isConfigPanelExpanded, isFalse);
    expect(find.byIcon(Icons.tune), findsOneWidget);

    // The mask editor has no parameter column at all (`hasRightPanel: false`),
    // so there is nothing to offer back. Without the `canShowRightPanel`
    // guard the button appeared here too and did nothing visible: it set the
    // preference, removed itself, and left the screen exactly as it was.
    await pressChord(tester, LogicalKeyboardKey.digit3, alt: true, real: true);
    expect(appState.workbenchTabIndex, 2, reason: 'the mask editor');
    expect(appState.isConfigPanelExpanded, isFalse, reason: 'still collapsed');
    expect(find.byIcon(Icons.tune), findsNothing,
        reason: 'a button that would bring back a column this tab does not '
            'have is a button that does nothing');

    // Back on the gallery it is owed again.
    await pressChord(tester, LogicalKeyboardKey.digit1, alt: true, real: true);
    expect(appState.workbenchTabIndex, 0);
    expect(find.byIcon(Icons.tune), findsOneWidget);
  });

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

    await shiftClick(tester, cards.at(2));

    expect(gallery.selectedImages, hasLength(3),
        reason: 'the span between the two clicks — all three — joins the '
            'selection, not just the card that was clicked');
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

  testWidgets('the menu row and the key it advertises act on the same files',
      (WidgetTester tester) async {
    // A row that carries a key's badge and then acts on one file while the
    // key acts on five is the drift the round exists to remove — the browser's
    // menu was given `targets` for exactly this reason, and the gallery's was
    // left behind.
    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
    final gallery = await mountGallery(tester, 'workbench-menu-targets');

    final cards = find.byType(ImageCard);
    await tester.tap(cards.at(0));
    await settle(tester);
    await shiftClick(tester, cards.at(2));
    expect(gallery.selectedImages, hasLength(3));

    // Right-click a card that is part of that selection.
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(cards.at(1)),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await gesture.up();
    await settle(tester, 12);

    expect(find.text(l10n.deleteFiles(3)), findsOneWidget,
        reason: 'the row names the selection it would delete, like the key '
            'that is badged beside it');
    expect(find.text(l10n.delete), findsNothing,
        reason: 'and never the bare singular while three are picked');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester, 12);
    gallery.clearImageSelection();
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

  testWidgets('the keys read the view the grid is showing, not the source list',
      (WidgetTester tester) async {
    // The regression this pins: the range and the preview used to look their
    // ends up in `galleryImages` — the aggregate behind the *all* view — so
    // in the temporary workspace neither end was found and Shift+click
    // silently became a plain click.
    final gallery = AppState().galleryState;
    gallery.clearImageSelection();
    gallery.clearDroppedImages();

    final sources = Directory(env.browserDir.path)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.png'))
        .take(3)
        .map((f) => AppImage.fromFile(f))
        .toList();
    expect(sources, hasLength(3));
    gallery.addDroppedFiles(sources);
    gallery.setViewMode(GalleryViewMode.temp);

    await mountApp(
      tester,
      env: env,
      screen: AppScreen.workbench,
      size: const Size(1440, 900),
      label: 'workbench-view-scoped-keys',
    );

    final cards = find.byType(ImageCard);
    expect(cards, findsNWidgets(3));

    await tester.tap(cards.at(0));
    await settle(tester);
    await shiftClick(tester, cards.at(2));

    expect(gallery.selectedImages, hasLength(3),
        reason: 'the span is the three pictures in the basket');

    // …and select-all takes the basket, not the source aggregate behind it.
    gallery.clearImageSelection();
    await settle(tester);
    await pressChord(tester, LogicalKeyboardKey.keyA);
    expect(gallery.selectedImages, hasLength(3));

    gallery.clearImageSelection();
    gallery.clearDroppedImages();
    gallery.setViewMode(GalleryViewMode.all);
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

  testWidgets('a key with nothing to act on changes nothing, here or later',
      (WidgetTester tester) async {
    final appState = AppState();
    await mountGallery(tester, 'workbench-config-key-scope');
    addTearDown(() {
      appState.setConfigPanelExpanded(true);
      appState.setWorkbenchTab(0);
    });

    // The mask editor has no parameter column (`hasRightPanel: false`), so
    // `⇧⌘\` has nothing to show or hide here. It used to fall through to the
    // preference anyway — a *persisted* one, and one nothing on this tab
    // reflects, so the press looked like a dead key and the gallery's column
    // was gone next time the user went back to it, with no press to blame.
    await pressChord(tester, LogicalKeyboardKey.digit3, alt: true, real: true);
    expect(appState.workbenchTabIndex, 2, reason: 'the mask editor');
    expect(appState.isConfigPanelExpanded, isTrue);

    await pressChord(tester, LogicalKeyboardKey.backslash, shift: true, real: true);
    expect(appState.isConfigPanelExpanded, isTrue,
        reason: 'a tab with no column must not move the column preference');

    // And the proof that it did not move is on the tab that has one.
    await pressChord(tester, LogicalKeyboardKey.digit1, alt: true, real: true);
    expect(appState.workbenchTabIndex, 0);
    expect(find.byIcon(Icons.tune), findsNothing,
        reason: 'the column is still there, so nothing is offering it back');
  });

  testWidgets('the way back opens the column where the column is a drawer',
      (WidgetTester tester) async {
    final appState = AppState();
    final gallery = AppState().galleryState;
    gallery.clearImageSelection();
    gallery.setViewMode(GalleryViewMode.all);

    // Collapsed on a wide window, then narrowed: the preference governs the
    // *inline* column, and at tablet width there is no inline column to
    // govern — the panel is a drawer. Reaching for the preference first left
    // the button expanding something invisible and opening nothing, so the
    // first press did nothing at all and the panel arrived on the second.
    // Registered before the state is touched: a tearDown that only exists
    // after the mutation succeeded is no tearDown at all.
    addTearDown(() {
      appState.setConfigPanelExpanded(true);
      appState.setWorkbenchTab(0);
    });
    await tester.runAsync(() async {
      appState.setConfigPanelExpanded(false);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });

    await mountApp(
      tester,
      env: env,
      screen: AppScreen.workbench,
      size: const Size(900, 800),
      label: 'workbench-tune-drawer',
    );

    expect(find.byIcon(Icons.tune), findsOneWidget,
        reason: 'a drawer always owes the user a button that opens it');
    expect(find.byType(Drawer), findsNothing,
        reason: 'a dismissed drawer builds no content');

    await actInRealAsync(tester, () => tester.tap(find.byIcon(Icons.tune)));

    expect(find.byType(Drawer), findsOneWidget,
        reason: 'one press, one panel — not a silent preference and a second '
            'press to actually see it');
  });

  testWidgets('Cmd+Alt+1 goes to the gallery you were last in',
      (WidgetTester tester) async {
    final appState = AppState();
    await mountGallery(tester, 'workbench-gallery-key-target');
    addTearDown(() {
      appState.setWorkbenchTab(0);
    });

    // 画廊 is two tabs, and the strip's 画廊 item has always returned to
    // whichever was open last. The key stands for that item, so jumping to
    // `image` outright dropped a video session into image mode — the mode
    // segment flipped and the video parameters went with it — for pressing
    // "go to the gallery".
    await actInRealAsync(tester, () async => appState.setWorkbenchTab(WorkbenchTab.video));
    expect(appState.workbenchTabIndex, WorkbenchTab.video);

    await pressChord(tester, LogicalKeyboardKey.digit2, alt: true, real: true);
    expect(appState.workbenchTabIndex, WorkbenchTab.comparator);

    await pressChord(tester, LogicalKeyboardKey.digit1, alt: true, real: true);
    expect(appState.workbenchTabIndex, WorkbenchTab.video,
        reason: 'back to the gallery means back to the one you left');
  });

  testWidgets('the selection bar empties the basket in one pass',
      (WidgetTester tester) async {
    final gallery = AppState().galleryState;
    gallery.clearImageSelection();
    gallery.clearDroppedImages();
    addTearDown(() {
      gallery.clearDroppedImages();
      gallery.setViewMode(GalleryViewMode.all);
    });

    final sources = Directory(env.browserDir.path)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.png'))
        .take(3)
        .map((f) => AppImage.fromFile(f))
        .toList();
    expect(sources, hasLength(3), reason: 'the fixture must have three pictures');
    gallery.addDroppedFiles(sources);
    gallery.setViewMode(GalleryViewMode.temp);

    await mountApp(
      tester,
      env: env,
      screen: AppScreen.workbench,
      size: const Size(1440, 900),
      label: 'workbench-basket-batch',
    );

    gallery.selectAllImages();
    await settle(tester);
    expect(gallery.selectedImages, hasLength(3));

    // One press, one pass. The bar used to call the single-image removal
    // once per picture, and each call re-filtered the basket, re-validated
    // the selection against all four collections and rebuilt the grid — the
    // very cost `removeDroppedImages` was added for, left behind at the one
    // call site nobody migrated.
    int notifications = 0;
    void count() => notifications++;
    gallery.addListener(count);
    addTearDown(() => gallery.removeListener(count));

    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
    // The bar labels its buttons when it fits and falls back to tooltips
    // when it does not, and which one it is is not this test's subject.
    await tester.tap(find.byWidgetPredicate((w) =>
        w is GlassIconButton &&
        (w.label == l10n.removeFromWorkspace ||
            w.tooltip == l10n.removeFromWorkspace)));
    await settle(tester);

    expect(gallery.droppedImages, isEmpty);
    expect(notifications, 1,
        reason: 'three pictures, one notification — not one rebuild each');
  });
}
