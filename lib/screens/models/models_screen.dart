import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../models/llm_channel.dart';
import '../../models/llm_model.dart';
import '../../services/database_service.dart';
import '../../services/llm/llm_types.dart';
import '../../state/app_state.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/models/channel_edit_dialog.dart';
import '../../widgets/models/channel_wizard_dialog.dart';
import '../../widgets/models/discovery_dialog.dart';
import '../../widgets/models/model_edit_dialog.dart';
import '../../widgets/panel_resizer.dart';
import '../../widgets/pricing_group_manager.dart';
import 'widgets/channel_column.dart';
import 'widgets/model_detail_column.dart';
import 'widgets/models_actions.dart';
import 'widgets/models_controls.dart';
import 'widgets/models_phone_layout.dart';

/// Models & Channels (`D1a`): channels on the left, the selected channel's
/// models on the right; on a phone, the two as tabs.
///
/// This state owns what outlives the pieces — the selected channel, the
/// channel search, the column width — and every dialog, confirmation and
/// reorder the pieces ask for through [ModelsActions].
class ModelsScreen extends StatefulWidget {
  const ModelsScreen({super.key});

  @override
  State<ModelsScreen> createState() => _ModelsScreenState();
}

class _ModelsScreenState extends State<ModelsScreen> {
  static const double _minSidebarWidth = 220;
  static const double _maxSidebarWidth = 420;

  /// Drag accumulator, allowed [_kDragSlack] past the limits so the handle
  /// re-engages where the pointer actually is after a drag past the end,
  /// instead of the instant the pointer reverses. Null when no drag is live.
  static const double _kDragSlack = 24;
  double? _dragSidebarWidth;

  int? _selectedChannelId;

  /// The channel column's width once loaded or dragged; null takes the
  /// default for the window (`D1a`: 300, tablet 260).
  double? _sidebarWidth;

  final TextEditingController _channelSearch = TextEditingController();

  /// Plain lowercase substring match on name and tag — the lists are at most
  /// a few hundred rows.
  String _channelQuery = '';

  /// Focus for the channel column, which is where Alt+↑/↓ and Ctrl+↑/↓ are
  /// bound. A row tap takes it, so the chord works right after picking a
  /// channel.
  final FocusNode _channelFocus = FocusNode(debugLabel: 'ModelsScreen.channels');

  @override
  void initState() {
    super.initState();
    _loadSidebarWidth();
  }

  @override
  void dispose() {
    _channelSearch.dispose();
    _channelFocus.dispose();
    super.dispose();
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

    // `FilledFieldScope` stays around the whole screen: the channel and model
    // editors opened from here capture this theme, and their fields are drawn
    // filled. The columns give their own fields the panel fill.
    return FilledFieldScope(
      child: Consumer<AppState>(
        builder: (context, appState, _) {
          final actions = _actionsFor(l10n, appState);
          return ResponsiveBuilder(
            mobile: ModelsPhoneLayout(appState: appState, actions: actions),
            desktop: _buildColumns(context, l10n, appState, actions),
          );
        },
      ),
    );
  }

  ModelsActions _actionsFor(AppLocalizations l10n, AppState appState) => ModelsActions(
        addChannel: () => _showChannelDialog(l10n, appState),
        editChannel: (channel) => _showChannelDialog(l10n, appState, channel: channel),
        deleteChannel: (channel) => _confirmDeleteChannel(l10n, channel, appState),
        fetchModels: (channel) => _showDiscoveryDialog(l10n, channel, appState),
        addModel: (channelId) => _showModelDialog(l10n, appState, preChannelId: channelId),
        editModel: (model) => _showModelDialog(l10n, appState, model: model),
        deleteModel: (model) => _confirmDeleteModel(l10n, model, appState),
        moveChannel: (oldIndex, newIndex) => _reorderChannels(l10n, appState, oldIndex, newIndex),
        openFeeManager: _showFeeGroupManager,
      );

  // --- Two columns (tablet + desktop) ---------------------------------------

