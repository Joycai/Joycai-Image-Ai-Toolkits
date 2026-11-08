import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/browser_file.dart';
import 'package:joycai_image_ai_toolkits/screens/browser/widgets/file_card.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/preview/media_preview_dialog.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/focus_pane.dart';

import '../../screenshots/harness/fixture_env.dart';
import '../../screenshots/harness/shoot.dart';
import '../../screenshots/harness/suite.dart';

void main() {
  late FixtureEnv env;
  setUpScreenSuite((value) => env = value);
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
      await settle(tester);
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
}
