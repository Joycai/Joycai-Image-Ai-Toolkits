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
    final g = PricingGroup(
      name: 'Veo',
      billingMode: 'spec',
      outputUnit: OutputUnit.second,
      outputRates: veo,
    );
    expect(feeGroupSummary(l10n, g), 'Per second · 4 rates · \$0.10–0.50');
    expect(feeGroupOtherSpecsAtZero(g), isFalse);
  });

  test('the catch-all counts as a rate only when it has a price', () {
    final g = PricingGroup(
      name: 'Nano',
      billingMode: 'spec',
      outputRates: const [
        SpecRate(size: '1K', price: 0.03),
        SpecRate(size: '4K', price: 0.12),
      ],
    );
    expect(feeGroupSummary(l10n, g), 'Per image · 2 rates · \$0.03–0.12');
    expect(feeGroupOtherSpecsAtZero(g), isTrue);
  });

  group('a group that charges for reference images (D2c)', () {
    PricingGroup seedream({
      int free = 1,
      double price = 0.02,
      OutputUnit unit = OutputUnit.image,
    }) => PricingGroup(
      name: 'Seedream pro',
      billingMode: 'spec',
      outputUnit: unit,
      outputRates: const [SpecRate(price: 0.30)],
      inputUnitPrice: price,
      inputFreeUnits: free,
    );

    test('says so at the summary\'s tail, the free ones after the price', () {
      expect(
        feeGroupSummary(l10n, seedream()),
        'Per image · 1 rates · \$0.30–0.30 · input \$0.02/image · first 1 free',
      );
      expect(feeGroupSummary(l10n, seedream(free: 0)), endsWith(' · input \$0.02/image'));
    });

    test('the row leaves it out of the summary and tags it instead', () {
      expect(
        feeGroupSummary(l10n, seedream(), withInput: false),
        'Per image · 1 rates · \$0.30–0.30',
      );
      expect(feeGroupInputRate(l10n, seedream()), '\$0.02/image · first 1 free');
    });

    test('the tooltip table gains one last line, four places like the rest', () {
      expect(
        feeGroupRateTable(l10n, seedream()).split('\n').last,
        'Input images  \$0.0200/image · first 1 free',
      );
    });

    test('no price or token mode: the input fee appears nowhere', () {
      final quiet = [
        seedream(price: 0),
        PricingGroup(name: 'T', billingMode: 'token', inputUnitPrice: 0.02),
      ];
      for (final g in quiet) {
        expect(feeGroupInputSummary(l10n, g), isNull, reason: g.name);
        expect(feeGroupInputRate(l10n, g), isNull);
        expect(feeGroupSummary(l10n, g), isNot(contains('input')));
        expect(feeGroupRateTable(l10n, g), isNot(contains('Input images')));
      }
    });
  });

  test('an empty table says zero rates rather than a range of nothing', () {
    final g = PricingGroup(name: 'New', billingMode: 'spec', outputUnit: OutputUnit.clip);
    expect(feeGroupSummary(l10n, g), 'Per clip · 0 rates');
  });

  test('a request group that charges inputs carries the same tail (D2e)', () {
    final g = PricingGroup(
      name: 'xAI video',
      billingMode: 'request',
      requestPrice: 0.08,
      inputUnitPrice: 0.01,
    );
    expect(feeGroupSummary(l10n, g), 'Per request · \$0.0800/req · input \$0.01/image');
    expect(feeGroupSummary(l10n, g, withInput: false), 'Per request · \$0.0800/req');
    expect(feeGroupInputRate(l10n, g), '\$0.01/image');
    final perSecond = PricingGroup(
      name: 'xAI video',
      billingMode: 'spec',
      outputUnit: OutputUnit.second,
      outputRates: const [SpecRate(price: 0.08)],
      inputUnitPrice: 0.01,
    );
    expect(
      feeGroupSummary(l10n, perSecond),
      'Per second · 1 rates · \$0.08–0.08 · input \$0.01/image',
    );
    expect(feeGroupRateTable(l10n, perSecond), contains('Input images  \$0.0100/image'));
  });

  test('token and request groups summarise in the same shape', () {
    expect(
      feeGroupSummary(
        l10n,
        PricingGroup(name: 'T', inputPrice: 0.3, cacheInputPrice: 0.03, outputPrice: 2.5),
      ),
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
    final g = PricingGroup(
      name: 'Veo',
      billingMode: 'spec',
      outputUnit: OutputUnit.second,
      outputRates: veo,
    );
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
