import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../l10n/app_localizations.dart';
import '../../services/database_service.dart';
import '../../services/task_queue_service.dart';
import '../../state/app_state.dart';
import '../../widgets/dialogs/library_dialog.dart';
import '../../widgets/markdown_editor.dart';
import '../../widgets/refiner_panel.dart';
import 'model_selection_section.dart';

class ControlPanelWidget extends StatefulWidget {
  const ControlPanelWidget({super.key});

  @override
  State<ControlPanelWidget> createState() => _ControlPanelWidgetState();
}

class _ControlPanelWidgetState extends State<ControlPanelWidget> {
  late TextEditingController _promptController;
  late TextEditingController _prefixController;
  final DatabaseService _db = DatabaseService();
  
  bool _isModelSettingsExpanded = false;

  List<Map<String, dynamic>> _allUserPrompts = [];
  List<Map<String, dynamic>> _tags = [];

  @override
  void initState() {
    super.initState();
    final appState = Provider.of<AppState>(context, listen: false);
    _promptController = TextEditingController(text: appState.lastPrompt);
    _prefixController = TextEditingController(text: appState.imagePrefix);
    _loadPrompts();
  }

  @override
  void dispose() {
    _promptController.dispose();
    _prefixController.dispose();
    super.dispose();
  }

  // Reloads prompts from DB
  Future<void> _loadPrompts() async {
    final prompts = await _db.getPrompts();
    final tags = await _db.getPromptTags();
    
    if (mounted) {
      setState(() {
        _allUserPrompts = prompts;
        _tags = tags;
      });
    }
  }

  void _updateConfig({int? modelPk, String? modelIdStr, AppAspectRatio? ar, AppResolution? res, String? prompt}) {
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
    // Select specific values to rebuild on change
    final appState = context.watch<AppState>();
    final imageModels = appState.imageModels;
    final allChannels = appState.allChannels;
    final isMarkdownWorkbench = appState.isMarkdownWorkbench;
    
    // Determine selected model from AppState
    int? selectedModelPk;
    int? selectedChannelId;
    
    if (imageModels.isNotEmpty) {
      final savedModelId = appState.lastSelectedModelId;
      final match = imageModels.firstWhere(
        (m) => m['id'].toString() == savedModelId || m['model_id'] == savedModelId,
        orElse: () => {},
      );
      
      if (match.isNotEmpty) {
        selectedModelPk = match['id'] as int;
        selectedChannelId = match['channel_id'] as int?;
      } else {
        // Default to first
        final first = imageModels.first;
        selectedModelPk = first['id'] as int;
        selectedChannelId = first['channel_id'] as int?;
      }
    }

    // Keep controllers in sync if state changes externally (e.g. prompt refiner)
    if (_promptController.text != appState.lastPrompt) {
      _promptController.value = _promptController.value.copyWith(
        text: appState.lastPrompt,
        selection: TextSelection.collapsed(offset: appState.lastPrompt.length),
      );
    }
    if (_prefixController.text != appState.imagePrefix) {
      _prefixController.text = appState.imagePrefix;
    }

    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

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
                  // Model Selection Section
                  ModelSelectionSection(
                    availableModels: imageModels,
                    channels: allChannels,
                    selectedChannelId: selectedChannelId,
                    selectedModelPk: selectedModelPk,
                    aspectRatio: appState.lastAspectRatio,
                    resolution: appState.lastResolution,
                    isExpanded: _isModelSettingsExpanded,
                    onToggleExpansion: () => setState(() => _isModelSettingsExpanded = !_isModelSettingsExpanded),
                    onChannelChanged: (val) {
                      final firstInChannel = appState.getModelsForChannel(val).cast<Map<String, dynamic>?>().firstWhere(
                        (m) => m != null,
                        orElse: () => null,
                      );
                      final newPk = firstInChannel?['id'] as int?;
                      if (newPk != null) {
                        _updateConfig(modelPk: newPk);
                      }
                    },
                    onModelChanged: (val) {
                      _updateConfig(modelPk: val);
                    },
                    onAspectRatioChanged: (v) {
                      _updateConfig(ar: v);
                    },
                    onResolutionChanged: (v) {
                      _updateConfig(res: v);
                    },
                  ),

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
                  MarkdownEditor(
                    controller: _promptController,
                    label: l10n.prompt,
                    isMarkdown: isMarkdownWorkbench,
                    onMarkdownChanged: (v) => appState.setIsMarkdownWorkbench(v),
                    maxLines: 15,
                    initiallyPreview: false,
                    hint: l10n.promptHint,
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
                  onPressed: (_promptController.text.isEmpty || selectedModelPk == null) 
                      ? null 
                      : () {
                          final selectedModel = appState.imageModels.firstWhere((m) => m['id'] == selectedModelPk);
                          final modelName = selectedModel['model_name'] as String;
                          
                          appState.submitTask(selectedModelPk, {
                            'prompt': _promptController.text,
                            'aspectRatio': appState.lastAspectRatio.value,
                            'imageSize': appState.lastResolution.value,
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
    final activeTasks = appState.taskQueue.queue.where((t) => t.status == TaskStatus.processing).toList();
    
    // Average progress of running tasks
    double? totalProgress;
    int progressCount = 0;
    for (var t in activeTasks) {
      if (t.progress != null) {
        totalProgress = (totalProgress ?? 0) + t.progress!;
        progressCount++;
      }
    }
    final avgProgress = progressCount > 0 ? totalProgress! / progressCount : null;

    if (pendingCount == 0 && runningCount == 0) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (avgProgress != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: avgProgress,
              minHeight: 4,
              backgroundColor: colorScheme.secondaryContainer,
              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.secondaryContainer.withAlpha((255 * 0.5).round()),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (runningCount > 0) ...[
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: avgProgress,
                  ),
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
        ),
      ],
    );
  }

  void _showRefinerDialog(AppState appState, AppLocalizations l10n) {
    showDialog(
      context: context,
      builder: (context) => AIPromptRefiner(
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
      onPressed: _allUserPrompts.isEmpty ? null : () => _showPromptPickerMenu(l10n),
      icon: const Icon(Icons.library_books_outlined, size: 16),
      label: Text(l10n.library, style: const TextStyle(fontSize: 12)),
      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
    );
  }

  void _showPromptPickerMenu(AppLocalizations l10n) {
    showDialog(
      context: context,
      builder: (context) => LibraryDialog(
        allPrompts: _allUserPrompts,
        tags: _tags,
        initialContent: _promptController.text,
        onApply: (content, isAppend) {
          if (isAppend) {
            final existing = _promptController.text;
            _promptController.text = existing.isEmpty ? content : "$existing\n\n$content";
          } else {
            _promptController.text = content;
          }
          _updateConfig(prompt: _promptController.text);
        },
      ),
    );
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