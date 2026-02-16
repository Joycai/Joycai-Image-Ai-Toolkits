import 'package:flutter/material.dart';

import '../../core/responsive.dart';
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

  void _toggleSelectAll() {
    final available = _filtered.where((m) => !_isModelAdded(m)).toList();
    setState(() {
      if (_selectedIds.length == available.length) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(available.map((m) => m.modelId));
      }
    });
  }

  bool _isModelAdded(DiscoveredModel m) {
    return widget.appState.allModels.any((em) => 
      em.modelId == m.modelId && em.channelId == widget.channel.id
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final isMobile = Responsive.isMobile(context);

    if (isMobile) {
      return Scaffold(
        appBar: AppBar(
          title: Text(l10n.fetchModels),
          leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(60),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _buildSearchBar(l10n),
            ),
          ),
        ),
        body: _buildMainContent(l10n),
        bottomNavigationBar: _isLoading || _error != null || _discovered.isEmpty 
          ? null 
          : _buildMobileBottomBar(l10n),
      );
    }

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.auto_awesome_outlined, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Text(l10n.selectModelsToAdd),
        ],
      ),
      contentPadding: EdgeInsets.zero,
      content: SizedBox(
        width: 600,
        height: 600,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: _buildSearchBar(l10n),
            ),
            Expanded(child: _buildMainContent(l10n)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        if (!_isLoading && _error == null && _discovered.isNotEmpty)
          FilledButton.icon(
            onPressed: _selectedIds.isEmpty ? null : _handleAddSelected,
            icon: const Icon(Icons.add, size: 18),
            label: Text(l10n.addSelected(_selectedIds.length)),
          ),
      ],
    );
  }

  Widget _buildSearchBar(AppLocalizations l10n) {
    return TextField(
      controller: _filterCtrl,
      decoration: InputDecoration(
        hintText: l10n.searchModels,
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: _filterCtrl.text.isNotEmpty 
          ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => _filterCtrl.clear()) 
          : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(80),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }

  Widget _buildMainContent(AppLocalizations l10n) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(l10n.discoveringModels, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          ],
        ),
      );
    }

    if (_error != null) {
      return _buildStateView(
        icon: Icons.error_outline,
        color: Theme.of(context).colorScheme.error,
        title: "Connection Failed",
        subtitle: l10n.fetchFailed(_error!),
        action: FilledButton(onPressed: () {
          setState(() { _isLoading = true; _error = null; });
          _fetch();
        }, child: const Text("Retry")),
      );
    }

    if (_discovered.isEmpty) {
      return _buildStateView(
        icon: Icons.search_off_outlined,
        color: Theme.of(context).colorScheme.outline,
        title: "No Models Found",
        subtitle: l10n.noNewModelsFound,
      );
    }

    final available = _filtered.where((m) => !_isModelAdded(m)).toList();

    return Column(
      children: [
        if (_filtered.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              children: [
                Text(l10n.modelsDiscovered(_filtered.length), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (available.isNotEmpty)
                  TextButton.icon(
                    onPressed: _toggleSelectAll,
                    icon: Icon(_selectedIds.length == available.length ? Icons.deselect : Icons.select_all, size: 16),
                    label: Text(_selectedIds.length == available.length ? l10n.deselectAll : l10n.selectAll, style: const TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: _filtered.length,
            itemBuilder: (context, index) {
              final m = _filtered[index];
              final bool isAdded = _isModelAdded(m);
              final bool isSelected = _selectedIds.contains(m.modelId);
              
              return _buildModelCard(m, isAdded, isSelected);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildModelCard(DiscoveredModel m, bool isAdded, bool isSelected) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected 
            ? colorScheme.primary 
            : colorScheme.outlineVariant.withAlpha(100),
          width: isSelected ? 2 : 1,
        ),
      ),
      color: isSelected ? colorScheme.primaryContainer.withAlpha(30) : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: isAdded ? null : () {
          setState(() {
            if (isSelected) {
              _selectedIds.remove(m.modelId);
            } else {
              _selectedIds.add(m.modelId);
            }
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              if (!isAdded)
                Checkbox(
                  value: isSelected, 
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selectedIds.add(m.modelId);
                      } else {
                        _selectedIds.remove(m.modelId);
                      }
                    });
                  },
                )
              else
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(Icons.check_circle, color: Colors.green, size: 20),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.displayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Text(m.modelId, style: TextStyle(fontSize: 11, color: colorScheme.outline)),
                  ],
                ),
              ),
              if (isAdded)
                Text(widget.l10n.alreadyAdded, style: TextStyle(color: colorScheme.outline, fontSize: 10, fontWeight: FontWeight.bold))
              else
                _buildTagChip(_inferTag(m)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTagChip(String tag) {
    Color color;
    switch (tag.toLowerCase()) {
      case 'image': color = Colors.purple; break;
      case 'multimodal': color = Colors.orange; break;
      case 'chat': color = Colors.green; break;
      default: color = Colors.blue;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(tag.toUpperCase(), style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildStateView({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: color.withAlpha(150)),
            const SizedBox(height: 24),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 13)),
            if (action != null) ...[
              const SizedBox(height: 24),
              action,
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMobileBottomBar(AppLocalizations l10n) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: FilledButton.icon(
          onPressed: _selectedIds.isEmpty ? null : _handleAddSelected,
          icon: const Icon(Icons.add),
          label: Text(l10n.addSelected(_selectedIds.length)),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ),
    );
  }

  Future<void> _handleAddSelected() async {
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
    if (mounted) Navigator.pop(context);
  }

  String _inferTag(DiscoveredModel m) {
    final id = m.modelId.toLowerCase();
    if (id.contains('vision') || id.contains('image')) return 'multimodal';
    if (id.contains('gemini')) return 'multimodal'; 
    return 'chat';
  }
}
