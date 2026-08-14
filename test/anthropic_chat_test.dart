import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_descriptor.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/anthropic_chat_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

/// Pins the ④-family rules that have no counterpart in ① or ③, and that the
/// API answers with a 400 rather than a hint: system is not a role, tool
/// results are user turns, roles must alternate, `max_tokens` is mandatory —
/// plus the usage arithmetic, where ④'s buckets do not overlap and every
/// other family's do (landscape.md §1, §5).
void main() {
  LLMTarget target(
    String modelId, {
    String channelType = Vendors.anthropicRest,
    bool thinking = false,
    bool webSearch = false,
  }) {
    final config = LLMModelConfig(
      modelId: modelId,
      channelType: channelType,
      endpoint: 'https://relay.example.com/v1',
      apiKey: 'k',
      enableThinking: thinking,
      enableWebSearch: webSearch,
    );
    return LLMTarget(
      config: config,
      vendor: Vendors.byId(config.channelType),
      model: ModelDescriptor.of(config.modelId),
    );
  }

  Map<String, dynamic> payload(
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    List<LLMTool>? tools,
    bool isStreaming = false,
  }) =>
      prepareAnthropicPayload(
        target('claude-opus-5'),
        history,
        options: options,
        tools: tools,
        isStreaming: isStreaming,
      );

  group('history conversion', () {
    test('system leaves the message array for the top-level field', () {
      final p = payload([
        LLMMessage(role: LLMRole.system, content: 'be brief'),
        LLMMessage(role: LLMRole.user, content: 'hi'),
      ]);
      expect(p['system'], 'be brief');
      expect(p['messages'], [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'hi'}
          ]
        }
      ]);
    });

    test('several system turns are joined, not dropped', () {
      final p = payload([
        LLMMessage(role: LLMRole.system, content: 'first'),
        LLMMessage(role: LLMRole.system, content: 'second'),
        LLMMessage(role: LLMRole.user, content: 'hi'),
      ]);
      expect(p['system'], 'first\n\nsecond');
    });

    test('no system prompt means no system field at all', () {
      final p = payload([LLMMessage(role: LLMRole.user, content: 'hi')]);
      expect(p.containsKey('system'), isFalse);
    });

    test('a batch of tool results travels in one user turn', () {
      // The API requires alternating roles, so N results for N parallel calls
      // cannot be N messages — they have to be N blocks of one. An agent loop
      // that calls two tools in a turn hits this on its very first reply.
      final p = payload([
        LLMMessage(role: LLMRole.user, content: 'do both'),
        LLMMessage(role: LLMRole.assistant, content: '', toolCalls: [
          LLMToolCall(id: 'toolu_1', name: 'a', arguments: {'x': 1}),
          LLMToolCall(id: 'toolu_2', name: 'b', arguments: const {}),
        ]),
        LLMMessage(role: LLMRole.tool, content: 'ra', toolCallId: 'toolu_1'),
        LLMMessage(role: LLMRole.tool, content: 'rb', toolCallId: 'toolu_2'),
      ]);

      final messages = p['messages'] as List;
      expect(messages, hasLength(3));
      expect(messages[1], {
        'role': 'assistant',
        'content': [
          {'type': 'tool_use', 'id': 'toolu_1', 'name': 'a', 'input': {'x': 1}},
          {'type': 'tool_use', 'id': 'toolu_2', 'name': 'b', 'input': <String, dynamic>{}},
        ]
      });
      expect(messages[2], {
        'role': 'user',
        'content': [
          {'type': 'tool_result', 'tool_use_id': 'toolu_1', 'content': 'ra'},
          {'type': 'tool_result', 'tool_use_id': 'toolu_2', 'content': 'rb'},
        ]
      });
    });

    test('a tool that returned nothing still sends a non-empty block', () {
      final p = payload([
        LLMMessage(role: LLMRole.user, content: 'go'),
        LLMMessage(role: LLMRole.assistant, content: '', toolCalls: [
          LLMToolCall(id: 'toolu_1', name: 'a', arguments: const {}),
        ]),
        LLMMessage(role: LLMRole.tool, content: '', toolCallId: 'toolu_1'),
      ]);
      final blocks = (p['messages'] as List).last['content'] as List;
      expect(blocks.single['content'], isNotEmpty);
    });

    test('an assistant turn with nothing in it is not sent', () {
      // Neither text nor a tool call means no content blocks, and an empty
      // content array is itself a 400.
      final p = payload([
        LLMMessage(role: LLMRole.user, content: 'hi'),
        LLMMessage(role: LLMRole.assistant, content: ''),
        LLMMessage(role: LLMRole.user, content: 'still there?'),
      ]);
      final messages = p['messages'] as List;
      expect(messages, hasLength(1));
      expect((messages.single['content'] as List), hasLength(2));
    });

    test('an assistant turn keeps its text alongside its tool calls', () {
      final p = payload([
        LLMMessage(role: LLMRole.user, content: 'hi'),
        LLMMessage(
          role: LLMRole.assistant,
          content: 'let me look',
          toolCalls: [LLMToolCall(id: 'toolu_1', name: 'a', arguments: const {})],
        ),
      ]);
      final blocks = (p['messages'] as List)[1]['content'] as List;
      expect(blocks.first['type'], 'text');
      expect(blocks.last['type'], 'tool_use');
    });

    test('an image rides as a base64 source block', () {
      final p = payload([
        LLMMessage(
          role: LLMRole.user,
          content: 'what is this',
          attachments: [
            LLMAttachment.fromBytes(
                Uint8List.fromList([1, 2, 3]), 'image/png'),
          ],
        ),
      ]);
      final blocks = (p['messages'] as List).single['content'] as List;
      expect(blocks.last['type'], 'image');
      expect(blocks.last['source']['type'], 'base64');
      expect(blocks.last['source']['media_type'], 'image/png');
    });
  });

  group('request envelope', () {
    test('max_tokens is always present — the API has no default', () {
      final p = payload([LLMMessage(role: LLMRole.user, content: 'hi')]);
      expect(p['max_tokens'], anthropicDefaultMaxTokens);
    });

    test('the caller can raise the cap', () {
      final p = payload(
        [LLMMessage(role: LLMRole.user, content: 'hi')],
        options: {'maxTokens': 32000},
      );
      expect(p['max_tokens'], 32000);
    });

    test('a nonsensical cap falls back rather than being sent', () {
      for (final bad in [0, -1, 'lots', null]) {
        expect(
          payload([LLMMessage(role: LLMRole.user, content: 'hi')],
              options: {'maxTokens': bad})['max_tokens'],
          anthropicDefaultMaxTokens,
          reason: '$bad',
        );
      }
    });

    test('sampling parameters are never sent', () {
      // Anthropic's current generation 400s on a non-default temperature /
      // top_p / top_k unconditionally, and nothing in the app asks for one.
      final p = payload(
        [LLMMessage(role: LLMRole.user, content: 'hi')],
        options: {'temperature': 0.7, 'topP': 0.9, 'topK': 40},
      );
      expect(p.keys, isNot(contains('temperature')));
      expect(p.keys, isNot(contains('top_p')));
      expect(p.keys, isNot(contains('top_k')));
    });

    test('tools are flat, with the schema under input_schema', () {
      final p = payload(
        [LLMMessage(role: LLMRole.user, content: 'hi')],
        tools: [
          LLMTool(
            name: 'read_file',
            description: 'reads',
            parameters: {'type': 'object', 'properties': <String, dynamic>{}},
          )
        ],
      );
      expect(p['tools'], [
        {
          'name': 'read_file',
          'description': 'reads',
          'input_schema': {'type': 'object', 'properties': <String, dynamic>{}},
        }
      ]);
      // `auto` only: the forcing modes are the first thing ④ compat layers
      // drop, and nothing here depends on them.
      expect(p['tool_choice'], {'type': 'auto'});
    });

    test('no tools means no tool_choice', () {
      final p = payload([LLMMessage(role: LLMRole.user, content: 'hi')]);
      expect(p.containsKey('tools'), isFalse);
      expect(p.containsKey('tool_choice'), isFalse);
    });
  });

  group('response content blocks', () {
    test('text, thinking and tool calls each land in their own channel', () {
      final content = parseAnthropicContent([
        {'type': 'thinking', 'thinking': 'hmm', 'signature': 'sig'},
        {'type': 'text', 'text': 'the answer'},
        {'type': 'tool_use', 'id': 'toolu_1', 'name': 'f', 'input': {'a': 1}},
      ]);
      expect(content.text, 'the answer');
      expect(content.thinking, 'hmm');
      expect(content.toolCalls.single.id, 'toolu_1');
      expect(content.toolCalls.single.arguments, {'a': 1});
    });

    test('an unknown block type costs the blocks around it nothing', () {
      // ④ grows block types without a version bump — server tool use, search
      // results, citations — so an unrecognized one must be inert, not fatal.
      final content = parseAnthropicContent([
        {'type': 'text', 'text': 'before'},
        {'type': 'code_execution_tool_result', 'content': []},
        {'type': 'redacted_thinking', 'data': 'opaque'},
        {'type': 'text', 'text': 'after'},
      ]);
      expect(content.text, 'before\n\nafter');
      expect(content.thinking, isNull);
    });

    test('a malformed content field yields nothing, never a throw', () {
      expect(parseAnthropicContent(null).text, isEmpty);
      expect(parseAnthropicContent('nope').text, isEmpty);
      expect(parseAnthropicContent(['nope']).text, isEmpty);
    });
  });

  group('usage accounting', () {
    test('the three input buckets are summed into a comparable total', () {
      // input_tokens excludes what the cache served, unlike every other
      // family. Reporting it as the prompt total would under-count a long
      // cached prompt by an order of magnitude — and the shared accounting
      // then subtracts the cached part out of it a second time.
      final metadata = anthropicUsageMetadata({
        'input_tokens': 100,
        'cache_read_input_tokens': 9000,
        'cache_creation_input_tokens': 500,
        'output_tokens': 42,
      });
      expect(metadata['prompt_tokens'], 9600);
      expect(metadata['output_tokens'], 42);
      // The raw buckets survive for the debug log and for cache billing.
      expect(metadata['input_tokens'], 100);
      expect(metadata['cache_read_input_tokens'], 9000);
    });

    test('absent cache buckets simply count as zero', () {
      final metadata =
          anthropicUsageMetadata({'input_tokens': 7, 'output_tokens': 3});
      expect(metadata['prompt_tokens'], 7);
    });

    test('no usage at all publishes no token total', () {
      final metadata = anthropicUsageMetadata(null, stopReason: 'end_turn');
      expect(metadata.containsKey('prompt_tokens'), isFalse);
      expect(metadata['stop_reason'], 'end_turn');
    });

    test('a truncated answer is reported in the vocabulary callers check', () {
      // The assistant loop and the web scraper both test for
      // `finish_reason == 'length'`; ④ spells that `stop_reason: max_tokens`,
      // and the app's default cap makes it a reachable case.
      expect(anthropicFinishReason('max_tokens'), 'length');
      expect(anthropicFinishReason('tool_use'), 'tool_calls');
      expect(anthropicFinishReason('refusal'), 'content_filter');
      expect(anthropicFinishReason('end_turn'), 'stop');
      expect(anthropicFinishReason('stop_sequence'), 'stop');
      expect(anthropicFinishReason(null), isNull);
    });
  });

  group('authentication', () {
    test('the version header is not optional', () {
      final headers = Vendors.byId(Vendors.anthropicRest)
          .headers('secret', 'https://api.anthropic.com/v1');
      expect(headers['anthropic-version'], isNotEmpty);
      expect(headers['x-api-key'], 'secret');
    });

    test('Anthropic itself is the one host that gets no bearer token', () {
      final official = Vendors.byId(Vendors.anthropicRest)
          .headers('secret', 'https://api.anthropic.com/v1');
      expect(official.containsKey('Authorization'), isFalse);
    });

    test('a relay gets both spellings, since it documents neither', () {
      final relay = Vendors.byId(Vendors.newApiAnthropic)
          .headers('secret', 'https://relay.example.com/v1');
      expect(relay['x-api-key'], 'secret');
      expect(relay['Authorization'], 'Bearer secret');
    });

    test('the key never reaches the query string', () {
      // Only Google's schemes use `?key=`; the URL decoration used to treat
      // "not bearer" as "wants a key parameter", which would have leaked an
      // Anthropic key into every logged URL.
      final url = Uri.parse('https://relay.example.com/v1/messages');
      expect(
        Vendors.byId(Vendors.anthropicRest).decorateUrl(url, 'secret'),
        url,
      );
    });
  });

  group('thinking', () {
    Map<String, dynamic> payloadFor(String channelType, {bool thinking = true}) =>
        prepareAnthropicPayload(
          target('m', channelType: channelType, thinking: thinking),
          [LLMMessage(role: LLMRole.user, content: 'hi')],
          isStreaming: false,
        );

    test('each host gets its own spelling — there is no shared one', () {
      // MiniMax says `adaptive`, Anthropic says `enabled` with a budget. A
      // single hardcoded shape would be a 400 on one of the two, which is why
      // the dialect is declared on the vendor rather than guessed here.
      expect(payloadFor(Vendors.minimaxAnthropic)['thinking'],
          {'type': 'adaptive'});
      expect(payloadFor(Vendors.anthropicRest)['thinking'],
          {'type': 'enabled', 'budget_tokens': anthropicDefaultMaxTokens ~/ 2});
    });

    test('switched off means the parameter is absent, not false', () {
      for (final id in [Vendors.anthropicRest, Vendors.minimaxAnthropic]) {
        expect(payloadFor(id, thinking: false).containsKey('thinking'), isFalse,
            reason: id);
      }
    });

    test('the budget respects the API floor and still leaves room to answer', () {
      // Below 1024 the request is rejected rather than clamped, and a budget
      // that eats the whole cap leaves nothing for the answer — in which case
      // the request goes out without thinking instead of failing.
      final small = prepareAnthropicPayload(
        target('m', thinking: true),
        [LLMMessage(role: LLMRole.user, content: 'hi')],
        options: {'maxTokens': 1500},
        isStreaming: false,
      );
      expect(small['thinking'], {'type': 'enabled', 'budget_tokens': 1024});

      final tiny = prepareAnthropicPayload(
        target('m', thinking: true),
        [LLMMessage(role: LLMRole.user, content: 'hi')],
        options: {'maxTokens': 900},
        isStreaming: false,
      );
      expect(tiny.containsKey('thinking'), isFalse);
    });

    test('a sealed thinking block is replayed ahead of the tool call', () {
      // With thinking on, ④ rejects a replayed tool-calling turn whose
      // thinking block is missing — and the block has to come first.
      final p = prepareAnthropicPayload(
        target('m', thinking: true),
        [
          LLMMessage(role: LLMRole.user, content: 'go'),
          LLMMessage(
            role: LLMRole.assistant,
            content: 'looking',
            reasoningContent: 'I should search',
            reasoningSignature: 'sig-abc',
            toolCalls: [LLMToolCall(id: 'toolu_1', name: 'a', arguments: const {})],
          ),
        ],
        isStreaming: false,
      );
      final blocks = (p['messages'] as List)[1]['content'] as List;
      expect(blocks.map((b) => b['type']), ['thinking', 'text', 'tool_use']);
      expect(blocks.first['signature'], 'sig-abc');
    });

    test('an unsealed one is dropped rather than sent to be rejected', () {
      final p = prepareAnthropicPayload(
        target('m', thinking: true),
        [
          LLMMessage(role: LLMRole.user, content: 'go'),
          LLMMessage(
            role: LLMRole.assistant,
            content: 'answer',
            reasoningContent: 'thought that arrived without a signature',
          ),
        ],
        isStreaming: false,
      );
      final blocks = (p['messages'] as List)[1]['content'] as List;
      expect(blocks.map((b) => b['type']), ['text']);
    });

    test('the response carries the seal out to the next request', () {
      final content = parseAnthropicContent([
        {'type': 'thinking', 'thinking': 'hmm', 'signature': 'sig-abc'},
        {'type': 'text', 'text': 'done'},
      ]);
      expect(content.thinking, 'hmm');
      expect(content.thinkingSignature, 'sig-abc');
    });
  });

  group('server-side tools', () {
    test('web search is declared by type, with no schema of its own', () {
      // A server tool is run by the host, so there is nothing for the caller
      // to validate arguments against.
      final p = prepareAnthropicPayload(
        target('MiniMax-M3', channelType: Vendors.minimaxAnthropic, webSearch: true),
        [LLMMessage(role: LLMRole.user, content: 'weather?')],
        isStreaming: false,
      );
      expect(p['tools'], [
        {'type': anthropicWebSearchToolType, 'name': 'web_search'}
      ]);
      expect(p['tool_choice'], {'type': 'auto'});
    });

    test('it rides alongside the caller\'s own tools', () {
      final p = prepareAnthropicPayload(
        target('m', webSearch: true),
        [LLMMessage(role: LLMRole.user, content: 'hi')],
        tools: [
          LLMTool(name: 'read_file', description: 'reads', parameters: const {})
        ],
        isStreaming: false,
      );
      final tools = p['tools'] as List;
      expect(tools, hasLength(2));
      expect(tools.first['name'], 'read_file');
      expect(tools.last['type'], anthropicWebSearchToolType);
    });

    test('switched off means no tools array at all', () {
      final p = prepareAnthropicPayload(
        target('m'),
        [LLMMessage(role: LLMRole.user, content: 'hi')],
        isStreaming: false,
      );
      expect(p.containsKey('tools'), isFalse);
    });

    test('a host-run search is never surfaced as a call to make', () {
      // It is already executed and already answered. Handing it to an agent
      // loop as a tool call would make it run something nobody asked for and
      // then reply to a call the model never made.
      final content = parseAnthropicContent([
        {'type': 'text', 'text': 'let me look that up.'},
        {
          'type': 'server_tool_use',
          'id': 'call_1',
          'name': 'web_search',
          'input': {'query': '今天上海天气'},
        },
        {
          'type': 'web_search_tool_result',
          'tool_use_id': 'call_1',
          'content': [
            {
              'type': 'web_search_result',
              'title': '上海天气预报',
              'url': 'http://www.weather.com.cn/textFC/shanghai.shtml',
              'page_age': '2026-07-07 18:00:00',
              'content': '小雨 南风',
            }
          ],
        },
        {'type': 'text', 'text': 'It is raining.'},
      ]);

      expect(content.toolCalls, isEmpty);
      expect(content.serverToolRuns, hasLength(1));
      expect(content.serverToolRuns.single.query, '今天上海天气');
      expect(content.serverToolRuns.single.results.single.url,
          'http://www.weather.com.cn/textFC/shanghai.shtml');
    });

    test('the two texts around the search stay two paragraphs', () {
      final content = parseAnthropicContent([
        {'type': 'text', 'text': 'Searching.'},
        {'type': 'server_tool_use', 'id': 'c1', 'name': 'web_search', 'input': {}},
        {'type': 'text', 'text': 'Found it.'},
      ]);
      expect(content.text, 'Searching.\n\nFound it.');
    });

    test('sources reach the caller as metadata, not as prose', () {
      final content = parseAnthropicContent([
        {'type': 'server_tool_use', 'id': 'c1', 'name': 'web_search', 'input': {'query': 'q'}},
        {
          'type': 'web_search_tool_result',
          'tool_use_id': 'c1',
          'content': [
            {'type': 'web_search_result', 'title': 'T', 'url': 'https://e.com/a'}
          ],
        },
      ]);
      final metadata = anthropicUsageMetadata(
        {'input_tokens': 10, 'output_tokens': 5},
        serverToolRuns: content.serverToolRuns,
      );
      expect(metadata['server_tool_runs'], [
        {
          'name': 'web_search',
          'query': 'q',
          'sources': [
            {'title': 'T', 'url': 'https://e.com/a'}
          ],
        }
      ]);
    });

    test('a result whose call went missing still keeps its sources', () {
      final content = parseAnthropicContent([
        {
          'type': 'web_search_tool_result',
          'tool_use_id': 'never-announced',
          'content': [
            {'type': 'web_search_result', 'title': 'T', 'url': 'https://e.com/a'}
          ],
        },
      ]);
      expect(content.serverToolRuns.single.results, hasLength(1));
    });
  });

  group('third-party ④ hosts', () {
    test('every ④ vendor routes to the ④ protocol', () {
      for (final id in [
        Vendors.anthropicRest,
        Vendors.newApiAnthropic,
        Vendors.minimaxAnthropic,
      ]) {
        expect(Vendors.byId(id).family, ProtocolFamily.anthropic, reason: id);
      }
    });

    test('MiniMax serves ① and ④ from one company, on different paths', () {
      // The protocol family belongs to the channel, not to the vendor: the
      // same key reaches `/v1/chat/completions` and `/anthropic/v1/messages`
      // depending only on which channel it was saved under.
      expect(Vendors.byId(Vendors.minimax).family, ProtocolFamily.openai);
      expect(Vendors.byId(Vendors.minimaxAnthropic).family,
          ProtocolFamily.anthropic);
    });

    test('a non-/v1 base path still composes to the documented URL', () {
      // MiniMax is the one ④ host whose base is not `.../v1`. Nothing may
      // assume the suffix — the protocol appends `/messages` to whatever the
      // channel stored, and the endpoint normalizer only strips slashes.
      for (final raw in [
        'https://api.minimaxi.com/anthropic/v1',
        'https://api.minimaxi.com/anthropic/v1/',
      ]) {
        final config = LLMModelConfig(
          modelId: 'MiniMax-M3',
          channelType: Vendors.minimaxAnthropic,
          endpoint: raw,
          apiKey: 'k',
        );
        expect(
          '${trimBaseUrl(config.endpoint)}/messages',
          'https://api.minimaxi.com/anthropic/v1/messages',
          reason: raw,
        );
      }
    });

    test('an error envelope behind a 200 still fails the request', () {
      // ④ hosts answer `{"type":"error","error":{…}}`, and a relay can serve
      // one with a 200 — which would otherwise parse as a reply with no
      // content and be reported as a completed task.
      expect(
        () => throwIfEnvelopeError({
          'type': 'error',
          'request_id': 'r1',
          'error': {'type': 'rate_limit_error', 'message': 'slow down'},
        }),
        throwsA(predicate((e) => e.toString().contains('slow down'))),
      );
    });
  });
}
