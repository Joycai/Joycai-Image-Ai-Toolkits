import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:joycai_image_ai_toolkits/services/llm/image_compression.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';

/// Pins what a view-only attachment costs on the wire.
///
/// The bug this guards is not a crash: it is that the Prompt Assistant
/// re-sends every live attachment on every iteration of its tool loop, and
/// `compress` only ever fired above 3 MB and never resized — so three
/// reference photos meant ~8 MB uploaded a dozen times per turn, which is
/// what pushed the requests past the 120 s deadline. Nothing throws when
/// that regresses; the requests just quietly get slow again.
void main() {
  /// A deterministic photo-ish image: smooth gradients (so JPEG does well)
  /// with a little structure, at [width]×[height].
  img.Image gradient(int width, int height) {
    final image = img.Image(width: width, height: height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        image.setPixelRgb(x, y, (x * 255) ~/ width, (y * 255) ~/ height,
            ((x + y) * 255) ~/ (width + height));
      }
    }
    return image;
  }

  /// A deterministic image PNG cannot compress, for the cases that need a
  /// genuinely large file. A gradient is the wrong fixture there: PNG stores
  /// 4000×2000 of smooth ramp in ~200 KB, which is under every ceiling here.
  img.Image noise(int width, int height, [int seed = 20260825]) {
    final random = Random(seed);
    final image = img.Image(width: width, height: height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        image.setPixelRgb(
            x, y, random.nextInt(256), random.nextInt(256), random.nextInt(256));
      }
    }
    return image;
  }

  /// Photograph-shaped: smooth ramps carrying fine grain. PNG has to store
  /// the grain pixel by pixel (megabytes) while JPEG smooths it away
  /// (kilobytes) — which is exactly the asymmetry the byte ceiling exists to
  /// collect, and what a real 719×1244 reference photo costing 2.9 MB as PNG
  /// actually looks like.
  img.Image photo(int width, int height, [int seed = 4242]) {
    final random = Random(seed);
    final image = img.Image(width: width, height: height);
    int grain(int base) => (base + random.nextInt(25) - 12).clamp(0, 255);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        image.setPixelRgb(x, y, grain((x * 255) ~/ width),
            grain((y * 255) ~/ height), grain(((x + y) * 255) ~/ (width + height)));
      }
    }
    return image;
  }

  Uint8List png(img.Image image) => Uint8List.fromList(img.encodePng(image));

  ({int width, int height}) dimensionsOf(Uint8List bytes) {
    final decoded = img.decodeImage(bytes)!;
    return (width: decoded.width, height: decoded.height);
  }

  group('compressForViewing', () {
    test('caps the long edge of a landscape image and re-encodes as JPEG', () {
      final original = png(gradient(4000, 2000));

      final result = ImageCompressor.compressForViewing(original, 'image/png');

      expect(result.mimeType, 'image/jpeg');
      final size = dimensionsOf(result.bytes);
      expect(size.width, ImageCompressor.viewOnlyMaxLongEdge);
      // Aspect ratio survives: 4000×2000 is 2:1, so 1568 wide is 784 tall.
      expect(size.height, 784);
      expect(result.bytes.length, lessThan(original.length));
    });

    test('caps the long edge of a portrait image on the height', () {
      final original = png(gradient(1000, 3000));

      final result = ImageCompressor.compressForViewing(original, 'image/png');

      final size = dimensionsOf(result.bytes);
      expect(size.height, ImageCompressor.viewOnlyMaxLongEdge);
      expect(size.width, 523); // 1000 × (1568/3000), rounded
    });

    test('a small, already-cheap image is handed back untouched', () {
      // Within both ceilings: re-encoding it would cost quality for nothing.
      final original = png(gradient(400, 300));
      expect(original.length, lessThan(ImageCompressor.viewOnlyMaxBytes));

      final result = ImageCompressor.compressForViewing(original, 'image/png');

      expect(identical(result.bytes, original), isTrue);
      expect(result.mimeType, 'image/png');
    });

    test('an image within the pixel cap but over the byte cap is re-encoded '
        'at its original resolution', () {
      final original = png(photo(1200, 1200));
      expect(original.length, greaterThan(ImageCompressor.viewOnlyMaxBytes));

      final result = ImageCompressor.compressForViewing(original, 'image/png');

      expect(result.mimeType, 'image/jpeg');
      expect(dimensionsOf(result.bytes), (width: 1200, height: 1200));
      expect(result.bytes.length, lessThan(ImageCompressor.viewOnlyMaxBytes));
    });

    test('never returns more bytes than it was given', () {
      // Pure noise is the adversarial case: PNG cannot compress it and JPEG
      // may not either, so this is where the "re-encode came out bigger"
      // guard has to hold. Whether it shrinks or bails, it must not grow.
      // 900 is inside the pixel cap, so nothing is resized and the byte
      // comparison is the only thing standing between the model and a
      // request that got bigger.
      final original = png(noise(900, 900));

      final result = ImageCompressor.compressForViewing(original, 'image/png');

      expect(result.bytes.length, lessThanOrEqualTo(original.length));
    });

    test('a resize is taken even when the JPEG comes out larger', () {
      // A big, near-empty image: trivially small as PNG, but it still costs
      // its full several-thousand-token price at that resolution, so the
      // byte comparison must not veto the downscale. This is the case that
      // made the first version of the guard wrong.
      final flat = img.Image(width: 4000, height: 4000);
      img.fill(flat, color: img.ColorRgb8(120, 130, 140));
      final original = png(flat);

      final result = ImageCompressor.compressForViewing(original, 'image/png');

      expect(result.mimeType, 'image/jpeg');
      expect(dimensionsOf(result.bytes).width,
          ImageCompressor.viewOnlyMaxLongEdge);
    });

    test('bytes that are not an image at all come back unchanged', () {
      final garbage = Uint8List.fromList(List.filled(600 * 1024, 0x42));

      final result =
          ImageCompressor.compressForViewing(garbage, 'application/octet-stream');

      expect(identical(result.bytes, garbage), isTrue);
      expect(result.mimeType, 'application/octet-stream');
    });

    test('transparency is flattened onto white, not black', () {
      // A transparent PNG that has to be resized, so it takes the JPEG path.
      final image = img.Image(width: 2000, height: 1000, numChannels: 4);
      img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));
      // One opaque red square, so the image is not uniformly transparent.
      img.fillRect(image,
          x1: 0, y1: 0, x2: 99, y2: 99, color: img.ColorRgba8(255, 0, 0, 255));

      final result = ImageCompressor.compressForViewing(png(image), 'image/png');

      final decoded = img.decodeImage(result.bytes)!;
      final wasTransparent = decoded.getPixel(decoded.width - 5, decoded.height - 5);
      // JPEG is lossy, so this is "white" with room to breathe — the failure
      // it rules out is a black slab, which is nowhere near.
      expect(wasTransparent.r, greaterThan(230));
      expect(wasTransparent.g, greaterThan(230));
      expect(wasTransparent.b, greaterThan(230));
    });
  });

  group('readForApi', () {
    test('shrinks a viewOnly attachment', () {
      final original = png(gradient(3000, 3000));
      final attachment = LLMAttachment.fromBytes(original, 'image/png',
          referenceType: LLMReferenceType.viewOnly);

      final result = ImageCompressor.readForApi(attachment);

      expect(result.mimeType, 'image/jpeg');
      expect(dimensionsOf(result.bytes).width,
          ImageCompressor.viewOnlyMaxLongEdge);
    });

    for (final type in LLMReferenceType.values
        .where((t) => t != LLMReferenceType.viewOnly)) {
      test('leaves a ${type.name} attachment byte-identical', () {
        // Generation input: the user asked for this resolution, and the
        // workbench toggle is the only thing allowed to trade it away.
        final original = png(gradient(3000, 3000));
        final attachment = LLMAttachment.fromBytes(original, 'image/png',
            referenceType: type);

        final result = ImageCompressor.readForApi(attachment);

        expect(identical(result.bytes, original), isTrue);
        expect(result.mimeType, 'image/png');
      });
    }
  });

  group('compress (generation input, opt-in)', () {
    test('still refuses to resize', () {
      // Well over 3 MB as PNG, so it re-encodes — but the pixels must
      // survive, which is the whole difference between this path and
      // compressForViewing.
      final original = png(noise(1400, 1400));
      expect(original.length, greaterThan(ImageCompressor.maxBytes));

      final result = ImageCompressor.compress(original, 'image/png');

      expect(result.mimeType, 'image/jpeg');
      expect(dimensionsOf(result.bytes), (width: 1400, height: 1400));
    });
  });
}
