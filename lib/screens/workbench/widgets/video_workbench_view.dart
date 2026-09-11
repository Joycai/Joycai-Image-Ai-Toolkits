import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../../core/app_semantic_colors.dart';
import '../../../core/app_theme.dart';
import '../../../core/constants.dart';
import '../../../core/design_tokens.dart';
import '../../../core/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../../state/workbench_ui_state.dart';

/// The gap between the player panel and the gallery area's edges
/// (`A2` 「与画廊间距 10」).
const double _kInset = AppSpace.s10;

/// Below this gallery-area width the full panel's right column cannot hold
/// its header row, and the player takes the tablet strip instead.
const double _kPanelMinArea = 760;

/// Below this the tablet strip's labelled button no longer fits beside the
/// title, and the player takes the phone strip.
const double _kStripMinArea = 480;

/// From this width a strip can afford the labelled "Open in System Player"
/// button; under it the button is the bare glyph.
const double _kStripLabelledArea = 600;

enum _PlayerForm { panel, strip, phone }

/// The three sizes `A2` draws the player at.
class _PlayerMetrics {
  const _PlayerMetrics(this.form, this.video, this.padding, this.playIcon);

  final _PlayerForm form;

  /// The video's own box.
  final Size video;
  final double padding;
  final double playIcon;

  /// The panel's height: the video, the inset around it and the 1px hairline
  /// top and bottom.
  double get panelHeight => video.height + padding * 2 + 2;

  /// `1a`: 300×170 inside a 10px inset.
  static const panel = _PlayerMetrics(_PlayerForm.panel, Size(300, 170), AppSpace.s10, 28);

  /// `1c`: the tablet's short strip.
  static const strip = _PlayerMetrics(_PlayerForm.strip, Size(150, 84), 8, 24);

  /// `1d`: the phone's strip.
  static const phone = _PlayerMetrics(_PlayerForm.phone, Size(120, 68), 8, 20);
}

/// Which form the player takes: the window's breakpoint, stepped down further
/// when the gallery area itself is too narrow for it (a desktop window with
/// both side panels open).
_PlayerMetrics _metricsFor(BuildContext context, double areaWidth) {
  if (Responsive.isMobile(context) || areaWidth < _kStripMinArea) return _PlayerMetrics.phone;
  if (Responsive.isTablet(context) || areaWidth < _kPanelMinArea) return _PlayerMetrics.strip;
  return _PlayerMetrics.panel;
}

class VideoWorkbenchOverlay extends StatefulWidget {
  const VideoWorkbenchOverlay({super.key});

  /// How far up from the bottom of the gallery area the player reaches while
  /// it is showing — the panel plus the 10px inset under it — for a gallery
  /// area [areaWidth] wide. 202 for the full panel, 112 for the tablet strip,
  /// 96 for the phone strip.
  ///
  /// Zero is the caller's to decide: the player shows only while
  /// `WorkbenchUIState.lastGeneratedVideoPath` is set.
  static double occupiedHeight(BuildContext context, double areaWidth) =>
      _metricsFor(context, areaWidth).panelHeight + _kInset;

  @override
  State<VideoWorkbenchOverlay> createState() => _VideoWorkbenchOverlayState();
}

class _VideoWorkbenchOverlayState extends State<VideoWorkbenchOverlay> {
  VideoPlayerController? _controller;
  String? _lastPath;
  bool _hasError = false;

  /// The error is that the file is not there, as opposed to [_errorMessage].
  bool _fileMissing = false;
  String? _errorMessage;

  /// The file's size, read once when the path arrives.
  int? _fileBytes;

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
    _disposePlayer();
    _lastPath = path;
    _hasError = false;
    _fileMissing = false;
    _errorMessage = null;
    _fileBytes = null;

