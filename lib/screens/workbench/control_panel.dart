import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/database_service.dart';
import '../../services/llm/llm_models.dart';
import '../../services/llm/llm_service.dart';
import '../../state/app_state.dart';

class ControlPanelWidget extends StatefulWidget {
  const ControlPanelWidget({super.key});

  @override
  State<ControlPanelWidget> createState() => _ControlPanelWidgetState();
}

class _ControlPanelWidgetState extends State<ControlPanelWidget> {
  final TextEditingController _promptController = TextEditingController();
  final DatabaseService _db = DatabaseService();
  
  List<Map<String, dynamic>> _availableModels = [];
  String? _selectedModelId;
  String _aspectRatio = "not_set";
  String _resolution = "1K";

  Map<String, List<Map<String, dynamic>>> _groupedPrompts = {};

  @override
  void initState() {
    super.initState();
    _loadModels();
    _loadPrompts();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appState = Provider.of<AppState>(context, listen: false);
      setState(() {
        _selectedModelId = appState.lastSelectedModelId;
        _aspectRatio = appState.lastAspectRatio;
        _resolution = appState.lastResolution;
        _promptController.text = appState.lastPrompt;
      });
    });
  }

  Future<void> _loadModels() async {
    final allModels = await _db.getModels();
    final filtered = allModels.where((m) => 
      m['tag'] == 'image' || m['tag'] == 'multimodal'
    ).toList();
    
    setState(() {
      _availableModels = filtered;
      if (filtered.isNotEmpty && _selectedModelId == null) {
        _selectedModelId = filtered.first['model_id'];
      }
    });
  }

  Future<void> _loadPrompts() async {
    final prompts = await _db.getPrompts();
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var p in prompts) {
      final tag = p['tag'] as String;
      grouped[tag] ??= [];
      grouped[tag]!.add(p);
    }
    setState(() => _groupedPrompts = grouped);
  }

  void _updateConfig({String? modelId, String? ar, String? res, String? prompt}) {
    final appState = Provider.of<AppState>(context, listen: false);
    appState.updateWorkbenchConfig(
      modelId: modelId,
      aspectRatio: ar,
      resolution: res,
      prompt: prompt,
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final colorScheme = Theme.of(context).colorScheme;
    
    return Container(
      width: 350,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSelectionPreview(appState, colorScheme),
          const Divider(height: 32),
          
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Model Selection', style: TextStyle(fontWeight: FontWeight.bold)),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: _selectedModelId,
                    hint: const Text('Select a model'),
                    items: _availableModels.map((m) => DropdownMenuItem(
                      value: m['model_id'] as String,
                      child: Text(m['model_name']),
                    )).toList(),
                    onChanged: (val) {
                      setState(() => _selectedModelId = val);
                      _updateConfig(modelId: val);
                    },
                  ),
                  
                  if (_selectedModelId != null) ...[
                    const SizedBox(height: 16),
                    _buildModelSpecificOptions(_selectedModelId!),
                  ],

                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Prompt', style: TextStyle(fontWeight: FontWeight.bold)),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () => _showRefinerDialog(appState),
                            icon: const Icon(Icons.auto_fix_high, size: 16),
                            label: const Text('Refiner', style: TextStyle(fontSize: 12)),
                          ),
                          _buildPromptPicker(colorScheme),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _promptController,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Enter prompt here...',
                      alignLabelWithHint: true,
                    ),
                    onChanged: (v) => _updateConfig(prompt: v),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: ['Cyberpunk', 'Anime', 'Realistic'].map((tag) => ActionChip(
                      label: Text(tag, style: const TextStyle(fontSize: 12)),
                      onPressed: () {
                        final currentText = _promptController.text;
                        final newText = currentText.isEmpty ? tag : '$currentText, $tag';
                        _promptController.text = newText;
                        _updateConfig(prompt: newText);
                      },
                    )).toList(),
                  ),
                ],
              ),
            ),
          ),
          
          const Divider(),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () => _showQueueSettings(context, appState),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: (appState.selectedImages.isEmpty || _selectedModelId == null) 
                      ? null 
                      : () {
                          appState.submitTask(_selectedModelId!, {
                            'prompt': _promptController.text,
                            'aspectRatio': _aspectRatio,
                            'imageSize': _resolution,
                          });
                        },
                  icon: const Icon(Icons.play_arrow),
                  label: Text('Process ${appState.selectedImages.length} Images'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showRefinerDialog(AppState appState) async {
    final allModels = await _db.getModels();
    final refinerModels = allModels.where((m) => m['tag'] == 'chat' || m['tag'] == 'multimodal').toList();
    final refinerPrompts = (await _db.getPrompts()).where((p) => p['tag'] == 'Refiner').toList();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => _RefinerDialog(
        initialPrompt: _promptController.text,
        models: refinerModels,
        sysPrompts: refinerPrompts,
        selectedImages: appState.selectedImages,
        onApply: (refined) {
          _promptController.text = refined;
          _updateConfig(prompt: refined);
        },
      ),
    );
  }

  Widget _buildPromptPicker(ColorScheme colorScheme) {
    return TextButton.icon(
      onPressed: _groupedPrompts.isEmpty ? null : () => _showPromptPickerMenu(),
      icon: const Icon(Icons.library_books_outlined, size: 16),
      label: const Text('Library', style: TextStyle(fontSize: 12)),
      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
    );
  }

  void _showPromptPickerMenu() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select from Library'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _groupedPrompts.entries.map((group) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(
                        group.key.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                    ...group.value.map((p) => ListTile(
                      title: Text(p['title'], style: const TextStyle(fontSize: 14)),
                      subtitle: Text(p['content'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                      onTap: () {
                        _promptController.text = p['content'];
                        _updateConfig(prompt: p['content']);
                        Navigator.pop(context);
                      },
                      dense: true,
                    )),
                    const Divider(),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  Widget _buildModelSpecificOptions(String modelId) {
    if (modelId.contains('image') || modelId.contains('pro')) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Aspect Ratio', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          DropdownButton<String>(
            isExpanded: true,
            value: _aspectRatio,
            items: ["not_set", "1:1", "2:3", "3:2", "3:4", "4:3", "4:5", "5:4", "9:16", "16:9"]
                .map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
            onChanged: (v) {
              setState(() => _aspectRatio = v!);
              _updateConfig(ar: v);
            },
          ),
          const SizedBox(height: 8),
          const Text('Resolution', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          SegmentedButton<String>(
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
        ],
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildSelectionPreview(AppState appState, ColorScheme colorScheme) {
    if (appState.selectedImages.isEmpty) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.collections_outlined, size: 48, color: colorScheme.outline),
              const SizedBox(height: 8),
              Text('No images selected', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12)),
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
              'Selected (${appState.selectedImages.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            TextButton(
              onPressed: appState.clearImageSelection,
              child: const Text('Clear', style: TextStyle(fontSize: 12)),
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

  void _showQueueSettings(BuildContext context, AppState appState) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Queue Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Concurrency Limit: ${appState.concurrencyLimit}'),
            Slider(
              value: appState.concurrencyLimit.toDouble(),
              min: 1,
              max: 8,
              divisions: 7,
              onChanged: (v) => appState.setConcurrency(v.toInt()),
            ),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }
}

