part of 'video_config_panel.dart';

/// A first- or last-frame slot (`A2 · 1a`; drop states `00d · 1c`): the
/// caption, a 92px place (96 on a tablet, 104 on a phone), and the file's
/// name — or that the frame is optional — under it. A drop rings the slot and
/// the name line gives way to the confirmation for a moment.
class _FrameDropTarget extends StatefulWidget {
  final String label;
  final AppImage? image;
  final ValueChanged<AppImage> onDrop;
  final VoidCallback onClear;
  final IconData emptyIcon;

  /// The empty slot's name (「拖入首帧」).
  final String emptyTitle;

  /// What the note under the slot says after a drop (「已放入首帧」).
  final String confirmMessage;

  const _FrameDropTarget({
    required this.label,
    required this.image,
    required this.onDrop,
    required this.onClear,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.confirmMessage,
  });

  @override
  State<_FrameDropTarget> createState() => _FrameDropTargetState();
}

class _FrameDropTargetState extends State<_FrameDropTarget> {
  /// A file dragged in from the OS is over the slot. In-app drags report
  /// themselves through the [DragTarget] instead.
  bool _osDragging = false;

  /// Changed on every accepted drop to flash the slot's ring.
  Object? _confirmToken;
  bool _showNote = false;
  Timer? _noteTimer;

  @override
  void dispose() {
    _noteTimer?.cancel();
    super.dispose();
  }

  void _setOsDragging(bool value) {
    if (_osDragging != value) setState(() => _osDragging = value);
  }

  /// `1a` 「拖入或点击选择」: a click opens the system picker for one image.
  Future<void> _pickFrame() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    widget.onDrop(AppImage(path: picked.path, name: picked.name));
  }

  /// Takes a dropped picture and confirms it where it landed (`00d` 确认):
  /// the slot's ring and a note under it — not a snackbar, and no focus taken.
  void _accept(AppImage image) {
    widget.onDrop(image);
    _noteTimer?.cancel();
    setState(() {
      _confirmToken = Object();
      _showNote = true;
    });
    _noteTimer = Timer(_kDropNoteHold, () {
      if (mounted) setState(() => _showNote = false);
    });
    _announceDrop(context, widget.confirmMessage);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final l10n = AppLocalizations.of(context)!;
    final bool isMobile = Responsive.isMobile(context);
    final double slotHeight = Responsive.value<double>(
      context,
      mobile: 104,
      tablet: 96,
      desktop: 92,
    );
    final image = widget.image;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpace.s4),
        DropTarget(
          onDragEntered: (_) => _setOsDragging(true),
          onDragExited: (_) => _setOsDragging(false),
          onDragDone: (details) {
            _setOsDragging(false);
            if (details.files.isNotEmpty) {
              final file = details.files.first;
              if (AppConstants.isImageFile(file.path)) {
                _accept(AppImage(path: file.path, name: file.name));
              }
            }
          },
          // `00d` 「可放」: an in-app drag this slot would take, still elsewhere.
          child: ValueListenableBuilder<Object?>(
            valueListenable: AppDragSession.current,
            builder: (context, payload, _) => DragTarget<AppImage>(
              onWillAcceptWithDetails: (details) => _isDroppableImage(details.data),
              onAcceptWithDetails: (details) => _accept(details.data),
              builder: (context, candidateData, rejectedData) {
                final AppDropZoneState state = rejectedData.isNotEmpty
                    ? AppDropZoneState.reject
                    : (candidateData.isNotEmpty || _osDragging)
                    ? AppDropZoneState.hover
                    : _isDroppableImage(payload)
                    ? AppDropZoneState.armed
                    : AppDropZoneState.rest;

                void onTap() {
                  if (isMobile) {
                    Provider.of<AppState>(context, listen: false).setWorkbenchTab(0);
                  } else {
                    _pickFrame();
                  }
                }

                return AppDropConfirmRing(
                  trigger: _confirmToken,
                  child: SizedBox(
                    height: slotHeight,
                    child: image == null
                        ? _DropSlot(
                            state: state,
                            icon: widget.emptyIcon,
                            title: switch (state) {
                              AppDropZoneState.hover => l10n.dropRelease,
                              AppDropZoneState.reject => l10n.dropImagesOnly,
                              _ => widget.emptyTitle,
                            },
                            hint: state == AppDropZoneState.rest || state == AppDropZoneState.armed
                                ? (isMobile ? l10n.tapToPick : l10n.videoDropOrPick)
                                : null,
                            onTap: onTap,
                          )
                        : _FilledFrameSlot(
                            image: image,
                            state: state,
                            onClear: widget.onClear,
                            onTap: onTap,
                          ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: AppSpace.s4),
        AnimatedSize(
          duration: AppMotion.durationOf(context, AppMotion.reveal),
          curve: AppMotion.enter,
          alignment: AlignmentDirectional.topStart,
          child: _showNote
              ? AppDropNote(widget.confirmMessage)
              : Text(
                  image?.name ?? l10n.videoFrameOptional,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelSmall?.mono.copyWith(
                    fontWeight: FontWeight.w400,
                    color: image == null ? colorScheme.outline : colorScheme.onSurfaceVariant,
                  ),
                ),
        ),
      ],
    );
  }
}

/// A frame slot holding its image: the picture at r10 and a round clear
/// button on the image plate, top-right (20 / 22 / 24 by width). While a drag
/// is in flight only the edge changes over the picture, with the words on the
/// image plate.
class _FilledFrameSlot extends StatelessWidget {
  const _FilledFrameSlot({
    required this.image,
    required this.state,
    required this.onClear,
    required this.onTap,
  });

  final AppImage image;
  final AppDropZoneState state;
  final VoidCallback onClear;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final bool isMobile = Responsive.isMobile(context);
    final double clearSize = Responsive.value<double>(context, mobile: 24, tablet: 22, desktop: 20);
    final double inset = isMobile ? AppSpace.s6 : AppSpace.s4;
    final radius = BorderRadius.circular(AppRadius.control);
    final String? message = switch (state) {
      AppDropZoneState.hover => l10n.dropRelease,
      AppDropZoneState.reject => l10n.dropImagesOnly,
      _ => null,
    };

    return Material(
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image(image: image.imageProvider, fit: BoxFit.cover),
            // A replacement in flight: the ladder's edge alone — `ground:
            // false`, no `--tint` over the picture.
            if (state != AppDropZoneState.rest)
              IgnorePointer(
                child: AppDropZoneFrame(
                  state: state,
                  ground: false,
                  child: message == null
                      ? null
                      : Center(
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpace.s6),
                            child: _PlateLabel(
                              message,
                              // What a release does to the picture under it,
                              // where the slot has the room.
                              hint: state == AppDropZoneState.hover ? l10n.dropReplacesFrame : null,
                            ),
                          ),
                        ),
                ),
              ),
            Positioned(
              top: inset,
              right: inset,
              child: _PlateCloseButton(size: clearSize, tooltip: l10n.clear, onPressed: onClear),
            ),
          ],
        ),
      ),
    );
  }
}
