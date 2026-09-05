import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/turn_continuation.dart';

/// Pins how a turn the host stopped halfway is continued.
///
/// The failure this guards is silent: a ④ `pause_turn` (or MiniMax's
/// `end_turn` on a search result) is a 200 with a perfectly formed body —
/// the search ran, the model wrote one line, then nothing. Treating it as
/// finished delivers that one line as the answer.
void main() {
  final searchBlocks = <Map<String, dynamic>>[
    {'type': 'text', 'text': 'Let me look.'},
    {'type': 'server_tool_use', 'id': 'srv_1', 'name': 'web_search', 'input': {'query': 'q'}},
    {
      'type': 'web_search_tool_result',
      'tool_use_id': 'srv_1',
      'content': [
        {'type': 'web_search_result', 'title': 'T', 'url': 'https://e.com/a', 'encrypted_content': 'Eqgf…'}
      ],
    },
  ];
  final runs = [
    {
      'name': 'web_search',
      'query': 'q',
      'sources': [
        {'title': 'T', 'url': 'https://e.com/a'}
      ],
    }
  ];

  group('continuationFor', () {
    test('a finished turn needs nothing', () {
      final r = LLMResponse(text: 'done', metadata: {'finish_reason': 'stop'});
      expect(continuationFor(r, 'm'), isNull);
    });

    test('pause_turn sends the assistant message back unchanged', () {
      // The API defines the remedy: the same content array, verbatim — the
      // result block's encrypted_content included.
      final r = LLMResponse(
        text: 'Let me look.',
        metadata: {'finish_reason': 'pause', 'server_tool_runs': runs},
        rawContentBlocks: searchBlocks,
      );
      final next = continuationFor(r, 'claude-opus-5')!;
      expect(next, hasLength(1));
      expect(next.single.role, LLMRole.assistant);
      expect(next.single.rawContentBlocks, same(searchBlocks));
      expect(next.single.rawThinkingModelId, 'claude-opus-5');
    });

    test('an incomplete turn on a host that rejects its own blocks goes back as text', () {
      // MiniMax answers a verbatim replay with `tool result's tool id … not
      // found`, so the results are rendered as a user turn instead.
      final r = LLMResponse(
        text: 'Let me look.',
        metadata: {
          'finish_reason': 'stop',
          'turn_incomplete': true,
          'server_tool_runs': runs,
        },
        rawContentBlocks: searchBlocks,
      );
      final next = continuationFor(r, 'MiniMax-M3')!;
      expect(next.map((m) => m.role), [LLMRole.assistant, LLMRole.user]);
      expect(next.first.rawContentBlocks, isNull);
      expect(next.first.content, 'Let me look.');
      expect(next.last.content, contains('web_search: "q"'));
      expect(next.last.content, contains('T — https://e.com/a'));
      expect(next.last.content, contains('Continue your answer'));
    });

    test('a pause whose blocks were not captured still continues, as text', () {
      final r = LLMResponse(
        text: '',
        metadata: {'finish_reason': 'pause', 'server_tool_runs': runs},
      );
      final next = continuationFor(r, 'm')!;
      // Nothing said yet, so no assistant turn to replay — only the results.
      expect(next.map((m) => m.role), [LLMRole.user]);
    });
  });

  group('renderServerToolRuns', () {
    test('a failed search says so instead of pretending it found nothing', () {
      final text = renderServerToolRuns([
        {'name': 'web_search', 'query': 'q', 'sources': [], 'error': 'max_uses_exceeded'},
      ]);
      expect(text, contains('failed: max_uses_exceeded'));
      expect(text, isNot(contains('no results')));
    });

    test('zero results is its own line', () {
      expect(renderServerToolRuns([{'name': 'web_search', 'query': 'q', 'sources': []}]),
          contains('(no results)'));
    });

    test('no runs at all still produces an instruction to continue', () {
      expect(renderServerToolRuns(null), contains('Continue your answer'));
    });
  });

  group('mergeTurnParts', () {
    test('a single part is returned as-is', () {
      final only = LLMResponse(text: 'a');
      expect(identical(mergeTurnParts([only]), only), isTrue);
    });

    test('texts join as paragraphs, tool calls come from the last part', () {
      final merged = mergeTurnParts([
        LLMResponse(text: 'Let me look.', metadata: {'finish_reason': 'pause'}),
        LLMResponse(
          text: 'Here it is.',
          metadata: {'finish_reason': 'tool_calls'},
          toolCalls: [LLMToolCall(id: 't1', name: 'f', arguments: const {})],
        ),
      ]);
      expect(merged.text, 'Let me look.\n\nHere it is.');
      expect(merged.toolCalls.single.id, 't1');
      expect(merged.metadata['finish_reason'], 'tool_calls');
      expect(merged.metadata['continuations'], 1);
    });

    test('usage is summed — every part was billed', () {
      final merged = mergeTurnParts([
        LLMResponse(text: 'a', metadata: {
          'input_tokens': 100,
          'output_tokens': 10,
          'prompt_tokens': 120,
          'cache_read_input_tokens': 20,
        }),
        LLMResponse(text: 'b', metadata: {
          'input_tokens': 200,
          'output_tokens': 30,
          'prompt_tokens': 200,
        }),
      ]);
      expect(merged.metadata['input_tokens'], 300);
      expect(merged.metadata['output_tokens'], 40);
      expect(merged.metadata['prompt_tokens'], 320);
      expect(merged.metadata['cache_read_input_tokens'], 20);
    });

    test('the content arrays concatenate so the whole turn replays as one message', () {
      final second = <Map<String, dynamic>>[
        {'type': 'text', 'text': 'Here it is.'}
      ];
      final merged = mergeTurnParts([
        LLMResponse(text: 'Let me look.', rawContentBlocks: searchBlocks,
            metadata: {'server_tool_runs': runs}),
        LLMResponse(text: 'Here it is.', rawContentBlocks: second, metadata: {}),
      ]);
      expect(merged.rawContentBlocks, [...searchBlocks, ...second]);
      expect(merged.metadata['server_tool_runs'], runs);
    });

    test('parts without any content array leave the merged one null', () {
      final merged = mergeTurnParts([LLMResponse(text: 'a'), LLMResponse(text: 'b')]);
      expect(merged.rawContentBlocks, isNull);
    });
  });
}
