import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../ui/color_hue_picker.dart';
import '../../ui/app_button.dart';
import '../../ui/app_dialog.dart';
import 'channel_field.dart';

/// The tag-colour row: round swatches from [AppConstants.tagColors], then a
/// "More colors" pill that reveals the rest of the palette in place and a
/// "Custom color" pill that opens the hue wheel.
///
/// The current colour is always one of the swatches drawn: when it came from
/// the wheel it takes the leading slot, because a row that cannot show the
/// selection reads as "nothing is selected".
class ChannelTagColorPicker extends StatefulWidget {
  const ChannelTagColorPicker({
    super.key,
    required this.l10n,
    required this.selectedColor,
    required this.onColorChanged,
    this.inlineCount = 10,
    this.swatchSize = 28,
  });

  final AppLocalizations l10n;
  final int selectedColor;
  final ValueChanged<int> onColorChanged;

  /// Swatches shown before "More colors" is opened (`1d`: 10, `1e`: 8).
  final int inlineCount;

  /// Diameter of each swatch and the height of the two pills.
  final double swatchSize;

  @override
  State<ChannelTagColorPicker> createState() => _ChannelTagColorPickerState();
}

class _ChannelTagColorPickerState extends State<ChannelTagColorPicker> {
  bool _showAll = false;

  List<int> _visibleColors() {
    final palette = AppConstants.tagColors.map((c) => c.toARGB32()).toList();
    final shown = _showAll ? palette : palette.take(widget.inlineCount).toList();
    if (shown.contains(widget.selectedColor)) return shown;
    return [
      widget.selectedColor,
      ...(_showAll ? shown : shown.take(math.max(0, shown.length - 1))),
    ];
  }

  Future<void> _openCustom() async {
    final picked = await ChannelColorPickerDialog.show(
      context,
      l10n: widget.l10n,
      initialColor: widget.selectedColor,
    );
    if (picked != null) widget.onColorChanged(picked);
  }

  Widget _pill({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      shape: StadiumBorder(side: BorderSide(color: colorScheme.outlineVariant)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: widget.swatchSize,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: AppSize.iconSm, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: AppSpace.s4),
                Text(
                  label,
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpace.s6,
      runSpacing: AppSpace.s6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final color in _visibleColors())
          ChannelColorSwatch(
            color: Color(color),
            selected: color == widget.selectedColor,
            size: widget.swatchSize,
            onTap: () => widget.onColorChanged(color),
          ),
        _pill(
          icon: _showAll ? Icons.expand_less : Icons.add,
          label: widget.l10n.moreColors,
          onTap: () => setState(() => _showAll = !_showAll),
        ),
        _pill(
          icon: Icons.colorize,
          label: widget.l10n.customColor,
          onTap: _openCustom,
        ),
      ],
    );
  }
}

/// One round colour swatch. Selected: a 2px accent ring separated from the
/// colour by a 2px gap of the panel behind it — a ring set off from the disc
/// rather than drawn on it, so the picked swatch does not read as smaller.
class ChannelColorSwatch extends StatelessWidget {
  const ChannelColorSwatch({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
    this.size = 28,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: size,
          height: size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? null : color,
              border: selected
                  ? Border.all(color: colorScheme.primary, width: 2)
                  : null,
            ),
            child: selected
                ? Padding(
                    padding: const EdgeInsets.all(AppSpace.s4),
                    child: DecoratedBox(
                      decoration:
                          BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

/// The full palette behind the "Custom color" pill: every preset swatch, the
/// hue wheel, and a hex field, committed with Apply.
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
      animationStyle: appDialogAnimation(context),
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
      // The field is an input *and* a readout; letting it lag makes Apply
      // look like it committed something other than what is highlighted.
      _hexCtrl.text = _hexOf(argb);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;

    return AppDialog(
      icon: Icons.colorize,
      title: l10n.customColor,
      maxWidth: 380,
      maxHeight: 640,
      scrollable: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: AppSpace.s6,
            runSpacing: AppSpace.s6,
            children: [
              for (final preset in AppConstants.tagColors)
                ChannelColorSwatch(
                  color: preset,
                  selected: preset.toARGB32() == _color,
                  onTap: () => _select(preset.toARGB32()),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.s16),
          Center(
            child: ColorHuePicker(
              initialColor: Color(_color),
              onColorChanged: _select,
            ),
          ),
          const SizedBox(height: AppSpace.s16),
          Row(
            children: [
              Container(
                width: AppSize.control,
                height: AppSize.control,
                decoration: BoxDecoration(
                  color: Color(_color),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
              ),
              const SizedBox(width: AppSpace.s10),
              Expanded(
                child: ChannelField(
                  controller: _hexCtrl,
                  mono: true,
                  hint: '#RRGGBB',
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
  /// preview holds its last valid value rather than flickering.
  static int? _parseHex(String input) {
    final raw = input.trim();
    if (!raw.startsWith('#')) return null;
    final body = raw.substring(1);
    if (body.length != 6 && body.length != 8) return null;
    return int.tryParse(body.length == 6 ? 'FF$body' : body, radix: 16);
  }
}