  Widget _buildColumns(
    BuildContext context,
    AppLocalizations l10n,
    AppState appState,
    ModelsActions actions,
  ) {
    final channels = appState.allChannels;
    _ensureSelection(channels);
    final selected = channels.cast<LLMChannel?>().firstWhere(
          (c) => c?.id == _selectedChannelId,
          orElse: () => null,
        );

    final query = _channelQuery.trim().toLowerCase();
    final visible = query.isEmpty
        ? channels
        : [
            for (final c in channels)
              if (_matchesQuery(c, query)) c,
          ];
    final dense = Responsive.isTablet(context);
    final width = _sidebarWidth ?? (dense ? 260.0 : 300.0);

    return Row(
      children: [
        PanelCard(
          width: width,
          shape: PanelShape.column,
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): () =>
                  _moveSelectedBy(l10n, appState, -1),
              const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true): () =>
                  _moveSelectedBy(l10n, appState, 1),
              // `00d` 无障碍: Ctrl+↑ / Ctrl+↓, beside the Alt chord the row menu
              // and the footnote name.
              const SingleActivator(LogicalKeyboardKey.arrowUp, control: true): () =>
                  _moveSelectedBy(l10n, appState, -1),
              const SingleActivator(LogicalKeyboardKey.arrowDown, control: true): () =>
                  _moveSelectedBy(l10n, appState, 1),
            },
            child: Focus(
              focusNode: _channelFocus,
              child: ChannelColumn(
                appState: appState,
                visible: visible,
                selectedId: _selectedChannelId,
                searchController: _channelSearch,
                onQueryChanged: (v) => setState(() => _channelQuery = v),
                reorderLocked: query.isNotEmpty,
                dense: dense,
                touch: _touchReorder,
                actions: actions,
                onSelect: (channel) {
                  setState(() => _selectedChannelId = channel.id);
                  _channelFocus.requestFocus();
                },
              ),
            ),
          ),
        ),
        PanelResizer(
          shape: PanelShape.column,
          onDrag: (dx) => setState(() {
            _dragSidebarWidth = ((_dragSidebarWidth ?? width) + dx)
                .clamp(_minSidebarWidth - _kDragSlack, _maxSidebarWidth + _kDragSlack);
            _sidebarWidth = _dragSidebarWidth!.clamp(_minSidebarWidth, _maxSidebarWidth);
          }),
          onDragEnd: () {
            _dragSidebarWidth = null;
            final saved = _sidebarWidth;
            if (saved != null) {
              DatabaseService().saveSetting('models_sidebar_width', saved.round().toString());
            }
          },
        ),
        Expanded(
          child: PanelCard(
            shape: PanelShape.column,
            child: selected == null
                ? ModelsEmptyState(
                    icon: Icons.touch_app_outlined,
                    title: l10n.selectAChannel,
                    description: l10n.selectAChannelHint,
                  )
                : ModelDetailColumn(
                    channel: selected,
                    models: appState.getModelsForChannel(selected.id),
                    pricingGroups: appState.allPricingGroups,
                    dense: dense,
                    actions: actions,
                  ),
          ),
        ),
      ],
    );
  }

  /// Where the selected channel last stood in the stored order, so that when
  /// it disappears the selection lands on the channel that took its place.
  int _selectedIndex = 0;

  /// Keeps the selection pointing at a channel that exists.
  ///
  /// Runs on every rebuild of the channel data, which is what catches a
  /// channel deleted from anywhere — this screen's confirm, or the channel
  /// editor's own delete, which never passes through this screen.
  void _ensureSelection(List<LLMChannel> channels) {
    if (channels.isEmpty) {
      _selectedChannelId = null;
      _selectedIndex = 0;
      return;
    }
    final index = channels.indexWhere((c) => c.id == _selectedChannelId);
    if (index >= 0) {
      _selectedIndex = index;
      return;
    }
    final fallback = _selectedIndex.clamp(0, channels.length - 1);
    _selectedChannelId = channels[fallback].id;
    _selectedIndex = fallback;
  }

  /// Whether reordering is driven by long press rather than by press-and-move.
  ///
  /// Keyed off the platform rather than the last input event: a tablet running
  /// the two-column layout is still a touch device, and an immediate drag there
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

  /// Plain lowercase substring match of a channel's name and tag against an
  /// already-lowercased [query].
  static bool _matchesQuery(LLMChannel channel, String query) =>
      channel.displayName.toLowerCase().contains(query) || (channel.tag ?? '').toLowerCase().contains(query);

  /// Alt+↑/↓ and Ctrl+↑/↓ on the selected channel: one place in the stored
  /// order — the move the row menu makes, so like the menu it works while a
  /// search narrows the rail (`00d` 禁用: the menu is how a filtered rail is
  /// reordered). A selected channel the search hides is left where it is: the
  /// user can see neither it nor what it would pass.
  void _moveSelectedBy(AppLocalizations l10n, AppState appState, int delta) {
    final channels = appState.allChannels;
    final index = channels.indexWhere((c) => c.id == _selectedChannelId);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= channels.length) return;
    final query = _channelQuery.trim().toLowerCase();
    if (query.isNotEmpty && !_matchesQuery(channels[index], query)) return;
    _reorderChannels(l10n, appState, index, target);
  }

  /// Persist a move, and say so only when it fails — a successful reorder is
  /// already reported by the row being where the user put it.
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

  // --- Dialogs --------------------------------------------------------------

  void _showFeeGroupManager() {
    AppDialog.show<void>(
      context,
      maxWidth: 520,
      maxHeight: 720,
      content: const PricingGroupManager(mode: PricingGroupManagerMode.dialog),
    );
  }

  void _confirmDeleteModel(AppLocalizations l10n, LLMModel model, AppState appState) {
    AppDialog.show<void>(
      context,
      icon: Icons.delete_outline,
      iconColor: Theme.of(context).colorScheme.error,
      maxWidth: 440,
      title: l10n.deleteModelConfirmTitle,
      content: Text(l10n.deleteModelConfirmMessage(model.modelName)),
      actions: [
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          autofocus: true,
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

  /// `D1a · 1e` 删除渠道确认: the error plate, the channel and what goes with
  /// it, Cancel holding the focus.
  void _confirmDeleteChannel(AppLocalizations l10n, LLMChannel channel, AppState appState) {
    final modelCount = appState.getModelsForChannel(channel.id).length;
    AppDialog.show<void>(
      context,
      icon: Icons.delete_outline,
      iconColor: Theme.of(context).colorScheme.error,
      maxWidth: 440,
      title: l10n.deleteChannelTitle(channel.displayName),
      subtitle: l10n.deleteChannelModelsNote(modelCount),
      content: Text(l10n.deleteChannelBody),
      actions: [
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          autofocus: true,
          onPressed: () => Navigator.pop(context),
        ),
        AppButton(
          label: l10n.deleteChannel,
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
      // The editor is a full-screen page on a phone and handles the insets
      // itself; the route's own safe area would leave scrim strips around it.
      useSafeArea: false,
      builder: (context) => ModelEditDialog(l10n: l10n, appState: appState, model: model, preChannelId: preChannelId),
    );
  }

  void _showDiscoveryDialog(AppLocalizations l10n, LLMChannel channel, AppState appState) {
    final config = LLMModelConfig(
      modelId: 'discovery',
      channelType: channel.type,
      endpoint: channel.endpoint,
      apiKey: channel.apiKey,
    );

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
