/// The one table of keyboard shortcuts (`00f` · plan §3).
///
/// Three surfaces read this list and **only** this list, so they cannot drift
/// apart: the bindings themselves (`Focus.onKeyEvent` / the `HardwareKeyboard`
/// handler in `main.dart`), discoverability (the `⌘/` panel, the trailing
/// badges in context menus, the settings page's keyboard section), and the
/// tests that pin both.
///
/// A key belongs to exactly one of three tiers, and tiers are claimed bottom
/// up — the focus region answers first, then the screen, then the app
/// ([ShortcutLayer]). The rule that makes the model worth having: **anything
/// that acts on a selection is a [ShortcutLayer.pane] key.** When the same
/// action is claimed at two tiers (the folder tree claimed `Delete` as a pane
/// key while the file grid claimed it at screen level) whoever holds focus
/// wins, which is how "Delete deleted the folder I had clicked ten minutes
/// ago" happened.
///
/// This file stays pure data plus pure functions: `core` may not import
/// `l10n`, so entries carry a [AppShortcut.labelKey] and the widgets resolve
/// it. Platform differences are resolved here and nowhere else: a caller asks
/// [AppShortcut.matches] whether an event is the shortcut, or
/// [AppShortcuts.primaryModifierLabel] how to spell the modifier, and never
/// writes `Platform.isMacOS ? isMetaPressed : isControlPressed` itself.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Which tier claims a key. Claimed bottom up: [pane], then [screen], then
/// [app].
enum ShortcutLayer {
  /// L0 — works wherever focus sits, as long as this window is frontmost and
  /// the current route is. Only keys that depend on no selection and no
  /// screen state belong here.
  app,

  /// L1 — the screen is frontmost *and* no text field is holding the keyboard
  /// (`isTextEditingFocused()`); there are no exceptions to that gate.
  screen,

  /// L2 — the key acts on the active focus region and nothing else.
  pane,
}

/// The screens that claim keys. Only the two the first phase covers; the task
/// queue, downloader, prompts and models pages are phase two.
enum ShortcutScreen { fileBrowser, workbench }

/// A focus region inside a screen. The file browser has [tree], [grid] and
/// [staging]; the workbench has [tree], [grid] and [config] (which claims no
/// keys this round).
///
/// One `FocusNode` per region, never one per card: a few hundred nodes cost
/// real memory and pollute the Tab order, and arrow-key navigation — the only
/// thing that would need per-card focus — is phase two.
enum ShortcutPane { tree, grid, staging, config }

/// One combination, written so it reads the same on every platform:
/// [primary] is `⌘` on macOS and `Ctrl` everywhere else.
///
/// Matching is **exact** about modifiers. `⇧⌘1` is not `⌘1`, which is what
/// lets `⌘⌥1…5` (the workbench's tool tabs) coexist with `⌘1…8` (the app's
/// destinations) instead of both firing.
class ShortcutKey {
  const ShortcutKey(
    this.key, {
    this.primary = false,
    this.shift = false,
    this.alt = false,
    this.macOSOnly = false,
  });

  final LogicalKeyboardKey key;

  /// `⌘` on macOS, `Ctrl` elsewhere.
  final bool primary;
  final bool shift;
  final bool alt;

  /// A chord that exists only on macOS, because it is a macOS convention and
  /// its literal translation elsewhere would mean something else. `⌘⌫` is the
  /// case: on a Mac it is Finder's move-to-Trash, while `Ctrl+Backspace` on
  /// Windows is "delete the previous word" and belongs to text fields.
  final bool macOSOnly;

  /// The activator for a `Shortcuts`/`CallbackShortcuts` map, and the value
  /// the uniqueness test compares.
  SingleActivator activator({bool? macOS}) {
    final mac = macOS ?? Platform.isMacOS;
    return SingleActivator(
      key,
      meta: primary && mac,
      control: primary && !mac,
      shift: shift,
      alt: alt,
    );
  }

