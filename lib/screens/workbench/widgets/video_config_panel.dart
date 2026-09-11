import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/app_semantic_colors.dart';
import '../../../core/app_theme.dart';
import '../../../core/constants.dart';
import '../../../core/design_tokens.dart';
import '../../../core/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/app_image.dart';
import '../../../models/llm_channel.dart';
import '../../../models/llm_model.dart';
import '../../../models/prompt.dart';
import '../../../models/prompt_history_entry.dart';
import '../../../models/tag.dart';
import '../../../services/llm/model_capabilities.dart';
import '../../../state/app_state.dart';
import '../../../state/workbench_ui_state.dart';
import '../../../widgets/app_dropdown.dart';
import '../../../widgets/app_field_size.dart';
import '../../../widgets/app_segmented_control.dart';
import '../../../widgets/app_snackbar.dart';
import '../../../widgets/app_switch.dart';
import '../../../widgets/dashed_border.dart';
import '../../../widgets/dialogs/library_dialog.dart';
import '../../../widgets/dialogs/prompt_history_dialog.dart';
import '../../../widgets/markdown_editor.dart';
import '../../../widgets/models/model_picker_options.dart';
import '../../../widgets/scroll_edge_fade.dart';
import '../../../widgets/searchable_picker.dart';
import 'config_action_bar.dart';
import 'queue_settings_dialog.dart';

/// Space between two cards in the column, and the column's own inset
/// (`A2 · 1a`: `padding:10; gap:10`, the same column as `A1`).
const double _kCardGap = AppSpace.s10;

/// A card's inset (「右面板卡 r16 pad 10」).
const double _kCardPadding = AppSpace.s10;

/// Rhythm between the rows inside a card (`gap:8`).
const double _kCardInnerGap = 8;

/// Gap between the cells of the parameter grid (`gap:6`).
const double _kParamGap = AppSpace.s6;

/// A parameter cell's control (`A2 · 1a`: `height:30`).
const double _kParamControlHeight = 30;

/// The prompt card's header row: its caption and the two 28px icon actions.
const double _kPromptHeaderRow = AppSize.compact;

/// Shortest the prompt editor — its markdown header included — is reported
/// as when the column decides between filling and scrolling. See the image
/// panel's `kMinPromptEditorHeight` for the reasoning; the video column's
/// head is taller, so its floor is lower.
const double _kMinPromptEditorHeight = 160;

/// Everything the prompt card spends around [_kMinPromptEditorHeight].
const double _kPromptCardChrome = _kCardPadding * 2 + _kPromptHeaderRow + _kCardInnerGap;

/// The least the head is worth pinning for; under it the column scrolls as
/// one.
const double _kMinHeadHeight = 120;

/// A request toggle's row (`A2 · 1a`: `height:36`).
const double _kToggleRowHeight = 36;

/// The empty reference-image drop zone (`A2 · 1b`: `height:76`).
const double _kReferenceZoneHeight = 76;

class VideoConfigPanel extends StatefulWidget {
  final ScrollController? scrollController;
  const VideoConfigPanel({super.key, this.scrollController});

  @override
  State<VideoConfigPanel> createState() => _VideoConfigPanelState();
}

class _VideoConfigPanelState extends State<VideoConfigPanel> {
  late MarkdownTextEditingController _promptController;
  bool _isModelSettingsExpanded = false;

  List<Prompt> _allUserPrompts = [];
  List<PromptTag> _tags = [];

