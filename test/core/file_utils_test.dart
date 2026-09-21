import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/file_utils.dart';

void main() {
  test('safeFilenamePrefix stays inside the output directory', () {
    expect(
      FileUtils.safeFilenamePrefix('../../outside\\file'),
      '.._.._outside_file',
    );
    expect(FileUtils.safeFilenamePrefix(''), 'result');
    expect(FileUtils.safeFilenamePrefix('..'), 'result');
    expect(FileUtils.safeFilenamePrefix('  render  '), 'render');
  });

  test('safeFilenamePrefix caps unusually long input', () {
    expect(FileUtils.safeFilenamePrefix('x' * 200), hasLength(120));
  });
}
