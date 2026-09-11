import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_semantic_colors.dart';
import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../models/app_image.dart';
import '../../models/llm_channel.dart';
import '../../models/llm_model.dart';
import '../../models/prompt.dart';
import '../../models/prompt_history_entry.dart';
import '../../models/tag.dart';
import '../../state/app_state.dart';
import '../../state/gallery_state.dart';
import '../../state/workbench_ui_state.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/app_switch.dart';
import '../../widgets/dashed_border.dart';
import '../../widgets/dialogs/library_dialog.dart';
import '../../widgets/dialogs/prompt_history_dialog.dart';
import '../../widgets/markdown_editor.dart';
import '../../widgets/scroll_edge_fade.dart';
import 'model_selection_section.dart';
import 'widgets/config_action_bar.dart';
import 'widgets/queue_settings_dialog.dart';

/// Shortest the prompt editor — with the footer row under it — is allowed to
/// be reported as.
///
/// Not a layout minimum — inside its [Expanded] the editor is whatever height
/// is left. This is the height the card claims when asked how tall it *wants*
/// to be, which is what decides when the panel starts scrolling instead of
/// squeezing. An `expands: true` field answers zero on its own, so without a
/// figure here the panel would happily crush the editor to nothing before
/// giving the user a scrollbar.
///
/// 220 is about eight lines at the editor's own type scale — enough that a
/// prompt is still being written rather than peeked at.
const double kMinPromptEditorHeight = 220;

/// Space between two cards in the column, and the column's own inset
/// (`A1 · 1a`: `padding:10; gap:10`).
const double _kCardGap = AppSpace.s10;

/// A card's inset (`A1 · 1a` 「右面板卡 r16 pad 10」).
const double _kCardPadding = AppSpace.s10;

/// Rhythm between the rows inside a card (`A1 · 1a`: `gap:8`).
const double _kCardInnerGap = 8;

/// The prompt card's header row: its caption and the two 28px icon actions.
const double _kPromptHeaderRow = AppSize.compact;

/// Everything the prompt card spends above and around [kMinPromptEditorHeight]:
/// its inset top and bottom, the header row and the gap under it.
///
/// Pinned rather than measured. It is the one term the head's cap is computed
/// from besides the editor's floor, so a header that quietly grew would eat
/// that floor with nothing to say it had. (Measuring it instead is what the
/// panel's old [IntrinsicHeight] did, and what a [LayoutBuilder] anywhere in
/// the column makes impossible; see the desktop branch of `build`.)
const double _kPromptCardChrome = _kCardPadding * 2 + _kPromptHeaderRow + _kCardInnerGap;

/// The least the head is worth pinning for.
///
/// Under this the panel gives up on holding the prompt's footer in place and
/// scrolls as one, the way the bottom sheet does — a head squeezed to a
/// sliver is not a layout anyone wanted, it is just the arithmetic running
/// out.
const double _kMinHeadHeight = 120;

/// The selection strip's thumbnails (`A1 · 1a` 「88px 缩略 · 序号」).
const double _kThumbSize = 88;
const double _kThumbBadge = 18;
const double _kThumbInset = 6;

/// How far the thumbnail being dragged rises out of the strip.
const double _kThumbLift = 3;

/// A request toggle's row (`A1 · 1a`: `height:36`).
const double _kToggleRowHeight = 36;

class WorkbenchConfigPanel extends StatefulWidget {
  final ScrollController? scrollController;
  const WorkbenchConfigPanel({super.key, this.scrollController});

  @override
  State<WorkbenchConfigPanel> createState() => _WorkbenchConfigPanelState();
}

class _WorkbenchConfigPanelState extends State<WorkbenchConfigPanel> {
  late MarkdownTextEditingController _promptController;

  bool _isModelSettingsExpanded = false;

  List<Prompt> _allUserPrompts = [];
  List<PromptTag> _tags = [];

