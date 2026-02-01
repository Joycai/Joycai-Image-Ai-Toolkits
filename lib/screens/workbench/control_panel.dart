import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';
import '../../services/database_service.dart';

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
    
    // Initialize controllers and state from AppState
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
                      _buildPromptPicker(colorScheme),
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
              _updateConfig(aspectRatio: v);
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
              _updateConfig(resolution: v.first);
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
