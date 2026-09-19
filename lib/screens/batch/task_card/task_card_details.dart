part of '../task_queue_card.dart';

// ════════════════════════════════════════════════════════════════════════════
// Expanded detail — `B2 · 1a` 展开区
// ════════════════════════════════════════════════════════════════════════════

/// What a card opens onto: the fact table and the things to do about the task
/// on the left (340), and the request, its outputs and its log on the right —
/// each an inset card on the column colour. Stacked where the two will not
/// both fit.
class TaskExpandedDetails extends StatelessWidget {
  const TaskExpandedDetails({super.key, required this.task});

  final TaskItem task;

  static const double _factsWidth = 340;
  static const double _gap = 14;

  /// The narrowest the right-hand cards read as cards rather than as a
  /// column of wrapped words.
  static const double _paneMin = 280;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, box) {
            final left = _FactsAndActions(task: task);
            final right = _DetailPanes(task: task);
            if (box.maxWidth >= _factsWidth + _gap + _paneMin) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: _factsWidth, child: left),
                  const SizedBox(width: _gap),
                  Expanded(child: right),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [left, const SizedBox(height: _gap), right],
            );
          },
        ),
      ),
    );
  }
}

class _FactsAndActions extends StatelessWidget {
  const _FactsAndActions({required this.task});

  final TaskItem task;

  /// Lines a prompt may take in the table before it is ellipsized; the whole
  /// text is one menu entry away (copy prompt).
  static const int _promptLines = 4;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final queue = Provider.of<AppState>(context, listen: false).taskQueue;
    final failed = task.status == TaskStatus.failed;

    final prompt = '${task.parameters['prompt'] ?? ''}';
    final config = task.type == TaskType.imageProcess
        ? '${task.parameters['aspectRatio'] ?? ''} ${task.parameters['imageSize'] ?? ''}'.trim()
        : '';
    final source = switch (task.imagePaths.length) {
      0 => '',
      1 => p.basename(task.imagePaths.first),
      final n => '${p.basename(task.imagePaths.first)} +${n - 1}',
    };

    final rows = <(String, String, int)>[
      (l10n.model, task.modelId, 1),
      (l10n.createdAt, formatTaskClock(task.createdAt), 1),
      (l10n.started, formatTaskClock(task.startTime), 1),
      (l10n.finished, formatTaskClock(task.endTime), 1),
      (l10n.durationLabel, taskElapsed(task) ?? '', 1),
      (l10n.config, config, 1),
      (l10n.sourceFiles, source, 1),
      (l10n.prompt, prompt, _promptLines),
    ].where((row) => row.$2.isNotEmpty);

    final actions = <Widget>[
      // Before retry: on a video whose job was accepted, picking it back up
      // costs nothing, while a retry submits — and pays for — a new one.
      if (TaskQueueService.canResumeVideoJob(task))
        AppButton(
          label: l10n.resumeVideoJob,
          icon: Icons.play_arrow_rounded,
          size: AppButtonSize.compact,
          variant: AppButtonVariant.secondary,
          onPressed: () => queue.resumeVideoJob(task.id),
        ),
      if (failed || task.status == TaskStatus.cancelled)
        AppButton(
          label: l10n.retryTask,
          icon: Icons.refresh,
          size: AppButtonSize.compact,
          // A failure's retry is the solid error fill (`B2`); a cancellation
          // is not a fault, so its retry is the neutral outline.
          variant: failed ? AppButtonVariant.destructive : AppButtonVariant.secondary,
          onPressed: () => queue.retryTask(task.id),
        ),
      if (failed && task.logs.isNotEmpty)
        AppButton(
          label: l10n.copyError,
          icon: Icons.content_copy,
          size: AppButtonSize.compact,
          variant: AppButtonVariant.secondary,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: task.logs.join('\n')));
            AppSnackBar.success(context, l10n.copiedAll);
          },
        ),
      if (_isTerminal(task))
        AppButton(
          label: l10n.removeFromList,
          icon: Icons.playlist_remove,
          size: AppButtonSize.compact,
          variant: AppButtonVariant.text,
          onPressed: () => queue.removeTask(task.id),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (key, value, lines) in rows) _FactRow(label: key, value: value, maxLines: lines),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: AppSpace.s10),
          Wrap(spacing: AppSpace.s6, runSpacing: AppSpace.s6, children: actions),
        ],
      ],
    );
  }
}

