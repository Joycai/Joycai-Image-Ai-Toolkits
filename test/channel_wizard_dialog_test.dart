import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_text_field.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/channel_wizard_dialog.dart';

/// Mount the wizard at a given window width.
///
/// Width is the whole point of these tests: at or above
/// `Responsive.tabletBreakpoint` the dialog is one page with two columns, and
/// below it the same state is shown as a two-step flow. Both have to reach
/// every preset and every field.
Future<void> _pumpWizard(WidgetTester tester, {double width = 1400}) async {
  tester.view.physicalSize = Size(width, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          final l10n = AppLocalizations.of(context)!;
          return Scaffold(
            body: ChannelWizardDialog(l10n: l10n, appState: AppState()),
          );
        },
      ),
    ),
  );
  await tester.pump();
}

/// The [AppTextField] carrying [label]. Finding by label rather than by
/// position: the one-page layout puts a provider search box ahead of the form,
/// so "the first TextField" is no longer the endpoint.
Finder _fieldWithLabel(String label) => find.byWidgetPredicate(
      (w) => w is AppTextField && w.label == label,
    );

TextEditingController? _controllerOf(WidgetTester tester, Finder field) =>
    tester.widget<AppTextField>(field).controller;

Future<void> _typeInto(
  WidgetTester tester,
  Finder field,
  String text,
) async {
  await tester.enterText(
    find.descendant(of: field, matching: find.byType(TextField)),
    text,
  );
  await tester.pump();
}

/// Pick a provider by its card/row label, wherever the current layout draws it.
Future<void> _selectProvider(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).first);
  await tester.pumpAndSettle();
}

void main() {
  const endpointLabel = 'Endpoint URL';

  // Two regressions, both of which shipped: provider cards that existed in the
  // preset list but were never rendered, and an endpoint the user could not
  // edit once a preset supplied one. Both are pinned at both widths, because
  // the two layouts render the catalogue through different widgets.

  group('one page, two columns (wide)', () {
    testWidgets('every provider preset is reachable in the rail',
        (tester) async {
      await _pumpWizard(tester);

      // Names that only appear as provider rows. DashScope and Qianwen are the
      // ones that went missing; the other two disappeared the same way earlier.
      for (final label in const [
        'DeepSeek',
        'MiniMax',
        'Alibaba DashScope',
        'Qianwen Platform',
      ]) {
        expect(
          find.text(label),
          findsWidgets,
          reason: '$label is defined as a preset but not rendered in the rail',
        );
      }

      expect(tester.takeException(), isNull);
    });

    testWidgets('the form is visible without leaving the provider list',
        (tester) async {
      await _pumpWizard(tester);

      // The whole point of one page: no Next, and the connection fields are
      // already on screen beside the picker.
      expect(find.text('Next'), findsNothing);
      expect(_fieldWithLabel(endpointLabel), findsOneWidget);
      expect(_fieldWithLabel('Enter your API Key'), findsOneWidget);
      expect(find.text('Add Channel'), findsWidgets);
    });

    testWidgets('preset endpoint is prefilled and still editable',
        (tester) async {
      await _pumpWizard(tester);
      await _selectProvider(tester, 'Qianwen Platform');

      final field = _fieldWithLabel(endpointLabel);
      expect(
        _controllerOf(tester, field)?.text,
        'https://dashscope.aliyuncs.com/compatible-mode/v1',
        reason: 'the preset should prefill its host',
      );

      // The international host is the case that has no preset of its own and
      // so is only reachable by typing over the suggestion.
      const intl = 'https://dashscope-intl.aliyuncs.com/compatible-mode/v1';
      await _typeInto(tester, field, intl);
      expect(_controllerOf(tester, _fieldWithLabel(endpointLabel))?.text, intl);

      expect(tester.takeException(), isNull);
    });

    testWidgets('switching provider replaces the previous host',
        (tester) async {
      await _pumpWizard(tester);

      await _selectProvider(tester, 'Qianwen Platform');
      await _selectProvider(tester, 'DeepSeek');

      expect(
        _controllerOf(tester, _fieldWithLabel(endpointLabel))?.text,
        'https://api.deepseek.com',
        reason: 'a stale host here would create a channel pointed at Qianwen',
      );
    });

    testWidgets('search filters the rail', (tester) async {
      await _pumpWizard(tester);

      final search = find.byWidgetPredicate(
        (w) => w is AppTextField && w.hint == 'Search providers…',
      );
      expect(search, findsOneWidget);

      await _typeInto(tester, search, 'deepseek');
      expect(find.text('DeepSeek'), findsWidgets);
      expect(find.text('Qianwen Platform'), findsNothing);

      // Clearing restores everything — a filter that cannot be undone is how
      // a preset goes unreachable without anyone noticing.
      await _typeInto(tester, search, '');
      expect(find.text('Qianwen Platform'), findsWidgets);
    });

    testWidgets('a missing key blocks the add and says why', (tester) async {
      await _pumpWizard(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Add Channel'));
      await tester.pumpAndSettle();

      expect(
        find.text('This provider needs an API key before the channel can be added'),
        findsOneWidget,
      );
      // Still open: nothing was created.
      expect(_fieldWithLabel(endpointLabel), findsOneWidget);
    });
  });

  group('two steps (narrow fallback)', () {
    // 900 is a tablet-sized window: too narrow for a 288px rail beside a form,
    // wide enough that the dialog is still a dialog rather than a page.
    const narrow = 900.0;

    testWidgets('falls back to pick-then-configure', (tester) async {
      await _pumpWizard(tester, width: narrow);

      expect(find.text('Next'), findsOneWidget);
      // Step 1 is the picker only; the connection fields arrive on step 2.
      expect(_fieldWithLabel('Endpoint URL'), findsNothing);
    });

    testWidgets('every provider preset is reachable on step 1',
        (tester) async {
      await _pumpWizard(tester, width: narrow);

      for (final label in const [
        'DeepSeek',
        'MiniMax',
        'Alibaba DashScope',
        'Qianwen Platform',
      ]) {
        expect(
          find.text(label),
          findsWidgets,
          reason: '$label is defined as a preset but not rendered on step 1',
        );
      }
    });

    testWidgets('step 2 carries the same fields as the wide right column',
        (tester) async {
      await _pumpWizard(tester, width: narrow);

      await _selectProvider(tester, 'Qianwen Platform');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(
        _controllerOf(tester, _fieldWithLabel(endpointLabel))?.text,
        'https://dashscope.aliyuncs.com/compatible-mode/v1',
      );
      for (final label in const [
        'Enter your API Key',
        'Display Name',
        'Tag',
      ]) {
        expect(
          _fieldWithLabel(label),
          findsOneWidget,
          reason: '$label is only reachable on the wide layout',
        );
      }
      // Test connection is not a wide-only feature either.
      expect(find.text('Test connection'), findsOneWidget);
    });

    testWidgets('switching provider on step 1 replaces the previous host',
        (tester) async {
      await _pumpWizard(tester, width: narrow);

      await _selectProvider(tester, 'Qianwen Platform');
      await _selectProvider(tester, 'DeepSeek');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(
        _controllerOf(tester, _fieldWithLabel(endpointLabel))?.text,
        'https://api.deepseek.com',
      );
    });
  });
}
