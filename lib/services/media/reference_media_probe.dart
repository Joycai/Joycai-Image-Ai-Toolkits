import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

import '../../core/image_magic.dart';

/// Local metadata inspection. No subprocess, network, or platform player is
/// needed for MP4/MOV, WAV and MP3; malformed/unsupported inputs fail closed.
class ReferenceMediaInfo {
  const ReferenceMediaInfo(this.mime, {this.width, this.height, this.seconds, this.fps});
  final String mime;
  final int? width;
  final int? height;
  final double? seconds;
  final double? fps;
}

Future<ReferenceMediaInfo> probeReferenceImage(Uint8List bytes) async {
  final mime = imageMimeFromBytes(bytes);
  if (const ['image/jpeg', 'image/png', 'image/webp'].contains(mime)) {
    final info = img.findDecoderForData(bytes)?.startDecode(bytes);
    if (info == null) throw const FormatException('unreadableMedia');
    return ReferenceMediaInfo(mime!, width: info.width, height: info.height);
  }
  // HEIF decoding is delegated to the engine, preserving the original bytes.
  // Do not infer dimensions from the first ispe box (it may be a thumbnail).
  if (bytes.length >= 16 &&
      _text(bytes, 4, 4) == 'ftyp' &&
      const ['heic', 'heix', 'hevc', 'hevx', 'mif1', 'msf1'].contains(_text(bytes, 8, 4))) {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        return ReferenceMediaInfo('image/heif', width: descriptor.width, height: descriptor.height);
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
  }
  throw const FormatException('unsupportedMediaFormat');
}

String _text(Uint8List b, int offset, int count) =>
    String.fromCharCodes(b.sublist(offset, offset + count));

ReferenceMediaInfo probeReferenceMedia(Uint8List bytes, {required bool video}) {
  try {
    if (video) return _movie(bytes);
    if (bytes.length >= 12 && _text(bytes, 0, 4) == 'RIFF' && _text(bytes, 8, 4) == 'WAVE') {
      return _wave(bytes);
    }
    return _mp3(bytes);
  } on RangeError {
    throw const FormatException('unreadableMedia');
  }
}

class _Box {
  const _Box(this.type, this.start, this.end);
  final String type;
  final int start;
  final int end;
}

List<_Box> _boxes(Uint8List b, int start, int end) {
  final data = ByteData.sublistView(b);
  final result = <_Box>[];
  for (var offset = start; offset < end;) {
    if (offset + 8 > end) throw const FormatException('unreadableMedia');
    var size = data.getUint32(offset);
    var header = 8;
    if (size == 1) {
      if (offset + 16 > end) throw const FormatException('unreadableMedia');
      size = data.getUint64(offset + 8);
      header = 16;
    } else if (size == 0) {
      size = end - offset;
    }
    if (size < header || size > end - offset) throw const FormatException('unreadableMedia');
    result.add(_Box(_text(b, offset + 4, 4), offset + header, offset + size));
    offset += size;
  }
  return result;
}

_Box _child(Uint8List b, _Box parent, String type) =>
    _boxes(b, parent.start, parent.end).where((box) => box.type == type).firstOrNull ??
    (throw const FormatException('unreadableMedia'));

