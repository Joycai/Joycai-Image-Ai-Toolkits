import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/media/video_thumbnail_service.dart';

/// The platform extractor fails transiently on a file that is still being
/// written or still syncing down from a cloud drive. The service must keep
/// trying on a short backoff, share one attempt between concurrent callers,
/// and give up at once on a file that is simply not there.
void main() {
  late Directory tmp;
  late File video;
  late VideoThumbnailService service;
  late List<Duration> waits;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('vts_');
    video = File('${tmp.path}/clip.mp4')..writeAsBytesSync([1, 2, 3]);
    service = VideoThumbnailService.instance
      ..cacheDirOverride = Directory('${tmp.path}/cache')
      ..extractorOverride = null;
    waits = [];
    service.wait = (d) async => waits.add(d);
    await service.cacheDirOverride!.create();
  });

  tearDown(() async {
    service
      ..cacheDirOverride = null
      ..extractorOverride = null
      ..wait = (d) => Future<void>.delayed(d);
    await tmp.delete(recursive: true);
  });

  test('a transient extraction failure is retried on the backoff', () async {
    var calls = 0;
    service.extractorOverride = (src, dest) async {
      calls++;
      if (calls < 3) return false;
      File(dest).writeAsBytesSync([0xFF, 0xD8]);
      return true;
    };

    final path = await service.getThumbnail(video.path);

    expect(path, isNotNull);
    expect(File(path!).existsSync(), isTrue);
    expect(calls, 3);
    expect(waits, VideoThumbnailService.retryDelays);
  });

  test('after the last retry the caller gets null', () async {
    var calls = 0;
    service.extractorOverride = (src, dest) async {
      calls++;
      return false;
    };

    expect(await service.getThumbnail(video.path), isNull);
    expect(calls, VideoThumbnailService.retryDelays.length + 1);
  });

  test('a missing source file is not retried', () async {
    var calls = 0;
    service.extractorOverride = (src, dest) async {
      calls++;
      return false;
    };

    expect(await service.getThumbnail('${tmp.path}/nope.mp4'), isNull);
    expect(calls, 0);
    expect(waits, isEmpty);
  });

  test('concurrent requests for one file share a single extraction', () async {
    var calls = 0;
    service.extractorOverride = (src, dest) async {
      calls++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      File(dest).writeAsBytesSync([0xFF, 0xD8]);
      return true;
    };

    final results = await Future.wait([
      service.getThumbnail(video.path),
      service.getThumbnail(video.path),
      service.getThumbnail(video.path),
    ]);

    expect(results.toSet().single, isNotNull);
    expect(calls, 1);
  });

  test('a cached thumbnail is returned without touching the extractor',
      () async {
    var calls = 0;
    service.extractorOverride = (src, dest) async {
      calls++;
      File(dest).writeAsBytesSync([0xFF, 0xD8]);
      return true;
    };

    final first = await service.getThumbnail(video.path);
    final second = await service.getThumbnail(video.path);

    expect(second, first);
    expect(calls, 1);
  });
}