  /// Whether [event] is this combination going down, with exactly these
  /// modifiers held and no others.
  ///
  /// On macOS a held `⌃` always disqualifies: `⌃A`/`⌃E`/`⌃F`/`⌃D` are text
  /// editing there, and this table uses `⌘` on macOS precisely so it never
  /// has to fight them.
  bool matches(KeyEvent event, {bool? macOS, HardwareKeyboard? keyboard}) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != key) return false;

    final hw = keyboard ?? HardwareKeyboard.instance;
    final mac = macOS ?? Platform.isMacOS;
    if (macOSOnly && !mac) return false;
    final primaryHeld = mac ? hw.isMetaPressed : hw.isControlPressed;
    final strayHeld = mac ? hw.isControlPressed : hw.isMetaPressed;

    if (primaryHeld != primary) return false;
    if (strayHeld) return false;
    if (hw.isShiftPressed != shift) return false;
    if (hw.isAltPressed != alt) return false;
    return true;
  }

  /// Whether this chord exists at all on the given platform.
  bool existsOn({required bool macOS}) => macOS || !macOSOnly;

  @override
  bool operator ==(Object other) =>
      other is ShortcutKey &&
      other.key == key &&
      other.primary == primary &&
      other.shift == shift &&
      other.alt == alt &&
      other.macOSOnly == macOSOnly;

  @override
  int get hashCode => Object.hash(key, primary, shift, alt, macOSOnly);

  @override
  String toString() => '${primary ? 'Primary+' : ''}${shift ? 'Shift+' : ''}'
      '${alt ? 'Alt+' : ''}${key.keyLabel}${macOSOnly ? ' (macOS only)' : ''}';
}

/// One row of the table: an action, the keys that trigger it, and where it is
/// claimed.
class AppShortcut {
  const AppShortcut({
    required this.id,
    required this.layer,
    required this.keys,
    required this.labelKey,
    this.screens = const <ShortcutScreen>{},
    this.panes = const <ShortcutPane>{},
  });

  /// Stable identity, used by [AppShortcutIds] and by the tests. Never shown
  /// to a user.
  final String id;

  final ShortcutLayer layer;

  /// Every combination that triggers the action: `F5` and `⌘R` both refresh,
  /// `Delete` and `⌫` both delete (on a Mac keyboard the main-block key is
  /// `⌫`, so the two are always registered together).
  final List<ShortcutKey> keys;

  /// The `AppLocalizations` getter name the UI resolves — `core` cannot
  /// import `l10n`, so the string itself lives on the widget side.
  final String labelKey;

  /// Which screens claim it. Empty for [ShortcutLayer.app].
  final Set<ShortcutScreen> screens;

  /// Which focus regions claim it. Empty except for [ShortcutLayer.pane].
  final Set<ShortcutPane> panes;

  /// Whether this row's chords are a run of number keys — `⌘1…8`, `⌘⌥1…5`.
  ///
  /// Eight chords is what the table holds and one range is what a reader
  /// wants; every surface that draws keys collapses these the same way,
  /// which is why the question is answered here rather than by each of them.
  bool get isDigitRange {
    if (keys.length < 3) return false;
    const digits = <LogicalKeyboardKey>[
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];
    for (var i = 0; i < keys.length; i++) {
      if (keys[i].key != digits[i]) return false;
      if (keys[i].primary != keys.first.primary) return false;
      if (keys[i].shift != keys.first.shift) return false;
      if (keys[i].alt != keys.first.alt) return false;
    }
    return true;
  }

  /// Whether [event] triggers this action right now.
  bool matches(KeyEvent event, {bool? macOS, HardwareKeyboard? keyboard}) =>
      keys.any((k) => k.matches(event, macOS: macOS, keyboard: keyboard));

  /// The scopes this row occupies. Two rows may share a combination only if
  /// they share no scope — `Esc` exits the search at screen level and clears
  /// the selection at pane level, which is the `Esc` ladder (plan §2b), not a
  /// collision.
  Iterable<String> get scopeKeys sync* {
    switch (layer) {
      case ShortcutLayer.app:
        yield 'app';
      case ShortcutLayer.screen:
        for (final s in screens) {
          yield 'screen:${s.name}';
        }
      case ShortcutLayer.pane:
        for (final s in screens) {
          for (final p in panes) {
            yield 'pane:${s.name}:${p.name}';
          }
        }
    }
  }
}

/// The ids, so lookups are not stringly typed at the call sites.
abstract final class AppShortcutIds {
  static const navigateToDestination = 'navigateToDestination';
  static const showShortcutPanel = 'showShortcutPanel';
  static const openSettings = 'openSettings';

  static const focusSearch = 'focusSearch';
  static const refresh = 'refresh';
  static const toggleLeftPanel = 'toggleLeftPanel';
  static const toggleStaging = 'toggleStaging';
  static const toggleConfigPanel = 'toggleConfigPanel';
  static const exitSearch = 'exitSearch';
  static const selectWorkbenchTool = 'selectWorkbenchTool';

