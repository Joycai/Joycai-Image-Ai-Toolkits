import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../tool/screenshot_diff.dart';

void main() {
  test('screenshot_diff snapshots, compares PNGs, and builds HTML report', () {
    final Directory tempRoot = Directory.systemTemp.createTempSync('joycai_diff_tool_test');
    addTearDown(() => tempRoot.deleteSync(recursive: true));

    final Directory initialDir = Directory(p.join(tempRoot.path, 'initial'))..createSync();
    final Directory baselineDir = Directory(p.join(tempRoot.path, 'baseline'));
    final Directory currentDir = Directory(p.join(tempRoot.path, 'current'))..createSync();
    final Directory outDir = Directory(p.join(tempRoot.path, 'out'));

    final img.Image solid = img.Image(width: 8, height: 8);
    img.fill(solid, color: img.ColorRgba8(100, 120, 140, 255));
    final List<int> solidPng = img.encodePng(solid);

    final img.Image modified = img.Image(width: 8, height: 8);
    img.fill(modified, color: img.ColorRgba8(100, 120, 140, 255));
    modified.setPixelRgba(3, 3, 255, 0, 0, 255);

    File(p.join(initialDir.path, 'same.png')).writeAsBytesSync(solidPng);
    File(p.join(initialDir.path, 'changed.png')).writeAsBytesSync(solidPng);

    final int snapCode = runScreenshotDiff(<String>[
      'snapshot',
      '--from',
      initialDir.path,
      '--to',
      baselineDir.path,
    ]);
    expect(snapCode, 0);
    expect(File(p.join(baselineDir.path, 'same.png')).existsSync(), isTrue);
    expect(File(p.join(baselineDir.path, 'changed.png')).existsSync(), isTrue);

    File(p.join(currentDir.path, 'same.png')).writeAsBytesSync(solidPng);
    File(p.join(currentDir.path, 'changed.png')).writeAsBytesSync(img.encodePng(modified));
    File(p.join(currentDir.path, 'added.png')).writeAsBytesSync(solidPng);

    final int cmpCode = runScreenshotDiff(<String>[
      'compare',
      '--baseline',
      baselineDir.path,
      '--current',
      currentDir.path,
      '--out',
      outDir.path,
    ]);
    expect(cmpCode, 0);
    expect(File(p.join(outDir.path, 'diffs', 'changed.png')).existsSync(), isTrue);
    final File html = File(p.join(outDir.path, 'index.html'));
    expect(html.existsSync(), isTrue);
    final String htmlText = html.readAsStringSync();
    expect(htmlText, contains('changed.png'));
    expect(htmlText, contains('added.png'));
    expect(htmlText, contains('1 changed · 1 added · 0 removed · 1 identical'));
  });
}
