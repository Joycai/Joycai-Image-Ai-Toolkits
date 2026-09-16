part of '../ai_rename_dialog.dart';

/// The 11/500 tracked caption in the deep accent that heads a config group.
class _Caption extends StatelessWidget {
  final String text;

  const _Caption(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelSmall!.copyWith(
            color: Theme.of(context).colorScheme.onAccentTint,
            letterSpacing: AppType.trackedLabelSpacing,
          ),
    );
  }
}

/// Centres [child] in the space given, scrolling when the space is shorter.
class _CenteredScroll extends StatelessWidget {
  final Widget child;

  const _CenteredScroll({required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(padding: const EdgeInsets.all(AppSpace.s22), child: child),
          ),
        ),
      ),
    );
  }
}

/// `1e` 列表末: the list is still growing.
class _GeneratingRow extends StatelessWidget {
  final String label;

  const _GeneratingRow({required this.label});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colorScheme.primary,
              backgroundColor: colorScheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(width: AppSpace.s10),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall!.copyWith(color: colorScheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// `1e` 行 52: thumbnail · old name → new name · badge · inline actions.
class _ResultRow extends StatelessWidget {
  final RenameReviewRow row;
  final bool narrow;

  /// Actions as glyphs with tooltips, for a list too narrow for their labels.
  final bool iconOnly;

  final bool editing;
  final TextEditingController editController;
  final VoidCallback onUndoSkip;
  final VoidCallback onSkip;
  final VoidCallback onEdit;
  final ValueChanged<String> onCommitEdit;
  final ValueChanged<RenameConflictChoice> onResolve;

  const _ResultRow({
    required this.row,
    required this.narrow,
    required this.iconOnly,
    required this.editing,
    required this.editController,
    required this.onUndoSkip,
    required this.onSkip,
    required this.onEdit,
    required this.onCommitEdit,
    required this.onResolve,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final mono12 = textTheme.bodySmall!.mono;
    final unresolved = row.unresolved;

    final Color ground = unresolved
        ? colorScheme.errorContainer
        : (row.skipped ? colorScheme.surfaceContainer : colorScheme.surface);
    final Color newInk = unresolved
        ? colorScheme.onErrorContainer
        : (row.skipped ? colorScheme.outline : colorScheme.onSurface);

    final oldName = Tooltip(
      message: row.path,
      waitDuration: const Duration(milliseconds: 500),
      child: Text(
        row.oldName,
        style: mono12.copyWith(color: colorScheme.onSurfaceVariant),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      ),
    );

    final Widget newName = editing
        ? SizedBox(
            height: AppSize.compact,
            child: TextField(
              controller: editController,
              autofocus: true,
              style: mono12,
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: colorScheme.surface,
                // 28, not the 32 control: an editor inside a table row.
                constraints: const BoxConstraints.tightFor(height: AppSize.compact),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: pinnedFieldInset(context, mono12, AppSize.compact),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  borderSide: BorderSide(color: colorScheme.primary),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  borderSide: BorderSide(color: colorScheme.primary),
                ),
              ),
              onSubmitted: onCommitEdit,
              onTapOutside: (_) => onCommitEdit(editController.text),
            ),
          )
        : Text(
            row.newName,
            style: mono12.copyWith(color: newInk, fontWeight: FontWeight.w500),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          );

    final Widget? badge;
    if (row.skipped) {
      badge = TransferBadge(label: l10n.renameSkippedBadge, tone: TransferTone.track);
    } else if (unresolved) {
      badge = TransferBadge(label: l10n.renameDuplicateBadge, tone: TransferTone.err, outlined: true);
    } else if (row.choice == RenameConflictChoice.overwrite) {
      badge = TransferBadge(label: l10n.conflictOverwrite, tone: TransferTone.err);
    } else if (row.autoRenamed) {
      badge = TransferBadge(label: l10n.renameRenamedBadge, tone: TransferTone.ok);
    } else {
      badge = null;
    }

    final List<Widget> actions;
    if (row.skipped) {
      actions = [
        _RowAction(
          icon: Icons.undo,
          label: l10n.renameActionUndo,
          color: colorScheme.onAccentTint,
          iconOnly: iconOnly,
          onTap: onUndoSkip,
        ),
      ];
    } else if (unresolved) {
      actions = [
        _RowAction(
          icon: Icons.auto_fix_high,
          label: l10n.renameConflictAutoRename,
          color: colorScheme.onAccentTint,
          iconOnly: iconOnly,
          onTap: () => onResolve(RenameConflictChoice.rename),
        ),
        // Overwrite is the only answer that destroys a file, so it is the
        // only one in the error colour. On a clash between two rows there is
        // no file to replace yet — only the other row's result — so it stays
        // visible but unavailable, and says why (`resolveRenameConflict`
        // refuses it too).
        _RowAction(
          icon: Icons.swap_horiz,
          label: l10n.conflictOverwrite,
          color: colorScheme.error,
          iconOnly: iconOnly,
          onTap: row.conflict == RenameConflict.duplicate
              ? null
              : () => onResolve(RenameConflictChoice.overwrite),
          disabledHint: l10n.renameOverwriteDuplicateHint,
        ),
        _RowAction(
          icon: Icons.block,
          label: l10n.renameActionSkip,
          color: colorScheme.onSurfaceVariant,
          iconOnly: true,
          onTap: () => onResolve(RenameConflictChoice.skip),
        ),
      ];
    } else {
      actions = [
        _RowAction(
          icon: Icons.edit_outlined,
          label: l10n.renameActionEdit,
          color: colorScheme.onSurfaceVariant,
          iconOnly: iconOnly,
          active: editing,
          onTap: onEdit,
        ),
        _RowAction(
          icon: Icons.block,
          label: l10n.renameActionSkip,
          color: colorScheme.onSurfaceVariant,
          iconOnly: iconOnly,
          onTap: onSkip,
        ),
      ];
    }

    return AnimatedContainer(
      duration: AppMotion.durationOf(context, AppMotion.hover),
      curve: AppMotion.quick,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: ground,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          TransferThumb(path: row.path, size: 32),
          const SizedBox(width: AppSpace.s10),
          if (narrow)
            // Two lines instead of two columns: at this width the columns are
            // too narrow for either name to survive its own ellipsis.
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  oldName,
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.subdirectory_arrow_right, size: 12, color: colorScheme.outline),
                      const SizedBox(width: AppSpace.s4),
                      Expanded(child: newName),
                    ],
                  ),
                ],
              ),
            )
          else ...[
            SizedBox(width: _kOldNameWidth, child: oldName),
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward, size: AppSize.iconSm, color: colorScheme.outline),
            const SizedBox(width: 8),
            Expanded(child: newName),
          ],
          if (badge != null) ...[const SizedBox(width: 8), badge],
          const SizedBox(width: 8),
          for (final (index, action) in actions.indexed) ...[
            if (index > 0) const SizedBox(width: 2),
            action,
          ],
        ],
      ),
    );
  }
}

