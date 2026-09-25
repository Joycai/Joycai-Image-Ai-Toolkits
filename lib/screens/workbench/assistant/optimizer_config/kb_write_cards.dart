part of '../optimizer_config_panel.dart';

/// Edit mode's two cards: the write permissions and the pending changes.
extension _KbWriteCards on _OptimizerConfigPanelState {
  /// `A3b 1a`'s write-permissions card: what the agent may do to the folder.
  ///
  /// Three switches rather than one because they fail differently. The first
  /// withdraws the write tool outright — the model is not offered it, so it
  /// cannot be talked into calling it. The second is the approval gate, and
  /// turning it off is the one setting here that lets LLM-authored text reach
  /// the user's files unread; the amber row under it says so, and only while
  /// it is true. The third is the answer to having turned the second off.
  Widget _buildWritePolicy(AppLocalizations l10n, ColorScheme colorScheme, TextTheme textTheme) {
    final policy = widget.writePolicy;
    final semantic = context.semantic;

    void update(KbWritePolicy next) => widget.onWritePolicyChanged?.call(next);

    return OptimizerPanelCard(
      children: [
        OptimizerPanelCaption(l10n.kbWritePolicyTitle),
        _policyRow(
          colorScheme,
          textTheme,
          title: l10n.kbWriteAllow,
          value: policy.allowWrites,
          onChanged: (v) => update(policy.copyWith(allowWrites: v)),
        ),
        _hairlined(
          colorScheme,
          _policyRow(
            colorScheme,
            textTheme,
            title: l10n.kbWriteConfirmEach,
            value: policy.confirmEachWrite,
            // Off with writing itself off: nothing can be proposed, so there is
            // nothing to confirm.
            onChanged: policy.allowWrites
                ? (v) => update(policy.copyWith(confirmEachWrite: v))
                : null,
          ),
        ),
        if (policy.allowWrites && !policy.confirmEachWrite)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: AppSpace.s6),
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
                    Icons.warning_amber_rounded,
                    size: AppSize.iconSm,
                    color: semantic.warning,
                  ),
                ),
                const SizedBox(width: AppSpace.s6),
                Expanded(
                  child: Text(
                    l10n.kbWriteNoConfirmWarning,
                    style: textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w400,
                      color: semantic.onWarningContainer,
                      height: AppType.proseHeight,
                    ),
                  ),
                ),
              ],
            ),
          ),
        _hairlined(
          colorScheme,
          _policyRow(
            colorScheme,
            textTheme,
            title: l10n.kbWriteBackup,
            value: policy.backupBeforeOverwrite,
            onChanged: policy.allowWrites
                ? (v) => update(policy.copyWith(backupBeforeOverwrite: v))
                : null,
          ),
        ),
      ],
    );
  }

  Widget _policyRow(
    ColorScheme colorScheme,
    TextTheme textTheme, {
    required String title,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return ConstrainedBox(
      // `1d` gives each switch row a 44px touch band in the phone sheet.
      constraints: BoxConstraints(minHeight: _touch ? AppSize.touch - OptimizerPanelCard.gap : 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: (_touch ? textTheme.bodyMedium : textTheme.bodySmall)?.copyWith(
                color: onChanged == null ? colorScheme.onSurfaceVariant : colorScheme.onSurface,
                height: AppType.tightHeight,
              ),
            ),
          ),
          const SizedBox(width: OptimizerPanelCard.gap),
          AppSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  /// `A3b 1a`'s pending-changes card: every staged edit in one list, and the
  /// two bulk answers.
  ///
  /// The transcript already carries each edit as its own reviewable card, so
  /// this is deliberately not a second place to review them — it is the count,
  /// the files, and the way out of a queue of six without scrolling back
  /// through six cards to find them.
  Widget _buildPendingKbEdits(AppLocalizations l10n, ColorScheme colorScheme, TextTheme textTheme) {
    final edits = widget.pendingKbEdits;
    final onWriteAll = widget.running ? null : widget.onWriteAllKbEdits;
    final onDiscardAll = widget.running ? null : widget.onDiscardAllKbEdits;

    final Widget actions = _touch
        // `1d`: two equal 44px buttons across the sheet.
        ? Row(
            children: [
              Expanded(
                child: AppButton(
                  label: l10n.kbEditDiscardAll,
                  variant: AppButtonVariant.destructiveOutline,
                  size: AppButtonSize.large,
                  fullWidth: true,
                  onPressed: onDiscardAll,
                ),
              ),
              const SizedBox(width: OptimizerPanelCard.gap),
              Expanded(
                child: AppButton(
                  label: l10n.kbEditWriteAll,
                  size: AppButtonSize.large,
                  fullWidth: true,
                  onPressed: onWriteAll,
                ),
              ),
            ],
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(
                child: AppButton(
                  label: l10n.kbEditDiscardAll,
                  variant: AppButtonVariant.destructiveText,
                  size: AppButtonSize.compact,
                  onPressed: onDiscardAll,
                ),
              ),
              const SizedBox(width: AppSpace.s6),
              Flexible(
                child: AppButton(
                  label: l10n.kbEditWriteAll,
                  size: AppButtonSize.compact,
                  onPressed: onWriteAll,
                ),
              ),
            ],
          );

    return OptimizerPanelCard(
      children: [
        OptimizerPanelCaption(
          l10n.kbEditPendingTitle,
          trailing: Text(
            '${edits.length}',
            style: _monoStyle(textTheme, colorScheme.onSurfaceVariant),
          ),
        ),
        for (final edit in edits) _buildPendingRow(edit, l10n, colorScheme, textTheme),
        _hairlined(colorScheme, actions),
      ],
    );
  }

  Widget _buildPendingRow(
    OptimizerChatEntry edit,
    AppLocalizations l10n,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final semantic = context.semantic;
    final isCreate = edit.oldContent == null;
    final (added, removed) = _pendingCounts(edit);
    // The line counts ride on the row's tooltip: the column narrows to 250px,
    // and the path and its change kind are what have to survive there.
    final counts = [if (added > 0) '+$added', if (removed > 0) '−$removed'].join(' ');

    final row = ConstrainedBox(
      constraints: BoxConstraints(minHeight: _touch ? AppSize.large - OptimizerPanelCard.gap : 0),
      child: Row(
        children: [
          Icon(
            isCreate ? Icons.note_add_outlined : Icons.edit_document,
            size: AppSize.iconMd,
            color: isCreate ? semantic.success : semantic.info,
          ),
          const SizedBox(width: OptimizerPanelCard.gap),
          Expanded(
            child: _ElidedPath(
              path: edit.targetPath ?? '',
              style: (_touch ? textTheme.bodySmall?.mono : textTheme.labelSmall?.mono)?.copyWith(
                fontWeight: FontWeight.w400,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: OptimizerPanelCard.gap),
          OptimizerTagBadge(
            mono: true,
            label: isCreate ? l10n.optKbTreeAdded : l10n.optKbTreeChanged,
            background: isCreate ? semantic.successContainer : semantic.infoContainer,
            foreground: isCreate ? semantic.onSuccessContainer : semantic.onInfoContainer,
          ),
        ],
      ),
    );
    return counts.isEmpty ? row : Tooltip(message: counts, child: row);
  }

  /// Line counts for one staged edit, memoized by its id.
  ///
  /// A staged edit is immutable — its content is fixed when the agent proposes
  /// it and only its *state* ever changes — so the cache cannot go stale. It
  /// is worth having because this panel rebuilds on every session
  /// notification, and diffing several documents per rebuild is real work to
  /// redo for an answer that cannot have changed.
  (int, int) _pendingCounts(OptimizerChatEntry edit) {
    final id = edit.editId ?? '';
    final cached = _kbEditCounts[id];
    if (cached != null) return cached;

    final content = edit.newContent ?? '';
    final counts = edit.oldContent == null
        ? (_lineCount(content), 0)
        : TextDiff.counts(edit.oldContent!, content);
    _kbEditCounts[id] = counts;
    return counts;
  }
}

int _lineCount(String text) {
  if (text.isEmpty) return 0;
  final trimmed = text.endsWith('\n') ? text.substring(0, text.length - 1) : text;
  return '\n'.allMatches(trimmed).length + 1;
}