  static const preview = 'preview';
  static const rename = 'rename';
  static const delete = 'delete';
  static const renameFolder = 'renameFolder';
  static const deleteFolder = 'deleteFolder';
  static const selectAll = 'selectAll';
  static const clearSelection = 'clearSelection';
  static const copyFileName = 'copyFileName';
  static const revealInFileManager = 'revealInFileManager';
  static const openWithSystem = 'openWithSystem';
  static const newSubfolder = 'newSubfolder';

  /// Every id above. `AppShortcuts.byId` throws on a miss and the ids are
  /// plain strings, so a constant with no row behind it would only show up as
  /// a `StateError` on the next keystroke — this list is what lets a test
  /// catch it instead. Dart cannot enumerate statics, so it is written out.
  static const List<String> all = <String>[
    navigateToDestination,
    showShortcutPanel,
    openSettings,
    focusSearch,
    refresh,
    toggleLeftPanel,
    toggleStaging,
    toggleConfigPanel,
    exitSearch,
    selectWorkbenchTool,
    preview,
    rename,
    delete,
    renameFolder,
    deleteFolder,
    selectAll,
    clearSelection,
    copyFileName,
    revealInFileManager,
    openWithSystem,
    newSubfolder,
  ];
}

const _bothFileScreens = {ShortcutScreen.fileBrowser, ShortcutScreen.workbench};

/// What deletes, everywhere something can be deleted.
///
/// `Delete` and `⌫` are always a pair — on a Mac keyboard the main-block key
/// is `⌫`. `⌘⌫` is there because it is *the* move-to-Trash chord on macOS and
/// exact modifier matching would otherwise drop it; Finder users reach for it
/// without thinking. Windows' `⇧Delete` is deliberately **not** bound: there
/// it means "skip the recycle bin", and this app asks that question in the
/// confirmation dialog instead, so binding it to the same trash-first action
/// would teach the wrong thing.
const _deleteChords = <ShortcutKey>[
  ShortcutKey(LogicalKeyboardKey.delete),
  ShortcutKey(LogicalKeyboardKey.backspace),
  ShortcutKey(LogicalKeyboardKey.backspace, primary: true, macOSOnly: true),
];

abstract final class AppShortcuts {
  /// Whether this platform gets shortcuts at all. A phone has no keyboard to
  /// register against; an iPad with an external one is phase two, and needs
  /// its own thinking (no `⌘` on many of them).
  static bool get registersShortcuts => !(Platform.isAndroid || Platform.isIOS);

  /// How the primary modifier is spelled in a label.
  static String get primaryModifierLabel => Platform.isMacOS ? '⌘' : 'Ctrl';

  // The one modifier deliberately *not* in this table: `AppCopyModifier`
  // (`widgets/drag/app_drag_session.dart`) reads `⌥` on macOS and `Ctrl`
  // elsewhere for drag-to-copy. That is the platform's drag convention, not a
  // shortcut — it has no key-down action and never appears in the panel.


