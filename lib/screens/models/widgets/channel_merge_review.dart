import 'package:flutter/material.dart';

import '../../../core/app_semantic_colors.dart';
import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/llm_channel.dart';
import '../../../services/catalogue/channel_merge.dart';
import '../../../services/catalogue/channel_merge_executor.dart';
import '../../../services/llm/channel_routes.dart';
import '../../../services/llm/model_routes.dart';
import '../../../services/llm/vendors/platforms.dart';
import '../../../state/app_state.dart';
import '../../../widgets/models/app_route_badge.dart';
import '../../../widgets/models/route_labels.dart';
import '../../../widgets/ui/app_button.dart';
import '../../../widgets/ui/app_dialog.dart';
import '../../../widgets/ui/app_snackbar.dart';

/// The mergeable channel groups, for the prompt at the top of the rail.
List<MergeCandidate> mergeCandidatesOf(AppState appState) =>
    ChannelMerge.candidates(appState.allChannels, appState.allModels);

/// `D1f · 4a` ②: the one-line prompt above the channel search, shown only
/// while there is something to merge — no badge, no popup.
class ChannelMergeBanner extends StatelessWidget {
  const ChannelMergeBanner({super.key, required this.count, required this.onReview});

  final int count;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpace.s10, AppSpace.s6, AppSpace.s4, AppSpace.s6),
      decoration: BoxDecoration(
        color: scheme.accentTint,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        children: [
          Icon(Icons.call_merge, size: AppSize.iconMd, color: scheme.onAccentTint),
          const SizedBox(width: AppSpace.s10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.channelMergeBannerTitle(count),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onAccentTint,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  l10n.channelMergeBannerReason,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          AppButton(
            label: l10n.channelMergeBannerAction,
            variant: AppButtonVariant.text,
            size: AppButtonSize.compact,
            onPressed: onReview,
          ),
        ],
      ),
    );
  }
}

enum _MergeChoice { merge, skip }

/// `D1f · 4f`: one dialog per group, in turn. Skip moves to the next group;
/// closing ends the review, and the prompt stays in the rail.
///
/// Each group is planned afresh from the current state just before it is
/// shown, so a merge confirmed after another one — or after an edit — writes
/// what the user is looking at.
Future<void> reviewChannelMerges(BuildContext context, AppState appState) async {
  final skipped = <(int?, int?)>{};
  var done = 0;
  while (context.mounted) {
    final pending = [
      for (final c in mergeCandidatesOf(appState))
        if (!skipped.contains((c.keep.id, c.absorb.id))) c,
    ];
    if (pending.isEmpty) return;
    final candidate = pending.first;
    final references = await ChannelMergeExecutor().referenceCount(candidate.plan);
    if (!context.mounted) return;
    final choice = await AppDialog.show<_MergeChoice>(
      context,
      icon: Icons.call_merge,
      title: AppLocalizations.of(context)!.mergeDialogTitle,
      subtitle: _progress(context, candidate, done + 1, done + pending.length),
      maxWidth: 560,
      scrollable: true,
      content: _MergePreview(
        appState: appState,
        candidate: candidate,
        references: references,
      ),
      actionsOverride: Builder(
        builder: (dialog) {
          final l10n = AppLocalizations.of(dialog)!;
          return Row(
            children: [
              AppButton(
                label: l10n.mergeSkip,
                variant: AppButtonVariant.text,
                onPressed: () => Navigator.pop(dialog, _MergeChoice.skip),
              ),
              const Spacer(),
              AppButton(
                label: l10n.cancel,
                variant: AppButtonVariant.text,
                autofocus: true,
                onPressed: () => Navigator.pop(dialog),
              ),
              const SizedBox(width: AppSpace.s6),
              AppButton(
                label: l10n.mergeConfirm,
                onPressed: () => Navigator.pop(dialog, _MergeChoice.merge),
              ),
            ],
          );
        },
      ),
    );
    switch (choice) {
      case _MergeChoice.merge:
        try {
          await appState.mergeChannels(candidate.plan);
        } catch (e) {
          // The transaction rolled back: both channels are as they were.
          // Say so and end the review; the prompt is still in the rail.
          if (context.mounted) {
            AppSnackBar.error(context, AppLocalizations.of(context)!.mergeFailed('$e'));
          }
          return;
        }
        if (context.mounted) {
          AppSnackBar.success(context, AppLocalizations.of(context)!.mergeDone);
        }
      case _MergeChoice.skip:
        skipped.add((candidate.keep.id, candidate.absorb.id));
      case null:
        return;
    }
    done++;
  }
}

String _progress(BuildContext context, MergeCandidate c, int index, int total) {
  final l10n = AppLocalizations.of(context)!;
  final routes = RoutedChannel.routesOf(c.keep);
  final host = Platforms.hostNameOf(routes.primaryAddress);
  return l10n.mergeDialogProgress(index, total, platformLabel(l10n, routes.platform), host);
}

