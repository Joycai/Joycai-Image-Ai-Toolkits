import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/pricing_group.dart';
import 'package:joycai_image_ai_toolkits/models/spec_rate.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/fee_group_summary.dart';

/// The one-line summary every fee group is shown as (`D2b · 21e / 21f`):
/// the same shape whatever the mode, so a price can be read without first
/// reading the mode.
void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  const veo = [
    SpecRate(size: '1080p', quality: 'high', price: 0.50),
    SpecRate(size: '1080p', price: 0.30),
    SpecRate(size: '720p', price: 0.15),
    SpecRate(price: 0.10),
  ];

  test('a spec group: unit, priced-row count and the price range', () {
    final g = PricingGroup(name: 'Veo', billingMode: 'spec', outputUnit: OutputUnit.second, outputRates: veo);
    expect(feeGroupSummary(l10n, g), 'Per second · 4 rates · \$0.10–0.50');
    expect(feeGroupOtherSpecsAtZero(g), isFalse);
  });

  test('the catch-all counts as a rate only when it has a price', () {
    final g = PricingGroup(
      name: 'Nano',
      billingMode: 'spec',
      outputRates: const [SpecRate(size: '1K', price: 0.03), SpecRate(size: '4K', price: 0.12)],
    );
    expect(feeGroupSummary(l10n, g), 'Per image · 2 rates · \$0.03–0.12');
    expect(feeGroupOtherSpecsAtZero(g), isTrue);
  });

  test('an empty table says zero rates rather than a range of nothing', () {
    final g = PricingGroup(name: 'New', billingMode: 'spec', outputUnit: OutputUnit.clip);
    expect(feeGroupSummary(l10n, g), 'Per clip · 0 rates');
  });

  test('token and request groups summarise in the same shape', () {
    expect(
      feeGroupSummary(l10n, PricingGroup(name: 'T', inputPrice: 0.3, cacheInputPrice: 0.03, outputPrice: 2.5)),
      'Per token · 0.30 / 0.03 / 2.50',
    );
    expect(
      feeGroupSummary(l10n, PricingGroup(name: 'R', billingMode: 'request', requestPrice: 0.04)),
      'Per request · \$0.0400/req',
    );
  });

  test('prices trim their trailing zeros, but never below two decimals', () {
    expect(trimPrice(0.5), '0.50');
    expect(trimPrice(0.125), '0.125');
    expect(trimPrice(1.0), '1.00');
    expect(trimPrice(0.0004), '0.0004');
  });

  test('the tooltip lists every row and says what unlisted specs cost', () {
    final g = PricingGroup(name: 'Veo', billingMode: 'spec', outputUnit: OutputUnit.second, outputRates: veo);
    expect(feeGroupRateTable(l10n, g).split('\n'), [
      '1080p · high  \$0.5000/s',
      '1080p  \$0.3000/s',
      '720p  \$0.1500/s',
      'Other specs  \$0.1000/s',
    ]);
    final noOther = PricingGroup(name: 'N', billingMode: 'spec', outputRates: veo.sublist(0, 1));
    expect(feeGroupRateTable(l10n, noOther).split('\n').last, 'Other specs  Other specs at 0');
  });
}
