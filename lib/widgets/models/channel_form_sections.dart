import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../l10n/app_localizations.dart';
import '../../screens/prompts/widgets/color_hue_picker.dart';

/// Small section label shared by the add/edit channel dialogs so both use
/// the same visual grouping language (连接 / 外观 / …).
class ChannelSectionLabel extends StatelessWidget {
  final String text;
  const ChannelSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

/// The appearance block shared by the add-channel wizard (step 3) and the
/// edit-channel dialog: display name, tag, and the compact color picker.
class ChannelAppearanceSection extends StatelessWidget {
  final AppLocalizations l10n;
  final TextEditingController nameCtrl;
  final TextEditingController tagCtrl;
  final int tagColor;
  final ValueChanged<int> onColorChanged;

  const ChannelAppearanceSection({
    super.key,
    required this.l10n,
    required this.nameCtrl,
    required this.tagCtrl,
    required this.tagColor,
    required this.onColorChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: nameCtrl,
          decoration: InputDecoration(
            labelText: l10n.displayName,
            hintText: l10n.nameHint,
            isDense: true,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.label_outline, size: 20),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: tagCtrl,
          decoration: InputDecoration(
            labelText: l10n.tag,
            hintText: l10n.tagHint,
            isDense: true,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.tag, size: 20),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          l10n.tagColor,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: colorScheme.outline,
          ),
        ),
        const SizedBox(height: 8),
        CompactColorPicker(
          l10n: l10n,
          selectedColor: tagColor,
          onColorChanged: onColorChanged,
        ),
      ],
    );
  }
}

/// Preset-first color picker: a swatch grid with the current hex shown as a
/// chip, and the full hue wheel + hex input tucked behind a "more colors"
/// toggle. Replaces the always-visible wheel that used to dominate both
/// channel dialogs.
class CompactColorPicker extends StatefulWidget {
  final AppLocalizations l10n;
  final int selectedColor;
  final ValueChanged<int> onColorChanged;

  const CompactColorPicker({
    super.key,
    required this.l10n,
    required this.selectedColor,
    required this.onColorChanged,
  });

  @override
  State<CompactColorPicker> createState() => _CompactColorPickerState();
}

class _CompactColorPickerState extends State<CompactColorPicker> {
  bool _expanded = false;

  String get _hex =>
      '#${widget.selectedColor.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: AppConstants.tagColors.map((color) {
            final isSelected = widget.selectedColor == color.toARGB32();
            return InkWell(
              onTap: () => widget.onColorChanged(color.toARGB32()),
              borderRadius: BorderRadius.circular(13),
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? colorScheme.onSurface
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        // Wrap (not Row + Spacer): the edit dialog's column can be < 300px
        // wide, where chip + button don't fit on one line and a Row would
        // overflow. Wrap flows the button onto a second line instead.
        Wrap(
          spacing: 8,
          runSpacing: 4,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Color(widget.selectedColor),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(_hex,
                      style: TextStyle(
                          fontSize: 12, color: colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: const Icon(Icons.palette_outlined, size: 16),
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.l10n.moreColors,
                      style: const TextStyle(fontSize: 12)),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                  ),
                ],
              ),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: _expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Column(
              children: [
                Center(
                  child: ColorHuePicker(
                    initialColor: Color(widget.selectedColor),
                    onColorChanged: widget.onColorChanged,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: TextEditingController(text: _hex),
                  decoration: const InputDecoration(
                    labelText: 'HEX',
                    prefixIcon: Icon(Icons.colorize, size: 20),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    if (v.startsWith('#') && (v.length == 7 || v.length == 9)) {
                      try {
                        final colorStr =
                            v.length == 7 ? 'FF${v.substring(1)}' : v.substring(1);
                        widget.onColorChanged(int.parse(colorStr, radix: 16));
                      } catch (_) {/* ignore malformed */}
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
