import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../state/app_state.dart';
import '../../../state/workbench_ui_state.dart';

/// Radius of a pane inside the canvas. Deliberately the smallest step on the
/// ladder: the panes sit 2px apart on a flat ground and read as one surface
/// split in two, not as two cards.
const double _kPaneRadius = AppRadius.xs;

class ComparatorView extends StatefulWidget {
  const ComparatorView({super.key});

  @override
  State<ComparatorView> createState() => _ComparatorViewState();
}

class _ComparatorViewState extends State<ComparatorView> {
  final TransformationController _rawController = TransformationController();
  final TransformationController _afterController = TransformationController();

  /// Mirrors [WorkbenchUIState.comparatorSyncTransform], read in `build` so
  /// the listeners below know whether to copy a transform across.
  bool _sync = true;

  /// Guards the mirror against the write it just made coming back the other
  /// way.
  bool _mirroring = false;

  /// Where the reveal curtain sits, 0–1 across the pane.
  ///
  /// A notifier rather than a field behind `setState`: it is driven by
  /// `MouseRegion.onHover`, so it moves at pointer rate, and a rebuild of this
  /// view reconstructs both full-size image layers and the footer to move a
  /// clip rect. Only the curtain, the handle and the two badges read it.
  final ValueNotifier<double> _scanRatio = ValueNotifier<double>(0.5);

  @override
  void initState() {
    super.initState();
    _rawController.addListener(_mirrorFromRaw);
    _afterController.addListener(_mirrorFromAfter);
  }

  void _mirrorFromRaw() => _mirror(_rawController, _afterController);
  void _mirrorFromAfter() => _mirror(_afterController, _rawController);

  /// Copies one pane's zoom/pan onto the other while sync is on.
  ///
  /// Two-way rather than the old one-way copy: with a controller on each pane
  /// both are interactive, and mirroring only the left one meant panning the
  /// right pane silently broke the alignment the mode exists to hold.
  void _mirror(TransformationController from, TransformationController to) {
    if (!_sync || _mirroring || from.value == to.value) return;
    _mirroring = true;
    to.value = from.value;
    _mirroring = false;
  }

