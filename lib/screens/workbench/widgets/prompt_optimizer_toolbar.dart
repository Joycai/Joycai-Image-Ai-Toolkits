import 'package:flutter/material.dart';

import '../../../core/responsive.dart';
import '../../../l10n/app_localizations.dart';

class PromptOptimizerToolbar extends StatelessWidget {
  final VoidCallback onNewSession;
  final VoidCallback onHistory;
  final VoidCallback onApply;
  final bool isRefining;
  final bool canApply;

  const PromptOptimizerToolbar({
    super.key,
    required this.onNewSession,
    required this.onHistory,
    required this.onApply,
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
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withAlpha(80))),
      ),
      child: Row(
        children: [
          // Title fills the leading space, pushing the actions to the right.
          Expanded(
            child: isMobile
                ? const SizedBox.shrink()
                : Text(
                    l10n.promptOptimizer,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
          ),

          if (isRefining)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ),

          if (!isMobile) ...[
            IconButton(
              icon: const Icon(Icons.history, size: 20),
              onPressed: onHistory,
              tooltip: l10n.optHistory,
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: const Icon(Icons.add_comment_outlined, size: 20),
              onPressed: onNewSession,
              tooltip: l10n.optNewSession,
              visualDensity: VisualDensity.compact,
            ),
            const VerticalDivider(width: 16, indent: 12, endIndent: 12),
          ],

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
                if (value == 'new_session') onNewSession();
                if (value == 'history') onHistory();
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'history',
                  child: ListTile(
                    leading: const Icon(Icons.history),
                    title: Text(l10n.optHistory),
                    dense: true,
                  ),
                ),
                PopupMenuItem(
                  value: 'new_session',
                  child: ListTile(
                    leading: Icon(Icons.add_comment_outlined, color: colorScheme.error),
                    title: Text(l10n.optNewSession, style: TextStyle(color: colorScheme.error)),
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
