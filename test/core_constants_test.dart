import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/constants.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_capabilities.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_family.dart';

void main() {
  group('ModelFamilyClassifier', () {
    test('classifies Google families', () {
      expect(ModelFamilyClassifier.classify('veo-3.0'), ModelFamily.geminiVideo);
      expect(ModelFamilyClassifier.classify('imagen-4.0'), ModelFamily.geminiImagen);
      expect(ModelFamilyClassifier.classify('gemini-2.5-flash-image'), ModelFamily.geminiImage);
      expect(ModelFamilyClassifier.classify('gemini-2.5-pro'), ModelFamily.geminiChat);
    });

    test('classifies OpenAI families', () {
      expect(ModelFamilyClassifier.classify('gpt-image-1'), ModelFamily.openaiImage);
      expect(ModelFamilyClassifier.classify('gpt-4o'), ModelFamily.openaiChat);
      expect(ModelFamilyClassifier.classify('o3-mini'), ModelFamily.openaiChat);
      expect(ModelFamilyClassifier.classify('claude-3-opus'), ModelFamily.other);
    });

    test('infers tags consistently', () {
      expect(ModelFamilyClassifier.inferTag('veo-3.0'), 'video');
      expect(ModelFamilyClassifier.inferTag('gpt-image-1'), 'image');
      expect(ModelFamilyClassifier.inferTag('imagen-4.0'), 'image');
      expect(ModelFamilyClassifier.inferTag('gemini-2.5-pro'), 'multimodal');
      expect(ModelFamilyClassifier.inferTag('gpt-4o'), 'chat');
    });
  });

  group('ModelCapabilities', () {
    test('image families expose adapted parameters', () {
      final nano = ModelCapabilities.forModel('gemini-2.5-flash-image');
      expect(nano.isImageGenerator, true);
      expect(nano.imageParams.map((p) => p.key), containsAll(['aspectRatio', 'imageSize']));

      final openai = ModelCapabilities.forModel('gpt-image-1');
      expect(openai.imageParams.map((p) => p.key), containsAll(['imageSize', 'quality']));
    });

    test('chat models expose no image parameters', () {
      final chat = ModelCapabilities.forModel('gpt-4o');
      expect(chat.isImageGenerator, false);
      expect(chat.imageParams, isEmpty);
    });

    test('normalize falls back to default for invalid values', () {
      final spec = ModelCapabilities.forModel('gpt-image-1')
          .imageParams
          .firstWhere((p) => p.key == 'imageSize');
      expect(spec.normalize('4K'), spec.defaultValue); // 4K is a Gemini value
      expect(spec.normalize('1024x1024'), '1024x1024');
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
