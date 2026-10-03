@Tags(<String>['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/core/constants.dart';
import 'package:joycai_image_ai_toolkits/core/design_tokens.dart';
import 'package:joycai_image_ai_toolkits/core/theme_accent.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/generation_params/generation_param_panel.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

void main() {
  const locales = [
    Locale('en'),
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    Locale('ja'),
  ];
  const scenarios = [
    (Vendors.xaiApi, 'grok-imagine-image-2.0', 'image', <String, String>{}),
    (
      Vendors.volcengineArk,
      'doubao-seedream-5-0-pro-260628',
      'image',
      {'imageTask': 'transparent', 'outputFormat': 'jpeg'},
    ),
    (
      Vendors.volcengineArk,
      'doubao-seedream-5-0-pro-260628',
      'image',
      {'imageTask': 'layers', 'aspectRatio': '16:9'},
    ),
    (Vendors.xaiApi, 'grok-imagine-video', 'video', {'seconds': '9'}),
    (Vendors.dashscopeNative, 'qwen-image-3.0', 'image', {'imageSize': '1024x1024'}),
  ];
  void shot({
    required double width,
    required Brightness brightness,
    required Locale locale,
    required ThemeAccent accent,
    required String suffix,
  }) {
    testWidgets('generation parameters $suffix', (tester) async {
      tester.view.physicalSize = Size(width, width < 600 ? 2400 : 1300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const root = ValueKey('generation-specimens');
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildAppTheme(accent: accent, brightness: brightness, fontFamily: 'NotoSansSC'),
          home: Scaffold(
            key: root,
            body: Padding(
              padding: const EdgeInsets.all(AppSpace.s16),
              child: Wrap(
                spacing: AppSpace.s16,
                runSpacing: AppSpace.s16,
                children: [
                  for (final (vendor, model, tag, values) in scenarios)
                    Builder(
                      builder: (context) {
                        final schema = LLMDispatcher.generationSchemaFor(
                          channelType: vendor,
                          modelId: model,
                          tag: tag,
                        );
                        return SizedBox(
                          width: width < 600 ? width - 32 : 268,
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpace.s10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(model, style: Theme.of(context).textTheme.titleSmall),
                                  const SizedBox(height: AppSpace.s10),
                                  GenerationParamPanel(
                                    specs: [for (final param in schema.params) param.legacy],
                                    schema: schema,
                                    video: tag == 'video',
                                    valueOf: (spec) => spec.normalize(values[spec.key]),
                                    storedValueOf: (key) =>
                                        key == 'quality' ? 'retired-value' : values[key],
                                    onChanged: (_, _) {},
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (Object? error = tester.takeException(); error != null; error = tester.takeException()) {
        debugPrint('[$suffix] exception: $error');
      }
      await expectLater(find.byKey(root), matchesGoldenFile('generation_$suffix.png'));
    });
  }

  for (final width in [390.0, 834.0, 1024.0, 1440.0]) {
    for (final brightness in Brightness.values) {
      for (final locale in locales) {
        shot(
          width: width,
          brightness: brightness,
          locale: locale,
          accent: AppConstants.presetThemes.values.first,
          suffix: '${width.toInt()}_${brightness.name}_${locale.toLanguageTag()}',
        );
      }
    }
  }
  for (final seed in AppConstants.presetThemes.entries) {
    for (final brightness in Brightness.values) {
      shot(
        width: 1440,
        brightness: brightness,
        locale: const Locale('en'),
        accent: seed.value,
        suffix: '${seed.key}_${brightness.name}',
      );
    }
  }
}
