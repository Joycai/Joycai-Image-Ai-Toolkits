import 'dart:typed_data';

/// Video container detection from the leading bytes — the video twin of
/// `image_magic.dart`, for the same reason: a download's status code and
/// `content-type` are claims, and a relay answering an expired signed link
/// with `200` + an HTML page used to be written out as `.mp4` while the task
/// reported success (standard 14 §3.4, 13 §6).
///
/// Pure and dependency-free; it only needs the first dozen bytes.

/// How many leading bytes [videoExtensionFromBytes] needs to decide.
const int videoMagicHeadLength = 12;

/// The file extension (with the dot) for the container [head] starts, or
/// null when it is no video container this app writes.
///
/// * ISO base media (MP4 / MOV): `ftyp` at offset 4; the major brand `qt  `
///   is QuickTime, everything else is saved as `.mp4`.
/// * Matroska / WebM: EBML magic `1A 45 DF A3` at offset 0.
String? videoExtensionFromBytes(List<int> head) {
  if (head.length >= 8 &&
      head[4] == 0x66 && // f
      head[5] == 0x74 && // t
      head[6] == 0x79 && // y
      head[7] == 0x70) {
    // p
    if (head.length >= 12 &&
        head[8] == 0x71 && // q
        head[9] == 0x74 && // t
        head[10] == 0x20 &&
        head[11] == 0x20) {
      return '.mov';
    }
    return '.mp4';
  }
  if (head.length >= 4 &&
      head[0] == 0x1A &&
      head[1] == 0x45 &&
      head[2] == 0xDF &&
      head[3] == 0xA3) {
    return '.webm';
  }
  return null;
}

/// [videoExtensionFromBytes] over a typed buffer.
String? videoExtensionFromHead(Uint8List head) => videoExtensionFromBytes(head);
