import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/generation/generation_schema.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_capabilities.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

void main() {
  for (final (id, profile, ratios, sizes, thinking) in [
    (
      'gemini-3.1-flash-image',
      'geminiImageV2',
      14,
      ['not_set', '512', '1K', '2K', '4K'],
      ['not_set', 'minimal', 'high'],
    ),
    ('gemini-3-pro-image', 'geminiImagePro', 10, ['not_set', '1K', '2K', '4K'], <String>[]),
  ]) {
    test('$id and preview aliases resolve the complete image profile', () {
      for (final name in [id, '$id-preview', 'models/$id', 'google/$id', id.toUpperCase()]) {
        final caps = ModelCapabilities.forModel(name);
        expect(caps.profileId, profile);
        expect(caps.maxReferenceImages, 14);
        final aspect = caps.imageParams.firstWhere((p) => p.key == 'aspectRatio');
        expect(aspect.options.where((o) => o.value != 'not_set'), hasLength(ratios));
        expect(aspect.isValid('21:9'), isTrue);
        expect(
          caps.imageParams.firstWhere((p) => p.key == 'imageSize').options.map((o) => o.value),
          sizes,
        );
        final levels = caps.imageParams.where((p) => p.key == 'thinkingLevel').firstOrNull;
        expect(levels?.options.map((o) => o.value).toList() ?? [], thinking);
      }
    });

    test('$id validates reference limits and model-specific parameter values', () {
      final schema = LLMDispatcher.generationSchemaFor(
        channelType: Vendors.officialGoogle,
        modelId: id,
      );
      final defaults = schema.readLegacy({});
      final refs = List.generate(
        14,
        (i) => GenerationMedia(GenerationMediaRole.reference, '$i.png'),
      );
      expect(schema.validate(defaults, refs), isEmpty);
      expect(
        schema
            .validate(defaults, [
              ...refs,
              const GenerationMedia(GenerationMediaRole.reference, 'extra.png'),
            ])
            .map((d) => d.code),
        contains('tooManyReferences'),
      );
      expect(
        schema
            .validate(schema.readLegacy({'imageSize': id.contains('flash') ? '0.5K' : '512'}), [])
            .map((d) => d.code),
        contains('invalidParameter'),
      );
      if (thinking.isNotEmpty) {
        expect(
          schema.validate(schema.readLegacy({'thinkingLevel': 'medium'}), []).map((d) => d.code),
          contains('invalidParameter'),
        );
      }
    });
  }
}
