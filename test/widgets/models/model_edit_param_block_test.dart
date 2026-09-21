import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/core/design_tokens.dart';
import 'package:joycai_image_ai_toolkits/core/theme_accent.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/model_edit_controls.dart';

/// `D2a`: the parameter summary's guide line takes the accent (35%) while a
/// protocol is pinned, and eases there (M2).
void main() {
  final theme = buildAppTheme(accent: ThemeAccent.fromSeed(Colors.indigo), brightness: Brightness.light);

  Future<void> pump(WidgetTester tester, bool governed) => tester.pumpWidget(MaterialApp(
        theme: theme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ModelEditParamBlock(items: const ['size: auto'], governed: governed),
        ),
      ));

  Color rail(WidgetTester tester) {
    final box = tester.widget<Container>(find.descendant(
      of: find.byType(ModelEditParamBlock),
      matching: find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration),
    ).first);
    final border = (box.decoration! as BoxDecoration).border! as BorderDirectional;
    return border.start.color;
  }

  testWidgets('hairline at rest, accent rule when governed, tweened', (tester) async {
    await pump(tester, false);
    expect(rail(tester), theme.colorScheme.outlineVariant);

    await pump(tester, true);
    await tester.pump(const Duration(milliseconds: 60));
    expect(rail(tester), isNot(theme.colorScheme.accentRule), reason: 'on its way, not switched');
    await tester.pumpAndSettle();
    expect(rail(tester), theme.colorScheme.accentRule);
  });
}