/// An 88px grey key beside a mono value that ellipsizes.
class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, required this.value, this.maxLines = 1});

  final String label;
  final String value;
  final int maxLines;

  static const double keyWidth = 88;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: keyWidth,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: _mono12(context).copyWith(color: scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailPanes extends StatelessWidget {
  const _DetailPanes({required this.task});

  final TaskItem task;

  /// The log card's ceiling. A failed generation can log a hundred lines, and
  /// an open card that runs past the window takes the rest of the queue with
  /// it.
  static const double _logMaxHeight = 168;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final mono = _mono11(context).copyWith(height: AppType.looseHeight, color: scheme.onSurface);
    final dash = Text('—', style: mono.copyWith(color: scheme.outline));

    // The prompt is already in the fact table beside this card.
    final params = [
      for (final entry in task.parameters.entries)
        if (entry.key != 'prompt' && '${entry.value ?? ''}'.isNotEmpty) '${entry.key}: ${entry.value}',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _PaneCard(
          caption: l10n.requestParameters,
          child: params.isEmpty
              ? dash
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in params)
                      Text(line, maxLines: 2, overflow: TextOverflow.ellipsis, style: mono),
                  ],
                ),
        ),
        const SizedBox(height: AppSpace.s10),
        _PaneCard(
          caption: l10n.outputPaths,
          trailing: task.resultPaths.isEmpty
              ? null
              : AppButton(
                  label: l10n.openInFolder,
                  icon: Icons.folder_open,
                  size: AppButtonSize.compact,
                  variant: AppButtonVariant.text,
                  onPressed: () => FileUtils.openFolder(task.resultPaths.first),
                ),
          child: task.resultPaths.isEmpty
              ? (task.status == TaskStatus.failed
                  ? Text(l10n.taskNoOutputsFailed, style: mono.copyWith(color: scheme.onSurfaceVariant))
                  : dash)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final path in task.resultPaths)
                      InkWell(
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                        onTap: () => FileUtils.openPath(path),
                        child: Text(
                          p.basename(path),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: mono,
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: AppSpace.s10),
        _PaneCard(
          caption: l10n.executionLogs,
          trailing: task.logs.isEmpty
              ? null
              : AppButton(
                  label: l10n.copyAll,
                  size: AppButtonSize.compact,
                  variant: AppButtonVariant.text,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: task.logs.join('\n')));
                    AppSnackBar.success(context, l10n.copiedAll);
                  },
                ),
          child: task.logs.isEmpty
              ? Text(l10n.noLogsYet, style: textTheme.bodySmall?.copyWith(color: scheme.outline))
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: _logMaxHeight),
                  child: ScrollEdgeFade(
                    child: SingleChildScrollView(
                      child: SelectionArea(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [for (final line in task.logs) _LogLine(line: line)],
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

/// A card inside the open card: the column colour at r10 with a hairline, a
/// tracked caption, and whatever it holds. The caption row is always a compact
/// control tall, so a card with an action beside its caption lines up with one
/// without.
class _PaneCard extends StatelessWidget {
  const _PaneCard({required this.caption, required this.child, this.trailing});

  final String caption;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpace.s10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: AppSize.compact,
            child: AppSectionLabel(caption, padding: EdgeInsets.zero, trailing: trailing),
          ),
          const SizedBox(height: AppSpace.s4),
          child,
        ],
      ),
    );
  }
}

/// One log line, its `[HH:MM:SS]` set apart in the quiet tone so the message
/// is what the eye lands on; error lines in the error ink.
class _LogLine extends StatelessWidget {
  const _LogLine({required this.line});

  final String line;

  static final RegExp _stamp = RegExp(r'^\s*(\[[^\]]{1,12}\])\s*');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final match = _stamp.firstMatch(line);
    final stamp = match?.group(1);
    final message = match == null ? line : line.substring(match.end);
    final upper = message.toUpperCase();
    final isError = upper.contains('ERROR') || upper.contains('FAILED');
    final base = _mono11(context).copyWith(height: AppType.looseHeight);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (stamp != null) ...[
          Text(stamp, style: base.copyWith(color: scheme.outline)),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            message,
            style: base.copyWith(
              color: isError ? scheme.onErrorContainer : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
