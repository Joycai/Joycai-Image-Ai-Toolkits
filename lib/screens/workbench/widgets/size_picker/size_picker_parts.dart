import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/app_theme.dart';
import '../../../../core/design_tokens.dart';
import '../../../../services/llm/image_size_rules.dart';
import '../../../../widgets/ui/app_field_size.dart';
import '../../../../widgets/ui/dashed_border.dart';

/// `A1c` `.sec`: an 11/500 tracked caption in the deep ink, with an optional
/// mono note pushed to the end (`1K / 2K / 4K`, `派生 · 跟着宽高走`).
class SizeSectionTitle extends StatelessWidget {
  const SizeSectionTitle({super.key, required this.label, this.icon, this.note});

  final String label;
  final IconData? icon;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Text(
          label,
          style: text.labelSmall?.copyWith(
            color: scheme.accentText,
            fontWeight: FontWeight.w500,
            letterSpacing: AppType.trackedLabelSpacing,
          ),
        ),
        if (icon != null) ...[
          const SizedBox(width: AppSpace.s6),
          Icon(icon, size: AppSize.iconSm, color: scheme.accentText),
        ],
        if (note != null) ...[
          const SizedBox(width: AppSpace.s6),
          Expanded(
            child: Text(
              note!,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.labelSmall?.mono.copyWith(color: scheme.outline),
            ),
          ),
        ],
      ],
    );
  }
}

/// A ratio chip (`A1c` `.rc`): a thumbnail of the shape beside its label, so
/// landscape, square and portrait read at a glance — and the label is always
/// there, never the shape alone.
class SizeRatioChip extends StatelessWidget {
  const SizeRatioChip({
    super.key,
    required this.label,
    required this.ratio,
    required this.selected,
    required this.onTap,
    required this.height,
    this.icon,
    this.error = false,
    this.dimmed = false,
  });

  final String label;

  /// Width over height of the thumbnail, or null for a glyph-only chip.
  final double? ratio;
  final bool selected;
  final VoidCallback onTap;
  final double height;
  final IconData? icon;
  final bool error;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final Color ink = error
        ? scheme.error
        : selected
        ? scheme.accentText
        : scheme.onSurfaceVariant;
    final Color border = error
        ? scheme.error
        : selected
        ? scheme.primary
        : scheme.outlineVariant;
    Widget? thumb;
    final r = ratio;
    if (r != null) {
      const double maxEdge = 14;
      final w = r >= 1 ? maxEdge : maxEdge * r;
      final h = r >= 1 ? maxEdge / r : maxEdge;
      thumb = Container(
        width: math.max(3, w),
        height: math.max(3, h),
        decoration: BoxDecoration(
          border: Border.all(color: ink.withValues(alpha: 0.85), width: 1.5),
          borderRadius: BorderRadius.circular(2),
        ),
      );
    } else if (icon != null) {
      thumb = Icon(icon, size: AppSize.iconSm, color: ink);
    }
    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: Material(
        color: selected && !error ? scheme.accentTint : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          side: BorderSide(color: border),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.control),
          child: SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (thumb != null) ...[
                    SizedBox(width: 14, height: 14, child: Center(child: thumb)),
                    const SizedBox(width: AppSpace.s6),
                  ],
                  Text(
                    label,
                    style: text.labelMedium?.copyWith(
                      color: ink,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small mono number box (`A1c` `.fld`): the long edge, the width and the
/// height. [flash] washes it with the accent tint for one beat — a value the
/// picker corrected shows *where* it changed (`30e` 显形).
class SizeNumberInput extends StatelessWidget {
  const SizeNumberInput({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.height,
    required this.onChanged,
    required this.onSubmitted,
    this.prefix,
    this.suffix,
    this.error = false,
    this.flash = false,
    this.allowRatio = false,
    this.semanticsLabel,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final double height;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final String? prefix;
  final String? suffix;
  final bool error;
  final bool flash;

  /// Accept a ratio's spelling (`16:9`, `1.78`) rather than digits only.
  final bool allowRatio;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodySmall!.mono.copyWith(color: scheme.onSurface);
    final affix = Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant);
    final vertical = pinnedFieldInset(context, style, height);
    OutlineInputBorder outline(Color color, [double width = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.control),
      borderSide: BorderSide(color: color, width: width),
    );
    return AnimatedContainer(
      duration: AppMotion.durationOf(context, flash ? AppMotion.state : const Duration(milliseconds: 300)),
      curve: AppMotion.quick,
      decoration: BoxDecoration(
        color: flash ? scheme.accentTint : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        style: style,
        keyboardType: allowRatio ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.allow(allowRatio ? RegExp(r'[0-9:.xX×/]') : RegExp(r'[0-9]'))],
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: flash ? Colors.transparent : scheme.surfaceContainerLow,
          constraints: BoxConstraints.tightFor(height: height),
          contentPadding: EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: vertical),
          prefixText: prefix == null ? null : '$prefix  ',
          prefixStyle: affix,
          suffixText: suffix,
          suffixStyle: affix,
          semanticCounterText: semanticsLabel,
          enabledBorder: outline(error ? scheme.error : scheme.outlineVariant),
          focusedBorder: outline(error ? scheme.error : scheme.primary, 1.5),
          border: outline(scheme.outlineVariant),
        ),
      ),
    );
  }
}

