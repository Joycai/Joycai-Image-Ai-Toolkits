import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/constants.dart';

void main() {
  group('AppAspectRatio', () {
    test('fromString should return correct enum', () {
      expect(AppAspectRatio.fromString('1:1'), AppAspectRatio.r1_1);
      expect(AppAspectRatio.fromString('16:9'), AppAspectRatio.r16_9);
      expect(AppAspectRatio.fromString('unknown'), AppAspectRatio.notSet);
      expect(AppAspectRatio.fromString(null), AppAspectRatio.notSet);
    });

    test('value should be correct', () {
      expect(AppAspectRatio.r1_1.value, '1:1');
      expect(AppAspectRatio.notSet.value, 'not_set');
    });
  });

  group('AppResolution', () {
    test('fromString should return correct enum', () {
      expect(AppResolution.fromString('1K'), AppResolution.r1K);
      expect(AppResolution.fromString('4K'), AppResolution.r4K);
      expect(AppResolution.fromString('unknown'), AppResolution.r1K);
    });
  });

  group('BillingMode', () {
    test('fromString should return correct enum', () {
      expect(BillingMode.fromString('token'), BillingMode.token);
      expect(BillingMode.fromString('request'), BillingMode.request);
      expect(BillingMode.fromString('unknown'), BillingMode.token);
    });
  });

  group('ModelTag', () {
    test('fromString should return correct enum', () {
      expect(ModelTag.fromString('image'), ModelTag.image);
      expect(ModelTag.fromString('chat'), ModelTag.chat);
      expect(ModelTag.fromString('unknown'), ModelTag.chat);
    });
  });

  group('AppConstants', () {
    test('isImageFile should correctly identify images', () {
      expect(AppConstants.isImageFile('test.jpg'), true);
      expect(AppConstants.isImageFile('test.JPEG'), true);
      expect(AppConstants.isImageFile('test.png'), true);
      expect(AppConstants.isImageFile('test.webp'), true);
      expect(AppConstants.isImageFile('test.bmp'), true);
      expect(AppConstants.isImageFile('test.txt'), false);
      expect(AppConstants.isImageFile('test.mp4'), false);
    });
  });
}
