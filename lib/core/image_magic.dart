import 'dart:typed_data';

/// Image format detection from the bytes themselves.
///
/// Every declared type an image arrives with is only a claim: a relay's
/// `inlineData.mimeType` has been seen saying `image/png` over JPEG bytes,
/// `b64_json` carries no type at all, and a download's `content-type` is
/// whatever that host felt like sending. The bytes are the one thing that
/// cannot lie about what they are, so anything that names a file or fills a
/// `media_type` field reads them first and uses the declaration only as a
/// fallback for formats this table does not know.
///
/// Pure and dependency-free on purpose: it runs on every generated image and
/// on every attachment read for a request, and a full `image` decode for a
/// four-byte question is the wrong tool.

/// The MIME type [bytes] actually are, or null when the leading bytes match
/// none of the formats the app writes or accepts.
String? imageMimeFromBytes(Uint8List bytes) {
  if (bytes.length < 12) return _shortPrefix(bytes);
  // PNG: 89 50 4E 47 0D 0A 1A 0A
  if (bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0D &&
      bytes[5] == 0x0A &&
      bytes[6] == 0x1A &&
      bytes[7] == 0x0A) {
    return 'image/png';
  }
  // JPEG: FF D8 FF
  if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
    return 'image/jpeg';
  }
  // WEBP: "RIFF" .... "WEBP"
  if (bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'image/webp';
  }
  // GIF: "GIF87a" / "GIF89a"
  if (bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x38 &&
      (bytes[4] == 0x37 || bytes[4] == 0x39) &&
      bytes[5] == 0x61) {
    return 'image/gif';
  }
  // BMP: "BM"
  if (bytes[0] == 0x42 && bytes[1] == 0x4D) return 'image/bmp';
  return null;
}

/// The PNG / JPEG / GIF / BMP signatures fit in fewer than twelve bytes; a
/// buffer that short is still worth a look before answering "unknown".
String? _shortPrefix(Uint8List bytes) {
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'image/png';
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (bytes.length >= 6 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x38) {
    return 'image/gif';
  }
  if (bytes.length >= 2 && bytes[0] == 0x42 && bytes[1] == 0x4D) {
    return 'image/bmp';
  }
  return null;
}

/// The file extension (with the dot) for an image MIME type, or null for a
/// type this app has no name for.
String? extensionForImageMime(String? mime) {
  switch (mime) {
    case 'image/png':
      return '.png';
    case 'image/jpeg':
      return '.jpg';
    case 'image/webp':
      return '.webp';
    case 'image/gif':
      return '.gif';
    case 'image/bmp':
      return '.bmp';
    default:
      return null;
  }
}

/// The extension a generated image should be saved under, read off its
/// bytes; [fallback] only when the format is unrecognized.
///
/// This is the one place a result file gets its name from, so that no
/// executor can go back to trusting a header. Before it existed every result
/// was written as `.png` regardless — and a relay returning JPEG bytes
/// produced a file whose viewer sniffed it fine and whose name lied to every
/// tool that trusted the extension.
String imageExtensionFromBytes(Uint8List bytes, {String fallback = '.png'}) =>
    extensionForImageMime(imageMimeFromBytes(bytes)) ?? fallback;

/// [declared] when it agrees with the bytes or the bytes are unrecognized;
/// the sniffed type otherwise.
///
/// The input-side twin of [imageExtensionFromBytes]: an attachment named
/// `photo.png` that holds JPEG bytes is a real occurrence (renamed downloads,
/// relays' output saved under the wrong name), and ④ validates the bytes
/// against `media_type` and 400s the whole request on a mismatch — while ①
/// and ③ accept the lie and decode by content anyway. Both are served by
/// telling the truth.
String resolveImageMime(Uint8List bytes, String declared) =>
    imageMimeFromBytes(bytes) ?? declared;
