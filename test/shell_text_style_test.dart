import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';

import 'screenshots/harness/fixture_env.dart';
import 'screenshots/harness/fixture_seed.dart';
import 'screenshots/harness/shoot.dart';

/// No text in the shell may fall back to MaterialApp's error text style.
///
/// A [Text] with no [Material] above it inherits the style `MaterialApp` puts
/// in scope for exactly that mistake: red, monospace, a yellow double
/// underline. Widgets that set their own size and colour hide everything but
/// the underline. The title bar, the phone dock and the task capsule sit
/// outside every route's Scaffold, so they only have the window frame's
/// Material to inherit from; take that away and they all grow the underline
/// at once, which no layout test notices.
void main() {
  final TestWidgetsFlutterBinding binding = TestWidgetsFlutterBinding.ensureInitialized();
  late FixtureEnv env;

  setUpAll(() async {
    env = installFixtureEnv(binding);
    await seedFixtures(env);

    final AppState appState = AppState();
    await appState.loadSettings();
    await Future<void>.delayed(const Duration(seconds: 1));
  });

  tearDownAll(() => env.dispose());

  bool isErrorStyle(TextStyle? style) =>
      style != null &&
      style.decoration == TextDecoration.underline &&
      style.decorationStyle == TextDecorationStyle.double;

  List<String> underlinedTexts(WidgetTester tester) {
    final hits = <String>[];
    for (final paragraph in tester.allRenderObjects.whereType<RenderParagraph>()) {
      var underlined = false;
      paragraph.text.visitChildren((span) {
        if (span is TextSpan && isErrorStyle(span.style)) underlined = true;
        return !underlined;
      });
      if (underlined) hits.add(paragraph.text.toPlainText());
    }
    return hits;
  }

  for (final (label, size) in const [
    ('desktop', Size(1440, 900)),
    ('phone', Size(390, 844)),
  ]) {
    testWidgets('no shell text wears the missing-Material underline on $label',
        (WidgetTester tester) async {
      await mountApp(
        tester,
        env: env,
        screen: AppScreen.workbench,
        size: size,
        label: 'shell-text-$label',
      );

      // The scan below must have something to look at, or it passes for the
      // wrong reason.
      expect(tester.allRenderObjects.whereType<RenderParagraph>(), isNotEmpty);
      expect(underlinedTexts(tester), isEmpty);
    });
  }
}
