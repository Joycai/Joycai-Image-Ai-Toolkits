part of '../task_queue_card.dart';

// ════════════════════════════════════════════════════════════════════════════
// Status pill
// ════════════════════════════════════════════════════════════════════════════

/// `B2` 状态胶囊: r4, 2/8, 11/500, each status on its own container pair.
/// Running is the accent's 12% form with the breathing dot — the one loop the
/// system allows, and it stops under reduce-motion and reduce-visual-effects.
class TaskStatusPill extends StatelessWidget {
  const TaskStatusPill({super.key, required this.status});

  final TaskStatus status;

  static const double padX = 8;
  static const double dotSize = 6;
  static const double dotGap = 5;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = context.semantic;
    final l10n = AppLocalizations.of(context)!;

    final (Color background, Color ink) = switch (status) {
      TaskStatus.processing => (scheme.accentTint, scheme.onAccentTint),
      TaskStatus.pending => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
      TaskStatus.completed => (semantic.successContainer, semantic.onSuccessContainer),
      TaskStatus.failed => (scheme.errorContainer, scheme.onErrorContainer),
      TaskStatus.cancelled => (semantic.warningContainer, semantic.onWarningContainer),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: padX, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == TaskStatus.processing) ...[
            AppBreathingDot(color: scheme.primary, size: dotSize),
            const SizedBox(width: dotGap),
          ],
          Text(
            taskStatusLabel(status, l10n),
            maxLines: 1,
            softWrap: false,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: ink),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Leading plate
// ════════════════════════════════════════════════════════════════════════════

/// The type glyph on its identity plate — or, while the task waits, its place
/// in the queue on the track colour (`B2`: 等待中用排队序号替掉图标).
///
/// The number replaces the glyph rather than joining it: the glyph only
/// restates the kind of task, and the place in the queue is the one thing
/// about waiting that moves.
class TaskLeadingPlate extends StatelessWidget {
  const TaskLeadingPlate({
    super.key,
    required this.task,
    required this.position,
    this.size = 32,
  });

  final TaskItem task;
  final int position;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = context.semantic;
    final radius = BorderRadius.circular(AppRadius.sm);

    if (task.status == TaskStatus.pending && position > 0) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: radius),
        // A three-digit queue still fits the plate rather than overflowing it.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '#$position',
            style: _mono12(context).copyWith(
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    // Identity colours: which kind of work a row is does not change with the
    // outcome, so the plate stays put while the pill beside it moves.
    final (Color background, Color ink) = switch (task.type) {
      TaskType.imageProcess => (semantic.infoContainer, semantic.onInfoContainer),
      TaskType.videoGenerate => (scheme.errorContainer, scheme.onErrorContainer),
      TaskType.promptRefine => (scheme.accentTint, scheme.onAccentTint),
      TaskType.aiRename => (semantic.warningContainer, semantic.onWarningContainer),
      TaskType.imageDownload => (semantic.successContainer, semantic.onSuccessContainer),
    };

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background, borderRadius: radius),
      child: Icon(
        task.type.glyph,
        size: size >= 32 ? AppSize.iconMd : AppSize.iconSm,
        color: ink,
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Model + channel
// ════════════════════════════════════════════════════════════════════════════

class _ChannelDot extends StatelessWidget {
  const _ChannelDot({required this.task});

  final TaskItem task;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          // The channel's own tag colour — identity, never the accent.
          color: Color(task.channelColor ?? AppConstants.defaultTagColor),
          shape: BoxShape.circle,
        ),
        child: const SizedBox.square(dimension: 6),
      );
}

