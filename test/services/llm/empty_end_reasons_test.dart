import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/dashscope_chat_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/openai_chat_parsing.dart';

/// Ends that used to pass as a normal, successful reply.
void main() {
  group('① finish_reason normalisation', () {
    test("GLM's `sensitive` is a content block", () {
      final metadata = openaiFinishMetadata('sensitive');
      expect(metadata['finish_reason'], contentFilterFinishReason);
      expect(metadata['finish_reason_raw'], 'sensitive');
      final failure = contentBlockedFailure(metadata);
      expect(failure, isNotNull);
      expect(failure!.isContentBlocked, isTrue);
      expect(failure.message, contains('sensitive'));
    });

    test('the standard spellings pass through unchanged', () {
      expect(openaiFinishMetadata('stop'), {'finish_reason': 'stop'});
      expect(openaiFinishMetadata('content_filter'), {'finish_reason': 'content_filter'});
      expect(openaiFinishMetadata(null), isEmpty);
      expect(openaiFinishMetadata(''), isEmpty);
    });
  });

  group("Bailian's native face: an empty reply", () {
    test('fails on a normal end', () {
      expect(
        dashscopeEmptyReplyFailure(sawOutput: false, finishReason: 'stop', options: null),
        isA<LLMApiException>(),
      );
      expect(
        dashscopeEmptyReplyFailure(sawOutput: false, finishReason: null, options: null),
        isA<LLMApiException>(),
      );
    });

    test('passes with output, on length or a block, or when declared', () {
      expect(
        dashscopeEmptyReplyFailure(sawOutput: true, finishReason: 'stop', options: null),
        isNull,
      );
      expect(
        dashscopeEmptyReplyFailure(sawOutput: false, finishReason: 'length', options: null),
        isNull,
      );
      expect(
        dashscopeEmptyReplyFailure(
          sawOutput: false,
          finishReason: contentFilterFinishReason,
          options: null,
        ),
        isNull,
      );
      expect(
        dashscopeEmptyReplyFailure(
          sawOutput: false,
          finishReason: 'stop',
          options: const {emptyReplyEndsTurnKey: true},
        ),
        isNull,
      );
    });
  });
}
