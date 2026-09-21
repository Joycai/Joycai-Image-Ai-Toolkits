import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/token_usage.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';

/// Usage recording runs after the provider already generated and billed the
/// output (standard 06 §1: best-effort, never throws). A failing write used
/// to propagate out of request() / startLongRunning(), turning a delivered
/// image into a failed task and dropping an accepted video job's ticket.
void main() {
  tearDown(() => LLMService.usageSinkOverride = null);

  LLMModelConfig config() => LLMModelConfig(
        modelId: 'gpt-image-1',
        channelType: 'openai-api-rest',
        endpoint: 'https://example.invalid/v1',
        apiKey: 'k',
      );

  test('a throwing usage sink is swallowed and logged at WARN', () async {
    LLMService.usageSinkOverride = (_) async => throw StateError('db locked');
    final logs = <(String, String)>[];
    final service = LLMService();
    final listener = service.addLogListener(
        (msg, {level = 'INFO', contextId}) => logs.add((msg, level)));
    addTearDown(() => service.removeLogListener(listener));

    await expectLater(
      service.recordUsageForTest(config(), const {'prompt_tokens': 3}),
      completes,
    );
    expect(logs.where((l) => l.$2 == 'WARN' && l.$1.contains('db locked')),
        isNotEmpty);
  });

  test('the row still reaches a working sink', () async {
    final rows = <TokenUsage>[];
    LLMService.usageSinkOverride = (row) async => rows.add(row);
    await LLMService().recordUsageForTest(config(), const {'prompt_tokens': 3});
    expect(rows.single.inputTokens, 3);
  });
}
