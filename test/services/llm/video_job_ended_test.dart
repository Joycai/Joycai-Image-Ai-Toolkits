import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_errors.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/gemini_veo_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/minimax_h3_base_payload.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/openai_videos_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/xai_videos_protocol.dart';

/// A poll that finds the upstream job over — failed, cancelled, expired,
/// filtered — says so ([LLMApiException.isJobEnded]), so the executor drops
/// the job id and the task stops offering "resume" for a job that can only
/// fail the same way again. A job still running is not ended.
void main() {
  Matcher ended(bool value) =>
      throwsA(isA<LLMApiException>().having((e) => e.isJobEnded, 'isJobEnded', value));

  test('OpenAI videos: failed, cancelled and expired are ended', () {
    for (final status in ['failed', 'cancelled', 'expired']) {
      expect(
        () => openaiVideoPollEnvelope({'status': status}, 'op', 'https://api.example.com/v1'),
        ended(true),
        reason: status,
      );
    }
    expect(
      openaiVideoPollEnvelope(
        {'status': 'in_progress'},
        'op',
        'https://api.example.com/v1',
      )['done'],
      isNot(true),
    );
  });

  test('xAI: failed, expired, cancelled and done-without-URL are ended', () {
    for (final data in [
      {'status': 'failed'},
      {'status': 'expired'},
      {'status': 'cancelled'},
      {'status': 'done'},
    ]) {
      expect(
        () => xaiVideoPollEnvelope(data, 'op', 'https://api.x.ai/v1'),
        ended(true),
        reason: '$data',
      );
    }
  });

  test('Veo: an operation error and a safety filter are ended', () {
    expect(
      () => veoPollResult(
        {
          'done': true,
          'error': {'code': 3, 'message': 'bad'},
        },
        'op',
        'https://generativelanguage.googleapis.com/v1beta',
      ),
      ended(true),
    );
    expect(
      () => veoPollResult(
        {
          'done': true,
          'response': {
            'generateVideoResponse': {
              'raiMediaFilteredReasons': ['x'],
            },
          },
        },
        'op',
        'https://generativelanguage.googleapis.com/v1beta',
      ),
      ended(true),
    );
  });

  test('MiniMax H3 local: failed is ended', () {
    expect(
      () => minimaxH3PollEnvelope({'status': 'failed', 'error': 'oom'}, 'op', 'http://localhost/c'),
      ended(true),
    );
  });
}
