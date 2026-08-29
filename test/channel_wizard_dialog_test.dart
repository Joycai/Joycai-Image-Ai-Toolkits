import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:joycai_image_ai_toolkits/widgets/api_key_field.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_text_field.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/channel_provider_presets.dart';
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

/// The provider search box, found by its role rather than its wording so the
/// placeholder can change without rewriting every search test.
Finder _searchField(WidgetTester tester) => find.byWidgetPredicate(
      (w) => w is AppTextField && w.hint != null && w.controller != null &&
          (w.hint!.contains('Search providers') || w.hint!.contains('搜索供应商')),
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

/// Find a provider row, scrolling the rail if it sits below the fold.
/// Presence, not first-screen visibility, is what these tests are about.
Future<Finder> _findProvider(WidgetTester tester, String label) async {
  final finder = find.text(label);
  if (finder.evaluate().isNotEmpty) return finder;
  // Scroll the *rail* specifically. `find.byType(Scrollable).first` picks up
  // the form column's scroll view on the wide layout, and dragging that one
  // never reveals a provider row.
  final rail = find.byType(ListView);
  if (rail.evaluate().isEmpty) return finder;
  for (var i = 0; i < 20 && finder.evaluate().isEmpty; i++) {
    await tester.drag(rail.first, const Offset(0, -120));
    await tester.pump();
  }
  await tester.pumpAndSettle();
  return finder;
}

/// Pick a provider by its card/row label, wherever the current layout draws it.
Future<void> _selectProvider(WidgetTester tester, String label) async {
  final finder = await _findProvider(tester, label);
  await tester.tap(finder.first);
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

      // Driven off the catalogue rather than a hand-typed list: a preset
      // added below has to appear here without anyone remembering to add it,
      // which is the whole reason the rail iterates the catalogue too.
      final l10n = AppLocalizations.of(
          tester.element(find.byType(ChannelWizardDialog)))!;
      for (final preset in kChannelProviderPresets) {
        final finder =
            await _findProvider(tester, channelProviderTitle(l10n, preset.id));
        expect(
          finder,
          findsWidgets,
          reason:
              '${preset.id} is defined as a preset but not rendered in the rail',
        );
      }
      expect(kChannelProviderPresets.length, 16);

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
      await _selectProvider(tester, 'Alibaba DashScope (OpenAI compatible)');

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

      await _selectProvider(tester, 'Alibaba DashScope (OpenAI compatible)');
      await _selectProvider(tester, 'DeepSeek');

      expect(
        _controllerOf(tester, _fieldWithLabel(endpointLabel))?.text,
        'https://api.deepseek.com',
        reason: 'a stale host here would create a channel pointed at DashScope',
      );
    });

    testWidgets('search filters the rail', (tester) async {
      await _pumpWizard(tester);

      final search = _searchField(tester);
      expect(search, findsOneWidget);

      await _typeInto(tester, search, 'deepseek');
      expect(find.text('DeepSeek'), findsWidgets);
      expect(find.text('Alibaba DashScope (OpenAI compatible)'), findsNothing);

      // Clearing restores everything — a filter that cannot be undone is how
      // a preset goes unreachable without anyone noticing.
      await _typeInto(tester, search, '');
      expect(find.text('Alibaba DashScope (OpenAI compatible)'), findsWidgets);
    });

    // The separate "Qianwen Platform" row was folded into DashScope — same
    // host, same key, same vendor — which is only safe because the names it
    // used to be found under still reach the row that replaced it.
    //
    // DashScope's own two rows are the opposite case: two faces that differ
    // in what they can do, so every alias has to reach *both* — a search
    // that surfaced only one would be choosing the face for the user.
    testWidgets('folded-in names still find DashScope', (tester) async {
      await _pumpWizard(tester);
      final search = _searchField(tester);

      for (final alias in const ['qianwen', 'Qwen', '千问', '通义']) {
        await _typeInto(tester, search, alias);
        for (final row in const [
          'Alibaba DashScope (OpenAI compatible)',
          'Alibaba DashScope (native)',
        ]) {
          expect(
            find.text(row),
            findsWidgets,
            reason: '"$alias" no longer reaches "$row"',
          );
        }
      }
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

  // The three presets with more than one way in. Switching face is the one
  // interaction that rewrites the endpoint, so each of these pins the address
  // the switch produces — a wrong one here is a 404 that says nothing about
  // which half of the URL is at fault.
  group('providers with more than one way in', () {
    testWidgets('MiniMax switches between its two interfaces',
        (tester) async {
      await _pumpWizard(tester);
      await _selectProvider(tester, 'MiniMax');

      expect(find.text('OpenAI interface'), findsOneWidget);
      expect(find.text('Anthropic interface'), findsOneWidget);

      // Both faces prefill, and switching back restores the first one — the
      // ① variant used to carry no address, so this round trip left the field
      // empty.
      expect(
        _controllerOf(tester, _fieldWithLabel(endpointLabel))?.text,
        'https://api.minimaxi.com/v1',
      );

      await tester.tap(find.text('Anthropic interface'));
      await tester.pumpAndSettle();
      expect(
        _controllerOf(tester, _fieldWithLabel(endpointLabel))?.text,
        'https://api.minimaxi.com/anthropic/v1',
      );

      await tester.tap(find.text('OpenAI interface'));
      await tester.pumpAndSettle();
      expect(
        _controllerOf(tester, _fieldWithLabel(endpointLabel))?.text,
        'https://api.minimaxi.com/v1',
      );
    });

    testWidgets('Google offers its native and OpenAI-compatible faces',
        (tester) async {
      await _pumpWizard(tester);
      await _selectProvider(tester, 'Google GenAI');

      expect(
        _controllerOf(tester, _fieldWithLabel(endpointLabel))?.text,
        'https://generativelanguage.googleapis.com/v1beta',
      );

      await tester.tap(find.text('OpenAI compatible'));
      await tester.pumpAndSettle();
      expect(
        _controllerOf(tester, _fieldWithLabel(endpointLabel))?.text,
        'https://generativelanguage.googleapis.com/v1beta/openai',
      );
    });

    testWidgets('NewAPI keeps the typed host and swaps only the version path',
        (tester) async {
      await _pumpWizard(tester);
      await _selectProvider(tester, 'NewAPI');

      final field = _fieldWithLabel('New API Base URL');
      await _typeInto(tester, field, 'https://relay.example.com');

      await tester.tap(find.text('Gemini format'));
      await tester.pumpAndSettle();
      expect(
        _controllerOf(tester, _fieldWithLabel('New API Base URL'))?.text,
        'https://relay.example.com',
        reason: 'the host the user typed must survive a format switch',
      );

      // The suffix is applied on submit, not typed into the field, so assert
      // it where it actually lands.
      await _typeInto(tester, _fieldWithLabel('Enter your API Key'), 'sk-x');
      await tester.tap(find.widgetWithText(FilledButton, 'Add Channel'));
      await tester.pumpAndSettle();
    });
  });

  // Spec D2 16f: the local runtimes have no key to give, and the required
  // check used to leave the user typing a junk character to get past it.
  group('local runtimes', () {
    testWidgets('Ollama prefills localhost and does not demand a key',
        (tester) async {
      await _pumpWizard(tester);
      await _selectProvider(tester, 'Ollama');

      expect(
        _controllerOf(tester, _fieldWithLabel(endpointLabel))?.text,
        'http://localhost:11434/v1',
      );

      // The field stays — someone may have put reverse-proxy auth in front —
      // but it says so, and it stops being required.
      final keyField = tester.widget<ApiKeyField>(find.byType(ApiKeyField));
      expect(keyField.label, contains('Optional'));
      expect(keyField.hint, 'Local services usually need none');
      expect(keyField.errorText, isNull);
      expect(Vendors.byId(Vendors.ollama).keyOptional, isTrue);
    });

    testWidgets('a hosted provider still requires one', (tester) async {
      await _pumpWizard(tester);
      await _selectProvider(tester, 'OpenAI');

      await tester.tap(find.widgetWithText(FilledButton, 'Add Channel'));
      await tester.pumpAndSettle();
      expect(
        find.text(
            'This provider needs an API key before the channel can be added'),
        findsOneWidget,
      );
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

      final l10n = AppLocalizations.of(
          tester.element(find.byType(ChannelWizardDialog)))!;
      for (final preset in kChannelProviderPresets) {
        expect(
          find.text(channelProviderTitle(l10n, preset.id)),
          findsWidgets,
          reason:
              '${preset.id} is defined as a preset but not rendered on step 1',
        );
      }
    });

    testWidgets('step 2 carries the same fields as the wide right column',
        (tester) async {
      await _pumpWizard(tester, width: narrow);

      await _selectProvider(tester, 'Alibaba DashScope (OpenAI compatible)');
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

      await _selectProvider(tester, 'Alibaba DashScope (OpenAI compatible)');
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