/// Mono 12/600 model id over a 6px channel dot and the channel's name.
class _ModelAndChannel extends StatelessWidget {
  const _ModelAndChannel({required this.task});

  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final channel = task.channelTag;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          task.modelId,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: _mono12(context).copyWith(
            fontWeight: FontWeight.w600,
            color: task.status == TaskStatus.cancelled ? scheme.onSurfaceVariant : scheme.onSurface,
          ),
        ),
        if (channel != null) ...[
          const SizedBox(height: 2),
          Row(
            children: [
              _ChannelDot(task: task),
              const SizedBox(width: AppSpace.s6),
              Flexible(
                child: Text(
                  channel,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w400,
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Outputs
// ════════════════════════════════════════════════════════════════════════════

/// What the task produced (`B2` 产物列): up to three 40px thumbnails and a
/// `+N` pill; a failure's grey plate with a cross where a result should have
/// been; a dashed slot where nothing is due yet.
///
/// Deliberately only *outputs* — a source image in the slot a result
/// normally fills is the one picture on this screen that must not be
/// ambiguous about which it is.
class TaskOutputs extends StatelessWidget {
  const TaskOutputs({super.key, required this.task});

  final TaskItem task;

  /// The fixed desktop column the outputs are right-aligned in, so every
  /// row's menu sits on one vertical line whatever the row produced.
  static const double columnWidth = 176;
  static const double tileSize = 40;
  static const double _gap = AppSpace.s4;
  static const int _maxThumbs = 3;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(AppRadius.sm);

    if (task.resultPaths.isNotEmpty) {
      final shown = task.resultPaths.take(_maxThumbs).toList();
      final more = task.resultPaths.length - shown.length;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < shown.length; i++) ...[
            if (i > 0) const SizedBox(width: _gap),
            ClipRRect(borderRadius: radius, child: _Thumbnail(path: shown[i])),
          ],
          if (more > 0) ...[
            const SizedBox(width: _gap),
            Container(
              height: tileSize,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: radius),
              child: Center(
                widthFactor: 1,
                child: Text(
                  '+$more',
                  style: _mono11(context).copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ],
      );
    }

    if (task.status == TaskStatus.failed) {
      return Container(
        width: tileSize,
        height: tileSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: radius),
        child: Icon(Icons.close, size: AppSize.iconMd, color: scheme.outline),
      );
    }

    return SizedBox.square(
      dimension: tileSize,
      child: DashedBorder(color: scheme.outlineVariant, radius: AppRadius.sm),
    );
  }
}

/// One 40px square of [path], decoded at the size it is drawn.
///
/// `cacheWidth` matters: without it a 40px chip held a full 2K generation in
/// the image cache, and a handful of finished tasks pushed every visible
/// thumbnail back onto the decoder while scrolling.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const double size = TaskOutputs.tileSize;
    return Image.file(
      File(path),
      width: size,
      height: size,
      cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Container(
        width: size,
        height: size,
        color: scheme.surfaceContainerHighest,
        child: Icon(Icons.broken_image_outlined, size: AppSize.iconSm, color: scheme.onSurfaceVariant),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Progress edge
// ════════════════════════════════════════════════════════════════════════════

/// The 3px edge along the bottom of a row head (`B2`: 进度 = 贴行底 3px 细边，
/// 绝对定位不占行高).
///
/// Positioned by the card rather than laid out in the row: a task that starts
/// running must not make its row taller, which on a working queue is every
/// row below it jumping down and back up. A failed task that stopped part way
/// keeps its residue in the error colour.
class _ProgressEdge extends StatelessWidget {
  const _ProgressEdge({required this.task});

  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final running = task.status == TaskStatus.processing;
    final residue = task.status == TaskStatus.failed && (task.progress ?? 0) > 0;
    if (!running && !residue) return const SizedBox.shrink();

    return SmoothProgress(
      value: task.progress,
      builder: (context, value) => LinearProgressIndicator(
        value: running ? value : task.progress,
        minHeight: 3,
        borderRadius: BorderRadius.zero,
        backgroundColor: scheme.surfaceContainerHighest,
        valueColor: AlwaysStoppedAnimation<Color>(running ? scheme.primary : scheme.error),
      ),
    );
  }
}
