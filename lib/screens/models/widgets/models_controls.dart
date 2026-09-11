import 'package:flutter/material.dart';

import '../../../core/design_tokens.dart';
import '../../../widgets/glass/glass_controls.dart';

/// The two button treatments `D1a` uses in its column headers and filter
/// row: the solid accent (Add Channel, Add Model) and the neutral hairline
/// box on the panel (Fetch Models, Edit), both 32 tall at r10.
enum ModelsButtonTone { primary, neutral }

/// A 32px header button that knows its own width, so a header can decide by
/// measurement whether it still fits with its label (`D1a · 1c`: Fetch
/// Models and Edit go icon-only, Add Channel collapses to a 32 plate).
///
/// Not `AppButton`: that one takes its padding from the theme and cannot
/// report a width before layout, which is exactly what a measured header
/// needs to ask.
class ModelsActionButton extends StatelessWidget {
  const ModelsActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tone = ModelsButtonTone.neutral,
    this.showLabel = true,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final ModelsButtonTone tone;
  final bool showLabel;

  /// Shown on hover. Defaults to [label] when the label is hidden; a labelled
  /// button shows no tooltip unless one is given.
  final String? tooltip;

  static const double _padStart = AppSpace.s10;
  static const double _padEnd = 12;
  static const double _gap = AppSpace.s6;

  static TextStyle labelStyle(BuildContext context) =>
      Theme.of(context).textTheme.labelLarge!.copyWith(fontWeight: FontWeight.w500);

  /// The width this button takes with its label shown, or the 32 square.
  static double widthFor(BuildContext context, String label, {bool showLabel = true}) {
    if (!showLabel) return AppSize.control;
    return (_padStart + AppSize.iconMd + _gap + measureGlassText(context, label, labelStyle(context)) + _padEnd)
        .ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final primary = tone == ModelsButtonTone.primary;
    final enabled = onPressed != null;

    final Color background = !enabled && primary
        ? scheme.surfaceContainerHighest
        : (primary ? scheme.primary : scheme.surface);
    final Color labelColor = !enabled
        ? scheme.onSurface.withValues(alpha: AppAlpha.disabled)
        : (primary ? scheme.onPrimary : scheme.onSurface);
    final Color iconColor = !enabled || primary ? labelColor : scheme.onSurfaceVariant;
    final radius = BorderRadius.circular(AppRadius.control);

    final Widget content = showLabel
        ? Padding(
            padding: const EdgeInsets.only(left: _padStart, right: _padEnd),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: AppSize.iconMd, color: iconColor),
                const SizedBox(width: _gap),
                Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  style: labelStyle(context).copyWith(color: labelColor),
                ),
              ],
            ),
          )
        : Center(child: Icon(icon, size: AppSize.iconMd, color: iconColor));

    Widget button = Material(
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: primary ? BorderSide.none : BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          height: AppSize.control,
          width: showLabel ? null : AppSize.control,
          child: content,
        ),
      ),
    );

    final String? message = tooltip ?? (showLabel ? null : label);
    if (message != null) button = Tooltip(message: message, child: button);
    return Semantics(button: true, enabled: enabled, label: label, child: button);
  }
}

/// A 28px icon action inside a card or a row (`D1a` 「28 edit ink2 · 28 delete
/// err」).
class ModelsRowIconButton extends StatelessWidget {
  const ModelsRowIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return IconButton(
      icon: Icon(icon, size: AppSize.iconMd),
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: AppSize.compact, height: AppSize.compact),
      style: IconButton.styleFrom(
        minimumSize: const Size.square(AppSize.compact),
        foregroundColor: danger ? scheme.error : scheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      ),
    );
  }
}

/// Gives the fields below it the panel fill `D1a` draws inputs with (「卡片 /
/// 输入 = panel」) and prefix/suffix boxes that fit a 32px field.
class ModelsPanelFields extends StatelessWidget {
  const ModelsPanelFields({super.key, required this.child, this.fill});

  final Widget child;

  /// Overrides the panel fill — the discovery dialog's search sits on the
  /// column colour.
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          filled: true,
          fillColor: fill ?? theme.colorScheme.surface,
          prefixIconConstraints: const BoxConstraints(minWidth: AppSize.control, minHeight: AppSize.control),
          suffixIconConstraints: const BoxConstraints(minWidth: AppSize.control, minHeight: AppSize.control),
        ),
      ),
      child: child,
    );
  }
}

/// `D1a · 1e`: an empty state inside a column — a 28px glyph in the weak ink,
/// one line, an optional sentence and up to two actions. Unboxed: the column
/// is already the box.
class ModelsEmptyState extends StatelessWidget {
  const ModelsEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.actions = const [],
  });

  final IconData icon;
  final String title;
  final String? description;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.s22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: AppSpace.s28, color: scheme.outline),
            const SizedBox(height: AppSpace.s10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: textTheme.titleMedium?.copyWith(color: scheme.onSurface),
            ),
            if (description != null) ...[
              const SizedBox(height: AppSpace.s4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: Text(
                  description!,
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: AppType.proseHeight,
                  ),
                ),
              ),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: AppSpace.s16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: actions,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
