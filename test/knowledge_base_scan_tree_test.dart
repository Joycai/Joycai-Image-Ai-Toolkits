import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/knowledge_base_service.dart';
import 'package:path/path.dart' as p;

/// Counts behind the knowledge-base status card.
///
/// The number shown to the user is a promise about what the assistant can
/// reach. If it counts files the agent cannot read, it is worse than showing
/// nothing — so these pin it to exactly `listFiles`' rules rather than to a
/// raw directory walk.
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('kb_scan_'));
  tearDown(() => root.deleteSync(recursive: true));

  void writeFile(String relPath, {String body = '# rule'}) {
    final file = File(p.join(root.path, relPath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(body);
  }

  KbTreeStats scan() => KnowledgeBaseService().scanTree(root.path);

  test('counts markdown files across the whole tree, not just the top level', () {
    writeFile('README.md');
    writeFile('04_cosplay.md');
    writeFile('07_footwear/07b_socks.md');
    writeFile('07_footwear/deep/nested.md');

    final stats = scan();
    expect(stats.files, 4);
    expect(stats.directories, 2);
  });

  test('ignores anything the agent cannot read', () {
    // listFiles surfaces only non-hidden .md; the count has to agree, or the
    // card advertises documents the assistant will never open.
    writeFile('README.md');
    writeFile('notes.txt');
    writeFile('image.png');
    writeFile('.hidden/secret.md');

    final stats = scan();
    expect(stats.files, 1);
    expect(stats.directories, 0, reason: 'A hidden directory was counted');
  });

  test('an empty base reports zero and no timestamp', () {
    final stats = scan();
    expect(stats.files, 0);
    expect(stats.directories, 0);
    expect(stats.newestModified, isNull);
  });

  test('reports the newest modification time in the tree', () async {
    // This is what the card shows as "content updated at" — the honest answer
    // to "will the assistant see the edit I just made". It has to track the
    // newest file anywhere, including nested ones.
    writeFile('README.md');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    writeFile('07_footwear/07b_socks.md');

    final newest = File(p.join(root.path, '07_footwear', '07b_socks.md')).statSync().modified;
    final stats = scan();

    expect(stats.newestModified, isNotNull);
    expect(
      stats.newestModified!.difference(newest).abs(),
      lessThan(const Duration(seconds: 1)),
      reason: 'Did not pick up the most recently written file',
    );
  });

  test('a deeply nested base terminates instead of recursing forever', () {
    // The containment check is lexical, so a symlink loop inside the root
    // would pass it. A depth cap is the cheap guard; this pins that it holds.
    var path = 'a';
    for (var i = 0; i < 30; i++) {
      path = p.join(path, 'a');
    }
    writeFile(p.join(path, 'deep.md'));

    expect(scan, returnsNormally);
  });
}
