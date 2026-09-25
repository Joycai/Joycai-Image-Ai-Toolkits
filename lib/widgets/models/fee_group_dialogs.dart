import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/pricing_group.dart';
import '../../state/app_state.dart';
import '../ui/app_button.dart';
import '../ui/app_dialog.dart';

/// `D2 · 1e` 删除组: the error plate, the group's name, and — when models
/// point at it — how many of them will be left with no fee group. Returns
/// true once the group is gone.
Future<bool> confirmDeleteFeeGroup(
  BuildContext context,
  AppState appState,
  PricingGroup group, {
  required int modelCount,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final textTheme = Theme.of(context).textTheme;
  final deleted = await AppDialog.show<bool>(
    context,
    icon: Icons.delete_outline,
    iconColor: Theme.of(context).colorScheme.error,
    maxWidth: 440,
    title: l10n.delete,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.deleteFeeGroupConfirm(group.name)),
        if (modelCount > 0) ...[
          const SizedBox(height: 6),
          Text(
            l10n.deleteFeeGroupInUse(modelCount),
            style: textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    ),
    actions: [
      AppButton(
        label: l10n.cancel,
        variant: AppButtonVariant.text,
        autofocus: true,
        onPressed: () => Navigator.pop(context, false),
      ),
      Builder(
        builder: (dialogContext) => AppButton(
          label: l10n.delete,
          variant: AppButtonVariant.destructive,
          onPressed: () async {
            await appState.deletePricingGroup(group.id!);
            if (dialogContext.mounted) Navigator.pop(dialogContext, true);
          },
        ),
      ),
    ],
  );
  return deleted ?? false;
}

/// `D2 · 1e` 切到另一组: the unsaved edits would be lost. Returns true when
/// the user lets them go.
Future<bool> confirmDiscardFeeGroupDraft(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final discard = await AppDialog.show<bool>(
    context,
    icon: Icons.edit_off_outlined,
    maxWidth: 420,
    title: l10n.discardChangesTitle,
    content: Text(l10n.discardChangesBody),
    actions: [
      AppButton(
        label: l10n.cancel,
        variant: AppButtonVariant.text,
        autofocus: true,
        onPressed: () => Navigator.pop(context, false),
      ),
      AppButton(
        label: l10n.discard,
        variant: AppButtonVariant.destructive,
        onPressed: () => Navigator.pop(context, true),
      ),
    ],
  );
  return discard ?? false;
}
