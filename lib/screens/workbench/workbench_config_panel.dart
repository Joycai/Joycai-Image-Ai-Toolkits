import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/app_image.dart';
import '../../models/llm_channel.dart';
import '../../models/llm_model.dart';
import '../../models/prompt.dart';
import '../../models/tag.dart';
import '../../services/llm/model_capabilities.dart';
import '../../state/app_state.dart';
import '../../state/workbench_ui_state.dart';
import '../../widgets/dialogs/library_dialog.dart';
import '../../widgets/markdown_editor.dart';
import 'model_selection_section.dart';
import 'widgets/config_action_bar.dart';
import 'widgets/config_section_header.dart';
import 'widgets/queue_settings_dialog.dart';

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

  void _updateConfig({int? modelDbId, String? modelIdStr, String? prompt, bool? useStream}) {
    final appState = Provider.of<AppState>(context, listen: false);

    String? idToSave;
    if (modelDbId != null) {
      idToSave = modelDbId.toString(); // Save PK as string
    }

    appState.updateWorkbenchConfig(
      modelId: idToSave ?? modelIdStr,
      prompt: prompt,
      useStream: useStream,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Select specific values to rebuild on change
    final imageModels = context.select<AppState, List<LLMModel>>((s) => s.imageModels);
    final allChannels = context.select<AppState, List<LLMChannel>>((s) => s.allChannels);
    final isMarkdownWorkbench = context.select<AppState, bool>((s) => s.isMarkdownWorkbench);
    final lastSelectedModelId = context.select<AppState, String?>((s) => s.lastSelectedModelId);
    final lastPrompt = context.select<AppState, String>((s) => s.lastPrompt);
    final useStream = context.select<AppState, bool>((s) => s.useStream);
    // Rebuild parameter controls when the stored image params change.
    context.select<AppState, int>((s) => s.imageParamsRevision);

    // Determine selected model from AppState
    int? selectedModelDbId;
    int? selectedChannelId;
    String? selectedModelIdStr;

    if (imageModels.isNotEmpty) {
      final savedModelId = lastSelectedModelId;
      final match = imageModels.cast<LLMModel?>().firstWhere(
        (m) => m?.id.toString() == savedModelId || m?.modelId == savedModelId,
        orElse: () => null,
      );

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
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Selector<AppState, List<AppImage>>(
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
            ModelSelectionSection(
              availableModels: imageModels.map((m) => m.toMap()).toList(),
              // Only offer channels that actually serve image models — a
              // chat-only channel (e.g. DeepSeek) has nothing selectable here.
              channels: allChannels
                  .where((c) => imageModels.any((m) => m.channelId == c.id))
                  .map((c) => c.toMap())
                  .toList(),
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

            const SizedBox(height: 8),
            SwitchListTile(
              title: Text(l10n.useStreaming, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              subtitle: Text(l10n.useStreamingDesc, style: const TextStyle(fontSize: 11)),
              value: useStream,
              onChanged: (v) => _updateConfig(useStream: v),
              secondary: const Icon(Icons.stream, size: 20),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),

            ConfigSectionHeader(l10n.prompt, trailing: _buildPromptPicker(colorScheme, l10n)),
            const SizedBox(height: 4),
            MarkdownEditor(
              controller: _promptController,
              label: l10n.prompt,
              isMarkdown: isMarkdownWorkbench,
              onMarkdownChanged: (v) => Provider.of<AppState>(context, listen: false).setIsMarkdownWorkbench(v),
              maxLines: 15,
              initiallyPreview: false,
              hint: l10n.promptHint,
              onChanged: (v) => _updateConfig(prompt: v),
              expand: false, // Don't expand inside scrollable
            ),
            const SizedBox(height: 16),

            const SizedBox(height: 12),
            // Action Zone Container
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.outlineVariant.withAlpha(100)),
              ),
              child: Row(
                children: [
                  // Send to Optimizer
                  Expanded(
                    child: OutlinedButton.icon(
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
                      icon: const Icon(Icons.auto_fix_high, size: 18),
                      label: Text(l10n.sendToOptimizer, style: const TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Queue Settings
                  IconButton.filledTonal(
                    onPressed: () => showQueueSettingsDialog(context),
                    icon: const Icon(Icons.settings_outlined, size: 20),
                    tooltip: l10n.queueSettings,
                    style: IconButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

        // Primary Execution Button — reused in both mobile (pinned) and desktop (in scroll)
        final processButton = SizedBox(
          width: double.infinity,
          child: Selector<AppState, int>(
            selector: (_, s) => s.selectedImages.length,
            builder: (context, selectedCount, _) => FilledButton.icon(
              onPressed: _promptController.text.isEmpty
                  ? null
                  : () {
                      final appState = Provider.of<AppState>(context, listen: false);
                      if (selectedModelDbId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(l10n.noModelsConfigured),
                            action: SnackBarAction(
                              label: l10n.models,
                              onPressed: () => appState.navigateToScreen(6),
                            ),
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

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(l10n.taskSubmitted),
                          duration: const Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                          width: 250,
                        ),
                      );
                    },
              icon: const Icon(Icons.play_arrow_rounded, size: 24),
              label: Text(
                selectedCount == 0
                    ? l10n.processPrompt
                    : l10n.processImages(selectedCount),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ),
        );

        if (widget.scrollController != null) {
          // Mobile bottom sheet: pin Process button at top so it's always visible
          return Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: processButton,
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
        } else {
          // Desktop sidebar: content scrolls; the Process button is docked at
          // the bottom so it's always reachable without scrolling to the end.
          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: content,
                ),
              ),
              ConfigActionBar(child: processButton),
            ],
          );
        }
      },
    );
  }

  Widget _buildPromptPicker(ColorScheme colorScheme, AppLocalizations l10n) {
    return TextButton.icon(
      onPressed: _allUserPrompts.isEmpty ? null : () => _showPromptPickerMenu(l10n),
      icon: const Icon(Icons.library_books_outlined, size: 16),
      label: Text(l10n.library, style: const TextStyle(fontSize: 12)),
      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
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
              Text(l10n.noImagesSelected, style: TextStyle(color: colorScheme.onSurface, fontSize: 12)),
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
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            TextButton(
              onPressed: () => Provider.of<AppState>(context, listen: false).clearImageSelection(),
              child: Text(l10n.clear, style: const TextStyle(fontSize: 12)),
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
                      borderRadius: BorderRadius.circular(8),
                      child: Image(
                        image: image.imageProvider,
                        width: 100,
                        height: 100,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () => Provider.of<AppState>(context, listen: false).toggleImageSelection(image),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(Icons.close, size: 14, color: Colors.white),
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
            child: Text(message, style: TextStyle(fontSize: 11, color: colorScheme.onTertiaryContainer)),
          ),
        ],
      ),
    );
  }

}
