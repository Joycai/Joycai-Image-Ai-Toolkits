import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/design_tokens.dart';
import '../../../widgets/glass/glass_controls.dart';

/// Shared geometry and the small controls of the downloader column (`B3`).
///
/// Every bar on this screen is an opaque column strip inset 20 from the edge,
/// every input a 32px panel box at r10, and every secondary action a hairline
/// panel button carrying the deep ink — kept here so the toolbar, the options
/// bar, the results header, the log panel and the advanced dialog cannot
/// drift apart.

/// Horizontal inset of every strip on the column (`B3 · 1a`: pad 0/20).
const double kDownloaderGutter = 20;

/// Gap between the items on a toolbar row (`gap 12`).
const double kDownloaderGap = 12;

/// The 11px secondary caption over a field (`11 ink2 标签`).
TextStyle downloaderCaptionStyle(BuildContext context) {
  final theme = Theme.of(context);
  return theme.textTheme.labelSmall!.copyWith(color: theme.colorScheme.onSurfaceVariant);
}

/// The tracked group caption (`LOGS`): 11/500, `.06em`, deep ink.
TextStyle downloaderTrackedCaptionStyle(BuildContext context) {
  final theme = Theme.of(context);
  return theme.textTheme.labelSmall!.copyWith(
    letterSpacing: AppType.trackedLabelSpacing,
    color: theme.colorScheme.accentText,
  );
}

/// The height one line of [style] takes, at the ambient text scale.
double downloaderLineHeight(BuildContext context, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: 'Ag', style: style),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final height = painter.height;
  painter.dispose();
  return height;
}

/// A [height]-tall filled input box (`32 r10 hair panel`).
///
/// The vertical inset is derived from [style]'s measured line rather than
/// left at zero: a dense decorator sizes itself to its content, so a zero
/// inset drew a 16px border inside a 32px slot. [fill] defaults to the panel;
/// the dialog passes the column colour.
InputDecoration downloaderFieldDecoration(
  BuildContext context, {
  required TextStyle style,
  String? hint,
  IconData? icon,
  Color? fill,
  double height = AppSize.control,
  EdgeInsetsGeometry? contentPadding,
}) {
  final scheme = Theme.of(context).colorScheme;
  final vertical = math.max(0.0, (height - downloaderLineHeight(context, style)) / 2);
  return InputDecoration(
    hintText: hint,
    hintStyle: style.copyWith(color: scheme.outline),
    hintMaxLines: 1,
    isDense: true,
    filled: true,
    fillColor: fill ?? scheme.surface,
    contentPadding: contentPadding ??
        EdgeInsetsDirectional.fromSTEB(icon == null ? AppSpace.s10 : 0, vertical, AppSpace.s10, vertical),
    prefixIcon: icon == null ? null : Icon(icon, size: AppSize.iconMd, color: scheme.outline),
    prefixIconConstraints: const BoxConstraints(minWidth: AppSize.control, minHeight: 0),
  );
}

/// A secondary action on the downloader column.
///
/// [outlined] is the hairline panel button with a deep-ink label (`全选`,
/// `从剪贴板粘贴`, `导入 Cookie 文件`); off, it is the bare label (`清空`,
/// `Copy logs`). Disabled is outline ink with no ground at all — `B3`:
/// 「禁用 = ink3，不加底」. A glyph with no [label] is square and needs a
/// [tooltip].
class DownloaderActionButton extends StatelessWidget {
  const DownloaderActionButton({
    super.key,
    this.icon,
    this.label,
    this.tooltip,
    required this.onPressed,
    this.height = AppSize.control,
    this.outlined = true,
    this.selected = false,
    this.fill,
    this.foreground,
    this.iconSize = AppSize.iconMd,
  }) : assert(icon != null || label != null, 'give DownloaderActionButton an icon, a label or both');

  final IconData? icon;
  final String? label;
  final String? tooltip;
  final VoidCallback? onPressed;
  final double height;
  final bool outlined;

  /// The toggle's on state: the accent wash and ring instead of the panel.
  final bool selected;

  /// The ground under an [outlined] button; the panel by default.
  final Color? fill;

  /// The enabled ink; the deep accent ink by default.
  final Color? foreground;
  final double iconSize;

  static TextStyle labelStyle(BuildContext context) => Theme.of(context).textTheme.labelMedium!;

  /// The width this button takes with [label], for bars that measure first.
  static double widthFor(
    BuildContext context, {
    String? label,
    bool hasIcon = true,
    double height = AppSize.control,
    double iconSize = AppSize.iconMd,
  }) {
    if (label == null) return height;
    return (AppSpace.s10 +
            (hasIcon ? iconSize + AppSpace.s6 : 0) +
            measureGlassText(context, label, labelStyle(context)) +
            AppSpace.s10)
        .ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    final Color ink = enabled ? (foreground ?? scheme.accentText) : scheme.outline;
    final bool boxed = enabled && outlined;
    final radius = BorderRadius.circular(AppRadius.control);

    final Color ground = !boxed
        ? Colors.transparent
        : selected
            ? scheme.accentTint
            : (fill ?? scheme.surface);
    final BorderSide side = !boxed
        ? BorderSide.none
        : BorderSide(color: selected ? scheme.accentRing : scheme.outlineVariant);

    final Widget content = label == null
        ? SizedBox.square(
            dimension: height,
            child: Icon(icon, size: iconSize, color: ink),
          )
        : SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: iconSize, color: ink),
                    const SizedBox(width: AppSpace.s6),
                  ],
                  Flexible(
                    child: Text(
                      label!,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: labelStyle(context).copyWith(color: ink),
                    ),
                  ),
                ],
              ),
            ),
          );

    Widget button = Material(
      color: ground,
      shape: RoundedRectangleBorder(borderRadius: radius, side: side),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        hoverColor: ink.withValues(alpha: 0.08),
        splashColor: ink.withValues(alpha: 0.10),
        highlightColor: Colors.transparent,
        child: content,
      ),
    );
    if (tooltip != null) button = Tooltip(message: tooltip!, child: button);
    return Semantics(button: true, enabled: enabled, child: button);
  }
}
