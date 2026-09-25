part of '../prompt_optimizer_view.dart';

/// A staged knowledge-base edit: header, diff or full content, and the
/// approve / reject actions (`A3b · 1a`).
extension _KbEditCard on _PromptOptimizerChatViewState {
  /// Preview card for a knowledge-base edit the agent proposed. Nothing has
  /// been written yet — this card is the approval gate.
  ///
  /// An update shows a unified diff under the header rather than the design's
  /// "Show content" link alone: on a two-line change inside a long document,
  /// the difference between what the agent was asked to do and what it
  /// actually rewrote is invisible in a wall of new text. A create has no diff
  /// to show and keeps the folded full content, which for a new file is the
  /// same thing.
  Widget _buildKbEditCard(
    OptimizerChatEntry entry,
    AppLocalizations l10n,
    ColorScheme colorScheme,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final semantic = context.semantic;
    final state = entry.editState ?? KbEditState.pending;
    final isCreate = entry.oldContent == null;
    final pending = state == KbEditState.pending;
    final editId = entry.editId!;
    final expanded = _expandedKbEdits.contains(editId);
    final content = entry.newContent ?? '';
    final phone = _phone;
    // A model that truncates its output would silently gut the file; the length
    // drop is the cheapest signal for the most destructive failure mode.
    final suspiciousShrink =
        !isCreate &&
        entry.oldContent!.length > 200 &&
        content.length < entry.oldContent!.length ~/ 2;

    final diff = isCreate ? null : _kbDiffFor(editId, entry.oldContent!, content);
    final (added, removed) = diff == null ? (_lineCount(content), 0) : (diff.added, diff.removed);

    void toggleContent() => _rebuild(() {
      if (!_expandedKbEdits.remove(editId)) _expandedKbEdits.add(editId);
    });

    return _underAvatar(
      LayoutBuilder(
        builder: (context, box) {
          // Where the card is too narrow for path, badge and link on one line,
          // the link drops to its own row: the path is the only thing in the
          // header that ellipsizing does not make useless, and it has to keep
          // enough room to be read.
          final wide = box.maxWidth >= _PromptOptimizerChatViewState._kbEditWideHeader;
          final showToggle = _textAction(
            expanded ? l10n.kbEditHide : l10n.kbEditShow(content.length),
            toggleContent,
          );

          return _card(
            children: [
              _cardHeader(
                icon: isCreate ? Icons.note_add_outlined : Icons.edit_document,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            entry.targetPath ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall?.mono.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Green for a new file, blue for one being changed —
                        // the distinction that matters: a create cannot
                        // destroy anything, an update can.
                        _statusBadge(
                          isCreate ? l10n.kbEditProposedCreate : l10n.kbEditProposedUpdate,
                          ground: isCreate ? semantic.successContainer : semantic.infoContainer,
                          ink: isCreate ? semantic.onSuccessContainer : semantic.onInfoContainer,
                        ),
                      ],
                    ),
                  ),
                  if (!isCreate && (added > 0 || removed > 0)) ...[
                    const SizedBox(width: 8),
                    if (added > 0)
                      Text(
                        '+$added',
                        style: textTheme.labelSmall?.mono.copyWith(color: semantic.success),
                      ),
                    if (added > 0 && removed > 0) const SizedBox(width: 6),
                    if (removed > 0)
                      Text(
                        '−$removed',
                        style: textTheme.labelSmall?.mono.copyWith(color: colorScheme.error),
                      ),
                    const SizedBox(width: 4),
                  ],
                  if (isCreate && wide) ...[const SizedBox(width: 8), showToggle],
                ],
              ),
              if (!isCreate && entry.editScope != KbEditScope.file)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Text(
                    switch (entry.editScope) {
                      KbEditScope.replaceSection => l10n.kbEditScopeReplace(
                        entry.editSection ?? '',
                      ),
                      _ when entry.editSection == null => l10n.kbEditScopeAppendEnd,
                      _ => l10n.kbEditScopeAppend(entry.editSection!),
                    },
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelSmall?.mono.copyWith(
                      fontWeight: FontWeight.w400,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (entry.note != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: Text(
                    entry.note!,
                    style: textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w400,
                      color: colorScheme.onSurfaceVariant,
                      height: AppType.proseHeight,
                    ),
                  ),
                ),
              if (suspiciousShrink)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: semantic.warningContainer,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(
                            Icons.warning_amber_outlined,
                            size: AppSize.iconSm,
                            color: semantic.warning,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            l10n.kbEditShrinkWarning(entry.oldContent!.length, content.length),
                            style: textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w400,
                              color: semantic.onWarningContainer,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (isCreate) ...[
                if (!wide)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 12, 0),
                    child: Align(alignment: Alignment.centerLeft, child: showToggle),
                  ),
                if (expanded) _buildKbEditFullContent(content, colorScheme, textTheme),
              ] else
                _buildKbEditDiff(diff!.hunks, content, colorScheme, textTheme, semantic),
              if (pending)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: phone
                      ? Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: _PromptOptimizerChatViewState._phoneActionHeight,
                                child: AppButton(
                                  label: l10n.kbEditReject,
                                  variant: AppButtonVariant.secondary,
                                  fullWidth: true,
                                  onPressed: () => widget.onRejectKbEdit(editId),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SizedBox(
                                height: _PromptOptimizerChatViewState._phoneActionHeight,
                                child: AppButton(
                                  label: l10n.kbEditApply,
                                  variant: AppButtonVariant.tonal,
                                  fullWidth: true,
                                  onPressed: () => widget.onApplyKbEdit(editId),
                                ),
                              ),
                            ),
                          ],
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            AppButton(
                              label: l10n.kbEditReject,
                              variant: AppButtonVariant.secondary,
                              size: AppButtonSize.compact,
                              onPressed: () => widget.onRejectKbEdit(editId),
                            ),
                            const SizedBox(width: 6),
                            AppButton(
                              label: l10n.kbEditApply,
                              variant: AppButtonVariant.tonal,
                              size: AppButtonSize.compact,
                              onPressed: () => widget.onApplyKbEdit(editId),
                            ),
                          ],
                        ),
                )
              else
                _buildKbEditResult(state, l10n, colorScheme, textTheme, semantic),
            ],
          );
        },
      ),
    );
  }

  /// What happened to a decided edit, as one 11px line.
  Widget _buildKbEditResult(
    KbEditState state,
    AppLocalizations l10n,
    ColorScheme colorScheme,
    TextTheme textTheme,
    AppSemanticColors semantic,
  ) {
    final (IconData icon, Color glyph, Color ink, String label) = switch (state) {
      KbEditState.applied => (
        Icons.check_circle_outline,
        semantic.success,
        semantic.onSuccessContainer,
        l10n.kbEditApplied,
      ),
      KbEditState.rejected => (
        Icons.cancel_outlined,
        colorScheme.outline,
        colorScheme.onSurfaceVariant,
        l10n.kbEditRejected,
      ),
      _ => (
        Icons.error_outline,
        colorScheme.error,
        colorScheme.onErrorContainer,
        l10n.kbEditFailedShort,
      ),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Row(
        children: [
          Icon(icon, size: AppSize.iconSm, color: glyph),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall?.copyWith(color: ink),
            ),
          ),
        ],
      ),
    );
  }

  /// The diff body: hunk headers over context, removed and added lines.
  ///
  /// A hunk header names the heading its change sits under, as `git diff`
  /// names the enclosing function: in a long knowledge file `@@ -212 +214`
  /// alone does not say which rule is being rewritten.
  ///
  /// Each line is a full-width band with a coloured left rule — the fill
  /// alone is too pale at 12% to survive being read past, and the rule is
  /// what lets the eye run down the changed region without reading the
  /// `+`/`−` on every line.
  Widget _buildKbEditDiff(
    List<DiffHunk> hunks,
    String newContent,
    ColorScheme colorScheme,
    TextTheme textTheme,
    AppSemanticColors semantic,
  ) {
    if (hunks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: Text(
          AppLocalizations.of(context)!.kbEditNoChange,
          style: textTheme.labelSmall?.copyWith(color: colorScheme.outline),
        ),
      );
    }

    final mono = textTheme.labelSmall?.mono.copyWith(
      fontWeight: FontWeight.w400,
      height: AppType.proseHeight,
    );

    // Capped and scrollable rather than folded behind a link: a diff is read
    // top to bottom and its first lines are not more important than its last,
    // which is the assumption a fold makes.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _PromptOptimizerChatViewState._kbDiffMaxHeight),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final hunk in hunks) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: Text(
                  _hunkHeader(hunk, newContent),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mono?.copyWith(color: colorScheme.outline),
                ),
              ),
              for (final line in hunk.lines) _buildDiffLine(line, colorScheme, semantic, mono),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDiffLine(
    DiffLine line,
    ColorScheme colorScheme,
    AppSemanticColors semantic,
    TextStyle? mono,
  ) {
    final (Color? fill, Color rule, Color ink, String sign) = switch (line.kind) {
      DiffLineKind.added => (
        semantic.success.withValues(alpha: AppAlpha.tint),
        semantic.success,
        semantic.success,
        '+',
      ),
      DiffLineKind.removed => (
        colorScheme.error.withValues(alpha: AppAlpha.tint),
        colorScheme.error,
        colorScheme.error,
        '−',
      ),
      DiffLineKind.context => (null, Colors.transparent, colorScheme.onSurfaceVariant, ' '),
    };

    return Container(
      decoration: BoxDecoration(
        color: fill,
        border: Border(left: BorderSide(color: rule, width: 2)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
      child: Text(
        '$sign ${line.text}',
        maxLines: 1,
        // Clipped, not wrapped: a wrapped diff line loses the one-line-per-line
        // alignment that makes the two sides comparable at a glance.
        overflow: TextOverflow.ellipsis,
        style: mono?.copyWith(color: ink),
      ),
    );
  }

  /// The create case, which has no previous version to diff against: the full
  /// proposed file, shown once the header's link is pressed.
  Widget _buildKbEditFullContent(String content, ColorScheme colorScheme, TextTheme textTheme) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(10),
      constraints: const BoxConstraints(maxHeight: _PromptOptimizerChatViewState._kbDiffMaxHeight),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          content,
          style: textTheme.labelSmall?.mono.copyWith(
            fontWeight: FontWeight.w400,
            height: AppType.proseHeight,
            color: colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// `@@ -old +new` and, when the change sits under one, the heading above its
/// first changed line in the proposed file.
///
/// A removed line has no line of its own in the proposed file: counted
/// there, it lands on the line that now follows the gap — which is the next
/// section's heading when a section's tail (or the whole section) was
/// deleted. The heading is looked up from the line before the gap instead.
String _hunkHeader(DiffHunk hunk, String newContent) {
  var firstChange = hunk.lines.indexWhere((l) => l.kind != DiffLineKind.context);
  if (firstChange < 0) firstChange = 0;
  final removal = hunk.lines.isNotEmpty && hunk.lines[firstChange].kind == DiffLineKind.removed;
  // The context lines before the change each take one line of the new file.
  final line = hunk.newStart + firstChange - (removal ? 1 : 0);
  final heading = line < 1 ? null : KnowledgeBaseService.headingAbove(newContent, line);
  final base = '@@ -${hunk.oldStart} +${hunk.newStart}';
  return heading == null ? base : '$base @@ $heading';
}

int _lineCount(String text) {
  if (text.isEmpty) return 0;
  final trimmed = text.endsWith('\n') ? text.substring(0, text.length - 1) : text;
  return '\n'.allMatches(trimmed).length + 1;
}

// ---------------------------------------------------------------------------
// Prompt versions
// ---------------------------------------------------------------------------
