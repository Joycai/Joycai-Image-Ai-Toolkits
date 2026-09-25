import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/core/theme_accent.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/llm_channel.dart';
import 'package:joycai_image_ai_toolkits/models/llm_model.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/model_selection_section.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/workbench_layout.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_descriptor.dart';

/// gpt-image-2.5's six-rung quality ladder on the workbench's right panel.
///
/// The four-rung ladder rides a segmented track. Six slots at the panel's
/// default width leave ~24px per label, and 「超高」/「最高」 need 24.6 — the
/// track drew 低 / 中 / 高 with three blank slots around them, in every
/// locale whose labels run to two characters. So the 2.5 ladder is a
/// dropdown, and this pins that every label it can show is drawn whole.
void main() {
  Widget host(String modelId, String quality, Locale locale) {
    final m = LLMModel(id: 1, modelId: modelId, modelName: modelId, tag: 'image', channelId: 1);
    final ch = LLMChannel(
      id: 1,
      displayName: 'Relay',
      endpoint: 'https://e.invalid',
      apiKey: 'k',
      type: 'openai-api-rest',
    );
    return MaterialApp(
      locale: locale,
      theme: buildAppTheme(
        accent: ThemeAccent.fromSeed(Colors.indigo),
        brightness: Brightness.light,
      ),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            // The right panel's default width, less the card's 10px a side.
            width: kRightPanelDefault - 20,
            child: SingleChildScrollView(
              child: ModelSelectionSection(
                availableModels: [m],
                channels: [ch],
                selectedChannelId: 1,
                selectedModelDbId: 1,
                isExpanded: true,
                onToggleExpansion: () {},
                onChannelChanged: (_) {},
                onModelChanged: (_) {},
                imageParamResolver: (model, spec) =>
                    spec.key == 'quality' ? quality : spec.defaultValue,
                onImageParamChanged: (_, _, _) {},
                capabilitiesOf: (m) => ModelDescriptor.of(m.modelId).capabilities,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Every single-line paragraph under the section is at least as wide as its
  /// text: none has been elided.
  void expectNothingElided(WidgetTester tester) {
    final paragraphs = tester.renderObjectList<RenderParagraph>(find.byType(RichText));
    for (final p in paragraphs) {
      if (p.maxLines != 1) continue;
      final painter = TextPainter(text: p.text, textDirection: TextDirection.ltr)..layout();
      expect(
        p.size.width + 0.01,
        greaterThanOrEqualTo(painter.width),
        reason: '"${p.text.toPlainText()}" was elided at the panel width',
      );
    }
  }

  for (final locale in const [Locale('zh'), Locale('en'), Locale('ja')]) {
    testWidgets('gpt-image-2.5: every quality rung is drawn whole ($locale)', (tester) async {
      for (final quality in const ['auto', 'low', 'medium', 'high', 'xhigh', 'max']) {
        await tester.pumpWidget(host('gpt-image-2.5-sunburst', quality, locale));
        await tester.pump();
        expectNothingElided(tester);
      }
    });
  }

  testWidgets('gpt-image-2 keeps its four-rung track intact', (tester) async {
    await tester.pumpWidget(host('gpt-image-2', 'high', const Locale('zh')));
    await tester.pump();
    for (final label in ['自动', '低', '中', '高']) {
      expect(find.text(label), findsWidgets);
    }
    expectNothingElided(tester);
  });
}
