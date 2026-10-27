import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/llm_channel.dart';
import 'package:joycai_image_ai_toolkits/models/llm_model.dart';
import 'package:joycai_image_ai_toolkits/models/task_item.dart';
import 'package:joycai_image_ai_toolkits/services/llm/generation/generation_request.dart';
import 'package:joycai_image_ai_toolkits/services/llm/generation/generation_schema.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:joycai_image_ai_toolkits/services/tasks/generation_task_data.dart';

void main() {
  final channel = LLMChannel(
    id: 2,
    displayName: 'test',
    endpoint: 'https://relay.invalid/v1',
    apiKey: 'never-persist-this',
    type: 'openai-api-rest',
  );
  final model = LLMModel(
    id: 1,
    modelId: 'gpt-image-2',
    modelName: 'image',
    tag: 'image',
    channelId: 2,
  );

  test('H3 snapshot carries audio/video once and restores them as separate inputs', () {
    final params = snapshotGenerationTask(
      model: LLMModel(
        id: 5,
        modelId: 'MiniMax-H3-Max',
        modelName: 'Max',
        tag: 'video',
        channelId: 2,
      ),
      channel: LLMChannel(
        id: 2,
        displayName: 'MiniMax',
        endpoint: 'https://api.minimax.cn/v1',
        apiKey: 'secret',
        type: Vendors.minimax,
      ),
      type: TaskType.videoGenerate,
      imagePaths: ['ref.png'],
      options: {
        'prompt': 'animate',
        'referenceImagePaths': ['ref.png'],
        'referenceVideoPaths': ['v.mp4'],
        'referenceAudioPaths': ['a.wav'],
        'resolution': '480P',
      },
    );
    expect(params.containsKey('referenceVideoPaths'), false);
    expect(params.containsKey('referenceAudioPaths'), false);
    final restored = jsonDecode(jsonEncode(params)) as Map<String, dynamic>;
    final options = generationTaskOptions(restored);
    expect(options['referenceImagePaths'], ['ref.png']);
    expect(options['referenceVideoPaths'], ['v.mp4']);
    expect(options['referenceAudioPaths'], ['a.wav']);
    expect(options['resolution'], '480P');
    expect(jsonEncode(params), isNot(contains('secret')));
  });

  test('new task JSON owns prompt, media and values once, retaining application metadata', () {
    final params = snapshotGenerationTask(
      model: model,
      channel: channel,
      type: TaskType.imageProcess,
      imagePaths: ['source.png'],
      options: {
        'prompt': 'cat',
        'imageSize': '2048x2048',
        'imagePrefix': 'render',
        'retryCount': 2,
        'saveGenerationText': true,
      },
    );
    expect(params, isNot(contains('prompt')));
    expect(params, isNot(contains('imageSize')));
    expect(params['imagePrefix'], 'render');
    expect(params['saveGenerationText'], isTrue);
    final decoded = GenerationRequest.fromTask(
      jsonDecode(jsonEncode(params)) as Map<String, dynamic>,
    )!;
    expect(decoded.prompt, 'cat');
    expect(decoded.operation, GenerationOperation.editImage);
    expect(decoded.media.single.path, 'source.png');
    expect(decoded.modelRowId, 1);
    expect(decoded.channelRowId, 2);
    expect(jsonEncode(params), isNot(contains(channel.apiKey)));
    final task = TaskItem(
      id: 'test',
      imagePaths: ['wrong.png'],
      modelId: 'display',
      parameters: params,
    );
    expect(task.generationImagePaths, ['source.png']);
    expect(task.generationOptions['imageSize'], '2048x2048');
    expect(task.generationSourceNeedsAlpha, isFalse);
  });

  test('old task reads unchanged and an existing snapshot is not rewritten on retry', () {
    final old = TaskItem(
      id: 'old',
      imagePaths: ['old.png'],
      modelId: 'legacy',
      parameters: {'prompt': 'old', 'quality': 'high'},
    );
    expect(old.generationImagePaths, ['old.png']);
    expect(old.generationOptions, old.parameters);
    final transparent = TaskItem(
      id: 'alpha',
      imagePaths: ['layer.png'],
      modelId: 'legacy',
      parameters: {'imageTask': 'transparent', 'compressReferenceImages': true},
    );
    expect(transparent.generationSourceNeedsAlpha, isTrue);
    final params = snapshotGenerationTask(
      model: model,
      channel: channel,
      type: TaskType.imageProcess,
      imagePaths: [],
      options: {'prompt': 'cat'},
    );
    expect(
      snapshotGenerationTask(
        model: model,
        channel: channel,
        type: TaskType.imageProcess,
        imagePaths: ['different.png'],
        options: params,
      ),
      params,
    );
  });
}