/// A 28px inline row action: a text button with its glyph, or the glyph alone
/// with the label as its tooltip.
class _RowAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool iconOnly;
  final bool active;

  /// Null draws the action disabled; [disabledHint] then says why.
  final VoidCallback? onTap;
  final String? disabledHint;

  const _RowAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.iconOnly,
    required this.onTap,
    this.active = false,
    this.disabledHint,
  });

  /// Everything a labelled action takes besides its label: 8px of padding a
  /// side, the glyph, and Material's gap after it.
  static const double chrome = 16 + AppSize.iconSm + 8;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm));

    final String? hint = onTap == null ? disabledHint : null;

    if (iconOnly) {
      return IconButton(
        icon: Icon(icon, size: AppSize.iconSm),
        tooltip: hint == null ? label : '$label — $hint',
        onPressed: onTap,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: AppSize.compact, height: AppSize.compact),
        style: IconButton.styleFrom(
          foregroundColor: color,
          backgroundColor: active ? colorScheme.accentTint : null,
          shape: shape,
        ),
      );
    }

    final button = TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: AppSize.iconSm),
      label: Text(label, maxLines: 1),
      style: TextButton.styleFrom(
        foregroundColor: color,
        backgroundColor: active ? colorScheme.accentTint : null,
        minimumSize: const Size(0, AppSize.compact),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        textStyle: Theme.of(context).textTheme.labelMedium,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        shape: shape,
      ),
    );
    return hint == null ? button : Tooltip(message: hint, child: button);
  }
}
