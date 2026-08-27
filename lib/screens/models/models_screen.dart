import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../core/constants.dart';
import '../../core/design_tokens.dart';
import '../../core/fee_group_palette.dart';
import '../../core/model_kind_palette.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../models/llm_channel.dart';
import '../../models/llm_model.dart';
import '../../services/database_service.dart';
import '../../services/llm/context_budget.dart';
import '../../services/llm/llm_dispatcher.dart';
import '../../services/llm/llm_types.dart';
import '../../state/app_state.dart';
import '../../widgets/models/channel_avatar.dart';
import '../../widgets/models/model_tag_chip.dart';
import '../../widgets/app_button.dart';
import '../../widgets/dashed_border.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/models/channel_edit_dialog.dart';
import '../../widgets/models/channel_wizard_dialog.dart';
import '../../widgets/models/discovery_dialog.dart';
import '../../widgets/models/model_edit_dialog.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/models/wire_protocol_labels.dart';
import '../../widgets/panel_resizer.dart';
import '../../widgets/pricing_group_manager.dart';
import '../../widgets/scroll_edge_fade.dart';

/// [ReorderableDelayedDragStartListener] at the spec's 300 ms instead of the
/// framework's 500 ms long-press timeout: half a second of holding still
/// before a row lifts reads as the app not having noticed the touch.
class _ChannelLongPressDragListener extends ReorderableDelayedDragStartListener {
  const _ChannelLongPressDragListener({
    super.key,
    required super.index,
    required super.child,
  });

  @override
  MultiDragGestureRecognizer createRecognizer() =>
      DelayedMultiDragGestureRecognizer(
        delay: const Duration(milliseconds: 300),
        debugOwner: this,
      );
}

/// The 12px drag grip that fades in over a channel row's left padding.
///
/// A widget of its own for one reason: the hover flag stays in the row. On
/// [_ModelsScreenState] it rebuilt both panels on every pointer crossing —
/// including the right-hand column, whose model cards are built eagerly and
/// measured two at a time by an [IntrinsicHeight]. Hover belongs to the row,
/// the way it already does in `image_card.dart` and `file_card.dart`.
class _ChannelHoverHandle extends StatefulWidget {
  const _ChannelHoverHandle({
    required this.enabled,
    required this.tooltip,
    required this.child,
  });

  /// Whether the row can be dragged. When false there is no [MouseRegion] and
  /// the handle stays hidden — a rail filtered by a query has no order to
  /// rearrange, so nothing should suggest it has.
  final bool enabled;

  final String tooltip;

  /// The row's own content.
  final Widget child;

  @override
  State<_ChannelHoverHandle> createState() => _ChannelHoverHandleState();
}

class _ChannelHoverHandleState extends State<_ChannelHoverHandle> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final content = Stack(
      children: [
        // The handle is painted *over* the row's existing left padding
        // rather than taking a column of its own: revealing it must not
        // move the avatar, the name or the subline by a pixel, which is
        // the whole argument for 方案乙 over the always-on grip.
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 12,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: widget.enabled && _hovering ? 1 : 0,
              duration: AppMotion.durationOf(context, AppMotion.hover),
              curve: AppMotion.enter,
              child: Center(
                child: Tooltip(
                  message: widget.tooltip,
                  child: Icon(
                    Icons.drag_indicator,
                    size: 12,
                    color: colorScheme.outline,
                  ),
                ),
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );

    if (!widget.enabled) return content;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: content,
    );
  }
}

class ModelsScreen extends StatefulWidget {
  const ModelsScreen({super.key});

  @override
  State<ModelsScreen> createState() => _ModelsScreenState();
}

class _ModelsScreenState extends State<ModelsScreen> {
  static const double _minSidebarWidth = 220;
  static const double _maxSidebarWidth = 420;

  int? _selectedChannelId;
  double _sidebarWidth = 300;

  /// Live filters, per `14a`: the channel list and the model grid each carry
  /// their own search, and the grid a kind filter besides. Plain lowercase
  /// substring match — the lists are at most a few hundred rows.
  String _channelQuery = '';

  String _modelQuery = '';

  /// The selected kind chip, a [ModelTag] string value; null is "all".
  String? _kindFilter;

  /// Drag accumulator, allowed [_kDragSlack] past the limits so the handle
  /// re-engages where the pointer actually is after a drag past the end,
  /// instead of the instant the pointer reverses. Null when no drag is live.
  static const double _kDragSlack = 24;
  double? _dragSidebarWidth;