    final file = File(path);
    if (!file.existsSync()) {
      // Reached from build, which reads these fields straight after.
      _hasError = true;
      _fileMissing = true;
      return;
    }
    try {
      _fileBytes = file.lengthSync();
    } on FileSystemException {
      _fileBytes = null;
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
    final path = context.select<WorkbenchUIState, String?>((s) => s.lastGeneratedVideoPath);
    final l10n = AppLocalizations.of(context)!;

    // No result: the panel does not take any room at all (`1e` 「无结果」).
    if (path == null) {
      _disposePlayer();
      return const SizedBox.shrink();
    }

    _initPlayer(path);

    // Anchored to the bottom of the gallery area, full width less the inset.
    // Its height is fixed by its form, so it needs no top anchor to stay out
    // from under the toolbar.
    return Positioned(
      left: _kInset,
      right: _kInset,
      bottom: _kInset,
      child: LayoutBuilder(
        builder: (context, box) {
          final double areaWidth = box.maxWidth + _kInset * 2;
          final metrics = _metricsFor(context, areaWidth);
          return TweenAnimationBuilder<double>(
            key: ValueKey(path),
            tween: Tween(begin: 0.0, end: 1.0),
            duration: AppMotion.sceneOf(context),
            curve: AppMotion.emphasized,
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(0, 24 * (1 - value)),
                child: Opacity(opacity: value, child: child),
              );
            },
            child: _buildPanel(context, path, metrics, areaWidth, l10n),
          );
        },
      ),
    );
  }

  /// `A2 · 1a`: an opaque panel — the player is content, not glass.
  Widget _buildPanel(
    BuildContext context,
    String path,
    _PlayerMetrics metrics,
    double areaWidth,
    AppLocalizations l10n,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: metrics.panelHeight,
      padding: EdgeInsets.all(metrics.padding),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.12),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: metrics.form == _PlayerForm.panel
            ? _buildWide(context, path, metrics, l10n)
            : _buildStrip(context, path, metrics, areaWidth, l10n),
      ),
    );
  }

  /// The desktop panel: the video on the left, title / facts / path on the
  /// right.
  Widget _buildWide(BuildContext context, String path, _PlayerMetrics metrics, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final monoStyle = textTheme.labelSmall?.mono.copyWith(
      fontWeight: FontWeight.w400,
      color: colorScheme.onSurfaceVariant,
    );
    final badge = _statusBadge(context, l10n);
    final facts = _facts();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildVideo(context, metrics),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: AppSize.compact,
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              l10n.processResults,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (badge != null) ...[
                            const SizedBox(width: 8),
                            badge,
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_hasError) ...[
                      _actionButton(
                        context,
                        icon: Icons.refresh,
                        label: l10n.videoRetry,
                        onPressed: _retry,
                        labelled: true,
                        height: AppSize.compact,
                      ),
                      const SizedBox(width: AppSpace.s4),
                    ],
                    _actionButton(
                      context,
                      icon: Icons.open_in_new,
                      label: l10n.openInSystemPlayer,
                      onPressed: () => _openInSystemPlayer(path),
                      labelled: true,
                      height: AppSize.compact,
                    ),
                    const SizedBox(width: 2),
                    _closeButton(context, l10n, size: AppSize.compact),
                  ],
                ),
              ),
              if (_hasError) ...[
                const SizedBox(height: AppSpace.s6),
                Tooltip(
                  message: _errorDetail,
                  child: Text(
                    _errorReason(l10n, path),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: monoStyle?.copyWith(color: colorScheme.error),
                  ),
                ),
              ] else if (facts != null) ...[
                const SizedBox(height: AppSpace.s6),
                Text(facts, maxLines: 1, overflow: TextOverflow.ellipsis, style: monoStyle),
              ],
              const SizedBox(height: AppSpace.s6),
              Text(path, maxLines: 1, overflow: TextOverflow.ellipsis, style: monoStyle),
            ],
          ),
        ),
      ],
    );
  }

  /// The tablet (`1c`) and phone (`1d`) strips: one row — video, title over
  /// one fact line, open, close.
  Widget _buildStrip(
    BuildContext context,
    String path,
    _PlayerMetrics metrics,
    double areaWidth,
    AppLocalizations l10n,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final bool phone = metrics.form == _PlayerForm.phone;
    final badge = phone ? null : _statusBadge(context, l10n);
    final facts = _facts();

    final String line;
    final Color lineColor;
    if (_hasError) {
      line = _errorReason(l10n, path);
      lineColor = colorScheme.error;
    } else {
      line = facts ?? path.replaceAll('\\', '/').split('/').last;
      lineColor = colorScheme.onSurfaceVariant;
    }

    return Row(
      children: [
        _buildVideo(context, metrics),
        const SizedBox(width: AppSpace.s10),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      l10n.processResults,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: 8),
                    badge,
                  ],
                ],
              ),
              SizedBox(height: phone ? 2 : AppSpace.s4),
              Text(
                line,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelSmall?.mono.copyWith(fontWeight: FontWeight.w400, color: lineColor),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // A strip has room for one action: retry while the file will not play,
        // open in the system player otherwise.
        _hasError
            ? _actionButton(
                context,
                icon: Icons.refresh,
                label: l10n.videoRetry,
                onPressed: _retry,
                labelled: !phone && areaWidth >= _kStripLabelledArea,
                height: AppSize.control,
              )
            : _actionButton(
                context,
                icon: Icons.open_in_new,
                label: l10n.openInSystemPlayer,
                onPressed: () => _openInSystemPlayer(path),
                labelled: !phone && areaWidth >= _kStripLabelledArea,
                height: AppSize.control,
              ),
        const SizedBox(width: 2),
        _closeButton(context, l10n, size: AppSize.control),
      ],
    );
  }

  /// The video's box: the playing video, the loading ring, or the error
  /// glyph (`1b`).
  Widget _buildVideo(BuildContext context, _PlayerMetrics metrics) {
    final colorScheme = Theme.of(context).colorScheme;
    final controller = _controller;

    final Widget content;
    if (_hasError) {
      content = ColoredBox(
        color: colorScheme.surfaceContainerHigh,
        child: Center(
          child: Icon(Icons.broken_image_outlined, size: metrics.playIcon, color: colorScheme.error),
        ),
      );
    } else if (controller != null && controller.value.isInitialized) {
      content = _VideoSurface(
        controller: controller,
        compact: metrics.form != _PlayerForm.panel,
        playIcon: metrics.playIcon,
      );
    } else {
      content = ColoredBox(
        color: colorScheme.surfaceContainerHigh,
        child: Center(
          child: SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: colorScheme.primary,
              backgroundColor: colorScheme.surfaceContainerHighest,
            ),
          ),
        ),
      );
    }

    return SizedBox.fromSize(
      size: metrics.video,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: content,
      ),
    );
  }

  /// `1a` 已完成 on the success container; `1b` 失败 on the error container.
  /// Nothing while the player is still opening the file.
  Widget? _statusBadge(BuildContext context, AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    if (_hasError) {
      return _Badge(
        label: l10n.videoPlaybackFailed,
        background: colorScheme.errorContainer,
        foreground: colorScheme.onErrorContainer,
      );
    }
    if (_controller?.value.isInitialized ?? false) {
      final semantic = context.semantic;
      return _Badge(
        label: l10n.completedTasks,
        background: semantic.successContainer,
        foreground: semantic.onSuccessContainer,
      );
    }
    return null;
  }

  /// What the player knows about the file: its frame size, its length and its
  /// size on disk.
  String? _facts() {
    final parts = <String>[];
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      final size = controller.value.size;
      if (size.width > 0 && size.height > 0) {
        parts.add('${size.width.round()}×${size.height.round()}');
      }
      final duration = controller.value.duration;
      if (duration > Duration.zero) {
        parts.add('${(duration.inMilliseconds / 1000).round()}s');
      }
    }
    final bytes = _fileBytes;
    if (bytes != null) parts.add(AppConstants.formatFileSize(bytes));
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// `1b`: the file's name after the reason, in the error ink.
  String _errorReason(AppLocalizations l10n, String path) =>
      l10n.videoPlaybackFailedReason(File(path).uri.pathSegments.last);

  /// What the player said when it could not decode the file, for the reason
  /// line's tooltip. Nothing when the file is simply gone.
  String get _errorDetail => _fileMissing ? '' : (_errorMessage ?? '');

  /// `1b` 重试: drop the failed player so the next build opens the file afresh.
  void _retry() => setState(_disposePlayer);

  Widget _actionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required bool labelled,
    required double height,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control));
    final side = BorderSide(color: colorScheme.outlineVariant);

    if (!labelled) {
      return IconButton(
        onPressed: onPressed,
        tooltip: label,
        icon: Icon(icon),
        style: IconButton.styleFrom(
          foregroundColor: colorScheme.onSurface,
          iconSize: AppSize.iconMd,
          fixedSize: Size.square(height),
          minimumSize: Size.square(height),
          maximumSize: Size.square(height),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.standard,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          side: side,
          shape: shape,
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: AppSize.iconMd),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        foregroundColor: colorScheme.onSurface,
        side: side,
        shape: shape,
        fixedSize: Size.fromHeight(height),
        minimumSize: Size(0, height),
        maximumSize: Size(double.infinity, height),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10),
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _closeButton(BuildContext context, AppLocalizations l10n, {required double size}) {
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton(
      icon: const Icon(Icons.close),
      tooltip: l10n.close,
      onPressed: () => Provider.of<WorkbenchUIState>(context, listen: false).setLastGeneratedVideoPath(null),
      style: IconButton.styleFrom(
        foregroundColor: colorScheme.onSurfaceVariant,
        iconSize: AppSize.iconMd,
        fixedSize: Size.square(size),
        minimumSize: Size.square(size),
        maximumSize: Size.square(size),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
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

/// A status badge: r4, 11/500, on its state's container.
class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.background, required this.foreground});

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: foreground),
      ),
    );
  }
}

