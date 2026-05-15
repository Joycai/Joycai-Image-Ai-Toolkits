import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../../l10n/app_localizations.dart';
import '../../../state/workbench_ui_state.dart';

class VideoWorkbenchView extends StatefulWidget {
  const VideoWorkbenchView({super.key});

  @override
  State<VideoWorkbenchView> createState() => _VideoWorkbenchViewState();
}

class _VideoWorkbenchViewState extends State<VideoWorkbenchView> {
  VideoPlayerController? _controller;
  String? _lastPath;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _initPlayer(String path) {
    if (_lastPath == path) return;
    _lastPath = path;
    _controller?.dispose();
    
    final file = File(path);
    if (!file.existsSync()) return;

    _controller = VideoPlayerController.file(file)
      ..initialize().then((_) {
        if (mounted) setState(() {});
      });
  }

  @override
  Widget build(BuildContext context) {
    final uiState = context.watch<WorkbenchUIState>();
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    if (uiState.lastGeneratedVideoPath != null) {
      _initPlayer(uiState.lastGeneratedVideoPath!);
    }

    return Container(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Center(
        child: uiState.lastGeneratedVideoPath == null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.movie_creation_outlined, size: 64, color: colorScheme.outline),
                  const SizedBox(height: 16),
                  Text(
                    l10n.noResultsYet,
                    style: TextStyle(color: colorScheme.outline, fontSize: 16),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_controller != null && _controller!.value.isInitialized)
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
                    const CircularProgressIndicator(),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _openInSystemPlayer(uiState.lastGeneratedVideoPath!),
                        icon: const Icon(Icons.open_in_new),
                        label: Text(l10n.openInSystemPlayer),
                      ),
                      TextButton.icon(
                        onPressed: () => uiState.setLastGeneratedVideoPath(null),
                        icon: const Icon(Icons.clear),
                        label: Text(l10n.clearTempWorkspace),
                      ),
                    ],
                  ),
                ],
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
