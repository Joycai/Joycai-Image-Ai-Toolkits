part of 'video_config_panel.dart';

/// The native video wire's additional reference inputs. Selection belongs to
/// WorkbenchUIState, including parked files after switching to another model.
class _ReferenceFilesSection extends StatelessWidget {
  const _ReferenceFilesSection({
    required this.contract,
    required this.maxImages,
    this.captionStyle,
  });
  final GenerationProtocolContract contract;
  final int maxImages;
  bool get enabled => contract.referenceAudioVideo;
  final TextStyle? captionStyle;

  Future<void> _pick(BuildContext context, {required bool audio}) async {
    final state = context.read<WorkbenchUIState>();
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: audio ? ['wav', 'mp3'] : ['mp4', 'mov'],
    );
    try {
      for (final file in result) {
        if (file.path == null) continue;
        final path = await PersistentMediaService.instance.importFile(file.path!);
        if (!context.mounted) return;
        state.addVideoReferenceFiles([path], audio: audio);
      }
    } catch (error) {
      if (context.mounted) {
        AppSnackBar.error(context, AppLocalizations.of(context)!.importFailed('$error'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<WorkbenchUIState>();
    final l10n = AppLocalizations.of(context)!;
    Future<void> importVideo(String source, {DropItem? drop}) async {
      if (!enabled || !['.mp4', '.mov'].contains(p.extension(source).toLowerCase())) {
        AppSnackBar.warning(context, l10n.dropVideosOnly);
        return;
      }
      try {
        final path = await PersistentMediaService.instance.importFile(
          source,
          appleBookmark: drop?.extraAppleBookmark,
        );
        if (!context.mounted) return;
        state.addVideoReferenceFiles([path], audio: false);
        _announceDrop(context, l10n.generationAddReferenceVideo);
      } catch (error) {
        if (context.mounted) AppSnackBar.error(context, l10n.importFailed('$error'));
      }
    }

    return DropTarget(
      onDragDone: (details) {
        for (final file in details.files) {
          importVideo(file.path, drop: file);
        }
      },
      child: DragTarget<AppImage>(
        onWillAcceptWithDetails: (d) => enabled && AppConstants.isVideoFile(d.data.path),
        onAcceptWithDetails: (d) => importVideo(d.data.path),
        builder: (context, candidates, rejected) => AppDropZoneFrame(
          state: rejected.isNotEmpty
              ? AppDropZoneState.reject
              : candidates.isNotEmpty
              ? AppDropZoneState.hover
              : AppDropZoneState.rest,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.generationReferenceMedia, style: captionStyle),
              const SizedBox(height: AppSpace.s4),
              if (enabled) ...[
                Text(
                  l10n.generationReferenceMediaLimits(
                    maxImages,
                    contract.maxReferenceVideos,
                    contract.maxReferenceAudios,
                    contract.maxReferenceMedia,
                    contract.minReferenceSeconds,
                    contract.maxReferenceTotalSeconds,
                  ),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                if (contract.referenceUpload)
                  Text(
                    l10n.generationReferenceUploadHint,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
              ],
              const SizedBox(height: AppSpace.s6),
              Wrap(
                spacing: AppSpace.s6,
                runSpacing: AppSpace.s4,
                children: [
                  AppButton(
                    variant: AppButtonVariant.secondary,
                    onPressed: enabled ? () => _pick(context, audio: false) : null,
                    icon: Icons.video_library_outlined,
                    label: l10n.generationAddReferenceVideo,
                  ),
                  AppButton(
                    variant: AppButtonVariant.secondary,
                    onPressed: enabled ? () => _pick(context, audio: true) : null,
                    icon: Icons.audiotrack_outlined,
                    label: l10n.generationAddReferenceAudio,
                  ),
                ],
              ),
              for (final audio in [false, true])
                for (final path in audio ? state.videoReferenceAudios : state.videoReferenceVideos)
                  Row(
                    children: [
                      Icon(
                        audio ? Icons.audiotrack_outlined : Icons.movie_outlined,
                        size: AppSize.iconSm,
                      ),
                      const SizedBox(width: AppSpace.s6),
                      Expanded(
                        child: Text(p.basename(path), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      AppIconButton(
                        tooltip: l10n.remove,
                        icon: Icons.close,
                        outlined: false,
                        iconSize: AppSize.iconSm,
                        onPressed: () => state.removeVideoReferenceFile(path, audio: audio),
                      ),
                    ],
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
