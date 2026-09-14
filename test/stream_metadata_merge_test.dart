import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';

/// A stream's metadata is merged across chunks, not replaced by the last one.
/// On ③ a trailing usage-only chunk arrived after the chunk that carried the
/// finish, and replacing dropped `finish_reason` — `content_filter` included,
/// which batch A now throws on — so blocked output passed as a success.
void main() {
  Map<String, dynamic>? fold(List<Map<String, dynamic>?> chunks) {
    Map<String, dynamic>? acc;
    for (final c in chunks) {
      acc = LLMService.mergeChunkMetadata(acc, c);
    }
    return acc;
  }

  test('a trailing usage-only chunk keeps the earlier finish_reason', () {
    final merged = fold([
      {'finish_reason': 'stop', 'promptTokenCount': 10},
      null,
      {'promptTokenCount': 12, 'candidatesTokenCount': 40},
    ])!;
    expect(merged['finish_reason'], 'stop');
    expect(merged['promptTokenCount'], 12, reason: 'later counters win');
    expect(merged['candidatesTokenCount'], 40);
  });

  test('content_filter survives a trailing usage chunk and still fails', () {
    final merged = fold([
      {'finish_reason': contentFilterFinishReason, 'finish_reason_raw': 'SAFETY'},
      {'promptTokenCount': 5, 'finish_reason': null},
    ]);
    expect(merged!['finish_reason'], contentFilterFinishReason);
    expect(contentBlockedFailure(merged), isNotNull);
  });

  test('a later STOP does not un-block a content_filter', () {
    final merged = fold([
      {'finish_reason': contentFilterFinishReason},
      {'finish_reason': 'stop'},
    ]);
    expect(merged!['finish_reason'], contentFilterFinishReason);
  });

  test('a later non-null finish otherwise wins', () {
    final merged = fold([
      {'finish_reason': 'length'},
      {'finish_reason': 'stop'},
    ]);
    expect(merged!['finish_reason'], 'stop');
  });

  test('no metadata at all stays null', () {
    expect(fold([null, null]), isNull);
  });

  test('the first chunk is copied, not aliased', () {
    final first = <String, dynamic>{'finish_reason': 'stop'};
    final merged = LLMService.mergeChunkMetadata(null, first)!;
    merged['x'] = 1;
    expect(first.containsKey('x'), isFalse);
  });
}
