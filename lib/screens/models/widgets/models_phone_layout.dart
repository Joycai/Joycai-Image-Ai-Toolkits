import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/llm_channel.dart';
import '../../../models/llm_model.dart';
import '../../../services/model_list_ordering.dart';
import '../../../state/app_state.dart';
import '../../../state/model_list_state.dart';
import '../../../widgets/drag/app_drag_lift.dart';
import '../../../widgets/drag/app_reorder_gap.dart';
import '../../../widgets/glass/app_glass.dart';
import '../../../widgets/glass/app_glass_menu.dart';
import '../../../widgets/glass/glass_controls.dart';
import '../../../widgets/models/channel_avatar.dart';
import 'channel_row.dart';
import '../../../widgets/models/model_card.dart';
import 'models_actions.dart';
import '../../../widgets/models/models_controls.dart';

/// The phone form (`D1a · 1d`): a G1 top bar — the title, an add action for
/// whichever tab is showing, and the Models / Channels tabs — over two lists
/// that scroll under it.
class ModelsPhoneLayout extends StatelessWidget {
  const ModelsPhoneLayout({super.key, required this.appState, required this.actions});

  final AppState appState;
  final ModelsActions actions;

  static const double _titleHeight = 52;
  static const double _tabsHeight = 46;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return DefaultTabController(
      length: 2,
      child: Builder(
        builder: (context) {
          final controller = DefaultTabController.of(context);
          const double top = _titleHeight + _tabsHeight;
          final double bottom = MediaQuery.paddingOf(context).bottom;

          return Stack(
            children: [
              Positioned.fill(
                child: TabBarView(
                  children: [
                    _PhoneModelsTab(appState: appState, actions: actions, top: top, bottom: bottom),
                    _PhoneChannelsTab(appState: appState, actions: actions, top: top, bottom: bottom),
                  ],
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AppGlass(
                  grade: GlassGrade.bar,
                  edges: GlassEdges.bottom,
                  shadow: false,
                  child: Material(
                    type: MaterialType.transparency,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: _titleHeight,
                          child: Padding(
                            padding: const EdgeInsets.only(left: AppSpace.s16, right: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Builder(
                                    builder: (context) => Text(
                                      l10n.modelManager,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                            color: GlassInk.maybeOf(context)?.ink,
                                          ),
                                    ),
                                  ),
                                ),
                                ListenableBuilder(
                                  listenable: controller,
                                  builder: (context, _) {
                                    final onModels = controller.index == 0;
                                    return Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Only over the model list: the
                                        // channels tab is hand-dragged into
                                        // order, and dragging *is* the sort
                                        // there (`D1d · 2e`).
                                        if (onModels) const _PhoneSortButton(),
                                        GlassIconButton(
                                          icon: Icons.add,
                                          tooltip: onModels ? l10n.addModel : l10n.addChannel,
                                          onPressed:
                                              onModels ? () => actions.addModel(null) : actions.addChannel,
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(
                          height: _tabsHeight,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, AppSpace.s6),
                            child: TabBar(
                              tabs: [
                                Tab(text: l10n.modelsTab),
                                Tab(text: l10n.channelsTab),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
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

/// `D1d · 2e` 排序: the phone has no filter row to put it in, so it rides the
/// title bar beside the add action.
///
/// The same two faces as the right column's button — quiet `sort` on the
/// arrangement the tab has always had, the accent direction arrow once it is
/// off that — except that here 「按渠道分组」 counts as off it too: one list
/// across every channel is as much a change to look at as a sort is.
class _PhoneSortButton extends StatelessWidget {
  const _PhoneSortButton();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final listState = context.watch<ModelListState>();
    final bool lit = !listState.isPhoneDefault;
    final bool ascending = listState.sortDirection == ModelSortDirection.ascending;

    return Builder(
      builder: (anchor) => GlassIconButton(
        icon: lit ? (ascending ? Icons.arrow_upward : Icons.arrow_downward) : Icons.sort,
        active: lit,
        tooltip: l10n.modelSortTooltip(
          modelSortKeyLabel(l10n, listState.sortKey),
          modelSortDirectionLabel(l10n, listState.sortDirection),
        ),
        onPressed: () => showAppGlassMenuBelow(
          anchor,
          entries: modelSortMenuItems(l10n, listState: listState, withGrouping: true),
        ),
      ),
    );
  }
}

/// Every channel's models (`D1d · 2e`).
///
/// Grouped under the channel that serves them, each group header carrying
/// that channel's Fetch Models and Add Model — or, once 「按渠道分组」 is off,
/// one list across every channel with each card naming its own. The sort key
/// applies inside a group in the first shape and across the whole tab in the
/// second, which is the entire reason the switch exists: the key alone could
/// not say which was meant.
class _PhoneModelsTab extends StatelessWidget {
  const _PhoneModelsTab({
    required this.appState,
    required this.actions,
    required this.top,
    required this.bottom,
  });

  final AppState appState;
  final ModelsActions actions;
  final double top;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final listState = context.watch<ModelListState>();
    final channels = appState.allChannels;

    if (channels.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(top: top, bottom: bottom),
        child: ModelsEmptyState(
          icon: Icons.memory,
          title: l10n.noModelsConfigured,
          actions: [
            ModelsActionButton(
              icon: Icons.add,
              label: l10n.addChannel,
              tone: ModelsButtonTone.primary,
              onPressed: actions.addChannel,
            ),
          ],
        ),
      );
    }

    final groups = {for (final g in appState.allPricingGroups) g.id: g};
    final entries = <WidgetBuilder>[];

    Widget card(LLMModel model, LLMChannel channel, {required bool named}) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ModelCard(
            model: model,
            channel: channel,
            feeGroup: groups[model.feeGroupId],
            size: ModelCardSize.phone,
            showChannel: named,
            onTap: () => actions.editModel(model),
          ),
        );

    if (listState.groupByChannel) {
      for (final (i, channel) in channels.indexed) {
        final models = listState.arrange(appState.getModelsForChannel(channel.id));
        entries.add((_) => _PhoneChannelSection(
              channel: channel,
              modelCount: models.length,
              first: i == 0,
              actions: actions,
            ));
        if (models.isEmpty) {
          entries.add((context) => Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  l10n.noModelsConfigured,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ));
        }
        for (final model in models) {
          entries.add((_) => card(model, channel, named: false));
        }
      }
    } else {
      // One run across every channel. Laid out in channel order first, so
      // 「默认顺序」 here is the grouped list with its headers taken away
      // rather than some third arrangement; every other key then reads the
      // whole tab at once, which is the question this shape exists to answer.
      final owners = <int?, LLMChannel>{for (final c in channels) c.id: c};
      final flat = listState.arrange([
        for (final channel in channels) ...appState.getModelsForChannel(channel.id),
      ]);
      if (flat.isEmpty) {
        return Padding(
          padding: EdgeInsets.only(top: top, bottom: bottom),
          child: ModelsEmptyState(
            icon: Icons.memory,
            title: l10n.noModelsConfigured,
            description: l10n.noModelsConfiguredHint,
            actions: [
              ModelsActionButton(
                icon: Icons.add,
                label: l10n.addModel,
                tone: ModelsButtonTone.primary,
                onPressed: () => actions.addModel(null),
              ),
            ],
          ),
        );
      }
      for (final model in flat) {
        final channel = owners[model.channelId];
        if (channel == null) continue;
        entries.add((_) => card(model, channel, named: true));
      }
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(12, top + 8, 12, bottom + AppSpace.s16),
      itemCount: entries.length,
      itemBuilder: (context, index) => entries[index](context),
    );
  }
}

class _PhoneChannelSection extends StatelessWidget {
  const _PhoneChannelSection({
    required this.channel,
    required this.modelCount,
    required this.first,
    required this.actions,
  });

  final LLMChannel channel;
  final int modelCount;
  final bool first;
  final ModelsActions actions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : 12, bottom: AppSpace.s4),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            ChannelAvatar(channel, size: 24),
            const SizedBox(width: AppSpace.s10),
            Expanded(
              child: Text(
                channel.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              l10n.countModels(modelCount),
              style: textTheme.labelSmall?.mono.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (channel.enableDiscovery)
              IconButton(
                icon: const Icon(Icons.cloud_sync_outlined, size: AppSize.iconLg),
                tooltip: l10n.fetchModels,
                color: scheme.onSurfaceVariant,
                onPressed: () => actions.fetchModels(channel),
              ),
            IconButton(
              icon: const Icon(Icons.add, size: AppSize.iconLg),
              tooltip: l10n.addModel,
              color: scheme.onSurfaceVariant,
              onPressed: () => actions.addModel(channel.id),
            ),
          ],
        ),
      ),
    );
  }
}

/// The channels, held and dragged to reorder; a row opens its editor and its
/// ⋮ the same menu a right-click opens on desktop. Fee management ends the
/// list.
class _PhoneChannelsTab extends StatelessWidget {
  const _PhoneChannelsTab({
    required this.appState,
    required this.actions,
    required this.top,
    required this.bottom,
  });

  final AppState appState;
  final ModelsActions actions;
  final double top;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final channels = appState.allChannels;
    final draggable = channels.length > 1;

    // `00d · 1f`: the gap under the finger says where the row lands, with a
    // selection click per change and a light one on the drop.
    return AppReorderGap(
      itemCount: channels.length,
      touch: true,
      slotPadding: const EdgeInsets.only(bottom: AppSpace.s4),
      builder: (context, gap) => ReorderableListView.builder(
        padding: EdgeInsets.fromLTRB(12, top + 8, 12, bottom + AppSpace.s16),
        itemCount: channels.length,
        buildDefaultDragHandles: false,
        onReorderItem: gap.onReorderItem(actions.moveChannel),
        // `1f` 到时：触觉 medium + 抬起.
        onReorderStart: gap.onReorderStart((_) => HapticFeedback.mediumImpact()),
        proxyDecorator: channelDragProxy,
        footer: Padding(
          padding: EdgeInsets.only(top: channels.isEmpty ? 0 : 8),
          child: FeeManagementEntry(
            groupCount: appState.allPricingGroups.length,
            onTap: actions.openFeeManager,
            filled: true,
          ),
        ),
        itemBuilder: (context, index) {
          final channel = channels[index];
          final row = Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.s4),
            child: ChannelRow(
              channel: channel,
              modelCount: appState.getModelsForChannel(channel.id).length,
              filled: true,
              onTap: () => actions.editChannel(channel),
              trailing: Builder(
                builder: (anchor) => IconButton(
                  icon: const Icon(Icons.more_vert, size: AppSize.iconLg),
                  tooltip: l10n.more,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  onPressed: () => showAppGlassMenuBelow(
                    anchor,
                    entries: channelMenuItems(
                      anchor,
                      actions: actions,
                      channel: channel,
                      index: index,
                      count: channels.length,
                      reorderLocked: false,
                    ),
                  ),
                ),
              ),
            ),
          );
          return gap.item(
            key: ValueKey(channel.id),
            index: index,
            // No hover to reveal a grip on a phone, so a row is picked up by
            // holding it (300ms).
            child: draggable ? AppLongPressDragStartListener(index: index, child: row) : row,
          );
        },
      ),
    );
  }
}
