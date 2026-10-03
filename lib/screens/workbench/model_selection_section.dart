import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../models/llm_channel.dart';
import '../../models/llm_model.dart';
import '../../models/spec_rate.dart';
import '../../services/llm/generation/generation_schema.dart';
import '../../services/llm/model_capabilities.dart';
import '../../widgets/models/model_picker_options.dart';
import '../../widgets/ui/app_field_size.dart';
import '../../widgets/ui/searchable_picker.dart';
import 'widgets/generation_params/generation_param_panel.dart';

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
  final GenerationSchema Function(LLMModel model)? schemaOf;

  /// What the store holds for a parameter before validation — the size field
  /// says when a sibling model's size was dropped for this one. Null in a
  /// host that has no store to ask.
  final String? Function(LLMModel model, String paramKey)? storedImageParamOf;

  /// The model's spec-billing rate table, or null — the size picker names the
  /// billing tier from it, and shows nothing without it.
  final List<SpecRate>? Function(LLMModel model)? specRatesOf;

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
    this.schemaOf,
    this.storedImageParamOf,
    this.specRatesOf,
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
                        style: textTheme.labelSmall?.mono.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
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
          if (modelInChannel != null) _buildModelSpecificOptions(context, modelInChannel, l10n),
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
              ? Padding(
                  padding: const EdgeInsets.only(top: _kGap),
                  child: body,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _buildModelSpecificOptions(BuildContext context, LLMModel model, AppLocalizations l10n) {
    final caps = capabilitiesOf(model);
    if (!caps.isImageGenerator || caps.imageParams.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: _kGap),
      child: GenerationParamPanel(
        specs: caps.imageParams,
        valueOf: (spec) => imageParamResolver(model, spec),
        onChanged: (key, value) => onImageParamChanged(model, key, value),
        modelName: model.modelName,
        storedValueOf: (key) => storedImageParamOf?.call(model, key),
        rates: specRatesOf?.call(model),
        schema: schemaOf?.call(model),
      ),
    );
  }
}
