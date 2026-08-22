import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/constants.dart';
import '../../../../core/design_tokens.dart';
import '../../../../core/responsive.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/app_image.dart';
import '../../../../state/workbench_ui_state.dart';
import '../../../../widgets/app_snackbar.dart';
import 'preview_handler.dart';

/// Hero scope for thumbnails in the workbench gallery.
const String kWorkbenchPreviewHeroScope = 'workbench-gallery';

/// Hero scope for thumbnails in the file browser's grid.
const String kBrowserPreviewHeroScope = 'file-browser';

/// The tag shared by a grid thumbnail and the preview page it opens into.
///
/// [scope] namespaces the grid that owns the thumbnail: the workbench gallery
/// and the file browser can both be showing the same file, and during the
/// top-level navigation crossfade both grids are briefly in the tree at once —
/// un-namespaced, that is a duplicate-tag assertion waiting on unlucky timing.
String previewHeroTag(String scope, String path) => '$scope::$path';

/// Full-screen, swipeable preview for a list of media files of any supported
/// type. The dialog itself is file-type agnostic: it owns the chrome (toolbar,
/// navigation, thumbnail strip, save/share) and delegates rendering of each
/// page and thumbnail to the [PreviewHandler] resolved for that file via
/// [PreviewRegistry]. New file types are added by implementing a handler — no
/// changes to this widget are required.
class MediaPreviewDialog extends StatefulWidget {
  /// Namespace of the grid whose thumbnail this preview flew out of, or null
  /// when the opener has no thumbnail to fly back to (list views).
  final String? heroScope;

  const MediaPreviewDialog({super.key, this.heroScope});

  @override
  State<MediaPreviewDialog> createState() => _MediaPreviewDialogState();
}

