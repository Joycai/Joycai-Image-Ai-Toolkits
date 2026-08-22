import 'package:flutter/material.dart';

import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../app_button.dart';
import '../app_dialog.dart';

/// Asks which parts of a backup to restore.
///
/// Two presentations of one question: a dialog on desktop, a bottom sheet on
/// a phone — the sheet because this is a list of switches, and a phone-width
/// dialog would put them behind a scrim with barely room for their
/// descriptions.
///
/// This lived twice, in `settings/widgets/data_section.dart` and
/// `wizard/wizard_import.dart`, as three near-identical functions each. They
/// had already started to drift: one used [AppButtonSize.large] with
/// `fullWidth`, the other a `SizedBox` around a default-sized button; one
/// asked [Responsive] which layout to use, the other hard-coded
/// `MediaQuery.of(context).size.width < 600`.
///
/// [onUpdate] reports the chosen flags before the future completes, because
/// both call sites already hold their own `includeX` locals and restore from
/// those. Returns true if the user confirmed.
Future<bool?> showImportOptionsDialog(
  BuildContext context, {
  required AppLocalizations l10n,
  required bool hasDirs,
  required bool hasPrompts,
  required bool hasUsage,
  required void Function(bool dirs, bool prompts, bool usage) onUpdate,

  /// Overrides the [Responsive] check. The settings screen knows which of its
  /// two routes is mounted and passes that instead — the mobile route can be
  /// reached at a width the breakpoint would call something else, and it
  /// should still get the sheet.
  bool? isMobile,
}) {
  // Seeded from what the backup actually contains: a section that isn't in
  // the file is shown switched off and disabled, so the list doubles as a
  // description of the backup rather than offering something that cannot
  // happen.
  bool dirs = hasDirs;
  bool prompts = hasPrompts;
  bool usage = hasUsage;

  List<Widget> options(StateSetter setState, {required double gap}) => [
        _ImportOption(
          title: l10n.includeDirectories,
          description: l10n.includeDirectoriesDesc,
          value: dirs,
          enabled: hasDirs,
          l10n: l10n,
          onChanged: (v) => setState(() => dirs = v),
        ),
        SizedBox(height: gap),
        _ImportOption(
          title: l10n.includePrompts,
          description: l10n.includePromptsDesc,
          value: prompts,
          enabled: hasPrompts,
          l10n: l10n,
          onChanged: (v) => setState(() => prompts = v),
        ),
        SizedBox(height: gap),
        _ImportOption(
          title: l10n.includeUsage,
          description: l10n.includeUsageDesc,
          value: usage,
          enabled: hasUsage,
          l10n: l10n,
          onChanged: (v) => setState(() => usage = v),
        ),
      ];

  void confirm() {
    onUpdate(dirs, prompts, usage);
    Navigator.pop(context, true);
  }

  if (isMobile ?? Responsive.isMobile(context)) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setState) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.importOptions,
                style: Theme.of(sheetContext).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              _Caption(l10n.importSettingsConfirm),
              const SizedBox(height: 24),
              ...options(setState, gap: 20),
              const SizedBox(height: 48),
              AppButton(
                label: l10n.importNow,
                variant: AppButtonVariant.destructive,
                size: AppButtonSize.large,
                fullWidth: true,
                onPressed: () {
                  onUpdate(dirs, prompts, usage);
                  Navigator.pop(sheetContext, true);
                },
              ),
              const SizedBox(height: 12),
              AppButton(
                label: l10n.cancel,
                variant: AppButtonVariant.text,
                size: AppButtonSize.large,
                fullWidth: true,
                onPressed: () => Navigator.pop(sheetContext, false),
              ),
            ],
          ),
        ),
      ),
    );
  }

  return AppDialog.show<bool>(
    context,
    title: l10n.importOptions,
    maxWidth: 450,
    content: StatefulBuilder(
      builder: (_, setState) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Caption(l10n.importSettingsConfirm),
          const SizedBox(height: 20),
          ...options(setState, gap: 12),
        ],
      ),
    ),
    actions: [
      AppButton(
        label: l10n.cancel,
        variant: AppButtonVariant.text,
        onPressed: () => Navigator.pop(context, false),
      ),
      AppButton(
        label: l10n.importNow,
        variant: AppButtonVariant.destructive,
        onPressed: confirm,
      ),
    ],
  );
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      // Was `Colors.grey` in both copies, which is the same grey in dark mode
      // as in light and so lost most of its contrast against the sheet.
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}

/// One switch row: what it restores, and what it means when it can't.
class _ImportOption extends StatelessWidget {
  const _ImportOption({
    required this.title,
    required this.description,
    required this.value,
    required this.enabled,
    required this.l10n,
    required this.onChanged,
  });

  final String title;
  final String description;
  final bool value;

  /// False when the backup has no such section. The row stays visible and
  /// explains itself rather than disappearing, so the list tells the user
  /// what the file contains.
  final bool enabled;

  final AppLocalizations l10n;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    // Both copies reached for Colors.grey / Colors.grey[400] here, which do
    // not follow the theme — a disabled row was the same mid-grey on a white
    // sheet and on a near-black one.
    final disabledTitle = colorScheme.onSurface.withValues(alpha: 0.38);
    final disabledBody = colorScheme.onSurface.withValues(alpha: 0.30);

    return SwitchListTile(
      value: value && enabled,
      onChanged: enabled ? onChanged : null,
      title: Text(
        title,
        style: textTheme.titleMedium?.copyWith(color: enabled ? null : disabledTitle),
      ),
      subtitle: Text(
        enabled ? description : l10n.notInBackup,
        style: textTheme.bodySmall?.copyWith(
          color: enabled ? colorScheme.onSurfaceVariant : disabledBody,
        ),
      ),
      contentPadding: EdgeInsets.zero,
    );
  }
}