  @override
  void initState() {
    super.initState();
    _loadSidebarWidth();
  }

  Future<void> _loadSidebarWidth() async {
    final saved = await DatabaseService().getSetting('models_sidebar_width');
    final width = double.tryParse(saved ?? '');
    if (width != null && mounted) {
      setState(() => _sidebarWidth = width.clamp(_minSidebarWidth, _maxSidebarWidth));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return ResponsiveBuilder(
      mobile: _buildMobileLayout(l10n),
      desktop: _buildPanelLayout(l10n),
    );
  }

  // --- Mobile Layout (iPhone) ---
  Widget _buildMobileLayout(AppLocalizations l10n) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverAppBar(
              title: Text(l10n.modelManager),
              pinned: true,
              floating: true,
              snap: true,
              forceElevated: innerBoxIsScrolled,
              bottom: TabBar(
                tabs: [
                  Tab(text: l10n.modelsTab),
                  Tab(text: l10n.channelsTab),
                ],
              ),
            ),
          ],
          body: Consumer<AppState>(
            builder: (context, appState, child) => TabBarView(
              children: [
                _buildModelsMobileTab(l10n, appState),
                _buildChannelsMobileTab(l10n, appState),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Inset Panel Layout (tablet + desktop) ---
  //
  // Master-detail in two flush columns: channels on the left (with the screen
  // header and add-channel action), the selected channel and its models on the
  // right, a draggable hairline between.
  //
  // `D2` never draws this page — it is all add-channel dialog, with the page
  // behind it only as a scrim — so this follows the app-wide pattern rather
  // than a frame. Every screen with a sidebar the spec *does* draw is a column
  // screen, and 设置 is the one named exception; leaving this the only other
  // card layout would be an inconsistency with nothing behind it.
  Widget _buildPanelLayout(AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    return Consumer<AppState>(
      builder: (context, appState, child) {
        final channels = appState.allChannels;
        _ensureSelection(channels);
        final selectedChannel = channels.cast<LLMChannel?>().firstWhere(
          (c) => c?.id == _selectedChannelId,
          orElse: () => null,
        );

        return Scaffold(
          backgroundColor: colorScheme.surfaceContainer,
          // `14a` draws both search fields filled, a step off their column.
          body: FilledFieldScope(
            child: Row(
              children: [
                PanelCard(
                  width: _sidebarWidth,
                  shape: PanelShape.column,
                  child: _buildChannelsPanel(l10n, appState, channels),
                ),
                PanelResizer(
                  shape: PanelShape.column,
                  onDrag: (dx) => setState(() {
                    _dragSidebarWidth = ((_dragSidebarWidth ?? _sidebarWidth) + dx)
                        .clamp(_minSidebarWidth - _kDragSlack, _maxSidebarWidth + _kDragSlack);
                    _sidebarWidth = _dragSidebarWidth!.clamp(_minSidebarWidth, _maxSidebarWidth);
                  }),
                  onDragEnd: () {
                    _dragSidebarWidth = null;
                    DatabaseService()
                        .saveSetting('models_sidebar_width', _sidebarWidth.round().toString());
                  },
                ),
                Expanded(
                  child: PanelCard(
                    shape: PanelShape.column,
                    child: selectedChannel == null
                        ? Center(
                            child: Text(
                              l10n.noModelsConfigured,
                              style: TextStyle(color: colorScheme.outline),
                            ),
                          )
                        : _buildDetailPanel(l10n, appState, selectedChannel),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _ensureSelection(List<LLMChannel> channels) {
    if (channels.isEmpty) {
      _selectedChannelId = null;
      return;
    }
    if (_selectedChannelId == null || !channels.any((c) => c.id == _selectedChannelId)) {
      _selectedChannelId = channels.first.id;
    }
  }

  // --- Channels Panel (left card) ---

  Widget _buildChannelsPanel(AppLocalizations l10n, AppState appState, List<LLMChannel> channels) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final modelCount = appState.allModels.length;

    // Screen header lives inside the top of the card; its bottom border
    // becomes an internal divider on the inset-panel canvas. `14a` titles it
    // with what the column actually lists — channels — and spends the trailing
    // slot on a labelled add button rather than a bare plus.
    final header = Container(
      height: 56,
      padding: const EdgeInsets.only(left: 16, right: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withAlpha(90))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.channels,
                  style: textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  l10n.modelsAndChannelsCount(modelCount, channels.length),
                  style: textTheme.labelMedium?.mono.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Default height, not compact. The spec labels this 30px, but the
          // row it has to agree with is the app's: 获取模型, the edit icon and
          // every dialog footer sit at the 36px control height, and one short
          // button among them reads as a mistake rather than a size.
          AppButton(
            label: l10n.addChannel,
            icon: Icons.add,
            onPressed: () => _showChannelDialog(l10n, appState),
          ),
        ],
      ),
    );

    final query = _channelQuery.trim().toLowerCase();
    final visible = query.isEmpty
        ? channels
        : [
            for (final c in channels)
              if (c.displayName.toLowerCase().contains(query) ||
                  (c.tag ?? '').toLowerCase().contains(query))
                c,
          ];

    return Column(
      children: [
        header,
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: TextField(
            onChanged: (v) => setState(() => _channelQuery = v),
            decoration: InputDecoration(
              hintText: l10n.searchChannels,
              prefixIcon: const Icon(Icons.search, size: AppSize.iconSm),
              prefixIconConstraints: const BoxConstraints(minWidth: 36),
            ),
            style: textTheme.bodyMedium,
          ),
        ),
        Expanded(
          child: channels.isEmpty
              ? Center(
                  child: Text(
                    l10n.noModelsConfigured,
                    style: TextStyle(color: colorScheme.outline),
                  ),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: visible.length,
                  // Handles are ours (hover-revealed, whole row draggable),
                  // not the framework's trailing grips.
                  buildDefaultDragHandles: false,
                  onReorderItem: (oldIndex, newIndex) =>
                      _reorderChannels(l10n, appState, oldIndex, newIndex),
                  onReorderStart: (_) {
                    if (_touchReorder) HapticFeedback.selectionClick();
                  },
                  proxyDecorator: _channelDragProxy,
                  itemBuilder: (context, index) => _buildChannelRow(
                    l10n,
                    appState,
                    visible[index],
                    index: index,
                    // Dragging inside a filtered list has no meaning — the
                    // position the user sees is not the position in the
                    // stored order — and a single channel has nothing to be
                    // reordered against.
                    draggable: query.isEmpty && visible.length > 1,
                  ),
                ),
        ),
        // The fee-group entry `14a` pins under the list: pricing lives a
        // screen away (usage → 费率组), and a model card naming its group is
        // only actionable if the group is reachable from here.
        Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colorScheme.outlineVariant.withAlpha(90))),
          ),
          child: InkWell(
            onTap: () => _showFeeGroupManager(l10n),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.money_outlined, size: AppSize.iconSm, color: colorScheme.outline),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.feeManagement,
                      style: textTheme.labelLarge?.copyWith(color: colorScheme.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    l10n.countGroups(appState.allPricingGroups.length),
                    style: textTheme.labelMedium?.mono.copyWith(color: colorScheme.outline),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// One channel row: identity disc, name beside the channel's own tag chip,
  /// and a mono second line pairing the model count with the vendor id — the
  /// two facts `14a` surfaces so a row answers "which endpoint, how big"
  /// without being opened.
  Widget _buildChannelRow(
    AppLocalizations l10n,
    AppState appState,
    LLMChannel channel, {
    required int index,
    required bool draggable,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isSelected = channel.id == _selectedChannelId;
    final models = appState.getModelsForChannel(channel.id);

    final row = Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: isSelected ? colorScheme.primary.withValues(alpha: AppAlpha.tint) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: isSelected
              ? BorderSide(color: colorScheme.primary.withValues(alpha: AppAlpha.ring))
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => setState(() => _selectedChannelId = channel.id),
          // The cursor says the row can be picked up; the handle, revealed on
          // hover inside [_ChannelHoverHandle], says where.
          mouseCursor: draggable ? SystemMouseCursors.grab : null,
          child: _ChannelHoverHandle(
            enabled: draggable,
            tooltip: l10n.channelReorderHandleTooltip,
            child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                ChannelAvatar(channel, size: 30),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              channel.displayName,
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                color: isSelected ? colorScheme.primary : null,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (channel.tag != null && channel.tag!.isNotEmpty) ...[
                            const SizedBox(width: 7),
                            ModelTagChip(
                              channel.tag!,
                              color: Color(channel.tagColor ?? AppConstants.defaultTagColor),
                              uppercase: false,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      // The capability subline (18c): model count + the faces
                      // the channel's models actually use, in fixed order.
                      // Plain type, not mono — it is prose now, no longer a
                      // vendor-id string (that stays on the detail header and
                      // in the channel editor for troubleshooting).
                      Text(
                        _channelSubline(l10n, models),
                        style: textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ),
        ),
      ),
    );

    if (!draggable) return KeyedSubtree(key: ValueKey(channel.id), child: row);
    // Whole-row drag, so the pointer never has to find a 12px target. On a
    // touch device there is no hover to reveal the handle and no cursor to
    // change, so the gesture becomes an explicit long press instead.
    return _touchReorder
        ? _ChannelLongPressDragListener(
            key: ValueKey(channel.id), index: index, child: row)
        : ReorderableDragStartListener(
            key: ValueKey(channel.id), index: index, child: row);
  }

  /// Whether reordering is driven by long press rather than by press-and-move.
  ///
  /// Keyed off the platform rather than the last input event: a tablet running
  /// the two-pane layout is still a touch device, and an immediate drag there
  /// would fight every scroll of the rail.
  bool get _touchReorder {
    switch (Theme.of(context).platform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return true;
      default:
        return false;
    }
  }

  /// The lifted row: the app's own elevation and a primary ring, ramped in
  /// over the pick-up so the card rises rather than appearing.
  Widget _channelDragProxy(Widget child, int index, Animation<double> animation) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(animation.value);
        return Transform.scale(
          scale: 1 + 0.02 * t,
          child: Material(
            // Opaque, unlike the resting row: an unselected row paints no
            // background of its own, and a transparent card in flight would
            // show the rows sliding underneath it.
            color: colorScheme.surface,
            elevation: 6 * t,
            shadowColor: colorScheme.shadow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              side: BorderSide(
                color: colorScheme.primary.withValues(alpha: 0.35 + 0.65 * t),
              ),
            ),
            child: child,
          ),
        );
      },
    );
  }

  /// Persist a drag, and say so only when it fails — a successful reorder is
  /// already reported by the row being where the user dropped it.
  Future<void> _reorderChannels(
    AppLocalizations l10n,
    AppState appState,
    int oldIndex,
    int newIndex,
  ) async {
    final ok = await appState.reorderChannels(oldIndex, newIndex);
    if (!ok && mounted) {
      AppSnackBar.error(context, l10n.channelOrderSaveFailed);
    }
  }

  void _showFeeGroupManager(AppLocalizations l10n) {
    AppDialog.show<void>(
      context,
      title: l10n.feeManagement,
      icon: Icons.money_outlined,
      maxWidth: 760,
      maxHeight: 720,
      scrollable: true,
      onClose: () => Navigator.pop(context),
      content: const PricingGroupManager(),
    );
  }

  // --- Detail Panel (right card) ---

  Widget _buildDetailPanel(AppLocalizations l10n, AppState appState, LLMChannel channel) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final showActionLabels = Responsive.isDesktop(context);

    final header = Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withAlpha(90))),
      ),
      child: Row(
        children: [
          ChannelAvatar(channel, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        channel.displayName,
                        style: textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // The vendor id, restated as a badge the way `14a` (and
                    // the model editor's heading) draw it — which wire
                    // protocol this endpoint speaks is the fact that decides
                    // what the models under it can do.
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                      child: Text(
                        channel.type,
                        style: textTheme.labelSmall?.mono.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  channel.endpoint,
                  // `12o` sets the endpoint in mono, and it is the clearest
                  // case on this screen: two channels differing by one path
                  // segment only look different when the segments line up.
                  style: textTheme.labelMedium?.mono.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (channel.enableDiscovery) ...[
            if (showActionLabels)
              AppButton(
                label: l10n.fetchModels,
                icon: Icons.auto_awesome_outlined,
                variant: AppButtonVariant.secondary,
                onPressed: () => _showDiscoveryDialog(l10n, channel, appState),
              )
            else
              IconButton.filledTonal(
                icon: const Icon(Icons.auto_awesome_outlined, size: 20),
                onPressed: () => _showDiscoveryDialog(l10n, channel, appState),
                tooltip: l10n.fetchModels,
              ),
            const SizedBox(width: 4),
          ],
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () => _showChannelDialog(l10n, appState, channel: channel),
            tooltip: l10n.edit,
          ),
          // A kebab, not a bare trash can: `14a` keeps the header to one
          // restrained row, and delete is the one action that should not sit
          // a stray click away from "edit".
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            tooltip: l10n.more,
            onSelected: (v) {
              if (v == 'delete') _confirmDeleteChannel(l10n, channel, appState);
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: AppSize.iconMd, color: colorScheme.error),
                    const SizedBox(width: 10),
                    Text(l10n.delete, style: TextStyle(color: colorScheme.error)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return Column(
      children: [
        header,
        _buildModelsToolbar(l10n, appState, channel),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: _buildModelsGrid(channel, l10n, appState),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The `14a` toolbar: a filter field, one pill per model kind with its
  /// count, and the add action — replacing the old "模型" heading, which said
  /// nothing the grid under it didn't.
  ///
  /// The pills sit in a horizontal scroller rather than behind a measured
  /// width threshold; if the row is squeezed the chips scroll, they don't
  /// vanish.
  Widget _buildModelsToolbar(AppLocalizations l10n, AppState appState, LLMChannel channel) {
    final textTheme = Theme.of(context).textTheme;
    final models = appState.getModelsForChannel(channel.id!);

    final kinds = <(String?, String, Color?)>[
      (null, l10n.filterAll, null),
      ('chat', l10n.kindChat, modelTagAccent('chat')),
      ('image', l10n.kindImage, modelTagAccent('image')),
      ('video', l10n.kindVideo, modelTagAccent('video')),
      ('multimodal', l10n.kindMultimodal, modelTagAccent('multimodal')),
    ];

    int countOf(String? kind) => kind == null
        ? models.length
        : models.where((m) => m.tag.toLowerCase() == kind).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              onChanged: (v) => setState(() => _modelQuery = v),
              decoration: InputDecoration(
                hintText: l10n.filterModels,
                prefixIcon: const Icon(Icons.search, size: AppSize.iconSm),
                prefixIconConstraints: const BoxConstraints(minWidth: 36),
              ),
              style: textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: ScrollEdgeFade(
              axis: Axis.horizontal,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (kind, label, color) in kinds) ...[
                      _buildKindPill(
                        label: label,
                        count: countOf(kind),
                        dot: color,
                        selected: _kindFilter == kind,
                        onTap: () => setState(() => _kindFilter = kind),
                      ),
                      if (kind != 'multimodal') const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          AppButton(
            label: l10n.addModel,
            icon: Icons.add,
            onPressed: () => _showModelDialog(l10n, appState, preChannelId: channel.id),
          ),
        ],
      ),
    );
  }

  Widget _buildKindPill({
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onTap,
    Color? dot,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // A chip, not a pill. `10e` 「筛选 chip」 draws the two apart on purpose:
    // a status badge is read-only and is a stadium, a filter is a target and
    // takes an edge plus the radius its neighbouring buttons take. 26 tall,
    // and the count is its own token — mono, a weight up, six pixels off the
    // label — rather than a second word inside it.
    final Color ink = selected ? colorScheme.onAccentTint : colorScheme.onSurfaceVariant;

    return Material(
      color: selected ? colorScheme.accentTint : colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        side: BorderSide(
          color: selected ? colorScheme.accentRing : colorScheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: dot == null ? 10 : 8, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dot != null) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: textTheme.bodySmall?.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: ink,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: textTheme.labelMedium?.mono.copyWith(
                  fontWeight: FontWeight.w600,
                  color: selected ? colorScheme.onAccentTint : colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModelsGrid(LLMChannel channel, AppLocalizations l10n, AppState appState) {
    final colorScheme = Theme.of(context).colorScheme;
    final models = appState.getModelsForChannel(channel.id!);
    if (models.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(48),
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outlineVariant, style: BorderStyle.solid),
        ),
        child: Column(
          children: [
            Icon(Icons.model_training, size: 48, color: colorScheme.outline.withAlpha(100)),
            const SizedBox(height: 16),
            Text(l10n.noModelsConfigured, style: TextStyle(color: colorScheme.outline)),
          ],
        ),
      );
    }

    final query = _modelQuery.trim().toLowerCase();
    final visible = [
      for (final m in models)
        if ((_kindFilter == null || m.tag.toLowerCase() == _kindFilter) &&
            (query.isEmpty ||
                m.modelName.toLowerCase().contains(query) ||
                m.modelId.toLowerCase().contains(query)))
          m,
    ];

    if (visible.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(l10n.pickerNoMatches, style: TextStyle(color: colorScheme.outline)),
        ),
      );
    }

    // Rows of equal-height pairs rather than a fixed-extent GridView: the
    // `14a` card's third row wraps, so its height is content-driven, and a
    // hardcoded mainAxisExtent would either clip the wrapped chips or pad
    // every unwrapped card. IntrinsicHeight is safe here — nothing in a card
    // measures via LayoutBuilder.
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 800 ? 2 : 1;
        final cells = <Widget>[
          for (final m in visible) _buildModelCard(m, l10n, appState, channel),
          _buildAddModelCard(l10n, appState, channel),
        ];

        return Column(
          children: [
            for (var r = 0; r < cells.length; r += columns)
              Padding(
                padding: EdgeInsets.only(top: r == 0 ? 0 : 12),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var c = 0; c < columns; c++) ...[
                        if (c > 0) const SizedBox(width: 12),
                        Expanded(
                          child: r + c < cells.length ? cells[r + c] : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// One model card, `14a`'s information-density upgrade: the fields the edit
  /// dialog settles — context, capabilities, reasoning, fee group — laid on
  /// the card, so what a model is configured to do is readable without
  /// opening it.
  Widget _buildModelCard(LLMModel model, AppLocalizations l10n, AppState appState, LLMChannel channel) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final pricingGroup = appState.allPricingGroups
        .cast<dynamic>()
        .firstWhere((g) => g.id == model.feeGroupId, orElse: () => null);

    // Legacy rows carry only the boolean; render its effort equivalent, same
    // as the edit dialog does.
    final effort =
        model.reasoningEffort ?? (model.enableThinking ? 'medium' : null);
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

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: colorScheme.outlineVariant.withAlpha(100)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => _showModelDialog(l10n, appState, model: model),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      model.modelName,
                      style: textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 9),
                  ModelTagChip(model.tag),
                  IconButton(
                    icon: const Icon(Icons.more_vert, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _showModelOptions(model, l10n, appState),
                  ),
                ],
              ),
              Text(
                model.modelId,
                style: textTheme.labelMedium?.mono
                    .copyWith(color: colorScheme.onSurfaceVariant),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 9),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _specChip(contextLabel, mono: true),
                        // One capability chip, the way `14a` curates it:
                        // streaming is the interesting fact, standard-request
                        // only worth stating when streaming is off.
                        if (model.supportsStream)
                          _specChip(l10n.capabilityStreamingShort)
                        else if (model.supportsStandard)
                          _specChip(l10n.capabilityStandardShort),
                        if (effortLabel != null)
                          _specChip(l10n.reasoningChip(effortLabel)),
                        if (model.enableWebSearch)
                          _specChip(
                            l10n.webSearchChip,
                            bg: colorScheme.primary.withValues(alpha: 0.10),
                            fg: colorScheme.primary,
                          ),
                        if (model.forceViewAllImages)
                          _specChip(l10n.viewAllImagesChip),
                        // Pinned-protocol chip (18b): after the capability
                        // chips, before the fee group. Absent on auto — four
                        // of six cards stay exactly as before.
                        ?_protocolPinChip(l10n, channel, model),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (pricingGroup != null)
                    _specChip(
                      pricingGroup.name,
                      bg: feeGroupAccent(pricingGroup.id as int?).withValues(alpha: 0.10),
                      fg: feeGroupAccent(pricingGroup.id as int?),
                    )
                  else
                    _specChip(
                      l10n.noFeeGroup,
                      fg: colorScheme.outline,
                      outlined: true,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The channel-card subline (18c): `N 个模型 · 面 · 面 · 面`, faces drawn
  /// from the channel's models' actual kinds in the fixed chat → image →
  /// video → multimodal order. Zero models degrades to the count alone.
  String _channelSubline(AppLocalizations l10n, List<LLMModel> models) {
    final present = models.map((m) => m.tag).toSet();
    final faces = [
      if (present.contains('chat')) l10n.kindChat,
      if (present.contains('image')) l10n.kindImage,
      if (present.contains('video')) l10n.kindVideo,
      if (present.contains('multimodal')) l10n.kindMultimodal,
    ];
    final count = l10n.countModels(models.length);
    return faces.isEmpty ? count : '$count · ${faces.join(' · ')}';
  }

  /// The pinned-protocol chip (18b, tier 2): visible only when a model has an
  /// explicit selection. Valid → primary-tinted chip naming the protocol;
  /// stale → outlined neutral chip ("selection inactive") with the reason in
  /// a tooltip — helper tone, not a warning, because the model still runs.
  Widget? _protocolPinChip(
      AppLocalizations l10n, LLMChannel channel, LLMModel model) {
    final pin = model.wireProtocol;
    if (pin == null || pin.isEmpty) return null;
    final colorScheme = Theme.of(context).colorScheme;

    if (LLMDispatcher.isStaleProtocolSelection(
        channel.type, model.modelId, pin)) {
      return Tooltip(
        message: l10n.protocolStaleTooltip(storedProtocolLabel(l10n, pin)),
        child: _specChip(
          l10n.protocolPinStale,
          fg: colorScheme.outline,
          outlined: true,
        ),
      );
    }
    return _specChip(
      storedProtocolLabel(l10n, pin),
      bg: colorScheme.primary.withValues(alpha: 0.10),
      fg: colorScheme.primary,
    );
  }

  /// A quiet spec token: rounded 6, faint fill, one short fact.
  Widget _specChip(String text, {Color? bg, Color? fg, bool mono = false, bool outlined = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final base = textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w500,
      color: fg ?? colorScheme.onSurfaceVariant,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      constraints: const BoxConstraints(maxWidth: 180),
      decoration: BoxDecoration(
        color: outlined ? null : (bg ?? colorScheme.surfaceContainerHigh),
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: outlined ? Border.all(color: colorScheme.outlineVariant) : null,
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: mono ? base?.mono : base,
      ),
    );
  }

  /// The dashed add-model cell closing the grid, as `14a` draws it — the same
  /// affordance the toolbar button offers, restated where the eye ends up
  /// after scanning the cards.
  Widget _buildAddModelCard(AppLocalizations l10n, AppState appState, LLMChannel channel) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return DashedBorder(
      color: colorScheme.outlineVariant,
      radius: AppRadius.lg,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _showModelDialog(l10n, appState, preChannelId: channel.id),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 96),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, size: AppSize.iconLg, color: colorScheme.outline),
                const SizedBox(height: 6),
                Text(
                  l10n.addModel,
                  style: textTheme.labelLarge?.copyWith(color: colorScheme.outline),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTokens(int tokens) {
    if (tokens >= 1048576) return '${tokens ~/ 1048576}M';
    if (tokens >= 1024) return '${tokens ~/ 1024}K';
    return '$tokens';
  }

  // --- Mobile Tab Content ---

  Widget _buildModelsMobileTab(AppLocalizations l10n, AppState appState) {
    if (appState.allChannels.isEmpty) {
      return Center(child: Text(l10n.noModelsConfigured));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: appState.allChannels.length,
      itemBuilder: (context, index) {
        final channel = appState.allChannels[index];
        final models = appState.getModelsForChannel(channel.id);

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            leading: ChannelAvatar(channel),
            title: Text(channel.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
            // Same capability subline as the desktop channel rail (18e: the
            // subline rides up into the tile header on narrow screens).
            subtitle: Text(_channelSubline(l10n, models),
                style: Theme.of(context).textTheme.bodySmall?.metricsOnly),
            children: [
              if (models.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(l10n.noModelsConfigured, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
                )
              else
                ...models.map((m) => ListTile(
                  title: Text(m.modelName),
                  // ListTile's subtitle slot is `onSurfaceVariant`; the type slot
                  // carries `onSurface`, so the muted tone is restated here.
                  subtitle: Text(
                    m.modelId,
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  trailing: ModelTagChip(m.tag),
                  onTap: () => _showModelDialog(l10n, appState, model: m),
                )),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: OverflowBar(
                  alignment: MainAxisAlignment.end,
                  children: [
                    if (channel.enableDiscovery)
                      AppButton(
                        label: l10n.fetchModels,
                        icon: Icons.refresh,
                        variant: AppButtonVariant.text,
                        onPressed: () => _showDiscoveryDialog(l10n, channel, appState),
                      ),
                    AppButton(
                      label: l10n.addModel,
                      icon: Icons.add,
                      variant: AppButtonVariant.text,
                      onPressed: () => _showModelDialog(l10n, appState, preChannelId: channel.id),
                    ),
                  ],
                ),
              )
            ],
          ),
        );
      },
    );
  }

  Widget _buildChannelsMobileTab(AppLocalizations l10n, AppState appState) {
    // Same arrangement, same storage — only the gesture differs: no hover to
    // reveal a handle on a phone, so a row is picked up by holding it.
    final draggable = appState.allChannels.length > 1;
    return Scaffold(
      body: ReorderableListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: appState.allChannels.length,
        buildDefaultDragHandles: false,
        onReorderItem: (oldIndex, newIndex) =>
            _reorderChannels(l10n, appState, oldIndex, newIndex),
        onReorderStart: (_) => HapticFeedback.selectionClick(),
        proxyDecorator: _channelDragProxy,
        itemBuilder: (context, index) {
          final channel = appState.allChannels[index];
          final card = Card(
            child: ListTile(
              leading: ChannelAvatar(channel, size: 32),
              title: Text(channel.displayName),
              subtitle: Text(
                channel.endpoint,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showChannelDialog(l10n, appState, channel: channel),
            ),
          );
          if (!draggable) {
            return KeyedSubtree(key: ValueKey(channel.id), child: card);
          }
          return _ChannelLongPressDragListener(
            key: ValueKey(channel.id),
            index: index,
            child: card,
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showChannelDialog(l10n, appState),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showModelOptions(LLMModel model, AppLocalizations l10n, AppState appState) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(l10n.edit),
              onTap: () {
                Navigator.pop(context);
                _showModelDialog(l10n, appState, model: model);
              },
            ),
            ListTile(
              // `error`, not a red literal: destructive is a semantic role and
              // Material derives it independently of the seed, so this stays
              // red at every theme without being written as one.
              leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
              title: Text(l10n.delete,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: () {
                Navigator.pop(context);
                _confirmDeleteModel(l10n, model, appState);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteModel(AppLocalizations l10n, LLMModel model, AppState appState) {
    AppDialog.show<void>(
      context,
      title: l10n.deleteModelConfirmTitle,
      content: Text(l10n.deleteModelConfirmMessage(model.modelName)),
      actions: [
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.pop(context),
        ),
        AppButton(
          label: l10n.delete,
          variant: AppButtonVariant.destructive,
          onPressed: () async {
            await appState.deleteModel(model.id!);
            if (mounted) Navigator.pop(context);
          },
        ),
      ],
    );
  }

  void _showChannelDialog(AppLocalizations l10n, AppState appState, {LLMChannel? channel}) {
    if (channel == null) {
      if (Responsive.isMobile(context)) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (context) => ChannelWizardDialog(l10n: l10n, appState: appState),
          fullscreenDialog: true,
        ));
      } else {
        showDialog(
          context: context,
          builder: (context) => ChannelWizardDialog(l10n: l10n, appState: appState),
        );
      }
    } else {
      showDialog(
        context: context,
        builder: (context) => ChannelEditDialog(l10n: l10n, appState: appState, channel: channel),
      );
    }
  }

  void _confirmDeleteChannel(AppLocalizations l10n, LLMChannel channel, AppState appState) {
    AppDialog.show<void>(
      context,
      title: l10n.delete,
      content: Text(l10n.deleteChannelConfirm(channel.displayName)),
      actions: [
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.pop(context),
        ),
        AppButton(
          label: l10n.delete,
          variant: AppButtonVariant.destructive,
          onPressed: () async {
            await appState.deleteChannel(channel.id!);
            if (mounted) Navigator.pop(context);
          },
        ),
      ],
    );
  }

  void _showModelDialog(AppLocalizations l10n, AppState appState, {LLMModel? model, int? preChannelId}) {
    showDialog(
      context: context,
      builder: (context) => ModelEditDialog(l10n: l10n, appState: appState, model: model, preChannelId: preChannelId),
    );
  }

  void _showDiscoveryDialog(AppLocalizations l10n, LLMChannel channel, AppState appState) async {
    final config = LLMModelConfig(
      modelId: 'discovery',
      channelType: channel.type,
      endpoint: channel.endpoint,
      apiKey: channel.apiKey,
    );

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => DiscoveryDialog(
        channel: channel,
        config: config,
        appState: appState,
        l10n: l10n,
      ),
    );
  }
}