  /// The table. Order is the reading order of the `⌘/` panel and of the
  /// settings section.
  static const List<AppShortcut> all = <AppShortcut>[
    // ── L0 · application ────────────────────────────────────────────────
    AppShortcut(
      id: AppShortcutIds.navigateToDestination,
      layer: ShortcutLayer.app,
      labelKey: 'shortcutNavigateToDestination',
      // Order matches `AppDestination`; the index is the destination.
      keys: [
        ShortcutKey(LogicalKeyboardKey.digit1, primary: true),
        ShortcutKey(LogicalKeyboardKey.digit2, primary: true),
        ShortcutKey(LogicalKeyboardKey.digit3, primary: true),
        ShortcutKey(LogicalKeyboardKey.digit4, primary: true),
        ShortcutKey(LogicalKeyboardKey.digit5, primary: true),
        ShortcutKey(LogicalKeyboardKey.digit6, primary: true),
        ShortcutKey(LogicalKeyboardKey.digit7, primary: true),
        ShortcutKey(LogicalKeyboardKey.digit8, primary: true),
      ],
    ),
    AppShortcut(
      id: AppShortcutIds.showShortcutPanel,
      layer: ShortcutLayer.app,
      labelKey: 'shortcutShowShortcutPanel',
      // Both forms: `⇧⌘/` is what a US-layout user presses when they think
      // "Cmd+?", and it costs nothing to answer it.
      keys: [
        ShortcutKey(LogicalKeyboardKey.slash, primary: true),
        ShortcutKey(LogicalKeyboardKey.slash, primary: true, shift: true),
      ],
    ),
    AppShortcut(
      id: AppShortcutIds.openSettings,
      layer: ShortcutLayer.app,
      labelKey: 'shortcutOpenSettings',
      keys: [ShortcutKey(LogicalKeyboardKey.comma, primary: true)],
    ),

    // ── L1 · screen ─────────────────────────────────────────────────────
    AppShortcut(
      id: AppShortcutIds.focusSearch,
      layer: ShortcutLayer.screen,
      labelKey: 'shortcutFocusSearch',
      screens: {ShortcutScreen.fileBrowser},
      keys: [ShortcutKey(LogicalKeyboardKey.keyF, primary: true)],
    ),
    AppShortcut(
      id: AppShortcutIds.refresh,
      layer: ShortcutLayer.screen,
      labelKey: 'shortcutRefresh',
      screens: _bothFileScreens,
      keys: [
        ShortcutKey(LogicalKeyboardKey.f5),
        ShortcutKey(LogicalKeyboardKey.keyR, primary: true),
      ],
    ),
    AppShortcut(
      id: AppShortcutIds.toggleLeftPanel,
      layer: ShortcutLayer.screen,
      labelKey: 'shortcutToggleLeftPanel',
      screens: _bothFileScreens,
      keys: [ShortcutKey(LogicalKeyboardKey.backslash, primary: true)],
    ),
    // `⇧⌘\` is the right-hand column on both screens, but the column is not
    // the same thing — staging in the browser, the run parameters in the
    // workbench — so it is two rows with one chord. Same scope rule as `Esc`:
    // different scopes may share a chord, and the panel then names each one
    // correctly instead of calling both "the right panel".
    AppShortcut(
      id: AppShortcutIds.toggleStaging,
      layer: ShortcutLayer.screen,
      labelKey: 'shortcutToggleStaging',
      screens: {ShortcutScreen.fileBrowser},
      keys: [
        ShortcutKey(LogicalKeyboardKey.backslash, primary: true, shift: true),
      ],
    ),
    AppShortcut(
      id: AppShortcutIds.toggleConfigPanel,
      layer: ShortcutLayer.screen,
      labelKey: 'shortcutToggleConfigPanel',
      screens: {ShortcutScreen.workbench},
      keys: [
        ShortcutKey(LogicalKeyboardKey.backslash, primary: true, shift: true),
      ],
    ),
    AppShortcut(
      id: AppShortcutIds.exitSearch,
      layer: ShortcutLayer.screen,
      labelKey: 'shortcutExitSearch',
      screens: {ShortcutScreen.fileBrowser},
      keys: [ShortcutKey(LogicalKeyboardKey.escape)],
    ),
    AppShortcut(
      id: AppShortcutIds.selectWorkbenchTool,
      layer: ShortcutLayer.screen,
      labelKey: 'shortcutSelectWorkbenchTool',
      screens: {ShortcutScreen.workbench},
      // Gallery / comparator / mask / crop / assistant, in `WorkbenchTab`
      // order. `⌥` keeps them clear of `⌘1…8`.
      keys: [
        ShortcutKey(LogicalKeyboardKey.digit1, primary: true, alt: true),
        ShortcutKey(LogicalKeyboardKey.digit2, primary: true, alt: true),
        ShortcutKey(LogicalKeyboardKey.digit3, primary: true, alt: true),
        ShortcutKey(LogicalKeyboardKey.digit4, primary: true, alt: true),
        ShortcutKey(LogicalKeyboardKey.digit5, primary: true, alt: true),
      ],
    ),

    // ── L2 · focus region · the same keys on both screens ───────────────
    AppShortcut(
      id: AppShortcutIds.preview,
      layer: ShortcutLayer.pane,
      labelKey: 'shortcutPreview',
      screens: _bothFileScreens,
      panes: {ShortcutPane.grid},
      keys: [
        ShortcutKey(LogicalKeyboardKey.enter),
        ShortcutKey(LogicalKeyboardKey.numpadEnter),
      ],
    ),
    AppShortcut(
      id: AppShortcutIds.rename,
      layer: ShortcutLayer.pane,
      labelKey: 'shortcutRename',
      screens: _bothFileScreens,
      panes: {ShortcutPane.grid},
      keys: [ShortcutKey(LogicalKeyboardKey.f2)],
    ),
    AppShortcut(
      id: AppShortcutIds.delete,
      layer: ShortcutLayer.pane,
      labelKey: 'shortcutDelete',
      screens: _bothFileScreens,
      panes: {ShortcutPane.grid},
      keys: _deleteChords,
    ),
    // The tree renames and deletes *folders*, which is a different act with a
    // different confirmation — and only in the file browser: the workbench
    // shares the tree widget but manages no folders there (`useFileBrowserState`
    // gates it, plan §4b).
    AppShortcut(
      id: AppShortcutIds.renameFolder,
      layer: ShortcutLayer.pane,
      labelKey: 'shortcutRenameFolder',
      screens: {ShortcutScreen.fileBrowser},
      panes: {ShortcutPane.tree},
      keys: [ShortcutKey(LogicalKeyboardKey.f2)],
    ),
    AppShortcut(
      id: AppShortcutIds.deleteFolder,
      layer: ShortcutLayer.pane,
      labelKey: 'shortcutDeleteFolder',
      screens: {ShortcutScreen.fileBrowser},
      panes: {ShortcutPane.tree},
      keys: _deleteChords,
    ),
    AppShortcut(
      id: AppShortcutIds.selectAll,
      layer: ShortcutLayer.pane,
      labelKey: 'shortcutSelectAll',
      screens: _bothFileScreens,
      panes: {ShortcutPane.grid},
      keys: [ShortcutKey(LogicalKeyboardKey.keyA, primary: true)],
    ),
    AppShortcut(
      id: AppShortcutIds.clearSelection,
      layer: ShortcutLayer.pane,
      labelKey: 'shortcutClearSelection',
      screens: _bothFileScreens,
      panes: {ShortcutPane.grid},
      keys: [ShortcutKey(LogicalKeyboardKey.escape)],
    ),
    AppShortcut(
      id: AppShortcutIds.copyFileName,
      layer: ShortcutLayer.pane,
      labelKey: 'shortcutCopyFileName',
      screens: _bothFileScreens,
      panes: {ShortcutPane.grid},
      keys: [ShortcutKey(LogicalKeyboardKey.keyC, primary: true, shift: true)],
    ),
    AppShortcut(
      id: AppShortcutIds.revealInFileManager,
      layer: ShortcutLayer.pane,
      labelKey: 'shortcutRevealInFileManager',
      screens: _bothFileScreens,
      panes: {ShortcutPane.grid},
      keys: [ShortcutKey(LogicalKeyboardKey.keyR, primary: true, alt: true)],
    ),
    AppShortcut(
      id: AppShortcutIds.openWithSystem,
      layer: ShortcutLayer.pane,
      labelKey: 'shortcutOpenWithSystem',
      screens: {ShortcutScreen.fileBrowser},
      panes: {ShortcutPane.grid},
      keys: [ShortcutKey(LogicalKeyboardKey.keyO, primary: true)],
    ),
    AppShortcut(
      id: AppShortcutIds.newSubfolder,
      layer: ShortcutLayer.pane,
      labelKey: 'shortcutNewSubfolder',
      screens: {ShortcutScreen.fileBrowser},
      panes: {ShortcutPane.tree},
      keys: [ShortcutKey(LogicalKeyboardKey.keyN, primary: true, shift: true)],
    ),
  ];

