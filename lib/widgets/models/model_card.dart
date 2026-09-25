import 'package:flutter/material.dart';

import '../../core/app_semantic_colors.dart';
import '../../core/app_theme.dart';
import '../../core/constants.dart';
import '../../core/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../models/llm_channel.dart';
import '../../models/llm_model.dart';
import '../../models/pricing_group.dart';
import '../../services/llm/context_budget.dart';
import '../../services/llm/llm_dispatcher.dart';
import '../../services/llm/model_routes.dart';
import '../../services/llm/vendors/platforms.dart';
import '../ui/model_tag_chip.dart';
import 'app_route_badge.dart';
import 'fee_group_summary.dart';
import 'models_controls.dart';
import 'route_labels.dart';
import 'wire_protocol_labels.dart';

/// The three densities a [ModelCard] is drawn at.
enum ModelCardSize {
  /// Desktop (`D1a · 1a`): pad 12/14, a 32 kind plate, capability chips.
  regular,

  /// Tablet (`1c`): pad 10/12, a 28 plate, the same content.
  compact,

  /// Phone (`1d`): pad 12, name and id only, a chevron in place of the
  /// actions.
  phone,
}

/// One model, as the models screen lists it (`D1a · 1a`).
///
/// A kind plate in the model kind's identity colour; the display name with
/// the kind badge and, when a pinned protocol no longer applies, the
/// 「Selection inactive」 warning badge; the model id in mono; and a row of
/// capability chips closed by the fee group (or 「No Fee Group」). Edit and
/// delete sit at the right edge when their callbacks are given.
///
/// Public so the model editor can render the card it is editing as a live
/// preview: build an [LLMModel] from the form and pass it with no callbacks.
/// Nothing in here reads providers.
class ModelCard extends StatelessWidget {
  const ModelCard({
    super.key,
    required this.model,
    this.channel,
    this.feeGroup,
    this.size = ModelCardSize.regular,
    this.showBilling = false,
    this.showChannel = false,
    this.onTap,
    this.onEdit,
    this.onDelete,
  });

  final LLMModel model;

  /// `D2b · 21f`: a 「计费 · summary」 line under the chips, stating what
  /// [feeGroup] charges. On for the editor's preview, where the fee group is
  /// a choice being made; off in the list, where the chip's name suffices.
  final bool showBilling;

  /// The channel the model belongs to. Tells whether a pinned protocol is
  /// stale — without it the pin is shown as valid — and, with [showChannel],
  /// names itself on the card.
  final LLMChannel? channel;

  /// `D1d · 2e`: a 「● 渠道名」 line under the model id, in the channel's own
  /// tag colour. For the phone's Models tab once its channel groups are off:
  /// the group header was the only thing saying which channel served a model,
  /// and a flat list across every channel has to put that back on the card.
  final bool showChannel;

  /// The model's fee group, resolved by the caller; null draws
  /// 「No Fee Group」.
  final PricingGroup? feeGroup;

  final ModelCardSize size;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  bool get _phone => size == ModelCardSize.phone;

  /// The name of the selection the model made that its channel can no
  /// longer serve, or null: for a chat model a route the channel does not
  /// offer (`D1f` — chat pins are routes), for an image or video model a
  /// dedicated endpoint its channel's vendor has no menu entry for.
  String? _staleSelection(AppLocalizations l10n) {
    final channel = this.channel;
    if (channel == null) return null;
    if (ModelRoutes.usesRoutes(model)) {
      final chosen = ModelRoutes.explicitRoute(model);
      if (chosen == null || RoutedChannel.routesOf(channel).has(chosen)) return null;
      return routeLabel(l10n, chosen);
    }
    final pin = model.wireProtocol;
    if (pin == null || pin.isEmpty) return null;
    final stale = LLMDispatcher.isStaleProtocolSelection(
        RoutedChannel.primary(channel).channelType, model.modelId, pin, tag: model.tag);
    return stale ? storedProtocolLabel(l10n, pin) : null;
  }