  @override
  void initState() {
    super.initState();
    final appState = Provider.of<AppState>(context, listen: false);
    _promptController = MarkdownTextEditingController(text: appState.lastVideoPrompt);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPrompts());
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _loadPrompts() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final prompts = await appState.getPrompts();
    final tags = await appState.getPromptTags();
    if (mounted) {
      setState(() {
        _allUserPrompts = prompts;
        _tags = tags;
      });
    }
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
      ...appState.effectiveVideoParams(selectedModel),
    };

    appState.submitVideoTask(selectedModel.id, params, modelIdDisplay: selectedModel.modelName);

    AppSnackBar.info(context, l10n.taskSubmitted);
  }

  void _showPromptPickerMenu() {
    PromptLibrarySheet.show(
      context: context,
      allPrompts: _allUserPrompts,
      tags: _tags,
      initialContent: _promptController.text,
      onApply: (content, isAppend) {
        if (isAppend) {
          final existing = _promptController.text;
          _promptController.text = existing.isEmpty ? content : '$existing\n\n$content';
        } else {
          _promptController.text = content;
        }
        Provider.of<AppState>(context, listen: false).updateVideoConfig(prompt: _promptController.text);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final uiState = context.watch<WorkbenchUIState>();
    // Rebuild the parameter grid when a stored video param changes.
    context.select<AppState, int>((s) => s.videoParamsRevision);
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

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
    // A model whose channel is not the selected one is a stale pair; nothing
    // below may describe or edit it under the wrong channel.
    final modelInChannel = selectedModel?.channelId == selectedChannel?.id ? selectedModel : null;
    final caps = modelInChannel == null
        ? const ModelCapabilities()
        : appState.descriptorForModel(modelInChannel).capabilities;

    // The bottom sheet is this panel's phone form: the layout opens it below
    // the 600 breakpoint and nowhere else.
    final bool inSheet = widget.scrollController != null;

    // `A2 · 1a`: the 11/500 tracked caption in the deep ink that heads a card.
    final captionStyle = textTheme.labelSmall?.copyWith(
      letterSpacing: AppType.trackedLabelSpacing,
      color: colorScheme.onAccentTint,
    );

    // Everything above the prompt. Fixed content — on the desktop column this
    // is the half that scrolls when the window is short.
    final Widget head = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _PanelCard(
          child: _buildModelSection(
            l10n: l10n,
            videoModels: videoModels,
            videoChannels: videoChannels,
            selectedChannel: selectedChannel,
            selectedModel: selectedModel,
            modelInChannel: modelInChannel,
            caps: caps,
            appState: appState,
            captionStyle: captionStyle,
          ),
        ),
        const SizedBox(height: _kCardGap),
        // `A2 · 1a` 「帧」: two slots side by side at every width — the phone
        // sheet (`1d`) keeps the pair too, only taller.
        _PanelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.frames, maxLines: 1, overflow: TextOverflow.ellipsis, style: captionStyle),
              const SizedBox(height: _kCardInnerGap),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _FrameDropTarget(
                      label: l10n.firstFrame,
                      image: uiState.videoFirstFrame,
                      onDrop: (img) => uiState.setVideoFirstFrame(img),
                      onClear: () => uiState.setVideoFirstFrame(null),
                      emptyIcon: Icons.first_page,
                    ),
                  ),
                  const SizedBox(width: _kCardInnerGap),
                  Expanded(
                    child: _FrameDropTarget(
                      label: l10n.lastFrame,
                      image: uiState.videoLastFrame,
                      onDrop: (img) => uiState.setVideoLastFrame(img),
                      onClear: () => uiState.setVideoLastFrame(null),
                      emptyIcon: Icons.last_page,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: _kCardGap),
        _PanelCard(
          child: _ReferenceImagesSection(
            images: uiState.videoReferenceImages,
            onDrop: (img) => uiState.addVideoReferenceImage(img),
            onRemove: (img) => uiState.removeVideoReferenceImage(img),
            maxImages: caps.maxReferenceImages,
            captionStyle: captionStyle,
          ),
        ),
        const SizedBox(height: _kCardGap),
        // `1a` 「开关卡」: a tighter card around one 36px row.
        _PanelCard(
          padding: const EdgeInsets.symmetric(horizontal: _kCardPadding, vertical: AppSpace.s4),
          child: _ToggleRow(
            title: l10n.compressReferenceImages,
            hint: l10n.compressReferenceImagesDesc,
            value: appState.compressReferenceImages,
            onChanged: (v) => appState.updateWorkbenchConfig(compressReferenceImages: v),
          ),
        ),
      ],
    );

    // The prompt card. `fill: true` lets it take whatever height the column
    // leaves; only the desktop column passes it — the bottom sheet is scrolled
    // from above, where a flex child throws.
    Widget buildPrompt({required bool fill}) => _PanelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
            children: [
              // Pinned to its height: [PromptHistoryButton] brings a 32px
              // target, which the row clamps to 28 instead of growing.
              SizedBox(
                height: _kPromptHeaderRow,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.prompt,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: captionStyle,
                      ),
                    ),
                    // The history button is shared and styles its own box;
                    // the theme is how its glyph takes the deep ink `1a` draws.
                    IconButtonTheme(
                      data: IconButtonThemeData(
                        style: _cardIconStyle(colorScheme, colorScheme.onAccentTint),
                      ),
                      child: PromptHistoryButton(
                        entries: appState.videoPromptHistory,
                        type: PromptHistoryType.video,
                        onApply: (content) {
                          _promptController.text = content;
                          appState.updateVideoConfig(prompt: content);
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.library_books_outlined),
                      tooltip: l10n.library,
                      style: _cardIconStyle(colorScheme, colorScheme.onAccentTint),
                      onPressed: _allUserPrompts.isEmpty ? null : _showPromptPickerMenu,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: _kCardInnerGap),
              _fillable(
                fill: fill,
                child: ConstrainedBox(
                  // A floor for the bottom sheet; under the desktop
                  // [Expanded] the height is already tight.
                  constraints: const BoxConstraints(minHeight: _kMinPromptEditorHeight),
                  child: _EditorWell(
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
                      expand: fill,
                      probeAvailableHeight: !fill,
                      // The well is the frame; the editor draws its markdown
                      // row inside it over a hairline.
                      bordered: false,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );

    final bool hasModels = videoModels.isNotEmpty;
    // 40 in the column, the touch 44 in the phone sheet (`1d`).
    final double actionHeight = inSheet ? AppSize.touch : AppSize.large;

    // Enabled state hangs off the controller, not off a panel rebuild: typing
    // no longer notifies [AppState], so nothing else re-runs this.
    final generateButton = ValueListenableBuilder<TextEditingValue>(
      valueListenable: _promptController,
      builder: (context, promptValue, _) {
        final bool enabled = hasModels && promptValue.text.isNotEmpty;
        return DecoratedBox(
          // `1a` lifts the live button on a glow in its ring colour; the
          // disabled one (`1b`) sits flat on the track.
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.control),
            boxShadow: enabled
                ? [BoxShadow(color: colorScheme.accentRing, blurRadius: 12, offset: const Offset(0, 4))]
                : null,
          ),
          child: FilledButton(
            onPressed: enabled ? _handleSubmit : null,
            style: FilledButton.styleFrom(
              minimumSize: Size(double.infinity, actionHeight),
            ),
            child: Text(l10n.generateVideo, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        );
      },
    );

    // Queue settings (concurrency / retry / prefix / safety thresholds),
    // shared with the image workbench. `1a`: an outlined neutral square the
    // height of the button beside it.
    final gearButton = IconButton(
      onPressed: () => showQueueSettingsDialog(context),
      icon: const Icon(Icons.settings_outlined),
      tooltip: l10n.queueSettings,
      style: IconButton.styleFrom(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurfaceVariant,
        iconSize: AppSize.iconLg,
        fixedSize: Size.square(actionHeight),
        minimumSize: Size.square(actionHeight),
        maximumSize: Size.square(actionHeight),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: BorderSide(color: colorScheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
      ),
    );

    final actionArea = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // `1b`: with nothing to run, say so beside the button that cannot.
        if (!hasModels) ...[
          _WarningNotice(message: l10n.noModelsConfigured),
          const SizedBox(height: _kCardInnerGap),
        ],
        Row(
          children: [
            Expanded(child: generateButton),
            const SizedBox(width: AppSpace.s6),
            gearButton,
          ],
        ),
      ],
    );

    if (inSheet) {
      // Mobile bottom sheet: Generate pinned at the top (`1d`).
      return Column(
        mainAxisSize: MainAxisSize.max,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.s16, AppSpace.s16, AppSpace.s16, AppSpace.s10),
            child: actionArea,
          ),
          Expanded(
            child: ScrollEdgeFade(
              child: SingleChildScrollView(
                controller: widget.scrollController,
                padding: const EdgeInsets.fromLTRB(AppSpace.s16, 0, AppSpace.s16, AppSpace.s16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    head,
                    const SizedBox(height: _kCardGap),
                    buildPrompt(fill: false),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Desktop column (and the tablet end drawer): the head gets a cap and
    // scrolls under it, the prompt card takes the rest, Generate is docked.
    // The same explicit split as the image panel, for the same reasons.
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(_kCardGap),
            child: LayoutBuilder(
              builder: (context, box) {
                const double promptFloor = _kMinPromptEditorHeight + _kPromptCardChrome + _kCardGap;

                if (box.maxHeight < promptFloor + _kMinHeadHeight) {
                  return ScrollEdgeFade(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          head,
                          const SizedBox(height: _kCardGap),
                          buildPrompt(fill: false),
                        ],
                      ),
                    ),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: box.maxHeight - promptFloor),
                      child: ScrollEdgeFade(
                        child: SingleChildScrollView(child: head),
                      ),
                    ),
                    const SizedBox(height: _kCardGap),
                    Expanded(child: buildPrompt(fill: true)),
                  ],
                );
              },
            ),
          ),
        ),
        ConfigActionBar(child: actionArea),
      ],
    );
  }

  /// [Expanded] when the column may stretch, the child untouched when it may
  /// not.
  static Widget _fillable({required bool fill, required Widget child}) =>
      fill ? Expanded(child: child) : child;

  /// A 28px bare icon action inside a card: a 16px glyph in [ink], the muted
  /// ink when disabled.
  static ButtonStyle _cardIconStyle(ColorScheme colorScheme, Color ink) => IconButton.styleFrom(
        foregroundColor: ink,
        disabledForegroundColor: colorScheme.outline,
        iconSize: AppSize.iconMd,
        fixedSize: const Size.square(AppSize.compact),
        minimumSize: const Size.square(AppSize.compact),
        maximumSize: const Size.square(AppSize.compact),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
      );

  Widget _buildModelSection({
    required AppLocalizations l10n,
    required List<LLMModel> videoModels,
    required List<LLMChannel> videoChannels,
    required LLMChannel? selectedChannel,
    required LLMModel? selectedModel,
    required LLMModel? modelInChannel,
    required ModelCapabilities caps,
    required AppState appState,
    required TextStyle? captionStyle,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final selectedChannelId = selectedChannel?.id;
    final collapsedModelName = _isModelSettingsExpanded ? null : selectedModel?.modelName;

    // Some families (e.g. grok-imagine-video-1.5) declare their own
    // aspectRatio/resolution videoParams with a different option set than
    // the shared Veo dropdowns below — hide the shared control for whichever
    // key that family overrides so the panel doesn't show two conflicting
    // resolution/aspect-ratio pickers.
    final overridesResolution = caps.videoParams.any((p) => p.key == 'resolution');
    final overridesAspectRatio = caps.videoParams.any((p) => p.key == 'aspectRatio');

    // `A2 · 1a`: one two-column grid for every parameter — the shared Veo
    // pair first, then whatever the model declares (duration, quality…).
    final cells = <_ParamCell>[
      if (!overridesResolution)
        _ParamCell(
          label: l10n.videoResolution,
          control: AppDropdown<VeoResolution>(
            size: AppFieldSize.regular,
            height: _kParamControlHeight,
            value: appState.lastVideoResolution,
            items: [
              for (final v in VeoResolution.values) AppDropdownItem(value: v, label: v.value),
            ],
            onChanged: (v) => appState.updateVideoConfig(resolution: v),
          ),
        ),
      if (!overridesAspectRatio)
        _ParamCell(
          label: l10n.videoAspectRatio,
          control: AppDropdown<VeoAspectRatio>(
            size: AppFieldSize.regular,
            height: _kParamControlHeight,
            value: appState.lastVideoAspectRatio,
            items: [
              for (final v in VeoAspectRatio.values) AppDropdownItem(value: v, label: v.value),
            ],
            onChanged: (v) => appState.updateVideoConfig(aspectRatio: v),
          ),
        ),
      // Per-model extras (seconds / quality for openaiVideo; aspectRatio /
      // resolution / seconds slider for grok-imagine-video-1.5; nothing for
      // Veo). `customSize` is not used by any video family and draws nothing.
      if (modelInChannel != null)
        for (final spec in caps.videoParams)
          if (spec.control != ParamControl.customSize)
            _ParamCell(
              label: _videoParamLabel(l10n, spec.labelKey),
              control: _buildVideoParamControl(spec, modelInChannel, appState, l10n),
              spansRow: spec.control == ParamControl.slider ||
                  (spec.control == ParamControl.segmented && spec.options.length > 2),
            ),
    ];

    // `A2 · 1a`: the 11/500 caption and the chevron that folds the card.
    // Collapsed, the header still names the model.
    final header = Semantics(
      expanded: _isModelSettingsExpanded,
      child: InkWell(
        onTap: () => setState(() => _isModelSettingsExpanded = !_isModelSettingsExpanded),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: SizedBox(
          height: AppSize.iconLg,
          child: Row(
            children: [
              Text(l10n.modelSelection, style: captionStyle),
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
                _isModelSettingsExpanded ? Icons.expand_less : Icons.expand_more,
                size: AppSize.iconMd,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );

    final body = Theme(
      // A field inside a card takes the column's ground as its fill, under
      // the theme's own hairline (颜色角色 「输入填充 = col」).
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
          // is kept for screen readers.
          MergeSemantics(
            child: Semantics(
              label: l10n.channel,
              child: SearchablePickerField<int>(
                size: AppFieldSize.regular,
                selected: selectedChannel == null ? null : channelPickerOption(selectedChannel),
                optionsBuilder: () => videoChannels.map(channelPickerOption).toList(),
                onChanged: (val) {
                  final firstVideoInChannel = videoModels.where((m) => m.channelId == val).firstOrNull;
                  if (firstVideoInChannel != null) {
                    appState.updateVideoConfig(modelId: firstVideoInChannel.id.toString());
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
          const SizedBox(height: _kCardInnerGap),
          MergeSemantics(
            child: Semantics(
              label: l10n.model,
              child: SearchablePickerField<int>(
                size: AppFieldSize.regular,
                selected: modelInChannel == null ? null : modelPickerOption(modelInChannel),
                // Built on open, not on build: a relay's worth of video models
                // used to be mounted on every frame to render one line.
                optionsBuilder: () => [
                  for (final m in videoModels)
                    if (m.channelId == selectedChannelId && m.id != null) modelPickerOption(m),
                ],
                onChanged: (val) => appState.updateVideoConfig(modelId: val.toString()),
                hint: l10n.selectAModel,
                searchHint: l10n.searchModels,
                dialogIcon: Icons.memory_outlined,
                enabled: videoModels.any((m) => m.channelId == selectedChannelId),
              ),
            ),
          ),
          if (cells.isNotEmpty) ...[
            const SizedBox(height: _kCardInnerGap),
            _paramGrid(cells),
          ],
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
          child: _isModelSettingsExpanded
              ? Padding(padding: const EdgeInsets.only(top: _kCardInnerGap), child: body)
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  /// Pairs cells into rows of two, in order. A cell that spans the row, or a
  /// half left without a partner, takes the full width.
  static Widget _paramGrid(List<_ParamCell> cells) {
    final rows = <Widget>[];
    _ParamCell? pending;
    for (final cell in cells) {
      if (cell.spansRow) {
        if (pending != null) {
          rows.add(pending);
          pending = null;
        }
        rows.add(cell);
      } else if (pending == null) {
        pending = cell;
      } else {
        rows.add(Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: pending),
            const SizedBox(width: _kParamGap),
            Expanded(child: cell),
          ],
        ));
        pending = null;
      }
    }
    if (pending != null) rows.add(pending);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, row) in rows.indexed) ...[
          if (index > 0) const SizedBox(height: _kParamGap),
          row,
        ],
      ],
    );
  }

  Widget _buildVideoParamControl(
    ParamSpec spec,
    LLMModel model,
    AppState appState,
    AppLocalizations l10n,
  ) {
    final theme = Theme.of(context);
    final current = appState.getVideoParam(model, spec);
    switch (spec.control) {
      case ParamControl.dropdown:
        return AppDropdown<String>(
          size: AppFieldSize.regular,
          height: _kParamControlHeight,
          value: current,
          items: [
            for (final o in spec.options)
              AppDropdownItem(value: o.value, label: _videoOptionLabel(l10n, spec.key, o.value)),
          ],
          onChanged: (v) {
            if (v != null) appState.setVideoParam(model, spec.key, v);
          },
        );
      case ParamControl.segmented:
        // `1a` 「质量」: equal shares on the track, the chosen one lifted out
        // on the panel's ground.
        return AppSegmentedControl<String>(
          segments: spec.options
              .map((o) => AppSegment(
                    value: o.value,
                    label: _videoOptionLabel(l10n, spec.key, o.value),
                  ))
              .toList(),
          value: current,
          onChanged: (v) => appState.setVideoParam(model, spec.key, v),
          compact: true,
          expand: true,
          style: AppSegmentStyle.raised,
        );
      case ParamControl.customSize:
        // Not currently used by any video family — filtered out of the grid.
        return const SizedBox.shrink();
      case ParamControl.slider:
        final lo = spec.min ?? 1;
        final hi = spec.max ?? 15;
        final parsed = int.tryParse(current) ?? int.tryParse(spec.defaultValue) ?? lo;
        final value = parsed < lo ? lo : (parsed > hi ? hi : parsed);
        return SizedBox(
          height: _kParamControlHeight,
          child: Row(
            children: [
              Expanded(
                child: SliderTheme(
                  // Material's 24px overlay would otherwise decide the row's
                  // height instead of the grid's 30.
                  data: SliderTheme.of(context).copyWith(
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  ),
                  child: Slider(
                    value: value.toDouble(),
                    min: lo.toDouble(),
                    max: hi.toDouble(),
                    divisions: hi - lo,
                    label: '${value}s',
                    onChanged: (v) => appState.setVideoParam(model, spec.key, v.round().toString()),
                  ),
                ),
              ),
              SizedBox(
                width: 30,
                child: Text(
                  '${value}s',
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelSmall?.mono.copyWith(color: theme.colorScheme.onSurface),
                ),
              ),
            ],
          ),
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

/// A card in the right column (`A2 · 1a`): the panel's ground, a hairline,
/// r16, inset 10 — the image column's card, restated.
class _PanelCard extends StatelessWidget {
  const _PanelCard({
    required this.child,
    this.padding = const EdgeInsets.all(_kCardPadding),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Material, not a decorated Container, so the ink of the buttons and
    // fields inside lands on it.
    return Material(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: double.infinity,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// The prompt editor's frame (`1a`): the column's ground, r10, a hairline.
class _EditorWell extends StatelessWidget {
  const _EditorWell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// One cell of the parameter grid: an 11px secondary caption over its control.
class _ParamCell extends StatelessWidget {
  const _ParamCell({required this.label, required this.control, this.spansRow = false});

  final String label;
  final Widget control;

  /// A slider, or a segmented track with more than two options, needs the
  /// whole row rather than half of it.
  final bool spansRow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpace.s4),
          control,
        ],
      ),
    );
  }
}

/// A drop place with nothing in it (`A2 · 1a` 尾帧, `1b` 参考图): the
/// column's ground inside a dashed hairline, a glyph and a hint in the muted
/// ink. While something is dragged over it (`1b` 首帧) the ground takes the
/// accent wash, the edge a 2px dashed accent, and the hint the deep ink.
class _DropSlot extends StatelessWidget {
  const _DropSlot({
    required this.hovering,
    required this.icon,
    this.hoverIcon,
    this.hint,
    this.onTap,
  });

  final bool hovering;
  final IconData icon;
  final IconData? hoverIcon;
  final String? hint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final radius = BorderRadius.circular(AppRadius.control);
    final hint = this.hint;

    return Material(
      color: hovering ? colorScheme.accentTint : colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: radius),
      // Unclipped: the dashed stroke is centred on the edge, and a clip would
      // shave its outer half away.
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: DashedBorder(
          color: hovering ? colorScheme.primary : colorScheme.outlineVariant,
          radius: AppRadius.control,
          strokeWidth: hovering ? 2 : 1,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    hovering ? (hoverIcon ?? icon) : icon,
                    size: AppSize.iconLg,
                    color: hovering ? colorScheme.primary : colorScheme.outline,
                  ),
                  if (hint != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      hint,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: hovering ? colorScheme.onAccentTint : colorScheme.outline,
                        fontWeight: hovering ? FontWeight.w500 : FontWeight.w400,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A round close button on the fixed image plate, for a control laid over the
/// user's own picture.
class _PlateCloseButton extends StatelessWidget {
  const _PlateCloseButton({required this.size, required this.tooltip, required this.onPressed});

  final double size;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPressed,
            child: Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppOverlay.imagePlate, shape: BoxShape.circle),
              child: const Icon(Icons.close, size: AppSize.iconSm, color: AppOverlay.onImagePlate),
            ),
          ),
        ),
      ),
    );
  }
}

/// A first- or last-frame slot (`A2 · 1a`): the caption, a 92px place
/// (96 on a tablet, 104 on a phone), and the file's name — or that the frame
/// is optional — under it.
class _FrameDropTarget extends StatefulWidget {
  final String label;
  final AppImage? image;
  final ValueChanged<AppImage> onDrop;
  final VoidCallback onClear;
  final IconData emptyIcon;

  const _FrameDropTarget({
    required this.label,
    required this.image,
    required this.onDrop,
    required this.onClear,
    required this.emptyIcon,
  });

  @override
  State<_FrameDropTarget> createState() => _FrameDropTargetState();
}

class _FrameDropTargetState extends State<_FrameDropTarget> {
  /// A file dragged in from the OS is over the slot. In-app drags report
  /// themselves through the [DragTarget] instead.
  bool _osDragging = false;

  void _setOsDragging(bool value) {
    if (_osDragging != value) setState(() => _osDragging = value);
  }

  /// `1a` 「拖入或点击选择」: a click opens the system picker for one image.
  Future<void> _pickFrame() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    widget.onDrop(AppImage(path: picked.path, name: picked.name));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final l10n = AppLocalizations.of(context)!;
    final bool isMobile = Responsive.isMobile(context);
    final double slotHeight = Responsive.value<double>(context, mobile: 104, tablet: 96, desktop: 92);
    final image = widget.image;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpace.s4),
        DropTarget(
          onDragEntered: (_) => _setOsDragging(true),
          onDragExited: (_) => _setOsDragging(false),
          onDragDone: (details) {
            _setOsDragging(false);
            if (details.files.isNotEmpty) {
              final file = details.files.first;
              if (AppConstants.isImageFile(file.path)) {
                widget.onDrop(AppImage(path: file.path, name: file.name));
              }
            }
          },
          child: DragTarget<AppImage>(
            onAcceptWithDetails: (details) => widget.onDrop(details.data),
            builder: (context, candidateData, rejectedData) {
              final bool hovering = _osDragging || candidateData.isNotEmpty;
              void onTap() {
                if (isMobile) {
                  Provider.of<AppState>(context, listen: false).setWorkbenchTab(0);
                } else {
                  _pickFrame();
                }
              }

              return SizedBox(
                height: slotHeight,
                child: image == null
                    ? _DropSlot(
                        hovering: hovering,
                        icon: widget.emptyIcon,
                        hoverIcon: Icons.download,
                        hint: hovering
                            ? l10n.videoDropRelease
                            : (isMobile ? l10n.tapToPick : l10n.videoDropOrPick),
                        onTap: onTap,
                      )
                    : _FilledFrameSlot(
                        image: image,
                        hovering: hovering,
                        onClear: widget.onClear,
                        onTap: onTap,
                      ),
              );
            },
          ),
        ),
        const SizedBox(height: AppSpace.s4),
        Text(
          image?.name ?? l10n.videoFrameOptional,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.labelSmall?.mono.copyWith(
            fontWeight: FontWeight.w400,
            color: image == null ? colorScheme.outline : colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// A frame slot holding its image: the picture at r10 and a round clear
/// button on the image plate, top-right (20 / 22 / 24 by width).
class _FilledFrameSlot extends StatelessWidget {
  const _FilledFrameSlot({
    required this.image,
    required this.hovering,
    required this.onClear,
    required this.onTap,
  });

  final AppImage image;
  final bool hovering;
  final VoidCallback onClear;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final bool isMobile = Responsive.isMobile(context);
    final double clearSize = Responsive.value<double>(context, mobile: 24, tablet: 22, desktop: 20);
    final double inset = isMobile ? AppSpace.s6 : AppSpace.s4;
    final radius = BorderRadius.circular(AppRadius.control);

    return Material(
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image(image: image.imageProvider, fit: BoxFit.cover),
            // A replacement hovering over a filled slot: the same wash and a
            // solid accent edge, so the picture stays readable under it.
            if (hovering)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.accentTint,
                  borderRadius: radius,
                  border: Border.all(color: colorScheme.primary, width: 2),
                ),
              ),
            Positioned(
              top: inset,
              right: inset,
              child: _PlateCloseButton(size: clearSize, tooltip: l10n.clear, onPressed: onClear),
            ),
          ],
        ),
      ),
    );
  }
}

