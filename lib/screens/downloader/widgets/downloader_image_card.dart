import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../core/file_utils.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/image_metadata_service.dart';
import '../../../services/web_scraper_service.dart';
import '../../../widgets/app_snackbar.dart';
import '../../../widgets/glass/app_glass.dart';

/// Inset of the tick and the meta plate from the card's edge (`left/top 8`).
const double _inset = 8;

/// One discovered picture (`B3 · 1a`): the image filling an r10 tile, a tick
/// that is always drawn — picking is what this grid is for — and a mono plate
/// with the cached copy's size.
///
/// Selected is a 2px accent ring outside the picture with the ring colour
/// beyond it, as the workbench card draws it, so a picked photo is neither
/// washed nor shrunk. Right-click or long-press opens a glass menu.
class DownloaderImageCard extends StatefulWidget {
  const DownloaderImageCard({
    super.key,
    required this.image,
    required this.extent,
    required this.onToggle,
  });

  final DiscoveredImage image;

  /// The tile's side, which is also the width the cached copy is decoded at.
  final double extent;
  final VoidCallback onToggle;

  @override
  State<DownloaderImageCard> createState() => _DownloaderImageCardState();
}

class _DownloaderImageCardState extends State<DownloaderImageCard> {
  String _meta = '';

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  @override
  void didUpdateWidget(DownloaderImageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image.localCachePath != widget.image.localCachePath) {
      _meta = '';
      _loadMeta();
    }
  }

  /// Cache first, as the workbench card does: a tile scrolled back into view
  /// already has its measurement.
  void _loadMeta() {
    final path = widget.image.localCachePath;
    if (path == null) return;
    final known = ImageMetadataService().peek(path);
    if (known != null) {
      _meta = known.displayString;
      return;
    }
    ImageMetadataService().getMetadata(path).then(
      (metadata) {
        if (!mounted || metadata == null || widget.image.localCachePath != path) return;
        setState(() => _meta = metadata.displayString);
      },
      onError: (Object _) {},
    );
  }

  void _openMenu(Offset position) {
    final l10n = AppLocalizations.of(context)!;
    final url = widget.image.url;
    _showGlassMenu(
      context,
      position: position,
      items: [
        _GlassMenuItem(
          icon: Icons.open_in_new,
          label: l10n.openRawImage,
          onSelected: () {
            final uri = Uri.tryParse(url);
            if (uri != null) FileUtils.openUri(uri);
          },
        ),
        _GlassMenuItem(
          icon: Icons.content_copy,
          label: l10n.copyImageUrl,
          onSelected: () {
            Clipboard.setData(ClipboardData(text: url));
            if (mounted) AppSnackBar.success(context, l10n.copiedToClipboard(url));
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.image.isSelected;
    final path = widget.image.localCachePath;

    final Widget picture = path == null
        ? _placeholder(scheme, Icons.image_outlined)
        : Image.file(
            File(path),
            fit: BoxFit.cover,
            // A scraped page can hand back full-size artwork; decoding each at
            // native resolution for a 168px tile filled the image cache many
            // times over.
            cacheWidth: (widget.extent * MediaQuery.devicePixelRatioOf(context)).round(),
            errorBuilder: (context, error, stackTrace) => _placeholder(scheme, Icons.broken_image_outlined),
          );

    final card = AnimatedContainer(
      duration: AppMotion.durationOf(context, AppMotion.hover),
      curve: AppMotion.quick,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.control),
        color: scheme.surfaceContainerHighest,
        // Shadows paint outside the clip and in list order: the ring colour
        // first, the solid 2px over it.
        boxShadow: selected
            ? [
                BoxShadow(color: scheme.accentRing, spreadRadius: 4),
                BoxShadow(color: scheme.primary, spreadRadius: 2),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          picture,
          if (_meta.isNotEmpty)
            Positioned(
              left: _inset,
              right: _inset,
              bottom: _inset,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppOverlay.imagePlate,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6, vertical: 2),
                  child: Text(
                    _meta,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall!.mono.copyWith(
                          color: AppOverlay.onImagePlate,
                          fontWeight: FontWeight.w400,
                          height: AppType.tightHeight,
                        ),
                  ),
                ),
              ),
            ),
          Positioned(top: _inset, left: _inset, child: _TickCircle(selected: selected)),
        ],
      ),
    );

    return Semantics(
      button: true,
      selected: selected,
      label: (widget.image.alt?.isNotEmpty ?? false) ? widget.image.alt : widget.image.url,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onToggle,
          onSecondaryTapDown: (details) => _openMenu(details.globalPosition),
          onLongPressStart: (details) => _openMenu(details.globalPosition),
          child: card,
        ),
      ),
    );
  }

  Widget _placeholder(ColorScheme scheme, IconData icon) => ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: Center(child: Icon(icon, size: AppSize.iconLg, color: scheme.outline)),
      );
}

