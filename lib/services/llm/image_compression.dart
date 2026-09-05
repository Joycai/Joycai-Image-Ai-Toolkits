import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../core/image_magic.dart';
import 'llm_types.dart';

/// Re-encodes oversized images before they go out over the wire.
///
/// Two independent eligibility paths, with deliberately different rules:
///  * [readForApi] → [compressForViewing] — automatic, for
///    [LLMReferenceType.viewOnly] attachments. Those exist purely so a model
///    can describe what it sees (Prompt Assistant's `view_image`), so lossy
///    recompression is always safe and the ceilings are aggressive.
///  * Task executors (`task_executors.dart`) → [compress] — opt-in, gated by
///    the workbench "compress reference images" toggle. Every other reference
///    type (`media`, `asset`, `firstFrame`, `lastFrame`) is actual
///    image-generation/editing input, so the original bytes reach the API
///    untouched *unless* the user explicitly accepted the fidelity
///    trade-off for smaller requests — and even then only the size is
///    reduced, never the resolution.
class ImageCompressor {
  static const int maxBytes = 3 * 1024 * 1024;
  static const int _jpegQuality = 85;

  /// Long edge above which a view-only attachment is downscaled.
  ///
  /// Every vision API resamples above roughly this size before it looks at
  /// anything — Anthropic documents 1568px explicitly, and the tiling
  /// schemes ① and ③ use land in the same neighbourhood — so pixels past it
  /// are uploaded, paid for in wall-clock, and then discarded by the host.
  ///
  /// The resize on its own is the smaller half of the win — most reference
  /// photos are already near the cap, so [viewOnlyMaxBytes] does the heavy
  /// lifting. What makes both worth doing is that the Prompt Assistant
  /// re-sends every live attachment on *every* iteration of its tool loop:
  /// a session with three reference photos was uploading ~8 MB per request,
  /// a dozen or more times per turn. That, not generation speed, was the
  /// bulk of the latency behind the 120 s deadline
  /// (docs/plans/2026-08-assistant-timeout.md).
  static const int viewOnlyMaxLongEdge = 1568;

  /// Byte ceiling for a view-only attachment.
  ///
  /// Above it the image is re-encoded as JPEG even when its resolution is
  /// already within [viewOnlyMaxLongEdge]: a PNG of a photograph routinely
  /// costs ~10× its JPEG equivalent for a difference no model can act on. A
  /// measured case from the session that prompted this — three cosplay
  /// reference photos, all at or near the pixel cap — went from 7.97 MB to
  /// 0.89 MB of base64 per request, almost entirely on this rule rather
  /// than on the resize.
  static const int viewOnlyMaxBytes = 512 * 1024;

  /// Recompresses [original] to JPEG when it exceeds [maxBytes]. Falls back
  /// to the original bytes/mimeType when already small enough or when
  /// decoding fails — recompression is a size optimization, not a
  /// requirement, so a decode failure should still reach the model rather
  /// than drop the attachment.
  ///
  /// Deliberately does **not** downscale: this is the path generation input
  /// travels, where resolution is part of what the user asked for. Only
  /// [compressForViewing] resizes.
  static ({Uint8List bytes, String mimeType}) compress(Uint8List original, String mimeType) {
    if (original.length <= maxBytes) return (bytes: original, mimeType: mimeType);

    final decoded = img.decodeImage(original);
    if (decoded == null) return (bytes: original, mimeType: mimeType);

    final jpg = img.encodeJpg(_flattenAlpha(decoded), quality: _jpegQuality);
    return (bytes: Uint8List.fromList(jpg), mimeType: 'image/jpeg');
  }

