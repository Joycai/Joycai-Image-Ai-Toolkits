import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/llm/llm_models.dart';
import '../../services/llm/model_discovery_service.dart';
import '../../state/app_state.dart';
import '../../widgets/api_key_field.dart';
import '../../widgets/app_section.dart';
import '../../widgets/fee_group_manager.dart';

class ModelsScreen extends StatefulWidget {
  const ModelsScreen({super.key});

  @override
  State<ModelsScreen> createState() => _ModelsScreenState();
}

class _ModelsScreenState extends State<ModelsScreen> {
  final List<Color> _predefinedColors = [
    Colors.blue,
    Colors.red,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.pink,
    Colors.indigo,
    Colors.brown,
    Colors.blueGrey,
  ];

  @override
  void initState() {
    super.initState();
  }

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
                  final channelModels = appState.getModelsForChannel(channel['id']);
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
                FeeGroupManager(appState: appState, mode: FeeGroupManagerMode.section),
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

  Widget _buildChannelGroup(Map<String, dynamic> channel, List<Map<String, dynamic>> models, AppLocalizations l10n, AppState appState) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool enableDiscovery = (channel['enable_discovery'] ?? 1) == 1;

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
            if (channel['tag'] != null && channel['tag'].toString().isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Color(channel['tag_color'] ?? 0xFF607D8B).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Color(channel['tag_color'] ?? 0xFF607D8B).withValues(alpha: 0.5)),
                ),
                child: Text(
                  channel['tag'],
                  style: TextStyle(
                    fontSize: 10, 
                    color: Color(channel['tag_color'] ?? 0xFF607D8B),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Text(channel['display_name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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
              onPressed: () => _showModelDialog(l10n, appState, preChannelId: channel['id']),
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
                final feeGroup = appState.allFeeGroups.firstWhere((g) => g['id'] == model['fee_group_id'], orElse: () => {});
                return ListTile(
                  title: Text(model['model_name']),
                  subtitle: Row(
                    children: [
                      Text(model['model_id'], style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                      const SizedBox(width: 8),
                      if (feeGroup.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            feeGroup['name'],
                            style: TextStyle(fontSize: 10, color: colorScheme.onSecondaryContainer),
                          ),
                        ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildTagChip(model['tag']),
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

  void _confirmDeleteModel(AppLocalizations l10n, Map<String, dynamic> model, AppState appState) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteModelConfirmTitle),
        content: Text(l10n.deleteModelConfirmMessage(model['model_name'])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await appState.deleteModel(model['id']);
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
              leading: (channel['tag'] != null && channel['tag'].toString().isNotEmpty)
                ? CircleAvatar(
                    backgroundColor: Color(channel['tag_color'] ?? 0xFF607D8B),
                    radius: 16,
                    child: Text(channel['tag'][0], style: const TextStyle(color: Colors.white, fontSize: 12)),
                  )
                : const Icon(Icons.cloud_queue),
              title: Text(channel['display_name']),
              subtitle: Text(channel['endpoint'], style: const TextStyle(fontSize: 12)),
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

  void _showChannelDialog(AppLocalizations l10n, AppState appState, {Map<String, dynamic>? channel}) {
    final nameCtrl = TextEditingController(text: channel?['display_name'] ?? '');
    final epCtrl = TextEditingController(text: channel?['endpoint'] ?? '');
    final keyCtrl = TextEditingController(text: channel?['api_key'] ?? '');
    final tagCtrl = TextEditingController(text: channel?['tag'] ?? '');
    
    String type = channel?['type'] ?? 'google-genai-rest';
    bool discovery = (channel?['enable_discovery'] ?? 1) == 1;
    int tagColor = channel?['tag_color'] ?? _predefinedColors.first.toARGB32();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          String endpointHint = "";
          if (type == 'openai-api-rest') {
            endpointHint = "Hint: OpenAI compatible endpoints usually end with '/v1'";
          } else if (type.contains('google')) {
            endpointHint = "Hint: Google GenAI endpoints usually end with '/v1beta' (internal handling)";
          }

          return AlertDialog(
            title: Text(channel == null ? l10n.addChannel : l10n.editChannel),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameCtrl, decoration: InputDecoration(labelText: l10n.displayName)),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    items: const [
                      DropdownMenuItem(value: 'google-genai-rest', child: Text('Google GenAI REST')),
                      DropdownMenuItem(value: 'openai-api-rest', child: Text('OpenAI API REST')),
                      DropdownMenuItem(value: 'official-google-genai-api', child: Text('Official Google GenAI API')),
                    ],
                    onChanged: (v) => setDialogState(() {
                      type = v!;
                      if (channel == null) {
                        if (type == 'openai-api-rest') {
                          epCtrl.text = 'https://api.openai.com/v1';
                        } else {
                          epCtrl.text = 'https://generativelanguage.googleapis.com';
                        }
                      }
                    }),
                    decoration: InputDecoration(labelText: l10n.channelType),
                  ),
                  TextField(
                    controller: epCtrl, 
                    decoration: InputDecoration(
                      labelText: l10n.endpointUrl,
                      helperText: endpointHint,
                      helperStyle: const TextStyle(color: Colors.blueGrey),
                    ),
                  ),
                  ApiKeyField(controller: keyCtrl, label: l10n.apiKey, onChanged: (v) {}),
                SwitchListTile(
                  title: Text(l10n.enableDiscovery),
                  value: discovery,
                  onChanged: (v) => setDialogState(() => discovery = v),
                ),
                TextField(controller: tagCtrl, decoration: InputDecoration(labelText: l10n.tag)),
                const SizedBox(height: 16),
                Align(alignment: Alignment.centerLeft, child: Text(l10n.tagColor, style: const TextStyle(fontSize: 12))),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _predefinedColors.map((color) => InkWell(
                    onTap: () => setDialogState(() => tagColor = color.toARGB32()),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: tagColor == color.toARGB32() ? Colors.black : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                  )).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
            ElevatedButton(
              onPressed: () async {
                final data = {
                  'display_name': nameCtrl.text,
                  'endpoint': epCtrl.text,
                  'api_key': keyCtrl.text,
                  'type': type,
                  'enable_discovery': discovery ? 1 : 0,
                  'tag': tagCtrl.text,
                  'tag_color': tagColor,
                };
                if (channel == null) {
                  await appState.addChannel(data);
                } else {
                  await appState.updateChannel(channel['id'], data);
                }
                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
              child: Text(l10n.save),
            ),
          ],
        );
        },
      ),
    );
  }

  void _confirmDeleteChannel(AppLocalizations l10n, Map<String, dynamic> channel, AppState appState) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.delete),
        content: Text(l10n.deleteChannelConfirm(channel['display_name'])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await appState.deleteChannel(channel['id']);
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

  void _showModelDialog(AppLocalizations l10n, AppState appState, {Map<String, dynamic>? model, int? preChannelId}) {
    final idCtrl = TextEditingController(text: model?['model_id'] ?? '');
    final nameCtrl = TextEditingController(text: model?['model_name'] ?? '');
    
    int? channelId = model?['channel_id'] ?? preChannelId ?? (appState.allChannels.isNotEmpty ? appState.allChannels.first['id'] : null);
    String tag = model?['tag'] ?? 'chat';
    int? feeGroupId = model?['fee_group_id'];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(model == null ? l10n.addLlmModel : l10n.editLlmModel),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: channelId,
                  items: appState.allChannels.map((c) => DropdownMenuItem(
                    value: c['id'] as int,
                    child: Text(c['display_name']),
                  )).toList(),
                  onChanged: (v) => setDialogState(() => channelId = v),
                  decoration: InputDecoration(labelText: l10n.channel),
                ),
                TextField(controller: idCtrl, decoration: InputDecoration(labelText: l10n.modelIdLabel)),
                const SizedBox(height: 16),
                TextField(controller: nameCtrl, decoration: InputDecoration(labelText: l10n.displayName)),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: tag,
                  items: const [
                    DropdownMenuItem(value: 'chat', child: Text('Chat')),
                    DropdownMenuItem(value: 'image', child: Text('Image')),
                    DropdownMenuItem(value: 'multimodal', child: Text('Multimodal')),
                  ],
                  onChanged: (v) => setDialogState(() => tag = v!),
                  decoration: InputDecoration(labelText: l10n.tag),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: feeGroupId,
                  items: [
                     DropdownMenuItem(value: null, child: Text(l10n.noFeeGroup, style: const TextStyle(color: Colors.grey))),
                    ...appState.allFeeGroups.map((g) => DropdownMenuItem(
                      value: g['id'] as int, 
                      child: Text(g['name']),
                    )),
                  ],
                  onChanged: (v) => setDialogState(() => feeGroupId = v),
                  decoration: InputDecoration(labelText: l10n.feeGroup),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
            ElevatedButton(
              onPressed: channelId == null ? null : () async {
                final channel = appState.allChannels.firstWhere((c) => c['id'] == channelId);
                final data = {
                  'model_id': idCtrl.text,
                  'model_name': nameCtrl.text,
                  'type': channel['type'].contains('google') ? 'google-genai' : 'openai-api',
                  'tag': tag,
                  'is_paid': 1, // Simplified, derived from channel if needed
                  'fee_group_id': feeGroupId,
                  'channel_id': channelId,
                };
                
                if (model == null) {
                  data['sort_order'] = appState.allModels.length;
                  await appState.addModel(data);
                } else {
                  await appState.updateModel(model['id'], data);
                }
                
                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
              child: Text(model == null ? l10n.add : l10n.save),
            ),
          ],
        ),
      ),
    );
  }

  void _showDiscoveryDialog(AppLocalizations l10n, Map<String, dynamic> channel, AppState appState) async {
    final type = channel['type'].contains('google') ? 'google-genai' : 'openai-api';
    
    final config = LLMModelConfig(
      modelId: 'discovery',
      type: type,
      channelType: channel['type'],
      endpoint: channel['endpoint'],
      apiKey: channel['api_key'],
    );

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DiscoveryDialog(
        channel: channel,
        config: config,
        appState: appState,
        l10n: l10n,
      ),
    );
  }
}

