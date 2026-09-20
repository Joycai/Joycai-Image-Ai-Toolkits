// The pop-out prompt editor (`A1d`): edit, split and the phone form, in light
// and dark.
//
//   flutter test test/screenshots/large_editor_shots_test.dart
//
// What to look for: one header, not two; no outline around the text; the text
// held to a measure with margin either side; the split's right pane set back.

@Tags(<String>['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/core/theme_accent.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/markdown_editor.dart';

const _prompt = '## 主体\n一位身着**墨绿色丝绒长裙**的年轻女性，侧身站在落地窗前，左手轻扶窗框，目光望向窗外。\n\n'
    '## 场景与镜头\n- 午后四点的斜射光，窗纱半透，地板上有长影\n- 85mm，f/2，机位略低于视线\n- 背景虚化，保留窗框的竖线\n\n'
    '## 风格与画质\n胶片质感，_Kodak Portra 400_，颗粒细腻，肤色自然。';

void main() {
  for (final brightness in Brightness.values) {
    for (final (name, size, split) in [
      ('edit', const Size(1440, 900), false),
      ('split', const Size(1440, 900), true),
      ('phone', const Size(390, 844), false),
    ]) {
      testWidgets('large editor · $name · ${brightness.name}', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildAppTheme(
            accent: ThemeAccent.fromSeed(const Color(0xFF3B6CF6)),
            brightness: brightness,
            fontFamily: 'NotoSansSC',
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 340,
                child: MarkdownEditor(
                  controller: MarkdownTextEditingController(text: _prompt),
                  label: '提示词',
                  isMarkdown: true,
                  onMarkdownChanged: (_) {},
                ),
              ),
            ),
          ),
        ));
        await tester.tap(find.byIcon(Icons.open_in_full));
        await tester.pumpAndSettle();
        if (split) {
          await tester.tap(find.text('分栏'));
          await tester.pumpAndSettle();
        }
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('large_editor_${name}_${brightness.name}.png'));
      });
    }
  }
}
