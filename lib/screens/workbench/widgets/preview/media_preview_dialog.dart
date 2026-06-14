import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/constants.dart';
import '../../../../core/responsive.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/app_image.dart';
import '../../../../state/workbench_ui_state.dart';
import 'preview_handler.dart';

/// Full-screen, swipeable preview for a list of media files of any supported
/// type. The dialog itself is file-type agnostic: it owns the chrome (toolbar,
/// navigation, thumbnail strip, save/share) and delegates rendering of each
/// page and thumbnail to the [PreviewHandler] resolved for that file via
/// [PreviewRegistry]. New file types are added by implementing a handler — no
/// changes to this widget are required.
class MediaPreviewDialog extends StatefulWidget {
  const MediaPreviewDialog({super.key});

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
    if (workbenchUIState.activePreviewIndex < count - 1) {
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  void _prevImage() {
    final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
    if (workbenchUIState.activePreviewIndex > 0) {
      _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
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
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.settingsExported), backgroundColor: Colors.green),
            );
          }
        }
      } else {
        if (AppConstants.isVideoFile(path)) {
          await Gal.putVideo(path);
        } else {
          await Gal.putImage(path);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.savedToPhotos), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.saveFailed(e.toString())), backgroundColor: Colors.red),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.shareFailed(e.toString()))),
        );
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
                  return Center(
                    child: handler.buildContent(
                      context,
                      path: path,
                      isActive: index == activeIndex,
                    ),
                  );
                },
              ),
            ),

            // Custom Top Toolbar
            if (_showControls)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
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
                                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${activeIndex + 1} / ${images.length}',
                                style: const TextStyle(color: Colors.white70, fontSize: 11),
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

            // Side Navigation Buttons (Desktop/Tablet Only)
            if (_showControls && !Responsive.isMobile(context)) ...[
              if (activeIndex > 0)
                Positioned(
                  left: 16,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _buildNavButton(Icons.chevron_left, _prevImage),
                  ),
                ),
              if (activeIndex < images.length - 1)
                Positioned(
                  right: 16,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _buildNavButton(Icons.chevron_right, () => _nextImage(images.length)),
                  ),
                ),
            ],

            // Bottom Thumbnail Strip
            if (_showControls)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
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
                          onTap: () {
                            _pageController.animateToPage(index, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                          },
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
          ],
        ),
      ),
    );
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
void showMediaPreview(BuildContext context, {required List<AppImage> galleryImages, required int initialIndex}) {
  final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
  workbenchUIState.setPreviewList(galleryImages, initialIndex);

  showDialog(
    context: context,
    builder: (context) => const MediaPreviewDialog(),
  );
}