/// The reference-image card (`A2 · 1a` / `1b`): caption and the "n / max"
/// count, then 64px thumbnails (72 on a phone) followed by an add slot — or,
/// with nothing added yet, one dashed drop zone. The whole card accepts a
/// drop.
class _ReferenceImagesSection extends StatefulWidget {
  const _ReferenceImagesSection({
    required this.images,
    required this.onDrop,
    required this.onRemove,
    required this.maxImages,
    required this.captionStyle,
  });

  final List<AppImage> images;
  final ValueChanged<AppImage> onDrop;
  final ValueChanged<AppImage> onRemove;

  /// The selected model's ceiling (`ModelCapabilities.maxReferenceImages`):
  /// null for no enforced limit, 0 for none accepted.
  final int? maxImages;
  final TextStyle? captionStyle;

  @override
  State<_ReferenceImagesSection> createState() => _ReferenceImagesSectionState();
}

class _ReferenceImagesSectionState extends State<_ReferenceImagesSection> {
  bool _osDragging = false;

  void _setOsDragging(bool value) {
    if (_osDragging != value) setState(() => _osDragging = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final double thumbSize = Responsive.isMobile(context) ? 72 : 64;
    final images = widget.images;
    final max = widget.maxImages;

    return DropTarget(
      onDragEntered: (_) => _setOsDragging(true),
      onDragExited: (_) => _setOsDragging(false),
      onDragDone: (details) {
        _setOsDragging(false);
        for (final file in details.files) {
          if (AppConstants.isImageFile(file.path)) {
            widget.onDrop(AppImage(path: file.path, name: file.name));
          }
        }
      },
      child: DragTarget<AppImage>(
        onAcceptWithDetails: (details) => widget.onDrop(details.data),
        builder: (context, candidateData, rejectedData) {
          final bool hovering = _osDragging || candidateData.isNotEmpty;

          final String? count = max != null && max > 0
              ? '${images.length} / $max'
              : (images.isEmpty ? null : '${images.length}');

          // The model's limits, said where the images are: none accepted, or
          // more added than it will take.
          String? notice;
          if (images.isNotEmpty && max != null) {
            if (max == 0) {
              notice = l10n.referenceImagesNotSupported;
            } else if (images.length > max) {
              notice = l10n.referenceImagesLimited(max);
            }
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.referenceImages,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: widget.captionStyle,
                    ),
                  ),
                  if (count != null)
                    Text(
                      count,
                      style: theme.textTheme.labelSmall?.mono.copyWith(
                        fontWeight: FontWeight.w400,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: _kCardInnerGap),
              if (images.isEmpty)
                SizedBox(
                  height: _kReferenceZoneHeight,
                  child: _DropSlot(
                    hovering: hovering,
                    icon: Icons.add_photo_alternate_outlined,
                    hint: hovering
                        ? l10n.videoDropRelease
                        : (max != null && max > 0
                            ? l10n.videoReferenceDropMax(max)
                            : l10n.dropVideoReferenceHere),
                  ),
                )
              else
                Wrap(
                  spacing: AppSpace.s6,
                  runSpacing: AppSpace.s6,
                  children: [
                    for (final img in images)
                      _ReferenceThumbnail(
                        image: img,
                        size: thumbSize,
                        onRemove: () => widget.onRemove(img),
                      ),
                    if (max == null || images.length < max)
                      SizedBox.square(
                        dimension: thumbSize,
                        child: _DropSlot(hovering: hovering, icon: Icons.add),
                      ),
                  ],
                ),
              if (notice != null) ...[
                const SizedBox(height: _kCardInnerGap),
                _WarningNotice(message: notice),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ReferenceThumbnail extends StatelessWidget {
  final AppImage image;
  final double size;
  final VoidCallback onRemove;

  const _ReferenceThumbnail({required this.image, required this.size, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.control),
              child: Image(image: image.imageProvider, fit: BoxFit.cover),
            ),
          ),
          Positioned(
            top: AppSpace.s4,
            right: AppSpace.s4,
            child: _PlateCloseButton(size: 20, tooltip: l10n.remove, onPressed: onRemove),
          ),
        ],
      ),
    );
  }
}

/// A request toggle (`A2 · 1a` 「开关卡」): the label, its hint inline in the
/// secondary ink, and the switch at the end of a 36px row.
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    // Merged so the switch is announced with the words that name it.
    return MergeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _kToggleRowHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.s4),
          child: Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: title, style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurface)),
                      const WidgetSpan(child: SizedBox(width: AppSpace.s6)),
                      TextSpan(
                        text: hint,
                        style: textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpace.s10),
              AppSwitch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

/// `1b` 「琥珀提示条」: 11px warning ink on the warning container, r6, with a
/// 14px warning glyph.
class _WarningNotice extends StatelessWidget {
  const _WarningNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: AppSpace.s4),
      decoration: BoxDecoration(
        color: semantic.warningContainer,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.warning_amber_rounded, size: AppSize.iconSm, color: semantic.warning),
          ),
          const SizedBox(width: AppSpace.s4),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: semantic.onWarningContainer),
            ),
          ),
        ],
      ),
    );
  }
}
