import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/image_metadata_service.dart';
import '../../../state/app_state.dart';
import '../../../state/workbench_ui_state.dart';

/// Space around each image and between the two (`A5 · 1c`: inset 10, gap 10).
const double _kGutter = AppSpace.s10;

/// Where a plate sits inside the image it labels.
const double _kPlateInset = 8;

/// The comparator's canvas (`A5 · 1c`, `A5 · 1d`).
///
/// A content layer, not glass: the images sit straight on the window's aurora
/// at r10 with 10px around them, and everything written over them — the role
/// badges, the filenames, the zoom readout — is on the fixed image plate, so a
/// label never takes its colour from the theme it happens to cover.
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
  /// view reconstructs both full-size image layers to move a clip rect. Only
  /// the curtain, the handle and the two badges read it.
  final ValueNotifier<double> _scanRatio = ValueNotifier<double>(0.5);

  /// The curtain drag's own accumulator, in pixels, allowed slightly past the
  /// pane so the handle keeps its grab offset at the edges. Null between drags.
  double? _dragScanPos;

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

  /// Hands the user to the gallery — the comparator is filled from an image's
  /// context menu there, so this goes to the place that can do it rather than
  /// opening a second, parallel picker.
  void _openLibrary() => Provider.of<AppState>(context, listen: false).setWorkbenchTab(0);

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
      return _EmptyState(onPick: _openLibrary);
    }

    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.all(_kGutter),
            child: switch (uiState.comparatorLayout) {
              ComparatorLayout.sideBySide => _buildSplit(uiState, l10n, Axis.horizontal),
              ComparatorLayout.stacked => _buildSplit(uiState, l10n, Axis.vertical),
              ComparatorLayout.slider => _buildSlider(uiState, l10n),
            },
          ),
        ),
        // Centred along the foot of the canvas, 10px inside the images.
        Positioned(
          left: _kGutter,
          right: _kGutter,
          bottom: _kGutter * 2,
          child: IgnorePointer(
            child: Center(
              // Rebuilt from the controller alone: a zoom readout that re-ran
              // the whole view on every pan would re-decode both images for a
              // number.
              child: AnimatedBuilder(
                animation: _rawController,
                builder: (context, _) {
                  final percent = (_rawController.value.getMaxScaleOnAxis() * 100).round();
                  final synced = uiState.comparatorLayout == ComparatorLayout.slider ||
                      uiState.comparatorSyncTransform;
                  return _ImagePlate(
                    text: synced
                        ? l10n.comparatorZoomSynced(percent)
                        : l10n.comparatorZoomIndependent(percent),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Two panes across or down, each with its own badge and filename.
  Widget _buildSplit(WorkbenchUIState uiState, AppLocalizations l10n, Axis axis) {
    final panes = [
      Expanded(
        child: _buildPane(
          uiState.comparatorRawPath,
          label: l10n.labelRaw,
          pickLabel: l10n.comparatorPickRaw,
          controller: _rawController,
          l10n: l10n,
        ),
      ),
      const SizedBox(width: _kGutter, height: _kGutter),
      Expanded(
        child: _buildPane(
          uiState.comparatorAfterPath,
          label: l10n.labelAfter,
          pickLabel: l10n.comparatorPickAfter,
          controller: _afterController,
          l10n: l10n,
        ),
      ),
    ];

    return axis == Axis.horizontal
        ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: panes)
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: panes);
  }

  Widget _buildPane(
    String? path, {
    required String label,
    required String pickLabel,
    required TransformationController controller,
    required AppLocalizations l10n,
  }) {
    // One side still missing: the pane is the way to fill it.
    if (path == null) {
      return Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: 180,
            child: _ChooseCard(label: pickLabel, hint: l10n.selectFromLibrary, onTap: _openLibrary),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Stack(
        fit: StackFit.expand,
        children: [
          InteractiveViewer(
            transformationController: controller,
            minScale: 0.1,
            maxScale: 10.0,
            child: Center(child: Image.file(File(path), fit: BoxFit.contain)),
          ),
          // The filename rides beside the badge rather than at the foot, where
          // the design draws it: the zoom readout is centred along the foot of
          // the canvas, and in side-by-side the right pane's filename started
          // exactly under it.
          Positioned(
            top: _kPlateInset,
            left: _kPlateInset,
            right: _kPlateInset,
            child: IgnorePointer(
              child: Row(
                children: [
                  _ImagePlate(text: label, strong: true),
                  const SizedBox(width: AppSpace.s4),
                  Flexible(child: _FileNamePlate(path: path)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// One image over the other, revealed by a draggable curtain. Both layers
  /// ride the same controller — the reveal is only meaningful if the two are
  /// registered pixel for pixel.
  Widget _buildSlider(WorkbenchUIState uiState, AppLocalizations l10n) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Built once per rebuild of this view, and handed to the builders
          // below as their `child` so the curtain moving never rebuilds them.
          // These are full-resolution images inside an InteractiveViewer;
          // reconstructing them per hover event was the whole cost.
          final afterLayer = _buildLayer(uiState.comparatorAfterPath, l10n);
          final rawLayer = _buildLayer(uiState.comparatorRawPath, l10n);

          return MouseRegion(
            onHover: (event) =>
                _scanRatio.value = (event.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0),
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
                      onHorizontalDragStart: (_) =>
                          _dragScanPos = constraints.maxWidth * _scanRatio.value,
                      // The accumulator, not the ratio, absorbs the drag:
                      // recomputing from the clamped ratio meant that once the
                      // curtain pinned at an edge, the handle re-engaged the
                      // moment the pointer reversed — wherever the pointer
                      // happened to be. 24px of slack, same as the panel
                      // resizers.
                      onHorizontalDragUpdate: (details) {
                        _dragScanPos =
                            ((_dragScanPos ?? constraints.maxWidth * _scanRatio.value) + details.delta.dx)
                                .clamp(-24.0, constraints.maxWidth + 24.0);
                        _scanRatio.value = (_dragScanPos! / constraints.maxWidth).clamp(0.0, 1.0);
                      },
                      onHorizontalDragEnd: (_) => _dragScanPos = null,
                      onHorizontalDragCancel: () => _dragScanPos = null,
                      child: const _CurtainHandle(),
                    ),
                    builder: (context, ratio, child) => Stack(
                      children: [
                        Positioned(
                          top: 0,
                          bottom: 0,
                          left: constraints.maxWidth * ratio - _CurtainHandle.hitWidth / 2,
                          child: child!,
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: _kPlateInset,
                  left: _kPlateInset,
                  child: IgnorePointer(
                    child: ValueListenableBuilder<double>(
                      valueListenable: _scanRatio,
                      builder: (context, ratio, _) => _ImagePlate(
                        text: l10n.labelRaw,
                        strong: true,
                        opacity: (1.0 - ratio).clamp(0.4, 1.0),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: _kPlateInset,
                  right: _kPlateInset,
                  child: IgnorePointer(
                    child: ValueListenableBuilder<double>(
                      valueListenable: _scanRatio,
                      builder: (context, ratio, _) => _ImagePlate(
                        text: l10n.labelAfter,
                        strong: true,
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
    );
  }

  Widget _buildLayer(String? path, AppLocalizations l10n) {
    if (path == null) {
      return Center(
        child: Text(
          l10n.noImagesSelected,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
}

/// A label on the fixed dark plate laid over user images: mono 11 at r4.
///
/// Never themed (`A4–A6` 「角标」): what sits under it is a photograph, not
/// the app.
class _ImagePlate extends StatelessWidget {
  const _ImagePlate({
    required this.text,
    this.strong = false,
    this.opacity = 1.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
  });

  final String text;

  /// The role badges (RAW / AFTER) are 600; readouts and filenames are 400.
  final bool strong;
  final double opacity;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final plate = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppOverlay.imagePlate,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: Theme.of(context).textTheme.labelSmall!.metricsOnly.mono.copyWith(
              color: AppOverlay.onImagePlate,
              fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
            ),
      ),
    );
    return opacity >= 1.0 ? plate : Opacity(opacity: opacity, child: plate);
  }
}

/// `IMG_2041.png · 4000×3000`: the file's name and, once measured, its pixels.
class _FileNamePlate extends StatelessWidget {
  const _FileNamePlate({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final name = path.split(Platform.pathSeparator).last;
    final service = ImageMetadataService();
    return FutureBuilder<ImageMetadata?>(
      // The service caches and de-duplicates reads, and the inspector asks
      // for the same two files — this costs nothing after the first frame.
      future: service.getMetadata(path),
      initialData: service.peek(path),
      builder: (context, snapshot) {
        final meta = snapshot.data;
        final text = meta != null && meta.width > 0 ? '$name · ${meta.width}×${meta.height}' : name;
        return _ImagePlate(text: text);
      },
    );
  }
}

/// The curtain's grab line: a 2px white rule with a round grip at its middle,
/// so it reads as draggable on touch as well as under a mouse.
class _CurtainHandle extends StatelessWidget {
  const _CurtainHandle();

  /// The hit area, wider than the grip it centres.
  static const double hitWidth = AppSize.touch;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: SizedBox(
        width: hitWidth,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 2,
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 8)],
              ),
            ),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(Icons.code, size: AppSize.iconMd, color: AppOverlay.ink),
            ),
          ],
        ),
      ),
    );
  }
}

/// Nothing loaded yet (`A5 · 1d` centre): what the comparator is for, and the
/// two ways to fill it.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onPick});

  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.s22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.compare, size: 28, color: colorScheme.outline),
            const SizedBox(height: AppSpace.s10),
            Text(
              l10n.sendToComparator,
              textAlign: TextAlign.center,
              style: textTheme.titleLarge?.copyWith(color: colorScheme.onSurface),
            ),
            const SizedBox(height: AppSpace.s10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Text(
                l10n.comparatorEmptyHint,
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: AppType.proseHeight,
                ),
              ),
            ),
            const SizedBox(height: 14),
            // Wrap, not Row: on a phone the two cards stack instead of being
            // squeezed to half a label each.
            Wrap(
              spacing: AppSpace.s10,
              runSpacing: AppSpace.s10,
              alignment: WrapAlignment.center,
              children: [
                SizedBox(width: 160, child: _ChooseCard(label: l10n.comparatorPickRaw, onTap: onPick)),
                SizedBox(width: 160, child: _ChooseCard(label: l10n.comparatorPickAfter, onTap: onPick)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A "choose an image" target: a panel card with the accent's wash behind the
/// glyph, used by the empty state and by a pane still waiting for its image.
class _ChooseCard extends StatelessWidget {
  const _ChooseCard({required this.label, required this.onTap, this.hint});

  final String label;
  final String? hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.s16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: AppSize.touch,
                height: AppSize.touch,
                decoration: BoxDecoration(
                  color: colorScheme.accentTint,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: Icon(Icons.add_photo_alternate_outlined, size: 24, color: colorScheme.primary),
              ),
              const SizedBox(height: AppSpace.s10),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              if (hint != null) ...[
                const SizedBox(height: AppSpace.s4),
                Text(
                  hint!,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CurtainClipper extends CustomClipper<Rect> {
  final double ratio;
  _CurtainClipper(this.ratio);

  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, 0, size.width * ratio, size.height);

  @override
  bool shouldReclip(_CurtainClipper oldClipper) => oldClipper.ratio != ratio;
}
