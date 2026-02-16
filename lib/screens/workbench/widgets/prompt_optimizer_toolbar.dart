import 'package:flutter/material.dart';

import '../../../core/responsive.dart';
import '../../../l10n/app_localizations.dart';

class PromptOptimizerToolbar extends StatelessWidget {
  final VoidCallback onRefine;
  final VoidCallback onApply;
  final VoidCallback onClear;
  final bool isRefining;
  final bool canApply;

  const PromptOptimizerToolbar({
    super.key,
    required this.onRefine,
    required this.onApply,
    required this.onClear,
    required this.isRefining,
    required this.canApply,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final isMobile = Responsive.isMobile(context);

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: colorScheme.surface,
      child: Row(
        children: [
          if (!isMobile) ...[
            Text(l10n.promptOptimizer, style: const TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
          ] else 
            const Icon(Icons.auto_fix_high, size: 20),
          
          if (isRefining)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            
          if (!isMobile) ...[
            IconButton(
              icon: const Icon(Icons.cleaning_services_outlined, size: 20),
              onPressed: onClear,
              tooltip: l10n.clear,
              visualDensity: VisualDensity.compact,
            ),
            const VerticalDivider(width: 16, indent: 12, endIndent: 12),
          ],
          
          FilledButton.icon(
            onPressed: isRefining ? null : onRefine,
            icon: const Icon(Icons.auto_fix_high, size: 18),
            label: Text(l10n.refine, style: const TextStyle(fontSize: 12)),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: canApply ? onApply : null,
            icon: const Icon(Icons.check, size: 18),
            label: Text(isMobile ? l10n.apply : l10n.applyToWorkbench, style: const TextStyle(fontSize: 12)),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.tertiary,
              foregroundColor: colorScheme.onTertiary,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),

          if (isMobile) ...[
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz),
              onSelected: (value) {
                if (value == 'clear') onClear();
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'clear',
                  child: ListTile(
                    leading: const Icon(Icons.delete_outline, color: Colors.red),
                    title: Text(l10n.clear, style: const TextStyle(color: Colors.red)),
                    dense: true,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
