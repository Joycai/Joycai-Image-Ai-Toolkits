part of '../optimizer_config_panel.dart';

extension _TimelineCard on _OptimizerConfigPanelState {
  /// The iteration timeline: every prompt version with the feedback rounds
  /// between them, projected from the transcript on each build.
  ///
  /// Null for a session with no versions yet — a timeline card with no story
  /// under its heading is noise. No tap-to-jump (the transcript is a lazy list,
  /// and a control that promises navigation it cannot deliver is worse than
  /// none), and no time column: transcript entries carry no timestamp.
  Widget? _buildIterationTimeline(AppLocalizations l10n, ColorScheme colorScheme, TextTheme textTheme) {
    final nodes = <(OptimizerEntryKind, String, int?)>[
      for (final e in widget.transcript)
        if (e.kind == OptimizerEntryKind.prompt)
          (e.kind, e.note ?? l10n.optPromptVersionLabel, e.version)
        else if (e.kind == OptimizerEntryKind.resultFeedback)
          (e.kind, resultFeedbackSummary(l10n, e), e.version),
    ];
    final versionCount = nodes.where((n) => n.$1 == OptimizerEntryKind.prompt).length;
    if (versionCount == 0) return null;
    final lastVersionIndex = nodes.lastIndexWhere((n) => n.$1 == OptimizerEntryKind.prompt);

    return OptimizerPanelCard(
      children: [
        OptimizerPanelCaption('${l10n.optTimelineTitle} · ${l10n.optTimelineCount(versionCount)}'),
        for (var i = 0; i < nodes.length; i++)
          _timelineRow(nodes[i], l10n, colorScheme, textTheme, isCurrent: i == lastVersionIndex),
      ],
    );
  }

  /// One node: a 6px dot — the accent for the version on screen, amber for a
  /// feedback round, the muted grey for an older version — and its label.
  Widget _timelineRow(
    (OptimizerEntryKind, String, int?) node,
    AppLocalizations l10n,
    ColorScheme colorScheme,
    TextTheme textTheme, {
    required bool isCurrent,
  }) {
    final semantic = context.semantic;
    final isVersion = node.$1 == OptimizerEntryKind.prompt;

    final Color dot = !isVersion
        ? semantic.warning
        : (isCurrent ? colorScheme.primary : colorScheme.outline);
    final Color ink = !isVersion
        ? colorScheme.onSurfaceVariant
        : (isCurrent ? colorScheme.onAccentTint : colorScheme.onSurface);
    final label = isVersion
        ? (isCurrent
            ? 'v${node.$3 ?? '?'} · ${l10n.optTimelineCurrent} · ${node.$2}'
            : 'v${node.$3 ?? '?'} · ${node.$2}')
        : '${l10n.optFeedbackShort} · ${node.$2}';

    final row = Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: OptimizerPanelCard.gap),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(
              color: ink,
              fontWeight: isCurrent ? FontWeight.w500 : null,
            ),
          ),
        ),
      ],
    );
    // The feedback is the user's own words and routinely longer than a row.
    return isVersion ? row : Tooltip(message: node.$2, child: row);
  }
}
