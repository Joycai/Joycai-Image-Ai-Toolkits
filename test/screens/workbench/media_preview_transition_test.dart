import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/app_image.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/preview/media_preview_dialog.dart';
import 'package:joycai_image_ai_toolkits/state/workbench_ui_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/shell/shell_cover.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

void main() {
  late Directory tempDir;
  late List<AppImage> sampleImages;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('joycai_preview_transition_');
    // Minimal valid 1x1 PNG.
    const pngBytes = <int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      0x00,
      0x00,
      0x00,
      0x0D,
      0x49,
      0x48,
      0x44,
      0x52,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x01,
      0x08,
      0x06,
      0x00,
      0x00,
      0x00,
      0x1F,
      0x15,
      0xC4,
      0x89,
      0x00,
      0x00,
      0x00,
      0x0A,
      0x49,
      0x44,
      0x41,
      0x54,
      0x78,
      0x9C,
      0x63,
      0x00,
      0x01,
      0x00,
      0x00,
      0x05,
      0x00,
      0x01,
      0x0D,
      0x0A,
      0x2D,
      0xB4,
      0x00,
      0x00,
      0x00,
      0x00,
      0x49,
      0x45,
      0x4E,
      0x44,
      0xAE,
      0x42,
      0x60,
      0x82,
    ];
    sampleImages = [];
    for (final name in ['a.png', 'b.png']) {
      final file = File(p.join(tempDir.path, name));
      await file.writeAsBytes(pngBytes);
      sampleImages.add(AppImage.fromFile(file));
    }
  });

  tearDownAll(() async {
    await tempDir.delete(recursive: true);
  });

  Future<BuildContext> mountHost(
    WidgetTester tester, {
    required WorkbenchUIState uiState,
    required ShellCoverController cover,
    String heroScope = kWorkbenchPreviewHeroScope,
    bool disableAnimations = false,
  }) async {
    late BuildContext homeContext;
    await tester.pumpWidget(
      ChangeNotifierProvider<WorkbenchUIState>.value(
        value: uiState,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) {
            final covered = ShellCover(controller: cover, child: child!);
            if (!disableAnimations) return covered;
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: covered,
            );
          },
          home: Builder(
            builder: (context) {
              homeContext = context;
              return Scaffold(
                body: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final img in sampleImages)
                        Hero(
                          tag: previewHeroTag(heroScope, img.path),
                          child: SizedBox(width: 64, height: 64, key: ValueKey(img.path)),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return homeContext;
  }

  testWidgets('rapid duplicate showMediaPreview calls only mount one preview and recover', (
    tester,
  ) async {
    final uiState = WorkbenchUIState();
    final cover = ShellCoverController();
    addTearDown(() {
      uiState.dispose();
      cover.dispose();
    });

    final context = await mountHost(tester, uiState: uiState, cover: cover);

    // Rapid duplicate open calls on the same frame and mid-transition.
    showMediaPreview(
      context,
      galleryImages: sampleImages,
      initialIndex: 0,
      heroScope: kWorkbenchPreviewHeroScope,
    );
    showMediaPreview(
      context,
      galleryImages: sampleImages,
      initialIndex: 1,
      heroScope: kWorkbenchPreviewHeroScope,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.byType(MediaPreviewDialog), findsOneWidget);

    // Pop and try re-opening while the preview is still mid-exit: the latest
    // target is queued rather than stacked, and opens once the exit finishes.
    Navigator.of(context).maybePop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    showMediaPreview(
      context,
      galleryImages: sampleImages,
      initialIndex: 1,
      heroScope: kWorkbenchPreviewHeroScope,
    );
    await tester.pump();
    expect(find.byType(MediaPreviewDialog), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byType(MediaPreviewDialog), findsOneWidget);
    expect(uiState.activePreviewIndex, 1);
    expect(find.text('b.png'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(cover.value, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(MediaPreviewDialog), findsNothing);
    expect(tester.takeException(), isNull);
    expect(cover.value, 0);
  });

  testWidgets('rapid open + immediate Esc and repeated Back taps never double-pop home route', (
    tester,
  ) async {
    final uiState = WorkbenchUIState();
    final cover = ShellCoverController();
    addTearDown(() {
      uiState.dispose();
      cover.dispose();
    });

    final context = await mountHost(tester, uiState: uiState, cover: cover);

    // Open and immediately hit Escape + ArrowRight mid-push.
    showMediaPreview(
      context,
      galleryImages: sampleImages,
      initialIndex: 0,
      heroScope: kWorkbenchPreviewHeroScope,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(find.byType(MediaPreviewDialog), findsNothing);
    expect(find.byKey(ValueKey(sampleImages.first.path)), findsOneWidget);
    expect(uiState.activePreviewIndex, 0);
    expect(tester.takeException(), isNull);
    expect(cover.value, 0);

    // Open again, settle, then rapidly tap Back twice.
    showMediaPreview(
      context,
      galleryImages: sampleImages,
      initialIndex: 0,
      heroScope: kWorkbenchPreviewHeroScope,
    );
    await tester.pumpAndSettle();
    expect(find.byType(MediaPreviewDialog), findsOneWidget);

    final backButton = find.descendant(
      of: find.byType(MediaPreviewDialog),
      matching: find.byIcon(Icons.arrow_back),
    );
    await tester.tap(backButton);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.tap(backButton, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.byType(MediaPreviewDialog), findsNothing);
    expect(find.byKey(ValueKey(sampleImages.first.path)), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(cover.value, 0);
  });

  testWidgets('mutating WorkbenchUIState preview list during exit does not disrupt Hero flight', (
    tester,
  ) async {
    final uiState = WorkbenchUIState();
    final cover = ShellCoverController();
    addTearDown(() {
      uiState.dispose();
      cover.dispose();
    });

    final context = await mountHost(tester, uiState: uiState, cover: cover);

    showMediaPreview(
      context,
      galleryImages: sampleImages,
      initialIndex: 0,
      heroScope: kWorkbenchPreviewHeroScope,
    );
    await tester.pumpAndSettle();

    Navigator.of(context).maybePop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    // External state mutation while the preview is popping must not alter its Hero tag.
    uiState.setPreviewList(sampleImages, 1);
    await tester.pumpAndSettle();

    expect(find.byType(MediaPreviewDialog), findsNothing);
    expect(tester.takeException(), isNull);
    expect(cover.value, 0);
  });

  testWidgets('external Navigator.pop blocks mid-exit navigation and thumbnail jumps', (
    tester,
  ) async {
    final uiState = WorkbenchUIState();
    final cover = ShellCoverController();
    addTearDown(() {
      uiState.dispose();
      cover.dispose();
    });

    final context = await mountHost(tester, uiState: uiState, cover: cover);

    showMediaPreview(
      context,
      galleryImages: sampleImages,
      initialIndex: 0,
      heroScope: kWorkbenchPreviewHeroScope,
    );
    await tester.pumpAndSettle();
    expect(uiState.activePreviewIndex, 0);

    // Pop via Navigator directly (bypassing _close()) and send navigation
    // inputs mid-exit.
    Navigator.of(context).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();

    expect(find.byType(MediaPreviewDialog), findsNothing);
    expect(uiState.activePreviewIndex, 0);
    expect(tester.takeException(), isNull);
    expect(cover.value, 0);
  });

  testWidgets('multiple queued reopens keep latest and pushing a dialog cancels replay', (
    tester,
  ) async {
    final uiState = WorkbenchUIState();
    final cover = ShellCoverController();
    addTearDown(() {
      uiState.dispose();
      cover.dispose();
    });

    final context = await mountHost(tester, uiState: uiState, cover: cover);

    // Part A: multiple queued showMediaPreview calls mid-exit replay only the latest.
    showMediaPreview(
      context,
      galleryImages: sampleImages,
      initialIndex: 0,
      heroScope: kWorkbenchPreviewHeroScope,
    );
    await tester.pumpAndSettle();

    Navigator.of(context).maybePop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    showMediaPreview(
      context,
      galleryImages: sampleImages,
      initialIndex: 0,
      heroScope: kWorkbenchPreviewHeroScope,
    );
    showMediaPreview(
      context,
      galleryImages: sampleImages,
      initialIndex: 1,
      heroScope: kWorkbenchPreviewHeroScope,
    );
    await tester.pumpAndSettle();

    expect(find.byType(MediaPreviewDialog), findsOneWidget);
    expect(find.text('b.png'), findsOneWidget);
    expect(uiState.activePreviewIndex, 1);
    expect(cover.value, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(MediaPreviewDialog), findsNothing);
    expect(cover.value, 0);

    // Part B: pushing another route over the opener cancels a queued reopen.
    showMediaPreview(
      context,
      galleryImages: sampleImages,
      initialIndex: 0,
      heroScope: kWorkbenchPreviewHeroScope,
    );
    await tester.pumpAndSettle();

    Navigator.of(context).maybePop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    showMediaPreview(
      context,
      galleryImages: sampleImages,
      initialIndex: 1,
      heroScope: kWorkbenchPreviewHeroScope,
    );
    showDialog<void>(
      context: context,
      builder: (_) => const AlertDialog(content: Text('Blocking dialog')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Blocking dialog'), findsOneWidget);
    expect(find.byType(MediaPreviewDialog), findsNothing);

    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    expect(find.byType(MediaPreviewDialog), findsNothing);
    expect(cover.value, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced-motion open, Esc close, and immediate reopen settle cleanly', (
    tester,
  ) async {
    final uiState = WorkbenchUIState();
    final cover = ShellCoverController();
    addTearDown(() {
      uiState.dispose();
      cover.dispose();
    });

    final context = await mountHost(
      tester,
      uiState: uiState,
      cover: cover,
      disableAnimations: true,
    );

    showMediaPreview(
      context,
      galleryImages: sampleImages,
      initialIndex: 0,
      heroScope: kWorkbenchPreviewHeroScope,
    );
    await tester.pump();
    expect(find.byType(MediaPreviewDialog), findsOneWidget);
    expect(cover.value, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    showMediaPreview(
      context,
      galleryImages: sampleImages,
      initialIndex: 1,
      heroScope: kWorkbenchPreviewHeroScope,
    );
    await tester.pumpAndSettle();

    expect(find.byType(MediaPreviewDialog), findsOneWidget);
    expect(find.text('b.png'), findsOneWidget);
    expect(uiState.activePreviewIndex, 1);
    expect(cover.value, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(MediaPreviewDialog), findsNothing);
    expect(cover.value, 0);
    expect(tester.takeException(), isNull);
  });
}
