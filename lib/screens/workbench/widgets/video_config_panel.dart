import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants.dart';
import '../../../core/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/app_image.dart';
import '../../../models/llm_channel.dart';
import '../../../models/llm_model.dart';
import '../../../models/prompt_history_entry.dart';
import '../../../services/llm/model_capabilities.dart';
import '../../../state/app_state.dart';
import '../../../state/workbench_ui_state.dart';
import '../../../widgets/app_text_field.dart';
import '../../../core/design_tokens.dart';
import '../../../widgets/app_labelled_field.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/app_segmented_control.dart';
import '../../../widgets/app_snackbar.dart';
import '../../../widgets/collapsible_card.dart';
import '../../../widgets/dialogs/prompt_history_dialog.dart';
import '../../../widgets/markdown_editor.dart';
import '../../../widgets/models/model_picker_options.dart';
import '../../../widgets/searchable_picker.dart';
import 'config_action_bar.dart';
import '../../../widgets/app_section_label.dart';
import '../../../widgets/app_setting_row.dart';
import 'queue_settings_dialog.dart';

class VideoConfigPanel extends StatefulWidget {
  final ScrollController? scrollController;
  const VideoConfigPanel({super.key, this.scrollController});

  @override
  State<VideoConfigPanel> createState() => _VideoConfigPanelState();
}

class _VideoConfigPanelState extends State<VideoConfigPanel> {
  late MarkdownTextEditingController _promptController;
  bool _isModelSettingsExpanded = false;

