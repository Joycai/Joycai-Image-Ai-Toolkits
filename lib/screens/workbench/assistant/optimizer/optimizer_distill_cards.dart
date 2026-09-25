part of '../prompt_optimizer_view.dart';

/// The knowledge-base distill request and its wrap-up card (`20d`).
extension _DistillCards on _PromptOptimizerChatViewState {
  /// The distill request. The user pressed a button, so it reads as a turn in
  /// their voice, but the boilerplate instruction it carries is not worth a
  /// bubble of body text. The design's step checklist is deliberately not
  /// drawn — the app does not know those steps, and the real tool timeline
  /// that follows this entry shows what the agent actually did.
  Widget _buildKbDistillRequestCard(AppLocalizations l10n, ColorScheme colorScheme) {
    final textTheme = Theme.of(context).textTheme;
    return _besideAvatar(
      _avatar(
        Icons.auto_stories_outlined,
        ground: colorScheme.surfaceContainerHigh,
        ink: colorScheme.onSurfaceVariant,
      ),
      _card(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.optDistillAction,
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.accentText,
                    letterSpacing: AppType.trackedLabelSpacing,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  l10n.optKbDistillRequested,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: AppType.looseHeight,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The distill wrap-up card: which files the session's lessons landed in,
  /// with real +/− line counts from the same diff the review cards showed.
  Widget _buildDistillDoneCard(
    PromptOptimizerSession session,
    List<OptimizerChatEntry> applied,
    AppLocalizations l10n,
    ColorScheme colorScheme,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final semantic = context.semantic;

    return _underAvatar(
      _card(
        children: [
          _cardHeader(
            icon: Icons.check_circle_outline,
            iconColor: semantic.success,
            children: [
              Expanded(
                child: Text(
                  l10n.optDistillDoneTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _cardTitleStyle,
                ),
              ),
              if (session.promptVersions > 0) ...[
                const SizedBox(width: 8),
                _versionBadge('v${session.promptVersions}'),
                const SizedBox(width: 4),
              ],
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final edit in applied)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Icon(
                          Icons.description_outlined,
                          size: AppSize.iconSm,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            edit.targetPath ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall?.mono.copyWith(color: colorScheme.onSurface),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ..._lineCountBadges(edit, textTheme, semantic, colorScheme),
                        if (edit.note != null) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              edit.note!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w400,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (widget.onSaveFinalPrompt != null && session.refinedPrompt != null)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                // Tonal, like Apply: it puts the model's output to use.
                child: AppButton(
                  label: l10n.optSaveFinalPrompt,
                  icon: Icons.bookmark_add_outlined,
                  variant: AppButtonVariant.tonal,
                  size: AppButtonSize.compact,
                  onPressed: widget.onSaveFinalPrompt,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// `+a` / `−r` from the staged edit's own before/after texts — the same
  /// numbers the review card's diff showed, so the wrap-up never claims a
  /// different change than the one that was approved.
  List<Widget> _lineCountBadges(
    OptimizerChatEntry edit,
    TextTheme textTheme,
    AppSemanticColors semantic,
    ColorScheme colorScheme,
  ) {
    final (added, removed) = TextDiff.counts(edit.oldContent ?? '', edit.newContent ?? '');
    final style = textTheme.labelSmall?.mono.copyWith(fontWeight: FontWeight.w600);
    return [
      if (added > 0) Text('+$added', style: style?.copyWith(color: semantic.success)),
      if (added > 0 && removed > 0) const SizedBox(width: 4),
      if (removed > 0) Text('−$removed', style: style?.copyWith(color: colorScheme.error)),
    ];
  }

  // ---------------------------------------------------------------------------
  // Composer
  // ---------------------------------------------------------------------------
}

/// The applied edits of the finished distill turn plus where its wrap-up
/// card belongs, or null when the card (`20d`·d) has nothing to say: no
/// distill ran, an edit is still awaiting review, or nothing reached disk.
/// Derived from the transcript on every build — the card's presence IS the
/// state, so there is nothing to invalidate.
///
/// [insertBefore] is the transcript index where the distill turn ends — the
/// next user-initiated entry after it, or the transcript length when the
/// distill is the latest activity. The card anchors there rather than at the
/// list tail, so continuing the conversation does not leave it floating
/// below later messages with a version badge that no longer matches.
({List<OptimizerChatEntry> applied, int insertBefore})? _distillOutcome(
  List<OptimizerChatEntry> transcript,
) {
  int distillIndex = -1;
  for (var i = transcript.length - 1; i >= 0; i--) {
    if (transcript[i].kind == OptimizerEntryKind.kbDistill) {
      distillIndex = i;
      break;
    }
  }
  if (distillIndex < 0) return null;
  // The distill turn runs until the next user-initiated entry (a typed
  // message, a result-feedback report, or another distill request).
  int boundary = transcript.length;
  for (var i = distillIndex + 1; i < transcript.length; i++) {
    final k = transcript[i].kind;
    if (k == OptimizerEntryKind.user ||
        k == OptimizerEntryKind.resultFeedback ||
        k == OptimizerEntryKind.kbDistill) {
      boundary = i;
      break;
    }
  }
  final applied = <OptimizerChatEntry>[];
  for (var i = distillIndex + 1; i < boundary; i++) {
    final e = transcript[i];
    if (e.kind != OptimizerEntryKind.kbEdit) continue;
    // A pending edit means the review is still open — summarizing now
    // would claim an outcome the user has not decided yet.
    if (e.editState == KbEditState.pending) return null;
    if (e.editState == KbEditState.applied) applied.add(e);
  }
  if (applied.isEmpty) return null;
  return (applied: applied, insertBefore: boundary);
}
