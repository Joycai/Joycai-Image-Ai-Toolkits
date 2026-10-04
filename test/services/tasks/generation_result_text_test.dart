import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/task_item.dart';
import 'package:joycai_image_ai_toolkits/services/llm/generation/generation_request.dart';
import 'package:joycai_image_ai_toolkits/services/llm/generation/generation_schema.dart';
import 'package:joycai_image_ai_toolkits/services/tasks/generation_result_text.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;
  setUp(() async => directory = await Directory.systemTemp.createTemp('generation_text_'));
  tearDown(() async => directory.delete(recursive: true));

  TaskItem task(Map<String, dynamic> parameters, {List<String> inputs = const []}) =>
      TaskItem(id: 'test', modelId: 'test', imagePaths: inputs, parameters: parameters);

  test('off and legacy tasks create no companion file', () async {
    for (final parameters in [
      {},
      {'saveGenerationText': false},
    ]) {
      await saveGenerationResultText(
        task(Map<String, dynamic>.from(parameters)),
        p.join(directory.path, 'result.png'),
      );
    }
    expect(await directory.list().length, 0);
  });

  test('each image result gets UTF-8 prompt and input basenames', () async {
    final input = task(
      {'saveGenerationText': true, 'prompt': '猫\n  水彩 🎨'},
      inputs: ['/private/source/参考.png', '/other/photo.jpg'],
    );
    for (final name in ['result_0.png', 'result_1.jpg']) {
      await saveGenerationResultText(input, p.join(directory.path, name));
      final text = await File(p.join(directory.path, p.setExtension(name, '.txt'))).readAsString();
      expect(text, 'Input images:\n参考.png\nphoto.jpg\n\nPrompt:\n猫\n  水彩 🎨');
    }
  });

  test('video uses persisted generation snapshot including both frames and references', () async {
    final request = GenerationRequest(
      prompt: 'Animate this\nゆっくり',
      operation: GenerationOperation.values.first,
      values: {},
      media: [
        const GenerationMedia(GenerationMediaRole.firstFrame, '/in/first.png'),
        const GenerationMedia(GenerationMediaRole.lastFrame, '/in/last.png'),
        const GenerationMedia(GenerationMediaRole.reference, '/in/style.png'),
      ],
      modelId: 'test',
      channelType: 'test',
      protocolId: null,
      profileId: 'test',
    );
    final input = task(
      {'saveGenerationText': true, GenerationRequest.taskKey: request.toJson()},
      inputs: ['stale.png'],
    );
    await saveGenerationResultText(input, p.join(directory.path, 'clip.mp4'));
    expect(
      await File(p.join(directory.path, 'clip.txt')).readAsString(),
      'Input images:\nfirst.png\nlast.png\nstyle.png\n\nPrompt:\nAnimate this\nゆっくり',
    );
  });

  test('text-only generations explicitly record no input images', () async {
    await saveGenerationResultText(
      task({'saveGenerationText': true, 'prompt': 'Landscape'}),
      p.join(directory.path, 'out.png'),
    );
    expect(
      await File(p.join(directory.path, 'out.txt')).readAsString(),
      contains('Input images:\n(none)\n'),
    );
  });

  test('sidecar write failure warns without failing or removing generated media', () async {
    final media = File(p.join(directory.path, 'out.png'));
    await media.writeAsString('existing media');
    await Directory(p.join(directory.path, 'out.txt')).create();
    final input = task({'saveGenerationText': true});
    await saveGenerationResultText(input, media.path);
    expect(await media.readAsString(), 'existing media');
    expect(input.logs.last, contains('Warning: could not save generation text'));
  });
}
