part of '../task_queue_card.dart';

// ════════════════════════════════════════════════════════════════════════════
// Row menu
// ════════════════════════════════════════════════════════════════════════════

/// A 28px glyph button inside a row, r6 — the row is the container here, so
/// this is a control inside one, not a boxed one on the canvas.
class _RowIconButton extends StatelessWidget {
  const _RowIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool selected;

  static const double size = AppSize.compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: size,
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: AppSize.iconMd),
        style: IconButton.styleFrom(
          fixedSize: const Size.square(size),
          minimumSize: const Size.square(size),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: selected ? scheme.onAccentTint : scheme.onSurfaceVariant,
          backgroundColor: selected ? scheme.accentTint : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
        ),
      ),
    );
  }
}

/// A task's ⋮ (`B2 · 1b`): view log · retry · copy prompt, a hairline, then
/// remove and cancel. Each entry appears only where it can act.
class TaskMenuButton extends StatefulWidget {
  const TaskMenuButton({super.key, required this.task});

  final TaskItem task;

  @override
  State<TaskMenuButton> createState() => _TaskMenuButtonState();
}

/// `B2 · 1b` 任务 ⋮ 菜单: G2 glass, 210 wide, dropping from the button.
class _TaskMenuButtonState extends State<TaskMenuButton> {
  /// Open, so the button keeps its lens while the menu is up.
  bool _open = false;

  static const double _menuWidth = 210;

  Future<void> _openMenu() async {
    final l10n = AppLocalizations.of(context)!;
    final task = widget.task;
    final queue = Provider.of<AppState>(context, listen: false).taskQueue;

    final canCancel = _isActive(task);
    final canRetry = task.status == TaskStatus.failed || task.status == TaskStatus.cancelled;
    final canRemove = _isTerminal(task);
    final hasPrompt = task.parameters.containsKey('prompt');

    setState(() => _open = true);
    await showAppGlassMenuBelow(
      context,
      width: _menuWidth,
      entries: [
        // First and unconditional: every status has a use for it, and a
        // running task's log tails live in the dialog.
        AppGlassMenuItem(
          icon: Icons.article_outlined,
          label: l10n.viewTaskLog,
          onSelected: () {
            if (mounted) TaskLogDialog.show(context, task);
          },
        ),
        if (TaskQueueService.canResumeVideoJob(task))
          AppGlassMenuItem(
            icon: Icons.play_arrow_rounded,
            label: l10n.resumeVideoJob,
            onSelected: () => queue.resumeVideoJob(task.id),
          ),
        if (canRetry)
          AppGlassMenuItem(
            icon: Icons.refresh,
            label: l10n.retryTask,
            onSelected: () => queue.retryTask(task.id),
          ),
        if (hasPrompt)
          AppGlassMenuItem(
            icon: Icons.content_copy,
            label: l10n.copyPrompt,
            onSelected: () {
              final prompt = '${task.parameters['prompt'] ?? ''}';
              Clipboard.setData(ClipboardData(text: prompt));
              if (!mounted) return;
              AppSnackBar.info(
                context,
                l10n.copiedToClipboard(prompt.length > 30 ? '${prompt.substring(0, 30)}…' : prompt),
              );
            },
          ),
        if (canRemove || canCancel) const AppGlassMenuDivider(),
        if (canRemove)
          AppGlassMenuItem(
            icon: Icons.playlist_remove,
            label: l10n.removeFromList,
            onSelected: () => queue.removeTask(task.id),
          ),
        if (canCancel)
          AppGlassMenuItem(
            icon: Icons.cancel_outlined,
            label: l10n.cancelTask,
            danger: true,
            onSelected: () => queue.cancelTask(task.id),
          ),
      ],
    );
    if (mounted) setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _RowIconButton(
      icon: Icons.more_vert,
      tooltip: l10n.more,
      selected: _open,
      onPressed: _openMenu,
    );
  }
}
