import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_semantic_colors.dart';
import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/llm_channel.dart';
import '../../../state/app_state.dart';
import '../../../widgets/app_search_field.dart';
import '../../../widgets/glass/glass_controls.dart';
import 'channel_row.dart';
import 'glass_context_menu.dart';
import 'models_actions.dart';
import 'models_controls.dart';

/// The channels column of the two-column layout (`D1a · 1a` 左栏).
///
/// A 56 header with the counts and Add Channel, the search field, the rows,
/// and the pinned fee-management entry. Reordering has three equal entries —
/// drag (hover grip, whole row), the context menu, and Alt+↑/↓ (bound by the
/// screen around this column) — and all three are off while [reorderLocked],
/// with the reason stated under the search field.
class ChannelColumn extends StatelessWidget {
  const ChannelColumn({
    super.key,
    required this.appState,
    required this.visible,
    required this.selectedId,
    required this.searchController,
    required this.onQueryChanged,
    required this.reorderLocked,
    required this.dense,
    required this.touch,
    required this.actions,
    required this.onSelect,
  });

  final AppState appState;

  /// The channels the search leaves, in stored order.
  final List<LLMChannel> visible;
  final int? selectedId;
  final TextEditingController searchController;
  final ValueChanged<String> onQueryChanged;

  /// Whether a search is narrowing the list.
  final bool reorderLocked;

  /// Tablet density (`1c`).
  final bool dense;

  /// Whether the platform is touch-first: rows lift on long press and there
  /// is no hover to reveal a grip.
  final bool touch;

  final ModelsActions actions;
  final ValueChanged<LLMChannel> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final all = appState.allChannels;
    final bool multiple = all.length > 1;
    final bool canReorder = !reorderLocked && multiple;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          modelCount: appState.allModels.length,
          channelCount: all.length,
          onAdd: actions.addChannel,
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpace.s10),
          child: SizedBox(
            height: AppSize.control,
            child: ModelsPanelFields(
              child: AppSearchField(
                controller: searchController,
                hint: l10n.searchChannels,
                compact: true,
                onChanged: onQueryChanged,
              ),
            ),
          ),
        ),
        if (reorderLocked && multiple)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.s10, 0, AppSpace.s10, AppSpace.s10),
            child: _ReorderLockedNote(message: l10n.channelReorderLockedNote),
          ),
        Expanded(child: _buildList(context, l10n, all, canReorder)),
        FeeManagementEntry(
          groupCount: appState.allPricingGroups.length,
          onTap: actions.openFeeManager,
        ),
      ],
    );
  }

  Widget _buildList(BuildContext context, AppLocalizations l10n, List<LLMChannel> all, bool canReorder) {
    if (all.isEmpty) {
      return ModelsEmptyState(icon: Icons.cloud_queue, title: l10n.noModelsConfigured);
    }
    if (visible.isEmpty) {
      return ModelsEmptyState(icon: Icons.search_off, title: l10n.pickerNoMatches);
    }

    final scheme = Theme.of(context).colorScheme;
    final handle = all.length <= 1
        ? ChannelHandle.none
        : (reorderLocked ? ChannelHandle.locked : ChannelHandle.drag);

    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(AppSpace.s10, 0, AppSpace.s10, AppSpace.s10),
      itemCount: visible.length,
      // The grip is ours (hover-revealed, whole row draggable), not the
      // framework's trailing handles.
      buildDefaultDragHandles: false,
      onReorderItem: (oldIndex, newIndex) {
        // Only reachable unfiltered, where `visible` is the stored order.
        if (canReorder) actions.moveChannel(oldIndex, newIndex);
      },
      onReorderStart: (_) {
        if (touch) HapticFeedback.selectionClick();
      },
      proxyDecorator: channelDragProxy,
      // The three reorder entries, stated once at the list's end (`1a`).
      footer: canReorder && !touch
          ? Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.s6, AppSpace.s6, AppSpace.s6, 0),
              child: Text(
                l10n.channelReorderFootnote,
                style: Theme.of(context).textTheme.labelSmall?.mono.copyWith(color: scheme.outline),
              ),
            )
          : null,
      itemBuilder: (context, index) {
        final channel = visible[index];
        final storedIndex = all.indexWhere((c) => c.id == channel.id);

        final row = Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.s4),
          child: ChannelRow(
            channel: channel,
            modelCount: appState.getModelsForChannel(channel.id).length,
            selected: channel.id == selectedId,
            dense: dense,
            handle: handle,
            onTap: () => onSelect(channel),
            onContextMenu: (position) => showGlassContextMenu(
              context,
              position: position,
              items: channelMenuItems(
                context,
                actions: actions,
                channel: channel,
                index: storedIndex,
                count: all.length,
                reorderLocked: reorderLocked,
              ),
            ),
          ),
        );

        if (!canReorder) return KeyedSubtree(key: ValueKey(channel.id), child: row);
        // Whole-row drag, so the pointer never has to find the grip. Touch
        // has no hover to reveal it and no cursor to change, so there the
        // gesture is an explicit long press.
        return touch
            ? ChannelLongPressDragListener(key: ValueKey(channel.id), index: index, child: row)
            : ReorderableDragStartListener(key: ValueKey(channel.id), index: index, child: row);
      },
    );
  }
}

/// `D1a · 1a` 左栏头: 「Channels」 over the mono counts, and Add Channel —
/// labelled while the text beside it still fits, a 32 plate once it does not.
class _Header extends StatelessWidget {
  const _Header({required this.modelCount, required this.channelCount, required this.onAdd});

  final int modelCount;
  final int channelCount;
  final VoidCallback onAdd;

  static const double _padStart = 14;
  static const double _padEnd = AppSpace.s10;
  static const double _gap = AppSpace.s10;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final titleStyle = textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w600);
    final countStyle = textTheme.labelSmall!.mono.copyWith(color: scheme.onSurfaceVariant);
    final title = l10n.channels;
    final counts = l10n.modelsAndChannelsCount(modelCount, channelCount);

    return Container(
      height: 56,
      padding: const EdgeInsets.only(left: _padStart, right: _padEnd),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textWidth = math.max(
            measureGlassText(context, title, titleStyle),
            measureGlassText(context, counts, countStyle),
          );
          final showLabel = constraints.maxWidth - textWidth - _gap >=
              ModelsActionButton.widthFor(context, l10n.addChannel);

          return Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: titleStyle),
                    Text(counts, maxLines: 1, overflow: TextOverflow.ellipsis, style: countStyle),
                  ],
                ),
              ),
              const SizedBox(width: _gap),
              ModelsActionButton(
                icon: Icons.add,
                label: l10n.addChannel,
                tone: ModelsButtonTone.primary,
                showLabel: showLabel,
                onPressed: onAdd,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// `D1a · 1b` 禁用说明条: why the grip turned into a lock.
class _ReorderLockedNote extends StatelessWidget {
  const _ReorderLockedNote({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: 8),
      decoration: BoxDecoration(
        color: semantic.warningContainer,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: AppSize.iconSm, color: semantic.onWarningContainer),
          const SizedBox(width: AppSpace.s6),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: semantic.onWarningContainer,
                    height: AppType.tightHeight,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
