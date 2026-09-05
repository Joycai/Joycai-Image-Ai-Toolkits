import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/openai_images_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';

/// Pins the request-shape rules of the OpenAI Images surface that the
/// endpoint answers with a 400 rather than a hint.
void main() {
  group('multipart image parts', () {
    final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(32, 0)]);

    test('carry the Content-Type of their bytes, never octet-stream', () {
      // A relay translating the multipart edit into its own JSON request
      // copied the part's type into a data URL and rejected
      // 'application/octet-stream' — the default when no type is given.
      final part = imageMultipartFile('image', jpeg,
          declaredMime: 'image/jpeg', baseName: 'image_0');
      expect(part.contentType.mimeType, 'image/jpeg');
      expect(part.filename, 'image_0.jpg');
      expect(part.field, 'image');
    });

    test('the bytes decide the type when the declaration disagrees', () {
      final part = imageMultipartFile('image[]', jpeg,
          declaredMime: 'image/png', baseName: 'image_1');
      expect(part.contentType.mimeType, 'image/jpeg');
      expect(part.filename, 'image_1.jpg');
    });
  });

  group('edit field name', () {
    test('a single source image travels as `image`', () {
      // The singular is what every edit endpoint accepts; older surfaces
      // (dall-e-2, relays built on it) know nothing else, and `image[]` for
      // one picture was a 400 there.
      expect(openaiImageEditFieldName(1), 'image');
    });

    test('several source images travel as `image[]`', () {
      expect(openaiImageEditFieldName(2), 'image[]');
      expect(openaiImageEditFieldName(16), 'image[]');
    });
  });
}
