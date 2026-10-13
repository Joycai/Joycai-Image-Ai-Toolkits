import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:joycai_image_ai_toolkits/services/tasks/external_generation_files.dart';
import 'package:joycai_image_ai_toolkits/services/tasks/generation_submission_error.dart';

void main() {
  late Directory temp;
  final png = img.encodePng(img.Image(width: 2, height: 2));
  setUp(() async {
    final created = await Directory.systemTemp.createTemp('mcp-files-review-');
    temp = Directory(await created.resolveSymbolicLinks());
  });
  tearDown(() => temp.delete(recursive: true));

  test('replacing an approved root with a symlink does not grant its new target', () async {
    final root = await Directory('${temp.path}/approved').create();
    final outside = await Directory('${temp.path}/outside').create();
    final source = await File('${outside.path}/image.png').writeAsBytes(png);
    await root.delete();
    await Link(root.path).create(outside.path);
    await expectLater(
      ExternalGenerationFiles.stage(source.path, [root.path], Directory('${temp.path}/stage'), 0),
      throwsA(
        isA<GenerationSubmissionError>().having((e) => e.code, 'code', 'referenceNotAllowed'),
      ),
    );
  }, skip: Platform.isWindows ? 'Creating symlinks requires Windows privileges' : false);

  test('missing unrelated roots do not block an approved image or registered output', () async {
    final source = await File('${temp.path}/image.png').writeAsBytes(png);
    final stage = Directory('${temp.path}/stage');
    final roots = ['${temp.path}/missing', temp.path];
    final first = await ExternalGenerationFiles.stage(source.path, roots, stage, 0);
    expect(await File(first).readAsBytes(), png);
    final second = await ExternalGenerationFiles.stage(
      source.path,
      ['${temp.path}/missing'],
      stage,
      1,
      registeredOutput: true,
    );
    expect(await File(second).readAsBytes(), png);
  });

  test('registered reads reject symlinks', () async {
    final source = await File('${temp.path}/image.png').writeAsBytes(png);
    final link = await Link('${temp.path}/link.png').create(source.path);
    await expectLater(
      ExternalGenerationFiles.read(link.path),
      throwsA(isA<GenerationSubmissionError>()),
    );
  }, skip: Platform.isWindows ? 'Creating symlinks requires Windows privileges' : false);

  test('animation pixel budget counts every frame before decoding', () async {
    final animation = img.Image(width: 2, height: 2);
    animation.addFrame(img.Image(width: 2, height: 2));
    final bytes = Uint8List.fromList(img.encodeGif(animation));
    // Two 8192 x 8192 logical frames exceed the total budget although one fits.
    final header = ByteData.sublistView(bytes);
    header.setUint16(6, 8192, Endian.little);
    header.setUint16(8, 8192, Endian.little);
    await expectLater(
      ExternalGenerationFiles.dimensions(bytes, decode: true),
      throwsA(isA<GenerationSubmissionError>()),
    );
  });

  test('a forged small canvas cannot conceal larger frame dimensions', () async {
    final bytes = Uint8List.fromList(img.encodeGif(img.Image(width: 2, height: 2)));
    final header = ByteData.sublistView(bytes);
    header.setUint16(6, 1, Endian.little);
    header.setUint16(8, 1, Endian.little);
    await expectLater(
      ExternalGenerationFiles.dimensions(bytes, decode: true),
      throwsA(isA<GenerationSubmissionError>()),
    );
  });
}
