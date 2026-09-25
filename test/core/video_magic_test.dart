import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/video_magic.dart';

/// B4: a downloaded video is named — and accepted — by its container
/// signature, never by the status code alone.
void main() {
  List<int> ftyp(String brand) => [0, 0, 0, 0x20, ...ascii.encode('ftyp'), ...ascii.encode(brand)];

  test('ISO base media is .mp4, QuickTime brand is .mov', () {
    expect(videoExtensionFromBytes(ftyp('isom')), '.mp4');
    expect(videoExtensionFromBytes(ftyp('mp42')), '.mp4');
    expect(videoExtensionFromBytes(ftyp('qt  ')), '.mov');
  });

  test('EBML magic is .webm', () {
    expect(videoExtensionFromBytes([0x1A, 0x45, 0xDF, 0xA3, 0x9F, 0x42]), '.webm');
  });

  test('an HTML error page or a JSON body is not a video', () {
    expect(videoExtensionFromBytes(utf8.encode('<!DOCTYPE html><html>')), isNull);
    expect(videoExtensionFromBytes(utf8.encode('{"error":"expired"}')), isNull);
    expect(videoExtensionFromBytes(const []), isNull);
  });
}
