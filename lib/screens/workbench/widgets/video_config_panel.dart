import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants.dart';
import '../../../core/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/app_image.dart';
import '../../../models/llm_channel.dart';
import '../../../models/llm_model.dart';
import '../../../state/app_state.dart';
import '../../../state/workbench_ui_state.dart';
import '../../../widgets/collapsible_card.dart';
import '../../../widgets/markdown_editor.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.noModelsConfigured)));
      return;
    }

    final savedModelId = appState.lastVideoModelId;
    final selectedModel = videoModels.cast<LLMModel?>().firstWhere(
      (m) => m?.id.toString() == savedModelId || m?.modelId == savedModelId,    
      orElse: () => videoModels.first,
    );

    if (selectedModel == null) return;

    final params = {
      'prompt': _promptController.text,
      'resolution': appState.lastVideoResolution.value,
      'aspectRatio': appState.lastVideoAspectRatio.value,
      'referenceImagePaths': uiState.videoReferenceImages.map((i) => i.path).toList(),
      'firstFramePath': uiState.videoFirstFrame?.path,
      'lastFramePath': uiState.videoLastFrame?.path,
    };

    appState.submitVideoTask(selectedModel.id, params, modelIdDisplay: selectedModel.modelName);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.taskSubmitted), behavior: SnackBarBehavior.floating),
    );
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

        const Divider(height: 32),

        // Prompt
        Text(l10n.prompt, style: const TextStyle(fontWeight: FontWeight.bold)), 
        const SizedBox(height: 8),
        MarkdownEditor(
          controller: _promptController,
          label: l10n.prompt,
          isMarkdown: appState.isMarkdownWorkbench,
          onMarkdownChanged: (v) => appState.setIsMarkdownWorkbench(v),
          maxLines: 8,
          hint: l10n.promptHint,
          onChanged: (v) => appState.updateVideoConfig(prompt: v),
          expand: false,
        ),

        const Divider(height: 32),

        // Frame Controls
        Text(l10n.frames, style: const TextStyle(fontWeight: FontWeight.bold)), 
        const SizedBox(height: 12),
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

        const SizedBox(height: 20),

        // Reference Images
        Text(l10n.referenceImages, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        _ReferenceImagesTarget(
          images: uiState.videoReferenceImages,
          onDrop: (img) => uiState.addVideoReferenceImage(img),
          onRemove: (img) => uiState.removeVideoReferenceImage(img),
          dropHint: l10n.dropVideoReferenceHere,
        ),

        const SizedBox(height: 32),

        // Submit Button
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _promptController.text.isEmpty ? null : _handleSubmit,   
            icon: const Icon(Icons.movie_outlined),
            label: Text(l10n.generateVideo, style: const TextStyle(fontWeight: FontWeight.bold)),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );

    return SingleChildScrollView(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(16),
      child: content,
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
    return CollapsibleCard(
      title: l10n.modelSelection,
      isExpanded: _isModelSettingsExpanded,
      onToggle: () => setState(() => _isModelSettingsExpanded = !_isModelSettingsExpanded),
      content: Column(
        children: [
          DropdownButtonFormField<int>(
            decoration: InputDecoration(labelText: l10n.channel, isDense: true),
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
            decoration: InputDecoration(labelText: l10n.model, isDense: true),  
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
          const SizedBox(height: 16),
          // Veo Resolution
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<VeoResolution>(
                  decoration: InputDecoration(labelText: l10n.videoResolution, isDense: true),
                  initialValue: appState.lastVideoResolution,
                  items: VeoResolution.values.map((v) => DropdownMenuItem(      
                    value: v,
                    child: Text(v.value),
                  )).toList(),
                  onChanged: (v) => appState.updateVideoConfig(resolution: v),  
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<VeoAspectRatio>(
                  decoration: InputDecoration(labelText: l10n.videoAspectRatio, isDense: true),
                  initialValue: appState.lastVideoAspectRatio,
                  items: VeoAspectRatio.values.map((v) => DropdownMenuItem(     
                    value: v,
                    child: Text(v.value),
                  )).toList(),
                  onChanged: (v) => appState.updateVideoConfig(aspectRatio: v), 
                ),
              ),
            ],
          ),
        ],
      ),
    );
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
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
                                Text(l10n.tapToPick, style: TextStyle(color: colorScheme.outline, fontSize: 10)),
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
                          style: TextStyle(color: colorScheme.outline, fontSize: 11),
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
