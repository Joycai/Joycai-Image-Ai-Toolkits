import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/llm_channel.dart';
import '../../models/llm_model.dart';
import '../../services/llm/model_capabilities.dart';
import '../../widgets/app_segmented_control.dart';
import '../../widgets/app_labelled_field.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/dialogs/image_size_picker_dialog.dart';
import '../../widgets/models/model_picker_options.dart';
import '../../widgets/searchable_picker.dart';

class ModelSelectionSection extends StatelessWidget {
  /// The image models to choose from, in the type the state already holds
  /// them in.
  ///
  /// These used to arrive as `Map<String, dynamic>` — one freshly allocated
  /// eighteen-entry map per model per build of the panel, read back out with
  /// string keys. The panel rebuilds on any [AppState] notification, so a
  /// relay channel's worth of models was being converted, and thrown away,
  /// several times a second.
  final List<LLMModel> availableModels;
  final List<LLMChannel> channels;
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

    // One pass over the models, for the two things a build actually needs: the
    // selected model, and whether the selected channel has any models at all.
    // The channel's *list* is not built here — see the pickers' optionsBuilder,
    // which runs only when one is opened.
    LLMModel? selectedModel;
    bool channelHasModels = false;
    for (final m in availableModels) {
      if (m.id == selectedModelDbId) selectedModel = m;
      if (m.channelId == selectedChannelId) channelHasModels = true;
    }
    final selectedChannel = channels.cast<LLMChannel?>().firstWhere(
      (c) => c?.id == selectedChannelId,
      orElse: () => null,
    );
    // A model whose channel is not the selected one is a stale selection, and
    // showing its name under the wrong channel is what made the pair look
    // unclickable the last time these two got out of step.
    //
    // Everything below reads *this*, not `selectedModel`. The guard used to
    // cover the picker alone, so in the one state it exists for, the card
    // contradicted itself: the field drew its "select a model" hint while the
    // subtitle named the stale model and the parameter rows underneath edited
    // it — writing under its family key, for a model the field said was not
    // chosen.
    final modelInChannel = selectedModel?.channelId == selectedChannelId ? selectedModel : null;

    final collapsedModelName = !isExpanded ? modelInChannel?.modelName : null;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        initiallyExpanded: isExpanded,
        onExpansionChanged: (_) => onToggleExpansion(),
        leading: Icon(Icons.tune_outlined, size: 20, color: colorScheme.primary),
        title: Text(l10n.modelSelection, style: Theme.of(context).textTheme.titleSmall),
        subtitle: collapsedModelName != null
            ? Text(collapsedModelName, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colorScheme.outline))
            : null,
        children: [
          const SizedBox(height: 8),
          // Filled, per `16a`: these two sit inside a card, where an outline
          // alone leaves them flush with it. Scoped to the pickers rather than
          // the whole panel — the prompt editor below is deliberately boxless.
          FilledFieldScope(
            child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppLabelledField(
                  label: l10n.channel,
                  child: SearchablePickerField<int>(
                    selected: selectedChannel == null ? null : channelPickerOption(selectedChannel),
                    optionsBuilder: () => channels.map(channelPickerOption).toList(),
                    onChanged: onChannelChanged,
                    hint: l10n.selectAChannel,
                    searchHint: l10n.searchChannels,
                    dialogIcon: Icons.hub_outlined,
                    enabled: channels.isNotEmpty,
                    // A dot, not a chip: this field is half a 340px column,
                    // and `16a` spends what is left on the channel's name.
                    badgeStyle: PickerBadge.dot,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: AppLabelledField(
                  // `model`, not `modelSelection` — the card's own heading is
                  // already 「模型选择」, and the caption under it was saying it
                  // a second time. `16a` labels the field 「模型」.
                  label: l10n.model,
                  child: SearchablePickerField<int>(
                    selected: modelInChannel == null ? null : modelPickerOption(modelInChannel),
                    // Built on open, not on build. This is the list that used
                    // to freeze the window for hundreds of milliseconds.
                    optionsBuilder: () => [
                      for (final m in availableModels)
                        if (m.channelId == selectedChannelId) modelPickerOption(m),
                    ],
                    onChanged: onModelChanged,
                    hint: l10n.selectAModel,
                    searchHint: l10n.searchModels,
                    dialogIcon: Icons.memory_outlined,
                    enabled: channelHasModels,
                  ),
                ),
              ),
            ],
            ),
          ),
          if (modelInChannel != null)
            _buildModelSpecificOptions(context, modelInChannel.modelId, l10n),
        ],
      ),
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
        // A themed field rather than a bare [DropdownButton] under a
        // hand-drawn rule. An option set is short enough that Material's own
        // menu costs nothing here — what it was missing was the box, which
        // left it reading as a different family of control from the two
        // pickers directly above it in the same card.
        control = DropdownButtonFormField<String>(
          // Keyed, because a `FormField` owns its value rather than taking it
          // from the caller every build: `initialValue` only re-syncs when it
          // *changes* between two builds. Switch model while a parameter write
          // is still in flight and this element is reused with the old value
          // against the new model's options — which asserts when the value is
          // absent from them, and silently displays a value the state does not
          // hold when it happens to be present. A key per model and parameter
          // makes it a fresh element instead.
          key: ValueKey<String>('$modelId.${spec.key}'),
          isExpanded: true,
          isDense: true,
          initialValue: current,
          decoration: const InputDecoration(),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurface),
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
        control = AppSegmentedControl<String>(
          segments: spec.options
              .map((o) => AppSegment(
                    value: o.value,
                    label: _optionLabel(l10n, spec.key, o.value),
                  ))
              .toList(),
          value: current,
          onChanged: (v) => onImageParamChanged(modelId, spec.key, v),
          compact: true,
          // `16a` gives every option `flex:1` and lifts the chosen one out on
          // white. Tinted and self-sized, this row read as four unequal
          // buttons with one of them washed — and on the accent tint the
          // chosen option was the *dimmest* box in the card.
          expand: true,
          style: AppSegmentStyle.raised,
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
            textStyle: Theme.of(context).textTheme.bodySmall,
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
                  // A pixel pair is a figure, and `16a` sets it in the mono
                  // face for the same reason every other id and count in the
                  // app is: the digits line up between one model and the next.
                  style: Theme.of(context).textTheme.bodySmall?.mono,
                ),
              ),
              const Icon(Icons.tune, size: 14),
            ],
          ),
        );
        break;
      case ParamControl.slider:
        // Video-only (grok-imagine-video's duration); no image family uses it.
        control = const SizedBox.shrink();
        break;
    }

    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(_paramLabel(l10n, spec.labelKey),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
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
        // The image families' `resolution` param is a width×height pair, which
        // is a size, not a resolution — and `16a` labels the row 「尺寸」. The
        // video panel's copy of this switch keeps `resolution`: there the
        // param really is one (720p / 1080p).
        return l10n.imageSizeLabel;
      case 'quality':
        return l10n.quality;
      case 'promptExtend':
        return l10n.promptExtend;
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
    if (paramKey == 'promptExtend') {
      switch (value) {
        case 'on':
          return l10n.promptExtendOn;
        case 'off':
          return l10n.promptExtendOff;
      }
    }
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

/// A control under its own bold caption.
///
/// The caption is [TextTheme.labelMedium] in bold, which is what the parameter
/// rows below already use for theirs — the two pickers and the aspect-ratio
/// row beneath them are labelled the same way rather than each inventing a
/// weight.
