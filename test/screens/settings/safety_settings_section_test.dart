import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/safety_settings.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/screens/settings/widgets/safety_settings_section.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:provider/provider.dart';

import '../../support/private_data_dir.dart';
import '../../support/real_async.dart';

void main() {
  usePrivateDataDir('mas05-settings');
  useRealAsyncAppState();
  setUpAll(() => AppState().loadSettings());

  Widget page() => ChangeNotifierProvider.value(
    value: AppState(),
    child: const MaterialApp(
      locale: Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: SafetySettingsSection())),
    ),
  );

  test('saved legacy values normalize on load and persisted edits survive reload', () async {
    final state = AppState();
    await state.saveSetting(
      'safety_thresholds',
      jsonEncode({for (final category in SafetySettings.categories) category: 'OFF'}),
    );
    await state.loadSettings();
    expect(
      state.safetyThresholds.values,
      everyElement(SafetySettings.restricted ? 'BLOCK_MEDIUM_AND_ABOVE' : 'OFF'),
    );
    await state.setSafetyThreshold(SafetySettings.categories.first, 'BLOCK_LOW_AND_ABOVE');
    final saved = Map.of(state.safetyThresholds);
    state.safetyThresholds = SafetySettings.defaults();
    await state.loadSettings();
    expect(state.safetyThresholds, saved);
  });

  testWidgets('cancel keeps editing locked; confirmation only unlocks; reopening locks again', (
    tester,
  ) async {
    final state = AppState();
    await tester.pumpWidget(page());
    final before = Map.of(state.safetyThresholds);
    expect(tester.widgetList<Slider>(find.byType(Slider)).every((s) => s.onChanged == null), true);
    await tester.tap(find.text('Unlock editing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.widgetList<Slider>(find.byType(Slider)).every((s) => s.onChanged == null), true);
    await tester.tap(find.text('Unlock editing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I understand — unlock'));
    await tester.pumpAndSettle();
    expect(state.safetyThresholds, before);
    expect(tester.widgetList<Slider>(find.byType(Slider)).every((s) => s.onChanged != null), true);
    await inRealAsync(
      tester,
      () => state.setSafetyThreshold(SafetySettings.categories.first, 'OFF'),
    );
    expect(
      state.safetyThresholds[SafetySettings.categories.first],
      SafetySettings.restricted ? 'BLOCK_MEDIUM_AND_ABOVE' : 'OFF',
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(page());
    expect(tester.widgetList<Slider>(find.byType(Slider)).every((s) => s.onChanged == null), true);
  });
}
