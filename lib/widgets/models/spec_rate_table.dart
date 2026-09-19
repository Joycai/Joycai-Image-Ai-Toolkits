import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../models/spec_rate.dart';
import '../../services/billing/spec_known_values.dart';
import '../../services/llm/output_spec.dart';
import '../ui/app_button.dart';
import '../glass/app_glass_menu.dart';
import 'fee_group_summary.dart';

/// Parses a price the way users type them, not just the way Dart does:
/// accepts a decimal comma ('1,25'), rejects garbage and negatives. Null when
/// the text is not a usable price.
double? parsePriceInput(String text) {
  final normalized = text.trim().replaceAll(',', '.');
  final value = double.tryParse(normalized);
  if (value == null || value.isNaN || value.isInfinite || value < 0) return null;
  return value;
}

/// One editable row of a spec-billed group's rate table. Conditions are held
/// already normalised (see [OutputSpec]); the price is a text controller so
/// the field can validate as it is typed.
class SpecRateDraft {
  String? size;
  String? quality;
  int? seconds;
  final TextEditingController priceCtrl;

  SpecRateDraft({this.size, this.quality, this.seconds, String price = ''})
      : priceCtrl = TextEditingController(text: price);

  factory SpecRateDraft.of(SpecRate rate) => SpecRateDraft(
        size: rate.size,
        quality: rate.quality,
        seconds: rate.seconds,
        price: rate.price.toStringAsFixed(4),
      );

  double? get price => parsePriceInput(priceCtrl.text);

  bool sameConditionsAs(SpecRateDraft other) =>
      size == other.size && quality == other.quality && seconds == other.seconds;

  OutputSpec get spec => OutputSpec(size: size, quality: quality, seconds: seconds);

  SpecRate toRate() => SpecRate(size: size, quality: quality, seconds: seconds, price: price ?? 0);

  void dispose() => priceCtrl.dispose();
}

/// What stops a rate table from saving, and what merely deserves a word.
class SpecTableIssues {
  /// 1-based index of the first ordinary row with no usable price.
  final int? missingPriceRow;

  /// The first pair of rows (1-based) stating the same conditions.
  final ({int a, int b})? duplicate;

  const SpecTableIssues({this.missingPriceRow, this.duplicate});

  bool get blocksSave => missingPriceRow != null || duplicate != null;

  static SpecTableIssues of(List<SpecRateDraft> rows) {
    int? missing;
    for (final (i, row) in rows.indexed) {
      if (row.price == null) {
        missing = i + 1;
        break;
      }
    }
    ({int a, int b})? duplicate;
    outer:
    for (var i = 0; i < rows.length; i++) {
      for (var j = i + 1; j < rows.length; j++) {
        if (rows[i].sameConditionsAs(rows[j])) {
          duplicate = (a: i + 1, b: j + 1);
          break outer;
        }
      }
    }
    return SpecTableIssues(missingPriceRow: missing, duplicate: duplicate);
  }
}

/// The spec branch of the fee-group editor (`D2b · 21a–21d`): the unit chips
/// and the rate table — a header, the ordinary rows, 「添加档位」, and under a
/// hairline the pinned 「其他规格」 row that only has a price.
///
/// The drafts are the caller's: this widget mutates them in place and calls
/// [onChanged] so the caller can rebuild and revalidate.
class SpecRateTableEditor extends StatelessWidget {
  const SpecRateTableEditor({
    super.key,
    required this.unit,
    required this.onUnitChanged,
    required this.rows,
    required this.otherPriceCtrl,
    required this.onAddRow,
    required this.onRemoveRow,
    required this.onChanged,
    required this.onSwitchToRequest,
    required this.narrow,
  });

  final OutputUnit unit;
  final ValueChanged<OutputUnit> onUnitChanged;
  final List<SpecRateDraft> rows;
  final TextEditingController otherPriceCtrl;
  final VoidCallback onAddRow;
  final ValueChanged<int> onRemoveRow;
  final VoidCallback onChanged;
  final VoidCallback onSwitchToRequest;

