import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/channel_form_sections.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/channel_provider_presets.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/channel_wizard_dialog.dart';

/// Mount the wizard at a given window width.
///
/// `D1b`: a stepped dialog on desktop and tablet, a full-screen page on a
/// phone — the same steps either way. Provider → (way in, for presets with
/// more than one) → endpoint & key → tag & appearance → preview.
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

/// The provider search box, by its role rather than its full wording.
Finder _searchField() => find.byWidgetPredicate(
      (w) => w is ChannelField && (w.hint ?? '').contains('Search providers'),
    );

/// On the connection step the only two fields are the endpoint and the key;
/// the key is the one that can be masked.
Finder _endpointField() => find.byWidgetPredicate((w) => w is ChannelField && !w.obscurable);
Finder _keyField() => find.byWidgetPredicate((w) => w is ChannelField && w.obscurable);

String _textOf(WidgetTester tester, Finder field) => tester.widget<ChannelField>(field).controller.text;

Future<void> _typeInto(WidgetTester tester, Finder field, String text) async {
  await tester.enterText(find.descendant(of: field, matching: find.byType(TextField)), text);
  await tester.pump();
}

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

Future<void> _selectProvider(WidgetTester tester, String label) async {
  final finder = find.text(label);
  expect(finder, findsWidgets, reason: '$label is not on the provider step');
  // Every row is built, but the lower groups sit below the dialog's fold.
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

/// Next until the connection step is on screen (one or two steps away).
Future<void> _toConnection(WidgetTester tester) async {
  for (var i = 0; i < 3 && _keyField().evaluate().isEmpty; i++) {
    await _tapText(tester, 'Next');
  }
  expect(_keyField(), findsOneWidget, reason: 'never reached the endpoint & key step');
}

void main() {
  // Two regressions, both of which shipped: provider rows that existed in the
  // preset list but were never rendered, and an endpoint the user could not
  // edit once a preset supplied one.

  group('provider step', () {
    testWidgets('every provider preset is rendered, without scrolling', (tester) async {
      await _pumpWizard(tester);

      // Driven off the catalogue: a preset added later has to appear here
      // without anyone remembering to add it to a list.
      final l10n = AppLocalizations.of(tester.element(find.byType(ChannelWizardDialog)))!;
      for (final preset in kChannelProviderPresets) {
        expect(
          find.text(channelProviderTitle(l10n, preset.id)),
          findsWidgets,
          reason: '${preset.id} is defined as a preset but not rendered',
        );
      }
      expect(kChannelProviderPresets.length, 16);
      expect(tester.takeException(), isNull);
    });

    testWidgets('opens on the picker; the connection fields come later', (tester) async {
      await _pumpWizard(tester);

      expect(find.text('Next'), findsOneWidget);
      expect(_keyField(), findsNothing);
    });

    testWidgets('search filters the providers, and clearing restores them', (tester) async {
      await _pumpWizard(tester);

      final search = _searchField();
      expect(search, findsOneWidget);

      await _typeInto(tester, search, 'deepseek');
      expect(find.text('DeepSeek'), findsWidgets);
      expect(find.text('Alibaba DashScope (OpenAI compatible)'), findsNothing);

      await _typeInto(tester, search, '');
      expect(find.text('Alibaba DashScope (OpenAI compatible)'), findsWidgets);
    });

    // The separate "Qianwen Platform" row was folded into DashScope, which is
    // only safe because the names it used to be found under still reach both
    // of DashScope's faces.
    testWidgets('folded-in names still find DashScope', (tester) async {
      await _pumpWizard(tester);
      final search = _searchField();

      for (final alias in const ['qianwen', 'Qwen', '千问', '通义']) {
        await _typeInto(tester, search, alias);
        for (final row in const [
          'Alibaba DashScope (OpenAI compatible)',
          'Alibaba DashScope (native)',
        ]) {
          expect(find.text(row), findsWidgets, reason: '"$alias" no longer reaches "$row"');
        }
      }
    });
  });

  group('endpoint & key step', () {
    testWidgets('preset endpoint is prefilled and still editable', (tester) async {
      await _pumpWizard(tester);
      await _selectProvider(tester, 'Alibaba DashScope (OpenAI compatible)');
      await _toConnection(tester);

      expect(
        _textOf(tester, _endpointField()),
        'https://dashscope.aliyuncs.com/compatible-mode/v1',
        reason: 'the preset should prefill its host',
      );

      // The international host has no preset of its own, so it is only
      // reachable by typing over the suggestion.
      const intl = 'https://dashscope-intl.aliyuncs.com/compatible-mode/v1';
      await _typeInto(tester, _endpointField(), intl);
      expect(_textOf(tester, _endpointField()), intl);
      expect(tester.takeException(), isNull);
    });

    testWidgets('switching provider replaces the previous host', (tester) async {
      await _pumpWizard(tester);

      await _selectProvider(tester, 'Alibaba DashScope (OpenAI compatible)');
      await _selectProvider(tester, 'DeepSeek');
      await _toConnection(tester);

      expect(
        _textOf(tester, _endpointField()),
        'https://api.deepseek.com',
        reason: 'a stale host here would create a channel pointed at DashScope',
      );
    });

    testWidgets('a missing key blocks the next step and says why', (tester) async {
      await _pumpWizard(tester);
      await _selectProvider(tester, 'DeepSeek');
      await _toConnection(tester);

      await _tapText(tester, 'Next');

      expect(
        find.text('This provider needs an API key before the channel can be added'),
        findsOneWidget,
      );
      // Still here: nothing moved on, nothing was created.
      expect(_keyField(), findsOneWidget);
    });
  });

  // The presets with more than one way in. Switching face is the one
  // interaction that rewrites the endpoint, so each pins the address the
  // switch produces — a wrong one is a 404 that says nothing about which half
  // of the URL is at fault.
  group('providers with more than one way in', () {
    testWidgets('MiniMax switches between its two interfaces', (tester) async {
      await _pumpWizard(tester);
      await _selectProvider(tester, 'MiniMax');
      await _tapText(tester, 'Next');

      expect(find.text('OpenAI interface'), findsWidgets);
      expect(find.text('Anthropic interface'), findsWidgets);

      await _tapText(tester, 'Next');
      expect(_textOf(tester, _endpointField()), 'https://api.minimaxi.com/v1');

      await _tapText(tester, 'Back');
      await tester.tap(find.text('Anthropic interface').first);
      await tester.pumpAndSettle();
      await _tapText(tester, 'Next');
      expect(_textOf(tester, _endpointField()), 'https://api.minimaxi.com/anthropic/v1');

      // Switching back restores the first face — the first variant once
      // carried no address, so this round trip left the field empty.
      await _tapText(tester, 'Back');
      await tester.tap(find.text('OpenAI interface').first);
      await tester.pumpAndSettle();
      await _tapText(tester, 'Next');
      expect(_textOf(tester, _endpointField()), 'https://api.minimaxi.com/v1');
    });

    testWidgets('Google offers its native and OpenAI-compatible faces', (tester) async {
      await _pumpWizard(tester);
      await _selectProvider(tester, 'Google GenAI');
      await _toConnection(tester);

      expect(_textOf(tester, _endpointField()), 'https://generativelanguage.googleapis.com/v1beta');

      await _tapText(tester, 'Back');
      await tester.tap(find.text('OpenAI compatible').first);
      await tester.pumpAndSettle();
      await _tapText(tester, 'Next');
      expect(
        _textOf(tester, _endpointField()),
        'https://generativelanguage.googleapis.com/v1beta/openai',
      );
    });

    testWidgets('NewAPI keeps the typed host and swaps only the version path', (tester) async {
      await _pumpWizard(tester);
      await _selectProvider(tester, 'NewAPI');
      await _toConnection(tester);

      await _typeInto(tester, _endpointField(), 'https://relay.example.com');

      await _tapText(tester, 'Back');
      await tester.tap(find.text('Gemini format').first);
      await tester.pumpAndSettle();
      await _tapText(tester, 'Next');

      expect(
        _textOf(tester, _endpointField()),
        'https://relay.example.com',
        reason: 'the host the user typed must survive a format switch',
      );
    });
  });

  // Spec D2 16f: the local runtimes have no key to give, and the required
  // check used to leave the user typing a junk character to get past it.
  group('local runtimes', () {
    testWidgets('Ollama prefills localhost and does not demand a key', (tester) async {
      await _pumpWizard(tester);
      await _selectProvider(tester, 'Ollama');
      await _toConnection(tester);

      expect(_textOf(tester, _endpointField()), 'http://localhost:11434/v1');

      // The field stays — someone may have put reverse-proxy auth in front —
      // but it says so, and it stops being required: moving on is a skip.
      final key = tester.widget<ChannelField>(_keyField());
      expect(key.hint, 'Local services usually need none');
      expect(key.errorText, isNull);
      expect(find.textContaining('Optional'), findsWidgets);
      expect(find.text('Skip'), findsOneWidget);
      expect(Vendors.byId(Vendors.ollama).keyOptional, isTrue);

      await _tapText(tester, 'Skip');
      expect(find.text('This provider needs an API key before the channel can be added'), findsNothing);
      expect(_keyField(), findsNothing, reason: 'an optional key must not block the next step');
    });

    testWidgets('a hosted provider still requires one', (tester) async {
      await _pumpWizard(tester);
      await _selectProvider(tester, 'OpenAI');
      await _toConnection(tester);

      await _tapText(tester, 'Next');
      expect(
        find.text('This provider needs an API key before the channel can be added'),
        findsOneWidget,
      );
    });
  });

  group('phone page', () {
    testWidgets('the same steps fit a phone', (tester) async {
      await _pumpWizard(tester, width: 390);

      expect(tester.takeException(), isNull);
      expect(find.text('Next'), findsOneWidget);
      await _selectProvider(tester, 'DeepSeek');
      await _toConnection(tester);
      expect(_textOf(tester, _endpointField()), 'https://api.deepseek.com');
      expect(tester.takeException(), isNull);
    });
  });
}