  @override
  void initState() {
    super.initState();
    final appState = Provider.of<AppState>(context, listen: false);
    _promptController = MarkdownTextEditingController(text: appState.lastPrompt);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPrompts());
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  // Reloads prompts via AppState
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

  void _updateConfig({
    int? modelDbId,
    String? modelIdStr,
    String? prompt,
    bool? useStream,
    bool? compressReferenceImages,
  }) {
    final appState = Provider.of<AppState>(context, listen: false);

    String? idToSave;
    if (modelDbId != null) {
      idToSave = modelDbId.toString(); // Save PK as string
    }

    appState.updateWorkbenchConfig(
      modelId: idToSave ?? modelIdStr,
      prompt: prompt,
      useStream: useStream,
      compressReferenceImages: compressReferenceImages,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Select specific values to rebuild on change
    final imageModels = context.select<AppState, List<LLMModel>>((s) => s.imageModels);
    // The channels that serve an image model, derived once per data load in
    // `AppState._cacheData` rather than filtered here. Selecting the narrow
    // view also means adding a chat-only channel no longer rebuilds this panel.
    final imageChannels = context.select<AppState, List<LLMChannel>>((s) => s.imageChannels);
    final isMarkdownWorkbench = context.select<AppState, bool>((s) => s.isMarkdownWorkbench);
    final lastSelectedModelId = context.select<AppState, String?>((s) => s.lastSelectedModelId);
    final lastPrompt = context.select<AppState, String>((s) => s.lastPrompt);
    final useStream = context.select<AppState, bool>((s) => s.useStream);
    final compressReferenceImages = context.select<AppState, bool>((s) => s.compressReferenceImages);
    final promptHistory = context.select<AppState, List<PromptHistoryEntry>>((s) => s.imagePromptHistory);
    // Rebuild parameter controls when the stored image params change.
    context.select<AppState, int>((s) => s.imageParamsRevision);

    // Determine selected model from AppState
    int? selectedModelDbId;
    int? selectedChannelId;
    LLMModel? resolvedModel;

    if (imageModels.isNotEmpty) {
      final savedModelId = lastSelectedModelId;
      // `int.tryParse` once, rather than `m.id.toString()` per model: the id is
      // written to the setting as a stringified int, so the old comparison
      // allocated a throwaway String for every model ahead of the match.
      final savedDbId = int.tryParse(savedModelId ?? '');
      LLMModel? match;
      for (final m in imageModels) {
        if (m.id == savedDbId || m.modelId == savedModelId) {
          match = m;
          break;
        }
      }

      final resolved = match ?? imageModels.first;
      selectedModelDbId = resolved.id;
      selectedChannelId = resolved.channelId;
      resolvedModel = resolved;
    }

    final appState = Provider.of<AppState>(context, listen: false);

    // BUT only if we are NOT currently on the optimizer tab to avoid overriding work-in-progress
    if (appState.workbenchTabIndex != 4 && _promptController.text != lastPrompt) {
      _promptController.value = _promptController.value.copyWith(
        text: lastPrompt,
        selection: TextSelection.collapsed(offset: lastPrompt.length),
      );
    }
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final l10n = AppLocalizations.of(context)!;

    // The bottom sheet is this panel's phone form: the layout opens it below
    // the 600 breakpoint and nowhere else, so it is also what decides the
    // touch-sized Process button.
    final bool inSheet = widget.scrollController != null;

    // `A1 · 1a`: the 11/500 tracked caption in the deep ink that heads a card.
    final captionStyle = textTheme.labelSmall?.copyWith(
      letterSpacing: AppType.trackedLabelSpacing,
      color: colorScheme.onAccentTint,
    );

    // Lives in the editor's own footer rather than beside the Process
    // button. Handing the draft to the assistant is a step *on the
    // prompt*, and at the bottom of the panel it was an outlined bar the
    // same width as the one button that actually runs the model -- two
    // equals, where there is only one primary action.
    final editorActions = Row(
      children: [
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            // `1a`: auto_awesome 14 and the label in the deep ink, no ground.
            child: AppButton(
              label: l10n.sendToOptimizer,
              icon: Icons.auto_awesome,
              variant: AppButtonVariant.text,
              size: AppButtonSize.compact,
              onPressed: () {
                final appState = Provider.of<AppState>(context, listen: false);
                final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);

                workbenchUIState.sendToOptimizer(
                  _promptController.text,
                  appState.selectedImages,
                );

                appState.setWorkbenchTab(4);

                if (widget.scrollController != null) {
                  Navigator.pop(context);
                }
              },
            ),
          ),
        ),
        // A bare glyph inside a card, as `1a` draws it: an outlined box here
        // reads as a third control on a row that has two.
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          tooltip: l10n.queueSettings,
          style: _cardIconStyle(colorScheme, colorScheme.onSurfaceVariant),
          onPressed: () => showQueueSettingsDialog(context),
        ),
      ],
    );

    // Everything above the prompt: what is selected, which model runs it,
    // and the two request switches. Fixed content — it is as tall as it is
    // — so on the desktop sidebar this is the half that gets a scroller
    // when the window is short, and the prompt below keeps its height.
    final Widget head = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Off GalleryState, which owns the selection — AppState no longer
        // re-broadcasts it.
        Selector<GalleryState, List<AppImage>>(
          selector: (_, s) => s.selectedImages,
          builder: (context, selectedImages, _) =>
              _buildSelectionCard(context, resolvedModel, selectedImages, l10n),
        ),
        const SizedBox(height: _kCardGap),
        _PanelCard(
          child: ModelSelectionSection(
            availableModels: imageModels,
            // Only offer channels that actually serve image models — a
            // chat-only channel (e.g. DeepSeek) has nothing selectable here.
            channels: imageChannels,
            selectedChannelId: selectedChannelId,
            selectedModelDbId: selectedModelDbId,
            isExpanded: _isModelSettingsExpanded,
            onToggleExpansion: () => setState(() => _isModelSettingsExpanded = !_isModelSettingsExpanded),
            onChannelChanged: (val) {
              final appState = Provider.of<AppState>(context, listen: false);
              // Pick the first *image* model of the channel. Using the
              // unfiltered model list here used to select a chat model,
              // which imageModels can't resolve — the selection silently
              // reverted and the channel appeared unclickable.
              final firstInChannel =
                  appState.imageModels.where((m) => m.channelId == val).firstOrNull;
              final newDbId = firstInChannel?.id;
              if (newDbId != null) {
                _updateConfig(modelDbId: newDbId);
              }
            },
            onModelChanged: (val) {
              _updateConfig(modelDbId: val);
            },
            imageParamResolver: (model, spec) =>
                Provider.of<AppState>(context, listen: false).getImageParam(model, spec),
            onImageParamChanged: (model, key, value) =>
                Provider.of<AppState>(context, listen: false).setImageParam(model, key, value),
            capabilitiesOf: (model) =>
                Provider.of<AppState>(context, listen: false).descriptorForModel(model).capabilities,
          ),
        ),
        const SizedBox(height: _kCardGap),
        // `1a`: a tighter card, the two rows split by a hairline.
        _PanelCard(
          padding: const EdgeInsets.symmetric(horizontal: _kCardPadding, vertical: AppSpace.s4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ToggleRow(
                title: l10n.useStreaming,
                hint: l10n.useStreamingDesc,
                value: useStream,
                onChanged: (v) => _updateConfig(useStream: v),
              ),
              const Divider(),
              _ToggleRow(
                title: l10n.compressReferenceImages,
                hint: l10n.compressReferenceImagesDesc,
                value: compressReferenceImages,
                onChanged: (v) => _updateConfig(compressReferenceImages: v),
              ),
            ],
          ),
        ),
      ],
    );

    // The prompt card: caption and its two actions, then the editor and its
    // footer. `fill: true` lets the card take whatever height the column
    // leaves it. Only the desktop sidebar passes it — the mobile bottom sheet
    // is scrolled by a controller above this widget, where the height is
    // unbounded and a flex child throws.
    Widget buildPrompt({required bool fill}) => _PanelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
            children: [
              // Given exactly its pinned height, not allowed to size itself:
              // [PromptHistoryButton] brings a padded tap target on touch
              // platforms (40 at its compact density), and a row that grew to
              // hold it would take those pixels out of the editor's floor.
              // Pinned, the target is clamped to the row instead.
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
                    PromptHistoryButton(
                      entries: promptHistory,
                      type: PromptHistoryType.image,
                      onApply: (content) {
                        _promptController.text = content;
                        _updateConfig(prompt: content);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.library_books_outlined),
                      tooltip: l10n.library,
                      style: _cardIconStyle(colorScheme, colorScheme.onAccentTint),
                      onPressed: _allUserPrompts.isEmpty ? null : () => _showPromptPickerMenu(l10n),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: _kCardInnerGap),
              _fillable(
                fill: fill,
                child: ConstrainedBox(
                  // A floor for the bottom sheet, where nothing else bounds the
                  // card. Under the desktop [Expanded] the height is already
                  // tight and this is a no-op.
                  constraints: const BoxConstraints(minHeight: kMinPromptEditorHeight),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
                    children: [
                      _fillable(
                        fill: fill,
                        child: MarkdownEditor(
                          controller: _promptController,
                          label: l10n.prompt,
                          isMarkdown: isMarkdownWorkbench,
                          onMarkdownChanged: (v) =>
                              Provider.of<AppState>(context, listen: false).setIsMarkdownWorkbench(v),
                          maxLines: 15,
                          initiallyPreview: false,
                          hint: l10n.promptHint,
                          // Not _updateConfig: keystrokes take the silent draft
                          // path so typing does not notify the whole app. See
                          // AppStateWorkbench.setPromptDraft.
                          onChanged: (v) => appState.setPromptDraft(v),
                          expand: fill,
                          // Filling, the height is handed down and there is
                          // nothing to measure; only the bottom sheet, where
                          // the card sizes itself, still probes.
                          probeAvailableHeight: !fill,
                          // `1a` draws the editor as its own box inside the
                          // card, under the markdown controls row.
                          bordered: true,
                        ),
                      ),
                      const SizedBox(height: _kCardInnerGap),
                      editorActions,
                    ],
                  ),
                ),
              ),
            ],
          ),
        );

    // Primary Execution Button — reused in both mobile (pinned) and desktop (docked)
    //
    // The enabled state hangs off the controller directly rather than off a
    // panel rebuild: typing no longer notifies [AppState] (see
    // setPromptDraft), so nothing else would re-run this. Listening to the
    // controller keeps the button live at the cost of rebuilding one button
    // per keystroke instead of the whole sidebar.
    final processButton = Selector<GalleryState, int>(
      selector: (_, s) => s.selectedImages.length,
      builder: (context, selectedCount, _) => ValueListenableBuilder<TextEditingValue>(
        valueListenable: _promptController,
        builder: (context, promptValue, _) {
          final bool enabled = promptValue.text.isNotEmpty;
          return DecoratedBox(
            // `1a` lifts the live button on a glow in its own ring colour;
            // the disabled one (`1c`) sits flat on the track.
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.control),
              boxShadow: enabled
                  ? [BoxShadow(color: colorScheme.accentRing, blurRadius: 12, offset: const Offset(0, 4))]
                  : null,
            ),
            // Colours, radius and the 13/600 label are the theme's; only the
            // height is this button's own — 40, or the touch 44 on a phone.
            child: FilledButton(
              onPressed: !enabled
                  ? null
                  : () {
                      final appState = Provider.of<AppState>(context, listen: false);
                      if (selectedModelDbId == null) {
                        AppSnackBar.warning(
                          context,
                          l10n.noModelsConfigured,
                          action: AppSnackBarAction(
                            label: l10n.models,
                            onPressed: () => appState.navigateToScreen(6),
                          ),
                        );
                        return;
                      }

                      final selectedModel = appState.imageModels.firstWhere((m) => m.id == selectedModelDbId);
                      final modelName = selectedModel.modelName;

                      final params = <String, dynamic>{
                        'prompt': _promptController.text,
                        ...appState.effectiveImageParams(selectedModel),
                      };

                      appState.submitTask(selectedModelDbId, params, modelIdDisplay: modelName);

                      if (widget.scrollController != null) {
                        Navigator.pop(context);
                      }

                      AppSnackBar.info(context, l10n.taskSubmitted);
                    },
              style: FilledButton.styleFrom(
                minimumSize: Size(double.infinity, inSheet ? AppSize.touch : AppSize.large),
              ),
              child: Text(
                selectedCount == 0 ? l10n.processPrompt : l10n.processImages(selectedCount),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          );
        },
      ),
    );

    if (inSheet) {
      // Mobile bottom sheet: pin the Process button at the top so it stays
      // visible (`01 · 1h`). The optimizer entry rides with the editor in the
      // scroll body, next to the text it acts on.
      return Column(
        mainAxisSize: MainAxisSize.max,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.s16, AppSpace.s16, AppSpace.s16, AppSpace.s10),
            child: processButton,
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

    // Desktop sidebar (and the tablet end drawer). `A1 · 1a` draws this column
    // with nothing scrolling in it: the prompt card is the flex child and
    // everything else is as tall as it is. So the prompt's own footer —
    // 「发送到提示词助手」 and the queue-settings gear — is always on screen,
    // which is the point of putting them in the card rather than beside the
    // Process button.
    //
    // The whole panel used to be one scroll view sized by an
    // [IntrinsicHeight]: the column asked its children how tall they
    // wanted to be, and whichever was larger — that or the viewport —
    // won. Two things were wrong with it. Once the total went over the
    // viewport *everything* scrolled, footer included, so the two
    // actions the design pins vanished below the fold at any ordinary
    // window height. And measuring intrinsics is impossible through a
    // [LayoutBuilder] — expanding 「模型选择」 mounts two
    // [SearchablePickerField]s, each of which contains one, and the
    // panel threw during layout and rendered blank.
    //
    // So the split is explicit instead: the head gets a cap, the prompt
    // gets the rest. Neither side is measured.
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(_kCardGap),
            child: LayoutBuilder(
              builder: (context, box) {
                // The prompt card's floor, and the gap that separates it from
                // the head.
                const double promptFloor = kMinPromptEditorHeight + _kPromptCardChrome + _kCardGap;

                // Not enough column to hold both. Rather than pin a
                // footer over a head crushed to nothing, fall back to
                // the bottom sheet's arrangement: one scroll, the card
                // at its own natural height.
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
                      // Everything the prompt does not need. The head
                      // shrink-wraps under this and scrolls past it, so
                      // the scroller is invisible until it is needed —
                      // and while the head fits, every extra pixel of
                      // window goes to the editor.
                      constraints: BoxConstraints(
                        maxHeight: box.maxHeight - promptFloor,
                      ),
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
        ConfigActionBar(child: processButton),
      ],
    );
  }

  /// [Expanded] when the column may stretch, the child untouched when it may
  /// not.
  ///
  /// The same subtree is built twice — once for the desktop sidebar, which has
  /// a bounded height, and once for the mobile bottom sheet, which is scrolled
  /// from above and has none. A flex child in the second would throw, so the
  /// difference is one wrapper rather than two copies of the panel.
  static Widget _fillable({required bool fill, required Widget child}) =>
      fill ? Expanded(child: child) : child;

  /// A 28px bare icon action inside a card (`1a` prompt header and footer):
  /// a 16px glyph in [ink], the muted ink when disabled.
  ///
  /// Shrink-wrapped: the prompt header's height is a pinned term of the
  /// panel's arithmetic, and a padded 48px tap target would silently grow it.
  static ButtonStyle _cardIconStyle(ColorScheme colorScheme, Color ink) => IconButton.styleFrom(
        foregroundColor: ink,
        disabledForegroundColor: colorScheme.outline,
        iconSize: AppSize.iconMd,
        minimumSize: const Size.square(AppSize.compact),
        maximumSize: const Size.square(AppSize.compact),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );

  void _showPromptPickerMenu(AppLocalizations l10n) {
    PromptLibrarySheet.show(
      context: context,
      allPrompts: _allUserPrompts,
      tags: _tags,
      initialContent: _promptController.text,
      onApply: (content, isAppend) {
        if (isAppend) {
          final existing = _promptController.text;
          _promptController.text = existing.isEmpty ? content : "$existing\n\n$content";
        } else {
          _promptController.text = content;
        }
        _updateConfig(prompt: _promptController.text);
      },
    );
  }

  Widget _buildSelectionCard(
      BuildContext context, LLMModel? model, List<AppImage> selectedImages, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    if (selectedImages.isEmpty) {
      // `A1` 「未选 = 虚线卡」: the 16:9 slot the selection will fill, drawn
      // as an empty place rather than as a card with nothing in it.
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: DashedBorder(
          color: colorScheme.outline,
          radius: AppRadius.lg,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.collections_outlined, size: AppSize.iconLg, color: colorScheme.outline),
                const SizedBox(height: AppSpace.s6),
                Text(
                  l10n.noImagesSelected,
                  style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final notice = _buildReferenceImageNotice(context, model, selectedImages.length, l10n);

    // The whole thumbnail is the drag source, as `1a` draws it (no handle
    // glyph): straight away under a mouse, after a long press under a finger
    // so a swipe still scrolls the strip — the split Material's own default
    // handles make.
    final bool touchDrag = switch (theme.platform) {
      TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.fuchsia => true,
      _ => false,
    };

    return _PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.selectedCount(selectedImages.length),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              AppButton(
                label: l10n.clear,
                variant: AppButtonVariant.text,
                size: AppButtonSize.compact,
                onPressed: () => Provider.of<AppState>(context, listen: false).clearImageSelection(),
              ),
            ],
          ),
          const SizedBox(height: _kCardInnerGap),
          SizedBox(
            height: _kThumbSize,
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: false,
              itemCount: selectedImages.length,
              onReorderItem: (oldIndex, newIndex) {
                Provider.of<AppState>(context, listen: false).galleryState.reorderSelectedImages(oldIndex, newIndex);
              },
              // `1a` 「拖动第 3 张」: the picked-up thumbnail rises 3px inside a
              // 2px accent ring, and settles back as it is dropped.
              proxyDecorator: (child, index, animation) {
                if (index >= selectedImages.length) return child;
                return AnimatedBuilder(
                  animation: animation,
                  builder: (context, _) => Material(
                    type: MaterialType.transparency,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(end: AppSpace.s6),
                      child: _SelectionThumb(
                        image: selectedImages[index],
                        index: index,
                        lift: AppMotion.enter.transform(animation.value),
                      ),
                    ),
                  ),
                );
              },
              itemBuilder: (context, index) {
                final image = selectedImages[index];
                final thumb = _SelectionThumb(
                  image: image,
                  index: index,
                  onRemove: () => Provider.of<AppState>(context, listen: false).toggleImageSelection(image),
                );
                return Padding(
                  key: ValueKey(image.path),
                  padding: const EdgeInsetsDirectional.only(end: AppSpace.s6),
                  child: touchDrag
                      ? ReorderableDelayedDragStartListener(index: index, child: thumb)
                      : ReorderableDragStartListener(index: index, child: thumb),
                );
              },
            ),
          ),
          if (notice != null) ...[
            const SizedBox(height: _kCardInnerGap),
            notice,
          ],
        ],
      ),
    );
  }

  /// Warns when the selected model can't use the images the user has picked as
  /// references (Imagen accepts none; OpenAI image caps the count).
  ///
  /// `A1 · 1c` 「琥珀提示条」: 11px warning ink on the warning container, r6.
  /// Null when there is nothing to say.
  Widget? _buildReferenceImageNotice(
      BuildContext context, LLMModel? model, int selectedCount, AppLocalizations l10n) {
    if (model == null || selectedCount == 0) return null;

    // As the channel serves it: a relay model pinned to the Images API has
    // that surface's reference-image ceiling, which its id cannot report.
    final caps = Provider.of<AppState>(context, listen: false).descriptorForModel(model).capabilities;
    String? message;
    if (!caps.supportsReferenceImages) {
      message = l10n.referenceImagesNotSupported;
    } else if (caps.maxReferenceImages != null && selectedCount > caps.maxReferenceImages!) {
      message = l10n.referenceImagesLimited(caps.maxReferenceImages!);
    }
    if (message == null) return null;

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

/// A card in the right column (`A1 · 1a`): the panel's ground, a hairline,
/// r16, inset 10.
///
/// Not [AppCard], whose radius and tones belong to the previous column; this
/// is the column's own card, used for every group in it.
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

/// One picked image in the selection strip: the picture at r10, its send
/// order in an accent disc, and a remove button on the image plate.
class _SelectionThumb extends StatelessWidget {
  const _SelectionThumb({
    required this.image,
    required this.index,
    this.onRemove,
    this.lift = 0,
  });

  final AppImage image;
  final int index;
  final VoidCallback? onRemove;

  /// 0 at rest, 1 fully picked up.
  final double lift;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Widget thumb = SizedBox(
      width: _kThumbSize,
      height: _kThumbSize,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.control),
              child: Image(image: image.imageProvider, fit: BoxFit.cover),
            ),
          ),
          // The same number the grid tile carries, because this is the same
          // fact: the order these are handed to the model. This strip is where
          // the order is actually *edited*, so the two halves of one idea must
          // name a picture the same way.
          Positioned(
            top: _kThumbInset,
            left: _kThumbInset,
            child: Container(
              width: _kThumbBadge,
              height: _kThumbBadge,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: colorScheme.primary, shape: BoxShape.circle),
              child: Text(
                '${index + 1}',
                style: theme.textTheme.labelSmall?.mono.copyWith(
                  color: colorScheme.onPrimary,
                  fontWeight: FontWeight.w600,
                  height: 1,
                ),
              ),
            ),
          ),
          // On the fixed image plate, never the theme: this sits on the user's
          // own photograph, where a tinted chip disappears into a picture in
          // that hue.
          Positioned(
            top: _kThumbInset,
            right: _kThumbInset,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: _kThumbBadge,
                height: _kThumbBadge,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppOverlay.imagePlate, shape: BoxShape.circle),
                child: const Icon(Icons.close, size: AppSize.iconSm, color: AppOverlay.onImagePlate),
              ),
            ),
          ),
        ],
      ),
    );

    if (lift > 0) {
      final double t = lift.clamp(0.0, 1.0);
      thumb = Transform.translate(
        offset: Offset(0, -_kThumbLift * t),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.control),
            boxShadow: [
              BoxShadow(color: colorScheme.primary.withValues(alpha: t), spreadRadius: 2),
            ],
          ),
          child: thumb,
        ),
      );
    }
    return thumb;
  }
}

/// A request toggle (`A1 · 1a` 「开关卡」): the label, its hint inline in the
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
          // Only felt when a long hint wraps: a second line never touches the
          // hairline beside it.
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
