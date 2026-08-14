import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'llm_types.dart';

/// Re-encodes oversized images before they go out over the wire.
///
/// Two independent eligibility paths call into [compress]:
///  * [readForApi] — automatic, for [LLMReferenceType.viewOnly] attachments.
///    Those exist purely so a model can describe what it sees (Prompt
///    Assistant's `view_image`), so lossy recompression is always safe.
///  * Task executors (`task_executors.dart`) — opt-in, gated by the
///    workbench "compress reference images" toggle. Every other reference
///    type (`media`, `asset`, `firstFrame`, `lastFrame`) is actual
///    image-generation/editing input, so the original bytes reach the API
///    untouched *unless* the user explicitly accepted the fidelity
///    trade-off for smaller requests.
class ImageCompressor {
  static const int maxBytes = 3 * 1024 * 1024;
  static const int _jpegQuality = 85;

  /// Recompresses [original] to JPEG when it exceeds [maxBytes]. Falls back
  /// to the original bytes/mimeType when already small enough or when
  /// decoding fails — recompression is a size optimization, not a
  /// requirement, so a decode failure should still reach the model rather
  /// than drop the attachment.
  static ({Uint8List bytes, String mimeType}) compress(Uint8List original, String mimeType) {
    if (original.length <= maxBytes) return (bytes: original, mimeType: mimeType);

    final decoded = img.decodeImage(original);
    if (decoded == null) return (bytes: original, mimeType: mimeType);

    final jpg = img.encodeJpg(decoded, quality: _jpegQuality);
    return (bytes: Uint8List.fromList(jpg), mimeType: 'image/jpeg');
  }

  /// Re-encodes [original] to JPEG when [mimeType] is not one [accepted] by
  /// the target API, and returns the pair unchanged when it already is.
  ///
  /// Only ④ needs this today: Anthropic accepts exactly four media types and
  /// 400s the whole request on a fifth, where ① and ③ take whatever they are
  /// handed. The alternatives — dropping the attachment, or relabelling it as
  /// a type it isn't — both end with the model answering as though it saw an
  /// image it never got. A decode failure falls back to the original bytes so
  /// the request still reaches the API and fails loudly there.
  static ({Uint8List bytes, String mimeType}) coerceMediaType(
    Uint8List original,
    String mimeType,
    Set<String> accepted,
  ) {
    if (accepted.contains(mimeType.toLowerCase())) {
      return (bytes: original, mimeType: mimeType);
    }
    final decoded = img.decodeImage(original);
    if (decoded == null) return (bytes: original, mimeType: mimeType);
    return (
      bytes: Uint8List.fromList(img.encodeJpg(decoded, quality: _jpegQuality)),
      mimeType: 'image/jpeg',
    );
  }

  /// Reads [attachment]'s bytes, compressing them when its referenceType is
  /// [LLMReferenceType.viewOnly] — see the class doc for why other
  /// reference types are excluded here.
  static ({Uint8List bytes, String mimeType}) readForApi(LLMAttachment attachment) {
    final raw = attachment.path != null
        ? File(attachment.path!).readAsBytesSync()
        : (attachment.bytes ?? Uint8List(0));

    if (attachment.referenceType != LLMReferenceType.viewOnly) {
      return (bytes: raw, mimeType: attachment.mimeType);
    }
    return compress(raw, attachment.mimeType);
  }
}
