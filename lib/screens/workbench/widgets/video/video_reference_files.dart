part of 'video_config_panel.dart';

/// The native video wire's additional reference inputs. Selection belongs to
/// WorkbenchUIState, including parked files after switching to another model.
class _ReferenceFilesSection extends StatelessWidget {
  const _ReferenceFilesSection({required this.enabled, this.captionStyle});
  final bool enabled;
  final TextStyle? captionStyle;

  Future<void> _pick(BuildContext context, {required bool audio}) async {
    final state = context.read<WorkbenchUIState>();
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: audio ? ['wav', 'mp3'] : ['mp4', 'mov'],
    );
    if (!context.mounted) return;
    state.addVideoReferenceFiles(result.map((file) => file.path).whereType<String>(), audio: audio);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<WorkbenchUIState>();
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.generationReferenceMedia, style: captionStyle),
        const SizedBox(height: AppSpace.s4),
        Text(l10n.generationReferenceMediaHint, style: Theme.of(context).textTheme.labelSmall),
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
                IconButton(
                  tooltip: l10n.remove,
                  icon: const Icon(Icons.close, size: AppSize.iconSm),
                  onPressed: () => state.removeVideoReferenceFile(path, audio: audio),
                ),
              ],
            ),
      ],
    );
  }
}
