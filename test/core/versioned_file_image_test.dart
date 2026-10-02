import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:joycai_image_ai_toolkits/core/versioned_file_image.dart';

import '../support/real_async.dart';

void main() {
  testWidgets('a mounted resized thumbnail reads replacement bytes at the same path', (
    tester,
  ) async {
    late Directory dir;
    late File file;
    await runAsyncRethrowing(tester, () async {
      dir = await Directory.systemTemp.createTemp('joycai_versioned_image');
      file = File('${dir.path}/image.png');
      await file.writeAsBytes(img.encodePng(img.Image(width: 16, height: 8)));
    });
    addTearDown(() async {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      await dir.delete(recursive: true);
    });

    Future<void> show(String version) async {
      await runAsyncRethrowing(tester, () async {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Image(image: ResizeImage(VersionedFileImage(file, version: version), width: 8)),
          ),
        );
        final provider = tester.widget<Image>(find.byType(Image)).image;
        final stream = provider.resolve(ImageConfiguration.empty);
        final done = Completer<void>();
        final listener = ImageStreamListener(
          (_, _) => done.complete(),
          onError: done.completeError,
        );
        stream.addListener(listener);
        await done.future;
        stream.removeListener(listener);
      });
      await tester.pump();
    }

    await show('before');
    final before = tester.widget<RawImage>(find.byType(RawImage)).image!;
    expect(before.height, 4);
    await runAsyncRethrowing(tester, () async {
      await file.writeAsBytes(img.encodePng(img.Image(width: 16, height: 16)));
    });
    await show('after');
    final ui.Image after = tester.widget<RawImage>(find.byType(RawImage)).image!;
    expect(after.height, 8, reason: 'the visible thumbnail must display the replacement image');
  });
}
