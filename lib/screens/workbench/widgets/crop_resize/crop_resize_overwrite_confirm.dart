part of '../crop_resize_toolbar.dart';

extension _OverwriteConfirm on _CropResizeToolbarState {
  /// The last stop before an original is replaced.
  ///
  /// Three outcomes, not two: `true` overwrite, `false` save a copy instead,
  /// `null` cancelled. The middle one is the point of the dialog — a confirm
  /// that only offers "yes" and "no" leaves someone who wanted to keep the
  /// original with nothing to do but start over, so the safe alternative is
  /// offered here, in the moment they are thinking about it.
  Future<bool?> _confirmOverwrite({
    required AppLocalizations l10n,
    required String fileName,
    required String originalSize,
    required String outputSize,
    required String copyDestination,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // `.mono` over the bare generic: the confirm dialog puts the before and
    // after dimensions one above the other, which only reads as a comparison
    // if the digits line up.
    final mono = textTheme.labelMedium?.mono;

    return AppDialog.show<bool>(
      context,
      icon: Icons.warning_amber_rounded,
      // Carries the whole dialog's mood: AppDialog tints the heading's icon
      // plate from this, so naming the error colour here is what makes the
      // plate red rather than the accent.
      iconColor: colorScheme.error,
      title: l10n.overwriteConfirmTitle,
      subtitle: l10n.overwriteConfirmSubtitle,
      maxWidth: 480,
      onClose: () => Navigator.pop(context, null),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.overwriteConfirmMessage, style: textTheme.bodyMedium),
          const SizedBox(height: 12),
          // What is being replaced, and what it becomes. The old→new pair is
          // the one fact that makes this decision answerable, so it gets a
          // surface of its own instead of a line of body text.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Row(
              children: [
                Icon(Icons.image_outlined, size: 18, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    fileName,
                    style: mono,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                const SizedBox(width: 12),
                Text(originalSize, style: mono?.copyWith(color: colorScheme.onSurfaceVariant)),
                const SizedBox(width: 7),
                Icon(Icons.arrow_forward, size: 14, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 7),
                Text(
                  outputSize,
                  // The new dimensions in the error colour: this number is the
                  // irreversible part, and it is what someone scanning the
                  // dialog should land on.
                  style: mono?.copyWith(color: colorScheme.error, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: colorScheme.accentTint,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 16, color: colorScheme.onAccentTint),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${l10n.overwriteConfirmKeepOriginalHint}'
                    '${l10n.cropResizeWillSaveTo(copyDestination)}',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onAccentTint,
                      height: AppType.looseHeight,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.pop(context, null),
        ),
        AppButton(
          label: l10n.overwriteConfirmSaveCopyInstead,
          variant: AppButtonVariant.secondary,
          onPressed: () => Navigator.pop(context, false),
        ),
        AppButton(
          label: l10n.overwriteSource,
          variant: AppButtonVariant.destructive,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
  }
}
