import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:joycai_image_ai_toolkits/core/app_shortcuts.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/widgets/shell/shortcut_labels.dart';

/// The join between the table and the words for it.
///
/// `core` cannot import `l10n`, so a row carries a `labelKey` and the switch
/// in `shortcut_labels.dart` turns it into a sentence. Nothing in the
/// language checks that the switch covers the table — it has a default arm,
/// because a switch over strings must — so a row added without a label would
/// quietly show its own id to the user, in every language. This is the check
/// that stops that.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final locales = <Locale>[
    const Locale('en'),
    const Locale('zh'),
    const Locale('zh', 'Hant'),
    const Locale('ja'),
  ];

  for (final locale in locales) {
    test('every shortcut has a label in $locale', () async {
      final l10n = await AppLocalizations.delegate.load(locale);

      for (final shortcut in AppShortcuts.all) {
        final label = shortcutLabel(l10n, shortcut);
        expect(label, isNot(shortcut.id),
            reason: '${shortcut.id} fell through to the default arm — add it '
                'to the switch in widgets/shell/shortcut_labels.dart');
        expect(label.trim(), isNotEmpty, reason: shortcut.id);
      }
    });

    test('every focus region has a name in $locale', () async {
      final l10n = await AppLocalizations.delegate.load(locale);

      for (final screen in ShortcutScreen.values) {
        for (final pane in ShortcutPane.values) {
          expect(shortcutPaneLabel(l10n, screen, pane).trim(), isNotEmpty,
              reason: '$screen/$pane');
        }
      }
    });
  }

  test('the middle region is called what each screen calls it', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
    expect(
      shortcutPaneLabel(l10n, ShortcutScreen.workbench, ShortcutPane.grid),
      isNot(shortcutPaneLabel(l10n, ShortcutScreen.fileBrowser, ShortcutPane.grid)),
      reason: 'the same role, but the workbench calls it the gallery and the '
          'browser calls it the file grid — the panel should use the word '
          'the screen uses',
    );
  });
}
