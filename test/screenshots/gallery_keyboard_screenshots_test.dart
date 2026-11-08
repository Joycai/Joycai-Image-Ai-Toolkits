@Tags(['screenshots'])
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/focus_pane.dart';

import 'harness/fixture_env.dart';
import 'harness/shoot.dart';
import 'harness/suite.dart';

void main() {
  late FixtureEnv env;
  setUpScreenSuite((value) => env = value);
  for (final locale in [
    const Locale('en'),
    const Locale('zh'),
    const Locale('ja'),
    const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ]) {
    testWidgets('gallery shortcut descriptions ${locale.toLanguageTag()}', (tester) async {
      final l10n = lookupAppLocalizations(locale);
      await shoot(
        tester,
        env: env,
        screen: AppScreen.settings,
        size: kShotSizes.first,
        locale: locale,
        suffix: 'galleryKeys_${locale.toLanguageTag()}',
        after: (tester) async {
          await tester.tap(find.text(l10n.shortcutsTitle).first);
          await settle(tester);
          await Scrollable.ensureVisible(
            tester.element(find.text(l10n.shortcutGridMove)),
            alignment: 0.2,
          );
          await settle(tester);
        },
      );
    });
  }
  for (final size in kShotSizes) {
    for (final brightness in Brightness.values) {
      testWidgets('gallery keyboard focus ${size.label} ${brightness.name}', (tester) async {
        await shoot(
          tester,
          env: env,
          screen: AppScreen.workbench,
          size: size,
          brightness: brightness,
          suffix: 'keyboardFocus',
          after: (tester) async {
            final pane = tester
                .widgetList<FocusPane>(find.byType(FocusPane))
                .firstWhere((pane) => pane.node.debugLabel == 'workbench-pane-grid');
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
