import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/output_spec.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/openai_images_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';

/// The output spec is read off workbench parameters spelled by many
/// families and typed by hand into rate tables, so both sides normalise the
/// same way — otherwise `1k` in the table never prices `1K` on the request.
void main() {
  group('OutputSpec.from', () {
    test('images: size from imageSize, quality from quality', () {
      final s = OutputSpec.from({'imageSize': '2K', 'quality': 'High', 'aspectRatio': '1:1'});
      expect(s.size, '2K');
      expect(s.quality, 'high');
      expect(s.seconds, isNull);
    });

    test('video: size from resolution, quality from videoQuality, seconds parsed', () {
      final s = OutputSpec.from({'resolution': '1080p', 'videoQuality': 'standard', 'seconds': '8'});
      expect(s.size, '1080p');
      expect(s.quality, 'standard');
      expect(s.seconds, 8);
    });

    test('imageSize outranks resolution when both are present', () {
      final s = OutputSpec.from({'imageSize': '1K', 'resolution': '720p'});
      expect(s.size, '1K');
    });

    test('provider echoes in metadata outrank the request', () {
      final s = OutputSpec.from(
        {'imageSize': 'auto', 'quality': 'auto'},
        metadata: {'output_size': '1024x1536', 'output_quality': 'medium'},
      );
      expect(s.size, '1024x1536');
      expect(s.quality, 'medium');
    });

    test('"let the provider decide" markers carry no spec', () {
      for (final v in ['auto', 'not_set', 'adaptive', '', ' ']) {
        final s = OutputSpec.from({'imageSize': v, 'quality': v});
        expect(s.size, isNull, reason: 'size "$v"');
        expect(s.quality, isNull, reason: 'quality "$v"');
      }
      expect(OutputSpec.from(null).isEmpty, isTrue);
      expect(OutputSpec.from(const {}).isEmpty, isTrue);
    });
  });

  group('normalisation', () {
    test('K suffix is upper-cased, p suffix lower-cased', () {
      expect(OutputSpec.normalizeSize('1k'), '1K');
      expect(OutputSpec.normalizeSize('4K'), '4K');
      expect(OutputSpec.normalizeSize('768P'), '768p');
      expect(OutputSpec.normalizeSize('1080p'), '1080p');
    });

    test('pixel sizes collapse to WxH', () {
      expect(OutputSpec.normalizeSize('1024X1024'), '1024x1024');
      expect(OutputSpec.normalizeSize('1536 × 1024'), '1536x1024');
      expect(OutputSpec.normalizeSize(' 1024x1536 '), '1024x1536');
    });

    test('anything else is kept as typed, trimmed', () {
      expect(OutputSpec.normalizeSize(' hd '), 'hd');
    });

    test('seconds accept numbers, numeric strings and a trailing s; junk is null', () {
      expect(OutputSpec.normalizeSeconds(8), 8);
      expect(OutputSpec.normalizeSeconds(7.6), 8);
      expect(OutputSpec.normalizeSeconds('10'), 10);
      expect(OutputSpec.normalizeSeconds('10s'), 10);
      expect(OutputSpec.normalizeSeconds('0'), isNull);
      expect(OutputSpec.normalizeSeconds('long'), isNull);
      expect(OutputSpec.normalizeSeconds(null), isNull);
    });
  });

  group('WxH spellings (B9)', () {
    test('parseWxH reads x, X, * and ×, with whitespace', () {
      for (final s in ['1024x768', '1024X768', '1024*768', '1024×768', ' 1024 * 768 ']) {
        expect(parseWxH(s), (width: 1024, height: 768), reason: s);
      }
      expect(parseWxH('1K'), isNull);
      expect(parseWxH('0x768'), isNull);
      expect(parseWxH(null), isNull);
      expect(parseWxH(1024), isNull);
    });

    test('normalizeSize folds the DashScope * spelling into WxH', () {
      // A rate table typed as 1024x1024 must price a request that went out
      // as DashScope's 1024*1024.
      expect(OutputSpec.normalizeSize('1024*1024'), '1024x1024');
    });

    test('the OpenAI Images size keeps an explicit * size', () {
      // Only lowercase x used to match, so a size carried over from a
      // DashScope selection was dropped and the upstream default rendered.
      expect(OpenAIImagesProtocol.resolveImageSize({'imageSize': '1536*1024'}),
          '1536x1024');
      expect(OpenAIImagesProtocol.resolveImageSize({'imageSize': '1024X1536'}),
          '1024x1536');
    });

    test('the video size keeps an explicit * size', () {
      expect(resolveVideoSize({'size': '1280*720'}), '1280x720');
      expect(resolveVideoSize({'size': '720×1280'}), '720x1280');
    });
  });

  test('the label omits the dimensions that are absent', () {
    const s = OutputSpec(size: '720p', seconds: 5);
    expect(s.label, '720p · 5s');
    expect(OutputSpec.none.label, '');
  });

  group('the reported cost (xAI cost_in_usd_ticks)', () {
    test('ticks become dollars at 1e-10 each', () {
      expect(reportedCostFromTicks(600000000), {reportedCostKey: closeTo(0.06, 1e-12)});
      expect(reportedCostFromTicks('1100000000'), {reportedCostKey: closeTo(0.11, 1e-12)});
      // A reported zero is a reported figure, not an absence.
      expect(reportedCostFromTicks(0), {reportedCostKey: 0.0});
    });

    test('a block without a usable figure publishes nothing', () {
      expect(reportedCostFromTicks(null), isEmpty);
      expect(reportedCostFromTicks(-1), isEmpty);
      expect(reportedCostFromTicks('n/a'), isEmpty);
      expect(reportedCostFromTicks(double.nan), isEmpty);
      expect(reportedCostFromTicks(<String, Object>{}), isEmpty);
    });

    test('a usage block spread verbatim cannot carry the key in', () {
      // The billed figure is the app's conclusion, never the wire's: a relay
      // (or a vendor) naming a field the same must not set it.
      expect(upstreamUsage({'total_tokens': 3, reportedCostKey: 99}), {'total_tokens': 3});
      expect(upstreamUsage({'cost_in_usd_ticks': 5}), {'cost_in_usd_ticks': 5});
      expect(upstreamUsage(null), isEmpty);
      expect(upstreamUsage('usage'), isEmpty);
    });

    test('reportedCostEntry carries the figure alone, null without one', () {
      expect(reportedCostEntry({reportedCostKey: 0.06, 'x': 1}), {reportedCostKey: 0.06});
      expect(reportedCostEntry({'x': 1}), isNull);
      expect(reportedCostEntry(null), isNull);
    });

    test('reportedCostOf reads the key and nothing else, null when absent', () {
      expect(reportedCostOf({reportedCostKey: 0.07}), 0.07);
      expect(reportedCostOf({reportedCostKey: 0}), 0.0);
      expect(reportedCostOf({reportedCostKey: '0.05'}), 0.05);
      expect(reportedCostOf({'cost_in_usd_ticks': 700000000}), isNull);
      expect(reportedCostOf({reportedCostKey: -0.01}), isNull);
      expect(reportedCostOf({reportedCostKey: double.infinity}), isNull);
      expect(reportedCostOf(const {}), isNull);
      expect(reportedCostOf(null), isNull);
    });
  });
}
