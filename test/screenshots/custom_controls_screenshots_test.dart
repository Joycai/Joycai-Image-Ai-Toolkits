@Tags(<String>['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/widgets/glass/glass_controls.dart';

import 'harness/fixture_env.dart';
import 'harness/shoot.dart';
import 'harness/suite.dart';

void main() {
  late FixtureEnv env;
  setUpScreenSuite((e) => env = e);
  for (final screen in [
    AppScreen.workbench,
    AppScreen.fileBrowser,
    AppScreen.settings,
    AppScreen.models,
    AppScreen.prompts,
  ]) {
    for (final size in kShotSizes) {
      for (final brightness in Brightness.values) {
        testWidgets('custom controls ${screen.name} ${size.label} ${brightness.name}', (
          tester,
        ) async {
          final strategy = FocusManager.instance.highlightStrategy;
          FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
          addTearDown(() => FocusManager.instance.highlightStrategy = strategy);
          await shoot(
            tester,
            env: env,
            screen: screen,
            size: size,
            brightness: brightness,
            suffix: 'customAudit',
            after: (tester) async {
              if (screen == AppScreen.workbench) {
                await tester.sendKeyEvent(LogicalKeyboardKey.tab);
                final detector = tester.widget<FocusableActionDetector>(
                  find
                      .descendant(
                        of: find.byType(GlassIconButton).hitTestable().first,
                        matching: find.byType(FocusableActionDetector),
                      )
                      .first,
                );
                detector.focusNode!.requestFocus();
                await settle(tester);
                expect(detector.focusNode!.hasPrimaryFocus, isTrue);
                expect(
                  tester
                      .widgetList<DecoratedBox>(
                        find.descendant(
                          of: find.byType(GlassIconButton).hitTestable().first,
                          matching: find.byType(DecoratedBox),
                        ),
                      )
                      .any(
                        (box) =>
                            box.position == DecorationPosition.foreground &&
                            (box.decoration as BoxDecoration).border != null,
                      ),
                  isTrue,
                );
              }
            },
          );
        });
      }
    }
  }
}
