import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../../../core/image_magic.dart';
import '../../media/reference_media_probe.dart';
import '../generation/wan_reference_validation.dart';
import '../llm_types.dart';

String dashscopeVideoMediaRole(LLMAttachment attachment) => switch (attachment.referenceType) {
  LLMReferenceType.firstFrame => 'first_frame',
  LLMReferenceType.lastFrame => 'last_frame',
  LLMReferenceType.referenceVideo => 'reference_video',
  LLMReferenceType.referenceAudio => 'reference_audio',
  _ => 'reference_image',
};

void validateWanVideoMediaInfo(ReferenceMediaInfo info, {required bool video}) {
  final seconds = info.seconds;
  if (seconds == null || !seconds.isFinite || seconds < 1 || seconds > 15) {
    throw LLMApiException(
      'Wan reference clips must be between 1 and 15 seconds. Nothing was sent.',
    );
  }
  if (!video) {
    if (!['audio/wav', 'audio/mpeg'].contains(info.mime)) {
      throw LLMApiException('Wan reference audio requires WAV or MP3. Nothing was sent.');
    }
    return;
  }
  final w = info.width ?? 0;
  final h = info.height ?? 0;
  final fps = info.fps ?? 0;
  if (!['video/mp4', 'video/quicktime'].contains(info.mime) ||
      w < 240 ||
      h < 240 ||
      w > 4096 ||
      h > 4096 ||
      w > h * 8 ||
      h > w * 8 ||
      !fps.isFinite ||
      fps < 16) {
    throw LLMApiException(
      'Wan reference video requires MP4/MOV, 240–4096 pixel edges, at most 8:1 and at least 16 fps. Nothing was sent.',
    );
  }
}

class DashScopePreparedMedia {
  const DashScopePreparedMedia(this.directory, this.files, this.videoSeconds);
  final Directory directory;
  final List<({String role, String mime, File file})> files;
  final double videoSeconds;
  Future<void> dispose() => directory.delete(recursive: true);
}

/// Validate every input before the first upload. At most one bounded file is
/// decoded at a time; private snapshots keep the upload identical to the bytes
/// validated, even if a caller changes its original path during preparation.
Future<DashScopePreparedMedia> prepareDashScopeVideoMedia(
  List<LLMAttachment> attachments, {
  required int outputSeconds,
  required void Function() checkCancelled,
}) async {
  final dir = await Directory.systemTemp.createTemp('joycai-wan-upload-');
  final files = <({String role, String mime, File file})>[];
  var videoSeconds = 0.0;
  var audioSeconds = 0.0;
  try {
    for (final attachment in attachments) {
      checkCancelled();
      final role = dashscopeVideoMediaRole(attachment);
      final video = role == 'reference_video';
      final audio = role == 'reference_audio';
      final limit =
          (video
              ? 100
              : audio
              ? 15
              : 20) *
          1024 *
          1024;
      final bytes = await _readBounded(attachment, limit, checkCancelled);
      final String mime;
      if (video || audio) {
        final ReferenceMediaInfo info;
        try {
          info = await Isolate.run(() => probeReferenceMedia(bytes, video: video));
        } catch (_) {
          throw LLMApiException('Generation input invalid: unreadableMedia. Nothing was sent.');
        }
        validateWanVideoMediaInfo(info, video: video);
        if (video) videoSeconds += info.seconds!;
        if (audio) audioSeconds += info.seconds!;
        if (videoSeconds > 15.000001 ||
            audioSeconds > 15.000001 ||
            (videoSeconds > 0 && outputSeconds != -1 && videoSeconds + outputSeconds > 30.000001)) {
          throw LLMApiException(
            'Wan references may total 15 seconds per media kind; input video plus output must not exceed 30 seconds. Nothing was sent.',
          );
        }
        mime = info.mime;
      } else {
        await validateWanReference(bytes);
        mime = imageMimeFromBytes(bytes)!;
      }
      checkCancelled();
      final file = await File('${dir.path}/${files.length}').writeAsBytes(bytes);
      files.add((role: role, mime: mime, file: file));
    }
    return DashScopePreparedMedia(dir, files, videoSeconds);
  } catch (_) {
    await dir.delete(recursive: true);
    rethrow;
  }
}

Future<Uint8List> _readBounded(
  LLMAttachment attachment,
  int limit,
  void Function() checkCancelled,
) async {
  void sizeCheck(int length) {
    if (length > limit) {
      throw LLMApiException(
        'Reference media exceeds ${limit ~/ (1024 * 1024)} MB. Nothing was sent.',
      );
    }
  }

  if (attachment.bytes case final bytes?) {
    sizeCheck(bytes.length);
    if (bytes.isEmpty) throw LLMApiException('Unreadable reference media. Nothing was sent.');
    return Uint8List.fromList(bytes);
  }
  final path = attachment.path;
  if (path == null) throw LLMApiException('Unreadable reference media. Nothing was sent.');
  final file = File(path);
  sizeCheck(await file.length());
  final builder = BytesBuilder(copy: false);
  await for (final chunk in file.openRead()) {
    checkCancelled();
    sizeCheck(builder.length + chunk.length);
    builder.add(chunk);
  }
  if (builder.isEmpty) throw LLMApiException('Unreadable reference media. Nothing was sent.');
  return builder.takeBytes();
}
