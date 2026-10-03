import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/generation_params/generation_param_panel.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/generation_params/param_editor_registry.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/generation_params/param_presentation.dart';
import 'package:joycai_image_ai_toolkits/services/llm/generation/generation_schema.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_capabilities.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendor_profile.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_dropdown.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_segmented_control.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Center(child: SizedBox(width: 280, child: child)),
    ),
  );

  test('registry covers every declared editor', () {
    expect(ParamEditorRegistry.standard.builders.keys, containsAll(ParamControl.values));
  });

  testWidgets('presentation can replace an editor without changing semantic choices', (
    tester,
  ) async {
    final spec = ModelCapabilities.forModel('grok-imagine-image-2.0').imageParams.first;
    String? selected;
    await tester.pumpWidget(
      host(
        GenerationParamPanel(
          specs: [spec],
          valueOf: (_) => spec.defaultValue,
          presentation: {
            spec.key: const ParamPresentation(editor: ParamControl.segmented, fullRow: true),
          },
          registry: ParamEditorRegistry({
            ParamControl.segmented: (_, data) =>
                TextButton(onPressed: () => data.change('16:9'), child: const Text('Choose ratio')),
          }),
          onChanged: (_, value) => selected = value,
        ),
      ),
    );
    await tester.tap(find.text('Choose ratio'));
    expect(selected, '16:9');
    expect(spec.control, ParamControl.dropdown);
  });

  testWidgets('missing editors render a visible localized diagnostic', (tester) async {
    final spec = ModelCapabilities.forModel('grok-imagine-image-2.0').imageParams.first;
    await tester.pumpWidget(
      host(
        GenerationParamPanel(
          specs: [spec],
          valueOf: (_) => spec.defaultValue,
          onChanged: (_, _) {},
          registry: const ParamEditorRegistry({}),
        ),
      ),
    );
    expect(find.text('No editor is available for this setting.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Grok Image 2 has distinct Default and Auto ratio choices', (tester) async {
    final spec = ModelCapabilities.forModel(
      'grok-imagine-image-2.0',
    ).imageParams.firstWhere((p) => p.key == 'aspectRatio');
    String? selected;
    await tester.pumpWidget(
      host(
        GenerationParamPanel(
          specs: [spec],
          valueOf: (_) => 'not_set',
          onChanged: (_, value) => selected = value,
        ),
      ),
    );
    final dropdown = tester.widget<AppDropdown<String>>(find.byType(AppDropdown<String>));
    expect(dropdown.items.where((i) => i.label == 'Auto').length, 1);
    expect(dropdown.items.firstWhere((i) => i.value == 'not_set').label, 'Default');
    dropdown.onChanged!('auto');
    expect(selected, 'auto');
    dropdown.onChanged!('not_set');
    expect(selected, 'not_set');
  });

  for (final video in [false, true]) {
    testWidgets('shared slider emits selected duration in ${video ? 'video' : 'image'} form', (
      tester,
    ) async {
      final spec = ModelCapabilities.forModel(
        'grok-imagine-video',
      ).videoParams.firstWhere((p) => p.key == 'seconds');
      String? chosen;
      await tester.pumpWidget(
        host(
          GenerationParamPanel(
            specs: [spec],
            video: video,
            valueOf: (_) => '6',
            onChanged: (key, value) => chosen = value,
          ),
        ),
      );
      tester.widget<Slider>(find.byType(Slider)).onChanged!(9);
      expect(chosen, '9');
      expect(find.text('6s'), findsOneWidget);
    });
  }

  testWidgets('mode changes restore ratio and format while transparency shows fixed PNG', (
    tester,
  ) async {
    final caps = ModelCapabilities.forModel('doubao-seedream-5-0-pro-260628');
    final schema = GenerationSchema(
      protocol: WireProtocol.arkImages,
      capabilities: caps,
      profileId: caps.profileId,
    );
    final values = {for (final spec in caps.imageParams) spec.key: spec.defaultValue};
    values['aspectRatio'] = '16:9';
    Future<void> render(String mode) async {
      values['imageTask'] = mode;
      await tester.pumpWidget(
        host(
          GenerationParamPanel(
            specs: caps.imageParams,
            schema: schema,
            valueOf: (spec) => values[spec.key]!,
            onChanged: (key, value) => values[key] = value,
          ),
        ),
      );
    }

    await render('layers');
    expect(find.byKey(const ValueKey('aspectRatio')), findsNothing);
    await render('transparent');
    expect(find.text('PNG is required for transparent output.'), findsOneWidget);
    final format = find.descendant(
      of: find.byKey(const ValueKey('outputFormat')),
      matching: find.byType(AppSegmentedControl<String>),
    );
    expect(tester.widget<AppSegmentedControl<String>>(format).value, 'png');
    expect(values['outputFormat'], 'jpeg');
    await render('generate');
    expect(find.byKey(const ValueKey('aspectRatio')), findsOneWidget);
    expect(values['aspectRatio'], '16:9');
    expect(tester.widget<AppSegmentedControl<String>>(format).value, 'jpeg');
    expect(tester.takeException(), isNull);
  });
}
