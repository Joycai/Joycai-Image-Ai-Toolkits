part of 'video_config_panel.dart';

class _SourceVideoSlot extends StatefulWidget {
  const _SourceVideoSlot({required this.model, required this.operation, this.captionStyle});
  final LLMModel model;
  final GenerationOperation operation;
  final TextStyle? captionStyle;
  @override
  State<_SourceVideoSlot> createState() => _SourceVideoSlotState();
}

class _SourceVideoSlotState extends State<_SourceVideoSlot> {
  bool _osHover = false;
  int _importGeneration = 0;
  Object? _confirmToken;
  String? _thumbnailSource;
  Future<String?>? _thumbnail;

  Future<void> _import(String path, {DropItem? drop}) async {
    final generation = ++_importGeneration;
    final l10n = AppLocalizations.of(context)!;
    if (!['.mp4', '.mov'].contains(p.extension(path).toLowerCase())) {
      AppSnackBar.warning(context, l10n.dropVideosOnly);
      return;
    }
    try {
      final imported = await PersistentMediaService.instance.importFile(
        path,
        appleBookmark: drop?.extraAppleBookmark,
      );
      if (!mounted || generation != _importGeneration) return;
      final state = context.read<WorkbenchUIState>();
      setState(() => _confirmToken = Object());
      _announceDrop(context, l10n.sourceVideo);
      await state.setVideoSourceVideo(imported);
    } catch (error) {
      if (mounted) AppSnackBar.error(context, l10n.importFailed('$error'));
    }
  }

  Future<void> _pick() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp4', 'mov'],
    );
    if (!mounted) return;
    if (files.firstOrNull?.path case final path?) await _import(path);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final state = context.watch<WorkbenchUIState>();
    final l10n = AppLocalizations.of(context)!;
    final schema = app.generationSchemaForModel(widget.model);
    final options = app.effectiveVideoParams(widget.model);
    final source = state.videoSourceVideoPath;
    if (_thumbnailSource != source) {
      _thumbnailSource = source;
      _thumbnail = source == null ? null : VideoThumbnailService.instance.getThumbnail(source);
    }
    final info = state.videoSourceProbe?.info;
    final direction = schema.capabilities.videoParams
        .where((p) => p.key == 'extendDirection')
        .firstOrNull;
    final extend = widget.operation == GenerationOperation.extendVideo;
    final max = extend
        ? schema.contract.videoExtend?.maxCombinedSeconds
        : schema.contract.videoEdit?.maxCombinedSeconds;
    final totalInput =
        (info?.seconds ?? 0) +
        state.videoReferenceVideos.fold(
          0.0,
          (sum, path) => sum + (state.videoReferenceProbes[path]?.info?.seconds ?? 0),
        );
    final output = double.tryParse('${options['seconds']}');
    final style = Theme.of(context).textTheme.labelSmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${l10n.sourceVideo} · ${l10n.videoReferenceToken(1)}',
                style: widget.captionStyle,
              ),
            ),
            if (source != null) ...[
              AppIconButton(
                icon: Icons.visibility_outlined,
                size: Responsive.isMobile(context) ? AppSize.touch : AppSize.control,
                tooltip: l10n.preview,
                outlined: false,
                onPressed: () => showMediaPreview(
                  context,
                  galleryImages: [AppImage(path: source, name: p.basename(source))],
                  initialIndex: 0,
                ),
              ),
              AppIconButton(
                icon: Icons.close,
                size: Responsive.isMobile(context) ? AppSize.touch : AppSize.control,
                tooltip: l10n.remove,
                outlined: false,
                onPressed: () {
                  ++_importGeneration;
                  state.clearVideoSourceVideo();
                },
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpace.s6),
        DropTarget(
          onDragEntered: (_) => setState(() => _osHover = true),
          onDragExited: (_) => setState(() => _osHover = false),
          onDragDone: (details) {
            setState(() => _osHover = false);
            if (details.files.firstOrNull case final file?) _import(file.path, drop: file);
          },
          child: DragTarget<AppImage>(
            onWillAcceptWithDetails: (details) => AppConstants.isVideoFile(details.data.path),
            onAcceptWithDetails: (details) => _import(details.data.path),
            builder: (context, candidates, rejected) => AppDropConfirmRing(
              trigger: _confirmToken,
              child: AppDropZoneFrame(
                state: rejected.isNotEmpty
                    ? AppDropZoneState.reject
                    : _osHover || candidates.isNotEmpty
                    ? AppDropZoneState.hover
                    : AppDropZoneState.rest,
                child: AppActionTarget(
                  label: l10n.dropSourceVideo,
                  onTap: _pick,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.s10),
                    child: source == null
                        ? Column(
                            children: [
                              const Icon(Icons.video_library_outlined),
                              const SizedBox(height: AppSpace.s6),
                              Text(l10n.dropSourceVideo, textAlign: TextAlign.center),
                            ],
                          )
                        : Row(
                            children: [
                              SizedBox(
                                width: 64,
                                height: 48,
                                child: FutureBuilder<String?>(
                                  future: _thumbnail,
                                  builder: (context, snapshot) => snapshot.data == null
                                      ? const Icon(Icons.movie_outlined)
                                      : Image.file(File(snapshot.data!), fit: BoxFit.contain),
                                ),
                              ),
                              const SizedBox(width: AppSpace.s6),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p.basename(source),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: style?.mono,
                                    ),
                                    if (info != null)
                                      Text(
                                        '${info.width}×${info.height} · ${info.seconds?.toStringAsFixed(1)}s · ${info.fps?.toStringAsFixed(1)}fps',
                                        style: style,
                                      ),
                                    if (state.videoSourceProbe != null)
                                      Text(
                                        '${(state.videoSourceProbe!.bytes / (1024 * 1024)).toStringAsFixed(1)} MB',
                                        style: style,
                                      ),
                                    if (state.videoSourceProbing)
                                      Text(l10n.generationSourceVideoProbing, style: style),
                                  ],
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (extend && direction != null && schema.contract.videoExtend!.directions.length > 1) ...[
          const SizedBox(height: AppSpace.s10),
          Text(l10n.paramExtendDirection, style: style),
          const SizedBox(height: AppSpace.s4),
          AppSegmentedControl<String>(
            expand: true,
            tightLabels: true,
            value: app.getVideoParam(widget.model, direction),
            segments: [
              for (final option in direction.options)
                AppSegment(
                  value: option.value,
                  label: GenerationParamTexts.option(l10n, 'extendDirection', option.value),
                ),
            ],
            onChanged: (value) => app.setVideoParam(widget.model, 'extendDirection', value),
          ),
        ],
        const SizedBox(height: AppSpace.s6),
        if (schema.aspectPolicyFor(widget.operation) == VideoAspectPolicy.recommendedAdaptive)
          Text(l10n.videoAdaptiveHint, style: style),
        if (info != null && max != null) ...[
          const SizedBox(height: AppSpace.s6),
          Text(
            output == null || output < 0
                ? l10n.videoSmartBudget(totalInput.toStringAsFixed(1), max.toStringAsFixed(0))
                : l10n.videoFixedBudget(
                    totalInput.toStringAsFixed(1),
                    output.toStringAsFixed(0),
                    max.toStringAsFixed(0),
                  ),
            style: style,
          ),
          if (extend && output != null && output > 0)
            Text(
              output <= (info.seconds ?? 0)
                  ? l10n.videoShortExtension
                  : l10n.videoExtensionEstimate((output - (info.seconds ?? 0)).toStringAsFixed(1)),
              style: style,
            ),
        ],
      ],
    );
  }
}
