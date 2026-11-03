import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../../core/image_magic.dart';
import '../llm_types.dart';

/// Validates the actual uploaded bytes, including PNG alpha channels even if
/// every pixel is opaque. Decode away from the UI isolate.
Future<void> validateWanReference(Uint8List bytes) async {
  if (bytes.length > 20 * 1024 * 1024) {
    throw LLMApiException('Wan reference image exceeds 20 MB. Nothing was sent.');
  }
  final mime = imageMimeFromBytes(bytes);
  if (!const ['image/jpeg', 'image/png', 'image/bmp', 'image/webp'].contains(mime)) {
    throw LLMApiException('Wan references require JPEG, PNG, BMP or WEBP. Nothing was sent.');
  }
  final error = await Isolate.run(() {
    final decoder = img.findDecoderForData(bytes);
    final info = decoder?.startDecode(bytes);
    if (info == null) return 'unreadable image';
    final w = info.width;
    final h = info.height;
    if (w < 240 || h < 240 || w > 8000 || h > 8000) {
      return 'each edge must be between 240 and 8000 pixels';
    }
    if (w > h * 8 || h > w * 8) return 'aspect ratio must be between 1:8 and 8:1';
    final image = decoder!.decodeFrame(0);
    if (image == null) return 'unreadable image';
    if (mime == 'image/png' && image.hasAlpha) return 'PNG must have no alpha channel';
    return null;
  });
  if (error != null) throw LLMApiException('Invalid Wan reference: $error. Nothing was sent.');
}
