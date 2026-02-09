import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/fee_group.dart';
import '../../models/llm_channel.dart';
import '../../models/llm_model.dart';
import '../../services/llm/llm_models.dart';
import '../../state/app_state.dart';
import '../../widgets/app_section.dart';
import '../../widgets/fee_group_manager.dart';
import '../../widgets/models/channel_edit_dialog.dart';
import '../../widgets/models/discovery_dialog.dart';
import '../../widgets/models/model_edit_dialog.dart';

class ModelsScreen extends StatefulWidget {
  const ModelsScreen({super.key});

  @override
  State<ModelsScreen> createState() => _ModelsScreenState();
}

class _ModelsScreenState extends State<ModelsScreen> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.modelManager),
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.modelsTab),
              Tab(text: l10n.channelsTab),
            ],
          ),
        ),
        body: Consumer<AppState>(
          builder: (context, appState, child) => TabBarView(
            children: [
              _buildModelsTab(l10n, appState),
              _buildChannelsTab(l10n, appState),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModelsTab(AppLocalizations l10n, AppState appState) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            AppSection(
              title: l10n.modelManagement,
              children: [
                if (appState.allChannels.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Center(child: Text(l10n.noModelsConfigured)),
                  ),
                ...appState.allChannels.map((channel) {
                  final channelModels = appState.getModelsForChannel(channel.id);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _buildChannelGroup(channel, channelModels, l10n, appState),
                  );
                }),
              ],
            ),
            AppSection(
              title: l10n.feeManagement,
              padding: const EdgeInsets.only(bottom: 64),
              children: [
                const FeeGroupManager(mode: FeeGroupManagerMode.section),
              ],
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showModelDialog(l10n, appState),
        icon: const Icon(Icons.add),
        label: Text(l10n.addModel),
      ),
    );
  }

  Widget _buildChannelGroup(LLMChannel channel, List<LLMModel> models, AppLocalizations l10n, AppState appState) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool enableDiscovery = channel.enableDiscovery;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Row(
          children: [
            if (channel.tag != null && channel.tag!.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Color(channel.tagColor ?? 0xFF607D8B).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Color(channel.tagColor ?? 0xFF607D8B).withValues(alpha: 0.5)),
                ),
                child: Text(
                  channel.tag!,
                  style: TextStyle(
                    fontSize: 10, 
                    color: Color(channel.tagColor ?? 0xFF607D8B),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Text(channel.displayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
        initiallyExpanded: true,
        backgroundColor: colorScheme.surface,
        collapsedBackgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (enableDiscovery)
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: () => _showDiscoveryDialog(l10n, channel, appState),
                tooltip: l10n.fetchModels,
              ),
            IconButton(
              icon: const Icon(Icons.add, size: 20),
              onPressed: () => _showModelDialog(l10n, appState, preChannelId: channel.id),
              tooltip: l10n.addModel,
            ),
            const Icon(Icons.expand_more),
          ],
        ),
        children: [
          if (models.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Center(child: Text(l10n.noModelsConfigured, style: TextStyle(color: colorScheme.outline))),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: models.length,
              itemBuilder: (context, index) {
                final model = models[index];
                final feeGroup = appState.allFeeGroups.cast<FeeGroup?>().firstWhere((g) => g?.id == model.feeGroupId, orElse: () => null);
                return ListTile(
                  title: Text(model.modelName),
                  subtitle: Row(
                    children: [
                      Text(model.modelId, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                      const SizedBox(width: 8),
                      if (feeGroup != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            feeGroup.name,
                            style: TextStyle(fontSize: 10, color: colorScheme.onSecondaryContainer),
                          ),
                        ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildTagChip(model.tag),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _showModelDialog(l10n, appState, model: model),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _confirmDeleteModel(l10n, model, appState),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildTagChip(String tag) {
    Color color;
    switch (tag) {
      case 'image': color = Colors.purple; break;
      case 'multimodal': color = Colors.orange; break;
      default: color = Colors.blue;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        tag.toUpperCase(),
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
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
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await appState.deleteModel(model.id!);
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            child: Text(l10n.delete, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelsTab(AppLocalizations l10n, AppState appState) {
    return Scaffold(
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: appState.allChannels.length,
        itemBuilder: (context, index) {
          final channel = appState.allChannels[index];
          return Card(
            child: ListTile(
              leading: (channel.tag != null && channel.tag!.isNotEmpty)
                ? CircleAvatar(
                    backgroundColor: Color(channel.tagColor ?? 0xFF607D8B),
                    radius: 16,
                    child: Text(channel.tag![0], style: const TextStyle(color: Colors.white, fontSize: 12)),
                  )
                : const Icon(Icons.cloud_queue),
              title: Text(channel.displayName),
              subtitle: Text(channel.endpoint, style: const TextStyle(fontSize: 12)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _showChannelDialog(l10n, appState, channel: channel),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _confirmDeleteChannel(l10n, channel, appState),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showChannelDialog(l10n, appState),
        icon: const Icon(Icons.add),
        label: Text(l10n.addChannel),
      ),
    );
  }

  void _showChannelDialog(AppLocalizations l10n, AppState appState, {LLMChannel? channel}) {
    showDialog(
      context: context,
      builder: (context) => ChannelEditDialog(l10n: l10n, appState: appState, channel: channel),
    );
  }

  void _confirmDeleteChannel(AppLocalizations l10n, LLMChannel channel, AppState appState) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.delete),
        content: Text(l10n.deleteChannelConfirm(channel.displayName)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await appState.deleteChannel(channel.id!);
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            child: Text(l10n.delete, style: const TextStyle(color: Colors.white)),
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
    final type = channel.type.contains('google') ? 'google-genai' : 'openai-api';
    
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