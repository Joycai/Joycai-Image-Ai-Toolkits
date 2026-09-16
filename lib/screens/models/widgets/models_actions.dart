import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/llm_channel.dart';
import '../../../models/llm_model.dart';
import '../../../services/model_list_ordering.dart';
import '../../../state/model_list_state.dart';
import '../../../widgets/glass/app_glass_menu.dart';

/// Everything the models screen's pieces can ask the screen to do.
///
/// The columns, the phone tabs and the menus are separate widgets; the
/// dialogs they open, the reorder they persist and the confirmations they
/// raise stay in `ModelsScreen`, which is the one place holding the context
/// and state those need.
@immutable
class ModelsActions {
  const ModelsActions({
    required this.addChannel,
    required this.editChannel,
    required this.deleteChannel,
    required this.fetchModels,
    required this.addModel,
    required this.editModel,
    required this.deleteModel,
    required this.moveChannel,
    required this.openFeeManager,
  });

  final VoidCallback addChannel;
  final ValueChanged<LLMChannel> editChannel;
  final ValueChanged<LLMChannel> deleteChannel;
  final ValueChanged<LLMChannel> fetchModels;

  /// Opens the model editor, preselecting the channel with this id if given.
  final ValueChanged<int?> addModel;
  final ValueChanged<LLMModel> editModel;
  final ValueChanged<LLMModel> deleteModel;

  /// Moves the channel at `oldIndex` of the full, stored order so it ends up
  /// at `newIndex`.
  final void Function(int oldIndex, int newIndex) moveChannel;

  final VoidCallback openFeeManager;
}

/// The channel context menu (`D1a · 1b`): move to top / up / down / bottom,
/// then fetch, edit and delete.
///
/// [index] is the channel's position in the full stored order; the move rows
/// disable at the ends and all four while [reorderLocked] — a filtered rail
/// shows only part of the list, so a position in it means nothing.
List<AppGlassMenuEntry> channelMenuItems(
  BuildContext context, {
  required ModelsActions actions,
  required LLMChannel channel,
  required int index,
  required int count,
  required bool reorderLocked,
}) {
  final l10n = AppLocalizations.of(context)!;
  final mac = Theme.of(context).platform == TargetPlatform.macOS;
  final canMove = !reorderLocked && count > 1 && index >= 0;
  final canRise = canMove && index > 0;
  final canSink = canMove && index < count - 1;

  return [
    AppGlassMenuItem(
      icon: Icons.vertical_align_top,
      label: l10n.moveToTop,
      enabled: canRise,
      onSelected: () => actions.moveChannel(index, 0),
    ),
    AppGlassMenuItem(
      icon: Icons.keyboard_arrow_up,
      label: l10n.moveUp,
      trailing: mac ? '⌥↑' : 'Alt+↑',
      enabled: canRise,
      onSelected: () => actions.moveChannel(index, index - 1),
    ),
    AppGlassMenuItem(
      icon: Icons.keyboard_arrow_down,
      label: l10n.moveDown,
      trailing: mac ? '⌥↓' : 'Alt+↓',
      enabled: canSink,
      onSelected: () => actions.moveChannel(index, index + 1),
    ),
    AppGlassMenuItem(
      icon: Icons.vertical_align_bottom,
      label: l10n.moveToBottom,
      enabled: canSink,
      onSelected: () => actions.moveChannel(index, count - 1),
    ),
    const AppGlassMenuDivider(),
    if (channel.enableDiscovery)
      AppGlassMenuItem(
        icon: Icons.cloud_sync_outlined,
        label: l10n.fetchModels,
        onSelected: () => actions.fetchModels(channel),
      ),
    AppGlassMenuItem(
      icon: Icons.edit_outlined,
      label: l10n.editChannel,
      onSelected: () => actions.editChannel(channel),
    ),
    AppGlassMenuItem(
      icon: Icons.delete_outline,
      label: l10n.delete,
      danger: true,
      onSelected: () => actions.deleteChannel(channel),
    ),
  ];
}


/// The key's name as the sort menu and the sort button write it (`D1d`).
String modelSortKeyLabel(AppLocalizations l10n, ModelSortKey key) => switch (key) {
      ModelSortKey.manual => l10n.modelSortDefault,
      ModelSortKey.name => l10n.modelSortName,
      ModelSortKey.kind => l10n.modelSortKind,
      ModelSortKey.added => l10n.modelSortAdded,
    };

String modelSortDirectionLabel(AppLocalizations l10n, ModelSortDirection direction) =>
    direction == ModelSortDirection.ascending ? l10n.sortAscending : l10n.sortDescending;

/// The sort menu (`D1d`): the four keys, then the direction, each group a set
/// of radios under one rule.
///
/// [withGrouping] adds the phone's 「按渠道分组」 checkbox after a second rule
/// (`2e`). Only the phone passes it: the desktop right column is already one
/// channel, so there is nothing there to group by. The two surfaces share one
/// builder so the menu cannot drift into two dialects of the same question.
List<AppGlassMenuEntry> modelSortMenuItems(
  AppLocalizations l10n, {
  required ModelListState listState,
  bool withGrouping = false,
}) =>
    [
      AppGlassMenuHeading(l10n.sortSection),
      for (final key in ModelSortKey.values)
        AppGlassMenuItem(
          label: modelSortKeyLabel(l10n, key),
          // 「默认」 is a word with no content until it says whose default:
          // the order the channel handed over, or the one a hand left.
          hint: key == ModelSortKey.manual ? l10n.modelSortDefaultHint : null,
          radio: true,
          checked: listState.sortKey == key,
          onSelected: () => listState.setSortKey(key),
        ),
      const AppGlassMenuDivider(),
      for (final direction in ModelSortDirection.values)
        AppGlassMenuItem(
          label: modelSortDirectionLabel(l10n, direction),
          radio: true,
          checked: listState.sortDirection == direction,
          trailing: direction == ModelSortDirection.ascending ? '\u2191' : '\u2193',
          onSelected: () => listState.setSortDirection(direction),
        ),
      if (withGrouping) ...[
        const AppGlassMenuDivider(),
        // A checkbox, not a radio: the rows above say how to sort, this one
        // says who the list is for. Its hint states what turning it off does,
        // because the row's own label cannot — 「按渠道分组」 off is a shape
        // the tab has never had.
        AppGlassMenuItem(
          label: l10n.modelGroupByChannel,
          hint: l10n.modelGroupByChannelHint,
          checked: listState.groupByChannel,
          onSelected: () => listState.setGroupByChannel(!listState.groupByChannel),
        ),
      ],
    ];
