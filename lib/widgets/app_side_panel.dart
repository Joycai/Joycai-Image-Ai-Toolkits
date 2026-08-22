import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../core/responsive.dart';

/// Width a side panel takes on a window wide enough to slide one in.
const double appSidePanelWidth = 450;

/// A panel that arrives from the right edge on a wide window, and from the
/// bottom as a draggable sheet on a narrow one.
///
/// For content that is a *place* rather than a question — a prompt library, a
/// history list — where [AppDialog]'s centred box would either crop a long
/// list or float a tall column in the middle of the screen. A panel anchored
/// to an edge can be as tall as the window and leaves the work it belongs to
/// visible beside it.
///
/// Both presentations, and the surface itself, live here because the two
/// panels that existed before this had each copied the whole thing: the same
/// 46-line `isNarrow ? showModalBottomSheet : showGeneralDialog` branch, the
/// same slide curve, and the same 450px shadowed container, duplicated
/// verbatim. Anything that needs to change about how a panel arrives now has
/// one place to change it.
///
/// Assumes a left-to-right layout — the panel enters from the right and its
/// shadow falls left. Every locale this app ships is LTR; an RTL one would
/// need both mirrored.
class AppSidePanel extends StatelessWidget {
  final Widget child;

  /// Ignored on a narrow window, where the sheet always spans the width.
  final double width;

  const AppSidePanel({
    super.key,
    required this.child,
    this.width = appSidePanelWidth,
  });

  /// Presents [builder]'s content as a side panel, picking the presentation
  /// from the window width. Resolves with whatever the panel is popped with.
  static Future<T?> show<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    double width = appSidePanelWidth,
  }) {
    if (Responsive.isNarrow(context)) {
      return showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        // The panel paints its own surface and corner; a colour here would
        // sit behind them as a second, square one.
        backgroundColor: Colors.transparent,
        builder: (context) => DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, _) => AppSidePanel(width: width, child: builder(context)),
        ),
      );
    }

    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      // Material's own translated label, not the bare English "Dismiss" the
      // copies used — this is what a screen reader announces for the barrier.
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      transitionDuration: AppMotion.panel,
      pageBuilder: (context, _, _) => Align(
        alignment: Alignment.centerRight,
        child: AppSidePanel(width: width, child: builder(context)),
      ),
      transitionBuilder: (context, animation, _, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: animation, curve: AppMotion.enter)),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isNarrow = Responsive.isNarrow(context);
    final borderRadius =
        isNarrow ? const BorderRadius.vertical(top: Radius.circular(20)) : null;

    return Container(
      width: isNarrow ? double.infinity : width,
      height: double.infinity,
      // Shadow only. The fill belongs to the Material below, which also does
      // the clipping — a colour on both would be one painted over the other.
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: isNarrow
            ? null
            : [
                BoxShadow(
                  color: colorScheme.shadow.withValues(alpha: 0.2),
                  blurRadius: 20,
                  offset: const Offset(-5, 0),
                ),
              ],
      ),
      // Material, not a plain Container: these panels are lists of ListTiles
      // and InkWells, whose ink a Container swallows.
      child: Material(
        color: colorScheme.surface,
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}