  /// The phone form (`21i`): each row folds into a conditions line and a
  /// price line, and the unit chips share the width equally.
  final bool narrow;

  static const double _priceWidth = 84;
  static const double _deleteWidth = 28;
  static const double _gap = AppSpace.s6;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final issues = SpecTableIssues.of(rows);
    final otherBlank = otherPriceCtrl.text.trim().isEmpty;
    final onlyOther = rows.isEmpty;
    final suffix = specUnitSuffix(l10n, unit);
    final helpStyle = textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant, height: AppType.proseHeight);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildUnitRow(context, l10n, suffix),
        const SizedBox(height: AppSpace.s10),
        _buildHeader(context, l10n, suffix),
        const SizedBox(height: _gap),
        for (final (i, row) in rows.indexed) ...[
          if (i > 0 && !narrow) const SizedBox(height: _gap),
          narrow
              ? _buildNarrowRow(context, l10n, i, row, suffix, issues)
              : _buildWideRow(context, l10n, i, row, issues),
        ],
        if (rows.isNotEmpty) const SizedBox(height: _gap),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: SizedBox(
            height: narrow ? AppSize.touch : null,
            child: AppButton(
              label: l10n.specAddRate,
              icon: Icons.add,
              variant: AppButtonVariant.text,
              size: AppButtonSize.compact,
              onPressed: onAddRow,
            ),
          ),
        ),
        const SizedBox(height: _gap),
        Container(
          padding: const EdgeInsets.only(top: _gap),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: scheme.outlineVariant)),
          ),
          child: narrow ? _buildNarrowOtherRow(context, l10n, suffix) : _buildWideOtherRow(context, l10n),
        ),
        if (otherBlank) ...[
          const SizedBox(height: _gap),
          _Hint(icon: Icons.info_outline, text: l10n.specOtherBlankHint),
        ],
        if (issues.duplicate case final dup?) ...[
          const SizedBox(height: _gap),
          _Hint(
            icon: Icons.error_outline,
            text: l10n.specDuplicateRow(dup.a, dup.b, specRateConditions(l10n, rows[dup.a - 1].toRate())),
            error: true,
          ),
        ] else if (issues.missingPriceRow case final n?) ...[
          const SizedBox(height: _gap),
          _Hint(icon: Icons.info_outline, text: l10n.specPriceMissing(n)),
        ],
        // Only per clip is the same as per request: per image multiplies by
        // the pictures a request returned (a group of four is four units)
        // and per second by the length, while per request counts the call
        // once however many images it carried.
        if (onlyOther && unit == OutputUnit.clip) ...[
          const SizedBox(height: _gap),
          _Hint(icon: Icons.info_outline, text: l10n.specOnlyOtherHint),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton(
              label: l10n.specSwitchToRequest,
              icon: Icons.swap_horiz,
              variant: AppButtonVariant.text,
              size: AppButtonSize.compact,
              onPressed: onSwitchToRequest,
            ),
          ),
        ],
        const SizedBox(height: _gap),
        Text(l10n.specPriorityRule, style: helpStyle),
      ],
    );
  }

  // --- Unit ---------------------------------------------------------------

  Widget _buildUnitRow(BuildContext context, AppLocalizations l10n, String suffix) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final labelStyle = textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant);

    final chips = [
      for (final u in OutputUnit.values)
        _UnitChip(
          label: specUnitLabel(l10n, u),
          selected: u == unit,
          expand: narrow,
          onTap: () => onUnitChanged(u),
        ),
    ];

    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${l10n.specUnitLabel} · ${l10n.specPriceLabel(suffix)}', style: labelStyle),
          const SizedBox(height: AppSpace.s4),
          Row(
            children: [
              for (final (i, chip) in chips.indexed) ...[
                if (i > 0) const SizedBox(width: _gap),
                Expanded(child: chip),
              ],
            ],
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.specUnitLabel, style: labelStyle),
              const SizedBox(height: AppSpace.s4),
              Wrap(spacing: _gap, runSpacing: _gap, children: chips),
            ],
          ),
        ),
        const SizedBox(width: AppSpace.s10),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            specUnitNote(l10n, unit),
            style: textTheme.labelSmall?.mono.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  // --- Table --------------------------------------------------------------

  Widget _buildHeader(BuildContext context, AppLocalizations l10n, String suffix) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant);
    Widget cell(String text) => Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);

    return Row(
      children: [
        Expanded(child: cell(l10n.specDimSize)),
        const SizedBox(width: _gap),
        Expanded(child: cell(l10n.specDimQuality)),
        const SizedBox(width: _gap),
        Expanded(child: cell(l10n.specDimSeconds)),
        if (!narrow) ...[
          const SizedBox(width: _gap),
          SizedBox(width: _priceWidth, child: cell(l10n.specPriceLabel(suffix))),
          const SizedBox(width: _gap + _deleteWidth),
        ],
      ],
    );
  }

  List<Widget> _conditionCells(BuildContext context, AppLocalizations l10n, SpecRateDraft row, bool error) {
    final known = SpecKnownValues.collect();
    return [
      Expanded(
        child: SpecConditionField(
          value: row.size,
          error: error,
          groups: [
            (l10n.specGroupImageSizes, known.imageSizes),
            (l10n.specGroupVideoRes, known.videoResolutions),
          ],
          normalize: OutputSpec.normalizeSize,
          onChanged: (v) {
            row.size = v;
            onChanged();
          },
        ),
      ),
      const SizedBox(width: _gap),
      Expanded(
        child: SpecConditionField(
          value: row.quality,
          error: error,
          groups: [(null, known.qualities)],
          normalize: OutputSpec.normalizeQuality,
          onChanged: (v) {
            row.quality = v;
            onChanged();
          },
        ),
      ),
      const SizedBox(width: _gap),
      Expanded(
        child: SpecConditionField(
          value: row.seconds?.toString(),
          error: error,
          groups: [(null, [for (final s in known.seconds) '$s'])],
          normalize: (raw) => OutputSpec.normalizeSeconds(raw)?.toString(),
          onChanged: (v) {
            row.seconds = v == null ? null : int.tryParse(v);
            onChanged();
          },
        ),
      ),
    ];
  }

  bool _rowInDuplicate(int index, SpecTableIssues issues) {
    final dup = issues.duplicate;
    return dup != null && (dup.a == index + 1 || dup.b == index + 1);
  }

  Widget _buildWideRow(BuildContext context, AppLocalizations l10n, int index, SpecRateDraft row, SpecTableIssues issues) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        ..._conditionCells(context, l10n, row, _rowInDuplicate(index, issues)),
        const SizedBox(width: _gap),
        SizedBox(
          width: _priceWidth,
          child: _PriceField(controller: row.priceCtrl, placeholder: l10n.specPricePlaceholder, onChanged: onChanged),
        ),
        const SizedBox(width: _gap),
        _DeleteButton(width: _deleteWidth, onPressed: () => onRemoveRow(index)),
      ],
    );
  }

  Widget _buildNarrowRow(
    BuildContext context,
    AppLocalizations l10n,
    int index,
    SpecRateDraft row,
    String suffix,
    SpecTableIssues issues,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.only(bottom: _gap),
      margin: const EdgeInsets.only(bottom: _gap),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: scheme.outlineVariant))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: _conditionCells(context, l10n, row, _rowInDuplicate(index, issues))),
          const SizedBox(height: _gap),
          Row(
            children: [
              Expanded(
                child: _PriceField(
                  controller: row.priceCtrl,
                  placeholder: l10n.specPricePlaceholder,
                  suffix: '\$$suffix',
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: _gap),
              _DeleteButton(width: AppSize.touch, onPressed: () => onRemoveRow(index)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _otherTitle(BuildContext context, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Text(l10n.specOtherRates, style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            l10n.specOtherRatesSub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  Widget _buildWideOtherRow(BuildContext context, AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: AppSize.control,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Align(alignment: AlignmentDirectional.centerStart, child: _otherTitle(context, l10n)),
            ),
          ),
        ),
        const SizedBox(width: _gap),
        SizedBox(
          width: _priceWidth,
          child: _PriceField(controller: otherPriceCtrl, placeholder: '0.0000', onChanged: onChanged),
        ),
        const SizedBox(width: _gap + _deleteWidth),
      ],
    );
  }

  Widget _buildNarrowOtherRow(BuildContext context, AppLocalizations l10n, String suffix) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: 24, child: _otherTitle(context, l10n)),
        const SizedBox(height: _gap),
        Padding(
          padding: const EdgeInsets.only(right: AppSize.touch + _gap),
          child: _PriceField(
            controller: otherPriceCtrl,
            placeholder: '0.0000',
            suffix: '\$$suffix',
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// A unit choice (`21a`): 28 tall at r10, the accent tint and edge when on.
class _UnitChip extends StatelessWidget {
  const _UnitChip({required this.label, required this.selected, required this.onTap, required this.expand});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: selected ? scheme.accentTint : scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        side: BorderSide(color: selected ? scheme.primary : scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: AppSize.compact,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            // Hugs its label unless told to share a row: a Container given an
            // alignment would take the whole width the Wrap offers.
            child: Center(
              widthFactor: expand ? null : 1,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? scheme.onAccentTint : scheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One condition of a rate row (`21b / 21c`): a 32-tall field showing the
/// value in mono or 「任意」 as a placeholder; tapping opens a float-grade menu
/// of the known values in their groups, 「任意」 on top, 「自定义…」 at the
/// bottom. Custom turns the field itself into a text field: Enter commits
/// (blank = any), Escape returns to the menu's value.
class SpecConditionField extends StatefulWidget {
  const SpecConditionField({
    super.key,
    required this.value,
    required this.groups,
    required this.normalize,
    required this.onChanged,
    this.error = false,
  });

  /// The current condition, already normalised; null for any.
  final String? value;

  /// The menu's sections: a heading (null for none) over its values.
  final List<(String?, List<String>)> groups;

  /// The normaliser for typed values — the same one the request side uses.
  final String? Function(dynamic raw) normalize;

  final ValueChanged<String?> onChanged;

  /// Outlined in the error colour: this row duplicates another.
  final bool error;

  static const double menuWidth = 200;

  @override
  State<SpecConditionField> createState() => _SpecConditionFieldState();
}

class _SpecConditionFieldState extends State<SpecConditionField> {
  bool _custom = false;
  TextEditingController? _ctrl;

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  Future<void> _openMenu() async {
    final l10n = AppLocalizations.of(context)!;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final position = box.localToGlobal(Offset(0, box.size.height + AppSpace.s4));

    // A custom value the table already holds shows up in its group's tail,
    // so it can be re-picked without retyping.
    final known = widget.groups.expand((g) => g.$2).toSet();
    final current = widget.value;

    await showAppGlassMenu(
      context,
      position: position,
      width: SpecConditionField.menuWidth,
      entries: [
        AppGlassMenuItem(
          label: l10n.specAnyValue,
          icon: current == null ? Icons.check : null,
          onSelected: () => widget.onChanged(null),
        ),
        for (final (heading, values) in widget.groups) ...[
          if (heading != null) AppGlassMenuHeading(heading),
          for (final v in values)
            AppGlassMenuItem(
              label: v,
              icon: v == current ? Icons.check : null,
              onSelected: () => widget.onChanged(v),
            ),
        ],
        if (current != null && !known.contains(current))
          AppGlassMenuItem(
            label: current,
            icon: Icons.check,
            onSelected: () => widget.onChanged(current),
          ),
        const AppGlassMenuDivider(),
        AppGlassMenuItem(
          label: l10n.specCustomValue,
          icon: Icons.edit_outlined,
          onSelected: _startCustom,
        ),
      ],
    );
  }

  void _startCustom() {
    if (!mounted) return;
    _ctrl ??= TextEditingController();
    _ctrl!.text = widget.value ?? '';
    setState(() => _custom = true);
  }

  void _commitCustom() {
    final normalized = widget.normalize(_ctrl?.text ?? '');
    setState(() => _custom = false);
    widget.onChanged(normalized);
  }

  void _cancelCustom() => setState(() => _custom = false);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final mono = textTheme.labelSmall?.mono;
    final radius = BorderRadius.circular(AppRadius.control);

    if (_custom) {
      return Tooltip(
        message: l10n.specCustomHint,
        child: CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.escape): _cancelCustom},
          child: SizedBox(
            height: AppSize.control,
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              style: mono?.copyWith(color: scheme.onSurface),
              onSubmitted: (_) => _commitCustom(),
              onTapOutside: (_) => _commitCustom(),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: scheme.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.primary)),
                enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.primary)),
                focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.primary)),
              ),
            ),
          ),
        ),
      );
    }

    final value = widget.value;
    final label = Text(
      value ?? l10n.specAnyValue,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: mono?.copyWith(color: value == null ? scheme.outline : scheme.onSurface),
    );

    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: widget.error ? scheme.error : scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _openMenu,
        child: SizedBox(
          height: AppSize.control,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 6, 0),
            child: Row(
              children: [
                Expanded(child: value == null ? label : Tooltip(message: value, child: label)),
                const SizedBox(width: AppSpace.s4),
                Icon(Icons.expand_more, size: AppSize.iconSm, color: scheme.outline),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The 84-wide unit price: mono, four decimals, a placeholder in the outline
/// colour when empty. Never outlined red — a bad price is said under the
/// table, and the row's conditions are what a duplicate outlines.
class _PriceField extends StatelessWidget {
  const _PriceField({required this.controller, required this.placeholder, required this.onChanged, this.suffix});

  final TextEditingController controller;
  final String placeholder;
  final VoidCallback onChanged;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(AppRadius.control);

    return SizedBox(
      height: AppSize.control,
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: textTheme.bodySmall?.mono,
        onChanged: (_) => onChanged(),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: scheme.surface,
          hintText: placeholder,
          hintStyle: textTheme.bodySmall?.mono.copyWith(color: scheme.outline),
          suffixText: suffix,
          suffixStyle: textTheme.labelSmall?.copyWith(color: scheme.outline),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.outlineVariant)),
          enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.outlineVariant)),
          focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.primary)),
        ),
      ),
    );
  }
}

class _DeleteButton extends StatelessWidget {
  const _DeleteButton({required this.width, required this.onPressed});

  final double width;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      icon: const Icon(Icons.close, size: AppSize.iconMd),
      tooltip: l10n.delete,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(width: width, height: width > AppSize.compact ? AppSize.control : AppSize.compact),
      style: IconButton.styleFrom(
        foregroundColor: scheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
      ),
    );
  }
}

/// A line under the table: help in the secondary ink with an info glyph, or
/// the one error the table states (a duplicate row) in the error ink.
class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text, this.error = false});

  final IconData icon;
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final color = error ? scheme.onErrorContainer : scheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: AppSize.iconSm, color: error ? scheme.error : color),
        ),
        const SizedBox(width: AppSpace.s4),
        Expanded(
          child: Text(text, style: textTheme.labelSmall?.copyWith(color: color, height: AppType.proseHeight)),
        ),
      ],
    );
  }
}
