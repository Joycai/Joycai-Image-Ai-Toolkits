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
    _controller?.dispose();
    super.dispose();
  }

  void _initPlayer(String path) {
    if (_lastPath == path) return;
    _lastPath = path;
    _controller?.dispose();
    _controller = null;
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

    _controller = VideoPlayerController.file(file)
      ..initialize().then((_) {
        if (mounted) {
          setState(() {
            _hasError = false;
            _errorMessage = null;
          });
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

  @override
  Widget build(BuildContext context) {
    final uiState = context.watch<WorkbenchUIState>();
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    if (uiState.lastGeneratedVideoPath == null) {
      if (_controller != null) {
        _controller!.dispose();
        _controller = null;
        _lastPath = null;
      }
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
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        VideoPlayer(_controller!),
                        _VideoControls(controller: _controller!),
                        VideoProgressIndicator(_controller!, allowScrubbing: true),
                      ],
                    ),
                  ),
                )
              else
                const Center(child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                )),
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
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: controller.value.isPlaying
          ? const SizedBox.shrink()
          : Container(
              color: Colors.black26,
              child: Center(
                child: IconButton(
                  icon: const Icon(Icons.play_arrow, size: 64, color: Colors.white),
                  onPressed: () => controller.play(),
                ),
              ),
            ),
    );
  }
}