  @override
  void initState() {
    super.initState();
    final appState = Provider.of<AppState>(context, listen: false);
    _promptController = MarkdownTextEditingController(text: appState.lastVideoPrompt);
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    final appState = Provider.of<AppState>(context, listen: false);
    final uiState = Provider.of<WorkbenchUIState>(context, listen: false);      
    final l10n = AppLocalizations.of(context)!;

    // Find selected model
    final videoModels = appState.videoModels;
    if (videoModels.isEmpty) {
      AppSnackBar.warning(context, l10n.noModelsConfigured);
      return;
    }

    final savedModelId = appState.lastVideoModelId;
    final selectedModel = videoModels.cast<LLMModel?>().firstWhere(
      (m) => m?.id.toString() == savedModelId || m?.modelId == savedModelId,    
      orElse: () => videoModels.first,
    );

    if (selectedModel == null) return;

    final params = <String, dynamic>{
      'prompt': _promptController.text,
      'resolution': appState.lastVideoResolution.value,
      'aspectRatio': appState.lastVideoAspectRatio.value,
      'referenceImagePaths': uiState.videoReferenceImages.map((i) => i.path).toList(),
      'firstFramePath': uiState.videoFirstFrame?.path,
      'lastFramePath': uiState.videoLastFrame?.path,
      // Per-family video extras (e.g. Sora's seconds / quality). Empty for
      // families with no capability-driven controls.
      ...appState.effectiveVideoParams(selectedModel.modelId),
    };

    appState.submitVideoTask(selectedModel.id, params, modelIdDisplay: selectedModel.modelName);

    AppSnackBar.info(context, l10n.taskSubmitted);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final uiState = context.watch<WorkbenchUIState>();
    final l10n = AppLocalizations.of(context)!;

    final videoModels = appState.videoModels;

    // Determine selected model
    LLMModel? selectedModel;

    if (videoModels.isNotEmpty) {
      final savedModelId = appState.lastVideoModelId;
      final savedDbId = int.tryParse(savedModelId ?? '');
      for (final m in videoModels) {
        if (m.id == savedDbId || m.modelId == savedModelId) {
          selectedModel = m;
          break;
        }
      }

      selectedModel ??= videoModels.first;
    }
    // Derived once per data load rather than filtered here; this was a nested
    // `any` over the model list, O(channels × models) every frame to answer a
    // question about a dozen rows. See `AppState._channelsServing`.
    final videoChannels = appState.videoChannels;
    final selectedChannel = videoChannels.cast<LLMChannel?>().firstWhere(
      (c) => c?.id == selectedModel?.channelId,
      orElse: () => null,
    );

    final bool isMobile = Responsive.isMobile(context);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Model, channel, resolution, aspect and duration in one card. `A6`
        // groups them because they are one decision — what to render and how —
        // where this had them loose on the panel, reading as five unrelated
        // rows between two headed sections.
        AppCard(
          outlined: true,
          padding: EdgeInsets.zero,
          child: _buildModelSection(
              l10n, videoModels, videoChannels, selectedChannel, selectedModel, appState, uiState),
        ),
        const SizedBox(height: 12),

        AppSectionLabel(
          l10n.prompt,
          trailing: PromptHistoryButton(
            entries: appState.videoPromptHistory,
            type: PromptHistoryType.video,
            onApply: (content) {
              _promptController.text = content;
              appState.updateVideoConfig(prompt: content);
            },
          ),
        ),
        // One box, as `17a` draws it and as the image panel already does: the
        // card is the frame, and the header is set off by a hairline inside
        // it. See [MarkdownEditor.bordered].
        AppCard(
          outlined: true,
          padding: EdgeInsets.zero,
          child: MarkdownEditor(
            controller: _promptController,
            label: l10n.prompt,
            isMarkdown: appState.isMarkdownWorkbench,
            onMarkdownChanged: (v) => appState.setIsMarkdownWorkbench(v),
            maxLines: 8,
            hint: l10n.promptHint,
            // Silent draft path — typing here must not notify the whole app.
            // See AppStateWorkbench.setVideoPromptDraft.
            onChanged: (v) => appState.setVideoPromptDraft(v),
            expand: false,
            bordered: false,
          ),
        ),
        const SizedBox(height: 12),
        // In a card, like the image panel's pair of toggles and like `A6`. A
        // bare [SwitchListTile] between two headed sections read as a stray row
        // rather than as a setting belonging to the prompt above it.
        // The image panel's toggle row, restated — not a [SwitchListTile].
        // That widget brings Material's list geometry *and* its 52x32 switch,
        // where `17a` draws the same 18px glyph, two lines of text and 36px
        // pill the image panel's two toggles wear a tab away.
        AppCard(
          outlined: true,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: AppToggleRow(
            icon: Icons.compress,
            title: l10n.compressReferenceImages,
            description: l10n.compressReferenceImagesDesc,
            value: appState.compressReferenceImages,
            onChanged: (v) => appState.updateWorkbenchConfig(compressReferenceImages: v),
          ),
        ),
        const SizedBox(height: 12),

        AppSectionLabel(l10n.frames),
        const SizedBox(height: 6),
        Builder(
          builder: (context) {
            final cs = Theme.of(context).colorScheme;
            return Flex(
              direction: isMobile ? Axis.vertical : Axis.horizontal,
              children: [
                _buildFrameTargetWrapper(
                  isMobile: isMobile,
                  child: _FrameDropTarget(
                    label: l10n.firstFrame,
                    image: uiState.videoFirstFrame,
                    onDrop: (img) => uiState.setVideoFirstFrame(img),
                    onClear: () => uiState.setVideoFirstFrame(null),
                    dropHint: l10n.dropFirstFrameHere,
                    emptyColor: cs.primary.withValues(alpha: 0.04),
                    emptyIcon: Icons.first_page,
                  ),
                ),
                SizedBox(width: isMobile ? 0 : 12, height: isMobile ? 12 : 0),
                _buildFrameTargetWrapper(
                  isMobile: isMobile,
                  child: _FrameDropTarget(
                    label: l10n.lastFrame,
                    image: uiState.videoLastFrame,
                    onDrop: (img) => uiState.setVideoLastFrame(img),
                    onClear: () => uiState.setVideoLastFrame(null),
                    dropHint: l10n.dropLastFrameHere,
                    // The same wash as the first frame, not `tertiaryContainer`.
                    // Two drop targets in a row were being told apart by hue —
                    // an identity colour, derived from the seed, on a control
                    // whose two halves are already labelled 首帧 and 尾帧. `A6`
                    // draws both slots identically, and at some seeds the old
                    // pairing put a lilac box next to a mint one for no reason
                    // the user could act on.
                    emptyColor: cs.primary.withValues(alpha: 0.04),
                    emptyIcon: Icons.last_page,
                  ),
                ),
              ],
            );
          },
        ),

        const SizedBox(height: 12),
        AppSectionLabel(l10n.referenceImages),
        const SizedBox(height: 6),
        _ReferenceImagesTarget(
          images: uiState.videoReferenceImages,
          onDrop: (img) => uiState.addVideoReferenceImage(img),
          onRemove: (img) => uiState.removeVideoReferenceImage(img),
          dropHint: l10n.dropVideoReferenceHere,
        ),
      ],
    );

    // Primary action — pinned at the top on the mobile bottom sheet (mirroring
    // the image panel), or at the bottom of the scroll on desktop.
    final generateButton = Row(
      children: [
        Expanded(
          // Enabled state hangs off the controller, not off a panel rebuild:
          // typing no longer notifies [AppState], so nothing else re-runs this.
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _promptController,
            builder: (context, promptValue, _) => AppButton(
              label: l10n.generateVideo,
              icon: Icons.movie_outlined,
              size: AppButtonSize.large,
              fullWidth: true,
              onPressed: promptValue.text.isEmpty ? null : _handleSubmit,
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Queue settings (concurrency / retry / prefix / safety thresholds),
        // shared with the image workbench.
        // `17a` draws this as a 48px square washed in the accent at 12% with
        // an accent glyph — the app's own tonal pair. Material's `filledTonal`
        // reaches for `secondaryContainer`, which at several of the eight
        // seeds is a grey that reads as disabled beside the button it sits
        // next to.
        SizedBox(
          width: 48,
          height: 48,
          child: IconButton(
            onPressed: () => showQueueSettingsDialog(context),
            icon: const Icon(Icons.settings_outlined, size: 20),
            tooltip: l10n.queueSettings,
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.accentTint,
              foregroundColor: Theme.of(context).colorScheme.onAccentTint,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
            ),
          ),
        ),
      ],
    );

    if (widget.scrollController != null) {
      return Column(
        mainAxisSize: MainAxisSize.max,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: generateButton,
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: widget.scrollController,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: content,
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: content,
          ),
        ),
        ConfigActionBar(child: generateButton),
      ],
    );
  }

  Widget _buildFrameTargetWrapper({required bool isMobile, required Widget child}) {
    if (isMobile) {
      return SizedBox(width: double.infinity, child: child);
    }
    return Expanded(child: child);
  }

  Widget _buildModelSection(
    AppLocalizations l10n,
    List<LLMModel> videoModels,
    List<LLMChannel> videoChannels,
    LLMChannel? selectedChannel,
    LLMModel? selectedModel,
    AppState appState,
    WorkbenchUIState uiState,
  ) {
    final selectedChannelId = selectedChannel?.id;
    // The model the caller already resolved, rather than a second scan of the
    // list to recover a name it was holding all along.
    // The display name. `17a` renders `sora-2-pro` here in the mono face,
    // which reads as an id — but its own prose says 「只留标题与当前模型名」,
    // and for a Sora model those two strings are the same, so the markup
    // cannot settle it and the sentence can. The image panel's identical card
    // names the model too; a pair of panels one tab apart showing different
    // fields under the same heading is the thing this pass exists to remove.
    final collapsedModelName = _isModelSettingsExpanded ? null : selectedModel?.modelName;
    // A model whose channel is not the selected one is a stale pair, and the
    // card below would otherwise name it under the wrong channel — the same
    // guard the image panel carries.
    final modelInChannel =
        selectedModel?.channelId == selectedChannelId ? selectedModel : null;

    // Some families (e.g. grok-imagine-video-1.5) declare their own
    // aspectRatio/resolution videoParams with a different option set than
    // the shared Veo dropdowns below — hide the shared control for whichever
    // key that family overrides so the panel doesn't show two conflicting
    // resolution/aspect-ratio pickers.
    final caps = modelInChannel == null
        ? const ModelCapabilities()
        : ModelCapabilities.forModel(modelInChannel.modelId);
    final overridesResolution = caps.videoParams.any((p) => p.key == 'resolution');
    final overridesAspectRatio = caps.videoParams.any((p) => p.key == 'aspectRatio');

    final sharedControls = <Widget>[
      if (!overridesResolution)
        Expanded(
          child: AppLabelledField(
            label: l10n.videoResolution,
            child: DropdownButtonFormField<VeoResolution>(
              initialValue: appState.lastVideoResolution,
              items: VeoResolution.values.map((v) => DropdownMenuItem(
                value: v,
                child: Text(v.value),
              )).toList(),
              onChanged: (v) => appState.updateVideoConfig(resolution: v),
            ),
          ),
        ),
      if (!overridesResolution && !overridesAspectRatio) const SizedBox(width: 16),
      if (!overridesAspectRatio)
        Expanded(
          child: AppLabelledField(
            label: l10n.videoAspectRatio,
            child: DropdownButtonFormField<VeoAspectRatio>(
              initialValue: appState.lastVideoAspectRatio,
              items: VeoAspectRatio.values.map((v) => DropdownMenuItem(
                value: v,
                child: Text(v.value),
              )).toList(),
              onChanged: (v) => appState.updateVideoConfig(aspectRatio: v),
            ),
          ),
        ),
    ];

    return CollapsibleCard(
      leadingIcon: Icons.tune_outlined,
      title: l10n.modelSelection,
      subtitle: collapsedModelName,
      isExpanded: _isModelSettingsExpanded,
      onToggle: () => setState(() => _isModelSettingsExpanded = !_isModelSettingsExpanded),
      content: FilledFieldScope(
        child: Column(
          children: [
            // Side by side, captioned above, filled — `17b` draws the video
            // card's fields exactly as `16a` draws the image card's, which is
            // the point of them being the same card. Stacked with floating
            // `labelText`s, these two were the only pair of pickers in the app
            // wearing a different form from every other pair.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppLabelledField(
                    label: l10n.channel,
                    child: SearchablePickerField<int>(
                      selected:
                          selectedChannel == null ? null : channelPickerOption(selectedChannel),
                      optionsBuilder: () => videoChannels.map(channelPickerOption).toList(),
                      onChanged: (val) {
                        final firstVideoInChannel =
                            videoModels.where((m) => m.channelId == val).firstOrNull;
                        if (firstVideoInChannel != null) {
                          appState.updateVideoConfig(
                              modelId: firstVideoInChannel.id.toString());
                        }
                      },
                      hint: l10n.selectAChannel,
                      searchHint: l10n.searchChannels,
                      dialogIcon: Icons.hub_outlined,
                      enabled: videoChannels.isNotEmpty,
                      badgeStyle: PickerBadge.dot,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: AppLabelledField(
                    label: l10n.model,
                    child: SearchablePickerField<int>(
                      selected: modelInChannel == null ? null : modelPickerOption(modelInChannel),
                      // Built on open, not on build — the same reason the
                      // image panel's is: a relay's worth of video models used
                      // to be mounted as `DropdownMenuItem`s on every frame to
                      // render one line.
                      optionsBuilder: () => [
                        for (final m in videoModels)
                          if (m.channelId == selectedChannelId && m.id != null)
                            modelPickerOption(m),
                      ],
                      onChanged: (val) => appState.updateVideoConfig(modelId: val.toString()),
                      hint: l10n.selectAModel,
                      searchHint: l10n.searchModels,
                      dialogIcon: Icons.memory_outlined,
                      enabled: videoModels.any((m) => m.channelId == selectedChannelId),
                    ),
                  ),
                ),
              ],
            ),
            if (sharedControls.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: sharedControls),
            ],
            // Per-model extras (seconds / quality for openaiVideo; aspectRatio
            // / resolution / seconds slider for grok-imagine-video-1.5;
            // nothing for Veo). Rebuilds when the user changes a value or
            // switches model.
            if (modelInChannel != null) ...[
              const SizedBox(height: 8),
              _buildVideoParamControls(l10n, modelInChannel, appState),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVideoParamControls(
    AppLocalizations l10n,
    LLMModel model,
    AppState appState,
  ) {
    final caps = ModelCapabilities.forModel(model.modelId);
    if (caps.videoParams.isEmpty) return const SizedBox.shrink();

    // Rebuild when a param changes.
    context.select<AppState, int>((s) => s.videoParamsRevision);

    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final spec in caps.videoParams) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(
                  width: 80,
                  child: Text(_videoParamLabel(l10n, spec.labelKey),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                ),
                Expanded(
                  child: _buildVideoParamControl(spec, model.modelId, appState, colorScheme, l10n),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVideoParamControl(
    ParamSpec spec,
    String modelId,
    AppState appState,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    final current = appState.getVideoParam(modelId, spec);
    switch (spec.control) {
      case ParamControl.dropdown:
        return DropdownButton<String>(
          isExpanded: true,
          value: current,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurface),
          underline: Container(height: 1, color: colorScheme.outlineVariant),
          items: spec.options
              .map((o) => DropdownMenuItem(
                    value: o.value,
                    child: Text(_videoOptionLabel(l10n, spec.key, o.value)),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) appState.setVideoParam(modelId, spec.key, v);
          },
        );
      case ParamControl.segmented:
        return AppSegmentedControl<String>(
          segments: spec.options
              .map((o) => AppSegment(
                    value: o.value,
                    label: _videoOptionLabel(l10n, spec.key, o.value),
                  ))
              .toList(),
          value: current,
          onChanged: (v) => appState.setVideoParam(modelId, spec.key, v),
          compact: true,
          // `17b` draws 时长 and 质量 as equal shares with the chosen one
          // lifted out on white — the same control the image panel's 质量 row
          // takes, and for the same reason.
          expand: true,
          style: AppSegmentStyle.raised,
        );
      case ParamControl.customSize:
        // Not currently used by any video family — video panels render their
        // own resolution + aspect controls. Render a disabled placeholder
        // rather than silently throw if a future family opts in.
        return const SizedBox.shrink();
      case ParamControl.slider:
        final lo = spec.min ?? 1;
        final hi = spec.max ?? 15;
        final parsed = int.tryParse(current) ?? int.tryParse(spec.defaultValue) ?? lo;
        final value = parsed < lo ? lo : (parsed > hi ? hi : parsed);
        return Row(
          children: [
            Expanded(
              child: Slider(
                value: value.toDouble(),
                min: lo.toDouble(),
                max: hi.toDouble(),
                divisions: hi - lo,
                label: '${value}s',
                onChanged: (v) => appState.setVideoParam(modelId, spec.key, v.round().toString()),
              ),
            ),
            SizedBox(
              width: 30,
              child: Text(
                '${value}s',
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurface),
              ),
            ),
          ],
        );
    }
  }

  String _videoParamLabel(AppLocalizations l10n, String labelKey) {
    switch (labelKey) {
      case 'videoSeconds':
        return l10n.videoSeconds;
      case 'quality':
        return l10n.quality;
      case 'aspectRatio':
        return l10n.aspectRatio;
      case 'resolution':
        return l10n.resolution;
      default:
        return labelKey;
    }
  }

  String _videoOptionLabel(AppLocalizations l10n, String paramKey, String value) {
    if (value == 'not_set') return l10n.optionAuto;
    if (paramKey == 'videoQuality') {
      switch (value) {
        case 'standard':
          return l10n.videoQualityStandard;
        case 'high':
          return l10n.videoQualityHigh;
      }
    }
    if (paramKey == 'seconds') return '${value}s';
    return value;
  }
}

class _FrameDropTarget extends StatelessWidget {
  final String label;
  final AppImage? image;
  final Function(AppImage) onDrop;
  final VoidCallback onClear;
  final String dropHint;
  final Color? emptyColor;
  final IconData emptyIcon;

  const _FrameDropTarget({
    required this.label,
    required this.image,
    required this.onDrop,
    required this.onClear,
    required this.dropHint,
    this.emptyColor,
    this.emptyIcon = Icons.add_photo_alternate_outlined,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final bool isMobile = Responsive.isMobile(context);
    final bgColor = emptyColor ?? colorScheme.surfaceContainerHighest.withValues(alpha: 0.3);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        DropTarget(
          onDragDone: (details) {
            if (details.files.isNotEmpty) {
              final file = details.files.first;
              if (AppConstants.isImageFile(file.path)) {
                onDrop(AppImage(path: file.path, name: file.name));
              }
            }
          },
          child: DragTarget<AppImage>(
            onAcceptWithDetails: (details) => onDrop(details.data),
            builder: (context, candidateData, rejectedData) {
              return AspectRatio(
                aspectRatio: isMobile ? 16 / 9 : 1, // Wider on mobile to save vertical space
                child: Container(
                  decoration: BoxDecoration(
                    color: candidateData.isNotEmpty
                        ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                        : bgColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: candidateData.isNotEmpty ? colorScheme.primary : colorScheme.outlineVariant,
                      width: candidateData.isNotEmpty ? 2 : 1,
                      style: image == null ? BorderStyle.solid : BorderStyle.none,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      if (isMobile) {
                        Provider.of<AppState>(context, listen: false).setWorkbenchTab(0);
                      }
                    },
                    child: image != null
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              Image(image: image!.imageProvider, fit: BoxFit.cover),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: IconButton.filledTonal(
                                  onPressed: onClear,
                                  icon: const Icon(Icons.close, size: 16),
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints.tightFor(width: 24, height: 24),
                                ),
                              ),
                            ],
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(emptyIcon, color: colorScheme.outline),
                              if (isMobile) ...[
                                const SizedBox(height: 4),
                                Text(l10n.tapToPick, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colorScheme.outline)),
                              ],
                            ],
                          ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ReferenceImagesTarget extends StatelessWidget {
  final List<AppImage> images;
  final Function(AppImage) onDrop;
  final Function(AppImage) onRemove;
  final String dropHint;

  const _ReferenceImagesTarget({
    required this.images,
    required this.onDrop,
    required this.onRemove,
    required this.dropHint,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DropTarget(
      onDragDone: (details) {
        for (var file in details.files) {
          if (AppConstants.isImageFile(file.path)) {
            onDrop(AppImage(path: file.path, name: file.name));
          }
        }
      },
      child: DragTarget<AppImage>(
        onAcceptWithDetails: (details) => onDrop(details.data),
        builder: (context, candidateData, rejectedData) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: candidateData.isNotEmpty
                  ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3), 
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: candidateData.isNotEmpty ? colorScheme.primary : colorScheme.outlineVariant,
                width: candidateData.isNotEmpty ? 2 : 1,
              ),
            ),
            child: images.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      children: [
                        Icon(Icons.collections_outlined, color: colorScheme.outline),
                        const SizedBox(height: 8),
                        Text(
                          dropHint,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colorScheme.outline),
                        ),
                      ],
                    ),
                  )
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: images.map((img) => _ReferenceThumbnail(
                      image: img,
                      onRemove: () => onRemove(img),
                    )).toList(),
                  ),
          );
        },
      ),
    );
  }
}

class _ReferenceThumbnail extends StatelessWidget {
  final AppImage image;
  final VoidCallback onRemove;

  const _ReferenceThumbnail({required this.image, required this.onRemove});     

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image(
            image: image.imageProvider,
            width: 60,
            height: 60,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
              child: const Icon(Icons.close, size: 12, color: Colors.white),    
            ),
          ),
        ),
      ],
    );
  }
}
