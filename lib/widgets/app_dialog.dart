import 'package:flutter/material.dart';

import '../core/responsive.dart';

/// Corner radius shared by every dialog.
///
/// The same 12 the inset panels use ([PanelCard], [AppCard],
/// [AppSegmentedControl]). Dialogs used to be hand-rolled at 24 and Material's
/// own default is 28, but one radius across the app was the call: a dialog is
/// another surface in the same system, not a visitor from another one.
const double appDialogRadius = 12;

/// The app's dialog chrome: rounded surface, title in [TextTheme.titleLarge],
/// right-aligned action row.
///
/// Every dialog used to hand-build this — its own padding, corner radius and
/// title style — so no two matched. This is the shared shell they build on.
///
/// Use [AppDialog.show] for the common title/content/actions shape. For a
/// dialog whose body owns its own layout, construct [AppDialog] directly
/// inside your own `showDialog`/`showGeneralDialog` call: the chrome still
/// applies and nothing about the shape is assumed.
///
/// Note on popping: [actions] are built with the *caller's* context, not a
/// builder-scoped one, so `Navigator.pop(context, value)` inside an action
/// resolves to the nearest enclosing [Navigator] and pops its topmost route —
/// this dialog. That holds because the app has a single navigator; introduce a
/// nested one and an action inside a bottom sheet would start closing the
/// sheet instead of the dialog.
///
/// Two things callers reach for that this deliberately does not provide:
///
/// * **A `builder`.** Dialogs with live internal state wrap their own
///   [StatefulBuilder] around [content]; it passes through untouched.
/// * **An `IntrinsicWidth` body.** [AlertDialog] sizes itself to its content,
///   which is why a scrollable inside one fails to lay out and why call sites
///   grew `SizedBox(width: …)` workarounds. The width here comes from
///   [maxWidth] instead, so a scrollable body is safe and those wrappers can
///   go.
class AppDialog extends StatelessWidget {
  /// Plain-text heading. Mutually exclusive with [titleWidget].
  final String? title;

  /// A second, quieter line under [title] — a count, a step, a file name.
  final String? subtitle;

  /// Leading glyph beside [title], tinted [iconColor] or the accent.
  final IconData? icon;
  final Color? iconColor;

  /// Escape hatch for a heading this shell cannot express. Mutually exclusive
  /// with [title]; prefer [title] + [subtitle] + [icon], which covers all but
  /// a couple of cases.
  final Widget? titleWidget;

  final Widget content;

  /// Trailing buttons, right-aligned with 8px between them.
  final List<Widget>? actions;

  /// Replaces the whole action row, for a footer that is not a right-aligned
  /// run of buttons — a wizard pairing step dots on the left with Back/Next on
  /// the right. Wins over [actions].
  final Widget? actionsOverride;

  /// Caps how wide the dialog grows; it still shrinks to fit smaller
  /// viewports.
  final double maxWidth;

  /// Caps how tall the dialog grows.
  ///
  /// Without this a tall body has nothing to push back against — a dialog
  /// shrink-wraps its content, so a long list grows until it runs off the
  /// screen, and an [Expanded] child inside it throws outright. Set this
  /// whenever the body can be arbitrarily long.
  final double? maxHeight;

  /// Wraps [content] in a scroll view. Pair with [maxHeight]: on its own a
  /// scrollable still has unbounded height and so never scrolls.
  final bool scrollable;

  /// Padding around [content] only, leaving the title and actions inset as
  /// usual. Set to [EdgeInsets.zero] for a body that reaches the dialog's
  /// edges — a full-bleed list, or content that carries its own padding.
  final EdgeInsetsGeometry? contentPadding;

  /// Clips the body to the rounded corners. Needed when a scrolling or
  /// ink-splashing child would otherwise paint over them.
  final Clip clipBehavior;

  const AppDialog({
    super.key,
    this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.titleWidget,
    required this.content,
    this.actions,
    this.actionsOverride,
    this.maxWidth = 560,
    this.maxHeight,
    this.scrollable = false,
    this.contentPadding,
    this.clipBehavior = Clip.none,
  }) : assert(title == null || titleWidget == null,
            'Give AppDialog a title or a titleWidget, not both');

  /// Shows an [AppDialog] and returns whatever the caller pops with
  /// `Navigator.pop(context, result)`.
  static Future<T?> show<T>(
    BuildContext context, {
    String? title,
    String? subtitle,
    IconData? icon,
    Color? iconColor,
    Widget? titleWidget,
    required Widget content,
    List<Widget>? actions,
    Widget? actionsOverride,
    double maxWidth = 560,
    double? maxHeight,
    bool scrollable = false,
    EdgeInsetsGeometry? contentPadding,
    Clip clipBehavior = Clip.none,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (_) => AppDialog(
        title: title,
        subtitle: subtitle,
        icon: icon,
        iconColor: iconColor,
        titleWidget: titleWidget,
        content: content,
        actions: actions,
        actionsOverride: actionsOverride,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        scrollable: scrollable,
        contentPadding: contentPadding,
        clipBehavior: clipBehavior,
      ),
    );
  }

  /// Inset from the dialog's edge to its content.
  static const double _pad = 20;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final heading = _buildHeading(context, colorScheme);
    final footer = _buildFooter();

    Widget body = scrollable ? SingleChildScrollView(child: content) : content;

    // Padding is applied per slot rather than once around the column, so a
    // body asking for EdgeInsets.zero can reach the dialog's edges — a
    // full-bleed list — while the title and actions above and below it stay
    // inset. The default absorbs the outer inset on whichever sides have no
    // neighbour to provide it.
    body = Padding(
      padding: contentPadding ??
          EdgeInsets.only(
            left: _pad,
            right: _pad,
            top: heading == null ? _pad : 0,
            bottom: footer == null ? _pad : 0,
          ),
      child: body,
    );

    return Dialog(
      // A tone above the canvas, same family PanelCard draws its surface
      // from, so a dialog reads as one more surface in the app rather than
      // Material's own stock white/near-black sheet.
      backgroundColor: colorScheme.surfaceContainer,
      clipBehavior: clipBehavior,
      // Material's 40px side inset costs a phone a fifth of its width; on a
      // 390pt screen a form dialog ends up 310pt wide with its fields
      // squeezed. Handled here rather than per call site, because every
      // dialog in the app has the same problem.
      insetPadding: EdgeInsets.symmetric(
        horizontal: Responsive.isMobile(context) ? 12 : 40,
        vertical: 24,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(appDialogRadius)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: maxHeight ?? double.infinity,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (heading != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(_pad, _pad, _pad, 16),
                child: heading,
              ),
            // The only slot allowed to take the height left over, so a
            // maxHeight bounds the scrolling body rather than cutting the
            // action row off the bottom of the dialog.
            Flexible(child: body),
            if (footer != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(_pad, _pad, _pad, _pad),
                child: footer,
              ),
          ],
        ),
      ),
    );
  }

  Widget? _buildHeading(BuildContext context, ColorScheme colorScheme) {
    if (titleWidget != null) return titleWidget;
    if (title == null) return null;

    final textTheme = Theme.of(context).textTheme;

    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title!, style: textTheme.titleLarge),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );

    if (icon == null) return text;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: iconColor ?? colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(child: text),
      ],
    );
  }

  Widget? _buildFooter() {
    if (actionsOverride != null) return actionsOverride;
    if (actions == null || actions!.isEmpty) return null;

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        for (var i = 0; i < actions!.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          actions![i],
        ],
      ],
    );
  }
}
