import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../models/app_image.dart';
import '../../models/llm_channel.dart';
import '../../models/llm_model.dart';
import '../../models/prompt.dart';
import '../../models/prompt_history_entry.dart';
import '../../models/tag.dart';
import '../../services/llm/model_capabilities.dart';
import '../../state/app_state.dart';
import '../../state/gallery_state.dart';
import '../../state/workbench_ui_state.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/dialogs/library_dialog.dart';
import '../../widgets/dialogs/prompt_history_dialog.dart';
import '../../widgets/markdown_editor.dart';
import 'model_selection_section.dart';
import 'widgets/config_action_bar.dart';
import '../../widgets/app_section_label.dart';
import 'widgets/queue_settings_dialog.dart';
import '../../widgets/scroll_edge_fade.dart';

/// Ink laid over a thumbnail. Neutral by construction rather than taken from
/// the [ColorScheme] — these sit on the user's own photographs, where a chip
/// tinted to the theme disappears the moment someone selects a picture in that
/// hue. Mirrors [ImageCard]'s overlay constants; the two strips show the same
/// pictures and must not treat them differently.
const Color _thumbScrim = Color(0x8A000000);
const Color _thumbInk = Color(0xFFFFFFFF);

/// Shortest the prompt editor is allowed to be reported as.
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

/// The 「提示词」 label row above the prompt card.
///
/// Pinned rather than measured, and the row is given exactly this height at
/// the call site rather than allowed to size itself. It is the one term the
/// head's cap is computed from, so a row that quietly grew — a taller trailing
/// button, a wider default padding — would eat the editor's floor with nothing
/// to say it had. (Measuring it instead is what the panel's old
/// [IntrinsicHeight] did, and what a [LayoutBuilder] anywhere in the column
/// makes impossible; see the desktop branch of `build`.)
///
/// 44 is the trailing controls' own 32 plus the spec's breathing room. The
/// row used to come out at 72 — `AppSectionLabel`'s 18px top gap over a
/// full-size text button — where `16a` draws it compact.
const double _kPromptLabelRow = 44;

