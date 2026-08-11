import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:joycai_image_ai_toolkits/services/image_processing_service.dart';
import 'package:path/path.dart' as p;

/// Pins the format of what a crop/resize actually writes.
///
/// The bug this guards: `_runImageProcess` used to `encodePng` unconditionally,
/// so overwriting `photo.jpg` put PNG bytes in a file still named `.jpg`.
/// Viewers that sniff magic bytes hid it, which is exactly why it needs a test
/// rather than an eyeball.
void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('joycai_enc'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// A real 8×8 image on disk, in [format].
  String writeSource(String format) {
    final image = img.Image(width: 8, height: 8);
    img.fill(image, color: img.ColorRgb8(200, 100, 50));
    final path = p.join(tmp.path, 'src.$format');
    File(path).writeAsBytesSync(img.encodeNamedImage(path, image)!);
    return path;
  }

  for (final format in ['png', 'jpg', 'bmp']) {
    test('a $format target is encoded as $format', () async {
      final source = writeSource(format);
      final target = p.join(tmp.path, 'out.$format');

      final bytes = await ImageProcessingService().processImage(
        sourcePath: source,
        targetPath: target,
        width: 4,
        height: 4,
      );

      // Identified from the bytes, not from the name we gave it.
      final decoded = img.findFormatForData(bytes);
      expect(decoded, img.findFormatForData(File(source).readAsBytesSync()),
          reason: 'a .$format target must contain $format bytes');
      expect(img.decodeImage(bytes)?.width, 4);
    });
  }

  test('a format that cannot be encoded fails loudly instead of writing PNG',
      () async {
    // .avif is the case that actually occurs: AppConstants.isImageFile accepts
    // it, and `image` decodes but cannot encode it.
    final source = writeSource('png');

    expect(
      () => ImageProcessingService().processImage(
        sourcePath: source,
        targetPath: p.join(tmp.path, 'out.avif'),
        width: 4,
        height: 4,
      ),
      throwsA(isA<UnsupportedImageFormatException>()),
    );
  });

  test('saveImage refuses to clobber without being told to', () async {
    final target = p.join(tmp.path, 'existing.png');
    File(target).writeAsBytesSync([1, 2, 3]);

    expect(
      () => ImageProcessingService()
          .saveImage(bytes: img.encodePng(img.Image(width: 1, height: 1)),
              targetPath: target, allowOverwrite: false),
      throwsA(isA<FileSystemException>()),
    );

    // …and does when it is.
    await ImageProcessingService().saveImage(
      bytes: img.encodePng(img.Image(width: 1, height: 1)),
      targetPath: target,
      allowOverwrite: true,
    );
    expect(File(target).lengthSync(), greaterThan(3));
  });
}
