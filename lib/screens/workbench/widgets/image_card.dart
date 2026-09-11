import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_effects.dart';
import '../../../core/app_theme.dart';
import '../../../core/constants.dart';
import '../../../core/design_tokens.dart';
import '../../../core/responsive.dart';
import '../../../core/thumbnail_decode.dart';
import '../../../core/thumbnail_fit.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/app_image.dart';
import '../../../services/image_metadata_service.dart';
import '../../../services/video_thumbnail_service.dart';
import '../../../state/app_state.dart';
import '../../../state/workbench_ui_state.dart';
import '../../../widgets/drag/app_drag_follower.dart';
import '../../../widgets/drag/app_drag_session.dart';
import '../../../widgets/glass/app_glass.dart';
import 'image_card_context_menu.dart';
import 'preview/media_preview_dialog.dart' show previewHeroTag;
import 'result_feedback_dialog.dart';

/// The play glyph laid straight on a video frame (`A1 · 1a`:
/// `rgba(255,255,255,.85)`).
///
/// Pure white rather than [AppOverlay.onImagePlate]: there is no plate under
/// this one, and the warm off-white reads as a tint against a cool frame.
const Color _playGlyphInk = Color(0xD9FFFFFF);

/// The selection number's drop shadow (`0 1px 3px rgba(0,0,0,.3)`).
///
/// Black, not `colorScheme.shadow`: it lifts the badge off a photograph, which
/// has no brightness of its own for the scheme to follow.
const Color _selectionBadgeShadow = Color(0x4D000000);

/// The selected ring's outer halo (`--p` at 30%), outside the 2px solid ring.
const double _ringHaloAlpha = 0.3;

/// Inset of every badge and the hover strip from the card's edge (`A1 · 1a`).
const double _badgeInset = AppSpace.s6;

/// A single thumbnail tile in the gallery grid. Handles its own thumbnail
/// loading and hover/selection chrome; all file actions are delegated to
/// [showImageCardContextMenu].
class ImageCard extends StatefulWidget {
  final AppImage imageFile;

  /// This picture's place in the selection, counting from 1; `0` when it is
  /// not selected.
  ///
  /// A number rather than a flag because the order is the order the pictures
  /// reach the model, and the reference strip in the config panel labels them
  /// the same way — a prompt that refers to "the second image" needs the two
  /// to agree.
  final int selectionNumber;

  final double thumbnailSize;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;

  /// Hero namespace pairing this tile's thumbnail with the media preview it
  /// opens into (see [previewHeroTag]); null leaves the tile un-tagged.
  final String? heroScope;

  const ImageCard({
    super.key,
    required this.imageFile,
    required this.selectionNumber,
    required this.thumbnailSize,
    required this.onTap,
    this.onDoubleTap,
    this.heroScope,
  });

  bool get isSelected => selectionNumber > 0;

  @override
  State<ImageCard> createState() => _ImageCardState();
}

class _ImageCardState extends State<ImageCard> {
  String _dimensions = "";
  bool _isHovering = false;
  bool _isPressed = false;
  String? _videoThumbnailPath;

  @override
  void initState() {
    super.initState();
    // Seed from the cache first: a tile scrolled back into view already has its
    // measurement, and going through the async path for it would cost a
    // scheduled task and a second build to show a value that was in hand.
    _dimensions = ImageMetadataService().peek(widget.imageFile.path)?.displayString ?? "";
    if (_dimensions.isEmpty) _getImageDimensions();
    _loadVideoThumbnail();
  }