class _MediaPreviewDialogState extends State<MediaPreviewDialog> {
  late PageController _pageController;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
    _pageController = PageController(initialPage: workbenchUIState.activePreviewIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextImage(int count) {
    final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
    final i = workbenchUIState.activePreviewIndex;
    if (i < count - 1) {
      _pageController.jumpToPage(i + 1);
    }
  }

  void _prevImage() {
    final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
    final i = workbenchUIState.activePreviewIndex;
    if (i > 0) {
      _pageController.jumpToPage(i - 1);
    }
  }

  void _jumpToPage(int index) {
    final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
    final current = workbenchUIState.activePreviewIndex;
    if (current == index) return;
    if ((current - index).abs() == 1) {
      // `move`, not `enter`: both endpoints of a page slide are visible.
      _pageController.animateToPage(index,
          duration: AppMotion.durationOf(context, AppMotion.reveal), curve: AppMotion.move);
    } else {
      _pageController.jumpToPage(index);
    }
  }

  Future<void> _saveFile(String path, String fileName, AppLocalizations l10n) async {
    try {
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        final extension = path.split('.').last;
        final bytes = await File(path).readAsBytes();
        final outputFile = await FilePicker.saveFile(
          dialogTitle: l10n.save,
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: [extension],
          bytes: bytes,
        );

        if (outputFile != null) {
          if (mounted) {
            AppSnackBar.success(context, l10n.settingsExported);
          }
        }
      } else {
        if (AppConstants.isVideoFile(path)) {
          await Gal.putVideo(path);
        } else {
          await Gal.putImage(path);
        }
        if (mounted) {
          AppSnackBar.success(context, l10n.savedToPhotos);
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(context, l10n.saveFailed(e.toString()));
      }
    }
  }

  Future<void> _shareFile(AppImage file, AppLocalizations l10n) async {
    try {
      final xFile = XFile(file.path, name: file.name, mimeType: AppConstants.getMimeType(file.path));
      // ignore: deprecated_member_use
      await Share.shareXFiles([xFile], subject: file.name);
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(context, l10n.shareFailed(e.toString()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final workbenchUIState = Provider.of<WorkbenchUIState>(context);
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final images = workbenchUIState.previewImages;
    final activeIndex = workbenchUIState.activePreviewIndex;

    if (images.isEmpty) return const SizedBox.shrink();

    final activeFile = images[activeIndex];

    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: CallbackShortcuts(
        bindings: {
          // Bound here because this is a PageRoute now: showDialog's barrier
          // used to translate Escape into a pop for free, a PageRoute doesn't.
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.maybePop(context),
          const SingleActivator(LogicalKeyboardKey.arrowLeft): _prevImage,
          const SingleActivator(LogicalKeyboardKey.arrowRight): () => _nextImage(images.length),
          const SingleActivator(LogicalKeyboardKey.home): () => _jumpToPage(0),
          const SingleActivator(LogicalKeyboardKey.end): () => _jumpToPage(images.length - 1),
          // Space reaches here only when the active page did not consume it —
          // the video handler binds Space to play/pause on its own focus node.
          const SingleActivator(LogicalKeyboardKey.space): () =>
              setState(() => _showControls = !_showControls),
        },
        child: Focus(
          autofocus: true,
          child: ExcludeSemantics(
            child: Stack(
              children: [
                // PageView for Main Content
                GestureDetector(
                  onTap: () => setState(() => _showControls = !_showControls),
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: images.length,
                    onPageChanged: (index) => workbenchUIState.setActivePreview(index),
                    itemBuilder: (context, index) {
                      final path = images[index].path;
                      final handler = PreviewRegistry.resolve(path);
                      final Widget content = Center(
                        child: handler.buildContent(
                          context,
                          path: path,
                          isActive: index == activeIndex,
                        ),
                      );
                      // Only the active page carries the Hero: on pop the
                      // flight has to leave from whichever page the user
                      // ended on, not the one they arrived at — and tagging
                      // every built page would make each one fly at once.
                      if (widget.heroScope == null || index != activeIndex) {
                        return content;
                      }
                      return Hero(
                        tag: previewHeroTag(widget.heroScope!, path),
                        flightShuttleBuilder: _gridThumbnailShuttle,
                        child: content,
                      );
                    },
                  ),
                ),

                // Custom Top Toolbar. Resident and opacity-driven, like the
                // video handler's overlay: toggling chrome used to add and
                // remove these subtrees between two frames, the one overlay
                // family in this screen that neither faded in nor out.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _controlsLayer(
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black.withAlpha(180), Colors.transparent],
                        ),
                      ),
                      child: SafeArea(
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back, color: Colors.white),
                              onPressed: () => Navigator.pop(context),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    activeFile.name,
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '${activeIndex + 1} / ${images.length}',
                                    style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.white70),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.save_alt, color: Colors.white),
                              tooltip: l10n.save,
                              onPressed: () => _saveFile(activeFile.path, activeFile.name, l10n),
                            ),
                            IconButton(
                              icon: const Icon(Icons.share_outlined, color: Colors.white),
                              tooltip: l10n.share,
                              onPressed: () => _shareFile(activeFile, l10n),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Side Navigation Buttons (Desktop/Tablet Only). The index
                // conditions stay structural — a chevron with no page beyond
                // it is absent, not dimmed — while the chrome toggle fades.
                if (!Responsive.isMobile(context)) ...[
                  if (activeIndex > 0)
                    Positioned(
                      left: 16,
                      top: 0,
                      bottom: 0,
                      child: _controlsLayer(
                        Center(
                          child: _buildNavButton(Icons.chevron_left, _prevImage),
                        ),
                      ),
                    ),
                  if (activeIndex < images.length - 1)
                    Positioned(
                      right: 16,
                      top: 0,
                      bottom: 0,
                      child: _controlsLayer(
                        Center(
                          child: _buildNavButton(Icons.chevron_right, () => _nextImage(images.length)),
                        ),
                      ),
                    ),
                ],

                // Bottom Thumbnail Strip
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _controlsLayer(
                    Container(
                      height: 110,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Colors.black.withAlpha(180), Colors.transparent],
                        ),
                      ),
                      child: SafeArea(
                        top: false,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          scrollDirection: Axis.horizontal,
                          itemCount: images.length,
                          separatorBuilder: (context, index) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final isSelected = index == activeIndex;
                            final path = images[index].path;
                            return GestureDetector(
                              onTap: () => _jumpToPage(index),
                              child: Container(
                                width: 60,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSelected ? colorScheme.primary : Colors.white24,
                                    width: isSelected ? 3 : 1,
                                  ),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: PreviewRegistry.resolve(path).buildThumbnail(context, path: path),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The chrome toggle's shared presentation: resident in the tree, faded by
  /// [_showControls], and inert the moment it starts leaving — an overlay
  /// mid-fade-out should not swallow the tap that was aimed at the picture.
  Widget _controlsLayer(Widget child) {
    return IgnorePointer(
      ignoring: !_showControls,
      child: AnimatedOpacity(
        opacity: _showControls ? 1.0 : 0.0,
        duration: AppMotion.durationOf(context, AppMotion.reveal),
        curve: AppMotion.enter,
        child: child,
      ),
    );
  }

  /// Flies the grid's own thumbnail in both directions.
  ///
  /// The default shuttle is the destination hero's child, which on push is
  /// this page's full content — a video player still initialising (black), or
  /// a full-resolution image still decoding. The thumbnail the user just
  /// clicked is the one thing guaranteed to be painted at flight start, so it
  /// is the material of the flight; the real content fades in with the route
  /// underneath it, the way a photos app promotes a tile.
  static Widget _gridThumbnailShuttle(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    final gridHero = flightDirection == HeroFlightDirection.push
        ? fromHeroContext.widget
        : toHeroContext.widget;
    return (gridHero as Hero).child;
  }

  Widget _buildNavButton(IconData icon, VoidCallback onPressed) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(100),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: 32),
        onPressed: onPressed,
      ),
    );
  }
}

/// Opens the full-screen [MediaPreviewDialog] for [galleryImages], starting at
/// [initialIndex].
///
/// [heroScope] names the grid whose thumbnail the preview should fly out of
/// (and back into); pass one of the `k…PreviewHeroScope` constants from the
/// same screen that tagged its thumbnails, or nothing from a view with no
/// thumbnail to fly to. A tagged tile that has been scrolled out of view or
/// filtered away simply has no match, and the route's own fade covers it.
void showMediaPreview(BuildContext context,
    {required List<AppImage> galleryImages, required int initialIndex, String? heroScope}) {
  final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
  workbenchUIState.setPreviewList(galleryImages, initialIndex);

  // A PageRoute, not showDialog: hero flights only trigger between PageRoutes,
  // and the lightbox is the one dialog in the app with a real spatial origin —
  // it is always opened from a specific thumbnail. Transparent, so the grid
  // stays visible under the black as it fades in; that is what the flight
  // flies over.
  Navigator.of(context).push(PageRouteBuilder(
    opaque: false,
    fullscreenDialog: true,
    transitionDuration: AppMotion.durationOf(context, AppMotion.reveal),
    reverseTransitionDuration: AppMotion.durationOf(context, AppMotion.reveal),
    pageBuilder: (_, _, _) => MediaPreviewDialog(heroScope: heroScope),
    transitionsBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  ));
}
