import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/constants.dart';
import 'preview_handler.dart';
import 'video_thumbnail.dart';

/// Preview handler for video files. Renders an auto-playing, looping player
/// with an auto-hiding control overlay as full-screen content, and a generated
/// poster frame as the thumbnail.
class VideoPreviewHandler implements PreviewHandler {
  @override
  bool canHandle(String path) => AppConstants.isVideoFile(path);

  @override
  Widget buildContent(
    BuildContext context, {
    required String path,
    required bool isActive,
  }) {
    // Key by path so the pager rebuilds (and disposes the old player) when the
    // underlying file at this page changes.
    return _VideoPreviewContent(key: ValueKey(path), path: path, isActive: isActive);
  }

  @override
  Widget buildThumbnail(BuildContext context, {required String path}) {
    return VideoThumbnail(videoPath: path);
  }
}

class _VideoPreviewContent extends StatefulWidget {
  final String path;
  final bool isActive;
  const _VideoPreviewContent({super.key, required this.path, required this.isActive});

  @override
  State<_VideoPreviewContent> createState() => _VideoPreviewContentState();
}

class _VideoPreviewContentState extends State<_VideoPreviewContent> {
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

    final controller = VideoPlayerController.file(file);
    _controller = controller;

    controller.initialize().then((_) {
      if (!mounted || _controller != controller) {
        controller.dispose();
        return;
      }
      setState(() {});
      if (widget.isActive) {
        controller.play();
      }
      controller.setLooping(true);
      controller.addListener(_onControllerPlayStatusChanged);
      _startHideTimer();
    }).catchError((error) {
      if (!mounted || _controller != controller) {
        controller.dispose();
        return;
      }
      setState(() {
        _hasError = true;
        _errorMessage = error.toString();
      });
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
  void didUpdateWidget(_VideoPreviewContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.path != oldWidget.path || widget.isActive != oldWidget.isActive) {
      _disposePlayer();
      _hasError = false;
      _errorMessage = null;
      if (widget.isActive) {
        _initPlayer();
      } else {
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
          VideoThumbnail(
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
            // Isolate the video texture's repaints from the overlay so its
            // frames don't dirty the surrounding subtree every frame.
            RepaintBoundary(
              child: AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: VideoPlayer(_controller!),
              ),
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
            // Always present (opacity-driven) so toggling play/pause never
            // adds or removes a node from the tree — structural churn is a
            // trigger for the accessibility-bridge tree-update errors.
            ExcludeSemantics(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: (!_controller!.value.isPlaying && _showOverlay) ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
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

  // While the user is dragging the scrubber we ignore controller position
  // updates so the thumb doesn't fight the drag.
  bool _dragging = false;
  double _dragValueMs = 0.0;

  @override
  void initState() {
    super.initState();
    _isMuted = widget.controller.value.volume == 0;
    _volume = widget.controller.value.volume;
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _toggleMute() {
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
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () {}, // Consume tap to prevent triggering play/pause of main video area
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: Colors.black.withAlpha(160),
        // Only the position-dependent leaves rebuild per frame, via the
        // ValueListenableBuilder below. The Container / SliderTheme / static
        // controls stay stable instead of the whole bar rebuilding on every
        // controller tick (which is what hammered the desktop accessibility
        // bridge and spammed "Failed to update ui::AXTree").
        child: ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: widget.controller,
          builder: (context, value, _) {
            if (!value.isInitialized) return const SizedBox.shrink();

            final durationMs = value.duration.inMilliseconds.toDouble();
            final maxMs = durationMs > 0 ? durationMs : 1.0;
            final positionMs = value.position.inMilliseconds.toDouble();
            final sliderMs =
                (_dragging ? _dragValueMs : positionMs).clamp(0.0, maxMs);

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SliderTheme(
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
                    max: maxMs,
                    value: sliderMs,
                    onChangeStart: (v) {
                      setState(() {
                        _dragging = true;
                        _dragValueMs = v;
                      });
                    },
                    onChanged: (v) {
                      setState(() => _dragValueMs = v);
                    },
                    onChangeEnd: (v) {
                      widget.controller.seekTo(Duration(milliseconds: v.toInt()));
                      setState(() => _dragging = false);
                    },
                  ),
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
                      '${_formatDuration(value.position)} / ${_formatDuration(value.duration)}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(
                        _isMuted || _volume == 0 ? Icons.volume_off : Icons.volume_up,
                        color: Colors.white,
                      ),
                      onPressed: _toggleMute,
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
