import 'package:flutter/material.dart';

import '../../../core/design_tokens.dart';
import '../../../core/responsive.dart';
import '../../../widgets/app_section_label.dart';

/// The rhythm of a settings page — `E1` 「尺寸」: 32 between sections on a
/// desktop (the last followed by 24), 24 on a tablet, 18 on a phone.
class SettingsSections extends StatelessWidget {
  const SettingsSections({super.key, required this.children});

  final List<Widget> children;

  static double gapOf(BuildContext context) =>
      Responsive.value(context, mobile: 18.0, tablet: 24.0, desktop: 32.0);

  @override
  Widget build(BuildContext context) {
    final double gap = gapOf(context);
    return Padding(
      padding: EdgeInsets.only(bottom: Responsive.isDesktop(context) ? 24 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (int i, Widget child) in children.indexed) ...[
            if (i > 0) SizedBox(height: gap),
            child,
          ],
        ],
      ),
    );
  }
}

/// A captioned block: the tracked deep-accent caption, then its content.
class SettingsBlock extends StatelessWidget {
  const SettingsBlock({super.key, this.caption, required this.child, this.gap});

  final String? caption;
  final Widget child;

  /// Space between blocks' own children when [child] is a column built by
  /// the caller. Only the caption gap is this widget's.
  final double? gap;

  @override
  Widget build(BuildContext context) {
    if (caption == null) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionLabel(caption!, padding: EdgeInsets.zero),
        SizedBox(height: gap ?? (Responsive.isMobile(context) ? 8 : AppSpace.s10)),
        child,
      ],
    );
  }
}

/// The grouping box `E1 · 1c / 1d` draws: the column colour at r10 with a
/// hairline. Either a list of rows ruled by inset hairlines ([ruled]) or a
/// padded stack of a toggle and the fields under it.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.children,
    this.ruled = true,
    this.gap = AppSpace.s10,
  });

  final List<Widget> children;

  /// Rows separated by hairlines inset 12 (`1c` 「通知与日志」). False: a 12px
  /// padded stack with [gap] between children (`1c` 「连接」).
  final bool ruled;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: ruled ? const EdgeInsets.symmetric(vertical: 2) : const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (int i, Widget child) in children.indexed) ...[
              if (i > 0)
                ruled
                    ? const Divider(height: 1, indent: 12, endIndent: 12)
                    : SizedBox(height: gap),
              child,
            ],
          ],
        ),
      ),
    );
  }
}

/// A caption above a field — `1c`: 11px secondary ink, 4 below — and the
/// field skin inside a column-coloured group: the panel colour, 32 tall.
///
/// [enabled] false is `1c`'s rule for a field whose switch is off: it stays
/// exactly where it is, filled with the track colour, its caption and text in
/// the muted ink, and takes no input or focus.
class SettingsField extends StatelessWidget {
  const SettingsField({
    super.key,
    required this.label,
    required this.child,
    this.enabled = true,
  });

  final String label;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final Color ink = enabled ? colorScheme.onSurface : colorScheme.outline;

    OutlineInputBorder hair() => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        );

    Widget field = Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.copyWith(
          bodyMedium: theme.textTheme.bodyMedium?.copyWith(color: ink),
        ),
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          filled: true,
          fillColor: enabled ? colorScheme.surface : colorScheme.surfaceContainerHighest,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          enabledBorder: hair(),
          disabledBorder: hair(),
          hintStyle: TextStyle(color: colorScheme.outline),
          suffixIconConstraints: const BoxConstraints(
            minWidth: AppSize.control,
            minHeight: 0,
            maxHeight: AppSize.control,
          ),
        ),
        iconTheme: theme.iconTheme.copyWith(
          color: enabled ? colorScheme.onSurfaceVariant : colorScheme.outline,
        ),
      ),
      child: child,
    );
    if (!enabled) {
      field = ExcludeFocus(child: IgnorePointer(child: field));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w400,
            color: enabled ? colorScheme.onSurfaceVariant : colorScheme.outline,
          ),
        ),
        const SizedBox(height: 4),
        field,
      ],
    );
  }
}
