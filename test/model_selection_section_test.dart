import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/llm_channel.dart';
import 'package:joycai_image_ai_toolkits/models/llm_model.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/model_selection_section.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_dropdown.dart';

/// Covers the two ways the workbench's model card can disagree with itself.
///
/// Both are states a single mount never reaches: one needs the selection to
/// change while a parameter write is still in flight, the other needs the
/// selected model and the selected channel to come apart. The card derives
/// everything it draws from that one pair, so when they part company it is
/// three widgets' worth of disagreement, not one.
void main() {
  const seed = Colors.indigo;

  /// `gemini-3.1-flash-image` maps to the wide aspect-ratio table (which has
  /// `8:1`); a plain `gemini-*-image` maps to the narrow one (which does not).
  /// The pair is the point: the value has to be legal for one and absent from
  /// the other.
  LLMModel model({required int id, required String modelId, int channelId = 1}) => LLMModel(
        id: id,
        modelId: modelId,
        modelName: modelId,
        tag: 'image',
        channelId: channelId,
      );

  final wide = model(id: 1, modelId: 'gemini-3.1-flash-image');
  final narrow = model(id: 2, modelId: 'gemini-2.5-flash-image');

  final channel = LLMChannel(
    id: 1,
    displayName: 'Relay',
    endpoint: 'https://example.invalid',
    apiKey: 'k',
    type: 'openai-api-rest',
  );

  Widget host({
    required List<LLMModel> models,
    required int? selectedModelDbId,
    required int? selectedChannelId,
    required String Function(String modelId, dynamic spec) resolver,
    void Function(String, String, String)? onParamChanged,
    List<LLMChannel>? channels,
  }) {
    return MaterialApp(
      theme: buildAppTheme(seedColor: seed, brightness: Brightness.light),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ModelSelectionSection(
            availableModels: models,
            channels: channels ?? [channel],
            selectedChannelId: selectedChannelId,
            selectedModelDbId: selectedModelDbId,
            isExpanded: true,
            onToggleExpansion: () {},
            onChannelChanged: (_) {},
            onModelChanged: (_) {},
            imageParamResolver: (modelId, spec) => resolver(modelId, spec),
            onImageParamChanged: onParamChanged ?? (_, _, _) {},
          ),
        ),
      ),
    );
  }

  testWidgets('a parameter edit in flight survives a model change', (tester) async {
    // Tall enough for the whole card, so the dropdown is not below the fold
    // when its menu opens.
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // What the panel reads back from AppState. `setImageParam` awaits its
    // SQLite write before notifying, so between the user's pick and that write
    // landing this still answers with the old value — the window the whole
    // test is about, held open here by never moving it.
    const stored = 'not_set';
    final writes = <String>[];

    await tester.pumpWidget(host(
      models: [wide, narrow],
      selectedModelDbId: wide.id,
      selectedChannelId: 1,
      resolver: (_, _) => stored,
      onParamChanged: (_, _, value) => writes.add(value),
    ));
    await tester.pumpAndSettle();

    // Pick an aspect ratio only the wide table offers.
    await tester.tap(find.byType(DropdownButton<String>).first, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('8:1').last);
    await tester.pumpAndSettle();
    expect(writes, ['8:1'], reason: 'the pick should have been handed to the caller');

    // Now switch models before the write lands: `stored` is deliberately left
    // at 'not_set', so a dropdown that owned its own value (the FormField
    // this row used to be) would keep '8:1' across the two builds — a value
    // absent from the narrow table, which the inner DropdownButton asserts
    // on. The controlled [AppDropdown] shows the resolver's answer instead.
    await tester.pumpWidget(host(
      models: [wide, narrow],
      selectedModelDbId: narrow.id,
      selectedChannelId: 1,
      resolver: (_, _) => stored,
      onParamChanged: (_, _, value) => writes.add(value),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('8:1'), findsNothing, reason: 'the stale value must not survive the swap');
  });

  group('a selection whose channel does not match', () {
    testWidgets('draws no parameter rows', (tester) async {
      // The model is real and selected, but its channel is not the selected
      // one. Every consumer of the selection has to agree it is not usable —
      // the parameter rows most of all, since editing them writes under this
      // model's family key.
      await tester.pumpWidget(host(
        models: [wide],
        selectedModelDbId: wide.id,
        selectedChannelId: 99,
        channels: [channel],
        resolver: (_, _) => 'not_set',
      ));
      await tester.pumpAndSettle();

      expect(find.byType(AppDropdown<String>), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('draws the parameter rows once the channel agrees', (tester) async {
      await tester.pumpWidget(host(
        models: [wide],
        selectedModelDbId: wide.id,
        selectedChannelId: 1,
        resolver: (_, _) => 'not_set',
      ));
      await tester.pumpAndSettle();

      expect(find.byType(AppDropdown<String>), findsWidgets);
    });
  });
}
