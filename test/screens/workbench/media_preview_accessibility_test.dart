import 'dart:io';

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/app_image.dart';
import 'package:joycai_image_ai_toolkits/models/browser_file.dart';
import 'package:joycai_image_ai_toolkits/screens/browser/widgets/file_card.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/gallery/image_card_context_menu.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/preview/media_preview_dialog.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/video/video_workbench_view.dart';
import 'package:joycai_image_ai_toolkits/services/media/video_thumbnail_service.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/focus_pane.dart';
import 'package:material_ui/material_ui.dart';

import '../../screenshots/harness/fixture_env.dart';
import '../../screenshots/harness/shoot.dart';
import '../../screenshots/harness/suite.dart';

void main() {
  late FixtureEnv env;
  setUpScreenSuite((value) => env = value);
  setUpAll(() {
    VideoThumbnailService.instance.extractorOverride = (_, destination) async {
      await File(env.sourceDir.listSync().first.path).copy(destination);
      return true;
    };
  });
  tearDownAll(() => VideoThumbnailService.instance.extractorOverride = null);
  testWidgets('preview exposes named actions and semantic close restores grid focus', (
    tester,
  ) async {
    await mountApp(tester, env: env, screen: AppScreen.fileBrowser, size: const Size(1440, 900));
    final file = AppState().fileBrowserState.filteredFiles.firstWhere(
      (f) => f.category == FileCategory.image,
    );
    final card = find.byWidgetPredicate((w) => w is FileCard && w.file.path == file.path);
    await tester.tap(card);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(card);
    await settle(tester);
    final handle = tester.ensureSemantics();
    try {
      await tester.pump();
      final preview = find.byType(MediaPreviewDialog);
      final l10n = AppLocalizations.of(tester.element(preview))!;
      for (final label in [l10n.close, l10n.save, l10n.share]) {
        expect(
          find.descendant(of: preview, matching: find.bySemanticsLabel(label)),
          findsOneWidget,
        );
      }
      // Hiding the chrome must not leave a keyboard user on invisible buttons.
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await settle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await settle(tester);
      final focused = FocusManager.instance.primaryFocus!;
      final opacity = focused.context!.findAncestorWidgetOfExactType<AnimatedOpacity>();
      expect(opacity?.opacity, 1);
      final close = tester.getSemantics(
        find.descendant(of: preview, matching: find.bySemanticsLabel(l10n.close)),
      );
      tester.binding.renderViews.single.owner!.semanticsOwner!.performAction(
        close.id,
        SemanticsAction.tap,
      );
      await inRealAsync(tester, () => settle(tester));
      expect(preview, findsNothing);
      expect(
        tester
            .widgetList<FocusPane>(find.byType(FocusPane))
            .firstWhere((p) => p.node.debugLabel == 'browser-pane-grid')
            .node
            .hasPrimaryFocus,
        isTrue,
      );
    } finally {
      handle.dispose();
    }
  });
  for (final mode in ['edit', 'extend']) {
    testWidgets('video preview $mode action closes preview and preserves selected model', (
      tester,
    ) async {
      await mountApp(tester, env: env, screen: AppScreen.workbench, size: const Size(390, 844));
      final app = AppState();
      final originalModel = app.lastVideoModelId;
      final context = tester.element(find.byType(Scaffold).first);
      showMediaPreview(
        context,
        galleryImages: [
          AppImage.fromFile(File('test/support/reference_media/three_seconds.mp4').absolute),
        ],
        initialIndex: 0,
      );
      await settle(tester);
      final preview = find.byType(MediaPreviewDialog);
      final l10n = AppLocalizations.of(tester.element(preview))!;
      final label = mode == 'edit' ? l10n.menuEditVideo : l10n.menuExtendVideo;
      final handle = tester.ensureSemantics();
      final action = find.descendant(of: preview, matching: find.bySemanticsLabel(label));
      expect(action, findsOneWidget);
      expect(tester.getRect(action).right, lessThanOrEqualTo(390));
      await inRealAsyncUntil(
        tester,
        () async {
          await tester.tap(action);
        },
        until: () =>
            app.workbenchUIState.videoSourceVideoPath != null &&
            !app.workbenchUIState.videoSourceProbing,
      );
      await inRealAsync(tester, () => settle(tester));
      expect(preview, findsNothing);
      expect(app.lastVideoModelId, originalModel);
      expect(app.workbenchUIState.videoSourceVideoPath, endsWith('.mp4'));
      expect(tester.takeException(), isNull);
      handle.dispose();
      app.workbenchUIState.clearVideoSourceVideo();
    });
  }
  for (final surface in ['player', 'gallery']) {
    testWidgets('$surface action loads source without switching the paid model', (tester) async {
      final app = AppState();
      final path = File('test/support/reference_media/three_seconds.mp4').absolute.path;
      await mountApp(
        tester,
        env: env,
        screen: AppScreen.workbench,
        size: const Size(390, 844),
        before: (_) async {
          app.setWorkbenchTab(5);
          app.isConsoleExpanded = false;
          app.workbenchUIState.clearVideoSourceVideo();
          app.workbenchUIState.videoPanelHandled = app.workbenchUIState.videoPanelRequest;
          app.workbenchUIState.setLastGeneratedVideoPath(surface == 'player' ? path : null);
        },
      );
      final selected = app.lastVideoModelId;
      final context = tester.element(find.byType(Scaffold).first);
      final l10n = AppLocalizations.of(context)!;
      await inRealAsync(tester, () async {
        if (surface == 'gallery') {
          showImageCardContextMenu(
            context,
            imageFile: AppImage.fromFile(File(path)),
            position: const Offset(30, 120),
          ).ignore();
        } else {
          await tester.tap(
            find.descendant(
              of: find.byType(VideoWorkbenchOverlay),
              matching: find.byIcon(Icons.more_horiz),
            ),
          );
        }
      });
      await settle(tester);
      final label = surface == 'player' ? l10n.menuEditVideo : l10n.menuExtendVideo;
      await inRealAsyncUntil(
        tester,
        () => tester.tap(find.text(label).last),
        until: () =>
            app.workbenchUIState.videoSourceVideoPath != null &&
            !app.workbenchUIState.videoSourceProbing,
      );
      await inRealAsync(tester, () => settle(tester));
      expect(app.lastVideoModelId, selected);
      expect(app.workbenchUIState.videoSourceVideoPath, endsWith('.mp4'));
      app.workbenchUIState.setLastGeneratedVideoPath(null);
      app.workbenchUIState.clearVideoSourceVideo();
    });
  }
}
