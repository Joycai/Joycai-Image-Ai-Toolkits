import 'package:flutter/material.dart';

import '../../../core/app_shortcuts.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';

import '../../../widgets/shell/shortcut_labels.dart';
import '../../../widgets/ui/app_key_label.dart';
import 'settings_layout.dart';

/// `00f` 帧 5: every shortcut, read-only, in the order the `⌘/` panel uses.
///
/// The panel answers "what can I press *here, now*"; this answers "what does
/// this application have". Same table behind both — the rows are built from
/// [AppShortcuts.all], so a key that exists is listed and a key that is
/// listed exists.
///
/// Read-only on purpose this round: rebinding needs conflict detection and
/// somewhere to persist to, and neither is worth inventing before the table
/// has settled. The placeholder at the bottom says so rather than leaving a
/// blank where a control obviously belongs.
class KeyboardSection extends StatelessWidget {
  const KeyboardSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return SettingsSections(
      children: [
        SettingsBlock(
          caption: l10n.shortcutsGroupGlobal,
          child: _Rows(rows: AppShortcuts.appLevel.toList(), l10n: l10n),
        ),
        // The file operations once, not once per screen: they are the same
        // key doing the same thing on both, which is the whole point of the
        // round. The region each belongs to is named beside it.
        for (final screen in ShortcutScreen.values)
          SettingsBlock(
            caption: _screenCaption(l10n, screen),
            child: _Rows(
              rows: <AppShortcut>[
                ...AppShortcuts.forScreen(screen),
                for (final pane in ShortcutPane.values) ...AppShortcuts.forPane(screen, pane),
              ],
              l10n: l10n,
              screen: screen,
            ),
          ),
        SettingsBlock(child: _CustomisePlaceholder(l10n: l10n)),
      ],
    );
  }

  String _screenCaption(AppLocalizations l10n, ShortcutScreen screen) => switch (screen) {
    ShortcutScreen.fileBrowser => l10n.fileBrowser,
    ShortcutScreen.workbench => l10n.workbench,
  };
}

class _Rows extends StatelessWidget {
  const _Rows({required this.rows, required this.l10n, this.screen});

  final List<AppShortcut> rows;
  final AppLocalizations l10n;
  final ShortcutScreen? screen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, row) in rows.indexed) ...[
          if (index > 0) Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
          _Row(shortcut: row, l10n: l10n, screen: screen),
        ],
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.shortcut, required this.l10n, this.screen});

  final AppShortcut shortcut;
  final AppLocalizations l10n;
  final ShortcutScreen? screen;

  /// Which region a pane-level key belongs to, so a reader can tell why
  /// `Delete` is listed once and means one thing.
  String? get _region {
    if (shortcut.layer != ShortcutLayer.pane || screen == null) return null;
    final panes = shortcut.panes.toList()..sort((a, b) => a.index - b.index);
    return panes.map((p) => shortcutPaneLabel(l10n, screen!, p)).join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final region = _region;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16, vertical: AppSpace.s10),
      child: AppShortcutRow(
        gap: AppSpace.s16,
        dense: true,
        shortcut: shortcut,
        label: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(shortcutLabel(l10n, shortcut), style: Theme.of(context).textTheme.bodyMedium),
            if (region != null)
              Text(
                region,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}

class _CustomisePlaceholder extends StatelessWidget {
  const _CustomisePlaceholder({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16, vertical: AppSpace.s10),
      child: Row(
        children: [
          Icon(Icons.tune, size: AppSize.iconMd, color: scheme.outline),
          const SizedBox(width: AppSpace.s10),
          Expanded(
            child: Text(
              l10n.shortcutsCustomise,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Text(
            l10n.shortcutsCustomiseLater,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.outline),
          ),
        ],
      ),
    );
  }
}
