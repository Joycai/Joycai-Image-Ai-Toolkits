import 'package:flutter/material.dart';

import '../../../core/app_semantic_colors.dart';
import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/llm_channel.dart';
import '../../../models/llm_model.dart';
import '../../../models/pricing_group.dart';
import '../../../services/llm/context_budget.dart';
import '../../../services/llm/llm_dispatcher.dart';
import '../../../widgets/models/model_tag_chip.dart';
import '../../../widgets/models/wire_protocol_labels.dart';
import 'models_controls.dart';

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
    this.onTap,
    this.onEdit,
    this.onDelete,
  });

  final LLMModel model;

  /// The channel the model belongs to. Only used to tell whether a pinned
  /// protocol is stale; without it the pin is shown as valid.
  final LLMChannel? channel;

  /// The model's fee group, resolved by the caller; null draws
  /// 「No Fee Group」.
  final PricingGroup? feeGroup;

  final ModelCardSize size;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  bool get _phone => size == ModelCardSize.phone;

  /// Whether the model pins a protocol that its channel can no longer serve.
  bool get _staleSelection {
    final pin = model.wireProtocol;
    final channel = this.channel;
    if (pin == null || pin.isEmpty || channel == null) return false;
    return LLMDispatcher.isStaleProtocolSelection(channel.type, model.modelId, pin, tag: model.tag);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final stale = _staleSelection;

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
        if (stale) ...[
          const SizedBox(width: AppSpace.s6),
          Flexible(child: _StaleSelectionBadge(pin: model.wireProtocol!)),
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
        if (!_phone) ...[
          const SizedBox(height: AppSpace.s6),
          Wrap(
            spacing: AppSpace.s6,
            runSpacing: AppSpace.s6,
            children: _chips(context, l10n, stale),
          ),
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

    return [
      _CapabilityChip(contextLabel, mono: true),
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
      if (pin != null && pin.isNotEmpty && !stale)
        Tooltip(
          message: storedProtocolLabel(l10n, pin),
          child: _CapabilityChip(storedProtocolLabel(l10n, pin), maxWidth: 128),
        ),
      if (group != null) _FeeGroupChip(group.name) else _CapabilityChip(l10n.noFeeGroup, faint: true),
    ];
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
  const _StaleSelectionBadge({required this.pin});

  final String pin;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;

    return Tooltip(
      message: l10n.protocolStaleTooltip(storedProtocolLabel(l10n, pin)),
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
