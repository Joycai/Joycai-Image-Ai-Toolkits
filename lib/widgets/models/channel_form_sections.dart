import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../screens/prompts/widgets/color_hue_picker.dart';
import '../app_button.dart';
import '../app_dialog.dart';

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
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
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
            prefixIcon: const Icon(Icons.label_outline, size: 20),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: tagCtrl,
          decoration: InputDecoration(
            labelText: l10n.tag,
            hintText: l10n.tagHint,
            prefixIcon: const Icon(Icons.tag, size: 20),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          l10n.tagColor,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
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
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: const Icon(Icons.palette_outlined, size: 16),
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The button's own foreground colour, carried explicitly: it
                  // used to arrive by inheritance, which a scale slot replaces.
                  Text(widget.l10n.moreColors,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant)),
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
          duration: AppMotion.durationOf(context, AppMotion.reveal),
          firstCurve: AppMotion.enter,
          secondCurve: AppMotion.enter,
          sizeCurve: AppMotion.enter,
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

/// A single row of colour swatches ending in a "custom" button, for a form
/// laying colour out *beside* another field rather than under it.
///
/// [CompactColorPicker] is the same idea for a column: it can afford the full
/// palette plus an inline hue wheel, and stacks them. The single-page channel
/// dialog puts colour in the same row as the display name, where a block that
/// tall would push the rest of the form off the page — so the palette and the
/// wheel move behind [ChannelColorPickerDialog] instead, and only a strip of
/// swatches stays on the page.
class ChannelColorStrip extends StatelessWidget {
  final AppLocalizations l10n;
  final int selectedColor;
  final ValueChanged<int> onColorChanged;

  /// How many preset swatches sit inline before the custom button.
  final int inlineCount;

  const ChannelColorStrip({
    super.key,
    required this.l10n,
    required this.selectedColor,
    required this.onColorChanged,
    this.inlineCount = 5,
  });

  /// The swatches to draw. The current colour is always one of them — when it
  /// came from the dialog rather than the strip it takes the leading slot,
  /// because a strip that cannot show the selection reads as "nothing is
  /// selected" while the form holds a colour the user chose.
  List<int> _visibleColors() {
    final presets = AppConstants.tagColors
        .take(inlineCount)
        .map((c) => c.toARGB32())
        .toList();
    if (presets.contains(selectedColor)) return presets;
    return [selectedColor, ...presets.take(inlineCount - 1)];
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final color in _visibleColors())
          ChannelColorSwatch(
            color: Color(color),
            selected: color == selectedColor,
            onTap: () => onColorChanged(color),
          ),
        Tooltip(
          message: l10n.customColor,
          child: InkWell(
            onTap: () => _openPicker(context),
            customBorder: const CircleBorder(),
            child: Container(
              width: AppSize.iconButton,
              height: AppSize.iconButton,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Icon(
                Icons.add,
                size: AppSize.iconSm,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    final picked = await ChannelColorPickerDialog.show(
      context,
      l10n: l10n,
      initialColor: selectedColor,
    );
    if (picked != null) onColorChanged(picked);
  }
}

/// One round colour chip, selected or not.
class ChannelColorSwatch extends StatelessWidget {
  const ChannelColorSwatch({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: AppSize.iconButton,
        height: AppSize.iconButton,
        alignment: Alignment.center,
        // A ring set off from the swatch rather than a border drawn on it: a
        // border eats into the colour, so the selected swatch would read as
        // *smaller* than its neighbours instead of as picked.
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

/// The full palette behind [ChannelColorStrip]'s custom button: every preset
/// swatch, the hue wheel, and a hex field, committed with Apply.
class ChannelColorPickerDialog extends StatefulWidget {
  final AppLocalizations l10n;
  final int initialColor;

  const ChannelColorPickerDialog({
    super.key,
    required this.l10n,
    required this.initialColor,
  });

  /// Returns the chosen colour, or null when dismissed.
  static Future<int?> show(
    BuildContext context, {
    required AppLocalizations l10n,
    required int initialColor,
  }) {
    return showDialog<int>(
      context: context,
      builder: (_) => ChannelColorPickerDialog(
        l10n: l10n,
        initialColor: initialColor,
      ),
    );
  }

  @override
  State<ChannelColorPickerDialog> createState() =>
      _ChannelColorPickerDialogState();
}

class _ChannelColorPickerDialogState extends State<ChannelColorPickerDialog> {
  late int _color = widget.initialColor;
  late final TextEditingController _hexCtrl =
      TextEditingController(text: _hexOf(_color));

  static String _hexOf(int argb) =>
      '#${argb.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  void _select(int argb) {
    setState(() {
      _color = argb;
      // Keep the hex readout in step with the swatches and the wheel; the
      // field is an input *and* a readout, and letting it lag makes Apply look
      // like it committed something other than what is highlighted.
      _hexCtrl.text = _hexOf(argb);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;

    return AppDialog(
      title: l10n.customColor,
      maxWidth: 380,
      maxHeight: 620,
      scrollable: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in AppConstants.tagColors)
                ChannelColorSwatch(
                  color: preset,
                  selected: preset.toARGB32() == _color,
                  onTap: () => _select(preset.toARGB32()),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: ColorHuePicker(
              initialColor: Color(_color),
              onColorChanged: _select,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: AppSize.iconButton,
                height: AppSize.iconButton,
                decoration: BoxDecoration(
                  color: Color(_color),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _hexCtrl,
                  decoration: const InputDecoration(
                    labelText: 'HEX',
                    prefixIcon: Icon(Icons.colorize, size: AppSize.iconLg),
                  ),
                  onChanged: (v) {
                    final parsed = _parseHex(v);
                    if (parsed != null) setState(() => _color = parsed);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.pop(context),
        ),
        AppButton(
          label: l10n.apply,
          onPressed: () => Navigator.pop(context, _color),
        ),
      ],
    );
  }

  /// `#RRGGBB` or `#AARRGGBB`; null for anything still half-typed, so the
  /// preview simply holds its last valid value rather than flickering.
  static int? _parseHex(String input) {
    final raw = input.trim();
    if (!raw.startsWith('#')) return null;
    final body = raw.substring(1);
    if (body.length != 6 && body.length != 8) return null;
    return int.tryParse(body.length == 6 ? 'FF$body' : body, radix: 16);
  }
}
