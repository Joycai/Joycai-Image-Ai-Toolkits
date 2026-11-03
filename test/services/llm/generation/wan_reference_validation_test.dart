import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:joycai_image_ai_toolkits/services/llm/generation/generation_validator.dart';
import 'package:joycai_image_ai_toolkits/services/llm/generation/wan_reference_validation.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

void main() {
  Uint8List png(int w, int h, {int channels = 3}) =>
      Uint8List.fromList(img.encodePng(img.Image(width: w, height: h, numChannels: channels)));
  test('valid non-grid dimensions and nine RGB references pass both surfaces', () async {
    for (final wire in ['dashscope-images-sync', 'dashscope-images-async']) {
      final schema = LLMDispatcher.generationSchemaFor(
        channelType: Vendors.dashscopeNative,
        modelId: 'wan2.7-image',
        wireProtocol: wire,
      );
      final bytes = png(241, 240);
      await validateGeneration(
        schema,
        [
          LLMMessage(
            role: LLMRole.user,
            content: 'edit',
            attachments: List.generate(9, (_) => LLMAttachment.fromBytes(bytes, 'image/png')),
          ),
        ],
        {'imageSize': '1000x1000'},
      );
    }
  });
  test('bad edges, ratio, alpha, type, corrupt bytes and excess bytes fail', () async {
    for (final bytes in [
      png(239, 240),
      png(8001, 240),
      png(1921, 240),
      png(240, 240, channels: 4),
      Uint8List.fromList(img.encodeGif(img.Image(width: 240, height: 240))),
      Uint8List(12),
      Uint8List(20 * 1024 * 1024 + 1),
    ]) {
      await expectLater(validateWanReference(bytes), throwsA(isA<LLMApiException>()));
    }
    await validateWanReference(png(1920, 240));
  });
}
