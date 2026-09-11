import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';

/// The floating pieces a canvas tool draws over its picture (`A4–A6`).
///
/// The canvas is the content layer — opaque pixels on the window's ground —
/// so nothing here is glass. Both the crop editor and the mask editor call
/// these, so the two tools' canvases read as one surface.

/// Bottom zoom readout: current scale against the source image's native
/// resolution (100% = one screen pixel per source pixel), plus a fit action.
///
/// An opaque panel, like the output preview card beside it: it is a number to
/// read, not a control layer.
class CanvasZoomPill extends StatelessWidget {
  final double percent;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFit;

  const CanvasZoomPill({
    super.key,
    required this.percent,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: colorScheme.shadowOverlay,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _pillIcon(context, Icons.remove, onZoomOut),
          SizedBox(
            width: 44,
            child: Text(
              '${percent.round()}%',
              textAlign: TextAlign.center,
              maxLines: 1,
              style: textTheme.bodySmall!.mono.copyWith(color: colorScheme.onSurface),
            ),
          ),
          _pillIcon(context, Icons.add, onZoomIn),
          Container(
            width: 1,
            height: 16,
            color: colorScheme.outlineVariant,
            margin: const EdgeInsets.symmetric(horizontal: 4),
          ),
          InkWell(
            onTap: onFit,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Text(
                l10n.fitToWindow,
                maxLines: 1,
                style: textTheme.bodySmall!.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pillIcon(BuildContext context, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Icon(icon, size: AppSize.iconSm, color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

/// A caption laid over a picture: what is loaded, what the brush will lay
/// down, the size of a selection.
///
/// `A4–A6` 「角标」: the fixed image plate — `rgba(20,19,16,.72)` under
/// `#F2F0EA`, r4, mono 11 — in both brightnesses. A theme surface disappears
/// into whatever the photograph happens to be under it, and eight of these on
/// one screen should not each resolve a colour.
///
/// [inverted] is the light plate (`rgba(242,240,234,.9)` under `#1C1B18`) for
/// a caption that sits on a canvas that may be pure black — `A6 · 1f`'s
/// binary-mode notice, which has to hold 4.5:1 there.
class CanvasBadge extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool inverted;

  const CanvasBadge({super.key, required this.label, this.icon, this.inverted = false});

  /// Distance from the corner of the picture it labels.
  static const double inset = 8;

  @override
  Widget build(BuildContext context) {
    final Color ground = inverted ? AppOverlay.onImagePlate.withValues(alpha: 0.9) : AppOverlay.imagePlate;
    final Color ink = inverted ? AppOverlay.ink : AppOverlay.onImagePlate;

    return IgnorePointer(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: ground,
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: ink),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                // Mono, because what this says is a measurement — a brush
                // width, a pixel size, a file's name. Numbers that change
                // under the pointer should not reflow the label around them
                // every time a digit does.
                style: Theme.of(context)
                    .textTheme
                    .labelSmall!
                    .metricsOnly
                    .mono
                    .copyWith(fontWeight: FontWeight.w400, color: ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
