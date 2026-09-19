import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/app_theme.dart';
import '../../../../core/design_tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/spec_rate.dart';
import '../../../../services/llm/image_size_vocabulary.dart';
import '../../../../services/llm/model_capabilities.dart';
import '../../../../services/llm/output_spec.dart';
import '../../workbench_layout.dart';
import 'size_picker_panel.dart';
import 'size_picker_texts.dart';
import 'size_popover.dart';

/// The workbench's size field (`A1c · 30a`): value, the ratio it derives, and
/// a separate swap button that turns the size on its side without opening
/// anything. It opens the size picker — a popover on desktop and tablet, the
/// picker unfolded in place inside the phone's parameter sheet (`30h`: one
/// sheet, never a second one on top).
///
/// Under it, once, a note when a size chosen for a sibling model was not
/// valid here and fell back (`30a` 刚被回落) — the helper ink, not a warning;
/// it goes as soon as the field is used.
class SizeField extends StatefulWidget {
  const SizeField({
    super.key,
    required this.spec,
    required this.value,
    required this.modelName,
    required this.onChanged,
    this.storedValue,
    this.rates,
  });

  /// A `customSize` spec with [ParamSpec.sizeRules] and
  /// [ParamSpec.sizeVocabulary].
  final ParamSpec spec;

  /// The validated value.
  final String value;
  final String modelName;
  final ValueChanged<String> onChanged;

  /// What the store held before validation — differs from [value] exactly
  /// when a value was dropped for this model.
  final String? storedValue;
  final List<SpecRate>? rates;

  @override
  State<SizeField> createState() => _SizeFieldState();
}

class _SizeFieldState extends State<SizeField> {
  bool _open = false;

  ImageSizeVocabulary get _vocab => widget.spec.sizeVocabulary!;

  String? get _sentinel =>
      widget.spec.options.map((o) => o.value).where((v) => v == 'auto' || v == 'not_set').firstOrNull;

  /// The size the value draws, when it has one to turn: pixels only — a
  /// keyword or a sentinel is a square, and turning a square does nothing.
  (int, int)? get _swappable {
    final wxh = parseWxH(widget.value);
    if (wxh == null || wxh.width == wxh.height) return null;
    return (wxh.width, wxh.height);
  }

  String? get _fellBackFrom {
    final stored = widget.storedValue;
    if (stored == null || stored == widget.value) return null;
    if (parseWxH(stored) == null && tierEdge(stored) == null) return null;
    return stored;
  }

  Future<void> _openPicker(WorkbenchLayoutState? layout) async {
    if (layout?.rightSheetOpener != null) {
      setState(() => _open = !_open);
      return;
    }
    final inDrawer = layout?.rightInDrawer ?? false;
    final box = context.findRenderObject() as RenderBox?;
    final fieldWidth = box?.hasSize ?? false ? box!.size.width : 300.0;
    setState(() => _open = true);
    await showSizePopover(
      context,
      width: inDrawer ? math.min(340, fieldWidth + AppSpace.s16) : 340,
      builder: (context, close) =>
          _panel(inDrawer ? SizePickerDensity.tablet : SizePickerDensity.desktop, close: close),
    );
    if (mounted) setState(() => _open = false);
  }

  Widget _panel(SizePickerDensity density, {required VoidCallback close, bool showHeader = true}) {
    return SizePickerPanel(
      spec: widget.spec,
      value: widget.value,
      modelName: widget.modelName,
      rates: widget.rates,
      density: density,
      showHeader: showHeader,
      onChanged: widget.onChanged,
      onClose: close,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final layout = context.watch<WorkbenchLayoutState?>();
    final inline = layout?.rightSheetOpener != null;
    final height = inline
        ? AppSize.touch
        : (layout?.rightInDrawer ?? false)
        ? AppSize.large
        : AppSize.control;

    final (primary, secondary, keyword) = _labels(l10n);
    final swap = _swappable;
    final fellBack = _fellBackFrom;

    final field = Row(
      children: [
        Expanded(
          child: Material(
            color: _open && inline ? scheme.accentTint : scheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
              side: BorderSide(color: _open ? scheme.primary : scheme.outlineVariant),
            ),
            child: InkWell(
              onTap: () => _openPicker(layout),
              borderRadius: BorderRadius.circular(AppRadius.control),
              child: SizedBox(
                height: height,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10),
                  child: Row(
                    children: [
                      // Not Flexible: beside the Expanded note a Flexible takes
                      // half the free width whether it needs it or not, and the
                      // note is elided at half. The value is short by nature.
                      Text(
                        primary,
                        maxLines: 1,
                        style: (keyword || parseWxH(widget.value) != null ? text.bodySmall?.mono : text.bodySmall)
                            ?.copyWith(
                              color: scheme.onSurface,
                              fontWeight: keyword ? FontWeight.w700 : FontWeight.w500,
                            ),
                      ),
                      const SizedBox(width: AppSpace.s6),
                      Expanded(
                        child: Text(
                          secondary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                      Icon(
                        _open ? Icons.expand_less : Icons.expand_more,
                        size: AppSize.iconMd,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (!inline || !_open) ...[
          const SizedBox(width: AppSpace.s6),
          SizedBox.square(
            dimension: height,
            child: Tooltip(
              message: l10n.imageSizeSwap,
              child: Material(
                color: scheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  side: BorderSide(color: scheme.outlineVariant),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  // S9: swap the sides; nothing opens.
                  onTap: swap == null ? null : () => widget.onChanged('${swap.$2}x${swap.$1}'),
                  child: Icon(
                    Icons.swap_horiz,
                    size: AppSize.iconMd,
                    color: swap == null ? scheme.outline.withValues(alpha: AppAlpha.disabled) : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        field,
        if (fellBack != null && !_open) ...[
          const SizedBox(height: AppSpace.s4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.history, size: AppSize.iconSm, color: scheme.onSurfaceVariant),
              const SizedBox(width: AppSpace.s4),
              Expanded(
                child: Text(
                  l10n.imageSizeFellBack(
                    sizeValueText(fellBack),
                    widget.modelName,
                    _sentinel == null ? sizeValueText(widget.value) : sentinelTexts(l10n, _vocab.sentinel).$1,
                  ),
                  style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
        if (inline)
          AnimatedSize(
            duration: AppMotion.durationOf(context, AppMotion.panel),
            curve: AppMotion.emphasized,
            alignment: Alignment.topCenter,
            child: _open
                ? Padding(
                    padding: const EdgeInsets.only(top: AppSpace.s10),
                    child: _panel(
                      SizePickerDensity.phone,
                      showHeader: false,
                      close: () => setState(() => _open = false),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
      ],
    );
  }

  /// The field's main text, its note, and whether the main text is a tier
  /// keyword (set bold, like a size, because it is one).
  (String, String, bool) _labels(AppLocalizations l10n) {
    final parsed = SizeValue.parse(widget.value, sentinel: _sentinel, tiers: _vocab.tiers);
    switch (parsed) {
      case SizeDimsValue(:final width, :final height):
        return (sizeValueText(widget.value), ratioLabel(width, height, chips: _vocab.ratios), false);
      case SizeTierValue(:final tier):
        return (tier, l10n.imageSizeKeywordHint('1:1'), true);
      case SizeSentinelValue():
        final (title, hint) = sentinelTexts(l10n, _vocab.sentinel);
        return (title, hint, false);
    }
  }
}
