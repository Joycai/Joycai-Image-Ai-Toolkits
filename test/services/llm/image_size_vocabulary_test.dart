import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/image_size_rules.dart';
import 'package:joycai_image_ai_toolkits/services/llm/image_size_vocabulary.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_capabilities.dart';

/// Pins the size picker's arithmetic (`A1c`): what a (ratio, tier) cell is on
/// each model, which tier a size is on, and the one-click fixes. The widget
/// only draws these answers.
void main() {
  ParamSpec sizeSpec(String modelId) =>
      ModelCapabilities.forModel(modelId).imageParams.firstWhere((p) => p.key == 'imageSize');

  (int, int) cell(String modelId, String ratio, String tier) {
    final spec = sizeSpec(modelId);
    return tierSize(parseAspectRatio(ratio)!, tier, spec.sizeRules!, spec.sizeVocabulary!);
  }

  group('tierSize', () {
    test("wan takes upstream's table, turned for portrait", () {
      expect(cell('wan2.7-image-pro', '16:9', '1K'), (1696, 960));
      expect(cell('wan2.7-image-pro', '16:9', '2K'), (2688, 1536));
      expect(cell('wan2.7-image-pro', '16:9', '4K'), (4096, 2304));
      expect(cell('wan2.7-image-pro', '9:16', '2K'), (1536, 2688));
      expect(cell('wan2.7-image-pro', '3:4', '4K'), (3072, 4096));
    });

    test('a wan square submits the keyword itself, any other cell pixels', () {
      final spec = sizeSpec('wan2.7-image');
      final rules = spec.sizeRules!;
      final vocab = spec.sizeVocabulary!;
      expect(tierValue(parseAspectRatio('1:1')!, '2K', rules, vocab), '2K');
      expect(tierValue(parseAspectRatio('4:3')!, '2K', rules, vocab), '2368x1728');
    });

    test("qwen's tier is an area: the exact ratio at or under it", () {
      // `30c`: 4:3 at 1K is 1152×864 (1.00 MP), not a size past the 1K tier.
      expect(cell('qwen-image-3.0', '4:3', '1K'), (1152, 864));
      expect(cell('qwen-image-3.0', '1:1', '1K'), (1024, 1024));
      expect(cell('qwen-image-3.0', '1:1', '2K'), (2048, 2048));
    });

    test("gpt's 4K is the largest legal size at the ratio", () {
      // `30d`: 16:9 lands exactly on the cap; a 4K square has to come down.
      expect(cell('gpt-image-2', '16:9', '4K'), (3840, 2160));
      expect(cell('gpt-image-2', '1:1', '4K'), (2880, 2880));
    });

    test('every cell every model offers is legal on that model', () {
      for (final id in ['gpt-image-2', 'qwen-image-3.0', 'qwen-image-edit-plus', 'wan2.7-image', 'wan2.7-image-pro']) {
        final spec = sizeSpec(id);
        final rules = spec.sizeRules!;
        final vocab = spec.sizeVocabulary!;
        for (final r in vocab.ratios) {
          for (final t in vocab.tiers) {
            final (w, h) = tierSize(parseAspectRatio(r)!, t, rules, vocab);
            expect(rules.passes(w, h), isTrue, reason: '$id $r $t → ${w}x$h');
          }
        }
      }
    });
  });

  group('tierOfSize', () {
    test('a cell reads back as its tier; anything else is custom', () {
      final spec = sizeSpec('wan2.7-image-pro');
      final rules = spec.sizeRules!;
      final vocab = spec.sizeVocabulary!;
      expect(tierOfSize(2688, 1536, null, rules, vocab), '2K');
      expect(tierOfSize(1536, 2688, null, rules, vocab), '2K');
      expect(tierOfSize(2000, 800, null, rules, vocab), isNull);
    });
  });

  group('fixFor', () {
    test('past the proportion limit: keep the smaller edge, press the other back', () {
      // `30f`: 4000×400 is 10:1 on wan's 8:1 — 「改成 3200 × 400」.
      final fix = fixFor(4000, 400, kDashscopeWanSizeRules);
      expect(fix.size, (3200, 400));
      expect(fix.label, '3200 × 400');
    });

    test('an area violation keeps the proportion', () {
      final fix = fixFor(3840, 3840, kOpenAIImage2SizeRules);
      final (w, h) = fix.size!;
      expect(w, h);
      expect(kOpenAIImage2SizeRules.passes(w, h), isTrue);
    });
  });

  group('ratioLabel', () {
    test("a chip's own label, else two decimals — never forced into terms", () {
      const chips = ['1:1', '16:9', '9:16', '4:3', '3:4'];
      expect(ratioLabel(2688, 1536, chips: chips), '16:9');
      expect(ratioLabel(1536, 2688, chips: chips), '9:16');
      expect(ratioLabel(2000, 800, chips: chips), '2.50:1');
      expect(ratioLabel(320, 400, chips: chips), '0.80:1');
    });
  });

  group('SizeValue.parse', () {
    test('sorts a value into sentinel, keyword or pixels', () {
      const tiers = ['1K', '2K', '4K'];
      expect(SizeValue.parse('not_set', sentinel: 'not_set', tiers: tiers), isA<SizeSentinelValue>());
      expect(SizeValue.parse('2K', sentinel: 'not_set', tiers: tiers), isA<SizeTierValue>());
      final dims = SizeValue.parse('2688x1536', sentinel: 'not_set', tiers: tiers);
      expect(dims, isA<SizeDimsValue>());
      expect((dims as SizeDimsValue).wire, '2688x1536');
    });
  });

  test('the area reference is the square of the model ceiling', () {
    expect(areaReferenceEdge(kOpenAIImage2SizeRules), 2880);
    expect(areaReferenceEdge(kDashscopeWanProSizeRules), 4096);
    expect(areaReferenceEdge(kDashscopeQwenSizeRules), 2048);
  });
}
