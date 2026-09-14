import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/output_spec.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/dashscope_images_protocol.dart';

/// B10: a spec-billed fee group prices a DashScope image by the size that
/// was rendered, so both DashScope image surfaces must publish it as
/// `output_size`, and must never publish empty metadata (the usage row is
/// skipped for an empty map on the non-streaming path).
void main() {
  test('usage width/height wins as the rendered size', () {
    final meta = dashscopeImageMetadata(
      data: {
        'usage': {'width': 1328, 'height': 1328, 'image_count': 1},
      },
      imageCount: 1,
      sentSize: '1024*1024',
    );
    expect(meta['output_size'], '1328x1328');
    expect(meta['image_count'], 1);
  });

  test('a usage size string is read next', () {
    final meta = dashscopeImageMetadata(
      data: {
        'usage': {'size': '1280*720'},
      },
      imageCount: 1,
      sentSize: '1K',
    );
    expect(OutputSpec.normalizeSize(meta['output_size']), '1280x720');
  });

  test('without a usage echo, the size actually sent is published', () {
    final meta =
        dashscopeImageMetadata(data: const {}, imageCount: 2, sentSize: '1K');
    expect(meta['output_size'], '1K');
    expect(meta['image_count'], 2);
    expect(OutputSpec.from(null, metadata: meta).size, '1K');
  });

  test('no usage and no size still yields non-empty metadata', () {
    final meta =
        dashscopeImageMetadata(data: const {}, imageCount: 1, sentSize: null);
    expect(meta, {'image_count': 1});
  });
}
