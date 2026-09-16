import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../core/model_kind_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/llm_channel.dart';
import '../../../models/llm_model.dart';
import '../../../models/pricing_group.dart';
import '../../../services/model_list_ordering.dart';
import '../../../state/model_list_state.dart';
import '../../../widgets/ui/app_search_field.dart';
import '../../../widgets/glass/app_glass_menu.dart';
import '../../../widgets/glass/glass_controls.dart';
import '../../../widgets/models/channel_avatar.dart';
import '../../../widgets/ui/scroll_edge_fade.dart';
import '../../../widgets/models/model_card.dart';
import 'models_actions.dart';
import '../../../widgets/models/models_controls.dart';

/// The selected channel's column (`D1a · 1a` 右栏): the channel header, the
/// kind filter row and the model cards.
///
/// Holds its own filter state — the model search and the kind chip — which
/// outlives a channel switch, as it always has.
class ModelDetailColumn extends StatefulWidget {
  const ModelDetailColumn({
    super.key,
    required this.channel,
    required this.models,
    required this.pricingGroups,
    required this.dense,
    required this.actions,
  });

  final LLMChannel channel;

  /// The channel's models, in stored order.
  final List<LLMModel> models;
  final List<PricingGroup> pricingGroups;

  /// Tablet density (`1c`): compact cards.
  final bool dense;

  final ModelsActions actions;

  @override
  State<ModelDetailColumn> createState() => _ModelDetailColumnState();
}

class _ModelDetailColumnState extends State<ModelDetailColumn> {
  final TextEditingController _query = TextEditingController();

  /// The selected kind chip, a [ModelTag] string value; null is "all".
  String? _kind;

