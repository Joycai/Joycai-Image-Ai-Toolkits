import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/database_service.dart';
import '../../services/llm/llm_models.dart';
import '../../services/llm/llm_service.dart';
import '../../services/task_queue_service.dart';
import '../../state/app_state.dart';

class ControlPanelWidget extends StatefulWidget {
  const ControlPanelWidget({super.key});

  @override
  State<ControlPanelWidget> createState() => _ControlPanelWidgetState();
}

class _ControlPanelWidgetState extends State<ControlPanelWidget> {
  final TextEditingController _promptController = TextEditingController();
  final TextEditingController _prefixController = TextEditingController();
  final DatabaseService _db = DatabaseService();
  
  List<Map<String, dynamic>> _availableModels = [];
  List<Map<String, dynamic>> _channels = [];
  int? _selectedChannelId;
  int? _selectedModelPk;
  String _aspectRatio = "not_set";
  String _resolution = "1K";
  bool _isModelSettingsExpanded = false;

  Map<String, List<Map<String, dynamic>>> _groupedPrompts = {};
  late AppState _appState;

  @override
  void initState() {
    super.initState();
    _loadModels();
    _loadPrompts();
    
    // Listen to AppState changes for external updates (e.g. import, reset)
    _appState = Provider.of<AppState>(context, listen: false);
    _appState.addListener(_onAppStateChanged);
    
    // Initial sync
    _syncWithState();
  }

  @override
  void dispose() {
    _appState.removeListener(_onAppStateChanged);
    _promptController.dispose();
    _prefixController.dispose();
    super.dispose();
  }

  void _onAppStateChanged() {
    if (!mounted) return;
    _syncWithState();
  }

  void _syncWithState() {
    final appState = Provider.of<AppState>(context, listen: false);
    if (!appState.settingsLoaded) return;

    bool changed = false;

    if (_promptController.text != appState.lastPrompt) {
      _promptController.text = appState.lastPrompt;
      changed = true;
    }

    if (_prefixController.text != appState.imagePrefix) {
      _prefixController.text = appState.imagePrefix;
      changed = true;
    }

    if (_aspectRatio != appState.lastAspectRatio) {
      _aspectRatio = appState.lastAspectRatio;
      changed = true;
    }

    if (_resolution != appState.lastResolution) {
      _resolution = appState.lastResolution;
      changed = true;
    }

    // Sync model selection
    if (_availableModels.isNotEmpty) {
      final savedModelId = appState.lastSelectedModelId;
      // Try match by PK first (int string), then by model_id string
      final match = _availableModels.firstWhere(
        (m) => m['id'].toString() == savedModelId || m['model_id'] == savedModelId,
        orElse: () => {},
      );
      
      if (match.isNotEmpty && _selectedModelPk != match['id']) {
        _selectedModelPk = match['id'] as int;
        _selectedChannelId = match['channel_id'] as int?;
        changed = true;
      }
    }

    if (changed) {
      setState(() {});
    }
  }

  Future<void> _loadModels() async {
    final allModels = await _db.getModels();
    final channels = await _db.getChannels();
    
    final filtered = allModels.where((m) => 
      m['tag'] == 'image' || m['tag'] == 'multimodal'
    ).toList();
    
    setState(() {
      _availableModels = filtered;
      _channels = channels;
      
      // Validate currently selected model and channel
      if (_selectedModelPk != null) {
        final currentModel = filtered.cast<Map<String, dynamic>?>().firstWhere(
          (m) => m?['id'] == _selectedModelPk,
          orElse: () => null,
        );
        if (currentModel == null) {
          _selectedModelPk = null;
        } else {
          _selectedChannelId = currentModel['channel_id'] as int?;
        }
      }

      if (filtered.isNotEmpty && _selectedModelPk == null) {
        final first = filtered.first;
        _selectedModelPk = first['id'] as int;
        _selectedChannelId = first['channel_id'] as int?;
      }
    });
  }

