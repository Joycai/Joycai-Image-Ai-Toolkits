import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import 'model_edit_metrics.dart';

/// The stroke a [ModelEditMenuField] wears.
enum ModelEditFieldEmphasis { normal, accent, error }

/// One row of a [ModelEditMenuField]'s menu.
@immutable
class ModelEditMenuEntry<T> {
  const ModelEditMenuEntry({
    required this.value,
    required this.label,
    this.description,
    this.trailing,
    this.leading,
  });

  final T value;
  final String label;
  final String? description;

  /// Mono, at the row's end — an endpoint path.
  final String? trailing;
  final Widget? leading;
}

/// A select-shaped box whose closed face is arbitrary content, opening a
/// menu of [entries] — or calling [onTap] instead (the phone's bottom sheet).
///
/// Exists because the request method's closed field is two type styles in
/// one line (「Auto」 at 500, the resolution in mono) and a kind needs its
/// dot, neither of which a `DropdownButton`'s selected item can carry.
class ModelEditMenuField<T> extends StatefulWidget {
  const ModelEditMenuField({
    super.key,
    required this.child,
    this.entries = const [],
    this.selected,
    this.onSelected,
    this.onTap,
    this.leading,
    this.emphasis = ModelEditFieldEmphasis.normal,
    this.autoHeight = false,
  });

  final Widget child;
  final List<ModelEditMenuEntry<T>> entries;
  final T? selected;
  final ValueChanged<T>? onSelected;

  /// Replaces the menu.
  final VoidCallback? onTap;
  final Widget? leading;
  final ModelEditFieldEmphasis emphasis;

  /// Grows past the field height for a two-line face (`1e`).
  final bool autoHeight;

  @override
  State<ModelEditMenuField<T>> createState() => _ModelEditMenuFieldState<T>();
}

class _ModelEditMenuFieldState<T> extends State<ModelEditMenuField<T>> {
  final MenuController _controller = MenuController();

  /// The narrowest a menu gets, so an entry's description still wraps to two
  /// lines at most beside a narrow field.
  static const double _minMenuWidth = 260;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final metrics = ModelEditMetrics.of(context);
    final radius = BorderRadius.circular(AppRadius.control);
    final stroke = switch (widget.emphasis) {
      ModelEditFieldEmphasis.normal => scheme.outlineVariant,
      ModelEditFieldEmphasis.accent => scheme.primary,
      ModelEditFieldEmphasis.error => scheme.error,
    };

    Widget face(VoidCallback? onTap) => Material(
      color: metrics.fill(scheme),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: stroke),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          // The stroke is the shape's side, painted inside the box rather
          // than added to it, so the face takes the whole field height.
          // Taking 2 off for it left the menu 30 beside 32px fields.
          constraints: widget.autoHeight
              ? BoxConstraints(minHeight: metrics.fieldHeight)
              : BoxConstraints.tightFor(height: metrics.fieldHeight),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: metrics.phone ? 12 : AppSpace.s10,
              vertical: widget.autoHeight ? AppSpace.s10 : 0,
            ),
            child: Row(
              children: [
                if (widget.leading != null) ...[widget.leading!, const SizedBox(width: 8)],
                Expanded(child: widget.child),
                const SizedBox(width: AppSpace.s6),
                Icon(Icons.expand_more, size: AppSize.iconMd, color: scheme.outline),
              ],
            ),
          ),
        ),
      ),
    );

    if (widget.onTap != null) return face(widget.onTap);

    return LayoutBuilder(
      builder: (context, constraints) {
        // The menu's padding (6) and each row's (10) come out of the field's
        // width, so the open menu lines up with the box it dropped from.
        final rowWidth =
            (constraints.maxWidth < _minMenuWidth ? _minMenuWidth : constraints.maxWidth) -
            2 * AppSpace.s6 -
            2 * AppSpace.s10;

        return MenuAnchor(
          controller: _controller,
          alignmentOffset: const Offset(0, AppSpace.s4),
          menuChildren: [
            for (final entry in widget.entries)
              MenuItemButton(
                onPressed: () => widget.onSelected?.call(entry.value),
                style: MenuItemButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.s10,
                    vertical: AppSpace.s6,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                  backgroundColor: entry.value == widget.selected ? scheme.accentTint : null,
                ),
                child: SizedBox(
                  width: rowWidth,
                  child: Row(
                    children: [
                      if (entry.leading != null) ...[entry.leading!, const SizedBox(width: 8)],
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                                color: entry.value == widget.selected
                                    ? scheme.onAccentTint
                                    : scheme.onSurface,
                              ),
                            ),
                            if (entry.description != null)
                              Text(
                                entry.description!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w400,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (entry.trailing != null) ...[
                        const SizedBox(width: 12),
                        Text(
                          entry.trailing!,
                          style: textTheme.labelSmall?.mono.copyWith(color: scheme.outline),
                        ),
                      ],
                      // `D2a`: the current value carries a check beside its wash.
                      // The slot is kept on every row so the labels do not shift
                      // when the selection moves.
                      const SizedBox(width: AppSpace.s6),
                      SizedBox.square(
                        dimension: AppSize.iconSm,
                        child: entry.value == widget.selected
                            ? Icon(Icons.check, size: AppSize.iconSm, color: scheme.onAccentTint)
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
          ],
          builder: (context, controller, _) => face(() {
            controller.isOpen ? controller.close() : controller.open();
          }),
        );
      },
    );
  }
}
