import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_shortcuts.dart';

/// The shape of the shortcut table, and the matching rule underneath it.
///
/// The uniqueness test is the one that earns its keep: a second row claiming a
/// combination inside one scope is exactly the bug this round is fixing (the
/// folder tree and the file grid both answering `Delete`), and it is invisible
/// from either call site. Scopes are checked on both platforms, because the
/// modifier differs and a collision can exist on one and not the other.
void main() {
  group('the table', () {
    test('ids are unique', () {
      final ids = AppShortcuts.all.map((s) => s.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('every id in AppShortcutIds is in the table, and vice versa', () {
      // Both directions, because both fail silently. An id constant with no
      // row behind it makes `byId` throw a StateError from inside a key
      // handler — on every keystroke, and invisibly to the analyzer, since
      // the ids are plain strings. A row no constant names is dead data.
      expect(
        AppShortcutIds.all.toSet(),
        AppShortcuts.all.map((s) => s.id).toSet(),
      );
      for (final id in AppShortcutIds.all) {
        expect(() => AppShortcuts.byId(id), returnsNormally, reason: id);
      }
    });

    test('label keys are present and unique', () {
      final labels = AppShortcuts.all.map((s) => s.labelKey).toList();
      expect(labels.where((l) => l.isEmpty), isEmpty);
      expect(labels.toSet().length, labels.length);
    });

    test('every row carries at least one key', () {
      for (final s in AppShortcuts.all) {
        expect(s.keys, isNotEmpty, reason: s.id);
      }
    });

    test('a row is scoped to its layer', () {
      for (final s in AppShortcuts.all) {
        switch (s.layer) {
          case ShortcutLayer.app:
            expect(s.screens, isEmpty, reason: '${s.id} is app level');
            expect(s.panes, isEmpty, reason: '${s.id} is app level');
          case ShortcutLayer.screen:
            expect(s.screens, isNotEmpty, reason: '${s.id} names no screen');
            expect(s.panes, isEmpty,
                reason: '${s.id} is screen level but names a pane — selection '
                    'keys belong to the pane layer (plan D1)');
          case ShortcutLayer.pane:
            expect(s.screens, isNotEmpty, reason: '${s.id} names no screen');
            expect(s.panes, isNotEmpty, reason: '${s.id} names no pane');
        }
        expect(s.scopeKeys, isNotEmpty, reason: s.id);
      }
    });

    for (final macOS in [true, false]) {
      test('no two rows share a chord inside one scope '
          '(${macOS ? 'macOS' : 'Windows/Linux'})', () {
        // Keyed on `ShortcutKey`, which has value equality. NOT on the
        // `SingleActivator` it builds: `SingleActivator` inherits identity
        // equality from Object, so a map keyed on freshly built ones never
        // finds anything and this test would pass no matter what the table
        // said. Both platforms run because `macOSOnly` chords exist on one
        // and not the other.
        final claimed = <String, Map<ShortcutKey, String>>{};
        final collisions = <String>[];

        for (final shortcut in AppShortcuts.all) {
          for (final scope in shortcut.scopeKeys) {
            final inScope = claimed.putIfAbsent(scope, () => {});
            for (final key in shortcut.keys) {
              if (!key.existsOn(macOS: macOS)) continue;
              final owner = inScope[key];
              if (owner != null) {
                collisions.add('$scope: $key claimed by both $owner and '
                    '${shortcut.id}');
              } else {
                inScope[key] = shortcut.id;
              }
            }
          }
        }

        expect(collisions, isEmpty,
            reason: 'two rows answer the same chord in the same scope, so '
                'which one runs depends on registration order:\n'
                '  ${collisions.join('\n  ')}');
      });
    }

    test('Delete and Backspace are always registered together', () {
      for (final s in AppShortcuts.all) {
        final bare = s.keys
            .where((k) => !k.primary && !k.shift && !k.alt)
            .map((k) => k.key)
            .toSet();
        expect(
          bare.contains(LogicalKeyboardKey.delete),
          bare.contains(LogicalKeyboardKey.backspace),
          reason: '${s.id}: on a Mac keyboard the main-block key is Backspace, '
              'so a row bound to one must be bound to the other',
        );
      }
    });

    test('macOS keeps Finder\'s Cmd+Backspace, Windows gets no alias', () {
      for (final id in [AppShortcutIds.delete, AppShortcutIds.deleteFolder]) {
        final chord = AppShortcuts.byId(id).keys.singleWhere((k) => k.primary);
        expect(chord.key, LogicalKeyboardKey.backspace);
        expect(chord.macOSOnly, isTrue,
            reason: 'Ctrl+Backspace means "delete the previous word" off '
                'macOS and belongs to text fields, not to a file grid');
        expect(chord.existsOn(macOS: false), isFalse);
      }
    });

    test('Esc lives at two tiers on purpose — the ladder, not a collision', () {
      final esc = AppShortcuts.all
          .where((s) => s.keys
              .any((k) => k.key == LogicalKeyboardKey.escape && !k.primary))
          .map((s) => s.id)
          .toSet();
      expect(esc, {AppShortcutIds.exitSearch, AppShortcutIds.clearSelection});
      expect(AppShortcuts.byId(AppShortcutIds.exitSearch).layer,
          ShortcutLayer.screen);
      expect(AppShortcuts.byId(AppShortcutIds.clearSelection).layer,
          ShortcutLayer.pane);
    });

    test('the file operations are claimed on both screens', () {
      const shared = [
        AppShortcutIds.preview,
        AppShortcutIds.rename,
        AppShortcutIds.delete,
        AppShortcutIds.selectAll,
        AppShortcutIds.clearSelection,
        AppShortcutIds.copyFileName,
        AppShortcutIds.revealInFileManager,
      ];
      // …and the folder rows are not shared: the workbench uses the same tree
      // widget but manages no folders there.
      for (final id in [
        AppShortcutIds.renameFolder,
        AppShortcutIds.deleteFolder,
        AppShortcutIds.newSubfolder,
      ]) {
        expect(AppShortcuts.byId(id).screens, {ShortcutScreen.fileBrowser},
            reason: id);
      }
      for (final id in shared) {
        expect(
          AppShortcuts.byId(id).screens,
          {ShortcutScreen.fileBrowser, ShortcutScreen.workbench},
          reason: '$id is the whole point of this round: one key, one meaning, '
              'on both screens',
        );
      }
    });

    test('the workbench tree claims nothing', () {
      expect(
          AppShortcuts.forPane(ShortcutScreen.workbench, ShortcutPane.tree),
          isEmpty,
          reason: 'it is the same widget as the browser tree but with folder '
              'management switched off');
    });

    test('the grid claims the selection keys on both screens', () {
      for (final screen in ShortcutScreen.values) {
        final ids =
            AppShortcuts.forPane(screen, ShortcutPane.grid).map((s) => s.id);
        expect(
          ids,
          containsAll([
            AppShortcutIds.preview,
            AppShortcutIds.rename,
            AppShortcutIds.delete,
            AppShortcutIds.selectAll,
            AppShortcutIds.clearSelection,
          ]),
          reason: '$screen',
        );
      }
    });
  });

  group('matching', () {
    // A KeyDownEvent carries the key; the modifiers come from the keyboard
    // state, so both are driven here.
    KeyEvent down(LogicalKeyboardKey key) => KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyA,
          logicalKey: key,
          timeStamp: Duration.zero,
        );

    /// A keyboard with exactly [held] down.
    HardwareKeyboard keyboardWith(Set<LogicalKeyboardKey> held) {
      final keyboard = HardwareKeyboard();
      var stamp = Duration.zero;
      for (final key in held) {
        stamp += const Duration(milliseconds: 1);
        keyboard.handleKeyEvent(KeyDownEvent(
          physicalKey: _physicalFor(key),
          logicalKey: key,
          timeStamp: stamp,
        ));
      }
      return keyboard;
    }

    test('the primary modifier is Cmd on macOS and Ctrl elsewhere', () {
      final selectAll = AppShortcuts.byId(AppShortcutIds.selectAll);
      final withMeta = keyboardWith({LogicalKeyboardKey.metaLeft});
      final withControl = keyboardWith({LogicalKeyboardKey.controlLeft});

      expect(
          selectAll.matches(down(LogicalKeyboardKey.keyA),
              macOS: true, keyboard: withMeta),
          isTrue);
      expect(
          selectAll.matches(down(LogicalKeyboardKey.keyA),
              macOS: true, keyboard: withControl),
          isFalse,
          reason: 'Ctrl+A is a text-editing binding on macOS; this table never '
              'claims it there');
      expect(
          selectAll.matches(down(LogicalKeyboardKey.keyA),
              macOS: false, keyboard: withControl),
          isTrue);
      expect(
          selectAll.matches(down(LogicalKeyboardKey.keyA),
              macOS: false, keyboard: withMeta),
          isFalse);
    });

    test('an extra modifier does not match', () {
      final selectAll = AppShortcuts.byId(AppShortcutIds.selectAll);
      final metaShift = keyboardWith(
          {LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.shiftLeft});
      expect(
          selectAll.matches(down(LogicalKeyboardKey.keyA),
              macOS: true, keyboard: metaShift),
          isFalse);
    });

    test('Cmd+1…8 navigates, Cmd+Alt+1…5 does not', () {
      final meta = keyboardWith({LogicalKeyboardKey.metaLeft});
      final metaAlt =
          keyboardWith({LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.altLeft});

      const digits = [
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit5,
        LogicalKeyboardKey.digit6,
        LogicalKeyboardKey.digit7,
        LogicalKeyboardKey.digit8,
      ];
      for (var i = 0; i < digits.length; i++) {
        expect(
          AppShortcuts.navigationIndexFor(down(digits[i]),
              macOS: true, keyboard: meta),
          i,
          reason: 'Cmd+${i + 1} is destination $i',
        );
      }

      // The workbench's tool tabs share the digits; only the modifier keeps
      // them apart, which is why matching is exact.
      expect(
          AppShortcuts.navigationIndexFor(down(LogicalKeyboardKey.digit1),
              macOS: true, keyboard: metaAlt),
          -1);
      expect(
          AppShortcuts.workbenchToolIndexFor(down(LogicalKeyboardKey.digit1),
              macOS: true, keyboard: metaAlt),
          0);
      expect(
          AppShortcuts.workbenchToolIndexFor(down(LogicalKeyboardKey.digit1),
              macOS: true, keyboard: meta),
          -1);
    });

    test('a key up never matches', () {
      final meta = keyboardWith({LogicalKeyboardKey.metaLeft});
      final up = KeyUpEvent(
        physicalKey: PhysicalKeyboardKey.keyA,
        logicalKey: LogicalKeyboardKey.keyA,
        timeStamp: const Duration(milliseconds: 2),
      );
      expect(
          AppShortcuts.byId(AppShortcutIds.selectAll)
              .matches(up, macOS: true, keyboard: meta),
          isFalse);
    });
  });
}

PhysicalKeyboardKey _physicalFor(LogicalKeyboardKey key) => switch (key) {
      LogicalKeyboardKey.metaLeft => PhysicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.controlLeft => PhysicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.shiftLeft => PhysicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.altLeft => PhysicalKeyboardKey.altLeft,
      _ => PhysicalKeyboardKey.keyA,
    };
