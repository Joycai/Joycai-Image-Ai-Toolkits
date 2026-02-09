import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/llm_channel.dart';
import '../../services/llm/llm_models.dart';
import '../../services/llm/model_discovery_service.dart';
import '../../state/app_state.dart';

class DiscoveryDialog extends StatefulWidget {
  final LLMChannel channel;
  final LLMModelConfig config;
  final AppState appState;
  final AppLocalizations l10n;

  const DiscoveryDialog({
    super.key,
    required this.channel,
    required this.config,
    required this.appState,
    required this.l10n,
  });

  @override
  State<DiscoveryDialog> createState() => _DiscoveryDialogState();
}

class _DiscoveryDialogState extends State<DiscoveryDialog> {
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
                      em.modelId == m.modelId && 
                      em.channelId == widget.channel.id
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
                  'channel_id': widget.channel.id,
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