  /// Whether the search field is open while the row is collapsed to icons.
  bool _searchOpen = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final listState = context.watch<ModelListState>();
    final models = widget.models;
    final query = _query.text.trim().toLowerCase();
    final matched = [
      for (final m in models)
        if ((_kind == null || m.tag.toLowerCase() == _kind) &&
            (query.isEmpty ||
                m.modelName.toLowerCase().contains(query) ||
                m.modelId.toLowerCase().contains(query)))
          m,
    ];
    // Sorted after filtering, not before: the two chips above the list say
    // what is *in* it, the sort button says what order it is in, and doing it
    // this way round means the sort only ever walks the rows on screen.
    final visible = listState.arrange(matched);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ChannelHeader(channel: widget.channel, actions: widget.actions),
        _buildFilterRow(context, l10n, listState),
        Expanded(child: _buildBody(context, l10n, visible)),
      ],
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n, List<LLMModel> visible) {
    final channel = widget.channel;

    if (widget.models.isEmpty) {
      return ModelsEmptyState(
        icon: Icons.memory,
        title: l10n.noModelsConfigured,
        description: l10n.noModelsConfiguredHint,
        actions: [
          if (channel.enableDiscovery)
            ModelsActionButton(
              icon: Icons.cloud_sync_outlined,
              label: l10n.fetchModels,
              tone: ModelsButtonTone.primary,
              onPressed: () => widget.actions.fetchModels(channel),
            ),
          ModelsActionButton(
            icon: Icons.add,
            label: l10n.addModelManually,
            onPressed: () => widget.actions.addModel(channel.id),
          ),
        ],
      );
    }

    if (visible.isEmpty) {
      final query = _query.text.trim();
      return ModelsEmptyState(
        icon: Icons.search_off,
        title: l10n.pickerNoMatches,
        // Only a typed query can be quoted back; a kind chip alone has no
        // sentence to offer.
        description: query.isEmpty ? null : l10n.noModelsMatchQuery(query),
      );
    }

    final groups = {for (final g in widget.pricingGroups) g.id: g};
    final double inset = widget.dense ? AppSpace.s16 : 20;

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(inset, 12, inset, 12),
      itemCount: visible.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final model = visible[index];
        return ModelCard(
          model: model,
          channel: channel,
          feeGroup: groups[model.feeGroupId],
          size: widget.dense ? ModelCardSize.compact : ModelCardSize.regular,
          onTap: () => widget.actions.editModel(model),
          onEdit: () => widget.actions.editModel(model),
          onDelete: () => widget.actions.deleteModel(model),
        );
      },
    );
  }

  // --- Filter row ----------------------------------------------------------

  /// `1a`: 8 between chips, 12 inside each.
  static const double _chipGap = 8;
  static const double _chipInset = 12;
  static const double _searchMin = 160;
  static const double _searchMax = 280;

  /// The label at rest and picked (`1a`: 400 / 600). A chip is measured at
  /// the picked weight and holds that width in both states, so picking one
  /// does not shove the row — on Windows a CJK bold is synthesised wider
  /// than its regular.
  TextStyle _chipLabelStyle(BuildContext context, {required bool selected}) =>
      Theme.of(context).textTheme.bodySmall!.copyWith(fontWeight: selected ? FontWeight.w600 : FontWeight.w400);

  /// The count is the label's own size in mono — `1a` sets only the family —
  /// so the digits sit on the label's baseline rather than a smaller slot's.
  TextStyle _chipCountStyle(BuildContext context) =>
      _chipLabelStyle(context, selected: false).mono.copyWith(fontWeight: FontWeight.w500);

  /// `1a` 筛选行, degrading by measurement (`1c`, `D1d`): first the chip counts
  /// and the sort key's name go — one branch, not two, so the row never shows
  /// a count beside a nameless sort button — then search and Add Model fold
  /// into two 32 icons (the search icon opens the field over the row), and
  /// only then do the chips scroll. The sort button survives every step: it
  /// is the answer to 「这个列表为什么是这个次序」, and a hidden control cannot
  /// answer anything.
  Widget _buildFilterRow(BuildContext context, AppLocalizations l10n, ModelListState listState) {
    final scheme = Theme.of(context).colorScheme;
    final models = widget.models;
    final double inset = widget.dense ? AppSpace.s16 : 20;

    final kinds = <(String?, String)>[
      (null, l10n.filterAll),
      ('chat', l10n.kindChat),
      ('image', l10n.kindImage),
      ('video', l10n.kindVideo),
      ('multimodal', l10n.kindMultimodal),
    ];
    int countOf(String? kind) =>
        kind == null ? models.length : models.where((m) => m.tag.toLowerCase() == kind).length;

    return Container(
      height: 44,
      padding: EdgeInsets.symmetric(horizontal: inset),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          double chipWidth(String? kind, String label, bool withCount) =>
              _chipInset +
              (kind == null ? 0 : AppSpace.s6 + AppSpace.s6) +
              measureGlassText(context, label, _chipLabelStyle(context, selected: true)) +
              (withCount ? AppSpace.s6 + measureGlassText(context, '${countOf(kind)}', _chipCountStyle(context)) : 0) +
              _chipInset;
          double chipsWidth(bool withCount) =>
              kinds.fold<double>(0, (sum, k) => sum + chipWidth(k.$1, k.$2, withCount)) +
              _chipGap * (kinds.length - 1);

          final addWidth = ModelsActionButton.widthFor(context, l10n.addModel);
          // The sort button is 32 unless it is lit *and* the row is wide
          // enough for its key's name; the two tails below are that row with
          // and without the name.
          final sortName = modelSortKeyLabel(l10n, listState.sortKey);
          final double sortNamed = listState.isDefault
              ? AppSize.control
              : ModelsActionButton.widthFor(context, sortName);
          const double sortIcon = AppSize.control;
          double tail(double sort) => 12 + _searchMin + 8 + sort + AppSpace.s6 + addWidth;
          final bool withCounts = chipsWidth(true) + tail(sortNamed) <= width;
          final bool iconsOnly = !withCounts && chipsWidth(false) + tail(sortIcon) > width;

          final chips = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, (kind, label)) in kinds.indexed) ...[
                if (i > 0) const SizedBox(width: _chipGap),
                _KindChip(
                  label: label,
                  count: withCounts ? countOf(kind) : null,
                  dot: kind == null ? null : modelTagAccent(kind),
                  selected: _kind == kind,
                  inset: _chipInset,
                  labelStyle: _chipLabelStyle,
                  countStyle: _chipCountStyle(context),
                  onTap: () => setState(() => _kind = kind),
                ),
              ],
            ],
          );

          final search = SizedBox(
            height: AppSize.control,
            child: ModelsPanelFields(
              child: AppSearchField(
                controller: _query,
                hint: l10n.filterModels,
                compact: true,
                autofocus: iconsOnly,
                onChanged: (_) => setState(() {}),
              ),
            ),
          );

          final add = ModelsActionButton(
            icon: Icons.add,
            label: l10n.addModel,
            tone: ModelsButtonTone.primary,
            showLabel: !iconsOnly,
            onPressed: () => widget.actions.addModel(widget.channel.id),
          );

          final sort = _SortButton(
            listState: listState,
            label: sortName,
            showLabel: withCounts && !listState.isDefault,
          );

          if (iconsOnly && (_searchOpen || _query.text.isNotEmpty)) {
            return Row(
              children: [
                Expanded(child: search),
                const SizedBox(width: AppSpace.s6),
                ModelsActionButton(
                  icon: Icons.close,
                  label: l10n.close,
                  showLabel: false,
                  onPressed: () => setState(() {
                    _query.clear();
                    _searchOpen = false;
                  }),
                ),
                const SizedBox(width: AppSpace.s6),
                sort,
                const SizedBox(width: AppSpace.s6),
                add,
              ],
            );
          }

          if (iconsOnly) {
            return Row(
              children: [
                Expanded(
                  child: ScrollEdgeFade(
                    axis: Axis.horizontal,
                    child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: chips),
                  ),
                ),
                const SizedBox(width: 12),
                ModelsActionButton(
                  icon: Icons.search,
                  label: l10n.filterModels,
                  showLabel: false,
                  onPressed: () => setState(() => _searchOpen = true),
                ),
                const SizedBox(width: AppSpace.s6),
                sort,
                const SizedBox(width: AppSpace.s6),
                add,
              ],
            );
          }

          return Row(
            children: [
              chips,
              const SizedBox(width: 12),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _searchMax),
                    child: search,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              sort,
              const SizedBox(width: AppSpace.s6),
              add,
            ],
          );
        },
      ),
    );
  }
}

