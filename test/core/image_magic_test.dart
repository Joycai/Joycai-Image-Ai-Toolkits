import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/image_magic.dart';

/// Pins the rule that an image's type is read off its bytes, never off a
/// declaration.
///
/// The declarations lie in practice: a relay's `inlineData.mimeType` has said
/// `image/png` over JPEG bytes, `b64_json` carries no type at all, and a file
/// renamed to `.png` keeps its JPEG contents. None of that throws — the file
/// simply gets the wrong name, or ④ rejects the request for a `media_type`
/// that does not match the bytes.
void main() {
  Uint8List bytes(List<int> head, {int pad = 16}) =>
      Uint8List.fromList([...head, ...List.filled(pad, 0)]);

  final png = bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  final jpeg = bytes([0xFF, 0xD8, 0xFF, 0xE0]);
  final webp = bytes([
    0x52, 0x49, 0x46, 0x46, // RIFF
    0x00, 0x00, 0x00, 0x00, // size
    0x57, 0x45, 0x42, 0x50, // WEBP
  ]);
  final gif = bytes([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]);
  final bmp = bytes([0x42, 0x4D]);

  group('imageMimeFromBytes', () {
    test('recognizes each format the app writes or accepts by its magic', () {
      expect(imageMimeFromBytes(png), 'image/png');
      expect(imageMimeFromBytes(jpeg), 'image/jpeg');
      expect(imageMimeFromBytes(webp), 'image/webp');
      expect(imageMimeFromBytes(gif), 'image/gif');
      expect(imageMimeFromBytes(bmp), 'image/bmp');
    });

    test('bytes that are not an image answer null, never a guess', () {
      expect(imageMimeFromBytes(Uint8List.fromList('<!doctype html>'.codeUnits)),
          isNull);
      expect(imageMimeFromBytes(Uint8List(0)), isNull);
      expect(imageMimeFromBytes(Uint8List.fromList([0x89, 0x50])), isNull);
    });

    test('a short buffer that still carries a full signature is recognized', () {
      // A JPEG header is three bytes; a buffer shorter than the WEBP window
      // must not be refused on length alone.
      expect(imageMimeFromBytes(Uint8List.fromList([0xFF, 0xD8, 0xFF])),
          'image/jpeg');
      expect(
          imageMimeFromBytes(
              Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])),
          'image/png');
    });
  });

  group('imageExtensionFromBytes', () {
    test('names the file after the bytes', () {
      expect(imageExtensionFromBytes(jpeg), '.jpg');
      expect(imageExtensionFromBytes(webp), '.webp');
      expect(imageExtensionFromBytes(png), '.png');
    });

    test('falls back only when the format is unknown', () {
      expect(imageExtensionFromBytes(Uint8List.fromList([1, 2, 3])), '.png');
      expect(imageExtensionFromBytes(Uint8List.fromList([1, 2, 3]), fallback: '.bin'),
          '.bin');
    });
  });

  group('resolveImageMime', () {
    test('the bytes win over a declaration that disagrees', () {
      expect(resolveImageMime(jpeg, 'image/png'), 'image/jpeg');
    });

    test('a declaration that agrees is kept as is', () {
      expect(resolveImageMime(png, 'image/png'), 'image/png');
    });

    test('unrecognized bytes keep the declaration — it is all there is', () {
      expect(resolveImageMime(Uint8List.fromList([1, 2, 3]), 'image/avif'),
          'image/avif');
    });
  });
}
