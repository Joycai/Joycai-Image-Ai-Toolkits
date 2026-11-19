import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../llm/generation/generation_schema.dart';
import '../llm/protocols/generation_contract.dart';
import 'reference_media_probe.dart';

class VideoSourceProbe {
  const VideoSourceProbe({this.info, this.bytes = 0, this.error});
  final ReferenceMediaInfo? info;
  final int bytes;
  final String? error;
}

/// A bounded local probe, with parsing off the UI isolate. Never uploads.
Future<VideoSourceProbe> probeVideoSource(String path) async {
  const limit = 100 * 1024 * 1024;
  try {
    final file = File(path);
    final size = await file.length();
    if (size > limit) return VideoSourceProbe(bytes: size, error: 'sourceVideoTooLarge');
    final builder = BytesBuilder(copy: false);
    await for (final chunk in file.openRead()) {
      if (builder.length + chunk.length > limit) {
        return const VideoSourceProbe(error: 'sourceVideoTooLarge');
      }
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    final info = await Isolate.run(() => probeReferenceMedia(bytes, video: true));
    return VideoSourceProbe(info: info, bytes: bytes.length);
  } catch (_) {
    return const VideoSourceProbe(error: 'unreadableMedia');
  }
}

List<GenerationDiagnostic> videoSourceDiagnostics({
  required GenerationSchema schema,
  required GenerationOperation operation,
  required List<VideoSourceProbe?> probes,
  required Map<String, dynamic> options,
  required bool uploadSupported,
}) {
  if (operation != GenerationOperation.editVideo && operation != GenerationOperation.extendVideo) {
    return const [];
  }
  final edit = operation == GenerationOperation.editVideo;
  final min = edit
      ? schema.contract.videoEdit?.minSourceSeconds
      : schema.contract.videoExtend?.minSourceSeconds;
  final max = edit
      ? schema.contract.videoEdit?.maxSourceSeconds
      : schema.contract.videoExtend?.maxSourceSeconds;
  final combined = edit
      ? schema.contract.videoEdit?.maxCombinedSeconds
      : schema.contract.videoExtend?.maxCombinedSeconds;
  final result = <GenerationDiagnostic>[];
  if (!uploadSupported) result.add(const GenerationDiagnostic('uploadRegionUnsupported'));
  var seconds = 0.0;
  for (final probe in probes) {
    if (probe == null) {
      result.add(const GenerationDiagnostic('sourceVideoProbing'));
      continue;
    }
    if (probe.error != null) {
      result.add(GenerationDiagnostic(probe.error!));
      continue;
    }
    final info = probe.info!;
    final duration = info.seconds;
    if (duration == null ||
        !duration.isFinite ||
        duration < (min ?? 0) ||
        duration > (max ?? double.infinity)) {
      result.add(const GenerationDiagnostic('sourceVideoDuration'));
    } else {
      seconds += duration;
    }
    // The current upload contract uses bounded MP4/MOV video inputs. These
    // format restrictions are shared with its final transport preflight.
    if (schema.contract.referenceUpload &&
        (!['video/mp4', 'video/quicktime'].contains(info.mime) ||
            (info.width ?? 0) < 240 ||
            (info.height ?? 0) < 240 ||
            (info.width ?? 0) > 4096 ||
            (info.height ?? 0) > 4096 ||
            info.width! > info.height! * 8 ||
            info.height! > info.width! * 8 ||
            !(info.fps ?? 0).isFinite ||
            (info.fps ?? 0) < 16)) {
      result.add(const GenerationDiagnostic('sourceVideoFormat'));
    }
  }
  if (schema.contract.maxReferenceTotalSeconds > 0 &&
      seconds > schema.contract.maxReferenceTotalSeconds + .000001) {
    result.add(const GenerationDiagnostic('sourceVideoDuration'));
  }
  final output = double.tryParse('${options['seconds']}');
  final semantics = schema.contract.videoExtend?.durationSemantics;
  final billedOutput = !edit && semantics == VideoExtendDurationSemantics.addedSeconds
      ? (output ?? 0) + seconds
      : output;
  if (combined != null &&
      output != null &&
      output > 0 &&
      seconds + billedOutput! > combined + .000001) {
    result.add(const GenerationDiagnostic('videoDurationBudgetExceeded'));
  }
  return result;
}