  /// The route the card names at its tail: the model's current one, when
  /// its channel has more than one to choose from (`D1f · 4a` ④). Null for
  /// image and video models, which name their dedicated endpoint instead.
  RouteKind? get _shownRoute {
    final channel = this.channel;
    if (channel == null || !ModelRoutes.usesRoutes(model)) return null;
    final routes = RoutedChannel.routesOf(channel);
    if (routes.entries.length < 2) return null;
    return ModelRoutes.requestRoute(model, routes);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final stale = _staleSelection(l10n);

    final EdgeInsets padding = switch (size) {
      ModelCardSize.regular => const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ModelCardSize.compact => const EdgeInsets.symmetric(horizontal: 12, vertical: AppSpace.s10),
      ModelCardSize.phone => const EdgeInsets.all(12),
    };
    final double plate = size == ModelCardSize.compact ? AppSize.compact : AppSize.control;

    final titleRow = Row(
      children: [
        Flexible(
          child: Text(
            model.modelName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (_phone ? textTheme.titleMedium : textTheme.titleSmall)
                ?.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurface),
          ),
        ),
        const SizedBox(width: 8),
        ModelKindBadge(model.tag),
        if (stale != null) ...[
          const SizedBox(width: AppSpace.s6),
          Flexible(child: _StaleSelectionBadge(label: stale)),
        ],
      ],
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        titleRow,
        SizedBox(height: _phone ? AppSpace.s4 : AppSpace.s6),
        Text(
          model.modelId,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: (_phone ? textTheme.bodySmall : textTheme.labelSmall)
              ?.mono
              .copyWith(color: scheme.onSurfaceVariant),
        ),
        if (showChannel && channel != null) ...[
          SizedBox(height: _phone ? AppSpace.s4 : AppSpace.s6),
          _ChannelLine(channel!),
        ],
        if (!_phone) ...[
          const SizedBox(height: AppSpace.s6),
          Wrap(
            spacing: AppSpace.s6,
            runSpacing: AppSpace.s6,
            children: _chips(context, l10n, stale != null),
          ),
          // Absent, not 「—」, when there is no group to summarise.
          if (showBilling && feeGroup != null) ...[
            const SizedBox(height: AppSpace.s6),
            _billingLine(context, l10n, feeGroup!),
          ],
        ],
      ],
    );

    final Widget? trailing = _phone
        ? Icon(Icons.chevron_right, size: AppSize.iconLg, color: scheme.outline)
        : (onEdit == null && onDelete == null)
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onEdit != null)
                    ModelsRowIconButton(icon: Icons.edit_outlined, tooltip: l10n.edit, onPressed: onEdit),
                  if (onEdit != null && onDelete != null) const SizedBox(width: 2),
                  if (onDelete != null)
                    ModelsRowIconButton(
                      icon: Icons.delete_outline,
                      tooltip: l10n.delete,
                      onPressed: onDelete,
                      danger: true,
                    ),
                ],
              );

    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: padding,
          child: Row(
            crossAxisAlignment: _phone ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              ModelKindPlate(model.tag, size: plate),
              const SizedBox(width: 12),
              Expanded(child: content),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing,
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The capability chips, curated as the card has always curated them, and
  /// the fee group last.
  List<Widget> _chips(BuildContext context, AppLocalizations l10n, bool stale) {
    // Legacy rows carry only the boolean; render its effort equivalent, as the
    // edit dialog does.
    final effort = model.reasoningEffort ?? (model.enableThinking ? 'medium' : null);
    final effortLabel = switch (effort) {
      'low' => l10n.reasoningEffortLow,
      'medium' => l10n.reasoningEffortMedium,
      'high' => l10n.reasoningEffortHigh,
      'max' => l10n.reasoningEffortMax,
      _ => null,
    };

    final contextLabel = switch (ContextBudget.modeOf(model.contextWindow)) {
      ContextWindowMode.unset => l10n.contextUnset,
      ContextWindowMode.unlimited => l10n.contextUnlimited,
      ContextWindowMode.specified => _formatTokens(model.contextWindow!),
    };

    final pin = model.wireProtocol;
    final group = feeGroup;

    final cap = model.maxOutputTokens;

    return [
      _CapabilityChip(contextLabel, mono: true),
      // Only a cap the user set: ④'s built-in 8192 is the app's default, not
      // a declaration about this model.
      if (cap != null && cap > 0) _CapabilityChip(l10n.outputCapChip(_formatTokens(cap)), mono: true),
      // Streaming is the interesting fact; standard-request only worth stating
      // when streaming is off.
      if (model.supportsStream)
        _CapabilityChip(l10n.capabilityStreamingShort)
      else if (model.supportsStandard)
        _CapabilityChip(l10n.capabilityStandardShort),
      if (effortLabel != null) _CapabilityChip(l10n.reasoningChip(effortLabel)),
      if (model.enableWebSearch) _CapabilityChip(l10n.webSearchChip),
      if (model.forceViewAllImages) _CapabilityChip(l10n.viewAllImagesChip),
      // A valid pin names its protocol as one more capability ("Async task");
      // a stale one is the warning badge beside the name instead.
      if (_shownRoute case final route?)
        AppRouteBadge(
          label: routeLabel(l10n, route),
          state: RouteBadgeState.current,
          size: RouteBadgeSize.card,
        )
      // A chat model's pin is its route, named above or not at all.
      else if (pin != null && pin.isNotEmpty && !stale && !ModelRoutes.usesRoutes(model))
        Tooltip(
          message: storedProtocolLabel(l10n, pin),
          child: _CapabilityChip(storedProtocolLabel(l10n, pin), maxWidth: 128),
        ),
      if (group != null) _FeeGroupChip(group.name) else _CapabilityChip(l10n.noFeeGroup, faint: true),
    ];
  }

  /// 「计费」 in the secondary ink, the mono summary, and for a spec group with
  /// no catch-all the outline-coloured 「其他规格按 0 计」.
  Widget _billingLine(BuildContext context, AppLocalizations l10n, PricingGroup group) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final label = textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant);

    return Row(
      children: [
        Text(l10n.modelCardBilling, style: label),
        const SizedBox(width: AppSpace.s6),
        Flexible(
          child: Text(
            feeGroupSummary(l10n, group),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: label?.mono,
          ),
        ),
        if (feeGroupOtherSpecsAtZero(group)) ...[
          const SizedBox(width: AppSpace.s6),
          Flexible(
            child: Text(
              '· ${l10n.specOtherZero}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall?.copyWith(color: scheme.outline),
            ),
          ),
        ],
      ],
    );
  }

  static String _formatTokens(int tokens) {
    if (tokens >= 1048576) return '${tokens ~/ 1048576}M';
    if (tokens >= 1024) return '${tokens ~/ 1024}K';
    return '$tokens';
  }
}

