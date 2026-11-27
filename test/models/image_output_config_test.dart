import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/image_output_config.dart';

void main() {
  group('ImageOutputConfig', () {
    test('round-trips JSON and preserves unmodifiable params', () {
      final config = ImageOutputConfig(
        id: 'out_1',
        modelDbId: 42,
        modelIdFallback: 'gpt-image-2.6-sunburst',
        enabled: false,
        alias: '高清透明',
        params: const {'size': '1024x1536', 'background': 'transparent'},
        useBatch: true,
      );

      final json = config.toJson();
      final decoded = ImageOutputConfig.fromJson(json);

      expect(decoded, equals(config));
      expect(decoded.hashCode, equals(config.hashCode));
      expect(() => decoded.params['size'] = '1024x1024', throwsUnsupportedError);
    });

    test('fromJson defensively handles missing or loose types', () {
      final decoded = ImageOutputConfig.fromJson({
        'id': 123,
        'modelDbId': '7',
        'params': {'count': 2, 'ignored': null},
      });

      expect(decoded.id, '123');
      expect(decoded.modelDbId, 7);
      expect(decoded.enabled, isTrue);
      expect(decoded.alias, '');
      expect(decoded.useBatch, isFalse);
      expect(decoded.params, {'count': '2'});
    });

    test('copyWith clears nullable fields when explicitly passed null', () {
      final original = ImageOutputConfig(id: 'out_1', modelDbId: 5, modelIdFallback: 'gpt-image-2');
      final cleared = original.copyWith(modelDbId: null, enabled: false, alias: 'draft');
      expect(cleared.modelDbId, isNull);
      expect(cleared.modelIdFallback, 'gpt-image-2');
      expect(cleared.enabled, isFalse);
      expect(cleared.alias, 'draft');
    });
  });
}