/// `D1d` 排序按钮: 32 at r10 in the filter row, between the search field and
/// Add Model — with the chips and the search, which shape the list, rather
/// than with the primary action.
///
/// Two faces, and which one it wears is the whole point: on the default
/// reading it is the neutral box the header buttons wear, so an unused
/// control takes no attention; off the default it lights up and its glyph
/// becomes the direction, so the order the list is in has an answer at rest
/// instead of only inside the menu.
class _SortButton extends StatelessWidget {
  const _SortButton({required this.listState, required this.label, required this.showLabel});

  final ModelListState listState;

  /// The current key's name, measured by the row even when it is not shown.
  final String label;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bool lit = !listState.isDefault;
    final bool ascending = listState.sortDirection == ModelSortDirection.ascending;

    return ModelsActionButton(
      // `sort` at rest is the glyph the file browser's sort chip (`B1a · 1f`)
      // already taught; lit, the direction replaces it, because by then
      // 「哪个方向」 is the thing the row cannot otherwise say.
      icon: lit ? (ascending ? Icons.arrow_upward : Icons.arrow_downward) : Icons.sort,
      label: label,
      showLabel: showLabel,
      tone: lit ? ModelsButtonTone.active : ModelsButtonTone.neutral,
      // Named on hover in both faces: the icon-only button says 「排过序」 but
      // not by what, and the labelled one still owes the direction.
      tooltip: l10n.modelSortTooltip(label, modelSortDirectionLabel(l10n, listState.sortDirection)),
      // The same menu the phone opens, minus its grouping row — one builder,
      // so the two surfaces cannot drift into two dialects (`D1d · 2e`).
      onPressed: () => showAppGlassMenuBelow(
        context,
        entries: modelSortMenuItems(l10n, listState: listState),
      ),
    );
  }
}

/// `1a` 右栏头: the channel's plate and name over its protocol and endpoint,
/// then Fetch Models, Edit and a ⋮ holding Delete.
class _ChannelHeader extends StatelessWidget {
  const _ChannelHeader({required this.channel, required this.actions});

  final LLMChannel channel;
  final ModelsActions actions;

  static const double _gap = AppSpace.s6;

  /// How much of the name must stay readable before the buttons give up
  /// their labels.
  static const double _nameFloor = 160;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final nameStyle = textTheme.titleLarge!;
    final subStyle = textTheme.labelSmall!.mono.copyWith(color: scheme.onSurfaceVariant);
    final fetch = channel.enableDiscovery;

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final nameNeed = math.min(measureGlassText(context, channel.displayName, nameStyle), _nameFloor);
          final labelled = (fetch ? ModelsActionButton.widthFor(context, l10n.fetchModels) + _gap : 0) +
              ModelsActionButton.widthFor(context, l10n.edit) +
              _gap +
              AppSize.iconButton;
          const chrome = AppSize.control + AppSpace.s10 + 12;
          final showLabels = constraints.maxWidth - chrome - nameNeed >= labelled;

