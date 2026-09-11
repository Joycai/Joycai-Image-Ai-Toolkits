import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../core/responsive.dart';
import '../l10n/app_localizations.dart';

/// Corner radius shared by every dialog (`01 · 1h`: r22).
///
/// Concentric with what it holds: a 16px card inside a dialog's 6px inset
/// lands on 22.
const double appDialogRadius = AppRadius.dialog;

/// The app's dialog shell (`01 · 1h`).
///
/// An **opaque panel** at r22 — dialogs are content, not controls, so they are
/// never glass — with a 44px icon plate beside a 16/600 title and a 12px
/// subtitle, a body, and a footer band on the column colour ruled off by a
/// hairline. Cancel is the deep-ink text button; a destructive confirm is the
/// solid error fill.
///
/// Use [AppDialog.show] for the common shape. For a dialog whose body owns its
/// own layout, construct [AppDialog] inside your own `showDialog` call.
///
/// Popping: [actions] are built with the caller's context, so
/// `Navigator.pop(context, value)` inside one pops this dialog — the app has a
/// single navigator.
///
/// Width comes from [maxWidth], not from the content, so a scrollable body is
/// safe without a `SizedBox(width: …)` wrapper.
class AppDialog extends StatelessWidget {
  /// Plain-text heading. Mutually exclusive with [titleWidget].
  final String? title;

  /// A second, quieter line under [title] — a count, a step, a file name.
  final String? subtitle;

  /// Leading glyph on a 44px plate beside [title], in [iconColor] or the
  /// accent.
  final IconData? icon;
  final Color? iconColor;

  /// Escape hatch for a heading this shell cannot express.
  final Widget? titleWidget;

  final Widget content;

  /// Trailing buttons, right-aligned with 6px between them.
  final List<Widget>? actions;

  /// Replaces the whole footer row. Wins over [actions].
  final Widget? actionsOverride;

  /// Caps how wide the dialog grows; it still shrinks to fit.
  final double maxWidth;

  /// Caps how tall the dialog grows. Set it whenever the body can be long.
  final double? maxHeight;

  /// Wraps [content] in a scroll view. Pair with [maxHeight].
  final bool scrollable;

  /// Padding around [content] only. [EdgeInsets.zero] for a full-bleed body.
  final EdgeInsetsGeometry? contentPadding;

  /// Clips the body to the rounded corners. The shell always clips the panel
  /// itself; this is kept for callers that pass it.
  final Clip clipBehavior;

  /// Adds an ✕ in the heading's trailing corner, calling this. Opt-in: most
  /// dialogs already have Cancel and are barrier-dismissible.
  final VoidCallback? onClose;

  /// Hairline rules between the heading, body and footer.
  ///
  /// The footer rule follows this. The heading rule is drawn only for a
  /// [scrollable] body by default — `1h` separates a heading from a short
  /// body by space alone, and a rule earns its place only where the body can
  /// scroll under it.
  final bool divided;

  /// Per-side overrides of [divided], null meaning "follow the default".
  final bool? dividedHeading;
  final bool? dividedFooter;

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
    this.onClose,
    this.divided = true,
    this.dividedHeading,
    this.dividedFooter,
  }) : assert(title == null || titleWidget == null,
            'Give AppDialog a title or a titleWidget, not both');

  /// Shows an [AppDialog] and returns whatever the caller pops with.
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
    VoidCallback? onClose,
    bool divided = true,
    bool? dividedHeading,
    bool? dividedFooter,
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
        onClose: onClose,
        divided: divided,
        dividedHeading: dividedHeading,
        dividedFooter: dividedFooter,
      ),
    );
  }

  /// Inset from the dialog's edge to its content (`1h`: 22).
  static const double _pad = AppSpace.s22;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final heading = _buildHeading(context, scheme);
    final footer = _buildFooter();
    final bool ruleAboveBody = dividedHeading ?? (divided && scrollable);
    final bool ruleBelowBody = dividedFooter ?? divided;

    Widget body = scrollable ? SingleChildScrollView(child: content) : content;

    body = Padding(
      padding: contentPadding ??
          EdgeInsets.only(
            left: _pad,
            right: _pad,
            top: heading == null ? _pad : (ruleAboveBody ? 16 : AppSpace.s10),
            bottom: (footer == null || ruleBelowBody) ? _pad : 0,
          ),
      child: body,
    );

    final radius = BorderRadius.circular(appDialogRadius);

    return _Materialize(
      child: Dialog(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        insetPadding: EdgeInsets.symmetric(
          horizontal: Responsive.isMobile(context) ? 12 : 40,
          vertical: 24,
        ),
        shape: RoundedRectangleBorder(borderRadius: radius),
        child: DecoratedBox(
          decoration: BoxDecoration(borderRadius: radius, boxShadow: scheme.shadowPanel),
          child: ClipRRect(
            borderRadius: radius,
            clipBehavior: clipBehavior == Clip.none ? Clip.antiAlias : clipBehavior,
            // A Material, not a ColoredBox: a ListTile in a dialog body paints
            // its selection and ink on the nearest Material, and a coloured box
            // in between would hide both.
            child: Material(
              color: scheme.surface,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: maxWidth,
                  maxHeight: maxHeight ?? double.infinity,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (heading != null) ...[
                      Padding(
                        padding: EdgeInsets.fromLTRB(_pad, _pad, _pad, ruleAboveBody ? 16 : AppSpace.s6),
                        child: heading,
                      ),
                      if (ruleAboveBody) const Divider(height: 1),
                    ],
                    // The only slot allowed the height left over, so a
                    // maxHeight bounds the body rather than cutting the footer.
                    Flexible(child: body),
                    if (footer != null) ...[
                      if (ruleBelowBody) const Divider(height: 1),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: ruleBelowBody ? scheme.surfaceContainerLow : null,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(_pad, 12, _pad, 12),
                          child: footer,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget? _buildHeading(BuildContext context, ColorScheme scheme) {
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
            style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );

    if (icon == null && onClose == null) return text;

    final accent = iconColor ?? scheme.primary;
    // The error plate is the opaque `--err-bg`, as `1h` draws it; any other
    // mood is its colour's 12% wash.
    final plate = accent == scheme.error ? scheme.errorContainer : accent.withValues(alpha: AppAlpha.tint);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: plate,
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: Icon(icon, size: 24, color: accent),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: icon != null ? 2 : 0),
            child: text,
          ),
        ),
        if (onClose != null) ...[
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.close, size: AppSize.iconMd),
            tooltip: AppLocalizations.of(context)!.close,
            onPressed: onClose,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(
              width: AppSize.iconButton,
              height: AppSize.iconButton,
            ),
            style: IconButton.styleFrom(
              foregroundColor: scheme.onSurfaceVariant,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.control),
                side: BorderSide(color: scheme.outlineVariant),
              ),
            ),
          ),
        ],
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
          if (i > 0) const SizedBox(width: AppSpace.s6),
          actions![i],
        ],
      ],
    );
  }
}

/// Grows a dialog into place from 0.96 on the route's own animation (M3,
/// `00 · 1e`), so the exit mirrors the entrance for free. A plain fade under
/// reduce-motion; nothing outside a route, which is how widget tests render it.
class _Materialize extends StatelessWidget {
  const _Materialize({required this.child});

  final Widget child;

  static const double _from = 0.96;

  @override
  Widget build(BuildContext context) {
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || AppMotion.prefersReduced(context)) return child;

    return ScaleTransition(
      scale: Tween<double>(begin: _from, end: 1).animate(
        CurvedAnimation(parent: animation, curve: AppMotion.emphasized),
      ),
      child: child,
    );
  }
}