  Future<void> _loadPrompts() async {
    final prompts = await _db.getPrompts();
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var p in prompts) {
      final tag = p['tag'] as String;
      if (tag == 'Refiner') continue;
      
      grouped[tag] ??= [];
      grouped[tag]!.add(p);
    }
    setState(() => _groupedPrompts = grouped);
  }

  void _updateConfig({int? modelPk, String? modelIdStr, String? ar, String? res, String? prompt}) {
    final appState = Provider.of<AppState>(context, listen: false);
    
    String? idToSave;
    if (modelPk != null) {
      idToSave = modelPk.toString(); // Save PK as string
    }

    appState.updateWorkbenchConfig(
      modelId: idToSave ?? modelIdStr,
      aspectRatio: ar,
      resolution: res,
      prompt: prompt,
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    final filteredModels = _availableModels.where((m) => m['channel_id'] == _selectedChannelId).toList();
    
    return Container(
      width: 350,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSelectionPreview(appState, colorScheme, l10n),
          const Divider(height: 32),
          
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Custom Collapsible Header
                  InkWell(
                    onTap: () => setState(() => _isModelSettingsExpanded = !_isModelSettingsExpanded),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        children: [
                          Icon(
                            _isModelSettingsExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                            size: 20,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l10n.modelSelection, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                if (!_isModelSettingsExpanded && _selectedModelPk != null)
                                  Text(
                                    _availableModels.firstWhere((m) => m['id'] == _selectedModelPk)['model_name'],
                                    style: TextStyle(fontSize: 11, color: colorScheme.outline),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Collapsible Content
                  if (_isModelSettingsExpanded) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l10n.channel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                              _buildChannelDropdown(colorScheme, l10n),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l10n.modelSelection, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                              DropdownButton<int>(
                                isExpanded: true,
                                value: (filteredModels.any((m) => m['id'] == _selectedModelPk)) 
                                    ? _selectedModelPk 
                                    : null,
                                hint: Text(l10n.selectAModel),
                                style: TextStyle(fontSize: 12, color: colorScheme.onSurface),
                                underline: Container(height: 1, color: colorScheme.outlineVariant),
                                items: filteredModels.map((m) => DropdownMenuItem(
                                  value: m['id'] as int,
                                  child: Text(m['model_name']),
                                )).toList(),
                                onChanged: (val) {
                                  setState(() => _selectedModelPk = val);
                                  _updateConfig(modelPk: val);
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_selectedModelPk != null)
                      Builder(
                        builder: (context) {
                          final model = _availableModels.firstWhere((m) => m['id'] == _selectedModelPk, orElse: () => {});
                          if (model.isNotEmpty) {
                            return _buildModelSpecificOptions(model['model_id'] as String, l10n);
                          }
                          return const SizedBox.shrink();
                        }
                      ),
                  ],

                  const Divider(height: 24),
                  
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(l10n.prompt, style: const TextStyle(fontWeight: FontWeight.bold)),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton.icon(
                            onPressed: () => _showRefinerDialog(appState, l10n),
                            icon: const Icon(Icons.auto_fix_high, size: 14),
                            label: Text(l10n.refiner, style: const TextStyle(fontSize: 11)),
                            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                          ),
                          _buildPromptPicker(colorScheme, l10n),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _promptController,
                    maxLines: 15,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: l10n.promptHint,
                      alignLabelWithHint: true,
                    ),
                    onChanged: (v) => _updateConfig(prompt: v),
                  ),
                  const SizedBox(height: 8),

                ],
              ),
            ),
          ),
          
          const Divider(),
          _buildQueueStatus(appState, colorScheme, l10n),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () => _showQueueSettings(context, l10n),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: (_promptController.text.isEmpty || _selectedModelPk == null) 
                      ? null 
                      : () {
                          final selectedModel = _availableModels.firstWhere((m) => m['id'] == _selectedModelPk);
                          final modelName = selectedModel['model_name'] as String;
                          
                          appState.submitTask(_selectedModelPk!, {
                            'prompt': _promptController.text,
                            'aspectRatio': _aspectRatio,
                            'imageSize': _resolution,
                          }, modelIdDisplay: modelName);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(l10n.taskSubmitted),
                              duration: const Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                              width: 250,
                            ),
                          );
                        },
                  icon: const Icon(Icons.play_arrow),
                  label: Text(appState.selectedImages.isEmpty 
                      ? l10n.processPrompt 
                      : l10n.processImages(appState.selectedImages.length)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQueueStatus(AppState appState, ColorScheme colorScheme, AppLocalizations l10n) {
    final pendingCount = appState.taskQueue.queue.where((t) => t.status == TaskStatus.pending).length;
    final runningCount = appState.taskQueue.runningCount;

    if (pendingCount == 0 && runningCount == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withAlpha((255 * 0.5).round()),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (runningCount > 0) ...[
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text(l10n.runningCount(runningCount), style: TextStyle(fontSize: 11, color: colorScheme.onSecondaryContainer, fontWeight: FontWeight.bold)),
            const SizedBox(width: 12),
          ],
          Icon(Icons.layers_outlined, size: 14, color: colorScheme.onSecondaryContainer),
          const SizedBox(width: 4),
          Text(l10n.plannedCount(pendingCount), style: TextStyle(fontSize: 11, color: colorScheme.onSecondaryContainer)),
        ],
      ),
    );
  }

  Widget _buildChannelDropdown(ColorScheme colorScheme, AppLocalizations l10n) {
    return DropdownButton<int>(
      isExpanded: true,
      value: _selectedChannelId,
      style: TextStyle(fontSize: 12, color: colorScheme.onSurface),
      underline: Container(height: 1, color: colorScheme.outlineVariant),
      items: _channels.map((c) => DropdownMenuItem<int>(
        value: c['id'] as int,
        child: Row(
          children: [
            if (c['tag'] != null)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Color(c['tag_color'] ?? 0xFF607D8B).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  c['tag'],
                  style: TextStyle(
                    fontSize: 9, 
                    color: Color(c['tag_color'] ?? 0xFF607D8B),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            Expanded(child: Text(c['display_name'], overflow: TextOverflow.ellipsis)),
          ],
        ),
      )).toList(),
      onChanged: (val) {
        setState(() {
          _selectedChannelId = val;
          final firstInChannel = _availableModels.cast<Map<String, dynamic>?>().firstWhere(
            (m) => m != null && m['channel_id'] == val,
            orElse: () => null,
          );
          _selectedModelPk = firstInChannel?['id'] as int?;
          if (_selectedModelPk != null) {
            _updateConfig(modelPk: _selectedModelPk);
          }
        });
      },
    );
  }

  void _showRefinerDialog(AppState appState, AppLocalizations l10n) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (context) => _RefinerDialog(
        initialPrompt: _promptController.text,
        selectedImages: appState.selectedImages,
        onApply: (refined) {
          _promptController.text = refined;
          _updateConfig(prompt: refined);
        },
      ),
    );
  }

  Widget _buildPromptPicker(ColorScheme colorScheme, AppLocalizations l10n) {
    return TextButton.icon(
      onPressed: _groupedPrompts.isEmpty ? null : () => _showPromptPickerMenu(l10n),
      icon: const Icon(Icons.library_books_outlined, size: 16),
      label: Text(l10n.library, style: const TextStyle(fontSize: 12)),
      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
    );
  }

  void _showPromptPickerMenu(AppLocalizations l10n) {
    showDialog(
      context: context,
      builder: (context) => _LibraryDialog(
        groupedPrompts: _groupedPrompts,
        onSelect: (prompt) {
          _promptController.text = prompt;
          _updateConfig(prompt: prompt);
        },
      ),
    );
  }

  Widget _buildModelSpecificOptions(String modelId, AppLocalizations l10n) {
    if (modelId.contains('image') || modelId.contains('pro')) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Column(
          children: [
            Row(
              children: [
                SizedBox(
                  width: 80,
                  child: Text(l10n.aspectRatio, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _aspectRatio,
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface),
                    underline: Container(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
                    items: ["not_set", "1:1", "2:3", "3:2", "3:4", "4:3", "4:5", "5:4", "9:16", "16:9"]
                        .map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (v) {
                      setState(() => _aspectRatio = v!);
                      _updateConfig(ar: v);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(
                  width: 80,
                  child: Text(l10n.resolution, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: SegmentedButton<String>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(fontSize: 10),
                    ),
                    segments: const [
                      ButtonSegment(value: '1K', label: Text('1K')),
                      ButtonSegment(value: '2K', label: Text('2K')),
                      ButtonSegment(value: '4K', label: Text('4K')),
                    ],
                    selected: {_resolution},
                    onSelectionChanged: (v) {
                      setState(() => _resolution = v.first);
                      _updateConfig(res: v.first);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildSelectionPreview(AppState appState, ColorScheme colorScheme, AppLocalizations l10n) {
    if (appState.selectedImages.isEmpty) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withAlpha((255 * 0.3).round()),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.collections_outlined, size: 48, color: colorScheme.outline),
              const SizedBox(height: 8),
              Text(l10n.noImagesSelected, style: TextStyle(color: colorScheme.onSurface, fontSize: 12)),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              l10n.selectedCount(appState.selectedImages.length),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            TextButton(
              onPressed: appState.clearImageSelection,
              child: Text(l10n.clear, style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: appState.selectedImages.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final image = appState.selectedImages[index];
              return Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      image,
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                      cacheWidth: 200,
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => appState.toggleImageSelection(image),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                        child: const Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  void _showQueueSettings(BuildContext context, AppLocalizations l10n) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final appState = Provider.of<AppState>(context);
          return AlertDialog(
            title: Text(l10n.queueSettings),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.concurrencyLimit(appState.concurrencyLimit)),
                Slider(
                  value: appState.concurrencyLimit.toDouble(),
                  min: 1,
                  max: 8,
                  divisions: 7,
                  onChanged: (v) {
                    appState.setConcurrency(v.toInt());
                    setDialogState(() {});
                  },
                ),
                const Divider(),
                const SizedBox(height: 8),
                Text(l10n.filenamePrefix, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                TextField(
                  controller: _prefixController,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    hintText: 'e.g. result',
                  ),
                  onChanged: (v) => appState.setImagePrefix(v),
                ),
              ],
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.close))],
          );
        },
      ),
    );
  }
}

class _RefinerDialog extends StatefulWidget {
  final String initialPrompt;
  final List<File> selectedImages;
  final Function(String) onApply;

  const _RefinerDialog({
    required this.initialPrompt,
    required this.selectedImages,
    required this.onApply,
  });

  @override
  State<_RefinerDialog> createState() => _RefinerDialogState();
}

class _RefinerDialogState extends State<_RefinerDialog> {
  final DatabaseService _db = DatabaseService();
  late TextEditingController _currentPromptCtrl;
  final TextEditingController _refinedPromptCtrl = TextEditingController();
  
  List<Map<String, dynamic>> _models = [];
  List<Map<String, dynamic>> _channels = [];
  List<Map<String, dynamic>> _sysPrompts = [];
  
  int? _selectedModelPk;
  String? _selectedSysPrompt;
  bool _isRefining = false;
  bool _isLoadingData = true;

  @override
  void initState() {
    super.initState();
    _currentPromptCtrl = TextEditingController(text: widget.initialPrompt);
    _loadData();
  }

  Future<void> _loadData() async {
    final allModels = await _db.getModels();
    final channels = await _db.getChannels();
    final refinerModels = allModels.where((m) => m['tag'] == 'chat' || m['tag'] == 'multimodal').toList();
    final refinerPrompts = (await _db.getPrompts()).where((p) => p['tag'] == 'Refiner').toList();

    if (mounted) {
      setState(() {
        _models = refinerModels;
        _channels = channels;
        _sysPrompts = refinerPrompts;
        if (_models.isNotEmpty) _selectedModelPk = _models.first['id'] as int;
        if (_sysPrompts.isNotEmpty) _selectedSysPrompt = _sysPrompts.first['content'];
        _isLoadingData = false;
      });
    }
  }

  Future<void> _refine() async {
    if (_selectedModelPk == null) return;
    final l10n = AppLocalizations.of(context)!;

    setState(() {
      _isRefining = true;
      _refinedPromptCtrl.clear();
    });

    try {
      final attachments = widget.selectedImages.map((f) => 
        LLMAttachment.fromFile(f, 'image/jpeg')
      ).toList();

      // Find the model ID string if needed, or just pass PK
      // LLMService now accepts dynamic modelIdentifier (String or int)
      
      final stream = LLMService().requestStream(
        modelIdentifier: _selectedModelPk!,
        messages: [
          if (_selectedSysPrompt != null)
            LLMMessage(role: LLMRole.system, content: _selectedSysPrompt!),
          LLMMessage(
            role: LLMRole.user, 
            content: _currentPromptCtrl.text,
            attachments: attachments,
          ),
        ],
      );

      String accumulatedText = "";

      await for (final chunk in stream) {
        if (chunk.textPart != null) {
          accumulatedText += chunk.textPart!;
          setState(() {
            _refinedPromptCtrl.text = accumulatedText;
          });
        }
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.refineFailed(e.toString()))));
      }
    } finally {
      if (mounted) setState(() => _isRefining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.aiPromptRefiner),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: _isLoadingData 
          ? const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))
          : Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _selectedModelPk,
                    decoration: InputDecoration(labelText: l10n.refinerModel, border: const OutlineInputBorder()),
                    items: _models.map((m) {
                      final channel = _channels.firstWhere((c) => c['id'] == m['channel_id'], orElse: () => {});
                      return DropdownMenuItem(
                        value: m['id'] as int,
                        child: Row(
                          children: [
                            if (channel.isNotEmpty && channel['tag'] != null)
                              Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Color(channel['tag_color'] ?? 0xFF607D8B).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  channel['tag'],
                                  style: TextStyle(
                                    fontSize: 9, 
                                    color: Color(channel['tag_color'] ?? 0xFF607D8B),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            Expanded(child: Text(m['model_name'], overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (v) => setState(() => _selectedModelPk = v),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedSysPrompt,
                    decoration: InputDecoration(labelText: l10n.systemPrompt, border: const OutlineInputBorder()),
                    items: _sysPrompts.map((p) => DropdownMenuItem(value: p['content'] as String, child: Text(p['title']))).toList(),
                    onChanged: (v) => setState(() => _selectedSysPrompt = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.currentPrompt, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _currentPromptCtrl,
                        maxLines: 10,
                        decoration: const InputDecoration(border: OutlineInputBorder()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                const Center(child: Icon(Icons.arrow_forward, color: Colors.grey)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.refinedPrompt, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _refinedPromptCtrl,
                        maxLines: 10,
                        readOnly: true,
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          fillColor: Colors.grey.withValues(alpha: 0.05),
                          filled: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton.icon(
          onPressed: _isRefining ? null : _refine,
          icon: _isRefining 
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.auto_fix_high),
          label: Text(l10n.refine),
        ),
        FilledButton(
          onPressed: _refinedPromptCtrl.text.isEmpty ? null : () {
            widget.onApply(_refinedPromptCtrl.text);
            Navigator.pop(context);
          },
          child: Text(l10n.apply),
        ),
      ],
    );
  }
}

class _LibraryDialog extends StatefulWidget {
  final Map<String, List<Map<String, dynamic>>> groupedPrompts;
  final Function(String) onSelect;

  const _LibraryDialog({
    required this.groupedPrompts,
    required this.onSelect,
  });

  @override
  State<_LibraryDialog> createState() => _LibraryDialogState();
}

class _LibraryDialogState extends State<_LibraryDialog> {
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    if (widget.groupedPrompts.isNotEmpty) {
      _selectedCategory = widget.groupedPrompts.keys.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final categories = widget.groupedPrompts.keys.toList();
    final currentPrompts = _selectedCategory != null 
        ? (widget.groupedPrompts[_selectedCategory] ?? []) 
        : <Map<String, dynamic>>[];

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 600),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(l10n.promptLibrary, style: Theme.of(context).textTheme.titleLarge),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left Pane: Categories
                  Container(
                    width: 200,
                    decoration: BoxDecoration(
                      border: Border(right: BorderSide(color: Theme.of(context).dividerColor)),
                      color: colorScheme.surfaceContainerLow,
                    ),
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: categories.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 4),
                      itemBuilder: (context, index) {
                        final cat = categories[index];
                        final isSelected = cat == _selectedCategory;
                        return ListTile(
                          title: Text(cat, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                          selected: isSelected,
                          selectedTileColor: colorScheme.secondaryContainer,
                          selectedColor: colorScheme.onSecondaryContainer,
                          onTap: () => setState(() => _selectedCategory = cat),
                          dense: true,
                        );
                      },
                    ),
                  ),
                  
                  // Right Pane: Prompts
                  Expanded(
                    child: currentPrompts.isEmpty 
                    ? Center(child: Text(l10n.noPromptsSaved)) 
                    : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 300,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.5,
                      ),
                      itemCount: currentPrompts.length,
                      itemBuilder: (context, index) {
                        final p = currentPrompts[index];
                        return Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: InkWell(
                            onTap: () {
                              widget.onSelect(p['content']);
                              Navigator.pop(context);
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p['title'],
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 8),
                                  Expanded(
                                    child: Text(
                                      p['content'],
                                      style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                      overflow: TextOverflow.fade,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
