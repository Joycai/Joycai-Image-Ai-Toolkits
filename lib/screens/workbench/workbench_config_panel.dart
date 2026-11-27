import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../models/app_image.dart';
import '../../models/image_output_config.dart';
import '../../models/llm_model.dart';
import '../../models/prompt.dart';
import '../../models/prompt_history_entry.dart';
import '../../models/tag.dart';
import '../../state/app_state.dart';
import '../../state/gallery_state.dart';
import '../../state/workbench_ui_state.dart';
import '../../widgets/drag/app_drag_lift.dart';
import '../../widgets/drag/app_reorder_gap.dart';
import '../../widgets/files/file_visuals.dart';
import '../../widgets/ui/app_action_target.dart';
import '../../widgets/ui/app_button.dart';
import '../../widgets/ui/app_snackbar.dart';
import '../../widgets/ui/dashed_border.dart';
import '../../widgets/ui/markdown_editor.dart';
import '../../widgets/ui/scroll_edge_fade.dart';
import 'widgets/config/config_action_bar.dart';
import 'widgets/config/generation_settings_dialog.dart';
import 'widgets/config/output_config_dialog.dart';
import 'widgets/config/output_config_list_card.dart';
import 'widgets/config/prompt_history_sheet.dart';
import 'widgets/config/prompt_library_sheet.dart';
import 'widgets/generation_params/generation_param_texts.dart';

part 'config_panel/config_panel_chrome.dart';
part 'config_panel/config_selection_card.dart';

/// Shortest the prompt editor — with the footer row under it — is allowed to
/// be reported as.
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
const double _kPromptCardChrome = _kCardPadding * 2 + _kPromptHeaderRow + _kCardInnerGap;

/// Room reserved for the selection card and output configs card in the pinned
/// desktop layout before falling back to single-column scrolling.
const double _kSelectionReserveHeight = 172;
const double _kMinOutputsHeight = 132;
const double _kMaxOutputsHeight = 300;

/// The selection strip's thumbnails (`A1 · 1a` 「88px 缩略 · 序号」).
const double _kThumbSize = 88;
const double _kThumbBadge = 18;
const double _kThumbInset = 6;

/// How far the thumbnail being dragged rises out of the strip.
const double _kThumbLift = 3;

class WorkbenchConfigPanel extends StatefulWidget {
  final ScrollController? scrollController;
  const WorkbenchConfigPanel({super.key, this.scrollController});

  @override
  State<WorkbenchConfigPanel> createState() => _WorkbenchConfigPanelState();
}

class _WorkbenchConfigPanelState extends State<WorkbenchConfigPanel> {
  late MarkdownTextEditingController _promptController;

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

  Future<void> _handleAddOutput() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;
    if (appState.imageModels.isEmpty) {
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
    await showOutputConfigDialog(context, onCommit: appState.addImageOutputConfig);
  }

  Future<void> _handleEditOutput(ImageOutputConfig config) async {
    final appState = Provider.of<AppState>(context, listen: false);
    await showOutputConfigDialog(
      context,
      initial: config,
      onCommit: appState.updateImageOutputConfig,
    );
  }

  @override
  Widget build(BuildContext context) {
    final imageModels = context.select<AppState, List<LLMModel>>((s) => s.imageModels);
    final outputConfigs = context.select<AppState, List<ImageOutputConfig>>(
      (s) => s.imageOutputConfigs,
    );
    final isMarkdownWorkbench = context.select<AppState, bool>((s) => s.isMarkdownWorkbench);
    final lastPrompt = context.select<AppState, String>((s) => s.lastPrompt);
    final promptHistory = context.select<AppState, List<PromptHistoryEntry>>(
      (s) => s.imagePromptHistory,
    );
    context.select<AppState, int>((s) => s.imageParamsRevision);

    final appState = Provider.of<AppState>(context, listen: false);

    // Sync editor from AppState only when not actively on the optimizer tab.
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

    final bool inSheet = widget.scrollController != null;

    final captionStyle = textTheme.labelSmall?.copyWith(
      letterSpacing: AppType.trackedLabelSpacing,
      color: colorScheme.onAccentTint,
    );

    final editorActions = Row(
      children: [
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton(
              label: l10n.sendToOptimizer,
              icon: Icons.auto_awesome,
              variant: AppButtonVariant.text,
              size: AppButtonSize.compact,
              onPressed: () {
                final appState = Provider.of<AppState>(context, listen: false);
                final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);

                workbenchUIState.sendToOptimizer(_promptController.text, appState.selectedImages);

                appState.setWorkbenchTab(4);

                if (widget.scrollController != null) {
                  Navigator.pop(context);
                }
              },
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          tooltip: l10n.generationSettings,
          style: _cardIconStyle(colorScheme, colorScheme.onSurfaceVariant),
          onPressed: () => showGenerationSettingsDialog(context),
        ),
      ],
    );

    final Widget selectionCard = Selector<GalleryState, List<AppImage>>(
      selector: (_, s) => s.selectedImages,
      builder: (context, selectedImages, _) => _buildSelectionCard(context, selectedImages, l10n),
    );

