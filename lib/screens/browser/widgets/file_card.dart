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
import '../../workbench/widgets/preview/media_preview_dialog.dart' show previewHeroTag;
import '../../workbench/widgets/preview/video_thumbnail.dart';


class FileCard extends StatefulWidget {
  final BrowserFile file;
  final bool isSelected;

  /// Whether this file is in the staging area.
  ///
  /// Orthogonal to [isSelected] and drawn in a different register — a corner
  /// badge rather than the edge — because both can be true at once and `11b`
  /// draws exactly that case. Selection is what the next action applies to;
  /// staging is a mark that outlives the selection entirely.
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

  @override
  State<FileCard> createState() => _FileCardState();
}

class _FileCardState extends State<FileCard> {
  String _dimensions = "";
  bool _isPressed = false;
  bool _isHovered = false;

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
    if (widget.file.path != oldWidget.file.path && widget.file.category == FileCategory.image) {
      _getImageDimensions();
    }
  }

  Future<void> _getImageDimensions() async {
    final metadata = await ImageMetadataService().getMetadata(widget.file.path);
    if (metadata != null && mounted) {
      setState(() {
        _dimensions = metadata.displayString;
      });
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Shared with the gallery and the assistant panel — see [ThumbnailFit].
    // `select` keeps a grid of these out of AppState's general traffic.
    final thumbFit = context.select<AppState, ThumbnailFit>((s) => s.thumbnailFit);

    // Glass, not opaque. `B1` answers the open question about the file area by
    // following `A1`: the grid is transparent and the window's backdrop shows
    // through it, so each card is a translucent panel over that rather than a
    // solid tile on a solid column. The two alphas are the frame's own — dark
    // needs the extra 7 points or the cards dissolve into the backdrop.
    final cardGround = colorScheme.surface.withValues(alpha: isDark ? 0.62 : 0.55);

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
          duration: AppMotion.durationOf(context, AppMotion.hover),
          curve: AppMotion.enter,
          child: AnimatedContainer(
          duration: AppMotion.durationOf(context, AppMotion.state),
          curve: AppMotion.enter,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            color: widget.isSelected
                ? colorScheme.accentTint
                // Hover is greyscale. The accent on this screen means selected,
                // and a card that tints on the way past says the pointer
                // selected it.
                : (_isHovered ? colorScheme.surfaceContainerHigh.withValues(alpha: 0.7) : cardGround),
            border: Border.all(
              // Only a selected card is outlined. The thumbnails supply their
              // own edges; a border on every one turns the grid into a mesh and
              // leaves the selected card with nothing of its own to say.
              color: widget.isSelected ? colorScheme.primary : Colors.transparent,
              width: 2,
            ),
            boxShadow: widget.isSelected
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.05),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                                Expanded(
                                  child: _maybeHero(
                                    widget.file.category == FileCategory.image
                                        ? Image(
                                            image: ResizeImage(
                                              widget.file.imageProvider,
                                              // Snapped to a ladder, not taken
                                              // at the painted size — see
                                              // [thumbnailDecodeWidth].
                                              width: thumbnailDecodeWidth(context, widget.thumbnailSize),
                                            ),
                                            fit: thumbFit.boxFit,
                                          )
                                        : widget.file.category == FileCategory.video
                                            ? VideoThumbnail(videoPath: widget.file.path, fit: thumbFit.boxFit)
                                            : Center(child: Icon(widget.file.icon, size: 48, color: widget.file.color.withAlpha(150))),
                                  ),
                                ),

                  // A footer strip on the card, not a scrim on the picture.
                  // `B1` draws it the way the workbench's gallery card already
                  // does — the name below the image with a hairline between,
                  // rather than a black band covering whatever the thumbnail
                  // had along its bottom edge. Left-aligned for the same
                  // reason a filename is: the end is what gets truncated, so
                  // the beginning has to start in a predictable place.
                  //
                  // Unfilled since the redraw: the card's own glass is the
                  // ground, and a second opaque tone under the name would put
                  // a solid block back on a surface the frame wants
                  // translucent. The rule is `surfaceContainer` rather than
                  // the app's usual hairline — one step subtler, because at
                  // `outlineVariant` every card in the grid reads as boxed.
                  Container(
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: colorScheme.surfaceContainer),
                      ),
                    ),
                    child: Text(
                      widget.file.name,
                      style: Theme.of(context).textTheme.labelSmall?.mono.copyWith(
                            color: widget.isSelected
                                ? colorScheme.onAccentTint
                                : colorScheme.onSurfaceVariant,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              // A pill that wraps the figures, not a band across the card's full
              // width: the band reads as a caption the image happens to start
              // under, and it dims the top of every thumbnail to say it.
              if (_dimensions.isNotEmpty)
                Positioned(
                  top: 8,
                  left: 6,
                  right: 6,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
                      decoration: BoxDecoration(
                        color: AppOverlay.ink.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        _dimensions,
                        style: Theme.of(context).textTheme.labelSmall?.mono.copyWith(
                          color: AppOverlay.onInk,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              // The staging mark. On the overlay ink rather than the accent,
              // so it stays legible over any thumbnail and cannot be confused
              // with the selection edge it may be sitting inside.
              if (widget.isStaged)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: AppOverlay.ink.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                    ),
                    child: const Icon(Icons.inbox_rounded, size: 11, color: Colors.white),
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

    // `12d`'s second entry point. The drag carries files rather than paths so
    // the drop target can label itself with a count without going back to the
    // browser state for it.
    return Draggable<List<BrowserFile>>(
      data: widget.dragPayload,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _DragChip(count: widget.dragPayload.length),
      // The card stays put and dims: a grid that reflows mid-drag loses the
      // drop target the user was aiming at.
      childWhenDragging: Opacity(opacity: 0.4, child: card),
      child: card,
    );
  }
}

/// What follows the pointer during a drag onto a folder.
class _DragChip extends StatelessWidget {
  final int count;

  const _DragChip({required this.count});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.only(left: 12, top: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppOverlay.ink,
          borderRadius: BorderRadius.circular(AppRadius.control),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Text(
          l10n.dragMoveHint(count),
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: AppOverlay.onInk, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}