/// The playing video and the controls laid over it on the image plate.
///
/// Tap anywhere toggles play; the centre button shows while paused, or while
/// the pointer is over the video. The full panel adds a transport bar —
/// progress, time and mute — along the bottom; the strips keep only a thin
/// scrubbable progress line.
class _VideoSurface extends StatefulWidget {
  const _VideoSurface({required this.controller, required this.compact, required this.playIcon});

  final VideoPlayerController controller;
  final bool compact;
  final double playIcon;

  @override
  State<_VideoSurface> createState() => _VideoSurfaceState();
}

class _VideoSurfaceState extends State<_VideoSurface> {
  bool _hovering = false;

  void _setHovering(bool value) {
    if (_hovering != value) setState(() => _hovering = value);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return MouseRegion(
      onEnter: (_) => _setHovering(true),
      onExit: (_) => _setHovering(false),
      child: GestureDetector(
        onTap: () => _togglePlay(controller),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The letterbox behind a video whose shape is not the box's.
            const ColoredBox(color: AppOverlay.ink),
            Center(
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: VideoPlayer(controller),
              ),
            ),
            _CentrePlayButton(controller: controller, hovering: _hovering, iconSize: widget.playIcon),
            if (widget.compact)
              Positioned(left: 0, right: 0, bottom: 0, child: _ProgressTrack(controller: controller))
            else
              Positioned(
                left: AppSpace.s6,
                right: AppSpace.s6,
                bottom: AppSpace.s6,
                child: _TransportBar(controller: controller),
              ),
          ],
        ),
      ),
    );
  }
}

