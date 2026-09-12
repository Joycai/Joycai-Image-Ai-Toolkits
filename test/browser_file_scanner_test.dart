import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/browser_file.dart';
import 'package:joycai_image_ai_toolkits/services/browser_file_scanner.dart';
import 'package:path/path.dart' as p;

/// `scanBrowserFiles`: the file browser's folder scan, and the running count
/// behind 「正在扫描 {n} 个文件…」.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('joycai_scan_test'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // The OS reaps temp dirs anyway.
    }
  });

  void write(String name) => File(p.join(dir.path, name)).writeAsStringSync('x');

  test('lists the files in a folder, not in its subfolders, by category', () async {
    for (final name in ['a.png', 'b.mp4', 'c.mp3', 'd.txt', 'e.bin']) {
      write(name);
    }
    Directory(p.join(dir.path, 'sub')).createSync();
    File(p.join(dir.path, 'sub', 'f.png')).writeAsStringSync('x');

    final files = await scanBrowserFiles([dir.path]);

    expect(
      {for (final f in files) f['name'] as String: f['categoryIndex'] as int},
      {'a.png': 1, 'b.mp4': 2, 'c.mp3': 3, 'd.txt': 4, 'e.bin': 5},
    );
  });

  test('reports a rising count of the files found while it scans', () async {
    for (var i = 0; i < 40; i++) {
      write('f$i.png');
    }
    final reports = <int>[];

    final files = await scanBrowserFiles([dir.path], onProgress: reports.add, progressInterval: Duration.zero);

    expect(files, hasLength(40));
    expect(reports, isNotEmpty, reason: 'the scan never reported a count');
    for (var i = 1; i < reports.length; i++) {
      expect(reports[i], greaterThan(reports[i - 1]));
    }
    expect(reports.last, lessThanOrEqualTo(40));
  });

  /// The scanner used to carry its own extension table, which had drifted
  /// from `BrowserFile.categoryOf`: these four were categorised in one and
  /// `other` in the other, so a listed file and the same file restored from a
  /// staging mark disagreed about what it was.
  test('classifies a file exactly as BrowserFile.categoryOf does', () async {
    const names = ['clip.m4v', 'song.wma', 'rows.csv', 'app.log', 'photo.JPG', 'thing.bin'];
    for (final name in names) {
      write(name);
    }

    final files = await scanBrowserFiles([dir.path]);

    expect(
      {for (final f in files) f['name'] as String: f['categoryIndex'] as int},
      {for (final name in names) name: BrowserFile.categoryOf(name).index},
    );
    expect(
      {for (final f in files) f['name'] as String: f['categoryIndex'] as int},
      {
        'clip.m4v': FileCategory.video.index,
        'song.wma': FileCategory.audio.index,
        'rows.csv': FileCategory.text.index,
        'app.log': FileCategory.text.index,
        'photo.JPG': FileCategory.image.index,
        'thing.bin': FileCategory.other.index,
      },
    );
  });

  test('a folder that is not there lists nothing and does not throw', () async {
    final files = await scanBrowserFiles([p.join(dir.path, 'missing')], onProgress: (_) {});
    expect(files, isEmpty);
  });
}
