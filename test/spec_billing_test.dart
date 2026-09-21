import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/pricing_group.dart';
import 'package:joycai_image_ai_toolkits/models/spec_rate.dart';
import 'package:joycai_image_ai_toolkits/models/token_usage.dart';
import 'package:joycai_image_ai_toolkits/services/billing/spec_billing.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/output_spec.dart';

/// Pins how a spec-billed fee group turns one generation into money: which
/// rate row a request lands on, what it counts, and what the usage row
/// snapshots — through the same pure entry point the three recording paths
/// in LLMService call.
void main() {
  const veo = [
    SpecRate(size: '1080p', quality: 'high', price: 0.50),
    SpecRate(size: '1080p', price: 0.30),
    SpecRate(size: '720p', price: 0.15),
    SpecRate(price: 0.10),
  ];

  group('matchSpecRate', () {
    test('the most specific matching row wins, whatever its position', () {
      final m = matchSpecRate(veo, const OutputSpec(size: '1080p', quality: 'high'));
      expect(m.price, 0.50);
    });

    test('a row stating a condition the spec lacks does not match', () {
      // 1080p without a quality: the `high` row asks for one, the plain
      // 1080p row does not.
      final m = matchSpecRate(veo, const OutputSpec(size: '1080p'));
      expect(m.price, 0.30);
    });

    test('a spec nothing states falls to the catch-all', () {
      final m = matchSpecRate(veo, const OutputSpec(size: '480p', seconds: 8));
      expect(m.price, 0.10);
      expect(m.matched, isTrue);
    });

    test('among equally specific rows the earlier one wins', () {
      const twice = [
        SpecRate(size: '1K', price: 0.03),
        SpecRate(quality: 'high', price: 0.09),
      ];
      final m = matchSpecRate(twice, const OutputSpec(size: '1K', quality: 'high'));
      expect(m.price, 0.03);
    });

    test('no catch-all and no match is reported, not priced at zero silently', () {
      final m = matchSpecRate(veo.sublist(0, 3), const OutputSpec(size: '480p'));
      expect(m.matched, isFalse);
      expect(m.price, 0.0);
    });

    test('an empty table matches nothing', () {
      expect(matchSpecRate(const [], OutputSpec.none).matched, isFalse);
    });

    group('a tier row prices the pixel sizes in its tier', () {
      // qwen-image, wan2.7-image and Seedream take free sizes, bill by tier
      // and echo the pixels they rendered: a table written in tiers has to
      // land on those pixels, or every free size is recorded as free.
      const wan = [
        SpecRate(size: '1K', price: 0.20),
        SpecRate(size: '2K', price: 0.40),
        SpecRate(size: '4K', price: 0.80),
      ];
      double priceOf(List<SpecRate> rates, String size) =>
          matchSpecRate(rates, OutputSpec(size: size)).price;

      test("upstream's recommended sizes land on the tier they are listed under", () {
        for (final size in ['1024x1024', '1280x1280', '1696x960', '960x1696', '1472x1104']) {
          expect(priceOf(wan, size), 0.20, reason: size);
        }
        for (final size in ['2048x2048', '2688x1536', '1536x2688', '2368x1728']) {
          expect(priceOf(wan, size), 0.40, reason: size);
        }
        for (final size in ['4096x4096', '4096x2304', '3072x4096']) {
          expect(priceOf(wan, size), 0.80, reason: size);
        }
      });

      test('only the tiers the table prices compete', () {
        const halves = [
          SpecRate(size: '1K', price: 0.20),
          SpecRate(size: '1.5K', price: 0.30),
          SpecRate(size: '2K', price: 0.40),
        ];
        // 1536² is the 1.5K tier's own area.
        expect(priceOf(halves, '1536x1536'), 0.30);
        expect(priceOf(wan, '1536x1536'), 0.40, reason: 'nearer 2K than 1K');
      });

      test('an exact pixel row beats the tier at the same specificity', () {
        const both = [
          SpecRate(size: '1K', price: 0.20),
          SpecRate(size: '1696x960', price: 0.25),
        ];
        expect(priceOf(both, '1696x960'), 0.25);
        expect(priceOf(both, '1024x1024'), 0.20);
      });

      test('a tier never prices a non-pixel spec, and a table without tiers is exact', () {
        expect(priceOf(wan, '720p'), 0.0);
        expect(matchSpecRate(veo, const OutputSpec(size: '1920x1080')).price, 0.10,
            reason: 'no tier rows: the catch-all');
      });
    });
  });

  group('SpecUsage.price', () {
    test('per second multiplies the requested seconds by the matched rate', () {
      final u = SpecUsage.price(
        unit: OutputUnit.second,
        rates: veo,
        spec: const OutputSpec(size: '1080p', seconds: 8),
        imageCount: 0,
      );
      expect(u.units, 8);
      expect(u.unitPrice, 0.30);
      expect(u.cost, closeTo(2.40, 1e-9));
    });

    test('per image counts what the response carried, not what was asked', () {
      final u = SpecUsage.price(
        unit: OutputUnit.image,
        rates: const [SpecRate(size: '2K', price: 0.06), SpecRate(price: 0.03)],
        spec: const OutputSpec(size: '2K'),
        imageCount: 4,
      );
      expect(u.units, 4);
      expect(u.cost, closeTo(0.24, 1e-9));
    });

    test('per clip is one whatever the request said', () {
      final u = SpecUsage.price(
        unit: OutputUnit.clip,
        rates: const [SpecRate(size: '1080p', seconds: 10, price: 1.2)],
        spec: const OutputSpec(size: '1080p', seconds: 10),
        imageCount: 0,
      );
      expect(u.units, 1);
      expect(u.cost, closeTo(1.2, 1e-9));
    });

    test('per second with no duration known counts zero and stays matched', () {
      // A family with no seconds parameter: the rate is right, the count is
      // not knowable. Zero here, and the editor's hint says to use `clip`.
      final u = SpecUsage.price(
        unit: OutputUnit.second,
        rates: veo,
        spec: const OutputSpec(size: '720p'),
        imageCount: 0,
      );
      expect(u.units, 0);
      expect(u.matched, isTrue);
    });

    test('the snapshot carries the spec and whether it was priced', () {
      final u = SpecUsage.price(
        unit: OutputUnit.image,
        rates: const [SpecRate(size: '1K', price: 0.03)],
        spec: const OutputSpec(size: '4K'),
        imageCount: 1,
      );
      final snapshot = u.toBilling().snapshot!;
      expect(snapshot.size, '4K');
      expect(snapshot.matched, isFalse);
      // What lands in the `output_spec` column, and what reads back out of it.
      expect(jsonDecode(snapshot.encode()), {'size': '4K', 'matched': false});
      expect(UsageSpecSnapshot.tryDecode(snapshot.encode())!.matched, isFalse);
    });
  });

  group('LLMService.specUsageFor', () {
    LLMModelConfig config(String mode, {OutputUnit unit = OutputUnit.image}) =>
        LLMModelConfig(
          modelId: 'm',
          channelType: 'openai-api-rest',
          endpoint: 'https://x',
          apiKey: 'k',
          billingMode: mode,
          outputUnit: unit,
          outputRates: veo,
        );

    test('is null for token- and request-billed groups', () {
      expect(LLMService.specUsageFor(config('token'), {'imageSize': '1K'}, const {}, imageCount: 1), isNull);
      expect(LLMService.specUsageFor(config('request'), {'imageSize': '1K'}, const {}, imageCount: 1), isNull);
    });

    test('a chat model on a per-image group that drew nothing costs nothing', () {
      final u = LLMService.specUsageFor(config('spec'), const {}, const {'prompt_tokens': 12}, imageCount: 0)!;
      expect(u.units, 0);
      expect(u.cost, 0);
    });

    test('a video submission is priced by the resolution and seconds requested', () {
      final u = LLMService.specUsageFor(
        config('spec', unit: OutputUnit.second),
        {'resolution': '1080p', 'aspectRatio': '16:9', 'seconds': '8', 'videoQuality': 'high'},
        const {'operation': 'submit'},
        imageCount: 0,
      )!;
      expect(u.unitPrice, 0.50);
      expect(u.units, 8);
      expect(u.spec.label, '1080p · high · 8s');
    });

    test('the provider\'s echoed size outranks the requested `auto`', () {
      final u = LLMService.specUsageFor(
        config('spec'),
        {'imageSize': 'auto'},
        const {'input_tokens': 10, 'output_size': '1536x1024'},
        imageCount: 1,
      )!;
      expect(u.spec.size, '1536x1024');
    });
  });

  group('PricingGroup round-trip', () {
    test('a spec-billed group survives toMap → fromMap with its table intact', () {
      final g = PricingGroup(
        name: 'Veo',
        billingMode: 'spec',
        outputUnit: OutputUnit.second,
        outputRates: veo,
      );
      final back = PricingGroup.fromMap({...g.toMap(includeId: false), 'id': 7});
      expect(back.id, 7);
      expect(back.isSpecBilled, isTrue);
      expect(back.outputUnit, OutputUnit.second);
      expect(back.outputRates.length, 4);
      expect(back.outputRates.first.quality, 'high');
      expect(back.outputRates.last.isCatchAll, isTrue);
      expect(back.outputRates.last.price, 0.10);
    });

    test('a row read from before v42 has the defaults and its mode untouched', () {
      final g = PricingGroup.fromMap({
        'id': 1,
        'name': 'Old',
        'billing_mode': 'request',
        'request_price': 0.02,
      });
      expect(g.billingMode, 'request');
      expect(g.outputUnit, OutputUnit.image);
      expect(g.outputRates, isEmpty);
    });

    test('malformed rate JSON is an empty table, not a crash', () {
      expect(SpecRate.decodeList('{not json'), isEmpty);
      expect(SpecRate.decodeList('{"a":1}'), isEmpty);
      expect(SpecRate.decodeList(null), isEmpty);
    });

    test('duplicate conditions are detectable for the editor', () {
      const a = SpecRate(size: '1K', price: 1);
      const b = SpecRate(size: '1K', price: 2);
      const c = SpecRate(size: '1K', quality: 'high', price: 2);
      expect(a.sameConditionsAs(b), isTrue);
      expect(a.sameConditionsAs(c), isFalse);
    });
  });
}
