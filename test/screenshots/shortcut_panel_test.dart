// The ⌘/ panel, against the real app tree.
//
//   flutter test test/screenshots/shortcut_panel_test.dart
//
// Asserts, so it stays in the gate and is not tagged `screenshots`.
//
// The panel's whole claim is that it cannot lie: its rows come from
// `AppShortcuts` and nowhere else. The test that matters is therefore not
// "does it look right" but "is every row it shows a row the app actually
// answers, and does it name the region that owns the keyboard".

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:joycai_image_ai_toolkits/core/app_shortcuts.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/shell/shortcut_labels.dart';
import 'package:joycai_image_ai_toolkits/widgets/shell/shortcut_panel.dart';

import 'harness/fixture_env.dart';
import 'harness/fixture_seed.dart';
import 'harness/shoot.dart';
import 'harness/suite.dart';

void main() {
  final TestWidgetsFlutterBinding binding = TestWidgetsFlutterBinding.ensureInitialized();
  late FixtureEnv env;
  late AppLocalizations l10n;

  setUpAll(() async {
    env = installFixtureEnv(binding);
    await seedFixtures(env);
    await AppState().loadSettings();
    l10n = await AppLocalizations.delegate.load(const Locale('zh'));
    await Future<void>.delayed(const Duration(seconds: 1));
  });

  tearDownAll(() => env.dispose());

  final LogicalKeyboardKey primary =
      Platform.isMacOS ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;

  Future<void> pressPanelKey(WidgetTester tester) async {
    await tester.sendKeyDownEvent(primary);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(primary);
    await settle(tester, 12);
  }

  testWidgets('Cmd+/ opens the panel, Escape closes it', (WidgetTester tester) async {
    await mountApp(
      tester,
      env: env,
      screen: AppScreen.fileBrowser,
      size: const Size(1440, 900),
      label: 'shortcut-panel',
    );

    expect(find.byType(ShortcutPanel), findsNothing);
    await pressPanelKey(tester);
    expect(find.byType(ShortcutPanel), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester, 12);
    expect(find.byType(ShortcutPanel), findsNothing,
        reason: 'Escape closes it — the panel is a float, not a page');

    // And the same chord again is a toggle, not a second panel.
    await pressPanelKey(tester);
    expect(find.byType(ShortcutPanel), findsOneWidget);
    await pressPanelKey(tester);
    expect(find.byType(ShortcutPanel), findsNothing);
  });

  testWidgets('the panel shows the file browser\'s rows and nobody else\'s',
      (WidgetTester tester) async {
    await mountApp(
      tester,
      env: env,
      screen: AppScreen.fileBrowser,
      size: const Size(1440, 900),
      label: 'shortcut-panel-rows',
    );
    await pressPanelKey(tester);
    expect(find.byType(ShortcutPanel), findsOneWidget);

    // Every row the browser claims, at any tier, is named in the panel…
    final expected = <AppShortcut>[
      ...AppShortcuts.appLevel,
      ...AppShortcuts.forScreen(ShortcutScreen.fileBrowser),
      for (final pane in ShortcutPane.values)
        ...AppShortcuts.forPane(ShortcutScreen.fileBrowser, pane),
    ];
    expect(expected, isNotEmpty);
    for (final shortcut in expected) {
      expect(
        find.descendant(
          of: find.byType(ShortcutPanel),
          matching: find.text(shortcutLabel(l10n, shortcut)),
        ),
        findsWidgets,
        reason: '${shortcut.id} is bound on this screen but the panel does '
            'not mention it',
      );
    }

    // …and nothing that belongs only to the other screen is.
    final workbenchOnly = AppShortcuts.all.where((s) =>
        s.layer != ShortcutLayer.app &&
        s.screens.contains(ShortcutScreen.workbench) &&
        !s.screens.contains(ShortcutScreen.fileBrowser));
    expect(workbenchOnly, isNotEmpty, reason: 'there are such rows to check');
    for (final shortcut in workbenchOnly) {
      expect(
        find.descendant(
          of: find.byType(ShortcutPanel),
          matching: find.text(shortcutLabel(l10n, shortcut)),
        ),
        findsNothing,
        reason: '${shortcut.id} does nothing on this screen',
      );
    }

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester, 12);
  });

  testWidgets('Cmd+, goes to settings', (WidgetTester tester) async {
    await mountApp(
      tester,
      env: env,
      screen: AppScreen.fileBrowser,
      size: const Size(1440, 900),
      label: 'shortcut-settings-key',
    );
    expect(AppState().activeScreenIndex, AppScreen.fileBrowser.index);

    await tester.sendKeyDownEvent(primary);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(primary);
    await settle(tester, 12);

    expect(AppState().activeScreenIndex, AppScreen.settings.index,
        reason: 'the macOS habit, and the same destination as ⌘8');

    AppState().navigateToScreen(AppScreen.fileBrowser.index);
    await settle(tester);
  });

  testWidgets('the panel names the region that owns the keyboard',
      (WidgetTester tester) async {
    await mountApp(
      tester,
      env: env,
      screen: AppScreen.fileBrowser,
      size: const Size(1440, 900),
      label: 'shortcut-panel-active-pane',
    );

    // The grid is the active region on a freshly opened browser.
    await pressPanelKey(tester);
    expect(
      find.text(l10n.shortcutsActiveRegion(l10n.shortcutsPaneGrid)),
      findsOneWidget,
      reason: 'the panel teaches the rule by obeying it',
    );
    expect(find.textContaining(l10n.shortcutsInactiveRegion), findsWidgets,
        reason: 'and says the other regions are not the one listening');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester, 12);
  });
}
