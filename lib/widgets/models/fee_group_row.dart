import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../models/pricing_group.dart';
import 'fee_group_summary.dart';
import '../ui/model_tag_chip.dart';

/// A group name split into the name proper and the labels the user wrote
/// into it in brackets: 「[K]gemini-3.1」 → base `gemini-3.1`, tags `[K]`.
typedef FeeGroupNameParts = ({String base, List<String> tags});

final RegExp _bracketed = RegExp(r'[\(\[（【]([^\(\)\[\]（）【】]+)[\)\]）】]');

/// Splits the bracketed parts out of a group name, in the order they
/// appear. Half- and full-width round and square brackets count; nested or
/// unbalanced ones are left in the name. A name that is nothing but brackets
/// stays as typed, since a row with no name would say less than the
/// punctuation did.
FeeGroupNameParts parseFeeGroupName(String name) {
  final tags = <String>[];
  final base = name
      .replaceAllMapped(_bracketed, (m) {
        final tag = m.group(1)!.trim();
        if (tag.isNotEmpty) tags.add(tag);
        return ' ';
      })
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (base.isEmpty) return (base: name, tags: const <String>[]);
  return (base: base, tags: tags);
}

/// Whether a fee-group row shows the reorder grip, and when.
enum FeeGroupHandle {
  /// No grip: a single group, a filtered list, or a touch screen at rest.
  none,

  /// `D2 · 1g` 甲案: the grip fades in when the pointer is over the row.
  hover,

  /// Reorder mode: the grip is always on show.
  always,
}

/// One fee group at rest (`D2 · 1d` 组卡): the name over how many models it
/// prices, its rates as mono tags, edit and delete. Selected (`1e`) it takes
/// the accent wash, a 1px accent edge and the deep accent name.
///
/// On a phone (`1h`) the same card is two lines — name and use over a
/// wrapping tag row — with a chevron, since the editor is a page.
class FeeGroupRow extends StatefulWidget {
  const FeeGroupRow({
    super.key,
    required this.group,
    required this.models,
    required this.onTap,
    this.selected = false,
    this.handle = FeeGroupHandle.none,
    this.onEdit,
    this.onDelete,
    this.onContextMenu,
    this.phone = false,
  });

  final PricingGroup group;

  /// Display names of the models pointing at this group.
  final List<String> models;

  final bool selected;
  final FeeGroupHandle handle;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final ValueChanged<Offset>? onContextMenu;
  final bool phone;

  @override
  State<FeeGroupRow> createState() => _FeeGroupRowState();
}

class _FeeGroupRowState extends State<FeeGroupRow> {
  /// A name badge wider than this ends in an ellipsis rather than eating
  /// the name it sits beside.
  static const double _badgeMaxWidth = 120;

  bool _hovering = false;
  bool _handleHovering = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final group = widget.group;
    final selected = widget.selected;
    final unused = widget.models.isEmpty;

    final Color nameColor = selected
        ? scheme.onAccentTint
        : unused
            ? scheme.outline
            : scheme.onSurface;

