import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/openai_images_protocol.dart';

/// Pins the request-shape rules of the OpenAI Images surface that the
/// endpoint answers with a 400 rather than a hint.
void main() {
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