/// The preview (`A1c` 预览): a dashed square standing for the model's area
/// ceiling (`面积参考 4096²`) and the chosen size drawn to the same scale over
/// it — so "already at the ceiling" shows before any number is read. The
/// rectangle's size eases (M2); a new size mid-tween continues from where it
/// is rather than restarting.
class SizePreview extends StatelessWidget {
  const SizePreview({
    super.key,
    required this.width,
    required this.height,
    required this.referenceEdge,
    required this.referenceLabel,
    required this.boxHeight,
    this.invalid = false,
    this.dimmed = false,
  });

  final int width;
  final int height;
  final int referenceEdge;
  final String referenceLabel;
  final double boxHeight;
  final bool invalid;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final double refSide = boxHeight - 28;
    final double scale = refSide / math.max(1, referenceEdge);
    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: Container(
        height: boxHeight,
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double maxW = constraints.maxWidth - 16;
            final double maxH = boxHeight - 12;
            final double rw = (width * scale).clamp(4.0, maxW);
            final double rh = (height * scale).clamp(4.0, maxH);
            final Color stroke = invalid ? scheme.error : scheme.primary;
            final Widget rect = invalid
                ? DashedBorder(
                    color: stroke,
                    radius: 3,
                    child: Container(color: scheme.errorContainer.withValues(alpha: 0.6)),
                  )
                : Container(
                    decoration: BoxDecoration(
                      color: scheme.accentTint,
                      border: Border.all(color: stroke, width: 1.5),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
            return Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: refSide,
                  height: refSide,
                  child: DashedBorder(color: scheme.outline, radius: 2, child: const SizedBox.expand()),
                ),
                TweenAnimationBuilder<Size?>(
                  tween: SizeTween(end: Size(rw, rh)),
                  duration: AppMotion.durationOf(context, AppMotion.state),
                  curve: AppMotion.move,
                  builder: (context, size, child) => SizedBox(width: size!.width, height: size.height, child: child),
                  child: rect,
                ),
                Positioned(
                  left: AppSpace.s10,
                  bottom: AppSpace.s6,
                  child: Text(referenceLabel, style: text.labelSmall?.copyWith(color: scheme.outline, fontSize: 10.5)),
                ),
                Positioned(
                  right: AppSpace.s10,
                  bottom: AppSpace.s6,
                  child: Text(
                    '$width×$height',
                    style: text.labelSmall?.mono.copyWith(
                      color: invalid ? scheme.error : scheme.onSurfaceVariant,
                      fontSize: 10.5,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One rule in the rule line, already worded.
class SizeRulePart {
  const SizeRulePart(this.text, {this.passes = true});
  final String text;
  final bool passes;
}

/// `A1c` 规则行: every rule in one mono 10.5 line. All passing it ends in
/// 「全部符合」; while typing, 「待校验」; with a failure, only the failing
/// rule is inked — the others stay grey, neither green nor red, because they
/// were not what stopped the size.
class SizeRuleLine extends StatelessWidget {
  const SizeRuleLine({super.key, required this.parts, required this.status, required this.failLabel});

  final List<SizeRulePart> parts;

  /// 「全部符合」 / 「待校验」, or null when a rule fails.
  final String? status;
  final String failLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ui = Theme.of(context).textTheme.labelSmall!.copyWith(color: scheme.outline, fontSize: 10.5);
    final base = ui.mono;
    final spans = <InlineSpan>[];
    for (final (i, p) in parts.indexed) {
      if (i > 0) spans.add(TextSpan(text: ' · ', style: base));
      spans.add(
        TextSpan(
          text: p.passes ? p.text : '${p.text} $failLabel',
          style: p.passes ? base : base.copyWith(color: scheme.error, fontWeight: FontWeight.w600),
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: Text.rich(TextSpan(children: spans), maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        if (status != null) ...[
          const SizedBox(width: AppSpace.s6),
          Text(status!, style: ui),
        ],
      ],
    );
  }
}

/// The rule line's parts for [rules], in the order the spec writes them
/// (`×16 · 长边 ≤ 3840 · ≤ 3:1 · 0.66–8.29 MP`). [check] marks which pass
/// when a size is being judged; null marks them all as passing.
List<SizeRulePart> sizeRuleParts(
  ImageSizeRules rules, {
  required String Function(int max) maxEdgeLabel,
  required String Function(int min) minEdgeLabel,
  required String ratioLimit,
  (int, int)? check,
}) {
  final results = check == null ? null : rules.check(check.$1, check.$2);
  bool ok(String key) => results == null || results.firstWhere((r) => r.labelKey == key).passes;
  final range = formatPixelRange(rules.minPixels, rules.minPixels, rules.maxPixels);
  return [
    SizeRulePart('×${rules.edgeStep}', passes: ok('sizeRuleEdgeGrid')),
    if (rules.minEdge != null) SizeRulePart(minEdgeLabel(rules.minEdge!), passes: ok('sizeRuleMinEdge')),
    if (rules.maxEdge != null) SizeRulePart(maxEdgeLabel(rules.maxEdge!), passes: ok('sizeRuleMaxEdge')),
    SizeRulePart('≤ $ratioLimit', passes: ok('sizeRuleAspect')),
    SizeRulePart('${range.min}–${range.max} MP', passes: ok('sizeRulePixels')),
  ];
}
