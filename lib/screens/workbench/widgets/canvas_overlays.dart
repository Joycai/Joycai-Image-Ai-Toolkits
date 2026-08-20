import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';

/// The two floating controls a canvas tool draws over its picture.
///
/// Both the crop editor and the mask editor had drawn their own: the mask
/// editor's zoom pill was a white card with a hairline edge, the crop editor's
/// was black ink at 55%, and each file's doc comment claimed to be mirroring
/// the other. The design spec draws one — `#fff` with a `#e5e9e7` border,
/// bottom-right of the canvas — so it lives here and both call it.

/// Bottom-right zoom readout: current scale against the source image's native
/// resolution (100% = one screen pixel per source pixel), plus a fit action.
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
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
              style: Theme.of(context).textTheme.labelMedium?.copyWith(fontFamily: 'monospace'),
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
            borderRadius: BorderRadius.circular(AppRadius.xs),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Text(
                l10n.fitToWindow,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
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
      borderRadius: BorderRadius.circular(AppRadius.xs),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Icon(icon, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

/// Top-left caption over a canvas: what is loaded, or what the tool is about
/// to do to it.
///
/// Ink rather than a theme surface — this sits over a photograph, and a
/// surface-coloured chip disappears into whatever the picture happens to be
/// under it. The spec draws it at `rgba(22,28,26,.72)`.
class CanvasBadge extends StatelessWidget {
  final String label;
  final IconData? icon;

  const CanvasBadge({super.key, required this.label, this.icon});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: Colors.white),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // Mono, because what this says is a measurement — a brush
                // width, a coverage percentage, a pixel size. `10o` sets it
                // that way, and it is the same reason the gallery's dimension
                // badge and the metadata panel's values are: numbers that
                // change under the pointer should not reflow the label
                // around them every time a digit does.
                style: Theme.of(context).textTheme.labelSmall?.mono.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