class _MergePreview extends StatelessWidget {
  const _MergePreview({
    required this.appState,
    required this.candidate,
    required this.references,
  });

  final AppState appState;
  final MergeCandidate candidate;
  final int references;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final plan = candidate.plan;
    final merged = RoutedChannel.routesOf(plan.channel);
    final added = plan.addedRoutes.toSet();
    final absorbedRoutes = RoutedChannel.routesOf(candidate.absorb);
    final absorbedModels = appState.getModelsForChannel(candidate.absorb.id);

    Widget caption(String text) => Padding(
      padding: const EdgeInsets.only(top: AppSpace.s16, bottom: AppSpace.s6),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          color: scheme.onAccentTint,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _ChannelSide(
                caption: l10n.mergeKeep,
                channel: candidate.keep,
                kept: true,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6, vertical: 22),
              child: Icon(Icons.arrow_back, size: AppSize.iconMd, color: scheme.outline),
            ),
            Expanded(
              child: _ChannelSide(
                caption: l10n.mergeAbsorb,
                channel: candidate.absorb,
                kept: false,
              ),
            ),
          ],
        ),
        caption(l10n.mergeRoutesAfter),
        Wrap(
          spacing: AppSpace.s6,
          runSpacing: AppSpace.s6,
          children: [
            for (final k in merged.kinds)
              AppRouteBadge(
                label: k == merged.primary.kind
                    ? '${routeLabel(l10n, k)} · ${l10n.routePrimarySuffix}'
                    : added.contains(k)
                    ? '${routeLabel(l10n, k)} · ${l10n.mergeRouteAdded}'
                    : routeLabel(l10n, k),
                state: k == merged.primary.kind
                    ? RouteBadgeState.current
                    : RouteBadgeState.configured,
              ),
          ],
        ),
        if (absorbedModels.isNotEmpty) ...[
          caption(l10n.models),
          for (final m in absorbedModels)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(
                    plan.idMap.containsKey(m.id) ? Icons.join_inner : Icons.move_down,
                    size: AppSize.iconMd,
                    color: plan.idMap.containsKey(m.id) ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpace.s10),
                  Expanded(
                    child: Text(
                      m.modelId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.mono.copyWith(color: scheme.onSurface),
                    ),
                  ),
                  const SizedBox(width: AppSpace.s10),
                  Flexible(
                    child: Text(
                      _what(l10n, m.id, absorbedRoutes),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: AppSpace.s16),
        _Note(
          icon: Icons.info_outline,
          text: l10n.mergeReferencesNote(references, candidate.keep.displayName),
        ),
        const SizedBox(height: AppSpace.s6),
        _Note(icon: Icons.warning_amber_rounded, text: l10n.mergeIrreversible, warning: true),
      ],
    );
  }

  /// What happens to one absorbed model: merged into its namesake, taking
  /// its parameters onto the route it rode; or moved across, pinned there.
  String _what(AppLocalizations l10n, int? id, ChannelRoutes absorbedRoutes) {
    final model = appState.allModels.firstWhere((m) => m.id == id);
    final route = ModelRoutes.usesRoutes(model)
        ? ModelRoutes.requestRoute(model, absorbedRoutes)
        : null;
    if (candidate.plan.idMap.containsKey(id)) {
      return route == null
          ? l10n.mergeModelJoinMedia
          : l10n.mergeModelJoin(routeLabel(l10n, route));
    }
    return route == null ? l10n.mergeModelJoinMedia : l10n.mergeModelMove(routeLabel(l10n, route));
  }
}

class _ChannelSide extends StatelessWidget {
  const _ChannelSide({required this.caption, required this.channel, required this.kept});

  final String caption;
  final LLMChannel channel;
  final bool kept;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpace.s10),
      decoration: BoxDecoration(
        color: kept ? scheme.accentTint : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: kept ? scheme.primary : scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            caption,
            style: theme.textTheme.labelSmall?.copyWith(
              color: kept ? scheme.onAccentTint : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpace.s4),
          Text(
            channel.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(color: scheme.onSurface),
          ),
          const SizedBox(height: AppSpace.s4),
          ChannelRouteBadges(RoutedChannel.routesOf(channel)),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, this.warning = false});

  final IconData icon;
  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final ink = warning ? semantic.onWarningContainer : theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.all(AppSpace.s10),
      decoration: BoxDecoration(
        color: warning ? semantic.warningContainer : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: AppSize.iconMd, color: ink),
          const SizedBox(width: AppSpace.s10),
          Expanded(
            child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: ink)),
          ),
        ],
      ),
    );
  }
}
