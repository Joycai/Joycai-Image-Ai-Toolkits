import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../screens/prompts/widgets/color_hue_picker.dart';

/// A reusable color picker widget with preset colors, color wheel, and hex input
class ColorPickerWidget extends StatelessWidget {
  final int selectedColor;
  final ValueChanged<int> onColorChanged;
  final bool showHexInput;
  final bool showColorWheel;

  const ColorPickerWidget({
    super.key,
    required this.selectedColor,
    required this.onColorChanged,
    this.showHexInput = true,
    this.showColorWheel = true,
  });

  @override
  Widget build(BuildContext context) {
    final hexCtrl = TextEditingController(
      text: '#${selectedColor.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Color Wheel (if enabled)
        if (showColorWheel) ...[
          Center(
            child: ColorHuePicker(
              initialColor: Color(selectedColor),
              onColorChanged: onColorChanged,
            ),
          ),
          const SizedBox(height: 24),
        ],

        // Hex Input (if enabled)
        if (showHexInput) ...[
          TextField(
            controller: hexCtrl,
            decoration: const InputDecoration(
              labelText: 'HEX Color',
              prefixIcon: Icon(Icons.colorize),
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              if (v.startsWith('#') && (v.length == 7 || v.length == 9)) {
                try {
                  final colorStr = v.length == 7 ? 'FF${v.substring(1)}' : v.substring(1);
                  final color = int.parse(colorStr, radix: 16);
                  onColorChanged(color);
                } catch (_) {}
              }
            },
          ),
          const SizedBox(height: 16),
        ],

        // Preset Colors Section
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            "Presets",
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: AppConstants.tagColors.map((color) {
            final isSelected = selectedColor == color.toARGB32();
            return InkWell(
              onTap: () => onColorChanged(color.toARGB32()),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    // `onSurface`, not black: this ring marks the chosen
                    // swatch, and black on a near-black canvas marked nothing.
                    color: isSelected
                        ? Theme.of(context).colorScheme.onSurface
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