    Widget buildPrompt({required bool fill}) => _PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        children: [
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
                    appState.updateWorkbenchConfig(prompt: content);
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
                      onChanged: appState.setPromptDraft,
                      expand: fill,
                      probeAvailableHeight: !fill,
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

    Widget buildOutputs({required bool scrollable}) => Selector<GalleryState, int>(
      selector: (_, s) => s.selectedImages.length,
      builder: (context, selectedCount, _) => OutputConfigListCard(
        configs: outputConfigs,
        selectedImageCount: selectedCount,
        scrollable: scrollable,
        onAdd: _handleAddOutput,
        onEdit: _handleEditOutput,
        onDuplicate: (c) =>
            appState.duplicateImageOutputConfig(c.id, copySuffix: l10n.duplicateOutputConfig),
        onDelete: (c) => appState.deleteImageOutputConfig(c.id),
        onToggle: appState.toggleImageOutputConfig,
      ),
    );

    final enabledConfigs = outputConfigs.where((c) => c.enabled).toList(growable: false);

    final processButton = Selector<GalleryState, int>(
      selector: (_, s) => s.selectedImages.length,
      builder: (context, selectedCount, _) => ValueListenableBuilder<TextEditingValue>(
        valueListenable: _promptController,
        builder: (context, promptValue, _) {
          final bool enabled = promptValue.text.isNotEmpty && enabledConfigs.isNotEmpty;

          final String ctaLabel;
          if (outputConfigs.isEmpty) {
            ctaLabel = l10n.addOutputConfigFirst;
          } else if (enabledConfigs.isEmpty) {
            ctaLabel = l10n.enableOutputConfigFirst;
          } else if (enabledConfigs.length == 1) {
            final single = enabledConfigs.single;
            final singleModel = appState.resolveOutputModel(single);
            final singleBatch = single.useBatch && appState.supportsImageBatch(singleModel);
            ctaLabel = singleBatch
                ? l10n.batchSubmit
                : selectedCount == 0
                ? l10n.processPrompt
                : l10n.processImages(selectedCount);
          } else {
            ctaLabel = selectedCount == 0
                ? l10n.processPromptOutputs(enabledConfigs.length)
                : l10n.processImagesOutputs(enabledConfigs.length, selectedCount);
          }

          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.control),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: colorScheme.accentRing,
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: FilledButton(
              onPressed: !enabled
                  ? null
                  : () async {
                      final appState = Provider.of<AppState>(context, listen: false);
                      if (imageModels.isEmpty) {
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

                      final ({int submitted, OutputSubmitFailure? failure}) result;
                      try {
                        result = await appState.submitImageOutputs(prompt: _promptController.text);
                      } catch (error) {
                        if (context.mounted) AppSnackBar.warning(context, error.toString());
                        return;
                      }
                      if (!context.mounted) return;

                      if (result.failure case final failure?) {
                        final modelLabel =
                            failure.model?.modelName ??
                            failure.config.modelIdFallback ??
                            l10n.model;
                        final message = failure.modelMissing
                            ? l10n.outputConfigValidationError(
                                modelLabel,
                                l10n.outputConfigModelUnavailable,
                              )
                            : l10n.outputConfigValidationError(
                                modelLabel,
                                GenerationParamTexts.diagnostic(l10n, failure.diagnostic!),
                              );
                        AppSnackBar.warning(context, message);
                        return;
                      }

                      if (result.submitted == 0) return;

                      if (widget.scrollController != null) {
                        Navigator.pop(context);
                      }

                      AppSnackBar.info(
                        context,
                        result.submitted == 1
                            ? l10n.taskSubmitted
                            : l10n.tasksSubmittedCount(result.submitted),
                      );
                    },
              style: FilledButton.styleFrom(
                minimumSize: Size(double.infinity, inSheet ? AppSize.touch : AppSize.large),
              ),
              child: Text(ctaLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          );
        },
      ),
    );

    if (inSheet) {
      return Column(
        mainAxisSize: MainAxisSize.max,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.s16,
              AppSpace.s16,
              AppSpace.s16,
              AppSpace.s10,
            ),
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
                    selectionCard,
                    const SizedBox(height: _kCardGap),
                    buildPrompt(fill: false),
                    const SizedBox(height: _kCardGap),
                    buildOutputs(scrollable: false),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(_kCardGap),
            child: LayoutBuilder(
              builder: (context, box) {
                const double promptFloor = kMinPromptEditorHeight + _kPromptCardChrome;
                const double minPinnedHeight =
                    promptFloor + _kSelectionReserveHeight + _kMinOutputsHeight + _kCardGap * 2;

                if (box.maxHeight < minPinnedHeight) {
                  return ScrollEdgeFade(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          selectionCard,
                          const SizedBox(height: _kCardGap),
                          buildPrompt(fill: false),
                          const SizedBox(height: _kCardGap),
                          buildOutputs(scrollable: false),
                        ],
                      ),
                    ),
                  );
                }

                final double outputsCap =
                    (box.maxHeight - promptFloor - _kSelectionReserveHeight - _kCardGap * 2).clamp(
                      _kMinOutputsHeight,
                      _kMaxOutputsHeight,
                    );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    selectionCard,
                    const SizedBox(height: _kCardGap),
                    Expanded(child: buildPrompt(fill: true)),
                    const SizedBox(height: _kCardGap),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: outputsCap),
                      child: buildOutputs(scrollable: true),
                    ),
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

  static Widget _fillable({required bool fill, required Widget child}) =>
      fill ? Expanded(child: child) : child;

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
          _promptController.text = existing.isEmpty ? content : '$existing\n\n$content';
        } else {
          _promptController.text = content;
        }
        Provider.of<AppState>(
          context,
          listen: false,
        ).updateWorkbenchConfig(prompt: _promptController.text);
      },
    );
  }
}
