import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../core/file_utils.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/image_metadata_service.dart';
import '../../../services/web_scraper_service.dart';
import '../../../widgets/app_snackbar.dart';
import '../../../widgets/glass/app_glass_menu.dart';

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
    showAppGlassMenu(
      context,
      position: position,
      width: 200,
      entries: [
        AppGlassMenuItem(
          icon: Icons.open_in_new,
          label: l10n.openRawImage,
          onSelected: () {
            final uri = Uri.tryParse(url);
            if (uri != null) FileUtils.openUri(uri);
          },
        ),
        AppGlassMenuItem(
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
