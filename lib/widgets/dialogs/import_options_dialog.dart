import 'package:flutter/material.dart';

import '../../core/app_semantic_colors.dart';
import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../app_button.dart';
import '../app_dialog.dart';

/// Asks which parts of a backup to restore — design `E1 · 1d` 「导入选项」.
///
/// Two presentations of one question: a dialog on desktop, a bottom sheet on
/// a phone. Both are the same body: one checkbox row per section of the
/// backup — a section the file does not contain stays in the list, unchecked
/// and greyed, with a badge saying so — and a warning that what is checked
/// gets *replaced*.
///
/// [onUpdate] reports the chosen flags before the future completes, because
/// both call sites (settings and the setup wizard) already hold their own
/// `includeX` locals and restore from those. Returns true if the user
/// confirmed.
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

  /// The backup's file name, shown under the title in mono.
  String? fileName,
}) {
  // Seeded from what the backup actually contains, so the list doubles as a
  // description of the file rather than offering something that cannot
  // happen.
  bool dirs = hasDirs;
  bool prompts = hasPrompts;
  bool usage = hasUsage;

  Widget body(StateSetter setState) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ImportOptionRow(
            title: l10n.includeDirectories,
            description: l10n.includeDirectoriesDesc,
            value: dirs,
            enabled: hasDirs,
            missingLabel: l10n.notInBackup,
            onChanged: (v) => setState(() => dirs = v),
          ),
          ImportOptionRow(
            title: l10n.includePrompts,
            description: l10n.includePromptsDesc,
            value: prompts,
            enabled: hasPrompts,
            missingLabel: l10n.notInBackup,
            onChanged: (v) => setState(() => prompts = v),
          ),
          ImportOptionRow(
            title: l10n.includeUsage,
            description: l10n.includeUsageDesc,
            value: usage,
            enabled: hasUsage,
            missingLabel: l10n.notInBackup,
            onChanged: (v) => setState(() => usage = v),
          ),
          const SizedBox(height: AppSpace.s10),
          _WarningNote(l10n.importSettingsConfirm),
        ],
      );

  if (isMobile ?? Responsive.isMobile(context)) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setState) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpace.s22, AppSpace.s22, AppSpace.s22, AppSpace.s28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.importOptions, style: Theme.of(sheetContext).textTheme.titleLarge),
              if (fileName != null) ...[
                const SizedBox(height: 2),
                _FileName(fileName),
              ],
              const SizedBox(height: AppSpace.s16),
              body(setState),
              const SizedBox(height: AppSpace.s22),
              AppButton(
                label: l10n.importAndReplace,
                size: AppButtonSize.large,
                fullWidth: true,
                onPressed: () {
                  onUpdate(dirs, prompts, usage);
                  Navigator.pop(sheetContext, true);
                },
              ),
              const SizedBox(height: AppSpace.s6),
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
    icon: Icons.download_outlined,
    title: l10n.importOptions,
    subtitle: fileName,
    maxWidth: 440,
    content: StatefulBuilder(builder: (_, setState) => body(setState)),
    actions: [
      AppButton(
        label: l10n.cancel,
        variant: AppButtonVariant.text,
        onPressed: () => Navigator.pop(context, false),
      ),
      AppButton(
        label: l10n.importAndReplace,
        onPressed: () {
          onUpdate(dirs, prompts, usage);
          Navigator.pop(context, true);
        },
      ),
    ],
  );
}

/// One checkbox row of an import or export choice: what it covers, and — when
/// the backup lacks it — a badge saying so, with the row greyed and inert.
///
/// Public so the settings export dialog draws its options the same way.
class ImportOptionRow extends StatelessWidget {
  const ImportOptionRow({
    super.key,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.missingLabel,
  });

  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// False when the backup has no such section.
  final bool enabled;

  /// The badge shown while [enabled] is false.
  final String? missingLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: enabled ? () => onChanged(!value) : null,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSize.large),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Checkbox(
                value: value && enabled,
                onChanged: enabled ? (v) => onChanged(v ?? false) : null,
              ),
              const SizedBox(width: AppSpace.s6),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: textTheme.bodyMedium?.copyWith(
                        color: enabled ? colorScheme.onSurface : colorScheme.outline,
                      ),
                    ),
                    Text(
                      description,
                      style: textTheme.bodySmall?.copyWith(
                        color: enabled ? colorScheme.onSurfaceVariant : colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              if (!enabled && missingLabel != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                    ),
                    child: Text(
                      missingLabel!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w400,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FileName extends StatelessWidget {
  const _FileName(this.name);
  final String name;

  @override
  Widget build(BuildContext context) {
    return Text(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall?.mono.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}

/// The warning under the options: what importing replaces.
class _WarningNote extends StatelessWidget {
  const _WarningNote(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: semantic.warningContainer,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.warning_amber_rounded, size: AppSize.iconSm, color: semantic.warning),
          ),
          const SizedBox(width: AppSpace.s6),
          Expanded(
            child: Text(
              text.trim(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: semantic.onWarningContainer,
                    height: AppType.proseHeight,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
