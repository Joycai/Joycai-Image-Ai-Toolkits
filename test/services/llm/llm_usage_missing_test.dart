import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';

/// A token-billed call whose provider reported no usage is recorded as zero
/// tokens, which reads as a free request (pitfalls 11 §A8). It is warned about
/// — never thrown, and no column is added.
void main() {
  LLMModelConfig config(String billingMode) => LLMModelConfig(
    modelId: 'm',
    channelType: 'openai-api-rest',
    endpoint: 'https://example.invalid/v1',
    apiKey: 'k',
    billingMode: billingMode,
  );

  test('token billing with no usage at all is flagged', () {
    expect(LLMService.usageMissing(config('token'), const {}), isTrue);
    expect(LLMService.usageMissing(config('token'), const {'finish_reason': 'stop'}), isTrue);
    expect(
      LLMService.usageMissing(config('token'), const {'prompt_tokens': 0, 'completion_tokens': 0}),
      isTrue,
    );
  });

  test('any reported count is usage', () {
    expect(LLMService.usageMissing(config('token'), const {'prompt_tokens': 12}), isFalse);
    expect(LLMService.usageMissing(config('token'), const {'candidatesTokenCount': 3}), isFalse);
    expect(LLMService.usageMissing(config('token'), const {'output_tokens': 5}), isFalse);
  });

  test('request- and spec-billed groups never warn', () {
    expect(LLMService.usageMissing(config('request'), const {}), isFalse);
    expect(LLMService.usageMissing(config('spec'), const {}), isFalse);
  });
}
