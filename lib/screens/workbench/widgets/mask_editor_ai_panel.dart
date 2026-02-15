import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/responsive.dart';
import '../../../state/app_state.dart';

class MaskEditorAIPanel extends StatelessWidget {
  final String? selectedModelId;
  final double pointCount;
  final TextEditingController promptController;
  final bool isGenerating;
  final Function(String?) onModelChanged;
  final Function(double) onPointCountChanged;
  final VoidCallback onGenerate;

  const MaskEditorAIPanel({
    super.key,
    required this.selectedModelId,
    required this.pointCount,
    required this.promptController,
    required this.isGenerating,
    required this.onModelChanged,
    required this.onPointCountChanged,
    required this.onGenerate,
  });

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final colorScheme = Theme.of(context).colorScheme;
    final isMobile = Responsive.isMobile(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: isMobile 
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: selectedModelId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Model',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: appState.imageModels.map((m) => DropdownMenuItem(
                        value: m.modelId,
                        child: Text(m.modelName.isNotEmpty ? m.modelName : m.modelId, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                      )).toList(),
                      onChanged: onModelChanged,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 100,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("Detail: ${pointCount.toInt()}", style: const TextStyle(fontSize: 10)),
                        Slider(
                          value: pointCount,
                          min: 10,
                          max: 500,
                          divisions: 49,
                          onChanged: onPointCountChanged,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: promptController,
                      decoration: const InputDecoration(
                        labelText: "What to mask?",
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => onGenerate(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: isGenerating ? null : onGenerate,
                    style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                    child: isGenerating 
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.play_arrow, size: 16),
                  ),
                ],
              ),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  initialValue: selectedModelId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Model',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: appState.imageModels.map((m) => DropdownMenuItem(
                    value: m.modelId,
                    child: Text(m.modelName.isNotEmpty ? m.modelName : m.modelId, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                  )).toList(),
                  onChanged: onModelChanged,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 1,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Detail: ${pointCount.toInt()}", style: const TextStyle(fontSize: 10)),
                    Slider(
                      value: pointCount,
                      min: 10,
                      max: 500,
                      divisions: 49,
                      onChanged: onPointCountChanged,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: promptController,
                  decoration: const InputDecoration(
                    labelText: "What to mask?",
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => onGenerate(),
                ),
              ),
              const SizedBox(width: 16),
              FilledButton.icon(
                onPressed: isGenerating ? null : onGenerate,
                icon: isGenerating 
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.auto_awesome, size: 16),
                label: Text(isGenerating ? "Generating..." : "Generate"),
              ),
            ],
          ),
    );
  }
}