  /// Shrinks a view-only attachment to something worth putting on the wire:
  /// long edge capped at [viewOnlyMaxLongEdge], bytes at [viewOnlyMaxBytes].
  ///
  /// The dimensions are read from the file header ([Decoder.startDecode])
  /// rather than by decoding, because this runs inside the payload builder —
  /// once per attachment per *request*, not once per session — and a full
  /// decode of an image that turns out to need no work is pure cost.
  ///
  /// Returns the original pair untouched when the format is unrecognized or
  /// when decoding fails: an attachment the model never receives is worse
  /// than a large one (it answers as though it saw an image it never got).
  ///
  /// It also bails when the re-encode came out no smaller — but **only for
  /// an image that was already within [viewOnlyMaxLongEdge]**. Once a resize
  /// is in play the byte count stops being the thing worth optimizing: a
  /// 4000² image of flat colour is a few KB as PNG and still costs its full
  /// several-thousand-token price at that resolution, so trading those bytes
  /// for a larger JPEG is the right call. The comparison exists for the case
  /// it was written for — a re-encode at unchanged resolution that was
  /// supposed to be a pure win and wasn't.
  static ({Uint8List bytes, String mimeType}) compressForViewing(
      Uint8List original, String mimeType) {
    final decoder = img.findDecoderForData(original);
    final info = decoder?.startDecode(original);
    if (decoder == null || info == null) {
      return (bytes: original, mimeType: mimeType);
    }

    final longEdge = info.width > info.height ? info.width : info.height;
    final oversized = longEdge > viewOnlyMaxLongEdge;
    if (!oversized && original.length <= viewOnlyMaxBytes) {
      return (bytes: original, mimeType: mimeType);
    }

    final decoded = decoder.decode(original);
    if (decoded == null) return (bytes: original, mimeType: mimeType);

    // Both dimensions are computed here rather than letting copyResize infer
    // the missing one: the rounding is then ours and the test can pin it.
    final img.Image sized;
    if (oversized) {
      final scale = viewOnlyMaxLongEdge / longEdge;
      final width = (info.width * scale).round().clamp(1, info.width);
      final height = (info.height * scale).round().clamp(1, info.height);
      sized = img.copyResize(
        decoded,
        width: width,
        height: height,
        interpolation: img.Interpolation.average,
      );
    } else {
      sized = decoded;
    }

    final jpg =
        Uint8List.fromList(img.encodeJpg(_flattenAlpha(sized), quality: _jpegQuality));
    if (!oversized && jpg.length >= original.length) {
      return (bytes: original, mimeType: mimeType);
    }
    return (bytes: jpg, mimeType: 'image/jpeg');
  }

  /// Composites [image] onto white when it carries alpha.
  ///
  /// JPEG has no alpha channel, and letting the encoder decide what to do
  /// with one turns a transparent PNG — a logo, a cut-out reference — into a
  /// black slab. White is the assumption every image viewer already makes,
  /// so it is what the user has been looking at.
  static img.Image _flattenAlpha(img.Image image) {
    if (!image.hasAlpha) return image;
    final flat = img.Image(width: image.width, height: image.height);
    img.fill(flat, color: img.ColorRgb8(255, 255, 255));
    return img.compositeImage(flat, image);
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
      bytes: Uint8List.fromList(
          img.encodeJpg(_flattenAlpha(decoded), quality: _jpegQuality)),
      mimeType: 'image/jpeg',
    );
  }

  /// Reads [attachment]'s bytes, shrinking them when its referenceType is
  /// [LLMReferenceType.viewOnly] — see the class doc for why other
  /// reference types are excluded here.
  ///
  /// The MIME type is taken from the bytes when they are a format this app
  /// recognizes, and from the attachment's declaration only otherwise. The
  /// declaration comes from a file extension, and a `.png` holding JPEG bytes
  /// is an ordinary occurrence (renamed downloads, relay output saved under
  /// the wrong name): ④ checks the bytes against `media_type` and rejects the
  /// whole request on a mismatch, so the truth has to be established here,
  /// once, for every protocol.
  static ({Uint8List bytes, String mimeType}) readForApi(LLMAttachment attachment) {
    final raw = attachment.path != null
        ? File(attachment.path!).readAsBytesSync()
        : (attachment.bytes ?? Uint8List(0));
    final mimeType = resolveImageMime(raw, attachment.mimeType);

    if (attachment.referenceType != LLMReferenceType.viewOnly) {
      return (bytes: raw, mimeType: mimeType);
    }
    return compressForViewing(raw, mimeType);
  }
}