ReferenceMediaInfo _movie(Uint8List b) {
  final root = _Box('', 0, b.length);
  final ftyp = _child(b, root, 'ftyp');
  final mime = _text(b, ftyp.start, 4) == 'qt  ' ? 'video/quicktime' : 'video/mp4';
  final moov = _child(b, root, 'moov');
  final data = ByteData.sublistView(b);
  ReferenceMediaInfo? video;
  for (final track in _boxes(b, moov.start, moov.end).where((box) => box.type == 'trak')) {
    final mdia = _child(b, track, 'mdia');
    final handler = _child(b, mdia, 'hdlr');
    final kind = _text(b, handler.start + 8, 4);
    if (kind != 'vide' && kind != 'soun') continue;
    final mdhd = _child(b, mdia, 'mdhd');
    final version = b[mdhd.start];
    if (version > 1) throw const FormatException('unreadableMedia');
    final scaleOffset = mdhd.start + (version == 1 ? 20 : 12);
    final scale = data.getUint32(scaleOffset);
    final duration = version == 1
        ? data.getUint64(scaleOffset + 4)
        : data.getUint32(scaleOffset + 4);
    if (scale == 0 || duration == 0) throw const FormatException('unreadableMedia');
    final seconds = duration / scale;
    final stbl = _child(b, _child(b, mdia, 'minf'), 'stbl');
    final stsd = _child(b, stbl, 'stsd');
    final entries = _boxes(b, stsd.start + 8, stsd.end);
    if (entries.isEmpty) throw const FormatException('unreadableMedia');
    if (kind == 'soun') {
      if (entries.any((e) => !['mp4a', '.mp3', 'mp3 '].contains(e.type))) {
        throw const FormatException('unsupportedMediaCodec');
      }
      continue;
    }
    if (video != null || entries.any((e) => !['avc1', 'avc3', 'hvc1', 'hev1'].contains(e.type))) {
      throw const FormatException('unsupportedMediaCodec');
    }
    final entry = entries.first;
    final width = data.getUint16(entry.start + 24);
    final height = data.getUint16(entry.start + 26);
    final stts = _child(b, stbl, 'stts');
    final count = data.getUint32(stts.start + 4);
    if (count == 0 || count > (stts.end - stts.start - 8) ~/ 8) {
      throw const FormatException('unreadableMedia');
    }
    var frames = 0;
    var ticks = 0;
    for (var i = 0; i < count; i++) {
      final n = data.getUint32(stts.start + 8 + i * 8);
      final delta = data.getUint32(stts.start + 12 + i * 8);
      frames += n;
      ticks += n * delta;
    }
    if (ticks == 0 || frames == 0) throw const FormatException('unreadableMedia');
    video = ReferenceMediaInfo(
      mime,
      width: width,
      height: height,
      seconds: seconds,
      fps: frames * scale / ticks,
    );
  }
  return video ?? (throw const FormatException('unreadableMedia'));
}

ReferenceMediaInfo _wave(Uint8List b) {
  final data = ByteData.sublistView(b);
  int? rate;
  int? length;
  final end = data.getUint32(4, Endian.little) + 8;
  if (end > b.length) throw const FormatException('unreadableMedia');
  for (var pos = 12; pos + 8 <= end;) {
    final size = data.getUint32(pos + 4, Endian.little);
    if (pos + 8 + size > end) throw const FormatException('unreadableMedia');
    final type = _text(b, pos, 4);
    if (type == 'fmt ' && size >= 16) rate = data.getUint32(pos + 16, Endian.little);
    if (type == 'data') length = size;
    pos += 8 + size + (size % 2);
  }
  if (rate == null || rate == 0 || length == null || length == 0) {
    throw const FormatException('unreadableMedia');
  }
  return ReferenceMediaInfo('audio/wav', seconds: length / rate);
}

ReferenceMediaInfo _mp3(Uint8List b) {
  var pos = 0;
  if (b.length >= 10 && _text(b, 0, 3) == 'ID3') {
    if (b.sublist(6, 10).any((v) => v >= 128)) throw const FormatException('unreadableMedia');
    pos = 10 + (b[6] << 21 | b[7] << 14 | b[8] << 7 | b[9]);
    if (b[5] & 0x10 != 0) pos += 10;
  }
  var seconds = 0.0;
  var frames = 0;
  while (pos + 4 <= b.length) {
    if (b.length - pos == 128 && _text(b, pos, 3) == 'TAG') {
      pos = b.length;
      break;
    }
    if (b[pos] != 255 || b[pos + 1] & 0xe0 != 0xe0) {
      throw const FormatException('unsupportedMediaFormat');
    }
    final version = (b[pos + 1] >> 3) & 3;
    final layer = (b[pos + 1] >> 1) & 3;
    final bitrateIndex = b[pos + 2] >> 4;
    final frequencyIndex = (b[pos + 2] >> 2) & 3;
    if (version == 1 ||
        layer != 1 ||
        bitrateIndex == 0 ||
        bitrateIndex == 15 ||
        frequencyIndex == 3) {
      throw const FormatException('unsupportedMediaCodec');
    }
    final bitrate =
        (version == 3
            ? const [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]
            : const [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160])[bitrateIndex] *
        1000;
    final rate =
        const [44100, 48000, 32000][frequencyIndex] ~/
        (version == 3
            ? 1
            : version == 2
            ? 2
            : 4);
    final size = (version == 3 ? 144 : 72) * bitrate ~/ rate + ((b[pos + 2] >> 1) & 1);
    if (pos + size > b.length) throw const FormatException('unreadableMedia');
    seconds += (version == 3 ? 1152 : 576) / rate;
    frames++;
    pos += size;
  }
  if (frames < 2 || pos != b.length) throw const FormatException('unreadableMedia');
  return ReferenceMediaInfo('audio/mpeg', seconds: seconds);
}
