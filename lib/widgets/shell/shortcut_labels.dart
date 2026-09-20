import '../../core/app_shortcuts.dart';
import '../../l10n/app_localizations.dart';

/// What each row of [AppShortcuts.all] is called, and what each focus region
/// is called.
///
/// `core` may not import `l10n`, so the table carries a
/// [AppShortcut.labelKey] and the words live here — one switch, and a test
/// that walks the registry proves none is missing. The panel, the context
/// menus and the settings section all read this, so a key cannot be called
/// one thing in a menu and another in a list.
String shortcutLabel(AppLocalizations l10n, AppShortcut shortcut) =>
    switch (shortcut.id) {
      AppShortcutIds.navigateToDestination => l10n.shortcutNavigateToDestination,
      AppShortcutIds.showShortcutPanel => l10n.shortcutShowShortcutPanel,
      AppShortcutIds.openSettings => l10n.shortcutOpenSettings,
      AppShortcutIds.focusSearch => l10n.shortcutFocusSearch,
      AppShortcutIds.refresh => l10n.shortcutRefresh,
      AppShortcutIds.toggleLeftPanel => l10n.shortcutToggleLeftPanel,
      AppShortcutIds.toggleStaging => l10n.shortcutToggleStaging,
      AppShortcutIds.toggleConfigPanel => l10n.shortcutToggleConfigPanel,
      AppShortcutIds.exitSearch => l10n.shortcutExitSearch,
      AppShortcutIds.selectWorkbenchTool => l10n.shortcutSelectWorkbenchTool,
      AppShortcutIds.preview => l10n.shortcutPreview,
      AppShortcutIds.rename => l10n.shortcutRename,
      AppShortcutIds.delete => l10n.shortcutDelete,
      AppShortcutIds.renameFolder => l10n.shortcutRenameFolder,
      AppShortcutIds.deleteFolder => l10n.shortcutDeleteFolder,
      AppShortcutIds.selectAll => l10n.shortcutSelectAll,
      AppShortcutIds.clearSelection => l10n.shortcutClearSelection,
      AppShortcutIds.copyFileName => l10n.shortcutCopyFileName,
      AppShortcutIds.revealInFileManager => l10n.shortcutRevealInFileManager,
      AppShortcutIds.openWithSystem => l10n.shortcutOpenWithSystem,
      AppShortcutIds.newSubfolder => l10n.shortcutNewSubfolder,
      // Unreachable while `app_shortcuts_test` passes: it walks
      // `AppShortcutIds.all` through here and fails on anything that lands
      // in this arm.
      _ => shortcut.id,
    };

/// What a focus region is called on a given screen.
///
/// The middle region is a file grid in the browser and the gallery in the
/// workbench — same role, different word, because that is what each screen
/// calls the thing on screen.
String shortcutPaneLabel(
  AppLocalizations l10n,
  ShortcutScreen screen,
  ShortcutPane pane,
) =>
    switch ((screen, pane)) {
      (_, ShortcutPane.tree) => l10n.shortcutsPaneTree,
      (ShortcutScreen.workbench, ShortcutPane.grid) => l10n.shortcutsPaneGallery,
      (_, ShortcutPane.grid) => l10n.shortcutsPaneGrid,
      (_, ShortcutPane.staging) => l10n.shortcutsPaneStaging,
      (_, ShortcutPane.config) => l10n.shortcutToggleConfigPanel,
    };
