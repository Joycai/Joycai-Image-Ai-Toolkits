import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/constants.dart';
import '../core/design_tokens.dart';
import '../l10n/app_localizations.dart';
import '../screens/prompts/widgets/color_hue_picker.dart';

/// Picks a category's identity colour (`C1 · 1d`): a hue bar, the preset
/// swatches, and a hex field.
///
/// Identity colours are stored as ARGB ints and never follow the accent.
class ColorPickerWidget extends StatefulWidget {
  final int selectedColor;
  final ValueChanged<int> onColorChanged;
  final bool showHexInput;

  /// Shows the hue bar. Named for the wheel this used to draw.
  final bool showColorWheel;

  const ColorPickerWidget({
    super.key,
    required this.selectedColor,
    required this.onColorChanged,
    this.showHexInput = true,
    this.showColorWheel = true,
  });

  @override
  State<ColorPickerWidget> createState() => _ColorPickerWidgetState();
}

class _ColorPickerWidgetState extends State<ColorPickerWidget> {
  /// Kept across rebuilds: a controller rebuilt on every colour change put the
  /// caret back at the start of the field under the user's typing.
  late final TextEditingController _hexCtrl;

  static String _format(int color) =>
      '#${color.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  static int? _parse(String v) {
    if (!v.startsWith('#') || (v.length != 7 && v.length != 9)) return null;
    final colorStr = v.length == 7 ? 'FF${v.substring(1)}' : v.substring(1);
    return int.tryParse(colorStr, radix: 16);
  }

  @override
  void initState() {
    super.initState();
    _hexCtrl = TextEditingController(text: _format(widget.selectedColor));
  }

  @override
  void didUpdateWidget(ColorPickerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedColor != widget.selectedColor && _parse(_hexCtrl.text) != widget.selectedColor) {
      _hexCtrl.text = _format(widget.selectedColor);
    }
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showColorWheel) ...[
          ColorHueBar(
            color: Color(widget.selectedColor),
            onColorChanged: widget.onColorChanged,
          ),
          const SizedBox(height: 12),
        ],
        Text(
          AppLocalizations.of(context)!.colorPresets,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: AppSpace.s6),
        Wrap(
          spacing: AppSpace.s6,
          runSpacing: AppSpace.s6,
          children: AppConstants.tagColors.map((color) {
            final isSelected = widget.selectedColor == color.toARGB32();
            return InkWell(
              onTap: () => widget.onColorChanged(color.toARGB32()),
              customBorder: const CircleBorder(),
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    // `onSurface`, not black: this ring marks the chosen
                    // swatch, and black on a near-black canvas marked nothing.
                    color: isSelected ? scheme.onSurface : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        if (widget.showHexInput) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: 120,
            height: AppSize.control,
            child: TextField(
              controller: _hexCtrl,
              style: Theme.of(context).textTheme.bodySmall!.mono,
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                filled: true,
                fillColor: scheme.surfaceContainerLow,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.s10),
              ),
              onChanged: (v) {
                final color = _parse(v);
                if (color != null) widget.onColorChanged(color);
              },
            ),
          ),
        ],
      ],
    );
  }
}
