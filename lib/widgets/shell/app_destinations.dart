import 'dart:io';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// The app's eight top-level destinations, in the order `Ctrl/⌘ + 1…8` maps
/// onto them.
///
/// One list, read by every navigation surface the shell draws — the title-bar
/// lens group on desktop, the 48px top bar on a tablet, the phone dock and its
/// "more" sheet — so the order, icons and labels cannot drift between them.
/// Screens themselves are resolved by `main.dart` from [AppDestination.index];
/// this file stays free of screen imports so the shell widgets can be tested
/// without building the app.
enum AppDestination {
  workbench(Icons.dashboard_outlined, Icons.dashboard),
  fileBrowser(Icons.folder_open_outlined, Icons.folder_open, desktopOnly: true),
  tasks(Icons.checklist_outlined, Icons.checklist, showsQueueBadge: true),
  downloader(Icons.cloud_download_outlined, Icons.cloud_download, desktopOnly: true),
  prompts(Icons.auto_awesome_outlined, Icons.auto_awesome),
  models(Icons.memory_outlined, Icons.memory),
  usage(Icons.analytics_outlined, Icons.analytics),
  settings(Icons.settings_outlined, Icons.settings);

  const AppDestination(
    this.icon,
    this.selectedIcon, {
    this.desktopOnly = false,
    this.showsQueueBadge = false,
  });

  final IconData icon;

  /// The filled glyph drawn for the current destination (`01 · 1b`: `ms f`).
  final IconData selectedIcon;

  /// Hidden on Android and iOS, where these screens have no file system to
  /// work on (`01 · 1g` 「更多」 sheet note).
  final bool desktopOnly;

  /// Carries the pending + running count (neutral, not red — red means a task
  /// failed).
  final bool showsQueueBadge;

  String label(AppLocalizations l10n) => switch (this) {
        AppDestination.workbench => l10n.workbench,
        AppDestination.fileBrowser => l10n.fileBrowser,
        AppDestination.tasks => l10n.tasks,
        AppDestination.downloader => l10n.downloader,
        AppDestination.prompts => l10n.prompts,
        AppDestination.models => l10n.models,
        AppDestination.usage => l10n.usage,
        AppDestination.settings => l10n.settings,
      };

  /// `Ctrl+3` / `⌘+3` — surfaced in the tooltip, the one place that says the
  /// shortcut exists.
  String get shortcutHint => '${Platform.isMacOS ? '⌘' : 'Ctrl'}+${index + 1}';

  /// Whether this platform offers the destination at all.
  static bool isAvailable(AppDestination d) =>
      !(d.desktopOnly && (Platform.isAndroid || Platform.isIOS));

  /// Every destination this platform offers, in shortcut order.
  static List<AppDestination> get available =>
      AppDestination.values.where(isAvailable).toList();

  /// The four the phone dock holds before its "more" cell (`01 · 1g`).
  static const List<AppDestination> dockPrimary = [
    AppDestination.workbench,
    AppDestination.tasks,
    AppDestination.prompts,
    AppDestination.models,
  ];
}
