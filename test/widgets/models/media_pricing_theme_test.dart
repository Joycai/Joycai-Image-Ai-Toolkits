import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/core/constants.dart';
import 'package:joycai_image_ai_toolkits/core/design_tokens.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/pricing_group.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/fee_group_draft.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/fee_group_editor_fields.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_text_field.dart';

void main() {
  for (final accent in AppConstants.presetThemes.entries) {
    for (final brightness in Brightness.values) {
      testWidgets('media inputs inherit ${accent.key} $brightness and shared focus', (
        tester,
      ) async {
        final draft = FeeGroupDraft(PricingGroup(name: 'Media'));
        addTearDown(draft.dispose);
        final theme = buildAppTheme(accent: accent.value, brightness: brightness);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(child: FeeGroupEditorFields(draft: draft)),
            ),
          ),
        );
        final field = find.byWidgetPredicate(
          (w) => w is TextField && w.controller == draft.imageTokenInputCtrl,
        );
        expect(find.ancestor(of: field, matching: find.byType(AppTextField)), findsOneWidget);
        await tester.ensureVisible(field);
        await tester.tap(field);
        await tester.pumpAndSettle();
        final decorator = tester.widget<InputDecorator>(
          find.descendant(of: field, matching: find.byType(InputDecorator)),
        );
        expect(decorator.decoration.focusedBorder!.borderSide.color, theme.colorScheme.primary);
        final wrapper = find.ancestor(of: field, matching: find.byType(AppTextField));
        final ring = tester.widget<AnimatedContainer>(
          find.descendant(of: wrapper, matching: find.byType(AnimatedContainer)),
        );
        expect(
          ((ring.decoration as BoxDecoration).border as Border).top.color,
          theme.colorScheme.accentRing,
        );
        await tester.enterText(field, '-1');
        await tester.pumpAndSettle();
        expect(draft.canSave, isFalse);
        await tester.enterText(field, '0');
        await tester.pumpAndSettle();
        expect(draft.canSave, isTrue);
        draft.setMode('spec');
        draft.videoInputExpanded = true;
        draft.touch();
        await tester.pumpAndSettle();
        for (final element in find.byType(TextField).evaluate()) {
          expect(element.findAncestorWidgetOfExactType<AppTextField>(), isNotNull);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
