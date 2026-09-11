import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../widgets/glass/app_glass.dart';

/// A float-grade glass menu opened at a pointer position — `B1b 1d`.
///
/// Its own route rather than [showMenu]: Material's popup route paints its
/// panel behind its own clip, where a backdrop filter cannot reach the page,
/// which is why the theme's popup menu is the opaque reduced form. This route
/// lays an [AppGlass] straight onto the overlay.
///
/// Rows are ordinary [PopupMenuItem]s, so tapping one pops the menu *before*
/// its `onTap` runs — the contract the tree's callbacks were written against —
/// and keyboard focus, hover and semantics come with them.
Future<void> showFolderGlassMenu({
  required BuildContext context,
  required Offset position,
  required List<Widget> entries,
  double width = 250,
}) {
  final navigator = Navigator.of(context);
  return navigator.push<void>(_FolderGlassMenuRoute(
    position: position,
    width: width,
    entries: entries,
    capturedThemes: InheritedTheme.capture(from: context, to: navigator.context),
    duration: AppMotion.durationOf(context, AppMotion.state),
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  ));
}

/// One 28px row of a glass menu: glyph, label, an optional mono shortcut and,
/// when the row is disabled, a second line saying why.
PopupMenuItem<void> folderGlassMenuItem({
  required IconData icon,
  required String label,
  required VoidCallback onTap,
  String? shortcut,
  bool danger = false,
  bool enabled = true,
  String? disabledNote,
}) {
  final showNote = !enabled && disabledNote != null;
  final height = showNote ? 42.0 : AppSize.compact;
  return PopupMenuItem<void>(
    height: height,
    padding: EdgeInsets.zero,
    enabled: enabled,
    onTap: onTap,
    child: _FolderGlassMenuRow(
      icon: icon,
      label: label,
      shortcut: shortcut,
      danger: danger,
      enabled: enabled,
      note: showNote ? disabledNote : null,
      height: height,
    ),
  );
}

/// The rule between two groups of a glass menu.
class FolderGlassMenuDivider extends StatelessWidget {
  const FolderGlassMenuDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final glass = GlassInk.maybeOf(context);
    // Glass ink at a hairline's weight: `--gedge` is a white refraction edge
    // and disappears against light glass, which is what a menu mostly sits on.
    final Color color = glass == null || glass.reduced
        ? (glass?.edge ?? Theme.of(context).colorScheme.outlineVariant)
        : glass.ink2.withValues(alpha: 0.2);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6, vertical: AppSpace.s4),
      child: SizedBox(height: 1, child: ColoredBox(color: color)),
    );
  }
}

class _FolderGlassMenuRow extends StatelessWidget {
  const _FolderGlassMenuRow({
    required this.icon,
    required this.label,
    required this.shortcut,
    required this.danger,
    required this.enabled,
    required this.note,
    required this.height,
  });

  final IconData icon;
  final String label;
  final String? shortcut;
  final bool danger;
  final bool enabled;
  final String? note;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final glass = GlassInk.maybeOf(context);
    final ink = glass?.ink ?? scheme.onSurface;
    final ink2 = glass?.ink2 ?? scheme.onSurfaceVariant;

    final Color glyph;
    final Color labelColor;
    if (!enabled) {
      glyph = scheme.outline;
      labelColor = scheme.outline;
    } else if (danger) {
      glyph = scheme.error;
      labelColor = scheme.error;
    } else {
      glyph = ink2;
      labelColor = ink;
    }

    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Icon(icon, size: AppSize.iconMd, color: glyph),
            const SizedBox(width: AppSpace.s10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: textTheme.bodyMedium!.copyWith(color: labelColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (note != null)
                    Text(
                      note!,
                      style: textTheme.labelSmall!.copyWith(color: scheme.outline),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (shortcut != null) ...[
              const SizedBox(width: AppSpace.s10),
              Text(shortcut!, style: textTheme.labelSmall!.mono.copyWith(color: ink2)),
            ],
          ],
        ),
      ),
    );
  }
}

class _FolderGlassMenuRoute extends PopupRoute<void> {
  _FolderGlassMenuRoute({
    required this.position,
    required this.width,
    required this.entries,
    required this.capturedThemes,
    required this.duration,
    required this.barrierLabel,
  });

  final Offset position;
  final double width;
  final List<Widget> entries;
  final CapturedThemes capturedThemes;
  final Duration duration;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => duration;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    final padding = MediaQuery.paddingOf(context);
    return capturedThemes.wrap(
      CustomSingleChildLayout(
        delegate: _MenuPositionDelegate(position: position, padding: padding),
        child: _FolderGlassMenu(width: width, entries: entries),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: AppMotion.enter, reverseCurve: AppMotion.quick),
      child: child,
    );
  }
}

class _FolderGlassMenu extends StatelessWidget {
  const _FolderGlassMenu({required this.width, required this.entries});

  final double width;
  final List<Widget> entries;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: AppGlass(
        grade: GlassGrade.float,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        // Transparent Material: the rows paint hover and focus ink on it.
        child: Material(
          type: MaterialType.transparency,
          child: FocusScope(
            autofocus: true,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpace.s6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final entry in entries)
                    entry is PopupMenuItem
                        ? ClipRRect(borderRadius: BorderRadius.circular(AppRadius.sm), child: entry)
                        : entry,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens down and right from the pointer, flipping to up or left where the
/// window runs out, and never closer than 8px to an edge.
class _MenuPositionDelegate extends SingleChildLayoutDelegate {
  _MenuPositionDelegate({required this.position, required this.padding});

  final Offset position;
  final EdgeInsets padding;

  static const double _margin = 8;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest).deflate(padding + const EdgeInsets.all(_margin));

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final double minX = padding.left + _margin;
    final double minY = padding.top + _margin;
    final double maxX = math.max(minX, size.width - padding.right - _margin - childSize.width);
    final double maxY = math.max(minY, size.height - padding.bottom - _margin - childSize.height);

    double x = position.dx;
    double y = position.dy;
    if (x > maxX) x = position.dx - childSize.width;
    if (y > maxY) y = position.dy - childSize.height;
    return Offset(x.clamp(minX, maxX), y.clamp(minY, maxY));
  }

  @override
  bool shouldRelayout(_MenuPositionDelegate oldDelegate) =>
      position != oldDelegate.position || padding != oldDelegate.padding;
}
