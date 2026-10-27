import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/media_pricing.dart';
import 'package:joycai_image_ai_toolkits/models/pricing_group.dart';
import 'package:joycai_image_ai_toolkits/models/spec_rate.dart';
import 'package:joycai_image_ai_toolkits/models/token_usage.dart';
import 'package:joycai_image_ai_toolkits/models/usage_accounting.dart';
import 'package:joycai_image_ai_toolkits/services/billing/media_accounting.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/usage_normalization.dart';

void main() {
  final pricing = PricingGroup(
    name: 'mixed',
    inputPrice: 2,
    cacheInputPrice: 0.5,
    outputPrice: 8,
    mediaPricing: const MediaPricing(imageInput: 4, imageCache: 1, imageOutput: 16),
  );
  Map<String, dynamic> usage({int cache = 30}) => {
    'input_tokens': 300,
    'output_tokens': 100,
    'input_tokens_details': {
      'text_tokens': 100,
      'image_tokens': 200,
      'cached_tokens': cache,
      'cached_tokens_details': {'text_tokens': 10, 'image_tokens': 20},
    },
  };
  test('disjoint multimodal buckets and cache, no duplicate total charge', () {
    final a = MediaAccounting.price(pricing, normalizeTokenUsage(usage(), imageOutput: true));
    expect(a.complete, isTrue);
    expect(a.cost, closeTo((90 * 2 + 10 * 0.5 + 180 * 4 + 20 * 1 + 100 * 16) / 1e6, 1e-12));
    expect(UsageAccounting.decode(a.encode())!.cost, a.cost);
  });
  test('unknown cache split and inconsistent totals remain incomplete', () {
    final raw = usage();
    (raw['input_tokens_details'] as Map).remove('cached_tokens_details');
    expect(
      MediaAccounting.price(pricing, normalizeTokenUsage(raw, imageOutput: true)).complete,
      isFalse,
    );
    expect(
      MediaAccounting.price(
        pricing,
        normalizeTokenUsage(usage(cache: 40), imageOutput: true),
      ).complete,
      isFalse,
    );
    raw['input_tokens'] = 200;
    expect(
      MediaAccounting.price(pricing, normalizeTokenUsage(raw, imageOutput: true)).complete,
      isFalse,
    );
  });
  test('zero total cache conflicting with modality cache is invalid', () {
    expect(
      MediaAccounting.price(
        pricing,
        normalizeTokenUsage(usage(cache: 0), imageOutput: true),
      ).complete,
      isFalse,
    );
  });
  test('no usage and no modality prices are unknown, explicit zero is free', () {
    expect(MediaAccounting.price(pricing, {}).complete, isFalse);
    final missing = MediaAccounting.price(
      PricingGroup(name: 'unset'),
      normalizeTokenUsage(usage(), imageOutput: true),
    );
    expect(missing.complete, isFalse);
    final zero = MediaAccounting.price(
      PricingGroup(
        name: 'zero',
        mediaPricing: const MediaPricing(imageInput: 0, imageCache: 0, imageOutput: 0),
      ),
      normalizeTokenUsage(usage(), imageOutput: true),
    );
    expect(zero.complete, isTrue);
    expect(zero.cost, 0);
  });
  test('video input and output have independent prices, preserve fractional seconds', () {
    final p = PricingGroup(
      name: 'video',
      billingMode: 'spec',
      outputUnit: OutputUnit.second,
      outputRates: const [SpecRate(size: '1080p', price: 0.2)],
      inputUnitPrice: 0.01,
      mediaPricing: const MediaPricing(videoInputRates: [SpecRate(size: '1080p', price: 0.1)]),
    );
    final a = MediaAccounting.price(
      p,
      {'input_seconds': 2.5, 'input_images': 2},
      options: {'resolution': '1080p', 'seconds': 5.4},
      video: true,
      pending: true,
    );
    expect(a.status, 'pending');
    expect(a.cost, closeTo(1.08 + 0.25 + 0.02, 1e-12));
    final b = MediaAccounting.settle(a, {'output_seconds': 6.25});
    expect(b.cost, closeTo(1.25 + 0.25 + 0.02, 1e-12));
    expect(b.components.first.quantity, 6.25);
  });
  test('terminal resolution matches the submitted rules and keeps known input', () {
    final p = PricingGroup(
      name: 'video',
      billingMode: 'spec',
      outputUnit: OutputUnit.second,
      outputRates: const [
        SpecRate(size: '720p', price: 1),
        SpecRate(size: '1080p', price: 2),
      ],
      mediaPricing: const MediaPricing(
        videoInputRates: [
          SpecRate(size: '720p', price: 3),
          SpecRate(size: '1080p', price: 4),
        ],
      ),
    );
    final a = MediaAccounting.price(
      p,
      {'input_seconds': 2, 'input_images': 0},
      options: {'resolution': '720p', 'seconds': 5},
      video: true,
    );
    final b = MediaAccounting.settle(a, {'output_size': '1080p', 'output_seconds': 6});
    expect(b.cost, 20);
    expect(b.quantities['input_seconds'], 2);
  });
  test('unknown input duration is not free; reported zero overrides only total', () {
    final a = MediaAccounting.price(
      PricingGroup(name: 'v', billingMode: 'request', requestPrice: 1),
      {'input_images': 0},
      video: true,
    );
    expect(a.complete, isFalse);
    final row = TokenUsage(modelId: 'v', timestamp: DateTime(2026), accounting: a, reportedCost: 0);
    expect(row.cost, 0);
    expect(row.costIncomplete, isFalse);
    expect(row.snapshotCost, 1);
  });
  test('zero output does not waive independently charged input processing', () {
    final a = MediaAccounting.price(
      PricingGroup(
        name: 'i',
        billingMode: 'spec',
        outputRates: const [SpecRate(price: 1)],
        inputUnitPrice: 0.1,
      ),
      {'images': 0, 'input_images': 2},
    );
    expect(a.cost, 0.2);
  });
  test('unknown mode cannot silently charge per request', () {
    expect(
      MediaAccounting.price(
        PricingGroup(name: 'bad', billingMode: 'bad', requestPrice: 100),
        {},
      ).complete,
      isFalse,
    );
  });
  test('vision input with ordinary text output does not invent image output usage', () {
    final raw = usage();
    final a = MediaAccounting.price(pricing, normalizeTokenUsage(raw));
    expect(a.complete, isTrue);
    expect(a.categoryCost('output'), 100 * 8 / 1e6);
    final unknown = MediaAccounting.price(
      pricing,
      normalizeTokenUsage(raw, hasGeneratedImages: true),
    );
    expect(unknown.complete, isFalse);
  });
}
