import 'dart:async';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../../core/app_semantic_colors.dart';
import '../../../../core/app_theme.dart';
import '../../../../core/constants.dart';
import '../../../../core/design_tokens.dart';
import '../../../../core/responsive.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/app_image.dart';
import '../../../../models/llm_channel.dart';
import '../../../../models/llm_model.dart';
import '../../../../models/prompt.dart';
import '../../../../models/prompt_history_entry.dart';
import '../../../../models/tag.dart';
import '../../../../services/llm/model_capabilities.dart';
import '../../../../state/app_state.dart';
import '../../../../state/workbench_ui_state.dart';
import '../../../../widgets/drag/app_drag_session.dart';
import '../../../../widgets/drag/app_drop_zone.dart';
import '../../../../widgets/files/file_visuals.dart';
import '../../../../widgets/models/model_picker_options.dart';
import '../../../../widgets/ui/app_dropdown.dart';
import '../../../../widgets/ui/app_field_size.dart';
import '../../../../widgets/ui/app_segmented_control.dart';
import '../../../../widgets/ui/app_snackbar.dart';
import '../../../../widgets/ui/app_switch.dart';
import '../../../../widgets/ui/markdown_editor.dart';
import '../../../../widgets/ui/scroll_edge_fade.dart';
import '../../../../widgets/ui/searchable_picker.dart';
import '../config/config_action_bar.dart';
import '../config/library_dialog.dart';
import '../config/prompt_history_dialog.dart';
import '../config/queue_settings_dialog.dart';

part 'video_drop_parts.dart';
part 'video_frame_slots.dart';
part 'video_model_section.dart';
part 'video_panel_chrome.dart';
part 'video_param_controls.dart';
part 'video_reference_images.dart';

/// Space between two cards in the column, and the column's own inset
/// (`A2 · 1a`: `padding:10; gap:10`, the same column as `A1`).
const double _kCardGap = AppSpace.s10;

/// A card's inset (「右面板卡 r16 pad 10」).
const double _kCardPadding = AppSpace.s10;

/// Rhythm between the rows inside a card (`gap:8`).
const double _kCardInnerGap = 8;

/// Gap between the cells of the parameter grid (`gap:6`).
const double _kParamGap = AppSpace.s6;

/// A parameter cell's control. `A2 · 1a`'s frame draws these at 30, but its
/// size table says 「其余同 A1」 and A1's says 「输入 32」; the image panel's
/// grid is 32, and 30 put these a step shorter than the pickers above them.
const double _kParamControlHeight = AppSize.control;

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

  /// The head's natural height, as last laid out, and the key that carries it
  /// between the split and the single-scroll column without remounting it.
  /// Null until the first layout.
  double? _headExtent;
  final GlobalKey _headKey = GlobalKey();

  /// [setState] for the builders in the parts. They are extensions on this
  /// class, and an extension may not call a protected member itself.
  void _rebuild(VoidCallback fn) => setState(fn);

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
      'referenceImagePaths': uiState.videoReferenceImages.map((i) => i.path).toList(),
      'firstFramePath': uiState.videoFirstFrame?.path,
      'lastFramePath': uiState.videoLastFrame?.path,
      // Every video control is declared per family (resolution, ratio,
      // seconds, quality…); only what the model declares is sent.
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
                      onDrop: uiState.setVideoFirstFrame,
                      onClear: () => uiState.setVideoFirstFrame(null),
                      emptyIcon: Icons.first_page,
                      emptyTitle: l10n.dropFirstFrame,
                      confirmMessage: l10n.dropSetAsFirstFrame,
                    ),
                  ),
                  const SizedBox(width: _kCardInnerGap),
                  Expanded(
                    child: _FrameDropTarget(
                      label: l10n.lastFrame,
                      image: uiState.videoLastFrame,
                      onDrop: uiState.setVideoLastFrame,
                      onClear: () => uiState.setVideoLastFrame(null),
                      emptyIcon: Icons.last_page,
                      emptyTitle: l10n.dropLastFrame,
                      confirmMessage: l10n.dropSetAsLastFrame,
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
            onDrop: uiState.addVideoReferenceImage,
            onRemove: uiState.removeVideoReferenceImage,
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
                      onMarkdownChanged: appState.setIsMarkdownWorkbench,
                      maxLines: 8,
                      hint: l10n.promptHint,
                      // Silent draft path — typing here must not notify the whole app.
                      // See AppStateWorkbench.setVideoPromptDraft.
                      onChanged: appState.setVideoPromptDraft,
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

                final Widget measuredHead = KeyedSubtree(
                  key: _headKey,
                  child: _ExtentReporter(
                    onExtent: (extent) {
                      if (!mounted || extent == _headExtent) return;
                      setState(() => _headExtent = extent);
                    },
                    child: head,
                  ),
                );
                final double headRoom = box.maxHeight - promptFloor;
                // Scroll as one when the head does not fit above the prompt
                // floor. Pinning a head taller than its room clipped it inside
                // its own scroll — at 1440×900 with the console open the
                // reference card showed one strip of thumbnails, and the
                // edge fade hid that there was more. The head lays out at its
                // natural height in both arrangements, so the measurement is
                // the same either side of the switch and cannot oscillate.
                if (headRoom < _kMinHeadHeight ||
                    (_headExtent != null && _headExtent! > headRoom)) {
                  return ScrollEdgeFade(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          measuredHead,
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
                      constraints: BoxConstraints(maxHeight: headRoom),
                      child: ScrollEdgeFade(
                        child: SingleChildScrollView(child: measuredHead),
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

}
