part of 'video_config_panel.dart';

/// A reference cell (`00d` 尺寸 「参考图格 72」), and the gap between cells.
const double _kReferenceCell = 72;

const double _kReferenceGap = _kCardInnerGap;

/// How far outside a full grid its drop verdict's edge sits, so the dashed
/// line runs beside the thumbnails rather than over their corners. Inside the
/// card's 10 inset, so the card's clip never shaves it.
const double _kVerdictOutset = AppSpace.s4;

/// The reference-image card (`A2 · 1a`; drop states `00d · 1c`): caption and
/// the "n / max" count, then 72 thumbnails and a drop cell taking the rest of
/// the last row — or, with nothing added yet, one dashed drop zone. The whole
/// card accepts a drop; at the model's ceiling it refuses more and says why.
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

  /// The pictures the last drop landed (added, or already there), and the
  /// token that rings their thumbnails.
  Set<String> _confirmedPaths = const {};
  Object? _confirmToken;

  /// The count the confirmation note reports; null while there is no note.
  int? _noteCount;
  Timer? _noteTimer;

  @override
  void dispose() {
    _noteTimer?.cancel();
    super.dispose();
  }

  void _setOsDragging(bool value) {
    if (_osDragging != value) setState(() => _osDragging = value);
  }

  /// At the selected model's ceiling (`00d` 已满).
  bool get _isFull {
    final max = widget.maxImages;
    return max != null && widget.images.length >= max;
  }

  bool _takes(Object? payload) => _isDroppableImage(payload) && !_isFull;

  /// Adds what fits under the ceiling, then confirms it (`00d` 确认): a ring
  /// on each thumbnail that landed and a note with the new count.
  void _acceptAll(List<AppImage> dropped) {
    final max = widget.maxImages;
    final present = {for (final image in widget.images) image.path};
    final landed = <String>{};
    var count = widget.images.length;
    var added = 0;
    for (final image in dropped) {
      if (present.contains(image.path)) {
        // Already there: nothing to add, but show where it is.
        landed.add(image.path);
        continue;
      }
      if (max != null && count >= max) break;
      widget.onDrop(image);
      present.add(image.path);
      landed.add(image.path);
      count++;
      added++;
    }
    if (landed.isEmpty) return;

    final int? noteCount = added > 0 ? count : null;
    _noteTimer?.cancel();
    setState(() {
      _confirmedPaths = landed;
      _confirmToken = null;
      _noteCount = noteCount;
    });
    // A ring fires on a change of its trigger, and a thumbnail this drop
    // mounts has nothing to change from: it gets the token a frame later.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _confirmToken = Object());
    });
    _noteTimer = Timer(_kDropNoteHold, () {
      if (!mounted) return;
      setState(() {
        _confirmedPaths = const {};
        _confirmToken = null;
        _noteCount = null;
      });
    });
    if (noteCount != null) {
      _announceDrop(context, _addedMessage(AppLocalizations.of(context)!, noteCount, max));
    }
  }

  /// 「已加入参考图 · 3 / 3」, or the bare count when the model sets no ceiling.
  static String _addedMessage(AppLocalizations l10n, int count, int? max) => max == null
      ? l10n.dropAddedToReferencesUnlimited(count)
      : l10n.dropAddedToReferences(count, max);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final images = widget.images;
    final max = widget.maxImages;

    return DropTarget(
      onDragEntered: (_) => _setOsDragging(true),
      onDragExited: (_) => _setOsDragging(false),
      onDragDone: (details) {
        _setOsDragging(false);
        _acceptAll([
          for (final file in details.files)
            if (AppConstants.isImageFile(file.path)) AppImage(path: file.path, name: file.name),
        ]);
      },
      // `00d` 「可放」: an in-app drag this card would take, still elsewhere.
      child: ValueListenableBuilder<Object?>(
        valueListenable: AppDragSession.current,
        builder: (context, payload, _) => DragTarget<AppImage>(
          onWillAcceptWithDetails: (details) => _takes(details.data),
          onAcceptWithDetails: (details) => _acceptAll([details.data]),
          builder: (context, candidateData, rejectedData) {
            final bool full = _isFull;
            final AppDropZoneState state;
            if (candidateData.isNotEmpty) {
              state = AppDropZoneState.hover;
            } else if (rejectedData.isNotEmpty) {
              // A picture turned away can only have met the ceiling.
              state = _isDroppableImage(rejectedData.first)
                  ? AppDropZoneState.full
                  : AppDropZoneState.reject;
            } else if (_osDragging) {
              // What the OS carries is unknown until the release; the ceiling
              // is known now.
              state = full ? AppDropZoneState.full : AppDropZoneState.hover;
            } else if (_takes(payload)) {
              state = AppDropZoneState.armed;
            } else {
              state = AppDropZoneState.rest;
            }

            final String zoneTitle = switch (state) {
              AppDropZoneState.hover => l10n.dropRelease,
              AppDropZoneState.reject => l10n.dropImagesOnly,
              AppDropZoneState.full =>
                max != null && max > 0
                    ? l10n.dropReferenceLimit(max)
                    : l10n.referenceImagesNotSupported,
              AppDropZoneState.rest || AppDropZoneState.armed =>
                max != null && max > 0
                    ? l10n.videoReferenceDropMax(max)
                    : l10n.dropVideoReferenceHere,
            };
            final IconData zoneIcon = images.isEmpty
                ? Icons.add_photo_alternate_outlined
                : Icons.add;

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

            final int? noteCount = _noteCount;

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
                    child: _DropSlot(state: state, icon: zoneIcon, title: zoneTitle),
                  )
                else
                  LayoutBuilder(
                    builder: (context, box) {
                      final double width = box.maxWidth;
                      final int perRow = math.max(
                        1,
                        ((width + _kReferenceGap) / (_kReferenceCell + _kReferenceGap)).floor(),
                      );
                      // The drop cell takes what the last row leaves — at
                      // least one cell, since a row never holds more than fit.
                      final int inLastRow = images.length % perRow;
                      final double zoneWidth =
                          (width - inLastRow * (_kReferenceCell + _kReferenceGap)).floorToDouble();
                      final Widget grid = Wrap(
                        spacing: _kReferenceGap,
                        runSpacing: _kReferenceGap,
                        children: [
                          for (final img in images)
                            _ReferenceThumbnail(
                              key: ValueKey(img.path),
                              image: img,
                              size: _kReferenceCell,
                              confirmTrigger: _confirmedPaths.contains(img.path)
                                  ? _confirmToken
                                  : null,
                              onRemove: () => widget.onRemove(img),
                            ),
                          // Under the ceiling the drop cell is always there;
                          // at it there is none, in every state — a drag
                          // passing over must never reflow the card.
                          if (!full)
                            SizedBox(
                              width: zoneWidth,
                              height: _kReferenceCell,
                              child: _DropSlot(state: state, icon: zoneIcon, title: zoneTitle),
                            ),
                        ],
                      );
                      if (!full) return grid;

                      // At the ceiling the verdict is laid over the grid at
                      // the grid's own size: the ladder's edge just outside
                      // the thumbnails, no ground over the pictures, and the
                      // reason on the image plate.
                      return Stack(
                        fit: StackFit.passthrough,
                        clipBehavior: Clip.none,
                        children: [
                          grid,
                          if (state.edgeWidth > 1)
                            Positioned.fill(
                              left: -_kVerdictOutset,
                              top: -_kVerdictOutset,
                              right: -_kVerdictOutset,
                              bottom: -_kVerdictOutset,
                              child: IgnorePointer(
                                child: AppDropZoneFrame(
                                  state: state,
                                  ground: false,
                                  radius: AppRadius.control + _kVerdictOutset,
                                  child: Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(AppSpace.s6),
                                      child: _PlateLabel(zoneTitle),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                AnimatedSize(
                  duration: AppMotion.durationOf(context, AppMotion.reveal),
                  curve: AppMotion.enter,
                  alignment: AlignmentDirectional.topStart,
                  child: noteCount != null
                      ? Padding(
                          padding: const EdgeInsets.only(top: _kCardInnerGap),
                          child: AppDropNote(_addedMessage(l10n, noteCount, max)),
                        )
                      : const SizedBox(width: double.infinity),
                ),
                if (notice != null) ...[
                  const SizedBox(height: _kCardInnerGap),
                  _WarningNotice(message: notice),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A reference picture with its remove button; [confirmTrigger] rings it
/// after the drop that brought it (`00d` 确认).
class _ReferenceThumbnail extends StatelessWidget {
  final AppImage image;
  final double size;
  final VoidCallback onRemove;
  final Object? confirmTrigger;

  const _ReferenceThumbnail({
    super.key,
    required this.image,
    required this.size,
    required this.onRemove,
    this.confirmTrigger,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox.square(
      dimension: size,
      child: AppDropConfirmRing(
        trigger: confirmTrigger,
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
      ),
    );
  }
}
