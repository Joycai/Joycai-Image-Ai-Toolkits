import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../core/thumbnail_decode.dart';
import '../../../core/thumbnail_fit.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/browser_file.dart';
import '../../../services/image_metadata_service.dart';
import '../../../state/app_state.dart';
import '../../../widgets/drag/app_drag_session.dart';
import '../../../widgets/glass/glass_controls.dart' show measureGlassText;
import '../../workbench/widgets/preview/media_preview_dialog.dart' show previewHeroTag;
import '../../workbench/widgets/preview/video_thumbnail.dart';
import 'browser_drag_chip.dart';
import 'browser_file_list_row.dart' show browserFileTypeColors;

/// The play glyph laid straight on a video frame (`rgba(255,255,255,.85)`) —
/// the same literal the workbench card uses, for the same reason: there is no
/// plate under it.
const Color _playGlyphInk = Color(0xD9FFFFFF);

/// The selection check's drop shadow, lifting it off a photograph.
const Color _checkShadow = Color(0x4D000000);

/// Inset of the badges from the thumbnail's edge.
const double _badgeInset = AppSpace.s6;

/// One tile of the file grid — `B1a · 1a`.
///
/// A panel card (r10, 1px hairline, 6 of padding) over the transparent grid:
/// the thumbnail at r6 and the file name in mono 11 under it. Selected, the
/// hairline goes and a 2px accent ring with the 4px `--ring` halo sits outside
/// the card, with a solid accent check at the thumbnail's top-left.
class FileCard extends StatefulWidget {
  final BrowserFile file;
  final bool isSelected;

  /// Whether this file is in the staging area.
  ///
  /// Orthogonal to [isSelected] and drawn in a different register — a corner
  /// plate rather than the edge — because both can be true at once.
  final bool isStaged;

  final double thumbnailSize;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final Function(Offset) onSecondaryTap;

  /// Hero namespace pairing this card's thumbnail with the media preview it
  /// opens into (see [previewHeroTag]); null leaves the card un-tagged.
  final String? heroScope;

  /// The files this card drags. Normally the whole selection when the card is
  /// part of it, this one file otherwise — resolved by the caller, because
  /// only the screen knows what is selected.
  final List<BrowserFile> dragPayload;

  const FileCard({
    super.key,
    required this.file,
    required this.isSelected,
    this.isStaged = false,
    required this.thumbnailSize,
    required this.onTap,
    this.onDoubleTap,
    required this.onSecondaryTap,
    this.heroScope,
    this.dragPayload = const [],
  });

  /// The card's height for a column [width]: the thumbnail keeps `1a`'s
  /// 150-in-180 proportion, plus the frame, the gap and one mono line.
  static double mainAxisExtentFor(BuildContext context, double width) {
    final nameLine = MediaQuery.textScalerOf(context).scale(16);
    return (width * 5 / 6) + 2 + AppSpace.s6 * 3 + nameLine;
  }

  @override
  State<FileCard> createState() => _FileCardState();
}

class _FileCardState extends State<FileCard> {
  String _dimensions = '';
  bool _isPressed = false;
  bool _isHovered = false;

  /// This card's files are being dragged.
  bool _dragging = false;

  void _dragStarted() {
    setState(() => _dragging = true);
    AppDragSession.begin(widget.dragPayload);
  }

  /// Wired to every end callback: `onDragEnd` is skipped once the card has
  /// been unmounted — a drop that moved its file away — and the session must
  /// end regardless.
  void _dragEnded() {
    if (mounted && _dragging) setState(() => _dragging = false);
    AppDragSession.end();
  }

  @override
  void initState() {
    super.initState();
    if (widget.file.category == FileCategory.image) {
      _getImageDimensions();
    }
  }

