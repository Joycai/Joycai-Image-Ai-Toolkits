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
import 'package:joycai_image_ai_toolkits/widgets/ui/app_dropdown.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_segmented_control.dart';

/// grok-imagine-image-2.0's three controls on the workbench's right panel
/// (`A1f · 4a`): ratio and quality side by side, the three-tier size track
/// on its own row underneath — the panel pairs cells in declaration order
/// and a segmented control of more than two options spans its row.
void main() {
  Widget host(String modelId, Locale locale, {double width = kRightPanelDefault - 20}) {
    final m = LLMModel(id: 1, modelId: modelId, modelName: modelId, tag: 'image', channelId: 1);
    final ch = LLMChannel(
        id: 1, displayName: 'xAI', endpoint: 'https://api.x.ai/v1', apiKey: 'k', type: 'xai-api');
    return MaterialApp(
      locale: locale,
      theme: buildAppTheme(accent: ThemeAccent.fromSeed(Colors.indigo), brightness: Brightness.light),
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
            width: width,
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
                imageParamResolver: (model, spec) => spec.defaultValue,
                onImageParamChanged: (_, _, _) {},
                capabilitiesOf: (m) => ModelDescriptor.of(m.modelId).capabilities,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void expectNothingElided(WidgetTester tester) {
    final paragraphs = tester.renderObjectList<RenderParagraph>(find.byType(RichText));
    for (final p in paragraphs) {
      if (p.maxLines != 1) continue;
      final painter = TextPainter(text: p.text, textDirection: TextDirection.ltr)..layout();
      expect(p.size.width + 0.01, greaterThanOrEqualTo(painter.width),
          reason: '"${p.text.toPlainText()}" was elided at the panel width');
    }
  }

  testWidgets('2.0: ratio beside quality, the size track full-width beneath', (tester) async {
    await tester.pumpWidget(host('grok-imagine-image-2.0', const Locale('zh')));
    await tester.pump();

    final tracks = find.byType(AppSegmentedControl<String>);
    expect(tracks, findsNWidgets(2));
    final quality = tester.getRect(tracks.at(0));
    final size = tester.getRect(tracks.at(1));
    final ratio = tester.getRect(find.byType(AppDropdown<String>));

    // Same row: the ratio box and the quality track share a top edge and
    // split the width; the size track sits below and takes all of it.
    expect(quality.top, ratio.top);
    expect(ratio.right, lessThan(quality.left));
    expect(size.top, greaterThan(quality.bottom));
    expect(size.left, ratio.left);
    expect(size.right, quality.right);
    expect(size.width, greaterThan(quality.width * 1.8));
  });

  for (final locale in const [Locale('zh'), Locale('ja')]) {
    testWidgets('2.0: every label is drawn whole at the panel width ($locale)', (tester) async {
      await tester.pumpWidget(host('grok-imagine-image-2.0', locale));
      await tester.pump();
      for (final label in ['1k', '1.5k', '2k']) {
        expect(find.text(label), findsOneWidget);
      }
      expectNothingElided(tester);
    });
  }

  testWidgets('2.0 (en): "Medium" has the width it needs in its half-cell', (tester) async {
    // The test font draws every glyph fontSize wide, so "Medium" reads as
    // 74px here and no elision check can pass; in the app's font it needs
    // 45.8px (measured with the screenshot harness's fonts, 2026-09-22). So
    // this pins the room the slot gives the label instead: with the track's
    // full 10px inset it was 43.5px, and the last two letters went.
    await tester.pumpWidget(host('grok-imagine-image-2.0', const Locale('en')));
    await tester.pump();
    final medium = tester.renderObject<RenderParagraph>(
        find.descendant(of: find.text('Medium'), matching: find.byType(RichText)));
    expect(medium.size.width, greaterThanOrEqualTo(46));
    for (final label in ['Low', '1k', '1.5k', '2k']) {
      final p = tester.renderObject<RenderParagraph>(
          find.descendant(of: find.text(label), matching: find.byType(RichText)));
      final painter = TextPainter(text: p.text, textDirection: TextDirection.ltr)..layout();
      expect(p.size.width + 0.01, greaterThanOrEqualTo(painter.width), reason: label);
    }
  });

  testWidgets('2.0 at the panel\'s minimum width keeps the size tiers whole', (tester) async {
    // 230px inside the card: a half-cell is 112px and an English "Medium"
    // (45.8px) no longer fits its 43px slot — the one label that elides,
    // and only below ~245px, where gpt-image-2's four-rung track loses its
    // "Medium" too. The full-width size track is never in question.
    await tester.pumpWidget(host('grok-imagine-image-2.0', const Locale('en'), width: kRightPanelMin - 20));
    await tester.pump();
    for (final label in ['1k', '1.5k', '2k']) {
      final p = tester.renderObject<RenderParagraph>(
          find.descendant(of: find.text(label), matching: find.byType(RichText)));
      final painter = TextPainter(text: p.text, textDirection: TextDirection.ltr)..layout();
      expect(p.size.width + 0.01, greaterThanOrEqualTo(painter.width), reason: label);
    }
  });

  testWidgets('the first generation keeps two controls in one row', (tester) async {
    await tester.pumpWidget(host('grok-imagine-image', const Locale('zh')));
    await tester.pump();
    final track = find.byType(AppSegmentedControl<String>);
    expect(track, findsOneWidget);
    expect(find.text('1.5k'), findsNothing);
    expect(find.text('低'), findsNothing);
    expect(tester.getRect(track).top, tester.getRect(find.byType(AppDropdown<String>)).top);
  });
}
