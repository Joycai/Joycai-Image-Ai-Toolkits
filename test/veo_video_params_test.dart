import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_capabilities.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_family.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendor_profile.dart' show WireProtocol;
import 'package:joycai_image_ai_toolkits/state/app_state.dart';

/// Veo's resolution and ratio are declared like every other family's video
/// controls; the panel no longer carries a fixed pair of its own.
void main() {
  List<String> keys(ModelCapabilities caps) => [for (final p in caps.videoParams) p.key];

  test('Veo declares resolution and aspect ratio, by family and by wire', () {
    for (final caps in [
      ModelCapabilities.forFamily(ModelFamily.geminiVideo),
      ModelCapabilities.forProtocol(WireProtocol.geminiVeo),
    ]) {
      expect(keys(caps), ['resolution', 'aspectRatio']);
      expect(caps.videoParams.first.defaultValue, '720p');
      expect(caps.videoParams.last.defaultValue, '16:9');
    }
  });

  test('Sora keeps the two inputs its size is built from', () {
    expect(keys(ModelCapabilities.forFamily(ModelFamily.openaiVideo)),
        containsAll(['resolution', 'aspectRatio', 'seconds', 'videoQuality']));
  });

  test("the old fixed controls' choice carries over, without overwriting", () async {
    final settings = {'last_video_resolution': '1080p', 'last_video_aspect_ratio': '9:16'};
    final seeded = await legacyVeoVideoParams(
      const {'openaiVideo.resolution': '720p'},
      (key) async => settings[key],
    );
    expect(seeded, {
      'geminiVideo.resolution': '1080p',
      'geminiVideo.aspectRatio': '9:16',
      'openaiVideo.aspectRatio': '9:16',
    });
    expect(await legacyVeoVideoParams(const {}, (_) async => null), isEmpty);
  });
}
