import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/image_size_rules.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_capabilities.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_family.dart';
import 'package:joycai_image_ai_toolkits/services/llm/output_spec.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendor_profile.dart' show WireProtocol;

/// Covers the gpt-image-2 size picker's ratio calculator: "16:9 at 3840"
/// has to come back as a size that passes all four of OpenAI's rules, with
/// the long edge corrected onto the 16-px grid rather than the user doing
/// that arithmetic themselves.
void main() {
  group('parseAspectRatio', () {
    test('reads a:b, and keeps the orientation the terms imply', () {
      expect(parseAspectRatio('16:9')!.longOverShort, closeTo(1.778, 0.001));
      expect(parseAspectRatio('16:9')!.portrait, isFalse);
      expect(parseAspectRatio('9:16')!.longOverShort, closeTo(1.778, 0.001));
      expect(parseAspectRatio('9:16')!.portrait, isTrue);
    });

    test('accepts x, × and / as separators, and a bare decimal', () {
      expect(parseAspectRatio('16x9')!.longOverShort, closeTo(1.778, 0.001));
      expect(parseAspectRatio('16×9')!.longOverShort, closeTo(1.778, 0.001));
      expect(parseAspectRatio('16/9')!.longOverShort, closeTo(1.778, 0.001));
      expect(parseAspectRatio('1.85')!.portrait, isFalse);
      expect(parseAspectRatio('0.5625')!.portrait, isTrue);
      expect(parseAspectRatio('0.5625')!.longOverShort, closeTo(1.778, 0.001));
    });

    test('rejects what it cannot read', () {
      for (final bad in ['', '  ', '16:', ':9', '0:9', '16:0', 'abc', '-2']) {
        expect(parseAspectRatio(bad), isNull, reason: bad);
      }
    });
  });

  group('formatAspectRatio', () {
    test('reduces to readable terms', () {
      expect(formatAspectRatio(3840, 2160), '16:9');
      expect(formatAspectRatio(2160, 3840), '9:16');
      expect(formatAspectRatio(1024, 1024), '1:1');
      expect(formatAspectRatio(1536, 1024), '3:2');
    });

    test('falls back to a decimal when the terms get unreadable', () {
      expect(formatAspectRatio(1000, 1234), '0.81');
    });
  });

  group('sizeFor (gpt-image-2)', () {
    (int, int) compute(String ratio, int longEdge) =>
        kOpenAIImage2SizeRules.sizeFor(parseAspectRatio(ratio)!, longEdge);

    test('hits the exact size when the ratio divides cleanly', () {
      expect(compute('16:9', 3840), (3840, 2160));
      expect(compute('9:16', 3840), (2160, 3840));
      expect(compute('1:1', 1024), (1024, 1024));
    });

    test('corrects the long edge onto the 16-px grid', () {
      expect(compute('16:9', 3838), (3840, 2160));
      // 3824 is the *nearer* multiple of 16 to 3830 (6px away, not 10).
      expect(compute('16:9', 3830), (3824, 2144));
    });

    test('walks the long edge down until the pixel cap is cleared', () {
      // 3840×3840 is 14.7 MP — nearly double the 8.29 MP ceiling. 2880² is
      // the largest square that fits under it.
      expect(compute('1:1', 3840), (2880, 2880));
    });

    test('walks the long edge up until the pixel floor is cleared', () {
      // 16:9 at 1024 is 0.6 MP, just under the 0.66 MP floor.
      expect(compute('16:9', 1024), (1088, 608));
    });

    test('every result that can be legal is legal', () {
      for (final ratio in ['1:1', '4:3', '3:2', '16:9', '21:9', '3:1', '9:16', '2:3']) {
        for (final long in [200, 1024, 1500, 2048, 3000, 3830, 3840]) {
          final (w, h) = compute(ratio, long);
          expect(kOpenAIImage2SizeRules.isValidSize('${w}x$h'), isTrue,
              reason: '$ratio @ $long → ${w}x$h');
        }
      }
    });

    test('a ratio no size can satisfy still returns the shape asked for', () {
      // Past 3:1 nothing is legal at any size, so the dialog shows the failing
      // rule rather than the button appearing to do nothing.
      final (w, h) = compute('4:1', 2048);
      expect(w / h, closeTo(4, 0.05));
      expect(kOpenAIImage2SizeRules.isValidSize('${w}x$h'), isFalse);
    });
  });

  group('per-endpoint rules', () {
    ParamSpec sizeSpec(String modelId) => ModelCapabilities.forModel(modelId)
        .imageParams
        .firstWhere((p) => p.key == 'imageSize');

    test('an endpoint with no edge ceiling has no edge rule to show', () {
      final keys = kDashscopeQwenSizeRules.check(1024, 1024).map((r) => r.labelKey);
      expect(keys, isNot(contains('sizeRuleMaxEdge')));
      expect(kOpenAIImage2SizeRules.check(1024, 1024).map((r) => r.labelKey),
          contains('sizeRuleMaxEdge'));
    });

    test('qwen takes the 8:1 strip gpt-image-2 refuses, inside its own area', () {
      final (w, h) = kDashscopeQwenSizeRules.sizeFor(parseAspectRatio('8:1')!, 2800);
      expect(kDashscopeQwenSizeRules.passes(w, h), isTrue, reason: '${w}x$h');
      expect(w / h, closeTo(8, 0.1));
      expect(kOpenAIImage2SizeRules.isValidSize('${w}x$h'), isFalse);
    });

    test('the calculator lands inside every dialect, whatever was typed', () {
      for (final rules in [
        kDashscopeQwenSizeRules,
        kDashscopeWanSizeRules,
        kDashscopeWanProSizeRules,
      ]) {
        for (final ratio in ['1:1', '4:3', '16:9', '21:9', '8:1', '9:16', '1:8']) {
          for (final long in [100, 1024, 2048, 4096, 20000]) {
            final (w, h) = rules.sizeFor(parseAspectRatio(ratio)!, long);
            expect(rules.passes(w, h), isTrue, reason: '$ratio @ $long → ${w}x$h');
          }
        }
      }
    });

    test('every pixel preset a table offers is one its own rules accept', () {
      // A preset the dialog would show with a red rule list — or that the
      // spec would normalize away the moment it was picked.
      for (final id in [
        'gpt-image-2',
        'qwen-image-3.0',
        'qwen-image-edit-plus',
        'wan2.7-image',
        'wan2.7-image-pro',
      ]) {
        final spec = sizeSpec(id);
        expect(spec.control, ParamControl.customSize, reason: id);
        for (final o in spec.options) {
          if (!o.value.contains('x')) continue;
          expect(spec.sizeRules!.isValidSize(o.value), isTrue, reason: '$id ${o.value}');
        }
      }
    });

    test('4K — keyword and area — is pro only', () {
      final base = sizeSpec('wan2.7-image');
      final pro = sizeSpec('wan2.7-image-pro');
      expect(base.isValid('4K'), isFalse);
      expect(pro.isValid('4K'), isTrue);
      expect(base.isValid('4096x2304'), isFalse);
      expect(pro.isValid('4096x2304'), isTrue);
      // A size left over from another model falls back rather than travelling.
      expect(base.normalize('4096x2304'), 'not_set');
    });

    test('first-generation qwen text-to-image stays a closed list', () {
      for (final id in ['qwen-image', 'qwen-image-plus', 'qwen-image-max-2026-01-01']) {
        final spec = sizeSpec(id);
        expect(spec.control, ParamControl.dropdown, reason: id);
        expect(spec.sizeRules, isNull);
        expect(spec.isValid('1024x1024'), isFalse);
        expect(spec.isValid('not_set'), isFalse);
      }
      // The edit models that share the suffix are free-size.
      expect(sizeSpec('qwen-image-edit-max').control, ParamControl.customSize);
    });

    test('first-generation qwen text-to-image takes no reference images', () {
      for (final id in ['qwen-image', 'qwen-image-plus', 'qwen-image-max']) {
        expect(ModelCapabilities.forModel(id).supportsReferenceImages, isFalse, reason: id);
      }
      expect(ModelCapabilities.forModel('qwen-image-edit-max').maxReferenceImages, 3);
    });

    test('edit-max / plus bound each edge, not only the area', () {
      // The docs: "宽度和高度的取值范围为 512 至 2048 像素". Area rules alone let
      // 4096x512 (an edge twice the ceiling) and 1024x256 through.
      final spec = sizeSpec('qwen-image-edit-plus');
      expect(spec.sizeRules, kDashscopeQwenEditSizeRules);
      for (final bad in ['4096x512', '1024x256', '2064x1024']) {
        expect(spec.isValid(bad), isFalse, reason: bad);
      }
      expect(kDashscopeQwenSizeRules.isValidSize('4096x512'), isTrue,
          reason: 'what the shared area rules used to let through');
      expect(spec.isValid('2048x512'), isTrue);
      // The calculator stays inside the edges too.
      final (w, h) = kDashscopeQwenEditSizeRules.sizeFor(parseAspectRatio('4:1')!, 4096);
      expect(kDashscopeQwenEditSizeRules.passes(w, h), isTrue, reason: '${w}x$h');
    });

    test('an unidentified DashScope model gets the box every family accepts', () {
      final spec = ModelCapabilities.forProtocol(WireProtocol.dashscopeImagesSync)
          .imageParams
          .firstWhere((p) => p.key == 'imageSize');
      expect(spec.sizeRules, kDashscopeCommonSizeRules);
      for (final o in spec.options) {
        final wxh = parseWxH(o.value);
        if (wxh == null) continue;
        for (final rules in [
          kDashscopeQwenSizeRules,
          kDashscopeQwenEditSizeRules,
          kDashscopeWanSizeRules,
          kDashscopeWanProSizeRules,
        ]) {
          expect(rules.passes(wxh.width, wxh.height), isTrue, reason: o.value);
        }
      }
    });

    test('every customSize spec declares its rules', () {
      // The dialog reads them unconditionally; a spec without them would
      // accept sizes in the dialog that ParamSpec.isValid then discards.
      final tables = [
        ...ModelCapabilities.idRoutedTables,
        for (final f in ModelFamily.values) ModelCapabilities.forFamily(f),
        for (final p in WireProtocol.values) ModelCapabilities.forProtocol(p),
      ];
      for (final t in tables) {
        for (final p in [...t.imageParams, ...t.videoParams]) {
          if (p.control == ParamControl.customSize) {
            expect(p.sizeRules, isNotNull, reason: p.key);
          }
        }
      }
    });

    test('any spelling of a size is a size; an absurd edge is not', () {
      expect(kDashscopeQwenSizeRules.isValidSize('1536*1024'), isTrue);
      expect(kDashscopeQwenSizeRules.isValidSize('1536 X 1024'), isTrue);
      // Big enough that the int area product would wrap.
      expect(kDashscopeQwenSizeRules.isValidSize('4294967296x4294967296'), isFalse);
    });

    test('the pixel row never contradicts its verdict', () {
      const floor = 768 * 768;
      const ceiling = 2048 * 2048;
      // Just under the floor, just over the ceiling, and both bounds exactly.
      expect(formatPixelRange(589568, floor, ceiling),
          (value: '0.58', min: '0.59', max: '4.19'));
      expect(formatPixelRange(4227072, floor, ceiling).value, '4.23');
      expect(formatPixelRange(4194305, floor, ceiling).value, '4.20');
      expect(formatPixelRange(floor, floor, ceiling).value, '0.59');
      expect(formatPixelRange(ceiling, floor, ceiling).value, '4.19');
      // gpt-image-2's floor rounds up past a passing value: it is held inside.
      expect(formatPixelRange(655360, 655360, 8294400),
          (value: '0.66', min: '0.66', max: '8.29'));
    });
  });
}