class _RefinerDialog extends StatefulWidget {
  final String initialPrompt;
  final List<Map<String, dynamic>> models;
  final List<Map<String, dynamic>> sysPrompts;
  final List<File> selectedImages;
  final Function(String) onApply;

  const _RefinerDialog({
    required this.initialPrompt,
    required this.models,
    required this.sysPrompts,
    required this.selectedImages,
    required this.onApply,
  });

  @override
  State<_RefinerDialog> createState() => _RefinerDialogState();
}

class _RefinerDialogState extends State<_RefinerDialog> {
  late TextEditingController _currentPromptCtrl;
  final TextEditingController _refinedPromptCtrl = TextEditingController();
  String? _selectedModelId;
  String? _selectedSysPrompt;
  bool _isRefining = false;

  @override
  void initState() {
    super.initState();
    _currentPromptCtrl = TextEditingController(text: widget.initialPrompt);
    if (widget.models.isNotEmpty) _selectedModelId = widget.models.first['model_id'];
    if (widget.sysPrompts.isNotEmpty) _selectedSysPrompt = widget.sysPrompts.first['content'];
  }

  Future<void> _refine() async {
    if (_selectedModelId == null) return;

    setState(() {
      _isRefining = true;
      _refinedPromptCtrl.clear();
    });

    try {
      final db = DatabaseService();
      final modelInfo = widget.models.firstWhere((m) => m['model_id'] == _selectedModelId);
      final inputPrice = modelInfo['input_fee'] ?? 0.0;
      final outputPrice = modelInfo['output_fee'] ?? 0.0;

      final attachments = widget.selectedImages.map((f) => 
        LLMAttachment.fromFile(f, 'image/jpeg')
      ).toList();

      final stream = LLMService().requestStream(
        modelId: _selectedModelId!,
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
      Map<String, dynamic>? finalMetadata;

      await for (final chunk in stream) {
        if (chunk.textPart != null) {
          accumulatedText += chunk.textPart!;
          setState(() {
            _refinedPromptCtrl.text = accumulatedText;
          });
        }
        if (chunk.metadata != null) {
          finalMetadata = chunk.metadata;
        }
      }

      // Record Token Usage for Refiner Task
      if (finalMetadata != null) {
        final inputTokens = finalMetadata['promptTokenCount'] ?? finalMetadata['prompt_tokens'] ?? 0;
        final outputTokens = finalMetadata['candidatesTokenCount'] ?? finalMetadata['completion_tokens'] ?? 0;
        
        await db.recordTokenUsage({
          'task_id': 'refine_${DateTime.now().millisecondsSinceEpoch}',
          'model_id': _selectedModelId!,
          'timestamp': DateTime.now().toIso8601String(),
          'input_tokens': inputTokens,
          'output_tokens': outputTokens,
          'input_price': inputPrice,
          'output_price': outputPrice,
        });
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Refine failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isRefining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('AI Prompt Refiner'),
      content: SizedBox(
        width: 800,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedModelId,
                    decoration: const InputDecoration(labelText: 'Refiner Model', border: OutlineInputBorder()),
                    items: widget.models.map((m) => DropdownMenuItem(value: m['model_id'] as String, child: Text(m['model_name']))).toList(),
                    onChanged: (v) => setState(() => _selectedModelId = v),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedSysPrompt,
                    decoration: const InputDecoration(labelText: 'System Prompt', border: OutlineInputBorder()),
                    items: widget.sysPrompts.map((p) => DropdownMenuItem(value: p['content'] as String, child: Text(p['title']))).toList(),
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
                      const Text('Current Prompt', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
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
                      const Text('Refined Prompt', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _refinedPromptCtrl,
                        maxLines: 10,
                        readOnly: true,
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          fillColor: Colors.grey.withOpacity(0.05),
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
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton.icon(
          onPressed: _isRefining ? null : _refine,
          icon: _isRefining 
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.auto_fix_high),
          label: const Text('Refine'),
        ),
        FilledButton(
          onPressed: _refinedPromptCtrl.text.isEmpty ? null : () {
            widget.onApply(_refinedPromptCtrl.text);
            Navigator.pop(context);
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