  static AppShortcut byId(String id) => all.firstWhere((s) => s.id == id);

  /// The app-level rows, in table order.
  static Iterable<AppShortcut> get appLevel =>
      all.where((s) => s.layer == ShortcutLayer.app);

  /// The rows [screen] claims at screen level.
  static Iterable<AppShortcut> forScreen(ShortcutScreen screen) => all.where(
      (s) => s.layer == ShortcutLayer.screen && s.screens.contains(screen));

  /// The rows the [pane] of [screen] claims.
  static Iterable<AppShortcut> forPane(
    ShortcutScreen screen,
    ShortcutPane pane,
  ) =>
      all.where((s) =>
          s.layer == ShortcutLayer.pane &&
          s.screens.contains(screen) &&
          s.panes.contains(pane));

  /// The destination [event] jumps to (`⌘1…8`), or -1.
  static int navigationIndexFor(
    KeyEvent event, {
    bool? macOS,
    HardwareKeyboard? keyboard,
  }) =>
      byId(AppShortcutIds.navigateToDestination).keys.indexWhere(
          (k) => k.matches(event, macOS: macOS, keyboard: keyboard));

  /// The workbench tool tab [event] selects (`⌘⌥1…5`), or -1.
  static int workbenchToolIndexFor(
    KeyEvent event, {
    bool? macOS,
    HardwareKeyboard? keyboard,
  }) =>
      byId(AppShortcutIds.selectWorkbenchTool).keys.indexWhere(
          (k) => k.matches(event, macOS: macOS, keyboard: keyboard));
}
