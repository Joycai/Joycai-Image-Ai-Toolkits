import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import 'panel_resizer.dart';

/// A rounded content card for grouping related widgets inside a panel — a
/// settings block, a list row, a summary tile.
///
/// Not [PanelCard]: that one is the top-level surface a [PanelResizer] gutter
/// sits between, coloured `surface` against the canvas's `surfaceContainer`.
/// This card nests *inside* a panel, so it takes the next tone up
/// (`surfaceContainerHigh`) to still read as a distinct group against the
/// panel's own `surface` fill. Reaching for a decorated [Container] instead
/// is what left every card in the app a slightly different shade and radius.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// Group with a hairline outline instead of a step in fill.
  ///
  /// For cards on a panel that is already near the top of the ramp — the
  /// workbench's right column, a [PanelShape.column] at `surfaceContainerLow`.
  /// A tone *down* from there is a grey card on a white panel, which inverts
  /// the usual figure/ground: the group ends up looking recessed rather than
  /// raised. A hair lighter plus an edge reads as a group without that.
  ///
  /// This is what every call site passes, and `10c` draws these cards the same
  /// way: an edge doing the work and a fill barely distinguishable from the
  /// panel under it.
  final bool outlined;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.onTap,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Material, not a decorated Container: a plain Container swallows the ink
    // response of any ListTile/InkWell inside it — the same reason PanelCard
    // uses one.
    return Material(
      // `surfaceContainerLowest`, not `surface`. The spec fills these with 55%
      // white over the panel, which lands a hair *above* the panel's own tone;
      // white is the nearest step on the ramp. It was `surface` while the
      // right column was too, and the column moving up to
      // `surfaceContainerLow` left this a step darker than the thing it sits
      // on — a recessed card, which is the exact inversion [outlined] exists
      // to avoid.
      color: outlined ? colorScheme.surfaceContainerLowest : colorScheme.surfaceContainerHigh,
      clipBehavior: Clip.antiAlias,
      // shape, never borderRadius: Material asserts if given both, and the
      // outlined tone needs a side.
      shape: RoundedRectangleBorder(
        // 10, a step under a panel's 12. `10c` draws every card inside the
        // right column at this, which is what keeps a stack of them from
        // reading as rounder than the column holding them.
        borderRadius: BorderRadius.circular(AppRadius.md),
        // The panel-edge tone, not `outlineVariant`. Same reasoning as the
        // column hairlines: the spec draws an edge *between surfaces* softer
        // than one inside a control.
        side: outlined
            ? BorderSide(color: colorScheme.surfaceContainerHigh)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        // Spans its parent rather than hugging its content. A card in a
        // column is a band across that column; left to shrink-wrap, one whose
        // body happens to be a short line comes out a stub beside its
        // neighbours, and whether any given card looked right became an
        // accident of whether something inside it was full-width already.
        //
        // Requires a bounded width, which every column and list gives. An
        // AppCard directly inside a Row needs an Expanded around it, as any
        // full-width child there would.
        child: SizedBox(
          width: double.infinity,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
