import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../../core/constants.dart';
import '../../../core/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/app_image.dart';
import '../../../state/workbench_ui_state.dart';

class ImagePreviewDialog extends StatefulWidget {
  const ImagePreviewDialog({super.key});

  @override
  State<ImagePreviewDialog> createState() => _ImagePreviewDialogState();
}

class _ImagePreviewDialogState extends State<ImagePreviewDialog> {
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

  Future<void> _saveImage(String path, String fileName, AppLocalizations l10n) async {
    try {
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        final extension = path.split('.').last;
        String? outputFile = await FilePicker.saveFile(
          dialogTitle: l10n.save,
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: [extension],
        );

        if (outputFile != null) {
          final file = File(path);
          await file.copy(outputFile);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.settingsExported), backgroundColor: Colors.green),
            );
          }
        }
      } else {
        await Gal.putImage(path);
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

  Future<void> _shareImage(AppImage file, AppLocalizations l10n) async {
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

  Widget _buildThumbnailItem(String path) {
    final isVideo = AppConstants.isVideoFile(path);
    if (isVideo) {
      return _VideoThumbnailWidget(videoPath: path);
    }
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      cacheWidth: 120,
    );
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
                  final isVideo = AppConstants.isVideoFile(images[index].path);
                  return Center(
                    child: isVideo 
                        ? _VideoPreviewItem(
                            path: images[index].path,
                            isActive: index == activeIndex,
                          )
                        : Hero(
                            tag: images[index].path,
                            child: InteractiveViewer(
                              minScale: 0.5,
                              maxScale: 5.0,
                              child: Image.file(
                                File(images[index].path),
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, color: Colors.white54, size: 64),
                              ),
                            ),
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
                          onPressed: () => _saveImage(activeFile.path, activeFile.name, l10n),
                        ),
                        IconButton(
                          icon: const Icon(Icons.share_outlined, color: Colors.white),
                          tooltip: l10n.share,
                          onPressed: () => _shareImage(activeFile, l10n),
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
                            child: _buildThumbnailItem(images[index].path),
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

class _VideoPreviewItem extends StatefulWidget {
  final String path;
  final bool isActive;
  const _VideoPreviewItem({required this.path, required this.isActive});

  @override
  State<_VideoPreviewItem> createState() => _VideoPreviewItemState();
}

class _VideoPreviewItemState extends State<_VideoPreviewItem> {
  VideoPlayerController? _controller;
  bool _hasError = false;
  String? _errorMessage;
  bool _showOverlay = true;
  Timer? _hideTimer;
  bool _wasPlaying = false;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      _initPlayer();
    }
  }

  void _onControllerPlayStatusChanged() {
    if (!mounted || _controller == null) return;
    final isPlaying = _controller!.value.isPlaying;
    if (isPlaying != _wasPlaying) {
      _wasPlaying = isPlaying;
      if (!isPlaying) {
        _hideTimer?.cancel();
        setState(() {
          _showOverlay = true;
        });
      } else {
        _onUserInteraction();
      }
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _controller != null && _controller!.value.isPlaying) {
        setState(() {
          _showOverlay = false;
        });
      }
    });
  }

  void _onUserInteraction() {
    if (!mounted) return;
    if (!_showOverlay) {
      setState(() {
        _showOverlay = true;
      });
    }
    _startHideTimer();
  }

  void _initPlayer() {
    if (_controller != null) return;
    final file = File(widget.path);
    if (!file.existsSync()) {
      setState(() {
        _hasError = true;
        _errorMessage = 'File not found';
      });
      return;
    }

    _controller = VideoPlayerController.file(file)
      ..initialize().then((_) {
        if (mounted) {
          setState(() {});
          if (widget.isActive) {
            _controller?.play();
          }
          _controller?.setLooping(true);
          _controller?.addListener(_onControllerPlayStatusChanged);
          _startHideTimer();
        }
      }).catchError((error) {
        if (mounted) {
          setState(() {
            _hasError = true;
            _errorMessage = error.toString();
          });
        }
      });
  }

  void _disposePlayer() {
    _hideTimer?.cancel();
    _controller?.removeListener(_onControllerPlayStatusChanged);
    _controller?.dispose();
    _controller = null;
    _wasPlaying = false;
  }

  @override
  void didUpdateWidget(_VideoPreviewItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        _initPlayer();
      } else {
        _disposePlayer();
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    _disposePlayer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white54, size: 64),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'Failed to play video',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    if (_controller == null || !_controller!.value.isInitialized) {
      return Stack(
        alignment: Alignment.center,
        children: [
          _VideoThumbnailWidget(
            videoPath: widget.path,
            fit: BoxFit.contain,
            showPlayIcon: false,
          ),
          const Center(child: CircularProgressIndicator()),
        ],
      );
    }

    return MouseRegion(
      onHover: (_) => _onUserInteraction(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _onUserInteraction();
          if (_controller!.value.isPlaying) {
            _controller?.pause();
          } else {
            _controller?.play();
          }
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            AspectRatio(
              aspectRatio: _controller!.value.aspectRatio,
              child: VideoPlayer(_controller!),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: _showOverlay ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: ExcludeSemantics(
                  child: IgnorePointer(
                    ignoring: !_showOverlay,
                    child: _VideoControlBar(controller: _controller!),
                  ),
                ),
              ),
            ),
            if (!_controller!.value.isPlaying && _showOverlay)
              ExcludeSemantics(
                child: IgnorePointer(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      color: Colors.black45,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.play_arrow, size: 48, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _VideoControlBar extends StatefulWidget {
  final VideoPlayerController controller;
  const _VideoControlBar({required this.controller});

  @override
  State<_VideoControlBar> createState() => _VideoControlBarState();
}

class _VideoControlBarState extends State<_VideoControlBar> {
  bool _isMuted = false;
  double _volume = 1.0;

  @override
  void initState() {
    super.initState();
    _isMuted = widget.controller.value.volume == 0;
    _volume = widget.controller.value.volume;
    widget.controller.addListener(_onControllerUpdate);
  }

  @override
  void didUpdateWidget(_VideoControlBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_onControllerUpdate);
      widget.controller.addListener(_onControllerUpdate);
      _isMuted = widget.controller.value.volume == 0;
      _volume = widget.controller.value.volume;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerUpdate);
    super.dispose();
  }

  void _onControllerUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.value;
    if (!value.isInitialized) return const SizedBox.shrink();

    final position = value.position;
    final duration = value.duration;
    
    final currentText = _formatDuration(position);
    final totalText = _formatDuration(duration);

    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () {}, // Consume tap to prevent triggering play/pause of main video area
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: Colors.black.withAlpha(160),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      activeTrackColor: colorScheme.primary,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: colorScheme.primary,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                    ),
                    child: Slider(
                      min: 0.0,
                      max: duration.inMilliseconds.toDouble(),
                      value: position.inMilliseconds.toDouble().clamp(0.0, duration.inMilliseconds.toDouble()),
                      onChanged: (newValue) {
                        widget.controller.seekTo(Duration(milliseconds: newValue.toInt()));
                      },
                    ),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                IconButton(
                  icon: Icon(
                    value.isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    if (value.isPlaying) {
                      widget.controller.pause();
                    } else {
                      widget.controller.play();
                    }
                  },
                ),
                const SizedBox(width: 8),
                Text(
                  '$currentText / $totalText',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    _isMuted || _volume == 0 ? Icons.volume_off : Icons.volume_up,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    setState(() {
                      if (_isMuted) {
                        widget.controller.setVolume(_volume > 0 ? _volume : 1.0);
                        _isMuted = false;
                      } else {
                        _volume = widget.controller.value.volume;
                        widget.controller.setVolume(0.0);
                        _isMuted = true;
                      }
                    });
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

void showImagePreview(BuildContext context, {required List<AppImage> galleryImages, required int initialIndex}) {
  final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
  workbenchUIState.setPreviewList(galleryImages, initialIndex);
  
  showDialog(
    context: context,
    builder: (context) => const ImagePreviewDialog(),
  );
}

class _VideoThumbnailWidget extends StatefulWidget {
  final String videoPath;
  final BoxFit fit;
  final bool showPlayIcon;
  
  const _VideoThumbnailWidget({
    required this.videoPath,
    this.fit = BoxFit.cover,
    this.showPlayIcon = true,
  });

  @override
  State<_VideoThumbnailWidget> createState() => _VideoThumbnailWidgetState();
}

class _VideoThumbnailWidgetState extends State<_VideoThumbnailWidget> {
  String? _thumbnailPath;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  Future<void> _loadThumbnail() async {
    try {
      final file = File(widget.videoPath);
      if (!await file.exists()) return;

      final tempDir = await getTemporaryDirectory();
      final stat = await file.stat();
      final key = '${widget.videoPath}_${stat.modified.millisecondsSinceEpoch}_${stat.size}';
      final hash = md5.convert(utf8.encode(key)).toString();
      final cachePath = '${tempDir.path}/joycai/video_thumbnails/$hash.jpg';

      if (File(cachePath).existsSync() && mounted) {
        setState(() {
          _thumbnailPath = cachePath;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_thumbnailPath != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.file(File(_thumbnailPath!), fit: widget.fit),
          Container(color: Colors.black26),
          if (widget.showPlayIcon)
            const Center(
              child: Icon(Icons.play_circle_outline, color: Colors.white, size: 24),
            ),
        ],
      );
    }
    return Container(
      color: Colors.white10,
      child: Center(
        child: widget.showPlayIcon
            ? const Icon(Icons.play_circle_outline, color: Colors.white, size: 24)
            : const SizedBox.shrink(),
      ),
    );
  }
}