/// 「link_off Selection inactive」 on the warning container, with the reason a
/// hover away.
class _StaleSelectionBadge extends StatelessWidget {
  const _StaleSelectionBadge({required this.label});

  /// The selection that went stale, in the user's words.
  final String label;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;

    return Tooltip(
      message: l10n.protocolStaleTooltip(label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6, vertical: 1),
        decoration: BoxDecoration(
          color: semantic.warningContainer,
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.link_off, size: AppSize.iconSm - 2, color: semantic.onWarningContainer),
            const SizedBox(width: AppSpace.s4),
            Flexible(
              child: Text(
                l10n.protocolPinStale,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: semantic.onWarningContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A capability: one short fact in an r4 hairline box (`D1a` 「能力芯片 r4 hair
/// 边 ink2 11」). [faint] is the weak-ink form 「No Fee Group」 takes.
class _CapabilityChip extends StatelessWidget {
  const _CapabilityChip(this.text, {this.mono = false, this.faint = false, this.maxWidth = 180});

  final String text;
  final bool mono;
  final bool faint;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.labelSmall;

    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: (mono ? base?.mono : base)?.copyWith(
          color: faint ? scheme.outline : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// The fee group a model bills against: the name beside a payments glyph on
/// the card tone.
class _FeeGroupChip extends StatelessWidget {
  const _FeeGroupChip(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(maxWidth: 200),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: scheme.surfaceContainer),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.payments_outlined, size: AppSize.iconSm - 2, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpace.s4),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// `D1d · 2e`: which channel serves this model — a 6px dot in the channel's
/// own tag colour and its name, in the weak ink.
///
/// A dot rather than the [ChannelAvatar] plate: the card already carries the
/// kind plate, and `D1a` is explicit that two identity colours on one card
/// read as no hierarchy at all. The dot is small enough to be a footnote to
/// the name, which is what it is.
class _ChannelLine extends StatelessWidget {
  const _ChannelLine(this.channel);

  final LLMChannel channel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Container(
          width: AppSpace.s6,
          height: AppSpace.s6,
          decoration: BoxDecoration(
            color: Color(channel.tagColor ?? AppConstants.defaultTagColor),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: AppSpace.s6),
        Flexible(
          child: Text(
            channel.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
