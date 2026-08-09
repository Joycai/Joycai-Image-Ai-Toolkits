import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// One choice in an [AppDropdown].
class AppDropdownItem<T> {
  final T value;
  final String label;
  final IconData? icon;

  const AppDropdownItem({required this.value, required this.label, this.icon});
}

/// A dropdown field sharing [AppTextField]'s fill colour and corner radius,
/// for choosing one of several values (not a fixed 2-4 option toggle — for
/// that, [AppSegmentedControl] reads as a single control rather than a menu).
///
/// Replaces reaching for [DropdownButton]/[DropdownButtonFormField] directly,
/// which — unlike [AppTextField] — has no fill colour by default and so sits
/// next to a themed text field looking like a different control family.
class AppDropdown<T> extends StatelessWidget {
  final T? value;
  final List<AppDropdownItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? label;
  final String? hint;
  final bool enabled;

  const AppDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.label,
    this.hint,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(appButtonRadius),
      borderSide: BorderSide.none,
    );

    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      // DropdownButtonFormField's own default text colour reads as disabled
      // grey regardless of enabled state; pinned to onSurface so it matches
      // the label colour any other themed field renders at.
      style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface),
      items: [
        for (final item in items)
          DropdownMenuItem<T>(
            value: item.value,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.icon != null) ...[
                  Icon(item.icon, size: 16),
                  const SizedBox(width: 8),
                ],
                Flexible(child: Text(item.label, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
      ],
      onChanged: enabled ? onChanged : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        border: border,
        enabledBorder: border,
        disabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
      ),
    );
  }
}
