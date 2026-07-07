import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/llm/model_capabilities.dart';
import '../../widgets/dialogs/image_size_picker_dialog.dart';

class ModelSelectionSection extends StatelessWidget {
  final List<Map<String, dynamic>> availableModels;
  final List<Map<String, dynamic>> channels;
  final int? selectedChannelId;
  final int? selectedModelDbId;
  final bool isExpanded;
  final VoidCallback onToggleExpansion;
  final ValueChanged<int?> onChannelChanged;
  final ValueChanged<int?> onModelChanged;

  /// Resolves the current (validated) value for a parameter of the given model.
  final String Function(String modelId, ParamSpec spec) imageParamResolver;

  /// Persists a parameter change for the given model.
  final void Function(String modelId, String paramKey, String value) onImageParamChanged;

  const ModelSelectionSection({
    super.key,
    required this.availableModels,
    required this.channels,
    required this.selectedChannelId,
    required this.selectedModelDbId,
    required this.isExpanded,
    required this.onToggleExpansion,
    required this.onChannelChanged,
    required this.onModelChanged,
    required this.imageParamResolver,
    required this.onImageParamChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final filteredModels = availableModels.where((m) => m['channel_id'] == selectedChannelId).toList();

    // Resolve subtitle model name safely
    String? collapsedModelName;
    if (!isExpanded && selectedModelDbId != null) {
      final match = availableModels.cast<Map<String, dynamic>?>().firstWhere(
        (m) => m?['id'] == selectedModelDbId,
        orElse: () => null,
      );
      collapsedModelName = match?['model_name'] as String?;
    }

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        initiallyExpanded: isExpanded,
        onExpansionChanged: (_) => onToggleExpansion(),
        leading: Icon(Icons.tune_outlined, size: 20, color: colorScheme.primary),
        title: Text(l10n.modelSelection, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        subtitle: collapsedModelName != null
            ? Text(collapsedModelName, style: TextStyle(fontSize: 11, color: colorScheme.outline))
            : null,
        children: [
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
                      value: (filteredModels.any((m) => m['id'] == selectedModelDbId))
                          ? selectedModelDbId
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
          if (selectedModelDbId != null)
            Builder(
              builder: (context) {
                final model = availableModels.firstWhere((m) => m['id'] == selectedModelDbId, orElse: () => {});
                if (model.isNotEmpty) {
                  return _buildModelSpecificOptions(context, model['model_id'] as String, l10n);
                }
                return const SizedBox.shrink();
              },
            ),
        ],
      ),
    );
  }

  Widget _buildChannelDropdown(ColorScheme colorScheme) {
    return DropdownButton<int>(
      isExpanded: true,
      // Guard: the selected id must exist in the (filtered) channel list,
      // otherwise DropdownButton throws an assertion error.
      value: channels.any((c) => c['id'] == selectedChannelId) ? selectedChannelId : null,
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
    final caps = ModelCapabilities.forModel(modelId);
    if (!caps.isImageGenerator || caps.imageParams.isEmpty) {
      return const SizedBox.shrink();
    }

    final fields = <Widget>[];
    for (final spec in caps.imageParams) {
      if (fields.isNotEmpty) fields.add(const SizedBox(height: 8));
      fields.add(_buildParamRow(context, modelId, spec, l10n));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(children: fields),
    );
  }

  Widget _buildParamRow(BuildContext context, String modelId, ParamSpec spec, AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final current = imageParamResolver(modelId, spec);

    Widget control;
    switch (spec.control) {
      case ParamControl.dropdown:
        control = DropdownButton<String>(
          isExpanded: true,
          value: current,
          style: TextStyle(fontSize: 12, color: colorScheme.onSurface),
          underline: Container(height: 1, color: colorScheme.outlineVariant),
          items: spec.options
              .map((o) => DropdownMenuItem(
                    value: o.value,
                    child: Text(_optionLabel(l10n, spec.key, o.value)),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) onImageParamChanged(modelId, spec.key, v);
          },
        );
        break;
      case ParamControl.segmented:
        control = SegmentedButton<String>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            textStyle: const TextStyle(fontSize: 10),
          ),
          segments: spec.options
              .map((o) => ButtonSegment(
                    value: o.value,
                    label: Text(_optionLabel(l10n, spec.key, o.value)),
                  ))
              .toList(),
          selected: {current},
          onSelectionChanged: (v) => onImageParamChanged(modelId, spec.key, v.first),
        );
        break;
      case ParamControl.customSize:
        // Render as a button that displays the current value and opens the
        // size-picker dialog. The dialog handles preset chips + free-form
        // WxH input + per-rule live validation.
        control = OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            minimumSize: const Size(0, 30),
            visualDensity: VisualDensity.compact,
            textStyle: const TextStyle(fontSize: 12),
            alignment: Alignment.centerLeft,
          ),
          onPressed: () async {
            final picked = await showImageSizePickerDialog(
              context: context,
              spec: spec,
              currentValue: current,
            );
            if (picked != null) onImageParamChanged(modelId, spec.key, picked);
          },
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _optionLabel(l10n, spec.key, current).replaceAll('x', '×'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.tune, size: 14),
            ],
          ),
        );
        break;
    }

    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(_paramLabel(l10n, spec.labelKey),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        ),
        Expanded(child: control),
      ],
    );
  }

  String _paramLabel(AppLocalizations l10n, String labelKey) {
    switch (labelKey) {
      case 'aspectRatio':
        return l10n.aspectRatio;
      case 'resolution':
        return l10n.resolution;
      case 'quality':
        return l10n.quality;
      case 'mjVersion':
        return l10n.mjVersion;
      case 'mjMode':
        return l10n.mjMode;
      case 'mjStylize':
        return l10n.mjStylize;
      case 'mjChaos':
        return l10n.mjChaos;
      default:
        return labelKey;
    }
  }

  String _optionLabel(AppLocalizations l10n, String paramKey, String value) {
    if (value == 'auto' || value == 'not_set') return l10n.optionAuto;
    if (paramKey == 'quality') {
      switch (value) {
        case 'low':
          return l10n.qualityLow;
        case 'medium':
          return l10n.qualityMedium;
        case 'high':
          return l10n.qualityHigh;
      }
    }
    return value;
  }
}
