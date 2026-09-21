import '../../l10n/app_localizations.dart';
import '../../models/pricing_group.dart';
import '../../models/spec_rate.dart';
import '../../services/llm/output_spec.dart';

/// The display name of a spec-billed group's unit (`D2b`: 按张 / 按秒 / 按条).
String specUnitLabel(AppLocalizations l10n, OutputUnit unit) => switch (unit) {
      OutputUnit.image => l10n.specUnitImage,
      OutputUnit.second => l10n.specUnitSecond,
      OutputUnit.clip => l10n.specUnitClip,
    };

/// The suffix after a unit price: `/张` `/秒` `/条`.
String specUnitSuffix(AppLocalizations l10n, OutputUnit unit) => switch (unit) {
      OutputUnit.image => l10n.specUnitSuffixImage,
      OutputUnit.second => l10n.specUnitSuffixSecond,
      OutputUnit.clip => l10n.specUnitSuffixClip,
    };

/// How a request is counted, stated beside the unit chips.
String specUnitNote(AppLocalizations l10n, OutputUnit unit) => switch (unit) {
      OutputUnit.image => l10n.specUnitNoteImage,
      OutputUnit.second => l10n.specUnitNoteSecond,
      OutputUnit.clip => l10n.specUnitNoteClip,
    };

/// One rate row's conditions as the editor and the usage page spell them:
/// `1080p · high · 8s`, or 「任意」 for the catch-all.
String specRateConditions(AppLocalizations l10n, SpecRate rate) {
  if (rate.isCatchAll) return l10n.specAnyValue;
  return OutputSpec(size: rate.size, quality: rate.quality, seconds: rate.seconds).label;
}

/// A price with its trailing zeros trimmed to at least two decimals:
/// `0.5000` → `0.50`, `0.1250` → `0.125`. The summary's spelling; the table
/// itself keeps four places.
String trimPrice(double price) {
  var text = price.toStringAsFixed(4);
  final dot = text.indexOf('.');
  while (text.endsWith('0') && text.length - dot - 1 > 2) {
    text = text.substring(0, text.length - 1);
  }
  return text;
}

/// The one-line summary of what a group charges, the same shape for every
/// mode (`D2b · 21e / 21f`): 「按 token · 0.30 / 0.03 / 2.50」, 「按次 ·
/// $0.0400/次」, 「按秒 · 4 档 · $0.10–0.50」.
///
/// For a spec-billed group [n] counts the rows with a price — the catch-all
/// included when it has one — and the range spans every priced row. A group
/// that charges for reference images says so at the tail (`D2c · 22e`),
/// where a one-line field cuts first; [withInput] is off where the input
/// fee has a tag of its own.
String feeGroupSummary(AppLocalizations l10n, PricingGroup group, {bool withInput = true}) {
  switch (group.billingMode) {
    case 'spec':
      final unit = specUnitLabel(l10n, group.outputUnit);
      final rates = group.outputRates;
      final input = withInput ? feeGroupInputSummary(l10n, group) : null;
      final tail = input == null ? '' : ' · $input';
      if (rates.isEmpty) return '${l10n.specSummaryEmpty(unit)}$tail';
      final prices = rates.map((r) => r.price).toList()..sort();
      final output = l10n.specSummary(
        unit,
        rates.length,
        '\$${trimPrice(prices.first)}',
        trimPrice(prices.last),
      );
      return '$output$tail';
    case 'request':
      return '${l10n.perRequest} · \$${group.requestPrice.toStringAsFixed(4)}${l10n.specUnitSuffixRequest}';
    default:
      return '${l10n.perToken} · ${trimPrice(group.inputPrice)} / '
          '${trimPrice(group.effectiveCacheInputPrice)} / ${trimPrice(group.outputPrice)}';
  }
}

/// What a group charges for reference images — 「输入 $0.02/张 · 首 1 张免费」
/// — or null when it charges nothing for them, which is most groups: the
/// input fee then appears nowhere (`D2c`).
String? feeGroupInputSummary(AppLocalizations l10n, PricingGroup group) {
  if (!group.chargesInputImages) return null;
  return _withFree(l10n, group, l10n.feeGroupInputSummary('\$${trimPrice(group.inputUnitPrice)}'));
}

/// The same without the word 「输入」, for where a label already says it:
/// the row's tag (`$0.02/张 · 首 1 张免费`) and, with [fixed] places like
/// every other line of it, the rate-table tooltip.
String? feeGroupInputRate(AppLocalizations l10n, PricingGroup group, {bool fixed = false}) {
  if (!group.chargesInputImages) return null;
  final figure = fixed ? group.inputUnitPrice.toStringAsFixed(4) : trimPrice(group.inputUnitPrice);
  return _withFree(l10n, group, '\$$figure${l10n.specUnitSuffixImage}');
}

String _withFree(AppLocalizations l10n, PricingGroup group, String rate) =>
    group.inputFreeUnits > 0 ? '$rate · ${l10n.feeGroupInputFree(group.inputFreeUnits)}' : rate;

/// True when a spec-billed group has no catch-all row, so unlisted specs bill
/// at zero — the summary then carries 「其他规格按 0 计」 after it.
bool feeGroupOtherSpecsAtZero(PricingGroup group) =>
    group.isSpecBilled && !group.outputRates.any((r) => r.isCatchAll);

/// The full rate table, one row per line, for the summary chip's tooltip.
String feeGroupRateTable(AppLocalizations l10n, PricingGroup group) {
  final suffix = specUnitSuffix(l10n, group.outputUnit);
  final rows = group.outputRates.where((r) => !r.isCatchAll).toList();
  final other = group.outputRates.where((r) => r.isCatchAll).firstOrNull;
  return [
    for (final r in rows) '${specRateConditions(l10n, r)}  \$${r.price.toStringAsFixed(4)}$suffix',
    if (other != null)
      '${l10n.specOtherRates}  \$${other.price.toStringAsFixed(4)}$suffix'
    else
      '${l10n.specOtherRates}  ${l10n.specOtherZero}',
    if (feeGroupInputRate(l10n, group, fixed: true) case final input?)
      '${l10n.specInputTitle}  $input',
  ].join('\n');
}
