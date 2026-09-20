import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_shortcuts.dart';
import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';

/// A keyboard shortcut, drawn (`00f` 规格 · 键位徽标).
///
/// The one place the app spells a key. Three surfaces use it — the `⌘/`
/// panel, the trailing of a context-menu row, and the settings page's
/// keyboard section — so a key cannot read one way in a menu and another in
/// a list, and none of them carries a hard-coded `'F2'` any more.
///
/// Platforms spell chords differently and the difference is not cosmetic:
///
/// * **macOS** writes the whole chord as one run of symbols with nothing
///   between them — `⇧⌘C`. Writing `⌘ + C` there is simply not how the
///   system does it.
/// * **Windows and Linux** name each key and join them with `+` —
///   `Ctrl + Shift + C`.
///
/// So macOS gets one badge per chord and the others get one badge per key.
/// Presentation only: it is not focusable and takes no pointer, and a screen
/// reader reads it as part of the row it sits in rather than as its own stop.
class AppKeyLabel extends StatelessWidget {
  const AppKeyLabel({super.key, required this.chord, this.dense = false});

  /// One chord.
  final ShortcutKey chord;

  /// Smaller, for a context-menu row where the label is the subject and the
  /// keys are a footnote.
  final bool dense;

  /// How one chord reads on this platform, as the pieces to draw.
  ///
  /// `null` where the chord does not exist here at all (`⌘⌫` off macOS).
  static List<String>? spell(ShortcutKey key, {bool? macOS}) {
    final mac = macOS ?? Platform.isMacOS;
    if (!key.existsOn(macOS: mac)) return null;

    final String main = _mainKeyLabel(key.key, macOS: mac);
    if (mac) {
      return <String>[
        '${key.alt ? '⌥' : ''}${key.shift ? '⇧' : ''}${key.primary ? '⌘' : ''}$main',
      ];
    }
    return <String>[
      if (key.primary) 'Ctrl',
      if (key.shift) 'Shift',
      if (key.alt) 'Alt',
      main,
    ];
  }

  /// The trigger key's own name. Ellipsised ranges (`1…8`) come from the
  /// caller, not from here.
  ///
  /// Modifiers get their symbols (`⌘⇧⌥`), the trigger gets its word. macOS
  /// menus do write `⌫`, `⌦` and `↩`, and the first draft did too — but those
  /// glyphs are missing from plenty of fonts, and a shortcut that renders as
  /// a tofu box teaches nothing. A word is unambiguous in every font and on
  /// every platform, which is worth more here than matching the system menu
  /// exactly.
  static String _mainKeyLabel(LogicalKeyboardKey key, {required bool macOS}) {
    if (key == LogicalKeyboardKey.backspace) return 'Backspace';
    if (key == LogicalKeyboardKey.delete) return 'Delete';
    if (key == LogicalKeyboardKey.enter) return 'Enter';
    if (key == LogicalKeyboardKey.numpadEnter) return 'Enter';
    if (key == LogicalKeyboardKey.escape) return 'Esc';
    if (key == LogicalKeyboardKey.backslash) return r'\';
    if (key == LogicalKeyboardKey.slash) return '/';
    if (key == LogicalKeyboardKey.comma) return ',';
    if (key == LogicalKeyboardKey.space) return 'Space';
    final String label = key.keyLabel;
    return label.length == 1 ? label.toUpperCase() : label;
  }

  @override
  Widget build(BuildContext context) {
    final pieces = spell(chord);
    if (pieces == null) return const SizedBox.shrink();
    return AppKeyBadges(pieces: pieces, dense: dense);
  }
}

/// Every chord one shortcut answers to, `/`-separated — `F5 / ⌘R`.
///
/// Chords that do not exist on this platform are left out rather than drawn
/// wrong: `⌘⌫` is Finder's move-to-Trash and has no Windows counterpart, so
/// a Windows user is not told about a key they do not have.
class AppShortcutKeys extends StatelessWidget {
  const AppShortcutKeys(this.shortcut, {super.key, this.dense = false});

  final AppShortcut shortcut;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    // Deduplicated: `Enter` and the numpad's `Enter` are two rows in the
    // table and one key to a reader, so the panel must not offer them as a
    // choice between identical things.
    final seen = <String>{};
    final spellings = <List<String>>[
      for (final key in shortcut.keys)
        if (AppKeyLabel.spell(key) case final pieces?)
          if (seen.add(pieces.join('+'))) pieces,
    ];
    if (spellings.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var i = 0; i < spellings.length; i++) ...[
          if (i > 0) _Separator(text: '/', dense: dense),
          AppKeyBadges(pieces: spellings[i], dense: dense),
        ],
      ],
    );
  }
}

/// One chord already spelled out: a single badge on macOS, `Ctrl + Shift + C`
/// elsewhere. Public so a caller with a chord the table cannot express — a
/// range like `⌘1…8` — can still draw it in the same ink.
class AppKeyBadges extends StatelessWidget {
  const AppKeyBadges({super.key, required this.pieces, this.dense = false});

  final List<String> pieces;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var i = 0; i < pieces.length; i++) ...[
          if (i > 0) _Separator(text: '+', dense: dense),
          _Badge(text: pieces[i], dense: dense),
        ],
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.dense});

  final String text;
  final bool dense;

  /// `00f` 规格: 18 high, 18 wide at the least, 5 of padding either side.
  static const double _height = 18;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: _height,
      constraints: const BoxConstraints(minWidth: _height),
      padding: EdgeInsets.symmetric(horizontal: dense ? 4 : 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.07),
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        text,
        maxLines: 1,
        style: Theme.of(context).textTheme.labelSmall!.mono.copyWith(
              fontSize: dense ? 10.5 : 11,
              height: 1,
              fontWeight: FontWeight.w500,
              color: scheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator({required this.text, required this.dense});

  final String text;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall!.mono.copyWith(
              fontSize: dense ? 9.5 : 10,
              height: 1,
              color: scheme.outline,
            ),
      ),
    );
  }
}
