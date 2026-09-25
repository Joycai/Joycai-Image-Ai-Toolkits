import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/spec_rate.dart';
import 'package:joycai_image_ai_toolkits/services/billing/spec_billing.dart';
import 'package:joycai_image_ai_toolkits/services/billing/spec_known_values.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_capabilities.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_family.dart';
import 'package:joycai_image_ai_toolkits/services/llm/output_spec.dart';

/// Layer 3 for Grok Imagine's image models (docs/api/usage.md §5): 2.0 is
/// priced per resolution × quality and gets both controls; the
/// first-generation ids are flat-priced, refuse `1.5k`, and keep the two
/// they had.
void main() {
  List<String> keysOf(ModelCapabilities caps) => [for (final p in caps.imageParams) p.key];
  ParamSpec spec(ModelCapabilities caps, String key) =>
      caps.imageParams.firstWhere((p) => p.key == key);
  List<String> optionsOf(ModelCapabilities caps, String key) => [
    for (final o in spec(caps, key).options) o.value,
  ];

  group('grok-imagine-image-2.0', () {
    final caps = ModelCapabilities.forModel('grok-imagine-image-2.0');

    test('ratio, then quality, then the three-tier size', () {
      expect(keysOf(caps), ['aspectRatio', 'quality', 'imageSize']);
    });

    test('quality is low / medium, medium by default — what upstream serves unasked', () {
      expect(optionsOf(caps, 'quality'), ['low', 'medium']);
      expect(spec(caps, 'quality').defaultValue, 'medium');
      // `auto` hands the tier to the model (billed Low once, 2026-09-22);
      // `high` is refused. Neither is a tier a rate row can be written for.
      expect(optionsOf(caps, 'quality'), isNot(contains('auto')));
      expect(optionsOf(caps, 'quality'), isNot(contains('high')));
    });

    test('size offers the 1.5k tier between 1k and 2k', () {
      expect(optionsOf(caps, 'imageSize'), ['1k', '1.5k', '2k']);
      expect(spec(caps, 'imageSize').defaultValue, '1k');
    });

    test('the defaults spell the tier the docs price as 1K · Medium', () {
      final defaults = {for (final p in caps.imageParams) p.key: p.defaultValue};
      final rendered = OutputSpec.from(defaults);
      expect(rendered.size, '1K');
      expect(rendered.quality, 'medium');
    });

    test('a rate table copied off the pricing page lands on every cell', () {
      const rates = [
        SpecRate(size: '1K', quality: 'low', price: 0.04),
        SpecRate(size: '1.5K', quality: 'low', price: 0.05),
        SpecRate(size: '2K', quality: 'low', price: 0.06),
        SpecRate(size: '1K', quality: 'medium', price: 0.06),
        SpecRate(size: '1.5K', quality: 'medium', price: 0.07),
        SpecRate(size: '2K', quality: 'medium', price: 0.08),
      ];
      double priceOf(String size, String quality) => matchSpecRate(
        rates,
        OutputSpec.from({'imageSize': size, 'quality': quality}),
      ).rate!.price;
      expect(priceOf('1k', 'low'), 0.04);
      expect(priceOf('1.5k', 'low'), 0.05);
      expect(priceOf('2k', 'low'), 0.06);
      expect(priceOf('1k', 'medium'), 0.06);
      expect(priceOf('1.5k', 'medium'), 0.07);
      expect(priceOf('2k', 'medium'), 0.08);
    });

    test('a table written by size alone, from before the control, still matches', () {
      // Quality left blank on the row matches any quality — the tables
      // users wrote against the medium default keep pricing what they did.
      const rates = [SpecRate(size: '1K', price: 0.06), SpecRate(size: '2K', price: 0.08)];
      final match = matchSpecRate(rates, OutputSpec.from({'imageSize': '1k', 'quality': 'medium'}));
      expect(match.rate?.price, 0.06);
    });
  });

  group('first-generation ids keep the two-control table', () {
    for (final id in [
      'grok-imagine-image',
      'grok-imagine-image-quality',
      'xai/grok-imagine-image',
      'Grok-Imagine-Image',
    ]) {
      test(id, () {
        expect(ModelFamilyClassifier.classify(id), ModelFamily.xaiImage);
        final caps = ModelCapabilities.forModel(id);
        expect(keysOf(caps), ['aspectRatio', 'imageSize']);
        // Upstream answers `1.5k` on these with a 400.
        expect(optionsOf(caps, 'imageSize'), ['1k', '2k']);
      });
    }
  });

  test('a later version defaults to the 2.0 shape, not the legacy one', () {
    for (final id in [
      'grok-imagine-image-2.0',
      'grok-imagine-image-3',
      'xai/grok-imagine-image-2.0',
    ]) {
      expect(ModelFamilyClassifier.classify(id), ModelFamily.xaiImage, reason: id);
      expect(keysOf(ModelCapabilities.forModel(id)), [
        'aspectRatio',
        'quality',
        'imageSize',
      ], reason: id);
    }
  });

  test('the legacy table is reachable by id alone and so is listed for the rate editor', () {
    expect(
      ModelCapabilities.idRoutedTables,
      contains(ModelCapabilities.forModel('grok-imagine-image')),
    );
    expect(
      ModelCapabilities.forFamily(ModelFamily.xaiImage),
      same(ModelCapabilities.forModel('grok-imagine-image-2.0')),
    );
  });

  test('the rate editor\'s menus know 1.5K, low and medium', () {
    final known = SpecKnownValues.collect();
    expect(known.imageSizes, containsAll(['1K', '1.5K', '2K']));
    expect(known.qualities, containsAll(['low', 'medium']));
  });
}