class _DiscoveryDialog extends StatefulWidget {
  final Map<String, dynamic> channel;
  final LLMModelConfig config;
  final AppState appState;
  final AppLocalizations l10n;

  const _DiscoveryDialog({
    required this.channel,
    required this.config,
    required this.appState,
    required this.l10n,
  });

  @override
  State<_DiscoveryDialog> createState() => _DiscoveryDialogState();
}

class _DiscoveryDialogState extends State<_DiscoveryDialog> {
  bool _isLoading = true;
  String? _error;
  List<DiscoveredModel> _discovered = [];
  List<DiscoveredModel> _filtered = [];
  final Set<String> _selectedIds = {};
  final TextEditingController _filterCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetch();
    _filterCtrl.addListener(_onFilterChanged);
  }

  @override
  void dispose() {
    _filterCtrl.dispose();
    super.dispose();
  }

  void _onFilterChanged() {
    final query = _filterCtrl.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filtered = List.from(_discovered);
      } else {
        _filtered = _discovered.where((m) => 
          m.displayName.toLowerCase().contains(query) || 
          m.modelId.toLowerCase().contains(query)
        ).toList();
      }
    });
  }

  Future<void> _fetch() async {
    try {
      final models = await ModelDiscoveryService().discoverModels(widget.config.type, widget.config);
      if (mounted) {
        setState(() {
          _discovered = models;
          _filtered = List.from(models);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final colorScheme = Theme.of(context).colorScheme;

    Widget content;
    if (_isLoading) {
      content = const Center(child: Padding(
        padding: EdgeInsets.all(32.0),
        child: CircularProgressIndicator(),
      ));
    } else if (_error != null) {
      content = Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: colorScheme.error, size: 48),
            const SizedBox(height: 16),
            Text(l10n.fetchFailed(_error!)),
          ],
        ),
      );
    } else if (_discovered.isEmpty) {
      content = Padding(
        padding: const EdgeInsets.all(32.0),
        child: Text(l10n.noNewModelsFound),
      );
    } else {
      content = SizedBox(
        width: 500,
        height: 450,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _filterCtrl,
                decoration: InputDecoration(
                  hintText: l10n.filterModels,
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _filtered.length,
                itemBuilder: (context, index) {
                  final m = _filtered[index];
                  final bool isAdded = widget.appState.allModels.any((em) => 
                      em['model_id'] == m.modelId && 
                      em['channel_id'] == widget.channel['id']
                  );
                  
                  return CheckboxListTile(
                    title: Text(m.displayName),
                    subtitle: Text(m.modelId, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                    value: isAdded || _selectedIds.contains(m.modelId),
                    onChanged: isAdded ? null : (val) {
                      setState(() {
                        if (val == true) {
                          _selectedIds.add(m.modelId);
                        } else {
                          _selectedIds.remove(m.modelId);
                        }
                      });
                    },
                    secondary: isAdded ? Text(l10n.alreadyAdded, style: TextStyle(color: colorScheme.outline, fontSize: 10)) : null,
                  );
                },
              ),
            ),
          ],
        ),
      );
    }

    return AlertDialog(
      title: Text(_isLoading ? l10n.discoveringModels : l10n.selectModelsToAdd),
      content: content,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        if (!_isLoading && _error == null && _discovered.isNotEmpty)
          ElevatedButton(
            onPressed: _selectedIds.isEmpty ? null : () async {
              for (var id in _selectedIds) {
                final m = _discovered.firstWhere((dm) => dm.modelId == id);
                await widget.appState.addModel({
                  'model_id': m.modelId,
                  'model_name': m.displayName,
                  'type': widget.config.type,
                  'tag': _inferTag(m),
                  'is_paid': 1,
                  'sort_order': widget.appState.allModels.length,
                  'channel_id': widget.channel['id'],
                });
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(l10n.addSelected(_selectedIds.length)),
          ),
      ],
    );
  }

  String _inferTag(DiscoveredModel m) {
    final id = m.modelId.toLowerCase();
    if (id.contains('vision') || id.contains('image')) return 'multimodal';
    if (id.contains('gemini')) return 'multimodal'; 
    return 'chat';
  }
}