    final parts = parseFeeGroupName(group.name);
    final Widget identity = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                parts.base,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: (widget.phone ? textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600) : textTheme.titleSmall)
                    ?.copyWith(color: nameColor),
              ),
            ),
            // A bracketed part of the name — 「[官方]」, 「(特价)」 — is the
            // user's own label for the group, so it reads as a badge beside
            // the name rather than as punctuation inside it. The badge keeps
            // its own width (capped) and the name takes what is left: as a
            // second Flexible it would claim half the column and the name
            // would end in an ellipsis with room to spare beside it.
            for (final tag in parts.tags) ...[
              const SizedBox(width: AppSpace.s6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _badgeMaxWidth),
                child: ModelTagChip(
                  tag,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  uppercase: false,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        _buildConsumers(context, l10n),
      ],
    );

    final tags = feeGroupPriceTags(context, l10n, group);

    final Widget content = widget.phone
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: identity),
                  const SizedBox(width: 8),
                  Icon(
                    widget.handle == FeeGroupHandle.always ? Icons.drag_indicator : Icons.chevron_right,
                    size: AppSize.iconMd,
                    color: widget.handle == FeeGroupHandle.always ? scheme.onSurfaceVariant : scheme.outline,
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.s6),
              Wrap(spacing: AppSpace.s6, runSpacing: AppSpace.s4, crossAxisAlignment: WrapCrossAlignment.center, children: tags),
            ],
          )
        : Row(
            children: [
              if (widget.handle != FeeGroupHandle.none) ...[
                _buildHandle(context, l10n),
                const SizedBox(width: AppSpace.s4),
              ],
              // The name yields before the tags do: a rate the user cannot
              // read is a worse loss than a name that ends in an ellipsis.
              Expanded(flex: 2, child: identity),
              const SizedBox(width: 8),
              // Expanded, not Flexible: a Flexible that stops at the tags'
              // own width hands its slack back to the row's end, and the
              // buttons after it end up floating mid-row instead of at the
              // right edge. The tags right-align inside their share instead.
              Expanded(
                flex: 3,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: AppSpace.s6,
                  runSpacing: AppSpace.s4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: tags,
                ),
              ),
              const SizedBox(width: AppSpace.s6),
              FeeRowIconButton(icon: Icons.edit_outlined, tooltip: l10n.edit, onPressed: widget.onEdit ?? widget.onTap),
              const SizedBox(width: 2),
              FeeRowIconButton(icon: Icons.delete_outline, tooltip: l10n.delete, onPressed: widget.onDelete, danger: true),
            ],
          );

    final grab = widget.handle != FeeGroupHandle.none && !widget.phone;

    return Material(
      color: selected
          ? scheme.accentTint
          : widget.phone
              ? scheme.surface
              : _hovering
                  ? scheme.surfaceContainer
                  : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        side: BorderSide(color: selected ? scheme.primary : scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        onSecondaryTapUp: widget.onContextMenu == null ? null : (details) => widget.onContextMenu!(details.globalPosition),
        onHover: (hovering) {
          if (hovering != _hovering) setState(() => _hovering = hovering);
        },
        hoverColor: Colors.transparent,
        mouseCursor: grab ? SystemMouseCursors.grab : SystemMouseCursors.click,
        child: Padding(
          padding: widget.phone
              ? const EdgeInsets.all(12)
              : EdgeInsetsDirectional.fromSTEB(
                  widget.handle == FeeGroupHandle.none ? 12 : 8,
                  AppSpace.s10,
                  AppSpace.s6,
                  AppSpace.s10,
                ),
          child: content,
        ),
      ),
    );
  }

  /// `1g`: the 20-wide grip slot, drawn only while hovered (or always, in
  /// reorder mode); the row's other content never moves for it.
  Widget _buildHandle(BuildContext context, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final show = widget.handle == FeeGroupHandle.always || _hovering;

    return SizedBox(
      width: 20,
      child: AnimatedOpacity(
        opacity: show ? 1 : 0,
        duration: AppMotion.durationOf(context, AppMotion.hover),
        curve: AppMotion.quick,
        child: IgnorePointer(
          ignoring: !show,
          child: MouseRegion(
            onEnter: (_) => setState(() => _handleHovering = true),
            onExit: (_) => setState(() => _handleHovering = false),
            child: Tooltip(
              message: l10n.channelReorderHandleTooltip,
              child: Icon(
                Icons.drag_indicator,
                size: AppSize.iconLg,
                color: _handleHovering ? scheme.onSurfaceVariant : scheme.outline,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The models this group bills — or, worth saying out loud, that it bills
  /// none: an orphaned group prices nothing, and nothing else would tell you.
  Widget _buildConsumers(BuildContext context, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final mono = Theme.of(context).textTheme.labelSmall?.mono;
    final models = widget.models;

    if (models.isEmpty) {
      return Text(
        l10n.feeGroupUnused,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: mono?.copyWith(color: scheme.outline),
      );
    }

    return Tooltip(
      message: models.join('\n'),
      child: Text(
        l10n.feeGroupModelCount(models.length),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: mono?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}

/// A group's rates as the row tags them: three for per-token billing, one
/// for per-request, and one summary for per-spec (`D2b · 21e`) with the
/// full table as its tooltip and 「其他规格按 0 计」 after it when the table
/// has no catch-all.
List<Widget> feeGroupPriceTags(BuildContext context, AppLocalizations l10n, PricingGroup group) {
  final scheme = Theme.of(context).colorScheme;
  final textTheme = Theme.of(context).textTheme;

  String rate(double price, String unit) => '\$${price.toStringAsFixed(4)}/$unit';

  switch (group.billingMode) {
    case 'token':
      return [
        FeePriceTag(label: l10n.priceLabelInput, value: rate(group.inputPrice, 'M')),
        // Always shown, even when unset: an inherited rate is still the rate
        // the user gets billed, so hiding it would just raise the question.
        FeePriceTag(
          label: l10n.priceLabelCache,
          value: rate(group.effectiveCacheInputPrice, 'M'),
          inherited: group.cacheInputPrice == null,
          tooltip: group.cacheInputPrice == null ? l10n.cachePriceFollowsInput : null,
        ),
        FeePriceTag(label: l10n.priceLabelOutput, value: rate(group.outputPrice, 'M')),
      ];
    case 'spec':
      return [
        FeePriceTag(value: feeGroupSummary(l10n, group), tooltip: feeGroupRateTable(l10n, group)),
        if (feeGroupOtherSpecsAtZero(group))
          Text(l10n.specOtherZero, style: textTheme.labelSmall?.mono.copyWith(color: scheme.outline)),
      ];
    default:
      return [FeePriceTag(label: l10n.priceLabelRequest, value: rate(group.requestPrice, 'Req'))];
  }
}

/// A rate as `D1a` tags it: the rate's name beside the mono figure, r4 on the
/// card tone. [inherited] renders the figure muted — it is not configured on
/// this group, it follows the input price.
class FeePriceTag extends StatelessWidget {
  const FeePriceTag({super.key, this.label, required this.value, this.inherited = false, this.tooltip});

  /// The rate's name; null for a tag that is all figure (the spec summary).
  final String? label;
  final String value;
  final bool inherited;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final Widget tag = Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label case final label?) ...[
            Text(label, style: textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(width: AppSpace.s4),
          ],
          // Flexible: the spec summary is the one long tag, and on a phone
          // it ends in an ellipsis rather than past the card's edge.
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall?.mono.copyWith(
                color: inherited ? scheme.outline : scheme.onSurface,
                fontStyle: inherited ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
        ],
      ),
    );

    return tooltip == null ? tag : Tooltip(message: tooltip!, child: tag);
  }
}

/// The 28 glyph at a row's end: edit in the secondary ink, delete in the
/// error's.
class FeeRowIconButton extends StatelessWidget {
  const FeeRowIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return IconButton(
      icon: Icon(icon, size: AppSize.iconMd),
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: AppSize.compact, height: AppSize.compact),
      style: IconButton.styleFrom(
        minimumSize: const Size.square(AppSize.compact),
        // The row places the glyph itself at its edge; the 48 tap target
        // Material would pad around it pushes the button 10px in from the
        // row's end and opens the same 10px between edit and delete.
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: danger ? scheme.error : scheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      ),
    );
  }
}
