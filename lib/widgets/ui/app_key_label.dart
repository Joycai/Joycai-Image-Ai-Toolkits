import 'dart:io';
import 'dart:math' as math;

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
      return <String>['${key.alt ? '⌥' : ''}${key.shift ? '⇧' : ''}${key.primary ? '⌘' : ''}$main'];
    }
    return <String>[if (key.primary) 'Ctrl', if (key.shift) 'Shift', if (key.alt) 'Alt', main];
  }

  /// One chord, for a reminder rather than a reference — a context-menu
  /// row's trailing.
  ///
  /// The table's first chord, which is the canonical one. A menu row has
  /// about forty points for this; `Delete / Backspace / ⌘Backspace` is the
  /// truth and it does not fit, so the full set belongs in the `⌘/` panel
  /// and the settings list, where there is room for it.
  static String? menuHint(AppShortcut shortcut, {bool? macOS}) {
    if (shortcut.isDigitRange) return shortcutText(shortcut, macOS: macOS);
    for (final key in shortcut.keys) {
      final pieces = spell(key, macOS: macOS);
      if (pieces != null) return pieces.join('+');
    }
    return null;
  }

  /// A shortcut as one line of text — for a place that has a text slot
  /// rather than room for badges, which is what a context-menu row's
  /// trailing is (it shares that slot with counts, and the two should read
  /// alike).
  ///
  /// Null when nothing in this shortcut exists on this platform.
  static String? shortcutText(AppShortcut shortcut, {bool? macOS}) {
    if (shortcut.isDigitRange) {
      final pieces = spell(shortcut.keys.first, macOS: macOS);
      if (pieces == null) return null;
      final joined = pieces.join('+');
      return '${joined.substring(0, joined.length - 1)}'
          '1…${shortcut.keys.length}';
    }
    final seen = <String>{};
    final chords = <String>[
      for (final key in shortcut.keys)
        if (spell(key, macOS: macOS) case final pieces?)
          if (seen.add(pieces.join('+'))) pieces.join('+'),
    ];
    return chords.isEmpty ? null : chords.join(' / ');
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
    // A run of number keys reads as a range: eight badges would be correct
    // and useless.
    if (shortcut.isDigitRange) {
      final pieces = AppKeyLabel.spell(shortcut.keys.first);
      if (pieces == null) return const SizedBox.shrink();
      final collapsed = <String>[...pieces];
      final last = collapsed.last;
      collapsed[collapsed.length - 1] =
          '${last.substring(0, last.length - 1)}1…${shortcut.keys.length}';
      return AppKeyBadges(pieces: collapsed, dense: dense);
    }

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

    // A Wrap, not a Row: given less room than the whole set needs, the later
    // chords drop to a line of their own, flush right under the first. Given
    // unbounded room it is one line, exactly as a Row was. The `/` rides on
    // the chord before it, so a break falls after the separator, as it would
    // in prose.
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: AppSpace.s4,
      children: <Widget>[
        for (var i = 0; i < spellings.length; i++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AppKeyBadges(pieces: spellings[i], dense: dense),
              if (i < spellings.length - 1) _Separator(text: '/', dense: dense),
            ],
          ),
      ],
    );
  }
}

/// A shortcut's name on the left and its keys on the right — the row the
/// `⌘/` panel and the settings page's keyboard section are both made of.
///
/// The keys are the truth and are never cut: `Delete / Backspace / ⌘Backspace`
/// is three chords on a Mac, and the panel is the one place that promises to
/// show all of them. So the row does not let them push the name out, or past
/// its own edge. They take at most [_keysMaxShare] of the row; past that they
/// wrap onto a second line and the name keeps what is left, ellipsised there
/// if it must be.
///
/// That was measured, not assumed: in the panel's 316-point column the Mac
/// delete row is 239 points of key caps in Menlo, which left `Delete folder`
/// 67 points, and the harness' box font made it 356 points, which is wider
/// than the column.
class AppShortcutRow extends StatelessWidget {
  const AppShortcutRow({
    super.key,
    required this.label,
    required this.shortcut,
    required this.gap,
    this.dense = false,
  });

  /// The shortcut's name — usually one [Text], ellipsised by the caller.
  final Widget label;
  final AppShortcut shortcut;

  /// Between the name and the keys.
  final double gap;

  /// Passed through to [AppShortcutKeys].
  final bool dense;

  /// The most of the row, after [gap], the keys may take. The name keeps at
  /// least the rest — about six CJK characters in the panel's column.
  static const double _keysMaxShare = 0.75;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final keysMax =
            math.max(0.0, (constraints.maxWidth - gap) * _keysMaxShare);
        return Row(
          children: <Widget>[
            Expanded(child: label),
            SizedBox(width: gap),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: keysMax),
              child: AppShortcutKeys(shortcut, dense: dense),
            ),
          ],
        );
      },
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
