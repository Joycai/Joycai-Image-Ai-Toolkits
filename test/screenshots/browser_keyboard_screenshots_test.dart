@Tags(['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/state/file_browser_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/focus_pane.dart';

import 'harness/fixture_env.dart';
import 'harness/shoot.dart';
import 'harness/suite.dart';

void main() {
  late FixtureEnv env;
  setUpScreenSuite((value) => env = value);
  for (final brightness in Brightness.values) {
    testWidgets('browser cross-pane focus ${brightness.name}', (tester) async {
      await shoot(
        tester,
        env: env,
        screen: AppScreen.fileBrowser,
        size: kShotSizes.last,
        brightness: brightness,
        suffix: 'keyboard_staging',
        before: (_) async {
          final app = AppState();
          app.fileBrowserState.setViewMode(BrowserViewMode.grid);
          app.fileStagingState.addAll(app.fileBrowserState.filteredFiles.take(2).toList());
        },
        after: (tester) async {
          final pane = tester
              .widgetList<FocusPane>(find.byType(FocusPane))
              .firstWhere((pane) => pane.node.debugLabel == 'browser-pane-grid');
          pane.node.requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.sendKeyEvent(LogicalKeyboardKey.f6);
          await settle(tester);
        },
      );
    });
  }
  for (final mode in BrowserViewMode.values) {
    for (final size in kShotSizes) {
      for (final brightness in Brightness.values) {
        testWidgets('browser focus ${mode.name} ${size.label} ${brightness.name}', (tester) async {
          await shoot(
            tester,
            env: env,
            screen: AppScreen.fileBrowser,
            size: size,
            brightness: brightness,
            suffix: 'keyboard_${mode.name}',
            before: (_) async {
              AppState().fileStagingState.clear();
              AppState().fileBrowserState.setViewMode(mode);
            },
            after: (tester) async {
              final pane = tester
                  .widgetList<FocusPane>(find.byType(FocusPane))
                  .firstWhere((pane) => pane.node.debugLabel == 'browser-pane-grid');
              pane.node.requestFocus();
              await tester.pump();
              await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
              await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
              await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
              await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
              await settle(tester);
            },
          );
        });
      }
    }
  }
  for (final locale in [
    const Locale('en'),
    const Locale('zh'),
    const Locale('ja'),
    const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ]) {
    testWidgets('pane shortcuts ${locale.toLanguageTag()}', (tester) async {
      final l10n = lookupAppLocalizations(locale);
      await shoot(
        tester,
        env: env,
        screen: AppScreen.settings,
        size: kShotSizes.first,
        locale: locale,
        suffix: 'paneKeys_${locale.toLanguageTag()}',
        after: (tester) async {
          await tester.tap(find.text(l10n.shortcutsTitle).first);
          await settle(tester);
          await Scrollable.ensureVisible(
            tester.element(find.text(l10n.shortcutNextPane)),
            alignment: .2,
          );
          await settle(tester);
        },
      );
    });
  }
}
