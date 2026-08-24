import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../core/responsive.dart';
import '../l10n/app_localizations.dart';

/// Corner radius shared by every dialog.
///
/// Dialogs used to be hand-rolled at 24 and Material's own default is 28; this
/// sat at the cards' 12 for a while on the argument that a dialog is another
/// surface in the same system. The design spec puts it one step above the
/// cards instead, which is the better reading of the same idea: a dialog is in
/// the system but *floating over* it, and one step of extra curvature is what
/// says so without breaking the family.
const double appDialogRadius = AppRadius.dialog;

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

  /// Adds an ✕ in the heading's trailing corner, calling this.
  ///
  /// Opt-in rather than automatic. The spec draws one on every dialog, but
  /// most of this app's dialogs already carry a Cancel in the footer and are
  /// barrier-dismissible besides — a third way out is clutter, not clarity.
  /// Reach for it on dialogs with no footer, or whose footer commits to
  /// something and has nothing to dismiss with.
  final VoidCallback? onClose;

  /// Hairline rules separating the heading and the footer from the body.
  ///
  /// On by default: they are what let the body run edge-to-edge under a
  /// heading without the two appearing to merge, which is the shape the spec
  /// draws and the shape a scrolling body needs anyway. Only drawn on the
  /// sides that actually have a neighbour.
  final bool divided;

  /// Per-side overrides of [divided], null meaning "follow it".
  ///
  /// The spec itself splits the two: the model editor's narrow layout
  /// separates its heading from the form by spacing alone while still ruling
  /// off the footer, and the wide layout rules both. One flag couldn't say
  /// that.
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

  /// Inset from the dialog's edge to its content.
  static const double _pad = 20;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final heading = _buildHeading(context, colorScheme);
    final footer = _buildFooter();
    final bool ruleAboveBody = dividedHeading ?? divided;
    final bool ruleBelowBody = dividedFooter ?? divided;

    Widget body = scrollable ? SingleChildScrollView(child: content) : content;

    // Padding is applied per slot rather than once around the column, so a
    // body asking for EdgeInsets.zero can reach the dialog's edges — a
    // full-bleed list — while the title and actions above and below it stay
    // inset. The default absorbs the outer inset on whichever sides have no
    // neighbour to provide it.
    // Without a rule between them, the heading's own bottom inset is the gap
    // and the body adds none. With one, that inset now sits *above* the rule,
    // so the body has to supply the space beneath it or the first line of
    // content ends up flush against the hairline. Same on the footer side.
    body = Padding(
      padding: contentPadding ??
          EdgeInsets.only(
            left: _pad,
            right: _pad,
            top: (heading == null || ruleAboveBody) ? _pad : 0,
            bottom: (footer == null || ruleBelowBody) ? _pad : 0,
          ),
      child: body,
    );

    return _Materialize(child: Dialog(
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
            if (heading != null) ...[
              Padding(
                padding: EdgeInsets.fromLTRB(_pad, _pad, _pad, ruleAboveBody ? _pad : 16),
                child: heading,
              ),
              if (ruleAboveBody) const Divider(height: 1),
            ],
            // The only slot allowed to take the height left over, so a
            // maxHeight bounds the scrolling body rather than cutting the
            // action row off the bottom of the dialog.
            Flexible(child: body),
            if (footer != null) ...[
              if (ruleBelowBody) const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(_pad, _pad, _pad, _pad),
                child: footer,
              ),
            ],
          ],
        ),
      ),
    ));
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

    if (icon == null && onClose == null) return text;

    final accent = iconColor ?? colorScheme.primary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (icon != null) ...[
          // A plate, not a bare glyph. The spec gives the heading icon a
          // tinted square so it reads as the dialog's subject rather than as
          // decoration beside the title — and because `iconColor` already
          // carries the dialog's mood, a destructive dialog passing
          // `iconColor: error` gets the spec's red plate with no extra API.
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: AppAlpha.tint),
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Icon(icon, size: 22, color: accent),
          ),
          const SizedBox(width: 14),
        ],
        Expanded(child: text),
        if (onClose != null) ...[
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.close, size: AppSize.iconSm),
            tooltip: AppLocalizations.of(context)!.close,
            onPressed: onClose,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(
              width: AppSize.iconButton,
              height: AppSize.iconButton,
            ),
            style: IconButton.styleFrom(
              foregroundColor: colorScheme.onSurfaceVariant,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.control),
                side: BorderSide(color: colorScheme.outlineVariant),
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
          if (i > 0) const SizedBox(width: 8),
          actions![i],
        ],
      ],
    );
  }
}

/// Grows a dialog into place instead of fading a full-size one in.
///
/// `showDialog`'s own transition is opacity alone, which is why a dialog here
/// arrived as a rectangle that was simply *there*, at final size, getting less
/// see-through. A surface that scales as it fades reads as a thing arriving —
/// the same reason a glass panel animates its blur and its size together
/// rather than only its alpha.
///
/// Deliberately small. 0.96 is a couple of pixels on a 560px dialog: enough
/// for the eye to register a direction of travel, not enough to be a bounce.
/// A dialog is an interruption, and an interruption that makes an entrance is
/// worse than one that does not.
///
/// The scale rides the route's own animation rather than a controller of its
/// own, so it is already reversed on the way out — the exit mirrors the
/// entrance for free, and a dialog dismissed mid-entrance shrinks from
/// wherever it had got to instead of snapping to full size first.
///
/// Drops to a plain fade under reduce-motion, and to nothing at all outside a
/// route, which is how [AppDialog] renders in widget tests.
class _Materialize extends StatelessWidget {
  const _Materialize({required this.child});

  final Widget child;

  /// Where the dialog starts, as a fraction of its final size.
  static const double _from = 0.96;

  @override
  Widget build(BuildContext context) {
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || AppMotion.prefersReduced(context)) return child;

    return ScaleTransition(
      scale: Tween<double>(begin: _from, end: 1).animate(
        CurvedAnimation(parent: animation, curve: AppMotion.enter),
      ),
      child: child,
    );
  }
}
