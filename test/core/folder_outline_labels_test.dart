import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/folder_outline_labels.dart';

/// A chip says the folder's basename, and just enough of the path above it
/// to tell two same-named folders apart.
void main() {
  test('distinct basenames stay bare', () {
    expect(folderOutlineLabels(['/w/render/out', '/w/render/in', '/w/tmp']), ['out', 'in', 'tmp']);
  });

  test('a shared basename takes one parent segment on both sides', () {
    expect(folderOutlineLabels(['/w/render/out/a', '/w/render/tmp/a', '/w/b']), [
      'out / a',
      'tmp / a',
      'b',
    ]);
  });

  test('keeps climbing while the tails still collide', () {
    expect(folderOutlineLabels(['/x/out/a', '/y/out/a']), ['x / out / a', 'y / out / a']);
  });

  test('only the colliding pair grows, not a third folder that happens to share a parent', () {
    expect(folderOutlineLabels(['/w/out/a', '/w/tmp/a', '/w/out/b']), ['out / a', 'tmp / a', 'b']);
  });

  test('collision is case-insensitive, like the folder order', () {
    expect(folderOutlineLabels(['/w/out/A', '/w/tmp/a']), ['out / A', 'tmp / a']);
  });

  test('identical paths cannot be told apart and are left alone', () {
    expect(folderOutlineLabels(['/w/a', '/w/a']), ['a', 'a']);
  });

  test('windows paths split on the backslash too', () {
    expect(folderOutlineLabels([r'C:\work\out\a', r'C:\work\tmp\a']), ['out / a', 'tmp / a']);
  });

  test('empty input, empty output', () {
    expect(folderOutlineLabels(const []), isEmpty);
  });
}
