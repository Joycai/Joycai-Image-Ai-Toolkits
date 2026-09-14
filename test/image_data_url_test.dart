import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';

/// B11: every inline input image is labelled by its bytes, not by the file
/// extension the attachment's declared type was derived from.
void main() {
  final jpeg = Uint8List.fromList(
      [0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10, 0x4A, 0x46, 0x49, 0x46, 0, 1]);

  test('JPEG bytes in a file named .png travel as image/jpeg', () {
    expect(imageDataUrl(jpeg, 'image/png'), startsWith('data:image/jpeg;base64,'));
  });

  test('unrecognised bytes keep the declared type', () {
    final unknown = Uint8List.fromList(List.filled(16, 7));
    expect(imageDataUrl(unknown, 'image/heic'),
        startsWith('data:image/heic;base64,'));
  });
}
