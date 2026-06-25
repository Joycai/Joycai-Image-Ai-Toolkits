import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../services/llm/model_capabilities.dart';

/// Picker for image-size parameters whose values aren't exhaustively
/// enumerable (currently used by gpt-image-2). Renders the spec's preset
/// options as quick-pick chips on top of a freeform Width × Height editor
/// with live validation against [ParamSpec.customValidator].
///
/// Returns the chosen value (a `WxH` string, the literal `auto`, or `null`
/// if the user cancelled).
Future<String?> showImageSizePickerDialog({
  required BuildContext context,
  required ParamSpec spec,
  required String currentValue,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _ImageSizePickerDialog(spec: spec, currentValue: currentValue),
  );
}

class _ImageSizePickerDialog extends StatefulWidget {
  final ParamSpec spec;
  final String currentValue;

  const _ImageSizePickerDialog({required this.spec, required this.currentValue});

  @override
  State<_ImageSizePickerDialog> createState() => _ImageSizePickerDialogState();
}

class _ImageSizePickerDialogState extends State<_ImageSizePickerDialog> {
  late final TextEditingController _widthCtrl;
  late final TextEditingController _heightCtrl;
  int? _width;
  int? _height;

  @override
  void initState() {
    super.initState();
    final parsed = _parseSize(widget.currentValue);
    _width = parsed?.$1 ?? 1024;
    _height = parsed?.$2 ?? 1024;
    _widthCtrl = TextEditingController(text: _width!.toString());
    _heightCtrl = TextEditingController(text: _height!.toString());
  }