  @override
  void didUpdateWidget(FileCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.file.path != oldWidget.file.path) {
      _dimensions = '';
      if (widget.file.category == FileCategory.image) _getImageDimensions();
    }
  }

  Future<void> _getImageDimensions() async {
    final path = widget.file.path;
    final metadata = await ImageMetadataService().getMetadata(path);
    if (metadata != null && mounted && widget.file.path == path) {
      setState(() => _dimensions = metadata.displayString);
    }
  }

  /// Tags media thumbnails for the preview's shared-element flight; documents
  /// never open into the preview, so they stay un-tagged.
  Widget _maybeHero(Widget thumbnail) {
    final isMedia = widget.file.category == FileCategory.image ||
        widget.file.category == FileCategory.video;
    if (widget.heroScope == null || !isMedia) return thumbnail;
    return Hero(
      tag: previewHeroTag(widget.heroScope!, widget.file.path),
      child: thumbnail,
    );
  }

  Widget _buildPicture(BuildContext context, ThumbnailFit thumbFit) {
    switch (widget.file.category) {
      case FileCategory.image:
        return Image(
          image: ResizeImage(
            widget.file.imageProvider,
            // Snapped to a ladder, not taken at the painted size — see
            // [thumbnailDecodeWidth].
            width: thumbnailDecodeWidth(context, widget.thumbnailSize),
          ),
          fit: thumbFit.boxFit,
        );
      case FileCategory.video:
        return VideoThumbnail(videoPath: widget.file.path, fit: thumbFit.boxFit);
      default:
        // `1a` draws text and audio as a centred glyph; it takes the type's
        // plate from the list view so the two views name a type alike.
        final plate = browserFileTypeColors(context, widget.file.category);
        return Center(
          child: Container(
            width: AppSize.touch,
            height: AppSize.touch,
            decoration: BoxDecoration(
              color: plate.background,
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: Icon(widget.file.icon, size: 24, color: plate.foreground),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    final selected = widget.isSelected;
    // Shared with the gallery and the assistant panel — see [ThumbnailFit].
    // `select` keeps a grid of these out of AppState's general traffic.
    final thumbFit = context.select<AppState, ThumbnailFit>((s) => s.thumbnailFit);
    final hoverDuration = AppMotion.durationOf(context, AppMotion.hover);

    final plateStyle = textTheme.labelSmall!.mono.copyWith(
      color: AppOverlay.onImagePlate,
      fontWeight: FontWeight.w400,
      height: AppType.tightHeight,
    );

    final thumbnail = ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The staged plate keeps its word only while the word fits beside
            // the check; past that it is the glyph alone, named in a tooltip.
            final labelWidth = measureGlassText(context, l10n.stagedBadge, plateStyle);
            final stagedWithLabel =
                _badgeInset + 20 + _badgeInset + 5 + 12 + 4 + labelWidth + 5 + _badgeInset <=
                    constraints.maxWidth;

            return Stack(
              fit: StackFit.expand,
              children: [
                _maybeHero(_buildPicture(context, thumbFit)),
                if (widget.file.category == FileCategory.video)
                  const Center(
                    child: Icon(Icons.play_circle_outline, size: 28, color: _playGlyphInk),
                  ),
                // Dimensions on hover only: `1a` keeps the resting card to the
                // picture and its name, and the list view carries them always.
                if (_dimensions.isNotEmpty)
                  Positioned(
                    left: _badgeInset,
                    right: _badgeInset,
                    bottom: _badgeInset,
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: AnimatedOpacity(
                        opacity: _isHovered ? 1 : 0,
                        duration: hoverDuration,
                        curve: AppMotion.quick,
                        child: _PlateBadge(child: Text(
                          _dimensions,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: plateStyle,
                        )),
                      ),
                    ),
                  ),
                if (selected)
                  Positioned(
                    top: _badgeInset,
                    left: _badgeInset,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                        boxShadow: const [
                          BoxShadow(color: _checkShadow, blurRadius: 3, offset: Offset(0, 1)),
                        ],
                      ),
                      child: Icon(Icons.check, size: AppSize.iconSm, color: scheme.onPrimary),
                    ),
                  ),
                if (widget.isStaged)
                  Positioned(
                    top: _badgeInset,
                    right: _badgeInset,
                    child: Tooltip(
                      message: l10n.stagedBadge,
                      child: _PlateBadge(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.inbox_outlined, size: 12, color: AppOverlay.onImagePlate),
                            if (stagedWithLabel) ...[
                              const SizedBox(width: AppSpace.s4),
                              Text(l10n.stagedBadge, maxLines: 1, style: plateStyle),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );

    // Same shape as ImageCard's press: a Listener, not onTapDown, because the
    // double-tap recognizer defers a quick click's onTapDown past the 300ms
    // disambiguation window. The open/select commits keep their deferral; the
    // card visibly taking the press does not.
    final card = Listener(
      onPointerDown: (_) => setState(() => _isPressed = true),
      onPointerUp: (_) => setState(() => _isPressed = false),
      onPointerCancel: (_) => setState(() => _isPressed = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        onSecondaryTapDown: (details) => widget.onSecondaryTap(details.globalPosition),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: AnimatedScale(
            scale: _isPressed ? 0.97 : 1.0,
            duration: hoverDuration,
            curve: AppMotion.quick,
            child: AnimatedContainer(
              duration: hoverDuration,
              curve: AppMotion.quick,
              padding: const EdgeInsets.all(AppSpace.s6),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(AppRadius.control),
                border: Border.all(
                  color: selected
                      ? Colors.transparent
                      : (_isHovered ? scheme.outline : scheme.outlineVariant),
                ),
                // Outside the card (`0 0 0 2px --p, 0 0 0 4px --ring`), halo
                // first and the solid ring over it; the card's own opaque
                // ground hides the part of each shadow under it.
                boxShadow: selected
                    ? [
                        BoxShadow(color: scheme.accentRing, spreadRadius: 4),
                        BoxShadow(color: scheme.primary, spreadRadius: 2),
                      ]
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: thumbnail),
                  const SizedBox(height: AppSpace.s6),
                  Text(
                    widget.file.name,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelSmall!.mono.copyWith(
                      color: selected ? scheme.onAccentTint : scheme.onSurface,
                      fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.dragPayload.isEmpty) return card;

    return Draggable<List<BrowserFile>>(
      data: widget.dragPayload,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: BrowserFileDragChip(count: widget.dragPayload.length),
      onDragStarted: _dragStarted,
      onDragEnd: (_) => _dragEnded(),
      onDragCompleted: _dragEnded,
      onDraggableCanceled: (_, _) => _dragEnded(),
      // `00d`: dragged out of the grid, the card stays where it is at half
      // strength — it may not move at all, and a grid that reflows mid-drag
      // loses the folder the user was aiming at. An Opacity in place rather
      // than `childWhenDragging`, so the thumbnail is not rebuilt.
      child: Opacity(opacity: _dragging ? 0.5 : 1, child: card),
    );
  }
}

/// A label on the fixed dark plate laid over a thumbnail: r4, 1×5 padding.
/// Never themed and never frosted — see [AppOverlay.imagePlate].
class _PlateBadge extends StatelessWidget {
  const _PlateBadge({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppOverlay.imagePlate,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        child: child,
      ),
    );
  }
}