  @override
  void dispose() {
    _rawController.removeListener(_mirrorFromRaw);
    _afterController.removeListener(_mirrorFromAfter);
    _rawController.dispose();
    _afterController.dispose();
    _scanRatio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uiState = Provider.of<WorkbenchUIState>(context);
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    if (_sync != uiState.comparatorSyncTransform) {
      _sync = uiState.comparatorSyncTransform;
      // Turning sync back on has to bring the panes together again; doing it
      // now would mutate a controller mid-build, so it waits for the frame.
      if (_sync) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _mirror(_rawController, _afterController);
        });
      }
    }

    if (uiState.comparatorRawPath == null && uiState.comparatorAfterPath == null) {
      return _EmptyState(l10n: l10n, colorScheme: colorScheme);
    }

    return Column(
      children: [
        Expanded(
          child: Container(
            color: colorScheme.surfaceContainerHigh,
            padding: const EdgeInsets.all(2),
            child: switch (uiState.comparatorLayout) {
              ComparatorLayout.sideBySide => _buildSplit(uiState, l10n, Axis.horizontal),
              ComparatorLayout.stacked => _buildSplit(uiState, l10n, Axis.vertical),
              ComparatorLayout.slider => _buildSlider(uiState, l10n),
            },
          ),
        ),
        _buildFooter(uiState, l10n, colorScheme),
      ],
    );
  }

  /// Two panes across or down, each with its own badge and filename caption.
  Widget _buildSplit(WorkbenchUIState uiState, AppLocalizations l10n, Axis axis) {
    final panes = [
      Expanded(
        child: _buildPane(uiState.comparatorRawPath, l10n.labelRaw, l10n, _rawController, isAfter: false),
      ),
      const SizedBox(width: 2, height: 2),
      Expanded(
        child: _buildPane(uiState.comparatorAfterPath, l10n.labelAfter, l10n, _afterController, isAfter: true),
      ),
    ];

    return axis == Axis.horizontal ? Row(children: panes) : Column(children: panes);
  }

  Widget _buildPane(
    String? path,
    String label,
    AppLocalizations l10n,
    TransformationController controller, {
    required bool isAfter,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(_kPaneRadius),
      child: Container(
        color: colorScheme.surfaceContainerHighest,
        child: path == null
            ? Center(
                child: Text(
                  l10n.noImagesSelected,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.outline),
                ),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  InteractiveViewer(
                    transformationController: controller,
                    minScale: 0.1,
                    maxScale: 10.0,
                    child: Center(child: Image.file(File(path), fit: BoxFit.contain)),
                  ),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: IgnorePointer(child: _RoleBadge(label: label, isAfter: isAfter)),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: IgnorePointer(child: _FileNameOverlay(path: path)),
                  ),
                ],
              ),
      ),
    );
  }

  /// One image over the other, revealed by a draggable curtain. Both layers
  /// ride the same controller — the reveal is only meaningful if the two are
  /// registered pixel for pixel.
  Widget _buildSlider(WorkbenchUIState uiState, AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(_kPaneRadius),
      child: Container(
        color: colorScheme.surfaceContainerHighest,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Built once per rebuild of this view, and handed to the builders
            // below as their `child` so the curtain moving never rebuilds
            // them. These are full-resolution images inside an
            // InteractiveViewer; reconstructing them per hover event was the
            // whole cost.
            final afterLayer = _buildLayer(uiState.comparatorAfterPath, l10n);
            final rawLayer = _buildLayer(uiState.comparatorRawPath, l10n);

            return MouseRegion(
              onHover: (event) => _scanRatio.value =
                  (event.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  afterLayer,
                  ValueListenableBuilder<double>(
                    valueListenable: _scanRatio,
                    child: rawLayer,
                    builder: (context, ratio, child) => ClipRect(
                      clipper: _CurtainClipper(ratio),
                      child: child,
                    ),
                  ),
                  // Positioned has to be the Stack's direct child, so the
                  // listener sits inside a fill and re-positions the handle
                  // within a nested Stack of its own.
                  Positioned.fill(
                    child: ValueListenableBuilder<double>(
                      valueListenable: _scanRatio,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onHorizontalDragUpdate: (details) {
                          final newPos =
                              constraints.maxWidth * _scanRatio.value + details.delta.dx;
                          _scanRatio.value =
                              (newPos / constraints.maxWidth).clamp(0.0, 1.0);
                        },
                        child: _CurtainHandle(colorScheme: colorScheme),
                      ),
                      builder: (context, ratio, child) => Stack(
                        children: [
                          Positioned(
                            top: 0,
                            bottom: 0,
                            left: constraints.maxWidth * ratio - 20, // wider hit area
                            child: child!,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: IgnorePointer(
                      child: ValueListenableBuilder<double>(
                        valueListenable: _scanRatio,
                        builder: (context, ratio, _) => _RoleBadge(
                          label: l10n.labelRaw,
                          isAfter: false,
                          opacity: (1.0 - ratio).clamp(0.4, 1.0),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: IgnorePointer(
                      child: ValueListenableBuilder<double>(
                        valueListenable: _scanRatio,
                        builder: (context, ratio, _) => _RoleBadge(
                          label: l10n.labelAfter,
                          isAfter: true,
                          opacity: ratio.clamp(0.4, 1.0),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLayer(String? path, AppLocalizations l10n) {
    if (path == null) {
      return Center(
        child: Text(
          l10n.noImagesSelected,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
      );
    }
    return InteractiveViewer(
      transformationController: _rawController,
      minScale: 0.1,
      maxScale: 10.0,
      child: Center(child: Image.file(File(path), fit: BoxFit.contain)),
    );
  }

  /// Which two files are being compared, and how the canvas is currently
  /// navigated — the same strip the crop editor carries, so both tools state
  /// their result in the same place.
  Widget _buildFooter(WorkbenchUIState uiState, AppLocalizations l10n, ColorScheme colorScheme) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant.withAlpha(80))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: _FooterEntry(
                    label: l10n.labelRaw,
                    path: uiState.comparatorRawPath,
                    isAfter: false,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_right_alt, size: 16, color: colorScheme.onSurfaceVariant),
                ),
                Flexible(
                  child: _FooterEntry(
                    label: l10n.labelAfter,
                    path: uiState.comparatorAfterPath,
                    isAfter: true,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Rebuilt from the controller alone: a zoom readout that re-ran the
          // whole view on every pan would re-decode both images for a number.
          AnimatedBuilder(
            animation: _rawController,
            builder: (context, _) {
              final percent = (_rawController.value.getMaxScaleOnAxis() * 100).round();
              final synced = uiState.comparatorLayout == ComparatorLayout.slider ||
                  uiState.comparatorSyncTransform;
              return _StatusPill(
                label: synced
                    ? l10n.comparatorZoomSynced(percent)
                    : l10n.comparatorZoomIndependent(percent),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// "RAW" / "AFTER" over the top-left of a pane.
///
/// The before badge stays neutral ink and the after badge takes the accent:
/// the accent means *this is the result* here, which is the one distinction
/// the whole screen exists to draw.
class _RoleBadge extends StatelessWidget {
  final String label;
  final bool isAfter;
  final double opacity;

  const _RoleBadge({required this.label, required this.isAfter, this.opacity = 1.0});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Ink, not surface: these sit on a photograph, where a theme-tinted plate
    // would tint whatever it covers.
    final background = isAfter
        ? colorScheme.primary.withValues(alpha: 0.85 * opacity)
        : Colors.black.withValues(alpha: 0.72 * opacity);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: isAfter ? colorScheme.onPrimary : Colors.white,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// The filename along the foot of a pane, on a gradient that fades into the
/// picture rather than a bar that cuts across it.
class _FileNameOverlay extends StatelessWidget {
  final String path;

  const _FileNameOverlay({required this.path});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.55)],
        ),
      ),
      child: Text(
        path.split(Platform.pathSeparator).last,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontFamily: 'monospace',
            ),
      ),
    );
  }
}

/// One "role chip + filename" pair in the footer strip.
class _FooterEntry extends StatelessWidget {
  final String label;
  final String? path;
  final bool isAfter;

  const _FooterEntry({required this.label, required this.path, required this.isAfter});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: isAfter ? colorScheme.accentTint : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.xs),
          ),
          child: Text(
            label,
            style: textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: isAfter ? colorScheme.onAccentTint : colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            path?.split(Platform.pathSeparator).last ?? '—',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: isAfter ? colorScheme.onAccentTint : colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// The capsule at the right of the footer strip, matching the crop editor's.
class _StatusPill extends StatelessWidget {
  final String label;

  const _StatusPill({required this.label});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.accentTint,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colorScheme.onAccentTint),
      ),
    );
  }
}

/// The curtain's grab line: a hairline with a round grip at its middle, so it
/// reads as draggable on touch as well as under a mouse.
class _CurtainHandle extends StatelessWidget {
  final ColorScheme colorScheme;

  const _CurtainHandle({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 2,
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 4)],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 6)],
            ),
            child: const RotatedBox(
              quarterTurns: 1,
              child: Icon(Icons.unfold_more, size: 16, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}

/// Nothing loaded yet: what the comparator is for, and the two ways to fill it.
class _EmptyState extends StatelessWidget {
  final AppLocalizations l10n;
  final ColorScheme colorScheme;

  const _EmptyState({required this.l10n, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      color: colorScheme.surfaceContainerHigh,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppRadius.dialog),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Icon(Icons.compare, size: 28, color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 22),
              Text(l10n.sendToComparator, style: textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                l10n.comparatorEmptyHint,
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 22),
              // Wrap, not Row: on a phone the two cards stack instead of
              // being squeezed to half a label each.
              Wrap(
                spacing: 14,
                runSpacing: 14,
                alignment: WrapAlignment.center,
                children: [
                  _PickCard(
                    icon: Icons.photo_outlined,
                    title: l10n.comparatorPickRaw,
                    subtitle: l10n.selectFromLibrary,
                  ),
                  _PickCard(
                    icon: Icons.auto_fix_high,
                    title: l10n.comparatorPickAfter,
                    subtitle: l10n.selectFromLibrary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A "choose an image" target. Dashed rather than outlined: the edge says the
/// box is waiting to be filled, which a solid border reads as already being.
///
/// Tapping goes to the gallery — the comparator is filled from an image's
/// context menu there, so this hands the user to the place that can do it
/// rather than opening a second, parallel picker.
class _PickCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _PickCard({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: () => Provider.of<AppState>(context, listen: false).setWorkbenchTab(0),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: CustomPaint(
        painter: _DashedBorderPainter(
          color: colorScheme.outlineVariant,
          radius: AppRadius.lg,
        ),
        child: Container(
          width: 200,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colorScheme.accentTint,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(icon, size: 17, color: colorScheme.onAccentTint),
              ),
              const SizedBox(height: 10),
              Text(title, style: textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Draws a rounded rectangle in dashes. Flutter's [Border] can't dash, and the
/// two drop targets are the only place in the app that needs it.
class _DashedBorderPainter extends CustomPainter {
  static const double _dash = 5;
  static const double _gap = 4;

  final Color color;
  final double radius;

  const _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, (distance + _dash).clamp(0.0, metric.length)),
          paint,
        );
        distance += _dash + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

class _CurtainClipper extends CustomClipper<Rect> {
  final double ratio;
  _CurtainClipper(this.ratio);

  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, 0, size.width * ratio, size.height);

  @override
  bool shouldReclip(_CurtainClipper oldClipper) => oldClipper.ratio != ratio;
}