          return Row(
            children: [
              ChannelAvatar(channel, size: AppSize.control),
              const SizedBox(width: AppSpace.s10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(channel.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: nameStyle),
                    // Which wire protocol the endpoint speaks, and where it
                    // is: the two facts that decide what the models below can
                    // do. Mono so two endpoints differing by a path segment
                    // line up.
                    Text(
                      '${channel.type} · ${channel.endpoint}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: subStyle,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (fetch) ...[
                ModelsActionButton(
                  icon: Icons.cloud_sync_outlined,
                  label: l10n.fetchModels,
                  showLabel: showLabels,
                  onPressed: () => actions.fetchModels(channel),
                ),
                const SizedBox(width: _gap),
              ],
              ModelsActionButton(
                icon: Icons.edit_outlined,
                label: l10n.edit,
                showLabel: showLabels,
                tooltip: l10n.edit,
                onPressed: () => actions.editChannel(channel),
              ),
              const SizedBox(width: _gap),
              // A kebab rather than a bare trash can: delete is the one action
              // that should not sit a stray click away from Edit.
              Builder(
                builder: (anchor) => IconButton(
                  icon: const Icon(Icons.more_vert, size: AppSize.iconLg),
                  tooltip: l10n.more,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: AppSize.iconButton,
                    height: AppSize.iconButton,
                  ),
                  color: scheme.onSurfaceVariant,
                  onPressed: () => showAppGlassMenuBelow(
                    anchor,
                    entries: [
                      AppGlassMenuItem(
                        icon: Icons.delete_outline,
                        label: l10n.delete,
                        danger: true,
                        onSelected: () => actions.deleteChannel(channel),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A kind filter (`1a` 类型芯片): 28 tall, a capsule, the kind's 6px identity
/// dot, the label and — while there is room — the mono count. Selected is the
/// accent wash under the deep ink with no edge; at rest a hairline.
///
/// The label and the count share one strut, so the two faces sit on one
/// baseline; the label reserves its picked-weight width in both states, so
/// the chip's width is a property of its text, not of which chip is picked.
class _KindChip extends StatelessWidget {
  const _KindChip({
    required this.label,
    required this.count,
    required this.dot,
    required this.selected,
    required this.inset,
    required this.labelStyle,
    required this.countStyle,
    required this.onTap,
  });

  final String label;
  final int? count;
  final Color? dot;
  final bool selected;
  final double inset;
  final TextStyle Function(BuildContext, {required bool selected}) labelStyle;
  final TextStyle countStyle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color ink = selected ? scheme.onAccentTint : scheme.onSurfaceVariant;
    final shape = StadiumBorder(
      side: selected ? BorderSide.none : BorderSide(color: scheme.outlineVariant),
    );
    final TextStyle picked = labelStyle(context, selected: true);
    final TextStyle rest = labelStyle(context, selected: selected);
    final strut = StrutStyle.fromTextStyle(rest, forceStrutHeight: true);

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? scheme.accentTint : Colors.transparent,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: SizedBox(
            height: AppSize.compact,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: inset),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (dot != null) ...[
                    Container(
                      width: AppSpace.s6,
                      height: AppSpace.s6,
                      decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: AppSpace.s6),
                  ],
                  // The picked weight, unseen, holds the width; the visible
                  // label is centred over it.
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Visibility(
                        visible: false,
                        maintainSize: true,
                        maintainState: true,
                        maintainAnimation: true,
                        child: Text(label, maxLines: 1, softWrap: false, style: picked, strutStyle: strut),
                      ),
                      Text(
                        label,
                        maxLines: 1,
                        softWrap: false,
                        style: rest.copyWith(color: ink),
                        strutStyle: strut,
                      ),
                    ],
                  ),
                  if (count != null) ...[
                    const SizedBox(width: AppSpace.s6),
                    Text(
                      '$count',
                      // `1a`: the label's ink at 80%.
                      style: countStyle.copyWith(color: ink.withValues(alpha: ink.a * 0.8)),
                      strutStyle: strut,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
