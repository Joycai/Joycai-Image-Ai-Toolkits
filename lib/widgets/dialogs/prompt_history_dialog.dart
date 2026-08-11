import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/prompt_history_entry.dart';
import '../../state/app_state.dart';
import '../app_button.dart';
import '../app_dialog.dart';
import '../app_side_panel.dart';

/// Prompt-header action that opens the recent-prompt picker for [type].
///
/// Icon-only: the image panel's header also carries the labelled Library
/// button, and two labelled buttons overflow the config sidebar, squeezing the
/// section title to nothing.
///
/// Disabled until something has been submitted, mirroring how the Library
/// button greys out with an empty library.
class PromptHistoryButton extends StatelessWidget {
  final List<PromptHistoryEntry> entries;
  final PromptHistoryType type;
  final ValueChanged<String> onApply;

  const PromptHistoryButton({
    super.key,
    required this.entries,
    required this.type,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return IconButton(
      onPressed: entries.isEmpty
          ? null
          : () => PromptHistorySheet.show(
                context: context,
                entries: entries,
                onApply: onApply,
                onClear: () =>
                    Provider.of<AppState>(context, listen: false).clearPromptHistory(type),
              ),
      icon: const Icon(Icons.history, size: 18),
      tooltip: l10n.promptHistory,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }
}

/// Recent-prompt picker for the workbench config panels.
///
/// Shares the shell of [PromptLibrarySheet] — bottom sheet when narrow, a
/// right-slide panel on desktop — since the two sit side by side in the prompt
/// header. Unlike the library, entries are read-only and picking one always
/// goes through a preview confirmation, because applying replaces whatever the
/// user has typed.
class PromptHistorySheet extends StatefulWidget {
  final List<PromptHistoryEntry> entries;
  final ValueChanged<String> onApply;
  final VoidCallback onClear;

  const PromptHistorySheet({
    super.key,
    required this.entries,
    required this.onApply,
    required this.onClear,
  });

  static Future<void> show({
    required BuildContext context,
    required List<PromptHistoryEntry> entries,
    required ValueChanged<String> onApply,
    required VoidCallback onClear,
  }) async {
    await AppSidePanel.show<void>(
      context,
      builder: (context) => PromptHistorySheet(
        entries: entries,
        onApply: onApply,
        onClear: onClear,
      ),
    );
  }

  @override
  State<PromptHistorySheet> createState() => _PromptHistorySheetState();
}

class _PromptHistorySheetState extends State<PromptHistorySheet> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    // Surface, width and shadow belong to AppSidePanel, which is what
    // presents this. All that is left here is what the panel contains.
    return Column(
      children: [
        _buildHeader(l10n, colorScheme),
        const Divider(height: 1),
        Expanded(child: _buildList(l10n, colorScheme)),
      ],
    );
  }

  Widget _buildHeader(AppLocalizations l10n, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Icon(Icons.history, color: colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.promptHistory,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          if (widget.entries.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, size: 20),
              tooltip: l10n.clearPromptHistory,
              onPressed: _confirmClear,
            ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildList(AppLocalizations l10n, ColorScheme colorScheme) {
    if (widget.entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.history_toggle_off, size: 48, color: colorScheme.outlineVariant),
              const SizedBox(height: 16),
              Text(l10n.noPromptHistory, style: TextStyle(color: colorScheme.outline)),
              const SizedBox(height: 6),
              Text(
                l10n.noPromptHistoryDesc,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.outline),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: widget.entries.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final entry = widget.entries[index];
        return _HistoryCard(
          entry: entry,
          onTap: () => _openPreview(entry),
        );
      },
    );
  }

  Future<void> _openPreview(PromptHistoryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _PromptPreviewDialog(entry: entry),
    );
    if (confirmed != true || !mounted) return;

    widget.onApply(entry.content);
    Navigator.pop(context);
  }

  Future<void> _confirmClear() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await AppDialog.show<bool>(
      context,
      title: l10n.clearPromptHistory,
      content: Text(l10n.clearPromptHistoryConfirm),
      actions: [
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.pop(context, false),
        ),
        AppButton(
          label: l10n.clear,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
    if (confirmed != true || !mounted) return;

    widget.onClear();
    Navigator.pop(context);
  }
}

class _HistoryCard extends StatelessWidget {
  final PromptHistoryEntry entry;
  final VoidCallback onTap;

  const _HistoryCard({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant.withAlpha(100)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.schedule, size: 12, color: colorScheme.outline),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      formatRelativeTime(l10n, entry.usedAt),
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: colorScheme.outline),
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 16, color: colorScheme.outline),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                entry.content,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PromptPreviewDialog extends StatelessWidget {
  final PromptHistoryEntry entry;

  const _PromptPreviewDialog({required this.entry});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return AppDialog(
      title: l10n.preview,
      maxWidth: 500,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatRelativeTime(l10n, entry.usedAt),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colorScheme.outline),
          ),
          const SizedBox(height: 12),
          // Caps the prompt body only — the warning line below it has to stay
          // visible however long the prompt runs.
          Flexible(
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 320),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withAlpha(80),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  entry.content,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            l10n.applyPromptWarning,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colorScheme.outline),
          ),
        ],
      ),
      actions: [
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.pop(context, false),
        ),
        AppButton(
          label: l10n.usePrompt,
          icon: Icons.check,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
  }
}

/// Coarse "time ago" label. History spans at most a handful of entries, so
/// anything older than a week is better served by the absolute date.
String formatRelativeTime(AppLocalizations l10n, DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return l10n.timeJustNow;
  if (diff.inHours < 1) return l10n.timeMinutesAgo(diff.inMinutes);
  if (diff.inDays < 1) return l10n.timeHoursAgo(diff.inHours);
  if (diff.inDays < 7) return l10n.timeDaysAgo(diff.inDays);
  return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
}