/// The round tick on the picture (`勾选框 20 圆`). Unticked it is the image
/// plate at 55% under a white 45% edge so it reads on any photograph; ticked
/// it is the solid accent.
class _TickCircle extends StatelessWidget {
  const _TickCircle({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: AppMotion.durationOf(context, AppMotion.hover),
      curve: AppMotion.quick,
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? scheme.primary : AppOverlay.imagePlate.withValues(alpha: 0.55),
        border: selected ? null : Border.all(color: Colors.white.withValues(alpha: 0.45)),
      ),
      child: selected ? Icon(Icons.check, size: AppSize.iconSm, color: scheme.onPrimary) : null,
    );
  }
}

class _GlassMenuItem {
  const _GlassMenuItem({required this.icon, required this.label, required this.onSelected});

  final IconData icon;
  final String label;
  final VoidCallback onSelected;
}

/// Shows a 200px float-grade glass menu at [position] (`B3 · 1c` 「结果卡右键
/// G2 200」).
///
/// A route of its own rather than [showMenu]: Material's popup route draws
/// behind its own clip, where a backdrop filter cannot reach the page.
Future<void> _showGlassMenu(
  BuildContext context, {
  required Offset position,
  required List<_GlassMenuItem> items,
}) {
  return Navigator.of(context).push(_GlassMenuRoute(
    position: position,
    items: items,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    duration: AppMotion.durationOf(context, AppMotion.state),
  ));
}

class _GlassMenuRoute extends PopupRoute<void> {
  _GlassMenuRoute({
    required this.position,
    required this.items,
    required this.barrierLabel,
    required Duration duration,
  }) : _duration = duration;

  final Offset position;
  final List<_GlassMenuItem> items;
  final Duration _duration;

  static const double _width = 200;
  static const double _pad = AppSpace.s6;
  static const double _row = AppSize.compact;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => _duration;

  @override
  Duration get reverseTransitionDuration => _duration * AppMotion.exitFactor;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    final size = MediaQuery.sizeOf(context);
    final height = _pad * 2 + items.length * _row;
    final double left = position.dx.clamp(_pad, math.max(_pad, size.width - _width - _pad)).toDouble();
    final double top = position.dy.clamp(_pad, math.max(_pad, size.height - height - _pad)).toDouble();

    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          width: _width,
          child: FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: AppMotion.enter),
            child: AppGlass(
              grade: GlassGrade.float,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              padding: const EdgeInsets.all(_pad),
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, item) in items.indexed) _GlassMenuRow(item: item, autofocus: i == 0),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GlassMenuRow extends StatelessWidget {
  const _GlassMenuRow({required this.item, required this.autofocus});

  final _GlassMenuItem item;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = GlassInk.maybeOf(context)?.ink ?? scheme.onSurface;
    return InkWell(
      autofocus: autofocus,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      hoverColor: ink.withValues(alpha: 0.08),
      focusColor: ink.withValues(alpha: 0.08),
      splashColor: ink.withValues(alpha: 0.10),
      highlightColor: Colors.transparent,
      onTap: () {
        Navigator.of(context).pop();
        item.onSelected();
      },
      child: SizedBox(
        height: _GlassMenuRoute._row,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Icon(item.icon, size: AppSize.iconMd, color: ink),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall!.metricsOnly.copyWith(color: ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
