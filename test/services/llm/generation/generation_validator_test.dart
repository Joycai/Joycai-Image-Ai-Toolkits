import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:joycai_image_ai_toolkits/services/llm/generation/generation_validator.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

void main() {
  final schema = LLMDispatcher.generationSchemaFor(
    channelType: Vendors.volcengineArk,
    modelId: 'doubao-seedream-5-0-pro-260628',
    tag: 'image',
  );
  List<LLMMessage> history(Uint8List bytes) => [
    LLMMessage(
      role: LLMRole.user,
      content: 'cat',
      attachments: [LLMAttachment.fromBytes(bytes, 'image/png')],
    ),
  ];
  test('transparent editing checks actual alpha metadata and returns visible fixed PNG', () async {
    final rgba = Uint8List.fromList(img.encodePng(img.Image(width: 2, height: 2, numChannels: 4)));
    final options = await validateGeneration(schema, history(rgba), {
      'imageTask': 'transparent',
      'outputFormat': 'jpeg',
    });
    expect(options!['outputFormat'], 'png');
    final rgb = Uint8List.fromList(img.encodePng(img.Image(width: 2, height: 2, numChannels: 3)));
    await expectLater(
      validateGeneration(schema, history(rgb), {'imageTask': 'transparent'}),
      throwsA(
        isA<LLMApiException>().having(
          (e) => e.toString(),
          'reason',
          contains('alphaSourceRequired'),
        ),
      ),
    );
  });
  test(
    'layers exclude unused ratio and explicit unreadable media blocks before encoding',
    () async {
      final bytes = Uint8List.fromList(img.encodePng(img.Image(width: 2, height: 2)));
      final options = await validateGeneration(schema, history(bytes), {
        'imageTask': 'layers',
        'aspectRatio': '16:9',
      });
      expect(options, isNot(contains('aspectRatio')));
      await expectLater(
        validateGeneration(schema, history(Uint8List(0)), {'imageTask': 'layers'}),
        throwsA(
          isA<LLMApiException>().having((e) => e.toString(), 'reason', contains('unreadableMedia')),
        ),
      );
    },
  );
}
