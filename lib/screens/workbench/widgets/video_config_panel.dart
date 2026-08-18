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
import '../../../widgets/app_button.dart';
import '../../../widgets/app_segmented_control.dart';
import '../../../widgets/app_snackbar.dart';
import '../../../widgets/collapsible_card.dart';
import '../../../widgets/dialogs/prompt_history_dialog.dart';
import '../../../widgets/markdown_editor.dart';
import 'config_action_bar.dart';
import '../../../widgets/app_section_label.dart';
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
    final videoChannels = appState.allChannels.where((c) => videoModels.any((m) => m.channelId == c.id)).toList();

    // Determine selected model
    int? selectedModelDbId;
    int? selectedChannelId;

    if (videoModels.isNotEmpty) {
      final savedModelId = appState.lastVideoModelId;
      final match = videoModels.cast<LLMModel?>().firstWhere(
        (m) => m?.id.toString() == savedModelId || m?.modelId == savedModelId,  
        orElse: () => null,
      );

      if (match != null) {
        selectedModelDbId = match.id;
        selectedChannelId = match.channelId;
      } else {
        selectedModelDbId = videoModels.first.id;
        selectedChannelId = videoModels.first.channelId;
      }
    }

    final bool isMobile = Responsive.isMobile(context);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Model Selection
        _buildModelSection(l10n, videoModels, videoChannels, selectedChannelId, selectedModelDbId, appState, uiState),

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
        MarkdownEditor(
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
        ),
        SwitchListTile(
          title: Text(l10n.compressReferenceImages, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          // Carries the colour the ListTile's own subtitle style supplied, which
          // the slot would otherwise replace with plain onSurface.
          subtitle: Text(l10n.compressReferenceImagesDesc,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          value: appState.compressReferenceImages,
          onChanged: (v) => appState.updateWorkbenchConfig(compressReferenceImages: v),
          secondary: const Icon(Icons.compress, size: 20),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),

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
                    emptyColor: cs.primaryContainer.withValues(alpha: 0.3),
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
                    emptyColor: cs.tertiaryContainer.withValues(alpha: 0.3),
                    emptyIcon: Icons.last_page,
                  ),
                ),
              ],
            );
          },
        ),

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
        IconButton.filledTonal(
          onPressed: () => showQueueSettingsDialog(context),
          icon: const Icon(Icons.settings_outlined, size: 20),
          tooltip: l10n.queueSettings,
          style: IconButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
    List<LLMChannel> allChannels,
    int? selectedChannelId,
    int? selectedModelDbId,
    AppState appState,
    WorkbenchUIState uiState,
  ) {
    String? collapsedModelName;
    if (!_isModelSettingsExpanded && selectedModelDbId != null) {
      final match = videoModels.cast<LLMModel?>().firstWhere(
        (m) => m?.id == selectedModelDbId,
        orElse: () => null,
      );
      collapsedModelName = match?.modelName;
    }

    // Some families (e.g. grok-imagine-video-1.5) declare their own
    // aspectRatio/resolution videoParams with a different option set than
    // the shared Veo dropdowns below — hide the shared control for whichever
    // key that family overrides so the panel doesn't show two conflicting
    // resolution/aspect-ratio pickers.
    final selectedModel = selectedModelDbId == null
        ? null
        : videoModels.cast<LLMModel?>().firstWhere(
            (m) => m?.id == selectedModelDbId,
            orElse: () => null,
          );
    final caps = selectedModel == null
        ? const ModelCapabilities()
        : ModelCapabilities.forModel(selectedModel.modelId);
    final overridesResolution = caps.videoParams.any((p) => p.key == 'resolution');
    final overridesAspectRatio = caps.videoParams.any((p) => p.key == 'aspectRatio');

    final sharedControls = <Widget>[
      if (!overridesResolution)
        Expanded(
          child: DropdownButtonFormField<VeoResolution>(
            decoration: InputDecoration(labelText: l10n.videoResolution),
            initialValue: appState.lastVideoResolution,
            items: VeoResolution.values.map((v) => DropdownMenuItem(
              value: v,
              child: Text(v.value),
            )).toList(),
            onChanged: (v) => appState.updateVideoConfig(resolution: v),
          ),
        ),
      if (!overridesResolution && !overridesAspectRatio) const SizedBox(width: 12),
      if (!overridesAspectRatio)
        Expanded(
          child: DropdownButtonFormField<VeoAspectRatio>(
            decoration: InputDecoration(labelText: l10n.videoAspectRatio),
            initialValue: appState.lastVideoAspectRatio,
            items: VeoAspectRatio.values.map((v) => DropdownMenuItem(
              value: v,
              child: Text(v.value),
            )).toList(),
            onChanged: (v) => appState.updateVideoConfig(aspectRatio: v),
          ),
        ),
    ];

    return CollapsibleCard(
      title: l10n.modelSelection,
      subtitle: collapsedModelName,
      isExpanded: _isModelSettingsExpanded,
      onToggle: () => setState(() => _isModelSettingsExpanded = !_isModelSettingsExpanded),
      content: Column(
        children: [
          DropdownButtonFormField<int>(
            decoration: InputDecoration(labelText: l10n.channel),
            initialValue: selectedChannelId,
            items: allChannels.map((c) => DropdownMenuItem(
              value: c.id,
              child: Text(c.displayName),
            )).toList(),
            onChanged: (val) {
              final firstVideoInChannel = videoModels.where((m) => m.channelId == val).firstOrNull;
              if (firstVideoInChannel != null) {
                appState.updateVideoConfig(modelId: firstVideoInChannel.id.toString());
              }
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            decoration: InputDecoration(labelText: l10n.model),  
            initialValue: selectedModelDbId,
            items: videoModels.where((m) => m.channelId == selectedChannelId).map((m) => DropdownMenuItem(
              value: m.id,
              child: Text(m.modelName),
            )).toList(),
            onChanged: (val) {
              if (val != null) {
                appState.updateVideoConfig(modelId: val.toString());
              }
            },
          ),
          if (sharedControls.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(children: sharedControls),
          ],
          // Per-model extras (seconds / quality for openaiVideo; aspectRatio /
          // resolution / seconds slider for grok-imagine-video-1.5; nothing
          // for Veo). Rebuilds when the user changes a value or switches model.
          if (selectedModelDbId != null) ...[
            const SizedBox(height: 8),
            _buildVideoParamControls(l10n, videoModels, selectedModelDbId, appState),
          ],
        ],
      ),
    );
  }

  Widget _buildVideoParamControls(
    AppLocalizations l10n,
    List<LLMModel> videoModels,
    int selectedModelDbId,
    AppState appState,
  ) {
    final model = videoModels.cast<LLMModel?>().firstWhere(
      (m) => m?.id == selectedModelDbId,
      orElse: () => null,
    );
    if (model == null) return const SizedBox.shrink();

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
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold)),
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
        Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
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