/// The least the head is worth pinning for.
///
/// Under this the panel gives up on holding the prompt's footer in place and
/// scrolls as one, the way the bottom sheet does — a head squeezed to a
/// sliver is not a layout anyone wanted, it is just the arithmetic running
/// out.
const double _kMinHeadHeight = 120;

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
    String? selectedModelIdStr;

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
      selectedModelIdStr = resolved.modelId;
    }

    final appState = Provider.of<AppState>(context, listen: false);

    // BUT only if we are NOT currently on the optimizer tab to avoid overriding work-in-progress
    if (appState.workbenchTabIndex != 4 && _promptController.text != lastPrompt) {
      _promptController.value = _promptController.value.copyWith(
        text: lastPrompt,
        selection: TextSelection.collapsed(offset: lastPrompt.length),
      );
    }
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    // Use a layout builder to detect if we should be internally scrollable (Desktop sidebar)
    // or if we are being scrolled by an external controller (Mobile BottomSheet)
    return LayoutBuilder(
      builder: (context, constraints) {
        // Lives in the editor's own footer rather than beside the Process
        // button. Handing the draft to the assistant is a step *on the
        // prompt*, and at the bottom of the panel it was an outlined bar the
        // same width as the one button that actually runs the model -- two
        // equals, where there is only one primary action.
        final editorActions = Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: AppButton(
                  label: l10n.sendToOptimizer,
                  icon: Icons.auto_fix_high,
                  variant: AppButtonVariant.text,
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
            // A plain [IconButton], not an [AppIconButton]: this one sits
            // *inside* a card, which is the case that widget's own doc sends
            // elsewhere ("a box around every one of those is noise"). `16a`
            // draws it as a bare 32px glyph, and the outlined box was reading
            // as a third control on a row that already has two.
            IconButton(
              icon: const Icon(Icons.settings_outlined, size: AppSize.iconSm),
              tooltip: l10n.queueSettings,
              color: colorScheme.onSurfaceVariant,
              visualDensity: VisualDensity.compact,
              onPressed: () => showQueueSettingsDialog(context),
            ),
          ],
        );

        // Everything above the prompt: what is selected, which model runs it,
        // and the two request switches. Fixed content — it is as tall as it is
        // — so on the desktop sidebar this is the half that gets a scroller
        // when the window is short, and the prompt below keeps its height.
        final Widget head = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Off GalleryState, which owns the selection — AppState no longer
            // re-broadcasts it.
            Selector<GalleryState, List<AppImage>>(
              selector: (_, s) => s.selectedImages,
              builder: (context, selectedImages, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSelectionPreview(context, selectedImages, colorScheme, l10n),
                  _buildReferenceImageNotice(context, selectedModelIdStr, selectedImages.length, colorScheme, l10n),
                ],
              ),
            ),

            // Model Selection Section — the section is self-titled (collapsible),
            // so no separate header above it (matches the video panel).
            const SizedBox(height: 8),
            AppCard(
              outlined: true,
              padding: const EdgeInsets.symmetric(horizontal: 12),
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
              imageParamResolver: (modelId, spec) =>
                  Provider.of<AppState>(context, listen: false).getImageParam(modelId, spec),
              onImageParamChanged: (modelId, key, value) =>
                  Provider.of<AppState>(context, listen: false).setImageParam(modelId, key, value),
              ),
            ),

            const SizedBox(height: 8),
            AppCard(
              outlined: true,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildToggleRow(
                    // `waves`, not `stream`: `stream` is a scatter of dots,
                    // and `16a` draws the sine the model editor already uses.
                    icon: Icons.waves,
                    title: l10n.useStreaming,
                    description: l10n.useStreamingDesc,
                    value: useStream,
                    onChanged: (v) => _updateConfig(useStream: v),
                  ),
                  _buildToggleRow(
                    icon: Icons.compress,
                    title: l10n.compressReferenceImages,
                    description: l10n.compressReferenceImagesDesc,
                    value: compressReferenceImages,
                    onChanged: (v) => _updateConfig(compressReferenceImages: v),
                  ),
                ],
              ),
            ),

          ],
        );

        // The prompt: its label row, then the card. `fill: true` lets the card
        // take whatever height the column leaves it. Only the desktop sidebar
        // passes it — the mobile bottom sheet is scrolled by a controller above
        // this widget, where the height is unbounded and a flex child throws.
        Widget buildPrompt({required bool fill}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
          children: [
            SizedBox(
              height: _kPromptLabelRow,
              child: AppSectionLabel(
                l10n.prompt,
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                trailing: _buildPromptActions(promptHistory, l10n),
              ),
            ),
            _fillable(
              fill: fill,
              child: ConstrainedBox(
                // A floor for the bottom sheet, where nothing else bounds the
                // card. Under the desktop [Expanded] the height is already
                // tight and this is a no-op.
                constraints: const BoxConstraints(minHeight: kMinPromptEditorHeight),
                child: AppCard(
                  outlined: true,
                  // Zero, so the editor's header hairline can run the full
                  // width of the card. `16a` draws one box with a rule across
                  // it, not a stack of inset pieces — the padding moves inside,
                  // onto the header, the body and the footer separately.
                  padding: EdgeInsets.zero,
                  child: Column(
                    mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                          // The card around it is the frame; see
                          // [MarkdownEditor.bordered].
                          bordered: false,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                        child: editorActions,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (!fill) const SizedBox(height: 16),
          ],
        );

        // Primary Execution Button — reused in both mobile (pinned) and desktop (in scroll)
        //
        // The enabled state hangs off the controller directly rather than off a
        // panel rebuild: typing no longer notifies [AppState] (see
        // setPromptDraft), so nothing else would re-run this. Listening to the
        // controller keeps the button live at the cost of rebuilding one button
        // per keystroke instead of the whole sidebar.
        final processButton = SizedBox(
          width: double.infinity,
          child: Selector<GalleryState, int>(
            selector: (_, s) => s.selectedImages.length,
            builder: (context, selectedCount, _) => ValueListenableBuilder<TextEditingValue>(
              valueListenable: _promptController,
              builder: (context, promptValue, _) => FilledButton.icon(
                onPressed: promptValue.text.isEmpty
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
                          ...appState.effectiveImageParams(selectedModel.modelId),
                        };

                        appState.submitTask(selectedModelDbId, params, modelIdDisplay: modelName);

                        if (widget.scrollController != null) {
                          Navigator.pop(context);
                        }

                        AppSnackBar.info(context, l10n.taskSubmitted);
                      },
                icon: const Icon(Icons.play_arrow_rounded, size: 24),
                label: Text(
                  selectedCount == 0
                      ? l10n.processPrompt
                      : l10n.processImages(selectedCount),
                  style: Theme.of(context).textTheme.titleMedium?.metricsOnly,
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                  elevation: 0,
                ),
              ),
            ),
          ),
        );

        if (widget.scrollController != null) {
          // Mobile bottom sheet: pin the Process button at the top so it stays
          // visible. The optimizer entry rides with the editor in the scroll
          // body now, next to the text it acts on.
          return Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: processButton,
              ),
              Expanded(
                child: ScrollEdgeFade(
                  child: SingleChildScrollView(
                    controller: widget.scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [head, buildPrompt(fill: false)],
                    ),
                  ),
                ),
              ),
            ],
          );
        } else {
          // Desktop sidebar. `A1 16a` draws this column with nothing scrolling
          // in it: the prompt card is the flex child and everything else is as
          // tall as it is. So the prompt's own footer — 「发送到提示词助手」 and
          // the queue-settings gear — is always on screen, which is the point
          // of putting them in the card rather than beside the Process button.
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
                  padding: const EdgeInsets.all(16),
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final double promptFloor =
                          kMinPromptEditorHeight + _kPromptLabelRow;

                      // Not enough column to hold both. Rather than pin a
                      // footer over a head crushed to nothing, fall back to
                      // the bottom sheet's arrangement: one scroll, the card
                      // at its own natural height.
                      if (box.maxHeight < promptFloor + _kMinHeadHeight) {
                        return ScrollEdgeFade(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [head, buildPrompt(fill: false)],
                            ),
                          ),
                        );
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
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
      },
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

  /// One setting: name, one line of explanation, switch.
  ///
  /// Replaces [SwitchListTile], whose title defaulted to bold 13 while the
  /// section headers above it sat at 11 -- the switches were shouting over
  /// the headings that grouped them. Here the name takes the type scale's
  /// small title and the explanation drops to `bodySmall` in
  /// `onSurfaceVariant`, so the row reads name-first and the description
  /// stays available without competing.
  Widget _buildToggleRow({
    required IconData icon,
    required String title,
    required String description,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: textTheme.titleSmall),
                const SizedBox(height: 1),
                Text(
                  description,
                  style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _buildPromptActions(List<PromptHistoryEntry> history, AppLocalizations l10n) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PromptHistoryButton(
          entries: history,
          type: PromptHistoryType.image,
          onApply: (content) {
            _promptController.text = content;
            _updateConfig(prompt: content);
          },
        ),
        AppButton(
          label: l10n.library,
          icon: Icons.library_books_outlined,
          variant: AppButtonVariant.text,
          // Compact, to match the history button beside it — at full size it
          // was 48 tall and set the whole label row's height, which is the
          // figure [_kPromptLabelRow] has to hold.
          size: AppButtonSize.compact,
          onPressed: _allUserPrompts.isEmpty ? null : () => _showPromptPickerMenu(l10n),
        ),
      ],
    );
  }

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

  Widget _buildSelectionPreview(BuildContext context, List<AppImage> selectedImages, ColorScheme colorScheme, AppLocalizations l10n) {
    if (selectedImages.isEmpty) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withAlpha((255 * 0.3).round()),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.collections_outlined, size: 48, color: colorScheme.outline),
              const SizedBox(height: 8),
              Text(l10n.noImagesSelected, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurface)),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              l10n.selectedCount(selectedImages.length),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            AppButton(
              label: l10n.clear,
              variant: AppButtonVariant.text,
              onPressed: () => Provider.of<AppState>(context, listen: false).clearImageSelection(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 100,
          child: ReorderableListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: selectedImages.length,
            onReorderItem: (oldIndex, newIndex) {
              Provider.of<AppState>(context, listen: false).galleryState.reorderSelectedImages(oldIndex, newIndex);
            },
            proxyDecorator: (child, index, animation) {
              return Material(
                color: Colors.transparent,
                child: child,
              );
            },
            itemBuilder: (context, index) {
              final image = selectedImages[index];
              return Padding(
                key: ValueKey(image.path),
                padding: const EdgeInsets.only(right: 8.0),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      child: Image(
                        image: image.imageProvider,
                        width: 100,
                        height: 100,
                        fit: BoxFit.cover,
                      ),
                    ),
                    // The same number the grid tile carries, because this is
                    // the same fact: the order these are handed to the model.
                    // The grid has said it since the selection badge went in;
                    // this strip is where the order is actually *edited* (it
                    // reorders by drag), so without the number the two halves
                    // of one idea disagreed about how to name a picture.
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Container(
                        width: 20,
                        height: 20,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          shape: BoxShape.circle,
                          boxShadow: const [
                            BoxShadow(color: _thumbScrim, blurRadius: 5, offset: Offset(0, 1)),
                          ],
                        ),
                        child: Text(
                          '${index + 1}',
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: colorScheme.onPrimary,
                                fontWeight: FontWeight.w600,
                                height: 1,
                              ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () => Provider.of<AppState>(context, listen: false).toggleImageSelection(image),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(color: _thumbScrim, shape: BoxShape.circle),
                          child: const Icon(Icons.close, size: 14, color: _thumbInk),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Warns when the selected model can't use the images the user has picked as
  /// references (Imagen accepts none; OpenAI image caps the count).
  Widget _buildReferenceImageNotice(
      BuildContext context, String? modelId, int selectedCount, ColorScheme colorScheme, AppLocalizations l10n) {
    if (modelId == null || selectedCount == 0) return const SizedBox.shrink();

    final caps = ModelCapabilities.forModel(modelId);
    String? message;
    if (!caps.supportsReferenceImages) {
      message = l10n.referenceImagesNotSupported;
    } else if (caps.maxReferenceImages != null && selectedCount > caps.maxReferenceImages!) {
      message = l10n.referenceImagesLimited(caps.maxReferenceImages!);
    }
    if (message == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: colorScheme.onTertiaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colorScheme.onTertiaryContainer)),
          ),
        ],
      ),
    );
  }

}