  @override
  void dispose() {
    _widthCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  /// Snap to the nearest multiple of 16, clamped to a sensible range so the
  /// user can't punch in numbers like 6 that round to zero.
  int _snap(int raw) {
    final clamped = raw.clamp(16, 8192);
    return ((clamped + 8) ~/ 16) * 16;
  }

  (int, int)? _parseSize(String value) {
    final m = RegExp(r'^(\d+)x(\d+)$').firstMatch(value);
    if (m == null) return null;
    return (int.parse(m.group(1)!), int.parse(m.group(2)!));
  }

  void _setSize(int w, int h) {
    setState(() {
      _width = w;
      _height = h;
    });
    _widthCtrl.text = w.toString();
    _heightCtrl.text = h.toString();
    // Move the caret to the end so the user sees the snapped value.
    _widthCtrl.selection = TextSelection.collapsed(offset: _widthCtrl.text.length);
    _heightCtrl.selection = TextSelection.collapsed(offset: _heightCtrl.text.length);
  }

  void _onWidthChanged(String text) {
    final n = int.tryParse(text);
    setState(() => _width = n);
  }

  void _onHeightChanged(String text) {
    final n = int.tryParse(text);
    setState(() => _height = n);
  }

  void _commitSnap() {
    final w = _width;
    final h = _height;
    if (w == null || h == null) return;
    final sw = _snap(w);
    final sh = _snap(h);
    if (sw != w || sh != h) _setSize(sw, sh);
  }

  bool get _customValid {
    final w = _width;
    final h = _height;
    if (w == null || h == null) return false;
    final validator = widget.spec.customValidator;
    if (validator == null) return false;
    return validator('${w}x$h');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final presets = widget.spec.options.where((o) => o.value != 'auto').toList();
    final hasAuto = widget.spec.options.any((o) => o.value == 'auto');

    final rules = (_width != null && _height != null)
        ? checkOpenAIImage2SizeRules(_width!, _height!)
        : const <SizeRuleResult>[];

    return AlertDialog(
      title: Text(l10n.imageSizePickerTitle),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasAuto) ...[
                _SectionHeader(label: l10n.imageSizeAuto),
                const SizedBox(height: 6),
                _AutoCard(
                  selected: widget.currentValue == 'auto' &&
                      _width.toString() == '1024' && _height.toString() == '1024',
                  onTap: () => Navigator.of(context).pop('auto'),
                  label: l10n.imageSizeAutoDesc,
                ),
                const SizedBox(height: 16),
              ],
              _SectionHeader(label: l10n.imageSizePresets),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: presets.map((opt) {
                  final isSelected = widget.currentValue == opt.value;
                  return ChoiceChip(
                    label: Text(opt.value.replaceAll('x', '×')),
                    selected: isSelected,
                    onSelected: (_) {
                      final parsed = _parseSize(opt.value);
                      if (parsed != null) _setSize(parsed.$1, parsed.$2);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              _SectionHeader(label: l10n.imageSizeCustom),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _widthCtrl,
                      decoration: InputDecoration(
                        labelText: l10n.imageSizeWidth,
                        isDense: true,
                        border: const OutlineInputBorder(),
                        suffixText: 'px',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: _onWidthChanged,
                      onEditingComplete: _commitSnap,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Icon(Icons.close, size: 16),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _heightCtrl,
                      decoration: InputDecoration(
                        labelText: l10n.imageSizeHeight,
                        isDense: true,
                        border: const OutlineInputBorder(),
                        suffixText: 'px',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: _onHeightChanged,
                      onEditingComplete: _commitSnap,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                l10n.imageSizeSnapHint,
                style: TextStyle(fontSize: 11, color: colorScheme.outline),
              ),
              if (rules.isNotEmpty) ...[
                const SizedBox(height: 14),
                _AspectPreview(
                  width: _width!,
                  height: _height!,
                  valid: _customValid,
                ),
                const SizedBox(height: 14),
                ...rules.map((r) => _RuleRow(
                      label: _ruleLabel(l10n, r.labelKey, _width!, _height!),
                      passes: r.passes,
                    )),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _customValid ? () => Navigator.of(context).pop('${_width}x$_height') : null,
          child: Text(l10n.apply),
        ),
      ],
    );
  }

  String _ruleLabel(AppLocalizations l10n, String key, int w, int h) {
    final long = w > h ? w : h;
    final short = w > h ? h : w;
    switch (key) {
      case 'sizeRuleMultiple16':
        return l10n.sizeRuleMultiple16;
      case 'sizeRuleMaxEdge':
        return l10n.sizeRuleMaxEdge(long);
      case 'sizeRuleAspect':
        final ratio = short > 0 ? (long / short).toStringAsFixed(2) : '∞';
        return l10n.sizeRuleAspect(ratio);
      case 'sizeRulePixels':
        return l10n.sizeRulePixels(_formatMegapixels(w * h));
      default:
        return key;
    }
  }

  String _formatMegapixels(int pixels) {
    final mp = pixels / 1000000;
    return '${mp.toStringAsFixed(2)} MP';
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.4),
    );
  }
}

class _AutoCard extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final String label;
  const _AutoCard({required this.selected, required this.onTap, required this.label});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
          color: selected ? colorScheme.primaryContainer.withValues(alpha: 0.3) : null,
        ),
        child: Row(
          children: [
            Icon(Icons.auto_fix_high,
                size: 18, color: selected ? colorScheme.primary : colorScheme.outline),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
            if (selected) Icon(Icons.check, size: 16, color: colorScheme.primary),
          ],
        ),
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  final String label;
  final bool passes;
  const _RuleRow({required this.label, required this.passes});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final iconColor = passes ? Colors.green.shade600 : colorScheme.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(passes ? Icons.check_circle : Icons.cancel, size: 14, color: iconColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: passes ? colorScheme.onSurfaceVariant : colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tiny rectangle that visually reflects the chosen aspect ratio. Helps the
/// user catch obviously-wrong inputs (e.g. accidentally a square when they
/// meant 16:9) before they commit.
class _AspectPreview extends StatelessWidget {
  final int width;
  final int height;
  final bool valid;
  const _AspectPreview({required this.width, required this.height, required this.valid});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const maxDim = 80.0;
    final ratio = width / height;
    final double previewW;
    final double previewH;
    if (ratio >= 1) {
      previewW = maxDim;
      previewH = maxDim / ratio;
    } else {
      previewH = maxDim;
      previewW = maxDim * ratio;
    }
    return Center(
      child: Column(
        children: [
          Container(
            width: previewW.clamp(8.0, maxDim),
            height: previewH.clamp(8.0, maxDim),
            decoration: BoxDecoration(
              color: (valid ? colorScheme.primary : colorScheme.error).withValues(alpha: 0.15),
              border: Border.all(
                color: valid ? colorScheme.primary : colorScheme.error,
                width: 1.2,
              ),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$width×$height',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
