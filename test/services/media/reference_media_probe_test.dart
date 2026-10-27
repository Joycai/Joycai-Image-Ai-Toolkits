import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:joycai_image_ai_toolkits/services/media/reference_media_probe.dart';

void main() {
  test('reads actual H264/AAC, PCM WAV and MPEG Layer III fixtures', () async {
    for (final (name, mime) in [
      ('three_seconds.mp4', 'video/mp4'),
      ('three_seconds.wav', 'audio/wav'),
      ('three_seconds.mp3', 'audio/mpeg'),
    ]) {
      final bytes = await File('test/support/reference_media/$name').readAsBytes();
      final info = probeReferenceMedia(bytes, video: name.endsWith('.mp4'));
      expect(info.mime, mime);
      expect(info.seconds, closeTo(3, 0.1));
      if (name.endsWith('.mp4')) {
        expect(info.width, 256);
        expect(info.height, 256);
        expect(info.fps, 24);
      }
      expect(
        () =>
            probeReferenceMedia(bytes.sublist(0, bytes.length ~/ 2), video: name.endsWith('.mp4')),
        throwsFormatException,
      );
    }
  });
  test('image format comes from bytes, unsupported image formats are rejected', () async {
    final image = img.Image(width: 320, height: 256);
    final info = await probeReferenceImage(Uint8List.fromList(img.encodeJpg(image)));
    expect(info.mime, 'image/jpeg');
    expect(info.width, 320);
    expect(info.height, 256);
    await expectLater(
      probeReferenceImage(Uint8List.fromList(img.encodeGif(image))),
      throwsFormatException,
    );
  });
  test('unsupported video codec is rejected before transport', () async {
    final bytes = await File('test/support/reference_media/three_seconds.mp4').readAsBytes();
    // Mutate the actual sample entry rather than mocking a probe result.
    final copy = Uint8List.fromList(bytes);
    for (var i = 4; i < copy.length - 4; i++) {
      if (String.fromCharCodes(copy.sublist(i, i + 4)) == 'avc1') {
        copy.setRange(i, i + 4, 'vp09'.codeUnits);
      }
    }
    expect(() => probeReferenceMedia(copy, video: true), throwsFormatException);
  });
}
