part of '../optimizer_config_panel.dart';

/// The knowledge base's status card and the files this round cited.
extension _KnowledgeCards on _OptimizerConfigPanelState {
  /// `A3b 1b`'s knowledge card: a status badge, then either what the base
  /// holds or what is wrong with it and the way out.
  Widget _buildKnowledgeStatus(
    AppLocalizations l10n,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final semantic = context.semantic;
    final status = widget.kbStatus;
    final noteStyle = _noteStyle(colorScheme, textTheme);
    final pathStyle = _monoStyle(textTheme, colorScheme.onSurfaceVariant);

    // Ready / Reading are the accent's — a configured base is a source the
    // agent reads from on every turn, not a finished job. The three faults
    // take the track (nothing chosen yet), the error wash (a folder that is
    // gone) and the warning wash (a folder missing its entry file).
    final (String label, Color background, Color foreground) = switch (status) {
      KbStatus.ok => (
        widget.running ? l10n.optKbSearching : l10n.optKbReady,
        colorScheme.accentTint,
        colorScheme.onAccentTint,
      ),
      KbStatus.notSet => (
        l10n.notSet,
        colorScheme.surfaceContainerHighest,
        colorScheme.onSurfaceVariant,
      ),
      KbStatus.missingDir => (
        l10n.kbInvalidDir,
        colorScheme.errorContainer,
        colorScheme.onErrorContainer,
      ),
      KbStatus.missingEntry => (
        l10n.optKbEntryMissingShort(KnowledgeBaseService.entryFileName),
        semantic.warningContainer,
        semantic.onWarningContainer,
      ),
    };
    final badge = OptimizerTagBadge(
      label: label,
      background: background,
      foreground: foreground,
      leading: status == KbStatus.ok
          ? AppBreathingDot(color: colorScheme.primary, size: 6, breathing: widget.running)
          : null,
    );

    if (status != KbStatus.ok) {
      return OptimizerPanelCard(
        children: [
          Align(alignment: AlignmentDirectional.centerStart, child: badge),
          if (status == KbStatus.missingDir && (widget.kbPath ?? '').isNotEmpty)
            _ElidedPath(path: widget.kbPath!, style: pathStyle),
          if (status == KbStatus.missingDir) Text(l10n.optKbPathInvalidDesc, style: noteStyle),
          if (status == KbStatus.notSet) Text(l10n.optKbNotConfigured, style: noteStyle),
          if (status == KbStatus.missingEntry) Text(l10n.kbMissingEntry, style: noteStyle),
          AppButton(
            label: l10n.kbScaffoldCreate,
            // Solid where there is nothing yet, tonal where the folder only
            // needs its entry file, and the quiet form beside a folder that is
            // gone — where initializing is the less likely answer.
            variant: switch (status) {
              KbStatus.notSet => AppButtonVariant.primary,
              KbStatus.missingEntry => AppButtonVariant.tonal,
              _ => AppButtonVariant.secondary,
            },
            accentLabel: true,
            size: _touch ? AppButtonSize.normal : AppButtonSize.compact,
            fullWidth: true,
            loading: _scaffolding,
            onPressed: _handleScaffold,
          ),
        ],
      );
    }

    final stats = _kbStats;
    final updated = stats?.newestModified;

    return OptimizerPanelCard(
      children: [
        Row(
          children: [
            badge,
            const Spacer(),
            // Off during a turn: the agent is reading this folder right now,
            // and a count taken mid-run describes a tree the answer on screen
            // was not built from.
            _TextLink(
              label: l10n.optKbRescan,
              loading: _scanning,
              onTap: widget.running ? null : _loadKbStats,
            ),
          ],
        ),
        _ElidedPath(path: widget.kbPath ?? '', style: pathStyle),
        // Nothing rather than a spinner while there are no counts: a scan that
        // fails would otherwise leave one turning forever. Rescan carries the
        // progress instead, where it resolves.
        //
        // "Content updated", not "last indexed": there is no index. The
        // question the user is asking is whether the edit they just made will
        // be picked up, which the newest file timestamp answers directly.
        if (stats != null)
          Text(l10n.optKbTreeStats(stats.files, stats.directories), style: noteStyle),
        if (updated != null)
          Text(l10n.optKbContentUpdated(_formatStamp(updated)), style: noteStyle),
        Wrap(
          spacing: AppSpace.s10,
          runSpacing: AppSpace.s4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _TextLink(
              label: l10n.openInFolder,
              onTap: widget.kbPath == null ? null : () => FileUtils.openPath(widget.kbPath!),
            ),
            // Kept visible and disabled once the base has an entry file, rather
            // than hidden: initializing is a one-time act, and an action that
            // silently disappears leaves the user wondering where it went. The
            // tooltip says why it is off. KnowledgeBaseStarter.scaffold refuses
            // independently — this is only the first gate.
            Tooltip(
              message: l10n.kbScaffoldAlreadyInit(KnowledgeBaseService.entryFileName),
              child: AppButton(
                label: l10n.kbScaffoldCreate,
                variant: AppButtonVariant.text,
                size: AppButtonSize.compact,
                onPressed: null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// `HH:mm` while it is today's date, `MM-DD HH:mm` once it is not — a bare
  /// clock time on a three-day-old file reads as "just now".
  String _formatStamp(DateTime when) {
    String two(int v) => v.toString().padLeft(2, '0');
    final now = DateTime.now();
    final clock = '${two(when.hour)}:${two(when.minute)}';
    final sameDay = when.year == now.year && when.month == now.month && when.day == now.day;
    return sameDay ? clock : '${two(when.month)}-${two(when.day)} $clock';
  }

  /// The documents holding up the answer on screen.
  ///
  /// Derived from the session's own history rather than tracked, so it cannot
  /// drift from what was actually sent — see
  /// [PromptOptimizerAgent.citedKnowledgeFiles].
  Widget _buildCitedThisRound(AppLocalizations l10n, ColorScheme colorScheme, TextTheme textTheme) {
    final cited = widget.citedKnowledgeFiles;
    final shown = cited.take(_OptimizerConfigPanelState._citedPreviewCount).toList();
    final more = cited.length > shown.length;
    final allLabel = Text(
      l10n.optKbCitedAll(cited.length),
      style: textTheme.labelMedium?.copyWith(color: colorScheme.onAccentTint),
    );

    return OptimizerPanelCard(
      children: [
        OptimizerPanelCaption(
          l10n.optKbCitedThisRound,
          // `2 · in progress` while the turn runs: "the answer rests on these
          // documents" and "on these so far" are different claims.
          trailing: widget.running
              ? Text(
                  '${cited.length} · ${l10n.optKbCitedRunning}',
                  style: _monoStyle(textTheme, colorScheme.onAccentTint),
                )
              : (more ? allLabel : null),
        ),
        if (cited.isEmpty)
          Text(
            l10n.optKbCitedNone,
            style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
          )
        else
          for (final path in shown)
            Row(
              children: [
                Icon(Icons.description_outlined, size: AppSize.iconSm, color: colorScheme.outline),
                const SizedBox(width: AppSpace.s6),
                Expanded(
                  child: Text(
                    path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _monoStyle(textTheme, colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
        // While running the caption carries the progress, so the total that
        // would otherwise sit there moves under the list.
        if (widget.running && more) allLabel,
      ],
    );
  }
}
