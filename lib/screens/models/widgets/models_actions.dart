import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/llm_channel.dart';
import '../../../models/llm_model.dart';
import 'glass_context_menu.dart';

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
List<GlassMenuItem> channelMenuItems(
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
    GlassMenuItem(
      icon: Icons.vertical_align_top,
      label: l10n.moveToTop,
      enabled: canRise,
      onSelected: () => actions.moveChannel(index, 0),
    ),
    GlassMenuItem(
      icon: Icons.keyboard_arrow_up,
      label: l10n.moveUp,
      shortcut: mac ? '⌥↑' : 'Alt+↑',
      enabled: canRise,
      onSelected: () => actions.moveChannel(index, index - 1),
    ),
    GlassMenuItem(
      icon: Icons.keyboard_arrow_down,
      label: l10n.moveDown,
      shortcut: mac ? '⌥↓' : 'Alt+↓',
      enabled: canSink,
      onSelected: () => actions.moveChannel(index, index + 1),
    ),
    GlassMenuItem(
      icon: Icons.vertical_align_bottom,
      label: l10n.moveToBottom,
      enabled: canSink,
      onSelected: () => actions.moveChannel(index, count - 1),
    ),
    const GlassMenuItem.divider(),
    if (channel.enableDiscovery)
      GlassMenuItem(
        icon: Icons.cloud_sync_outlined,
        label: l10n.fetchModels,
        onSelected: () => actions.fetchModels(channel),
      ),
    GlassMenuItem(
      icon: Icons.edit_outlined,
      label: l10n.editChannel,
      onSelected: () => actions.editChannel(channel),
    ),
    GlassMenuItem(
      icon: Icons.delete_outline,
      label: l10n.delete,
      danger: true,
      onSelected: () => actions.deleteChannel(channel),
    ),
  ];
}

/// Where a menu anchored under a button at [anchor] should open: its right
/// edge on the button's right edge, 4px below.
Offset menuPositionBelow(BuildContext anchor) {
  final box = anchor.findRenderObject() as RenderBox?;
  if (box == null) return Offset.zero;
  return box.localToGlobal(Offset(box.size.width - kGlassMenuWidth, box.size.height + 4));
}
