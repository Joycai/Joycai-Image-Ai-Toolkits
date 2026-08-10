import 'package:flutter/material.dart';

import '../../../core/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/panel_resizer.dart';

class PromptOptimizerToolbar extends StatelessWidget {
  final VoidCallback onNewSession;
  final VoidCallback onHistory;
  final VoidCallback onApply;
  final bool isRefining;
  final bool canApply;

  /// Localised name of the session's mode, shown as a badge beside the title.
  /// Null hides the badge.
  final String? modeLabel;

  const PromptOptimizerToolbar({
    super.key,
    required this.onNewSession,
    required this.onHistory,
    required this.onApply,
    required this.isRefining,
    required this.canApply,
    this.modeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final isMobile = Responsive.isMobile(context);

    final textTheme = Theme.of(context).textTheme;

    return Container(
      height: kPanelHeaderHeight,
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
                : Row(
                    children: [
                      Flexible(
                        child: Text(
                          l10n.promptOptimizer,
                          style: textTheme.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (modeLabel != null) ...[
                        const SizedBox(width: 10),
                        // Which brain is answering. The three modes behave
                        // very differently and the setting that picks them
                        // lives in a panel that can be closed, so the header
                        // has to say it.
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.smart_toy_outlined, size: 13, color: colorScheme.onSurfaceVariant),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    l10n.optModeBadgeAgent(modeLabel!),
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.labelMedium
                                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
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

          // Solid in the app's own accent, not the tertiary hue: this is the
          // one action the whole screen builds towards, and it should read as
          // the same "commit" colour every other primary button uses.
          //
          // Disabled is an outline, not a grey slab. There is nothing to apply
          // until the agent has produced a prompt, and a filled grey button
          // looks broken where an empty one reads as "not yet".
          FilledButton.icon(
            onPressed: canApply ? onApply : null,
            icon: const Icon(Icons.check, size: 18),
            label: Text(
              isMobile ? l10n.apply : l10n.applyToWorkbench,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            style: FilledButton.styleFrom(
              disabledBackgroundColor: Colors.transparent,
              disabledForegroundColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              side: canApply
                  ? null
                  : BorderSide(color: colorScheme.outlineVariant),
              elevation: canApply ? null : 0,
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
