import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../../l10n/app_localizations.dart';
import '../../../state/workbench_ui_state.dart';

class VideoWorkbenchOverlay extends StatefulWidget {
  const VideoWorkbenchOverlay({super.key});

  @override
  State<VideoWorkbenchOverlay> createState() => _VideoWorkbenchOverlayState();
}

class _VideoWorkbenchOverlayState extends State<VideoWorkbenchOverlay> {
  VideoPlayerController? _controller;
  String? _lastPath;
  bool _hasError = false;
  String? _errorMessage;

  @override
  void dispose() {
    _disposePlayer();
    super.dispose();
  }

  void _disposePlayer() {
    _controller?.dispose();
    _controller = null;
    _lastPath = null;
  }

  void _initPlayer(String path) {
    if (_lastPath == path) return;
    _lastPath = path;
    _disposePlayer();
    _hasError = false;
    _errorMessage = null;

    final file = File(path);
    if (!file.existsSync()) {
      setState(() {
        _hasError = true;
        _errorMessage = 'Video file does not exist.';
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
      // One rebuild to show the player once initialized. Per-frame updates
      // (play state, scrub position) are handled by self-listening leaf
      // widgets below, so the whole overlay no longer rebuilds every frame,
      // which is what spammed the accessibility-bridge AXTree errors.
      setState(() {
        _hasError = false;
        _errorMessage = null;
      });
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

  @override
  Widget build(BuildContext context) {
    final uiState = context.watch<WorkbenchUIState>();
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    if (uiState.lastGeneratedVideoPath == null) {
      _disposePlayer();
      return const SizedBox.shrink();
    }

    _initPlayer(uiState.lastGeneratedVideoPath!);

    return Positioned(
      bottom: 20,
      right: 20,
      left: 20,
      child: Align(
        alignment: Alignment.bottomRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(16),
            color: colorScheme.surfaceContainerHighest,
            child: Container(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.movie_outlined, size: 20, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.processResults,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => uiState.setLastGeneratedVideoPath(null),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_hasError)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline, size: 36, color: colorScheme.error),
                          const SizedBox(height: 8),
                          Text(
                            _errorMessage ?? 'Failed to initialize video player',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: colorScheme.error),
                          ),
                        ],
                      ),
                    )
                  else if (_controller != null && _controller!.value.isInitialized)
                    Flexible(
                      child: AspectRatio(
                        aspectRatio: _controller!.value.aspectRatio,
                        child: GestureDetector(
                          onTap: () {
                            if (_controller!.value.isPlaying) {
                              _controller!.pause();
                            } else {
                              _controller!.play();
                            }
                          },
                          child: Stack(
                            alignment: Alignment.bottomCenter,
                            children: [
                              VideoPlayer(_controller!),
                              _VideoControls(controller: _controller!),
                              VideoProgressIndicator(_controller!, allowScrubbing: true),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _openInSystemPlayer(uiState.lastGeneratedVideoPath!),
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: Text(l10n.openInSystemPlayer, style: const TextStyle(fontSize: 12)),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openInSystemPlayer(String path) async {
    final uri = Uri.file(path);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}

class _VideoControls extends StatelessWidget {
  final VideoPlayerController controller;

  const _VideoControls({required this.controller});

  @override
  Widget build(BuildContext context) {
    // Listen to the controller here (leaf) instead of the parent rebuilding
    // every frame. AnimatedSwitcher only swaps on play/pause transitions.
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: value.isPlaying
              ? const SizedBox.shrink(key: ValueKey('playing'))
              : Container(
                  key: const ValueKey('paused'),
                  color: Colors.black26,
                  child: Center(
                    child: IconButton(
                      icon: const Icon(Icons.play_arrow, size: 64, color: Colors.white),
                      onPressed: () => controller.play(),
                    ),
                  ),
                ),
        );
      },
    );
  }
}
