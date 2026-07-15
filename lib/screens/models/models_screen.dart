import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../models/llm_channel.dart';
import '../../models/llm_model.dart';
import '../../services/database_service.dart';
import '../../services/llm/channel_dialect.dart';
import '../../services/llm/llm_types.dart';
import '../../state/app_state.dart';
import '../../widgets/models/channel_edit_dialog.dart';
import '../../widgets/models/channel_wizard_dialog.dart';
import '../../widgets/models/discovery_dialog.dart';
import '../../widgets/models/model_edit_dialog.dart';
import '../../widgets/panel_resizer.dart';

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
  // Master-detail on a `surfaceContainer` canvas: a channels card on the
  // left (with the screen header and add-channel action) and a detail card
  // on the right showing the selected channel and its models. The two cards
  // are separated by a draggable PanelResizer gutter.
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
          body: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                PanelCard(
                  width: _sidebarWidth,
                  child: _buildChannelsPanel(l10n, appState, channels),
                ),
                PanelResizer(
                  onDrag: (dx) => setState(() {
                    _sidebarWidth = (_sidebarWidth + dx).clamp(_minSidebarWidth, _maxSidebarWidth);
                  }),
                  onDragEnd: () => DatabaseService()
                      .saveSetting('models_sidebar_width', _sidebarWidth.round().toString()),
                ),
                Expanded(
                  child: PanelCard(
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
    final modelCount = appState.allModels.length;

    // Screen header lives inside the top of the card; its bottom border
    // becomes an internal divider on the inset-panel canvas.
    final header = Container(
      height: 56,
      padding: const EdgeInsets.only(left: 16, right: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withAlpha(90))),
      ),
      child: Row(
        children: [
          Icon(Icons.memory, size: 22, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.modelManager,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  l10n.modelsAndChannelsCount(modelCount, channels.length),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 22),
            onPressed: () => _showChannelDialog(l10n, appState),
            tooltip: l10n.addChannel,
          ),
        ],
      ),
    );

    return Column(
      children: [
        header,
        Expanded(
          child: channels.isEmpty
              ? Center(
                  child: Text(
                    l10n.noModelsConfigured,
                    style: TextStyle(color: colorScheme.outline),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: channels.length,
                  itemBuilder: (context, index) {
                    final channel = channels[index];
                    final isSelected = channel.id == _selectedChannelId;
                    final models = appState.getModelsForChannel(channel.id);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: ListTile(
                        selected: isSelected,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        selectedTileColor: colorScheme.secondaryContainer,
                        leading: _buildChannelIcon(channel),
                        title: Text(
                          channel.displayName,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          l10n.countModels(models.length),
                          style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                        ),
                        onTap: () => setState(() => _selectedChannelId = channel.id),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // --- Detail Panel (right card) ---

  Widget _buildDetailPanel(AppLocalizations l10n, AppState appState, LLMChannel channel) {
    final colorScheme = Theme.of(context).colorScheme;
    final showActionLabels = Responsive.isDesktop(context);

    final header = Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withAlpha(90))),
      ),
      child: Row(
        children: [
          _buildChannelIcon(channel, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  channel.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  channel.endpoint,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (channel.enableDiscovery) ...[
            if (showActionLabels)
              FilledButton.tonalIcon(
                onPressed: () => _showDiscoveryDialog(l10n, channel, appState),
                icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                label: Text(l10n.fetchModels),
                style: tonalButtonStyle(Theme.of(context).colorScheme),
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
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            color: colorScheme.error,
            onPressed: () => _confirmDeleteChannel(l10n, channel, appState),
            tooltip: l10n.delete,
          ),
        ],
      ),
    );

    return Column(
      children: [
        header,
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          l10n.modelsTab,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        TextButton.icon(
                          onPressed: () =>
                              _showModelDialog(l10n, appState, preChannelId: channel.id),
                          icon: const Icon(Icons.add, size: 18),
                          label: Text(l10n.addModel),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildModelsGrid(channel, l10n, appState),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModelsGrid(LLMChannel channel, AppLocalizations l10n, AppState appState) {
    final models = appState.getModelsForChannel(channel.id!);
    if (models.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(48),
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, style: BorderStyle.solid),
        ),
        child: Column(
          children: [
            Icon(Icons.model_training, size: 48, color: Theme.of(context).colorScheme.outline.withAlpha(100)),
            const SizedBox(height: 16),
            Text(l10n.noModelsConfigured, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 800 ? 2 : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            mainAxisExtent: 100,
          ),
          itemCount: models.length,
          itemBuilder: (context, index) => _buildModelCard(models[index], l10n, appState),
        );
      },
    );
  }

  Widget _buildModelCard(LLMModel model, AppLocalizations l10n, AppState appState) {
    final colorScheme = Theme.of(context).colorScheme;
    final pricingGroup = appState.allPricingGroups.cast<dynamic>().firstWhere((g) => g.id == model.feeGroupId, orElse: () => null);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withAlpha(100)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showModelDialog(l10n, appState, model: model),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(model.modelName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(child: Text(model.modelId, style: TextStyle(fontSize: 12, color: colorScheme.outline), overflow: TextOverflow.ellipsis)),
                        if (pricingGroup != null) ...[
                          const SizedBox(width: 8),
                          _buildFeeBadge(pricingGroup.name, colorScheme),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              _buildTagChip(model.tag),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.more_vert, size: 20),
                onPressed: () => _showModelOptions(model, l10n, appState),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeeBadge(String name, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withAlpha(150),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(name, style: TextStyle(fontSize: 10, color: colorScheme.onSecondaryContainer, fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildChannelIcon(LLMChannel channel, {double size = 24}) {
    if (channel.tag != null && channel.tag!.isNotEmpty) {
      return CircleAvatar(
        backgroundColor: Color(channel.tagColor ?? 0xFF607D8B),
        radius: size / 2,
        child: Text(channel.tag![0].toUpperCase(), style: TextStyle(color: Colors.white, fontSize: size * 0.5, fontWeight: FontWeight.bold)),
      );
    }
    return Icon(Icons.cloud_queue, size: size * 0.8);
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
            leading: _buildChannelIcon(channel),
            title: Text(channel.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(l10n.countModels(models.length), style: const TextStyle(fontSize: 12)),
            children: [
              if (models.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(l10n.noModelsConfigured, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
                )
              else
                ...models.map((m) => ListTile(
                  title: Text(m.modelName),
                  subtitle: Text(m.modelId, style: const TextStyle(fontSize: 11)),
                  trailing: _buildTagChip(m.tag),
                  onTap: () => _showModelDialog(l10n, appState, model: m),
                )),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: OverflowBar(
                  alignment: MainAxisAlignment.end,
                  children: [
                    if (channel.enableDiscovery)
                      TextButton.icon(
                        icon: const Icon(Icons.refresh, size: 18),
                        label: Text(l10n.fetchModels),
                        onPressed: () => _showDiscoveryDialog(l10n, channel, appState),
                      ),
                    TextButton.icon(
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(l10n.addModel),
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
    return Scaffold(
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: appState.allChannels.length,
        itemBuilder: (context, index) {
          final channel = appState.allChannels[index];
          return Card(
            child: ListTile(
              leading: _buildChannelIcon(channel, size: 32),
              title: Text(channel.displayName),
              subtitle: Text(channel.endpoint, style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showChannelDialog(l10n, appState, channel: channel),
            ),
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
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: Text(l10n.delete, style: const TextStyle(color: Colors.red)),
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

  Widget _buildTagChip(String tag) {
    Color color;
    switch (tag.toLowerCase()) {
      case 'image': color = Colors.purple; break;
      case 'video': color = Colors.red; break;
      case 'multimodal': color = Colors.orange; break;
      case 'chat': color = Colors.green; break;
      default: color = Colors.blue;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(100)),
      ),
      child: Text(
        tag.toUpperCase(),
        style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  void _confirmDeleteModel(AppLocalizations l10n, LLMModel model, AppState appState) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteModelConfirmTitle),
        content: Text(l10n.deleteModelConfirmMessage(model.modelName)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () async {
              await appState.deleteModel(model.id!);
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(l10n.delete),
          ),
        ],
      ),
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.delete),
        content: Text(l10n.deleteChannelConfirm(channel.displayName)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () async {
              await appState.deleteChannel(channel.id!);
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  void _showModelDialog(AppLocalizations l10n, AppState appState, {LLMModel? model, int? preChannelId}) {
    showDialog(
      context: context,
      builder: (context) => ModelEditDialog(l10n: l10n, appState: appState, model: model, preChannelId: preChannelId),
    );
  }

  void _showDiscoveryDialog(AppLocalizations l10n, LLMChannel channel, AppState appState) async {
    final type = ChannelDialect.providerType(channel.type);

    final config = LLMModelConfig(
      modelId: 'discovery',
      type: type,
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
