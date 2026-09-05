import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/temp_storage_service.dart';
import 'package:path/path.dart' as p;

/// Covers the reaper for `<temp>/joycai`, the app's own scratch space.
///
/// Nothing collected it before: masks, crop copies and the downloader's page
/// cache accumulated for as long as the OS left its temp directory alone,
/// which on a desktop that is never rebooted is forever.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  // A directory of this test's own, never the real one. `getTemporaryDirectory`
  // on a dev machine can resolve to the same place the installed app uses, and
  // these tests delete what they find.
  late Directory sandbox;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('temp_storage_test');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => sandbox.path,
    );
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  /// Writes `<sandbox>/joycai/<relative>` with [bytes] bytes, aged [age].
  File seed(String relative, {int bytes = 16, Duration age = Duration.zero}) {
    final file = File(p.join(sandbox.path, 'joycai', relative));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(List.filled(bytes, 0));
    if (age > Duration.zero) {
      file.setLastModifiedSync(DateTime.now().subtract(age));
    }
    return file;
  }

  test('sweep takes what has gone cold and leaves what has not', () async {
    final stale = seed('masks/old.png', age: const Duration(days: 8));
    final fresh = seed('masks/new.png', age: const Duration(days: 6));
    final staleCrop = seed('processed/old_crop.png', age: const Duration(days: 30));
    final staleCache = seed('cache/downloader/page.html', age: const Duration(days: 9));
    // Owned by VideoThumbnailService, which prunes on a longer schedule of its
    // own; a stale entry here must survive this sweep.
    final foreign = seed('video_thumbnails/abc.jpg', age: const Duration(days: 60));

    await TempStorageService.instance.sweep();

    expect(stale.existsSync(), isFalse);
    expect(staleCrop.existsSync(), isFalse);
    expect(staleCache.existsSync(), isFalse);
    expect(fresh.existsSync(), isTrue, reason: 'Six days is inside the week');
    expect(foreign.existsSync(), isTrue, reason: 'video_thumbnails is not this sweep to make');

    // Directories stay: two other services hold a cached Directory for their
    // own subfolder and write through it without checking it still exists.
    expect(Directory(p.join(sandbox.path, 'joycai', 'masks')).existsSync(), isTrue);
  });

  test('sweep runs once per session', () async {
    // The first call in this file already consumed the guard, so a file that
    // is stale by any measure survives here. That is the contract: startup is
    // the one moment nothing holds these files.
    final stale = seed('masks/later.png', age: const Duration(days: 90));

    await TempStorageService.instance.sweep();

    expect(stale.existsSync(), isTrue);
  });

  test('measure counts the whole tree, video thumbnails included', () async {
    seed('masks/a.png', bytes: 100);
    seed('processed/b.png', bytes: 250);
    seed('video_thumbnails/c.jpg', bytes: 400);

    expect(await TempStorageService.instance.measure(), 750);
  });

  test('measure reports nothing when the app has written nothing', () async {
    expect(await TempStorageService.instance.measure(), 0);
  });

  test('clear takes every file regardless of age and reports what it freed', () async {
    final fresh = seed('masks/fresh.png', bytes: 100);
    final foreign = seed('video_thumbnails/c.jpg', bytes: 400);

    final freed = await TempStorageService.instance.clear();

    expect(freed, 500);
    expect(fresh.existsSync(), isFalse);
    expect(foreign.existsSync(), isFalse,
        reason: 'Asked for the space back, the user means all of it');
    expect(Directory(p.join(sandbox.path, 'joycai', 'masks')).existsSync(), isTrue);
    expect(await TempStorageService.instance.measure(), 0);
  });
}
