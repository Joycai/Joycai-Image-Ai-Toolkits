import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../l10n/app_localizations.dart';

class ModelSelectionSection extends StatelessWidget {
  final List<Map<String, dynamic>> availableModels;
  final List<Map<String, dynamic>> channels;
  final int? selectedChannelId;
  final int? selectedModelPk;
  final AppAspectRatio aspectRatio;
  final AppResolution resolution;
  final bool isExpanded;
  final VoidCallback onToggleExpansion;
  final ValueChanged<int?> onChannelChanged;
  final ValueChanged<int?> onModelChanged;
  final ValueChanged<AppAspectRatio> onAspectRatioChanged;
  final ValueChanged<AppResolution> onResolutionChanged;

  const ModelSelectionSection({
    super.key,
    required this.availableModels,
    required this.channels,
    required this.selectedChannelId,
    required this.selectedModelPk,
    required this.aspectRatio,
    required this.resolution,
    required this.isExpanded,
    required this.onToggleExpansion,
    required this.onChannelChanged,
    required this.onModelChanged,
    required this.onAspectRatioChanged,
    required this.onResolutionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final filteredModels = availableModels.where((m) => m['channel_id'] == selectedChannelId).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Custom Collapsible Header
        InkWell(
          onTap: onToggleExpansion,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              children: [
                Icon(
                  isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.modelSelection, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      if (!isExpanded && selectedModelPk != null)
                        Text(
                          availableModels.firstWhere((m) => m['id'] == selectedModelPk)['model_name'],
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
        if (isExpanded) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.channel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    _buildChannelDropdown(colorScheme),
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
                      value: (filteredModels.any((m) => m['id'] == selectedModelPk)) 
                          ? selectedModelPk 
                          : null,
                      hint: Text(l10n.selectAModel),
                      style: TextStyle(fontSize: 12, color: colorScheme.onSurface),
                      underline: Container(height: 1, color: colorScheme.outlineVariant),
                      items: filteredModels.map((m) => DropdownMenuItem(
                        value: m['id'] as int,
                        child: Text(m['model_name']),
                      )).toList(),
                      onChanged: onModelChanged,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (selectedModelPk != null)
            Builder(
              builder: (context) {
                final model = availableModels.firstWhere((m) => m['id'] == selectedModelPk, orElse: () => {});
                if (model.isNotEmpty) {
                  return _buildModelSpecificOptions(context, model['model_id'] as String, l10n);
                }
                return const SizedBox.shrink();
              }
            ),
        ],
      ],
    );
  }

  Widget _buildChannelDropdown(ColorScheme colorScheme) {
    return DropdownButton<int>(
      isExpanded: true,
      value: selectedChannelId,
      style: TextStyle(fontSize: 12, color: colorScheme.onSurface),
      underline: Container(height: 1, color: colorScheme.outlineVariant),
      items: channels.map((c) => DropdownMenuItem<int>(
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
      onChanged: onChannelChanged,
    );
  }

  Widget _buildModelSpecificOptions(BuildContext context, String modelId, AppLocalizations l10n) {
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
                  child: DropdownButton<AppAspectRatio>(
                    isExpanded: true,
                    value: aspectRatio,
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface),
                    underline: Container(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
                    items: AppAspectRatio.values
                        .map((e) => DropdownMenuItem(value: e, child: Text(e.value))).toList(),
                    onChanged: (v) => onAspectRatioChanged(v!),
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
                  child: SegmentedButton<AppResolution>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(fontSize: 10),
                    ),
                    segments: AppResolution.values.map((r) => 
                      ButtonSegment(value: r, label: Text(r.value))
                    ).toList(),
                    selected: {resolution},
                    onSelectionChanged: (v) => onResolutionChanged(v.first),
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
}
