import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/thumbnail_fit.dart';
import '../l10n/app_localizations.dart';
import '../state/app_state.dart';

/// The name a [ThumbnailFit] goes by in the UI.
String thumbnailFitLabel(AppLocalizations l10n, ThumbnailFit fit) =>
    switch (fit) {
      ThumbnailFit.fit => l10n.thumbnailFitContain,
      ThumbnailFit.fill => l10n.thumbnailFitCover,
    };

/// The glyph that stands for a [ThumbnailFit] — the picture boxed whole, or
/// the same picture cropped to the box.
IconData thumbnailFitIcon(ThumbnailFit fit) => switch (fit) {
      ThumbnailFit.fit => Icons.fit_screen_outlined,
      ThumbnailFit.fill => Icons.crop_outlined,
    };

/// Picks how thumbnails fill their tile, for the bar of whichever grid it is
/// dropped into.
///
/// A menu rather than a press-to-flip icon, even though there are only two
/// options: a toggle can show the state it is *in* or the state it would go
/// to, never both, and a display preference nobody touches twice a month is
/// exactly where that ambiguity costs a wrong click. The menu names both and
/// checks the live one.
///
/// One widget rather than a copy per bar because the setting is one setting —
/// see [ThumbnailFit].
class ThumbnailFitToggle extends StatelessWidget {
  const ThumbnailFitToggle({
    super.key,
    this.iconSize = 18,
    this.size = kMinInteractiveDimension,
  });

  final double iconSize;

  /// Both sides of the button's box.
  ///
  /// Boxed explicitly because [PopupMenuButton] hands its [IconButton] no
  /// constraints, so the button claims Material's 48px tap target — right on a
  /// toolbar, three times the height of a section-label row anywhere else. A
  /// tight box overrides that minimum, so only shrink it where the row height
  /// is what matters.
  final double size;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // `select`, not `watch`: AppState notifies for every model, setting and
    // prompt it owns, and this button cares about one enum.
    final fit = context.select<AppState, ThumbnailFit>((s) => s.thumbnailFit);

    return SizedBox(
      width: size,
      height: size,
      child: PopupMenuButton<ThumbnailFit>(
        icon: Icon(thumbnailFitIcon(fit), size: iconSize),
        iconSize: iconSize,
        padding: EdgeInsets.zero,
        tooltip: '${l10n.thumbnailDisplay}: ${thumbnailFitLabel(l10n, fit)}',
        onSelected: (value) => context.read<AppState>().setThumbnailFit(value),
        itemBuilder: (context) => [
          for (final option in ThumbnailFit.values)
            CheckedPopupMenuItem(
              value: option,
              checked: option == fit,
              child: Text(
                thumbnailFitLabel(l10n, option),
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
        ],
      ),
    );
  }
}
