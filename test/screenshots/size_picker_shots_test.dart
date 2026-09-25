// The `A1c` size picker, frame by frame, the way the design sheet lays them
// out: the entry field's states (30a), the popover on wan2.7-image-pro (30b),
// qwen across the 1K → 2K billing line (30c), gpt-image-2 (30d), a ratio no
// size satisfies (30e) and an illegal typed size (30f) — in light and dark.
//
//   flutter test test/screenshots/size_picker_shots_test.dart
//
// What to look for: every frame is the same control; the rule line loses the
// edge rule on qwen / wan; the error ink appears only on what blocks; the
// billing tag exists only where a rate table does.

@Tags(<String>['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/core/design_tokens.dart';
import 'package:joycai_image_ai_toolkits/core/theme_accent.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/spec_rate.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/size_picker/size_field.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/size_picker/size_picker_panel.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_capabilities.dart';
import 'package:joycai_image_ai_toolkits/widgets/glass/app_glass.dart';

void main() {
  ParamSpec sizeSpec(String modelId) =>
      ModelCapabilities.forModel(modelId).imageParams.firstWhere((p) => p.key == 'imageSize');

  const rates = [
    SpecRate(size: '1K', price: 0.2),
    SpecRate(size: '2K', price: 0.4),
    SpecRate(size: '4K', price: 0.8),
  ];

  Widget popover(Key key, String modelId, String value, {List<SpecRate>? rates}) => Builder(
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return SizedBox(
        width: 340,
        child: AppGlass(
          grade: GlassGrade.float,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          padding: const EdgeInsets.all(AppSpace.s6),
          child: Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: SizePickerPanel(
              key: key,
              spec: sizeSpec(modelId),
              value: value,
              modelName: modelId,
              rates: rates,
              onChanged: (_) {},
              onClose: () {},
            ),
          ),
        ),
      );
    },
  );

  Widget field(String modelId, String value, {String? stored}) => SizedBox(
    width: 268,
    child: SizeField(
      spec: sizeSpec(modelId),
      value: value,
      modelName: modelId,
      storedValue: stored,
      onChanged: (_) {},
    ),
  );

  for (final brightness in Brightness.values) {
    testWidgets('size picker · ${brightness.name}', (tester) async {
      tester.view.physicalSize = const Size(1480, 1500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final wanPro = GlobalKey();
      final qwen = GlobalKey();
      final gpt = GlobalKey();
      final bad = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
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
            body: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: brightness == Brightness.light
                      ? const [Color(0xFFE9E4DA), Color(0xFFD5DEEA)]
                      : const [Color(0xFF26241F), Color(0xFF1B2230)],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 16,
                      runSpacing: 10,
                      children: [
                        field('gpt-image-2', 'auto'),
                        field('qwen-image-3.0', 'not_set'),
                        field('wan2.7-image', 'not_set'),
                        field('wan2.7-image-pro', '2K'),
                        field('wan2.7-image-pro', '2688x1536'),
                        field('wan2.7-image', 'not_set', stored: '3840x2160'),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        popover(wanPro, 'wan2.7-image-pro', '4096x2304', rates: rates),
                        const SizedBox(width: 20),
                        popover(qwen, 'qwen-image-3.0', '1024x1024', rates: rates),
                        const SizedBox(width: 20),
                        popover(gpt, 'gpt-image-2', '3840x2160'),
                        const SizedBox(width: 20),
                        popover(bad, 'wan2.7-image', '1696x960'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 30c: qwen across the billing line — 2K at 4:3.
      await tester.tap(find.descendant(of: find.byKey(qwen), matching: find.text('4:3')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byKey(qwen), matching: find.text('2K')));
      await tester.pumpAndSettle();

      // 30e: 4:1 on gpt-image-2.
      await tester.tap(find.descendant(of: find.byKey(gpt), matching: find.byIcon(Icons.tune)));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(of: find.byKey(gpt), matching: find.byType(TextField)).first,
        '4:1',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // 30f: 4000 × 400 typed with the lock off.
      await tester.tap(find.descendant(of: find.byKey(bad), matching: find.byIcon(Icons.link)));
      await tester.pump();
      final badFields = find.descendant(of: find.byKey(bad), matching: find.byType(TextField));
      await tester.enterText(badFields.at(1), '4000');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.enterText(badFields.at(2), '400');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('size_picker_${brightness.name}.png'),
      );
    });
  }
}
