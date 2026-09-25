import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_capabilities.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_family.dart';
import 'package:joycai_image_ai_toolkits/services/llm/output_spec.dart';

/// Layer 3 for Seedream (docs/api/volcengine-ark.md): which ids are Seedream,
/// which generation each names, and what each generation's table offers.
void main() {
  List<String> keysOf(ModelCapabilities caps) => [for (final p in caps.imageParams) p.key];
  ParamSpec spec(ModelCapabilities caps, String key) =>
      caps.imageParams.firstWhere((p) => p.key == key);
  List<String> optionsOf(ModelCapabilities caps, String key) => [
    for (final o in spec(caps, key).options) o.value,
  ];

  group('classification', () {
    const seedreamIds = [
      'doubao-seedream-5-0-pro-260628',
      'doubao-seedream-5-0-lite-260128',
      'doubao-seedream-5-0-260128',
      'doubao-seedream-5.0-pro',
      'doubao-seedream-5.0-lite',
      'doubao-seedream-4-5-251128',
      'doubao-seedream-4-0-250828',
      'doubao-seedream-3-0-t2i-250415',
      'Doubao-Seedream-4-0-250828',
    ];

    test('every spelling is the Seedream image family, tagged image', () {
      for (final id in seedreamIds) {
        expect(ModelFamilyClassifier.classify(id), ModelFamily.seedreamImage, reason: id);
        expect(ModelFamilyClassifier.inferTag(id), 'image', reason: id);
      }
    });

    test('Seedance (the video line) and Doubao chat are not claimed', () {
      expect(ModelFamilyClassifier.classify('doubao-seed-1-6-250615'), ModelFamily.other);
      expect(
        ModelFamilyClassifier.classify('doubao-seedance-1-0-pro-250528'),
        isNot(ModelFamily.seedreamImage),
      );
    });

    test('the version reads the same through `-` and `.`, never the date', () {
      expect(ModelFamilyClassifier.seedreamVersion('doubao-seedream-5-0-pro-260628'), (5, 0));
      expect(ModelFamilyClassifier.seedreamVersion('doubao-seedream-5.0-lite'), (5, 0));
      expect(ModelFamilyClassifier.seedreamVersion('doubao-seedream-4-5-251128'), (4, 5));
      expect(ModelFamilyClassifier.seedreamVersion('doubao-seedream-4-0-250828'), (4, 0));
      expect(ModelFamilyClassifier.seedreamVersion('doubao-seedream-3-0-t2i-250415'), (3, 0));
      // A date straight after the major is not a minor.
      expect(ModelFamilyClassifier.seedreamVersion('doubao-seedream-4-250828'), (4, 0));
      expect(ModelFamilyClassifier.seedreamVersion('my-seedream'), isNull);
    });

    test('pro is told apart from the three spellings of lite', () {
      expect(ModelFamilyClassifier.isSeedreamPro('doubao-seedream-5-0-pro-260628'), isTrue);
      expect(ModelFamilyClassifier.isSeedreamPro('doubao-seedream-5.0-pro'), isTrue);
      for (final lite in [
        'doubao-seedream-5-0-lite-260128',
        'doubao-seedream-5-0-260128',
        'doubao-seedream-5.0-lite',
      ]) {
        expect(ModelFamilyClassifier.isSeedreamPro(lite), isFalse, reason: lite);
      }
    });
  });

  group('tables per generation', () {
    test('5.0 pro: task modes, auto/1K/1.5K/2K, format, fast mode, no groups', () {
      for (final id in ['doubao-seedream-5-0-pro-260628', 'doubao-seedream-5.0-pro']) {
        final caps = ModelCapabilities.forModel(id);
        expect(keysOf(caps), [
          'imageTask',
          'imageSize',
          'aspectRatio',
          'outputFormat',
          'optimizeMode',
          'watermark',
        ], reason: id);
        expect(optionsOf(caps, 'imageTask'), ['generate', 'layers', 'transparent']);
        // `not_set` is the only way to layer decomposition's `auto` — the
        // source's own size — and it keeps the price under 2.61 MP where a
        // forced 2K would double it (docs/api/volcengine-ark.md §6).
        expect(optionsOf(caps, 'imageSize'), ['not_set', '1K', '1.5K', '2K']);
        // 2K stays the default: a tier-priced fee group can match it.
        expect(spec(caps, 'imageSize').defaultValue, '2K');
        expect(caps.maxReferenceImages, 10);
      }
    });

    test('5.0 lite: 2K/3K/4K, groups, format, web search', () {
      for (final id in [
        'doubao-seedream-5-0-lite-260128',
        'doubao-seedream-5-0-260128',
        'doubao-seedream-5.0-lite',
      ]) {
        final caps = ModelCapabilities.forModel(id);
        expect(keysOf(caps), [
          'imageSize',
          'aspectRatio',
          'maxImages',
          'outputFormat',
          'webSearch',
          'watermark',
        ], reason: id);
        expect(optionsOf(caps, 'imageSize'), ['2K', '3K', '4K']);
        expect(caps.maxReferenceImages, 14);
      }
    });

    test('4.5 and 4.0 have no format control; only 4.0 has fast mode', () {
      final c45 = ModelCapabilities.forModel('doubao-seedream-4-5-251128');
      expect(keysOf(c45), ['imageSize', 'aspectRatio', 'maxImages', 'watermark']);
      expect(optionsOf(c45, 'imageSize'), ['2K', '4K']);

      final c40 = ModelCapabilities.forModel('doubao-seedream-4-0-250828');
      expect(keysOf(c40), ['imageSize', 'aspectRatio', 'maxImages', 'optimizeMode', 'watermark']);
      expect(optionsOf(c40, 'imageSize'), ['1K', '2K', '4K']);
    });

    test('3.0 takes no references; an unreadable id gets the generic table', () {
      final c30 = ModelCapabilities.forModel('doubao-seedream-3-0-t2i-250415');
      expect(c30.maxReferenceImages, 0);
      expect(keysOf(c30), ['aspectRatio', 'watermark']);

      final generic = ModelCapabilities.forModel('relay-seedream-latest');
      expect(optionsOf(generic, 'imageSize'), ['not_set', '2K', '4K']);
      expect(spec(generic, 'imageSize').defaultValue, 'not_set');
      expect(identical(generic, ModelCapabilities.forFamily(ModelFamily.seedreamImage)), isTrue);
    });

    test('every table: watermark off by default, image generator, long run', () {
      for (final id in _allTableIds) {
        final caps = ModelCapabilities.forModel(id);
        expect(caps.isImageGenerator, isTrue, reason: id);
        expect(caps.longRunning, isTrue, reason: id);
        expect(spec(caps, 'watermark').defaultValue, 'off', reason: id);
        expect(spec(caps, 'aspectRatio').defaultValue, 'not_set', reason: id);
        for (final p in caps.imageParams) {
          expect(p.isValid(p.defaultValue), isTrue, reason: '$id ${p.key}');
        }
      }
    });
  });

  group('tier × ratio pixels', () {
    // The documented total-pixel window per generation (§3.2); every mapped
    // size must fall inside it or the request is a guaranteed 400.
    const windows = {
      'doubao-seedream-5-0-pro-260628': (921600, 4624220),
      'doubao-seedream-5-0-lite-260128': (3686400, 16777216),
      'doubao-seedream-4-5-251128': (3686400, 16777216),
      'doubao-seedream-4-0-250828': (921600, 16777216),
      // 3.0 t2i: [512x512, 2048x2048].
      'doubao-seedream-3-0-t2i-250415': (262144, 4194304),
    };

    test('every tier the control offers maps every ratio it offers', () {
      for (final id in _allTableIds) {
        final caps = ModelCapabilities.forModel(id);
        final ratios = optionsOf(caps, 'aspectRatio').where((r) => r != 'not_set').toList();
        final tiers = caps.imageParams.any((p) => p.key == 'imageSize')
            ? optionsOf(caps, 'imageSize').where((t) => t != 'not_set')
            : caps.tierPixelSizes.keys;
        for (final tier in tiers) {
          final table = caps.tierPixelSizes[tier];
          expect(table, isNotNull, reason: '$id $tier');
          expect(table!.keys.toSet(), ratios.toSet(), reason: '$id $tier');
        }
      }
    });

    test('the first tier listed is upstream\'s default', () {
      // A ratio chosen with the tier left unset is looked up under the first
      // tier, so it must be the one upstream draws when `size` names none:
      // 2K for every generation that has tiers (§1), 3.0's only tier.
      const defaults = {
        'doubao-seedream-5-0-pro-260628': '2K',
        'doubao-seedream-5-0-lite-260128': '2K',
        'doubao-seedream-4-5-251128': '2K',
        'doubao-seedream-4-0-250828': '2K',
        'doubao-seedream-3-0-t2i-250415': '1K',
        'relay-seedream-latest': '2K',
      };
      expect(defaults.keys.toSet(), _allTableIds.toSet());
      defaults.forEach((id, tier) {
        expect(ModelCapabilities.forModel(id).tierPixelSizes.keys.first, tier, reason: id);
      });
    });

    test('mapped pixels sit inside the documented window and ratio', () {
      windows.forEach((id, window) {
        final caps = ModelCapabilities.forModel(id);
        caps.tierPixelSizes.forEach((tier, table) {
          table.forEach((ratio, size) {
            final wxh = parseWxH(size)!;
            final area = wxh.width * wxh.height;
            expect(area, inInclusiveRange(window.$1, window.$2), reason: '$id $tier $ratio $size');
            final parts = ratio.split(':').map(int.parse).toList();
            final want = parts[0] / parts[1];
            final got = wxh.width / wxh.height;
            expect((got - want).abs() / want, lessThan(0.05), reason: '$id $tier $ratio $size');
          });
        });
      });
    });
  });
}

const _allTableIds = [
  'doubao-seedream-5-0-pro-260628',
  'doubao-seedream-5-0-lite-260128',
  'doubao-seedream-4-5-251128',
  'doubao-seedream-4-0-250828',
  'doubao-seedream-3-0-t2i-250415',
  'relay-seedream-latest',
];
