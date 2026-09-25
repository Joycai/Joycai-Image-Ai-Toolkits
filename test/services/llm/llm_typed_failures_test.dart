import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_descriptor.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/openai_chat_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

/// A 200 with nothing usable in it is an API failure, typed as one — the
/// protocols used to throw a bare `Exception`, which only the legacy message
/// regex in [LLMService.isRetryable] could read. And a stored message with a
/// role the app does not know is refused rather than guessed.
void main() {
  test('① a 200 with no choices is an LLMApiException, and not retried', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      await req.drain<void>();
      req.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'id': 'x', 'object': 'chat.completion', 'choices': []}));
      await req.response.close();
    });

    final config = LLMModelConfig(
      modelId: 'gpt-test',
      channelType: 'openai-api-rest',
      endpoint: 'http://127.0.0.1:${server.port}/v1',
      apiKey: 'k',
    );
    final target = LLMTarget(
      config: config,
      vendor: Vendors.byId(config.channelType),
      model: ModelDescriptor.of(config.modelId),
    );

    Object? failure;
    try {
      await OpenAIChatProtocol().generate(target, [LLMMessage(role: LLMRole.user, content: 'hi')]);
    } catch (e) {
      failure = e;
    }
    expect(failure, isA<LLMApiException>());
    expect(failure.toString(), startsWith('OpenAI API returned no choices'));
    expect(LLMService.isRetryable(failure!), isFalse);
  });

  test('an unknown stored role is refused, not read as the user', () {
    expect(
      () => LLMMessage.fromJson(const {'role': 'narrator', 'content': 'x'}),
      throwsA(isA<FormatException>()),
    );
    expect(LLMMessage.fromJson(const {'role': 'tool', 'content': 'x'}).role, LLMRole.tool);
  });
}
