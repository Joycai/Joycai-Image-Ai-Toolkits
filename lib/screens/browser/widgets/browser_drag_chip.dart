import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/glass/app_glass.dart';

/// What follows the pointer while files are dragged onto a folder
/// (`B1a · 1b`): a small G2 glass piece, 32 tall at r10 — `drive_file_move`
/// and "Move 3 · hold Ctrl to copy".
///
/// Shared by the grid card and the list row. The drag carries files rather
/// than paths so this chip can count them without asking the browser state.
class BrowserFileDragChip extends StatelessWidget {
  const BrowserFileDragChip({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      // Off the pointer's hotspot, so the folder under it stays readable.
      padding: const EdgeInsets.only(left: 12, top: 12),
      child: Material(
        type: MaterialType.transparency,
        child: SizedBox(
          height: AppSize.control,
          child: AppGlass(
            grade: GlassGrade.float,
            borderRadius: BorderRadius.circular(AppRadius.control),
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.drive_file_move_outline, size: AppSize.iconMd, color: scheme.primary),
                const SizedBox(width: AppSpace.s6),
                Text(
                  l10n.dragMoveHint(count),
                  maxLines: 1,
                  style: Theme.of(context).textTheme.bodySmall!.metricsOnly.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
