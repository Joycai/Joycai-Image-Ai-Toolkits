import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/generation/generation_schema.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:joycai_image_ai_toolkits/services/media/reference_media_probe.dart';
import 'package:joycai_image_ai_toolkits/services/media/video_source_probe.dart';
import 'package:joycai_image_ai_toolkits/state/workbench_ui_state.dart';

void main() {
  test(
    'source probe is bounded, clear and replacement cannot be overwritten by a stale probe',
    () async {
      final root = await Directory.systemTemp.createTemp('source-probe-');
      addTearDown(() => root.delete(recursive: true));
      final large = await File('${root.path}/large.mp4').open(mode: FileMode.write);
      await large.truncate(100 * 1024 * 1024 + 1);
      await large.close();
      expect((await probeVideoSource('${root.path}/large.mp4')).error, 'sourceVideoTooLarge');
      final state = WorkbenchUIState();
      addTearDown(state.dispose);
      final pending = state.setVideoSourceVideo('test/support/reference_media/three_seconds.mp4');
      expect(state.videoSourceProbing, true);
      state.clearVideoSourceVideo();
      await pending;
      expect(state.videoSourceVideoPath, isNull);
      expect(state.videoSourceProbe, isNull);
      final first = state.setVideoSourceVideo('missing');
      final second = state.setVideoSourceVideo('test/support/reference_media/three_seconds.mp4');
      await Future.wait([first, second]);
      expect(state.videoSourceProbe!.error, isNull);
      expect(state.videoSourceProbe!.info!.seconds, closeTo(3, .01));
      expect(state.videoGenerationMediaFor(GenerationOperation.textVideo), isEmpty);
      expect(
        state.videoGenerationMediaFor(GenerationOperation.editVideo).single.role,
        GenerationMediaRole.sourceVideo,
      );
    },
  );
  test(
    'source specs, aggregate reference seconds, output budget and region block before queue',
    () {
      final schema = LLMDispatcher.generationSchemaFor(
        channelType: Vendors.dashscopeNative,
        modelId: 'wan3.0-video',
        tag: 'video',
      );
      VideoSourceProbe probe(double seconds, {double fps = 30}) => VideoSourceProbe(
        info: ReferenceMediaInfo('video/mp4', width: 1280, height: 720, seconds: seconds, fps: fps),
      );
      List<String> codes(
        List<VideoSourceProbe?> probes, {
        String seconds = '-1',
        bool upload = true,
      }) => videoSourceDiagnostics(
        schema: schema,
        operation: GenerationOperation.extendVideo,
        probes: probes,
        options: {'seconds': seconds},
        uploadSupported: upload,
      ).map((d) => d.code).toList();
      expect(codes([probe(3)]), isEmpty);
      expect(codes([null]), contains('sourceVideoProbing'));
      expect(codes([probe(20)]), contains('sourceVideoDuration'));
      expect(codes([probe(10), probe(6)]), contains('sourceVideoDuration'));
      expect(codes([probe(12)], seconds: '20'), contains('videoDurationBudgetExceeded'));
      expect(codes([probe(12)], seconds: '18'), isEmpty);
      expect(codes([probe(12)], seconds: '2'), isEmpty); // Soft warning only.
      expect(codes([probe(3, fps: 15)]), contains('sourceVideoFormat'));
      expect(codes([probe(3)], upload: false), contains('uploadRegionUnsupported'));
    },
  );
}
