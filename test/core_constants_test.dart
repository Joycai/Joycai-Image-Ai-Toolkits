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

    test('gpt-image-2 exposes the expanded 2K/4K size set', () {
      List<String> sizesFor(String modelId) => ModelCapabilities.forModel(modelId)
          .imageParams
          .firstWhere((p) => p.key == 'imageSize')
          .options
          .map((o) => o.value)
          .toList();

      final v2 = sizesFor('gpt-image-2');
      // The popular 2K / 4K sizes are only offered on v2.
      expect(v2, containsAll(['2048x2048', '3840x2160', '2160x3840']));
      // v1 must stay restricted to its documented size set.
      expect(sizesFor('gpt-image-1'), isNot(contains('3840x2160')));
    });

    test('nano Banana variants expose wider aspect-ratio sets', () {
      List<String> ratiosFor(String modelId) => ModelCapabilities.forModel(modelId)
          .imageParams
          .firstWhere((p) => p.key == 'aspectRatio')
          .options
          .map((o) => o.value)
          .toList();

      // Nano Banana Pro adds 21:9; it must not gain the extreme strip ratios.
      final pro = ratiosFor('gemini-3.1-pro-image');
      expect(pro, contains('21:9'));
      expect(pro, isNot(contains('1:8')));

      // Nano Banana 2 adds 21:9 plus the extreme panoramic / strip ratios.
      final v2 = ratiosFor('gemini-3.1-flash-image');
      expect(v2, containsAll(['21:9', '1:4', '4:1', '1:8', '8:1']));

      // The generic gemini-*-image table stays on the standard set.
      expect(ratiosFor('gemini-2.5-flash-image'), isNot(contains('21:9')));
    });

    test('chat models expose no image parameters', () {
      final chat = ModelCapabilities.forModel('gpt-4o');
      expect(chat.isImageGenerator, false);
      expect(chat.imageParams, isEmpty);
    });

    test('reference image support differs by family', () {
      // nanoBanana: supported, no enforced cap.
      final nano = ModelCapabilities.forModel('gemini-2.5-flash-image');
      expect(nano.supportsReferenceImages, true);
      expect(nano.maxReferenceImages, isNull);

      // Imagen: text-to-image only.
      final imagen = ModelCapabilities.forModel('imagen-4.0');
      expect(imagen.supportsReferenceImages, false);
      expect(imagen.maxReferenceImages, 0);

      // OpenAI image: supported up to 16.
      final openai = ModelCapabilities.forModel('gpt-image-1');
      expect(openai.supportsReferenceImages, true);
      expect(openai.maxReferenceImages, 16);
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