  @override
  void didUpdateWidget(covariant ImageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageFile.path != widget.imageFile.path) {
      // Same cache-first rule as initState — a recycled tile usually lands on a
      // file the grid has already measured.
      final known = ImageMetadataService().peek(widget.imageFile.path);
      setState(() {
        _dimensions = known?.displayString ?? "";
        _videoThumbnailPath = null;
      });
      if (known == null) _getImageDimensions();
      _loadVideoThumbnail();
    }
  }

  Future<void> _getImageDimensions() async {
    final metadata = await ImageMetadataService().getMetadata(widget.imageFile.path);
    if (metadata != null && mounted) {
      setState(() {
        _dimensions = metadata.displayString;
      });
    }
  }

  Future<void> _loadVideoThumbnail() async {
    if (!AppConstants.isVideoFile(widget.imageFile.path)) return;

    final path = widget.imageFile.path;
    final cachePath = await VideoThumbnailService.instance.getThumbnail(path);
    // Widget may have been recycled to a different file while awaiting.
    if (cachePath != null && mounted && widget.imageFile.path == path) {
      setState(() {
        _videoThumbnailPath = cachePath;
      });
    }
  }

  Widget _buildThumbnail(BuildContext context, ColorScheme colorScheme, ThumbnailFit thumbFit,
      {double? width, double? height}) {
    final isVideo = AppConstants.isVideoFile(widget.imageFile.path);

    if (isVideo) {
      // `A1 · 1a` / `A2 · 1a`: the extracted frame and a play glyph, nothing
      // else. No scrim over the frame and no "video" label — the glyph is the
      // whole signal. The glyph stays inside the thumbnail (not on the card)
      // so the drag proxy still says what is being dragged.
      return Container(
        width: width,
        height: height,
        color: colorScheme.surfaceContainerHighest,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_videoThumbnailPath != null)
              Positioned.fill(
                child: Image.file(
                  File(_videoThumbnailPath!),
                  fit: thumbFit.boxFit,
                  errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                ),
              ),
            const Icon(
              Icons.play_circle_outline,
              size: 28,
              color: _playGlyphInk,
            ),
          ],
        ),
      );
    }

    return Image(
      image: ResizeImage(
        widget.imageFile.imageProvider,
        // Snapped to a ladder rather than taken at the exact painted size —
        // see [thumbnailDecodeWidth]. The size slider is a drag, and a decode
        // width that follows it pixel for pixel re-decodes the whole visible
        // grid on every frame of that drag.
        width: thumbnailDecodeWidth(context, width ?? widget.thumbnailSize),
      ),
      fit: thumbFit.boxFit,
      errorBuilder: (context, error, stackTrace) => Container(
        color: colorScheme.surfaceContainerHighest,
        child: Icon(Icons.broken_image, color: colorScheme.onSurfaceVariant),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isMobile = Responsive.isMobile(context);
    // Read once here and handed down, rather than looked up in
    // [_buildThumbnail]: that runs three times per build (drag proxy, ghost,
    // card) and one dependency is enough. `select` keeps the card out of
    // AppState's general notification traffic.
    final thumbFit = context.select<AppState, ThumbnailFit>((s) => s.thumbnailFit);

    return Draggable<AppImage>(
      data: widget.imageFile,
      // `00d · 1e` 图片卡: the opaque 88 thumbnail in a 2px accent ring, with
      // the pointer off its top-left corner.
      feedback: _buildDragFollower(context),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      // `00d`: a drag out to another container leaves the source at .5 —
      // it is still here, and a drop elsewhere may not move it.
      childWhenDragging: Opacity(
        opacity: 0.5,
        child: _buildCardContent(context, colorScheme, isMobile, thumbFit),
      ),
      onDragStarted: () {
        // A drag steals the pointer stream: the Listener below never sees the
        // up event once the drag proxy takes over, so the press is released
        // here or it sticks at 0.97 until the next click.
        setState(() => _isPressed = false);
        // Slots not under the pointer yet learn of the drag here, to show
        // 「可放」.
        AppDragSession.begin(widget.imageFile);
      },
      // All three: `onDragEnd` is skipped once this card is unmounted
      // mid-drag (a recycled grid cell), the other two are not.
      onDragEnd: (_) => AppDragSession.end(),
      onDragCompleted: AppDragSession.end,
      onDraggableCanceled: (_, _) => AppDragSession.end(),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        // A Listener, not onTapDown: with the double-tap recognizer in the
        // arena, a quick click's onTapDown fires only after the 300ms
        // disambiguation timeout — the press would light up after the finger
        // had already left. The selection *commit* keeps that deferral (click
        // selects, double-click opens); the feedback must not wait with it.
        child: Listener(
          onPointerDown: (_) => setState(() => _isPressed = true),
          onPointerUp: (_) => setState(() => _isPressed = false),
          onPointerCancel: (_) => setState(() => _isPressed = false),
          child: GestureDetector(
            onTap: widget.onTap,
            onDoubleTap: widget.onDoubleTap,
            onSecondaryTapDown: (details) => showImageCardContextMenu(context, imageFile: widget.imageFile, position: details.globalPosition),
            onLongPressStart: (details) => showImageCardContextMenu(context, imageFile: widget.imageFile, position: details.globalPosition),
            child: AnimatedScale(
              scale: _isPressed ? 0.97 : 1.0,
              duration: AppMotion.durationOf(context, AppMotion.hover),
              curve: AppMotion.quick,
              child: _buildCardContent(context, colorScheme, isMobile, thumbFit),
            ),
          ),
        ),
      ),
    );
  }

  /// What follows the pointer while this card is dragged (`00d · 1e` 图片卡).
  ///
  /// A picture reuses the grid's own decode — the same [ResizeImage] key the
  /// card paints — so starting a drag decodes nothing. A video carries its
  /// extracted frame with the play glyph over it, so the follower still says
  /// it is a video; a video whose frame has not been extracted yet has no
  /// picture to show and falls back to the named chip.
  Widget _buildDragFollower(BuildContext context) {
    if (!AppConstants.isVideoFile(widget.imageFile.path)) {
      return AppImageDragFollower(
        image: ResizeImage(
          widget.imageFile.imageProvider,
          width: thumbnailDecodeWidth(context, widget.thumbnailSize),
        ),
      );
    }

    final frame = _videoThumbnailPath;
    if (frame == null) {
      return AppDragFollower(icon: Icons.movie_outlined, label: widget.imageFile.name);
    }

    const double size = 88;
    return Stack(
      children: [
        AppImageDragFollower(image: FileImage(File(frame)), size: size),
        Positioned(
          left: AppDragFollower.pointerOffset.dx,
          top: AppDragFollower.pointerOffset.dy,
          width: size,
          height: size,
          child: const Center(
            child: Icon(Icons.play_circle_outline, size: 28, color: _playGlyphInk),
          ),
        ),
      ],
    );
  }

  Widget _buildCardContent(
      BuildContext context, ColorScheme colorScheme, bool isMobile, ThumbnailFit thumbFit) {
    final isVideo = AppConstants.isVideoFile(widget.imageFile.path);
    final selected = widget.isSelected;
    // On touch layouts there is no hover, so the strip is permanent there —
    // unchanged from before the restyle.
    // Under a pointer the strip follows hover. A phone has no hover, and a
    // strip on every card buries the badges, so there it belongs to the
    // cards you have selected — tap selects, and the actions appear.
    final showActions = !isVideo && (_isHovering || (isMobile && widget.selectionNumber > 0));

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: AppMotion.durationOf(context, AppMotion.hover),
        curve: AppMotion.quick,
        decoration: BoxDecoration(
          // `A1 · 1a`: a thumbnail is a control-sized tile — r10, no border,
          // no resting shadow. The picture is the card.
          borderRadius: BorderRadius.circular(AppRadius.control),
          // The ground a contain-fit picture letterboxes onto.
          color: colorScheme.surfaceContainerHighest,
          // The selected ring sits *outside* the picture
          // (`0 0 0 2px --p, 0 0 0 4px --p 30%`), so a selected photo is not
          // washed or shrunk. Shadows paint outside the clip below, and in
          // list order — the halo first, the solid ring over it.
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: _ringHaloAlpha),
                    spreadRadius: 4,
                  ),
                  BoxShadow(
                    color: colorScheme.primary,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // During a flight the framework hides this child and flies the
            // shuttle in the overlay, leaving the tile's ground and badges in
            // place — which is exactly the hole a promoted photo should leave
            // behind.
            if (widget.heroScope == null)
              _buildThumbnail(context, colorScheme, thumbFit)
            else
              Hero(
                tag: previewHeroTag(widget.heroScope!, widget.imageFile.path),
                child: _buildThumbnail(context, colorScheme, thumbFit),
              ),
            // Bottom-left: the file name, then the dimensions badge on the
            // edge. `A1` draws only the dimensions; the name used to have a
            // footer strip of its own and appears nowhere else on the card
            // (the grid excludes semantics and has no tooltip), so it moved
            // onto a plate above the dimensions rather than disappearing.
            //
            // Bounded on the right, not just placed on the left: the labels
            // size to their text, and a dimension, aspect ratio and file size
            // is routinely wider than a three-column card. Bounding them lets
            // the text ellipsize instead of being cut mid-number by the clip.
            Positioned(
              left: _badgeInset,
              right: _badgeInset,
              bottom: _badgeInset,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPlateBadge(context, widget.imageFile.name, mono: false),
                    if (_dimensions.isNotEmpty) ...[
                      const SizedBox(height: AppSpace.s4),
                      _buildPlateBadge(context, _dimensions),
                    ],
                  ],
                ),
              ),
            ),
            if (selected)
              Positioned(
                top: _badgeInset,
                left: _badgeInset,
                child: _buildSelectionBadge(context, colorScheme),
              ),
            // The provenance badge (`20a`): which assistant prompt version
            // generated this picture. Derived from the tagged task record via
            // the session-scoped map on the state — present only while that
            // session is the live one.
            Positioned(
              top: _badgeInset,
              right: _badgeInset,
              child: Builder(builder: (context) {
                final version = context.select<WorkbenchUIState, int?>(
                    (w) => w.resultVersionByPath[widget.imageFile.path]);
                if (version == null) return const SizedBox.shrink();
                return _buildPlateBadge(context, 'v$version', fontWeight: FontWeight.w500);
              }),
            ),
            if (!isVideo)
              Positioned(
                left: _badgeInset,
                right: _badgeInset,
                bottom: _badgeInset,
                child: Align(
                  alignment: Alignment.bottomRight,
                  // Mounted only while shown, so a screen of idle cards holds
                  // no strip at all; the switcher still fades it both ways.
                  child: AnimatedSwitcher(
                    duration: AppMotion.durationOf(context, AppMotion.hover),
                    switchInCurve: AppMotion.quick,
                    switchOutCurve: AppMotion.quick,
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.bottomRight,
                      children: [...previous, ?current],
                    ),
                    child: showActions
                        ? KeyedSubtree(
                            key: const ValueKey('image-card-actions'),
                            child: _buildHoverActions(context, persistent: isMobile),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// A label on the fixed dark plate (`A1 · 1a` 「尺寸角标」): r4, 1×5 padding,
  /// 11px. [mono] for figures — dimensions, a version — and off for a name.
  ///
  /// Never themed and never frosted: see [AppOverlay.imagePlate]. A blur per
  /// badge on every card of a grid was more `saveLayer` passes a frame than
  /// the raster thread could finish.
  Widget _buildPlateBadge(
    BuildContext context,
    String text, {
    bool mono = true,
    FontWeight fontWeight = FontWeight.w400,
  }) {
    final base = Theme.of(context).textTheme.labelSmall;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppOverlay.imagePlate,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: (mono ? base?.mono : base)?.copyWith(
            color: AppOverlay.onImagePlate,
            fontWeight: fontWeight,
            height: AppType.tightHeight,
          ),
        ),
      ),
    );
  }

  /// The picture's position in the selection.
  ///
  /// A number rather than a tick: with several reference images the model is
  /// given them in this order, and the user has no other way to see it on the
  /// grid. Deliberately not animated — the number is read, not watched.
  Widget _buildSelectionBadge(BuildContext context, ColorScheme colorScheme) {
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colorScheme.primary,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(color: _selectionBadgeShadow, blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
      child: Text(
        '${widget.selectionNumber}',
        maxLines: 1,
        style: Theme.of(context).textTheme.labelSmall?.mono.copyWith(
              color: colorScheme.onPrimary,
              fontWeight: FontWeight.w600,
              height: 1,
              // Tracking trails the last glyph and would push a lone digit
              // off the circle's centre.
              letterSpacing: 0,
            ),
      ),
    );
  }

  /// Compare / mask / crop / feedback-to-assistant, on a dark lens of glass in
  /// the bottom-right corner (`A1 · 1a` 悬停条: G3, tone dark, r6, h28).
  ///
  /// [persistent] is the touch layout, where the strip sits on every card at
  /// once rather than on the one under the pointer. There it renders as the
  /// glass's opaque fallback: a backdrop blur per visible card is exactly the
  /// frame budget the glass grades exist to protect.
  Widget _buildHoverActions(BuildContext context, {required bool persistent}) {
    final l10n = AppLocalizations.of(context)!;
    // The feedback action (`20a`) exists only once the assistant has staged a
    // prompt version — there is nothing to give feedback *on* before that —
    // and is withdrawn while a turn is running, so a click cannot land in the
    // middle of one. Both `promptVersions` and `isRunning` live on the
    // session, so the button is wrapped in a ListenableBuilder on it: reading
    // once missed a version that staged while the cursor sat still, and
    // offered feedback during a live turn.
    final session =
        Provider.of<WorkbenchUIState>(context, listen: false).optimizerSession;

    Widget strip = AppGlass(
      grade: GlassGrade.lens,
      tone: GlassTone.dark,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      // A Builder so the buttons read the ink this glass hands down.
      child: Builder(
        builder: (context) => SizedBox(
          height: AppSize.compact,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildOverlayButton(
                context,
                icon: Icons.compare,
                onPressed: () => _handleCompare(context),
                tooltip: l10n.comparator,
              ),
              _buildOverlayButton(
                context,
                icon: Icons.brush,
                onPressed: () => _handleMask(context),
                tooltip: l10n.maskEditor,
              ),
              _buildOverlayButton(
                context,
                icon: Icons.crop,
                onPressed: () => _handleCrop(context),
                tooltip: l10n.cropAndResize,
              ),
              ListenableBuilder(
                listenable: session,
                builder: (context, _) {
                  if (session.promptVersions <= 0 || session.isRunning) {
                    return const SizedBox.shrink();
                  }
                  return _buildOverlayButton(
                    context,
                    icon: Icons.reply,
                    onPressed: () => _handleFeedback(context),
                    tooltip: l10n.optResultFeedbackAction,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );

    if (persistent) {
      strip = AppEffects(reduceVisualEffects: true, child: strip);
    }

    // The strip sits over a grid cell whose width is the column count's to
    // decide, and on a phone three columns leave less than the four buttons
    // measure. Scaling it down keeps every action reachable where a Row would
    // put the last one past the edge of the picture.
    return FittedBox(fit: BoxFit.scaleDown, child: strip);
  }

  /// Collects the critique, stages it on the session (which latches an
  /// assistant-turn request the workbench screen consumes), and jumps to the
  /// assistant tab so the user lands where the conversation continues.
  Future<void> _handleFeedback(BuildContext context) async {
    final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
    final appState = Provider.of<AppState>(context, listen: false);
    // Provenance first, latest version as the fallback: an image the task
    // record ties to v2 gives feedback on v2 even after v3 was staged —
    // that binding is the whole reason the tag exists.
    final version =
        workbenchUIState.resultVersionByPath[widget.imageFile.path] ??
            workbenchUIState.optimizerSession.promptVersions;
    if (version < 1) return;
    final feedback = await showResultFeedbackDialog(
      context,
      image: widget.imageFile,
      promptVersion: version,
    );
    if (feedback == null || feedback.isEmpty) return;
    if (!workbenchUIState.sendResultFeedback(
      widget.imageFile,
      feedback: feedback,
      promptVersion: version,
    )) {
      return;
    }
    appState.setWorkbenchTab(4); // Prompt assistant
  }

  /// A 16px glyph in a 26×26 hit box (`ms s` in a 26px span).
  ///
  /// [context] must be below the strip's [AppGlass]: [IconButton] paints the
  /// scheme's grey unless told otherwise, and the glass's ink is what reads on
  /// it — `gink` with effects on, the overlay ink in the opaque fallback.
  Widget _buildOverlayButton(
    BuildContext context, {
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
  }) {
    final ink = GlassInk.maybeOf(context)?.ink ?? AppOverlay.onImagePlate;
    return SizedBox.square(
      dimension: 26,
      child: IconButton(
        icon: Icon(icon, size: AppSize.iconMd),
        color: ink,
        onPressed: onPressed,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          // Concentric with the r6 strip across its 2px inset.
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xs),
          ),
        ),
      ),
    );
  }

  void _handleCompare(BuildContext context) {
    final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
    workbenchUIState.sendToComparator(widget.imageFile.path);
  }

  void _handleMask(BuildContext context) {
    final appState = Provider.of<AppState>(context, listen: false);
    final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
    workbenchUIState.setMaskEditorSourceImage(widget.imageFile);
    appState.setWorkbenchTab(2); // Mask Editor
  }

  void _handleCrop(BuildContext context) {
    final appState = Provider.of<AppState>(context, listen: false);
    final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
    workbenchUIState.setCropResizeSourceImage(widget.imageFile);
    appState.setWorkbenchTab(3); // Crop Tab
  }
}
