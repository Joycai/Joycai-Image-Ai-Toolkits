part of '../prompt_optimizer_view.dart';

/// A generation-feedback round as the user sent it.
extension _FeedbackCard on _PromptOptimizerChatViewState {
  /// The generation-feedback turn: the result image's thumbnail, what the
  /// user said about it, and which file and version it reports on.
  Widget _buildResultFeedbackCard(
    OptimizerChatEntry entry,
    AppLocalizations l10n,
    ColorScheme colorScheme,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final imageName = entry.note;
    // Resolved by name against the live reference list: the transcript stores
    // no paths (they must not ship to providers), and the panel already owns
    // the name → image binding. A missing image degrades to a plain glyph.
    final image = imageName == null
        ? null
        : context.watch<WorkbenchUIState>().optimizerReferenceImages.cast<AppImage?>().firstWhere(
            (i) => i?.name == imageName,
            orElse: () => null,
          );
    final monoMeta = textTheme.labelSmall?.mono.copyWith(
      fontWeight: FontWeight.w400,
      color: colorScheme.onSurfaceVariant,
    );

    return _besideAvatar(
      _avatar(
        Icons.rate_review_outlined,
        ground: colorScheme.surfaceContainerHigh,
        ink: colorScheme.onSurfaceVariant,
      ),
      _card(
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: SizedBox.square(
                    dimension: 44,
                    child: image != null
                        ? Image(image: image.imageProvider, fit: BoxFit.cover)
                        : ColoredBox(
                            color: colorScheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.image_outlined,
                              size: AppSize.iconMd,
                              color: colorScheme.outline,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.optResultFeedbackChatLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelSmall?.copyWith(
                          color: colorScheme.accentText,
                          letterSpacing: AppType.trackedLabelSpacing,
                        ),
                      ),
                      // The verdict (`3b`) as a filled chip, its reason tags
                      // as quiet ones; then the note, when there is one.
                      if (entry.feedbackSatisfied case final satisfied?) ...[
                        const SizedBox(height: 5),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _feedbackChip(
                              resultFeedbackVerdictLabel(l10n, satisfied),
                              icon: satisfied ? Icons.thumb_up : Icons.thumb_down,
                              fill: colorScheme.accentTint,
                              ink: colorScheme.accentText,
                              textTheme: textTheme,
                            ),
                            for (final reason in entry.feedbackReasons)
                              _feedbackChip(
                                resultFeedbackReasonLabel(l10n, reason),
                                fill: colorScheme.surfaceContainerHigh,
                                ink: colorScheme.onSurfaceVariant,
                                textTheme: textTheme,
                              ),
                          ],
                        ),
                      ],
                      if (entry.text.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        SelectableText(
                          entry.text,
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurface,
                            height: AppType.looseHeight,
                          ),
                        ),
                      ],
                      if (imageName != null || entry.version != null) ...[
                        const SizedBox(height: 4),
                        // Separate texts, not one joined string: the file name
                        // is the part that ellipsizes, the version never does.
                        Row(
                          children: [
                            if (imageName != null)
                              Flexible(
                                child: Text(
                                  imageName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: monoMeta,
                                ),
                              ),
                            if (imageName != null && entry.version != null)
                              Text(' · ', style: monoMeta),
                            if (entry.version != null) Text('v${entry.version}', style: monoMeta),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A 22px pill on the feedback card: the verdict in the accent tint, a
  /// reason tag on the high container.
  Widget _feedbackChip(
    String label, {
    IconData? icon,
    required Color fill,
    required Color ink,
    required TextTheme textTheme,
  }) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(11)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: AppSize.iconSm, color: ink),
            const SizedBox(width: AppSpace.s4),
          ],
          Text(
            label,
            style: textTheme.labelSmall?.copyWith(
              color: ink,
              fontWeight: icon != null ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
