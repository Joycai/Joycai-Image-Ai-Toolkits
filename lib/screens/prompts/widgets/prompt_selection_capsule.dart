import 'package:flutter/material.dart';

import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/glass/app_glass.dart';
import '../../../widgets/glass/glass_controls.dart';

/// The phone's selection actions (`C1 · 1c`): a 56px G2 glass capsule at r28
/// floating over the list — close, the count in the deep ink, Categorize and
/// Delete as 40px glyphs.
class PromptSelectionCapsule extends StatelessWidget {
  const PromptSelectionCapsule({
    super.key,
    required this.count,
    required this.onClose,
    required this.onCategorize,
    required this.onDelete,
  });

  static const double height = 56;

  final int count;
  final VoidCallback onClose;
  final VoidCallback onCategorize;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return AppGlass(
      grade: GlassGrade.float,
      borderRadius: BorderRadius.circular(AppRadius.sheet),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SizedBox(
        height: height,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlassIconButton(icon: Icons.close, tooltip: l10n.cancel, size: AppSize.large, onPressed: onClose),
            const SizedBox(width: AppSpace.s4),
            Flexible(
              child: Text(
                l10n.nSelected(count),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onAccentTint,
                    ),
              ),
            ),
            const SizedBox(width: 12),
            GlassIconButton(
              icon: Icons.label_outline,
              tooltip: l10n.categorize,
              size: AppSize.large,
              onPressed: onCategorize,
            ),
            GlassIconButton(
              icon: Icons.delete_outline,
              tooltip: l10n.delete,
              danger: true,
              size: AppSize.large,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