void _togglePlay(VideoPlayerController controller) {
  if (controller.value.isPlaying) {
    controller.pause();
  } else {
    controller.play();
  }
}

class _CentrePlayButton extends StatelessWidget {
  const _CentrePlayButton({required this.controller, required this.hovering, required this.iconSize});

  final VideoPlayerController controller;
  final bool hovering;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    // Listen to the controller here (leaf) instead of the parent rebuilding
    // every frame. The button is always present (opacity-driven) so toggling
    // play/pause never adds or removes a node — AnimatedOpacity retargets
    // mid-flight instead of cross-fading duplicate children.
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final bool visible = !value.isPlaying || hovering;
        return IgnorePointer(
          ignoring: !visible,
          child: ExcludeSemantics(
            excluding: !visible,
            child: AnimatedOpacity(
              opacity: visible ? 1.0 : 0.0,
              duration: AppMotion.durationOf(context, AppMotion.reveal),
              curve: AppMotion.enter,
              child: Center(
                child: Tooltip(
                  message: value.isPlaying
                      ? AppLocalizations.of(context)!.videoPause
                      : AppLocalizations.of(context)!.videoPlay,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => _togglePlay(controller),
                      child: Container(
                        width: iconSize + 12,
                        height: iconSize + 12,
                        decoration: const BoxDecoration(color: AppOverlay.imagePlate, shape: BoxShape.circle),
                        child: Icon(
                          value.isPlaying ? Icons.pause : Icons.play_arrow,
                          size: iconSize,
                          color: AppOverlay.onImagePlate,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// `1a`: progress, `00:03 / 00:08` in mono 11, and the volume glyph, on the
/// image plate along the bottom of the video.
class _TransportBar extends StatelessWidget {
  const _TransportBar({required this.controller});

  final VideoPlayerController controller;

  static String _clock(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final monoStyle = Theme.of(context).textTheme.labelSmall?.mono.copyWith(
          fontWeight: FontWeight.w400,
          color: AppOverlay.onImagePlate,
          height: 1,
        );
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppOverlay.imagePlate,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          Expanded(child: _ProgressTrack(controller: controller)),
          const SizedBox(width: 8),
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: controller,
            builder: (context, value, _) => Text(
              '${_clock(value.position)} / ${_clock(value.duration)}',
              style: monoStyle,
            ),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final bool muted = value.volume == 0;
              final l10n = AppLocalizations.of(context)!;
              return Tooltip(
                message: muted ? l10n.videoUnmute : l10n.videoMute,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => controller.setVolume(muted ? 1 : 0),
                    child: Icon(
                      muted ? Icons.volume_off : Icons.volume_up,
                      size: AppSize.iconSm,
                      color: AppOverlay.onImagePlate,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// A 3px scrubbable progress line — white at 35% under the played white —
/// inside a 12px hit band.
class _ProgressTrack extends StatelessWidget {
  const _ProgressTrack({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 12,
      child: VideoProgressIndicator(
        controller,
        allowScrubbing: true,
        padding: const EdgeInsets.symmetric(vertical: 4.5),
        colors: VideoProgressColors(
          playedColor: AppOverlay.onImagePlate,
          bufferedColor: AppOverlay.onImagePlate.withValues(alpha: 0.5),
          backgroundColor: AppOverlay.onImagePlate.withValues(alpha: 0.35),
        ),
      ),
    );
  }
}
