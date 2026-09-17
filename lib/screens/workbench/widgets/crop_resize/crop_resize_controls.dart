part of '../crop_resize_toolbar.dart';

/// A number field with no chrome of its own — the value, in mono, in the
/// glass ink.
class _BareNumberField extends StatelessWidget {
  const _BareNumberField({required this.controller, this.textAlign = TextAlign.start});

  final TextEditingController controller;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = GlassInk.maybeOf(context)?.ink ?? scheme.onSurface;
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      textAlign: textAlign,
      maxLines: 1,
      cursorColor: scheme.primary,
      style: _valueStyle(context).copyWith(color: ink),
      decoration: const InputDecoration.collapsed(hintText: null),
    );
  }
}

/// `1a`: a 72×32 input on the glass edge at r10, the value in mono 12.
///
/// No visible label, as the design draws it: the pair reads as W × H beside
/// the link, and the name is carried by the tooltip and the semantics.
class _GlassNumberField extends StatelessWidget {
  const _GlassNumberField({required this.controller, required this.label, required this.width});

  final TextEditingController controller;
  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    final edge = GlassInk.maybeOf(context)?.edge ?? Theme.of(context).colorScheme.outlineVariant;
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        textField: true,
        child: Container(
          width: width,
          height: AppSize.control,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: edge),
          ),
          child: _BareNumberField(controller: controller),
        ),
      ),
    );
  }
}

/// `1b`'s dialog field: an 11px label over a 40px input on the column colour.
class _DialogNumberField extends StatelessWidget {
  const _DialogNumberField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: textTheme.labelSmall!.copyWith(fontWeight: FontWeight.w400, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 3),
        Container(
          height: AppSize.large,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            maxLines: 1,
            style: _valueStyle(context).copyWith(color: scheme.onSurface),
            decoration: const InputDecoration.collapsed(hintText: null),
          ),
        ),
      ],
    );
  }
}

/// A 32px ghost button that opens a menu: `1a`'s 「lanczos ▾」. With no
/// [label] it is the glyph and the chevron.
class _GlassMenuButton extends StatefulWidget {
  const _GlassMenuButton({
    required this.label,
    required this.icon,
    required this.tooltip,
    required this.open,
    required this.onPressed,
  });

  final String? label;
  final IconData icon;
  final String tooltip;
  final bool open;
  final VoidCallback? onPressed;

  static double widthFor(BuildContext context, String? label) => label == null
      ? 8 + AppSize.iconLg + 2 + AppSize.iconSm + 8
      : (10 + measureGlassText(context, label, GlassIconButton.labelStyle(context)) + 4 + AppSize.iconSm + 10)
          .ceilToDouble();

  @override
  State<_GlassMenuButton> createState() => _GlassMenuButtonState();
}

class _GlassMenuButtonState extends State<_GlassMenuButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glass = GlassInk.maybeOf(context);
    final ink = glass?.ink ?? scheme.onSurface;
    final ink2 = glass?.ink2 ?? scheme.onSurfaceVariant;
    final label = widget.label;

    final content = SizedBox(
      height: AppSize.control,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: label == null ? 8 : 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (label == null)
              Icon(widget.icon, size: AppSize.iconLg, color: ink)
            else
              Text(
                label,
                maxLines: 1,
                softWrap: false,
                style: GlassIconButton.labelStyle(context).copyWith(color: ink),
              ),
            SizedBox(width: label == null ? 2 : 4),
            Icon(Icons.expand_more, size: AppSize.iconSm, color: ink2),
          ],
        ),
      ),
    );

    final radius = BorderRadius.circular(AppRadius.control);
    final Widget box = widget.open
        ? AppGlass(
            grade: GlassGrade.lens,
            borderRadius: radius,
            reducedColor: scheme.accentTint,
            child: content,
          )
        : AnimatedContainer(
            duration: AppMotion.durationOf(context, AppMotion.hover),
            curve: AppMotion.quick,
            decoration: BoxDecoration(
              color: _hovering ? ink.withValues(alpha: 0.08) : Colors.transparent,
              borderRadius: radius,
            ),
            child: content,
          );

    return Semantics(
      button: true,
      label: widget.tooltip,
      child: Tooltip(
        message: widget.tooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: box,
          ),
        ),
      ),
    );
  }
}

/// The accent's solid form on the glass bar: tinted glass, 32 tall, r10.
///
/// With a [subtitle] it is `1a`'s two-line Save Copy — the 600 label over an
/// 11px destination at 85% opacity. While [loading], the label keeps its room
/// and a spinner stands over it, so the row does not reflow mid-save.
class _TintedButton extends StatelessWidget {
  const _TintedButton({
    required this.label,
    required this.onPressed,
    this.subtitle,
    this.icon,
    this.showLabel = true,
    this.tooltip,
    this.loading = false,
  });

  final String label;
  final String? subtitle;
  final IconData? icon;
  final bool showLabel;
  final String? tooltip;
  final bool loading;
  final VoidCallback? onPressed;

  static double widthFor(BuildContext context, {required String label, String? subtitle, bool icon = false}) {
    var text = measureGlassText(context, label, _saveLabelStyle(context));
    if (subtitle != null) {
      text = math.max(text, measureGlassText(context, subtitle, _saveSubtitleStyle(context)));
    }
    return (12 + (icon ? AppSize.iconMd + 6 : 0) + text + 12).ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // A save in flight keeps its fill: the spinner is the state, and a CTA
    // that greys out the moment it is pressed reads as having failed.
    final lit = onPressed != null || loading;

    final Widget text = subtitle == null
        ? Text(label, maxLines: 1, softWrap: false, style: _saveLabelStyle(context))
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, maxLines: 1, softWrap: false, style: _saveLabelStyle(context)),
              Opacity(
                opacity: 0.85,
                child: Text(subtitle!, maxLines: 1, softWrap: false, style: _saveSubtitleStyle(context)),
              ),
            ],
          );

    Widget content;
    if (!showLabel && icon != null) {
      content = SizedBox(
        width: AppSize.control - 24,
        child: Icon(icon, size: AppSize.iconMd),
      );
    } else {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: AppSize.iconMd),
            const SizedBox(width: 6),
          ],
          text,
        ],
      );
    }
    content = _Spinning(on: loading, color: scheme.onPrimary, child: content);

    Widget button = MouseRegion(
      cursor: onPressed != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onPressed,
        child: AppTintedGlass(
          enabled: lit,
          child: SizedBox(
            height: AppSize.control,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(widthFactor: 1, child: content),
            ),
          ),
        ),
      ),
    );
    if (tooltip != null) button = Tooltip(message: tooltip!, child: button);
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: tooltip ?? label,
      child: button,
    );
  }
}

/// [child] with a small spinner over it while [on], keeping its size.
class _Spinning extends StatelessWidget {
  const _Spinning({required this.on, required this.color, required this.child});

  final bool on;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!on) return child;
    return Stack(
      alignment: Alignment.center,
      children: [
        Opacity(opacity: 0, child: child),
        SizedBox(
          width: AppSize.iconSm,
          height: AppSize.iconSm,
          child: CircularProgressIndicator(strokeWidth: 2, color: color),
        ),
      ],
    );
  }
}
