import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/gpt_image_timeout.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

void main() {
  final dispatcher = LLMDispatcher();
  LLMModelConfig config(String id) => LLMModelConfig(
    modelId: id,
    channelType: Vendors.openAIRest,
    endpoint: 'http://localhost/v1',
    apiKey: '',
  );
  test('all GPT Image models default to 25 minutes; only their route keeps late results', () {
    for (final id in [
      'gpt-image-1',
      'gpt-image-2',
      'gpt-image-2.5-flare',
      'gpt-image-2.5-sunburst',
    ]) {
      expect(dispatcher.generateTimeout(config(id)), const Duration(minutes: 25));
      expect(dispatcher.keepsLateImageResults(config(id)), isTrue);
      expect(
        dispatcher.generateTimeout(config(id), options: {GptImageTimeout.settingKey: 45}),
        const Duration(minutes: 45),
      );
    }
    expect(
      dispatcher.imageStreamChunkGap(
        config('gpt-image-2'),
        options: {GptImageTimeout.settingKey: 10},
      ),
      const Duration(minutes: 10),
    );
    expect(
      dispatcher.keepsLateImageResults(
        LLMModelConfig(
          modelId: 'gpt-image-2',
          channelType: Vendors.midjourneyProxy,
          endpoint: 'http://localhost',
          apiKey: '',
        ),
      ),
      isFalse,
    );
    expect(dispatcher.keepsLateImageResults(config('gemini-2.5-flash')), isFalse);
    expect(dispatcher.keepsLateImageResults(config('seedream-5.0-pro')), isFalse);
  });
  test('missing or invalid stored preferences use the default', () {
    for (final invalid in [null, '', 'abc', 0, -1, 121, 2.5]) {
      expect(GptImageTimeout.normalize(invalid), 25);
    }
    expect(GptImageTimeout.normalize('60'), 60);
  });
  test('soft deadline retains the same pending read before and after a preview', () async {
    final source = StreamController<int>();
    final slow = [Completer<void>(), Completer<void>()];
    var warnings = 0;
    final values = <int>[];
    final done = LLMService.idleGuardedForTest(
      source.stream,
      first: const Duration(milliseconds: 20),
      subsequent: const Duration(milliseconds: 20),
      firstIsDeadline: true,
      onSlowResponse: () => slow[warnings++].complete(),
    ).forEach(values.add);
    await slow[0].future.timeout(const Duration(seconds: 5));
    expect(values, isEmpty);
    source.add(1);
    await slow[1].future.timeout(const Duration(seconds: 5));
    expect(values, [1]);
    source.add(2);
    await source.close();
    await done;
    expect(values, [1, 2]);
    expect(warnings, 2);
  });
}
