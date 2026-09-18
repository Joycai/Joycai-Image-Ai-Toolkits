import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../ui/dashed_border.dart';

/// What a route badge says about its route (`D1f` · AppRouteBadge). Only fill
/// and stroke carry it — no new colour.
enum RouteBadgeState {
  /// Solid accent: the channel's primary route, or the model's current one.
  current,

  /// Accent hairline: a route that is set up.
  configured,

  /// Dashed muted hairline: offered by the platform, not enabled.
  off,

  /// Plain hairline: a list of routes that states nothing (the add-channel
  /// preview).
  quiet,
}

/// The badge's geometry. The rail and tables use [small]; a model card's
/// tail [card]; the model editor's route strip [strip], and [touch] on a
/// phone.
enum RouteBadgeSize {
  small(18, 5, 10.5, 6),
  card(22, 6, 11, 8),
  strip(28, 8, 11.5, 10),
  touch(34, 8, 11.5, 12);

  const RouteBadgeSize(this.height, this.radius, this.fontSize, this.padding);

  final double height;
  final double radius;
  final double fontSize;
  final double padding;
}

/// A route's name in its state. Tappable when [onTap] is set — the model
/// editor's strip, where tapping a route switches to it.
class AppRouteBadge extends StatelessWidget {
  final String label;
  final RouteBadgeState state;
  final RouteBadgeSize size;

  /// Drawn after the label: `add` on a route that is not enabled yet.
  final IconData? trailingIcon;
  final VoidCallback? onTap;
  final String? tooltip;

  const AppRouteBadge({
    super.key,
    required this.label,
    required this.state,
    this.size = RouteBadgeSize.small,
    this.trailingIcon,
    this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color? fill, Color? stroke, Color ink) = switch (state) {
      RouteBadgeState.current => (scheme.primary, null, scheme.onPrimary),
      RouteBadgeState.configured => (null, scheme.primary, scheme.onAccentTint),
      RouteBadgeState.off => (null, null, scheme.outline),
      RouteBadgeState.quiet => (
        null,
        scheme.outlineVariant,
        scheme.onSurfaceVariant,
      ),
    };
    final radius = BorderRadius.circular(size.radius);
    final text = Text(
      label,
      maxLines: 1,
      softWrap: false,
      style: TextStyle(
        fontSize: size.fontSize,
        fontWeight: state == RouteBadgeState.current
            ? FontWeight.w600
            : FontWeight.w500,
        color: ink,
        height: 1,
      ).mono,
    );
    Widget body = Container(
      height: size.height,
      padding: EdgeInsets.symmetric(horizontal: size.padding),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: radius,
        border: stroke == null ? null : Border.all(color: stroke),
      ),
      alignment: Alignment.center,
      child: trailingIcon == null
          ? text
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                text,
                const SizedBox(width: AppSpace.s4),
                Icon(trailingIcon, size: size.fontSize + 2, color: ink),
              ],
            ),
    );
    if (state == RouteBadgeState.off) {
      body = DashedBorder(
        color: scheme.outline,
        radius: size.radius,
        child: body,
      );
    }
    if (onTap != null) {
      body = Material(
        type: MaterialType.transparency,
        child: InkWell(borderRadius: radius, onTap: onTap, child: body),
      );
    }
    if (tooltip != null) body = Tooltip(message: tooltip!, child: body);
    return Semantics(
      button: onTap != null,
      selected: state == RouteBadgeState.current,
      child: body,
    );
  }
}
