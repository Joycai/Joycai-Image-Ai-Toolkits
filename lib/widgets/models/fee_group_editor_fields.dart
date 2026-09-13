import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../services/billing/spec_billing.dart';
import '../app_segmented_control.dart';
import '../spec_rate_table.dart';
import 'fee_group_draft.dart';

/// The fee-group editor's fields (`D2 · 1e / 1f`, `D1a · 1d`): the name,
/// the billing mode, and that mode's rates — the three token prices, the one
/// request price, or the spec table (`D2b`).
///
/// Only the fields: the card around them, the title and the footer buttons
/// belong to whichever host shows the draft — the desktop's right column, the
/// tablet's inline card or the phone's page — so the fields are the one part
/// the three share verbatim.
class FeeGroupEditorFields extends StatelessWidget {
  const FeeGroupEditorFields({super.key, required this.draft, this.narrow = false});

  final FeeGroupDraft draft;

  /// The phone form: the spec table folds each row into two lines.
  final bool narrow;

  /// Narrowest a rate field gets before the three stack instead of sharing a
  /// row.
  static const double _minRateField = 110;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: draft,
      builder: (context, _) {
        final l10n = AppLocalizations.of(context)!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _Caption(l10n.groupName),
            TextField(
              controller: draft.nameCtrl,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
              decoration: _decoration(context).copyWith(hintText: l10n.feeGroupNamePlaceholder),
            ),
            const SizedBox(height: AppSpace.s10),
            _Caption(l10n.billingMode),
            // Segmented rather than a dropdown: there are only three modes and
            // each one rewrites the rate fields below, so the choice should be
            // visible next to what it changes.
            AppSegmentedControl<String>(
              segments: [
                AppSegment(value: 'token', label: l10n.perToken, icon: Icons.token_outlined),
                AppSegment(value: 'request', label: l10n.perRequest, icon: Icons.ads_click),
                AppSegment(value: specBillingMode, label: l10n.perSpec, icon: Icons.photo_size_select_large_outlined),
              ],
              value: draft.billingMode,
              onChanged: draft.setMode,
              expand: true,
            ),
            const SizedBox(height: 12),
            // `D2b · 21a`: the lower half is swapped whole and the card grows
            // from its top edge; the fields themselves do not slide.
            AnimatedSize(
              duration: AppMotion.durationOf(context, AppMotion.state),
              curve: AppMotion.enter,
              alignment: Alignment.topCenter,
              child: _buildRates(context, l10n),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRates(BuildContext context, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (draft.isSpec) {
      return SpecRateTableEditor(
        key: const ValueKey('spec'),
        unit: draft.outputUnit,
        onUnitChanged: draft.setUnit,
        rows: draft.specRows,
        otherPriceCtrl: draft.otherPriceCtrl,
        onAddRow: draft.addSpecRow,
        onRemoveRow: draft.removeSpecRow,
        onChanged: draft.touch,
        onSwitchToRequest: draft.switchToRequest,
        narrow: narrow,
      );
    }

    return Column(
      key: ValueKey(draft.billingMode),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (draft.isToken)
          LayoutBuilder(
            builder: (context, constraints) {
              final fields = [
                _priceField(context, draft.inputPriceCtrl, l10n.priceLabelInput, '\$/M'),
                _priceField(
                  context,
                  draft.cacheInputPriceCtrl,
                  l10n.priceLabelCache,
                  '\$/M',
                  // The rate a blank field inherits; with no input rate yet,
                  // the rule itself.
                  hintText: draft.inputPriceCtrl.text.trim().isEmpty
                      ? l10n.cachePriceBlankPlaceholder
                      : draft.inputPriceCtrl.text.trim(),
                ),
                _priceField(context, draft.outputPriceCtrl, l10n.priceLabelOutput, '\$/M'),
              ];
              if (constraints.maxWidth >= 3 * _minRateField + 2 * 8) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (i, field) in fields.indexed) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(child: field),
                    ],
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (i, field) in fields.indexed) ...[
                    if (i > 0) const SizedBox(height: AppSpace.s10),
                    field,
                  ],
                ],
              );
            },
          )
        else
          _priceField(context, draft.requestPriceCtrl, l10n.priceLabelRequest, '\$/Req'),
        const SizedBox(height: AppSpace.s6),
        // What the numbers are charged against, and (`1f`) the nudge that
        // image and video models belong in 「按规格」. Per-token and
        // per-request rates differ by six orders of magnitude.
        Text(
          draft.isToken ? l10n.tokenPriceHint : l10n.requestPriceHint,
          style: textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant, height: AppType.proseHeight),
        ),
      ],
    );
  }

  static InputDecoration _decoration(BuildContext context) => InputDecoration(
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: 12),
      );

  Widget _priceField(
    BuildContext context,
    TextEditingController ctrl,
    String label,
    String suffix, {
    String? hintText,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final invalid = draft.invalid(ctrl);

    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: textTheme.bodyMedium?.mono,
      decoration: _decoration(context).copyWith(
        labelText: label,
        // Always up, never sitting in the field: an empty cache field still
        // says which rate it is empty of.
        floatingLabelBehavior: FloatingLabelBehavior.always,
        hintText: hintText,
        hintStyle: textTheme.bodyMedium?.mono.copyWith(color: scheme.outline, fontStyle: FontStyle.italic),
        suffixText: suffix,
        suffixStyle: textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        error: invalid
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, size: AppSize.iconSm - 2, color: scheme.onErrorContainer),
                  const SizedBox(width: AppSpace.s4),
                  Expanded(
                    child: Text(
                      l10n.invalidPriceValue,
                      style: textTheme.labelSmall?.copyWith(color: scheme.onErrorContainer),
                    ),
                  ),
                ],
              )
            : null,
      ),
    );
  }
}

/// The 11 secondary caption over a field (`D2` 组名 / 计费模式).
class _Caption extends StatelessWidget {
  const _Caption(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.s4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}
