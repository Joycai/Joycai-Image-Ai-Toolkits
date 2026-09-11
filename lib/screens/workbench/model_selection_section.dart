import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../models/llm_channel.dart';
import '../../models/llm_model.dart';
import '../../services/llm/model_capabilities.dart';
import '../../widgets/app_dropdown.dart';
import '../../widgets/app_field_size.dart';
import '../../widgets/app_segmented_control.dart';
import '../../widgets/dialogs/image_size_picker_dialog.dart';
import '../../widgets/models/model_picker_options.dart';
import '../../widgets/searchable_picker.dart';

/// Vertical rhythm inside the card: header → pickers → parameter grid
/// (`A1 · 1a`, `gap:8`).
const double _kGap = 8;

/// The model card's contents: a collapsible caption, the channel and model
/// pickers, and whichever parameters the selected model declares.
///
/// Drawn without a card of its own — the panel hosts it in one, the way it
/// hosts the selection and the toggles.
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
  final String Function(LLMModel model, ParamSpec spec) imageParamResolver;

  /// Persists a parameter change for the given model.
  final void Function(LLMModel model, String paramKey, String value) onImageParamChanged;

  /// The capability table for the given model as its channel serves it
  /// (`AppState.descriptorForModel`). Asked for rather than derived from the
  /// id here: a relay model pinned to a protocol has that protocol's
  /// parameters, which its id cannot know.
  final ModelCapabilities Function(LLMModel model) capabilitiesOf;

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
    required this.capabilitiesOf,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
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

    // `A1 · 1a`: an 11/500 tracked caption in the deep ink, and the chevron
    // that folds the card. Collapsed, the header still names the model, so
    // the card says what will run without having to be opened.
    final header = Semantics(
      expanded: isExpanded,
      child: InkWell(
        onTap: onToggleExpansion,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: SizedBox(
          height: AppSize.iconLg,
          child: Row(
            children: [
              Text(
                l10n.modelSelection,
                style: textTheme.labelSmall?.copyWith(
                  letterSpacing: AppType.trackedLabelSpacing,
                  color: colorScheme.onAccentTint,
                ),
              ),
              const SizedBox(width: AppSpace.s6),
              Expanded(
                child: collapsedModelName == null
                    ? const SizedBox.shrink()
                    : Text(
                        collapsedModelName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: textTheme.labelSmall?.mono.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
              ),
              const SizedBox(width: AppSpace.s4),
              Icon(
                isExpanded ? Icons.expand_less : Icons.expand_more,
                size: AppSize.iconMd,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );

    final body = Theme(
      // `A1 · 1a`: a field inside a card takes the column's ground as its fill,
      // under the theme's own hairline (颜色角色 「输入填充 = col」).
      data: theme.copyWith(
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          filled: true,
          fillColor: colorScheme.surfaceContainerLow,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Stacked full width and uncaptioned, as `1a` draws them: the
          // channel's dot and the model's name say which is which. The caption
          // is kept for screen readers, merged into the field it names.
          MergeSemantics(
            child: Semantics(
              label: l10n.channel,
              child: SearchablePickerField<int>(
                size: AppFieldSize.regular,
                selected: selectedChannel == null ? null : channelPickerOption(selectedChannel),
                optionsBuilder: () => channels.map(channelPickerOption).toList(),
                onChanged: onChannelChanged,
                hint: l10n.selectAChannel,
                searchHint: l10n.searchChannels,
                dialogIcon: Icons.hub_outlined,
                enabled: channels.isNotEmpty,
                badgeStyle: PickerBadge.dot,
              ),
            ),
          ),
          const SizedBox(height: _kGap),
          MergeSemantics(
            child: Semantics(
              label: l10n.model,
              child: SearchablePickerField<int>(
                size: AppFieldSize.regular,
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
          if (modelInChannel != null)
            _buildModelSpecificOptions(context, modelInChannel, l10n),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        header,
        AnimatedSize(
          duration: AppMotion.durationOf(context, AppMotion.reveal),
          curve: AppMotion.enter,
          alignment: AlignmentDirectional.topStart,
          child: isExpanded
              ? Padding(padding: const EdgeInsets.only(top: _kGap), child: body)
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  /// Whether a parameter needs the whole row rather than half of it.
  ///
  /// A segmented track of three or four options at half the card's width
  /// leaves each option ~30px — room for 「低」, not for "Medium". Two options
  /// and every select-like control fit a half.
  static bool _spansRow(ParamSpec spec) =>
      spec.control == ParamControl.segmented && spec.options.length > 2;

  Widget _buildModelSpecificOptions(BuildContext context, LLMModel model, AppLocalizations l10n) {
    final caps = capabilitiesOf(model);
    // Sliders are video-only (grok-imagine-video's duration); no image family
    // declares one, and this card has nothing to draw for it.
    final specs = [
      for (final spec in caps.imageParams)
        if (spec.control != ParamControl.slider) spec,
    ];
    if (!caps.isImageGenerator || specs.isEmpty) {
      return const SizedBox.shrink();
    }

    // `A1 · 1a`: a two-column grid, gap 6. Cells pair up in declaration order;
    // a cell that spans the row, or a half left without a partner, takes the
    // full width rather than leaving a hole beside it.
    final rows = <Widget>[];
    Widget? pendingHalf;
    for (final spec in specs) {
      final cell = _buildParamCell(context, model, spec, l10n);
      if (_spansRow(spec)) {
        if (pendingHalf != null) {
          rows.add(pendingHalf);
          pendingHalf = null;
        }
        rows.add(cell);
      } else if (pendingHalf == null) {
        pendingHalf = cell;
      } else {
        rows.add(Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: pendingHalf),
            const SizedBox(width: AppSpace.s6),
            Expanded(child: cell),
          ],
        ));
        pendingHalf = null;
      }
    }
    if (pendingHalf != null) rows.add(pendingHalf);

    return Padding(
      padding: const EdgeInsets.only(top: _kGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (index, row) in rows.indexed) ...[
            if (index > 0) const SizedBox(height: AppSpace.s6),
            row,
          ],
        ],
      ),
    );
  }

  /// One grid cell: an 11px secondary caption over its control.
  Widget _buildParamCell(BuildContext context, LLMModel model, ParamSpec spec, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final current = imageParamResolver(model, spec);

    final Widget control;
    switch (spec.control) {
      case ParamControl.dropdown:
        // The library's dropdown, drawn as the same box as the two pickers
        // above it. Controlled, so the value is the resolver's every build; the
        // `FormField` this replaced owned its own and had to be re-keyed per
        // model to drop a stale one.
        control = AppDropdown<String>(
          size: AppFieldSize.regular,
          value: current,
          items: [
            for (final o in spec.options)
              AppDropdownItem(value: o.value, label: _optionLabel(l10n, spec.key, o.value)),
          ],
          onChanged: (v) {
            if (v != null) onImageParamChanged(model, spec.key, v);
          },
        );
        break;
      case ParamControl.segmented:
        // `1a` 「质量」: every option `flex:1` on the track, the chosen one
        // lifted out on the panel's ground.
        control = AppSegmentedControl<String>(
          segments: spec.options
              .map((o) => AppSegment(
                    value: o.value,
                    label: _optionLabel(l10n, spec.key, o.value),
                  ))
              .toList(),
          value: current,
          onChanged: (v) => onImageParamChanged(model, spec.key, v),
          compact: true,
          expand: true,
          style: AppSegmentStyle.raised,
        );
        break;
      case ParamControl.customSize:
        // A field-shaped button showing the current value; it opens the
        // size-picker dialog (preset chips + free-form WxH + per-rule live
        // validation). `1d` draws it as a select box with an open-in-new glyph
        // rather than a chevron, because it opens a dialog, not a menu.
        control = OutlinedButton(
          style: OutlinedButton.styleFrom(
            backgroundColor: colorScheme.surfaceContainerLow,
            foregroundColor: colorScheme.onSurface,
            side: BorderSide(color: colorScheme.outlineVariant),
            minimumSize: const Size(0, AppSize.control),
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10),
            alignment: AlignmentDirectional.centerStart,
          ),
          onPressed: () async {
            final picked = await showImageSizePickerDialog(
              context: context,
              spec: spec,
              currentValue: current,
            );
            if (picked != null) onImageParamChanged(model, spec.key, picked);
          },
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _optionLabel(l10n, spec.key, current).replaceAll('x', '×'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // A pixel pair is a figure, set in the mono face so the
                  // digits line up between one model and the next.
                  style: textTheme.bodySmall?.mono,
                ),
              ),
              const SizedBox(width: AppSpace.s6),
              Icon(Icons.open_in_new, size: AppSize.iconSm, color: colorScheme.onSurfaceVariant),
            ],
          ),
        );
        break;
      case ParamControl.slider:
        // Filtered out above; kept so the switch stays exhaustive.
        control = const SizedBox.shrink();
        break;
    }

    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _paramLabel(l10n, spec.labelKey),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpace.s4),
          control,
        ],
      ),
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
