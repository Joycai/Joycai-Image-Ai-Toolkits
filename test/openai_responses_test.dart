import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_descriptor.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/openai_responses_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/turn_continuation.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/protocol_section_form.dart';

/// Pins the ② OpenAI Responses wire (protocol 02 §7, reasoning 03 §7, errors
/// 06 §4.1, pitfalls 11 group G). Most of these rules fail silently when
/// broken: a missing `instructions` bills a relay's injected prompt, a
/// missing `strict: false` rewrites the tool contract, a lost replay item
/// costs reasoning quality with a 200.
void main() {
  LLMTarget target({
    String channelType = Vendors.openAIRest,
    String modelId = 'gpt-5.5',
    ReasoningEffort? effort,
  }) {
    final config = LLMModelConfig(
      modelId: modelId,
      channelType: channelType,
      endpoint: 'https://api.example.com/v1',
      apiKey: 'k',
      reasoningEffort: effort,
      wireProtocol: WireProtocol.openaiResponses.id,
    );
    return LLMTarget(
      config: config,
      vendor: Vendors.byId(channelType),
      model: ModelDescriptor.of(modelId),
    );
  }

  final user = LLMMessage(role: LLMRole.user, content: 'hi');
  final tool = LLMTool(
    name: 'list_files',
    description: 'List files',
    parameters: {
      'type': 'object',
      'properties': {
        'dir': {'type': 'string'},
      },
    },
  );

  Map<String, dynamic> payload(
    List<LLMMessage> history, {
    LLMTarget? t,
    Map<String, dynamic>? options,
    bool streaming = true,
    List<LLMTool>? tools,
  }) =>
      buildResponsesPayload(t ?? target(), history,
          options: options, isStreaming: streaming, tools: tools);

  group('request builder', () {
    test('instructions are always sent — empty when there is no system', () {
      final body = payload([user]);
      expect(body.containsKey('instructions'), isTrue);
      expect(body['instructions'], '');
    });

    test('every system message is hoisted and joined by a blank line', () {
      final body = payload([
        LLMMessage(role: LLMRole.system, content: 'one'),
        user,
        LLMMessage(role: LLMRole.system, content: 'two'),
      ]);
      expect(body['instructions'], 'one\n\ntwo');
      expect((body['input'] as List).length, 1,
          reason: 'system messages do not also travel as input items');
    });

    test('store is false on both paths; stream only on the streaming one', () {
      final streamed = payload([user]);
      final sync = payload([user], streaming: false);
      expect(streamed['store'], isFalse);
      expect(sync['store'], isFalse);
      expect(streamed['stream'], isTrue);
      expect(sync.containsKey('stream'), isFalse);
    });

    test('function tools are flat with an explicit strict:false', () {
      final body = payload([user], tools: [tool]);
      final tools = body['tools'] as List;
      expect(tools.single, {
        'type': 'function',
        'name': 'list_files',
        'description': 'List files',
        'parameters': tool.parameters,
        'strict': false,
      });
      expect(body['tool_choice'], 'auto');
    });

    test('no tools, no tool_choice', () {
      final body = payload([user]);
      expect(body.containsKey('tools'), isFalse);
      expect(body.containsKey('tool_choice'), isFalse);
    });

    test('tool_choice keeps the keywords and names a function unwrapped', () {
      expect(responsesToolChoice(null), 'auto');
      expect(responsesToolChoice('required'), 'required');
      expect(responsesToolChoice('none'), 'none');
      expect(responsesToolChoice('list_files'),
          {'type': 'function', 'name': 'list_files'});
      final body =
          payload([user], tools: [tool], options: {'toolChoice': 'list_files'});
      expect(body['tool_choice'], {'type': 'function', 'name': 'list_files'});
    });

    test('reasoning: default sends nothing, off is none, levels carry summary',
        () {
      expect(payload([user]).containsKey('reasoning'), isFalse);
      expect(payload([user], t: target(effort: ReasoningEffort.off))['reasoning'],
          {'effort': 'none'});
      expect(
          payload([user], t: target(effort: ReasoningEffort.high))['reasoning'],
          {'effort': 'high', 'summary': 'auto'});
      expect(
          payload([user], t: target(effort: ReasoningEffort.max))['reasoning'],
          {'effort': 'max', 'summary': 'auto'});
    });

    test('include is sent only where the vendor declares it', () {
      expect(payload([user]).containsKey('include'), isFalse);
      expect(payload([user], t: target(channelType: Vendors.newApiOpenAI))
          .containsKey('include'), isFalse);
      expect(
          payload([user], t: target(channelType: Vendors.xaiApi))['include'],
          ['reasoning.encrypted_content']);
    });

    test('max_output_tokens only when the caller capped the output', () {
      expect(payload([user]).containsKey('max_output_tokens'), isFalse);
      expect(payload([user], options: {'maxTokens': 1})['max_output_tokens'], 1);
    });

    test('an image is an input_image whose image_url is a data URL string', () {
      final body = payload([
        LLMMessage(
          role: LLMRole.user,
          content: 'look',
          attachments: [
            LLMAttachment.fromBytes(Uint8List.fromList([1, 2, 3]), 'image/png'),
          ],
        ),
      ]);
      final content = ((body['input'] as List).single as Map)['content'] as List;
      expect(content.first, {'type': 'input_text', 'text': 'look'});
      final image = content.last as Map;
      expect(image['type'], 'input_image');
      expect(image['image_url'], isA<String>());
      expect(image['image_url'] as String, startsWith('data:image/png;base64,'));
    });
  });

  group('history conversion', () {
    final call = LLMToolCall(id: 'call_1', name: 'list_files', arguments: {'dir': '.'});
    final items = <Map<String, dynamic>>[
      {'type': 'reasoning', 'id': 'rs_1', 'encrypted_content': 'enc', 'summary': []},
      {
        'type': 'function_call',
        'id': 'fc_1',
        'call_id': 'call_1',
        'name': 'list_files',
        'arguments': '{"dir":"."}',
      },
    ];
    LLMMessage toolTurn({String? producer}) => LLMMessage(
          role: LLMRole.assistant,
          content: 'Checking.',
          toolCalls: [call],
          rawResponseItems: items,
          rawThinkingModelId: producer,
        );
    final result = LLMMessage(
        role: LLMRole.tool, content: 'a.txt', toolCallId: 'call_1', toolName: 'list_files');

    test('the same model gets the items verbatim, instead of bare calls', () {
      final input = buildResponsesInput(
          [user, toolTurn(producer: 'gpt-5.5'), result],
          modelId: 'gpt-5.5');
      expect(input.sublist(1, 3), items);
      expect(input.where((i) => i['type'] == 'function_call').length, 1,
          reason: 'never both the verbatim call and a rebuilt one');
      expect(input.any((i) => i['role'] == 'assistant'), isFalse);
      expect(input.last,
          {'type': 'function_call_output', 'call_id': 'call_1', 'output': 'a.txt'});
    });

    test('another model gets text and bare function_call, no reasoning', () {
      final input = buildResponsesInput(
          [user, toolTurn(producer: 'gpt-5.5'), result],
          modelId: 'grok-4.5');
      expect(input.any((i) => i['type'] == 'reasoning'), isFalse);
      expect(input[1], {'role': 'assistant', 'content': 'Checking.'});
      expect(input[2], {
        'type': 'function_call',
        'call_id': 'call_1',
        'name': 'list_files',
        'arguments': '{"dir":"."}',
      });
    });

    test('items with no recorded producer are not replayed', () {
      final input =
          buildResponsesInput([user, toolTurn(), result], modelId: 'gpt-5.5');
      expect(input.any((i) => i['type'] == 'reasoning'), isFalse);
    });

    test('the replayed items are copies, not the stored maps', () {
      final input = buildResponsesInput([toolTurn(producer: 'm')], modelId: 'm');
      expect(identical(input.first, items.first), isFalse);
    });

    test('plain assistant text is an easy input message', () {
      final input = buildResponsesInput(
          [user, LLMMessage(role: LLMRole.assistant, content: 'hello')],
          modelId: 'm');
      expect(input.last, {'role': 'assistant', 'content': 'hello'});
    });
  });

  group('stream assembler', () {
    List<LLMResponseChunk> run(List<Map<String, dynamic>> events,
        {String? sentEffort}) {
      final a = ResponsesStreamAssembler(sentEffort: sentEffort);
      return [for (final e in events) ...a.feed(e), ...a.finish()];
    }

    Map<String, dynamic> completed({Map<String, dynamic>? usage, Map? reasoning}) => {
          'type': 'response.completed',
          'response': {
            'status': 'completed',
            'usage': ?usage,
            'reasoning': ?reasoning,
          },
        };

    String textOf(List<LLMResponseChunk> c) =>
        c.map((x) => x.textPart ?? '').join();
    Map<String, dynamic> metaOf(List<LLMResponseChunk> c) =>
        c.lastWhere((x) => x.metadata != null).metadata!;

    test('text, reasoning summary and usage in the recorder shape', () {
      final chunks = run([
        {'type': 'response.created', 'response': {}},
        {'type': 'response.reasoning_summary_text.delta', 'output_index': 0, 'delta': 'plan'},
        {'type': 'response.output_text.delta', 'output_index': 1, 'delta': 'Hel', 'obfuscation': 'xx'},
        {'type': 'response.output_text.delta', 'output_index': 1, 'delta': 'lo'},
        completed(usage: {
          'input_tokens': 100,
          'input_tokens_details': {'cached_tokens': 40},
          'output_tokens': 20,
          'output_tokens_details': {'reasoning_tokens': 5},
          'total_tokens': 120,
        }),
      ]);
      expect(textOf(chunks), 'Hello');
      expect(chunks.map((c) => c.reasoningPart ?? '').join(), 'plan');
      final meta = metaOf(chunks);
      expect(meta['finish_reason'], 'stop');
      expect(meta['prompt_tokens'], 100);
      expect(meta['completion_tokens'], 20);
      expect((meta['prompt_tokens_details'] as Map)['cached_tokens'], 40);
      expect(LLMService.promptTokensOf(meta), 100,
          reason: 'the recorder and the context budget read this shape');
      expect(LLMService.outputTokensOf(meta), 20);
    });

    test('reasoning_text deltas are reasoning too', () {
      final chunks = run([
        {'type': 'response.reasoning_text.delta', 'output_index': 0, 'delta': 'raw'},
        {'type': 'response.output_text.delta', 'output_index': 1, 'delta': 'ok'},
        completed(),
      ]);
      expect(chunks.map((c) => c.reasoningPart ?? '').join(), 'raw');
    });

    test('parallel calls group by output_index, without item_id', () {
      final chunks = run([
        {'type': 'response.output_item.added', 'output_index': 0, 'item': {'type': 'function_call', 'call_id': 'c0', 'name': 'a'}},
        {'type': 'response.output_item.added', 'output_index': 1, 'item': {'type': 'function_call', 'call_id': 'c1', 'name': 'b'}},
        {'type': 'response.function_call_arguments.delta', 'output_index': 0, 'delta': '{"x":'},
        {'type': 'response.function_call_arguments.delta', 'output_index': 1, 'delta': '{"y":'},
        {'type': 'response.function_call_arguments.delta', 'output_index': 0, 'delta': '1}'},
        {'type': 'response.function_call_arguments.delta', 'output_index': 1, 'delta': '2}'},
        completed(),
      ]);
      final calls = [for (final c in chunks) ?c.toolCallPart];
      expect(calls.map((c) => c.id), ['c0', 'c1']);
      expect(calls[0].arguments, {'x': 1});
      expect(calls[1].arguments, {'y': 2});
      expect(metaOf(chunks)['finish_reason'], 'tool_calls');
      expect(chunks.any((c) => c.rawResponseItems != null), isFalse,
          reason: 'calls with no finished item have nothing to replay');
    });

    test('the whole string wins over the accumulated deltas', () {
      final chunks = run([
        {'type': 'response.output_item.added', 'output_index': 0, 'item': {'type': 'function_call', 'call_id': 'c0', 'name': 'a'}},
        {'type': 'response.function_call_arguments.delta', 'output_index': 0, 'delta': '{"x":1}{"x":1}'},
        {'type': 'response.function_call_arguments.done', 'output_index': 0, 'arguments': '{"x":7}'},
        completed(),
      ]);
      expect(chunks.firstWhere((c) => c.toolCallPart != null).toolCallPart!.arguments,
          {'x': 7});
    });

    test('replay items come from output_item.done, server tools left out', () {
      final reasoning = {'type': 'reasoning', 'id': 'rs', 'encrypted_content': 'e', 'summary': [{'type': 'summary_text', 'text': 'think'}]};
      final search = {'type': 'web_search_call', 'id': 'ws', 'status': 'completed'};
      final fc = {'type': 'function_call', 'id': 'fc', 'call_id': 'c9', 'name': 'a', 'arguments': '{}'};
      final chunks = run([
        {'type': 'response.output_item.done', 'output_index': 2, 'item': fc},
        {'type': 'response.output_item.done', 'output_index': 0, 'item': reasoning},
        {'type': 'response.output_item.done', 'output_index': 1, 'item': search},
        completed(),
      ]);
      final items = chunks.firstWhere((c) => c.rawResponseItems != null).rawResponseItems!;
      expect(items, [reasoning, fc], reason: 'output order, no server tool');
      expect(chunks.map((c) => c.reasoningPart ?? '').join(), 'think',
          reason: 'a summary that was not streamed still reaches the reader');
      expect(chunks.firstWhere((c) => c.toolCallPart != null).toolCallPart!.id, 'c9');
    });

    test('incomplete for max_output_tokens is length', () {
      final chunks = run([
        {'type': 'response.output_text.delta', 'output_index': 0, 'delta': 'part'},
        {'type': 'response.incomplete', 'response': {'status': 'incomplete', 'incomplete_details': {'reason': 'max_output_tokens'}}},
      ]);
      final meta = metaOf(chunks);
      expect(meta['finish_reason'], 'length');
      expect(meta['finish_reason_raw'], 'max_output_tokens');
      expect(contentBlockedFailure(meta), isNull);
    });

    test('incomplete for content_filter reaches the central block check', () {
      final chunks = run([
        {'type': 'response.output_text.delta', 'output_index': 0, 'delta': 'part'},
        {'type': 'response.incomplete', 'response': {'incomplete_details': {'reason': 'content_filter'}}},
      ]);
      final meta = metaOf(chunks);
      expect(meta['finish_reason'], contentFilterFinishReason);
      expect(contentBlockedFailure(meta), isNotNull);
    });

    test('a streamed refusal is content_filter, never reply text', () {
      final chunks = run([
        {'type': 'response.output_text.delta', 'output_index': 0, 'delta': 'Sure, '},
        {'type': 'response.refusal.delta', 'output_index': 0, 'delta': "I can't "},
        {'type': 'response.refusal.delta', 'output_index': 0, 'delta': 'help'},
        {'type': 'response.refusal.done', 'output_index': 0, 'refusal': "I can't help with that."},
        {
          'type': 'response.output_item.done',
          'output_index': 0,
          'item': {
            'type': 'message',
            'content': [
              {'type': 'output_text', 'text': 'Sure, '},
              {'type': 'refusal', 'refusal': "I can't help with that."},
            ],
          },
        },
        completed(usage: {'input_tokens': 4, 'output_tokens': 6}),
      ]);
      expect(textOf(chunks), 'Sure, ',
          reason: 'the refusal text must not reach the deliverable');
      final meta = metaOf(chunks);
      expect(meta['finish_reason'], contentFilterFinishReason);
      expect(meta['finish_reason_raw'], 'refusal');
      expect(meta['prompt_tokens'], 4, reason: 'usage is still published');
      expect(contentBlockedFailure(meta), isNotNull);
    });

    test('a refusal part only inside output_item.done is caught too', () {
      final chunks = run([
        {
          'type': 'response.output_item.done',
          'output_index': 0,
          'item': {
            'type': 'message',
            'content': [
              {'type': 'refusal', 'refusal': 'No.'},
            ],
          },
        },
        completed(),
      ]);
      expect(textOf(chunks), isEmpty);
      expect(metaOf(chunks)['finish_reason'], contentFilterFinishReason);
    });

    test('failed, error event and a bare error all throw', () {
      expect(
          () => ResponsesStreamAssembler().feed({
                'type': 'response.failed',
                'response': {'error': {'code': 'server_error', 'message': 'boom'}},
              }),
          throwsA(isA<LLMApiException>()
              .having((e) => e.message, 'message', contains('boom'))));
      expect(
          () => ResponsesStreamAssembler()
              .feed({'type': 'error', 'code': 'rate_limit', 'message': 'slow down'}),
          throwsA(isA<LLMApiException>()
              .having((e) => e.message, 'message', contains('slow down'))));
      expect(() => ResponsesStreamAssembler().feed({'error': {'message': 'quota'}}),
          throwsA(isA<LLMApiException>()));
    });

    test('no terminal event: text is delivered as truncated', () {
      final chunks = run([
        {'type': 'response.output_text.delta', 'output_index': 0, 'delta': 'cut'},
      ]);
      final meta = metaOf(chunks);
      expect(textOf(chunks), 'cut');
      expect(meta['finish_reason'], 'length');
      expect(meta['stream_incomplete'], isTrue);
      expect(meta.containsKey('prompt_tokens'), isFalse);
    });

    test('no terminal event with a call in flight throws', () {
      final a = ResponsesStreamAssembler();
      a.feed({'type': 'response.output_item.added', 'output_index': 0, 'item': {'type': 'function_call', 'call_id': 'c', 'name': 'a'}});
      a.feed({'type': 'response.function_call_arguments.delta', 'output_index': 0, 'delta': '{"x":'});
      expect(a.finish, throwsA(isA<LLMApiException>()));
    });

    test('no event at all, and a completed response with nothing, throw', () {
      expect(ResponsesStreamAssembler().finish, throwsA(isA<LLMApiException>()));
      final empty = ResponsesStreamAssembler()..feed(completed());
      expect(empty.finish, throwsA(isA<LLMApiException>()));
    });

    test('an echoed effort that differs is reported, never missing echoes', () {
      final events = [
        {'type': 'response.output_text.delta', 'output_index': 0, 'delta': 'x'},
        completed(reasoning: {'effort': 'none'}),
      ];
      final rewritten = metaOf(run(events, sentEffort: 'max'));
      expect(rewritten['wire_rewrites'], [
        {'field': 'reasoning.effort', 'sent': 'max', 'echoed': 'none'},
      ]);
      expect(metaOf(run(events, sentEffort: 'none')).containsKey('wire_rewrites'),
          isFalse);
      expect(metaOf(run(events)).containsKey('wire_rewrites'), isFalse,
          reason: 'nothing was sent, so nothing was rewritten');
      final noEcho = [events.first, completed()];
      expect(metaOf(run(noEcho, sentEffort: 'max')).containsKey('wire_rewrites'),
          isFalse);
    });
  });

  group('synchronous body', () {
    test('output[] goes through the same assembler and scopes the carrier', () {
      final fc = {'type': 'function_call', 'id': 'fc', 'call_id': 'c1', 'name': 'a', 'arguments': '{"k":1}'};
      final response = responsesResponseFromBody({
        'status': 'completed',
        'output': [
          {'type': 'reasoning', 'id': 'rs', 'summary': [{'type': 'summary_text', 'text': 'why'}]},
          {'type': 'message', 'role': 'assistant', 'content': [{'type': 'output_text', 'text': 'Doing it.'}]},
          fc,
        ],
        'usage': {'input_tokens': 9, 'output_tokens': 3},
      }, modelId: 'gpt-5.5');
      expect(response.text, 'Doing it.');
      expect(response.reasoningContent, 'why');
      expect(response.toolCalls.single.arguments, {'k': 1});
      expect(response.rawResponseItems!.length, 3);
      expect(response.rawThinkingModelId, 'gpt-5.5');
      expect(response.metadata['prompt_tokens'], 9);
    });

    test('a plain answer carries no replay items', () {
      final response = responsesResponseFromBody({
        'status': 'completed',
        'output': [
          {'type': 'message', 'content': [{'type': 'output_text', 'text': 'Hi'}]},
        ],
      }, modelId: 'm');
      expect(response.rawResponseItems, isNull);
      expect(response.rawThinkingModelId, isNull);
    });

    test('a refusal part in a synchronous body is content_filter', () {
      final response = responsesResponseFromBody({
        'status': 'completed',
        'output': [
          {
            'type': 'message',
            'content': [
              {'type': 'refusal', 'refusal': "I can't help with that."},
            ],
          },
        ],
        'usage': {'input_tokens': 3, 'output_tokens': 5},
      }, modelId: 'm');
      expect(response.text, isEmpty);
      expect(response.metadata['finish_reason'], contentFilterFinishReason);
      expect(contentBlockedFailure(response.metadata), isNotNull);
    });

    test('status incomplete is published like the stream event', () {
      final response = responsesResponseFromBody({
        'status': 'incomplete',
        'incomplete_details': {'reason': 'max_output_tokens'},
        'output': [
          {'type': 'message', 'content': [{'type': 'output_text', 'text': 'cut'}]},
        ],
      }, modelId: 'm');
      expect(response.metadata['finish_reason'], 'length');
    });
  });

  group('carrier', () {
    final items = [
      {'type': 'function_call', 'call_id': 'c', 'name': 'a', 'arguments': '{}'},
    ];

    test('survives persistence and is absent when null', () {
      final m = LLMMessage(
          role: LLMRole.assistant,
          content: '',
          rawResponseItems: items,
          rawThinkingModelId: 'm');
      final back = LLMMessage.fromJson(m.toJson());
      expect(back.rawResponseItems, items);
      expect(LLMMessage(role: LLMRole.assistant, content: 'x')
          .toJson()
          .containsKey('rawResponseItems'), isFalse);
    });

    test('a continued turn keeps the last part\'s items', () {
      final merged = mergeTurnParts([
        LLMResponse(text: 'a', metadata: const {}),
        LLMResponse(text: 'b', rawResponseItems: items, metadata: const {}),
      ]);
      expect(merged.rawResponseItems, items);
    });
  });

  group('routing', () {
    test('the Responses face is an alternate after ① on the generic OpenAI hosts',
        () {
      for (final id in [Vendors.openAIRest, Vendors.newApiOpenAI]) {
        final menu = LLMDispatcher.protocolMenu(id, 'gpt-5.5');
        expect(menu.options,
            [WireProtocol.openaiChat, WireProtocol.openaiResponses], reason: id);
        expect(menu.auto, WireProtocol.openaiChat, reason: id);
        expect(protocolSectionForm(menu, pinIsStale: false),
            ProtocolSectionForm.dropdown, reason: id);
      }
      // xAI leads with Responses: it marks Chat Completions deprecated, so an
      // unpinned Grok chat model rides Responses and ① stays a pin.
      final xai = LLMDispatcher.protocolMenu(Vendors.xaiApi, 'grok-4.5');
      expect(xai.options,
          [WireProtocol.openaiResponses, WireProtocol.openaiChat]);
      expect(xai.auto, WireProtocol.openaiResponses);
      expect(protocolSectionForm(xai, pinIsStale: false),
          ProtocolSectionForm.dropdown);
      expect(
          LLMDispatcher.isStaleProtocolSelection(
              Vendors.xaiApi, 'grok-4.5', WireProtocol.openaiChat.id),
          isFalse);
      expect(LLMDispatcher.protocolMenu(Vendors.deepseek, 'deepseek-chat').options,
          [WireProtocol.openaiChat]);
      expect(
          LLMDispatcher.isStaleProtocolSelection(
              Vendors.deepseek, 'deepseek-chat', WireProtocol.openaiResponses.id),
          isTrue);
      expect(
          LLMDispatcher.isStaleProtocolSelection(
              Vendors.xaiApi, 'grok-4.5', WireProtocol.openaiResponses.id),
          isFalse);
    });

    test('a Responses model streams tools; the face follows default and pin',
        () {
      final dispatcher = LLMDispatcher();
      final config = target(channelType: Vendors.xaiApi, modelId: 'grok-4.5').config;
      expect(dispatcher.streamSupportsTools(config), isTrue);
      expect(dispatcher.streamIsSingleShot(config), isFalse);
      // Unpinned on xAI: Responses, the vendor's chat default.
      expect(
          LLMDispatcher.resolvedChatFace(
              channelType: Vendors.xaiApi, modelId: 'grok-4.5'),
          WireProtocol.openaiResponses);
      // A Chat Completions pin still wins.
      expect(
          LLMDispatcher.resolvedChatFace(
              channelType: Vendors.xaiApi,
              modelId: 'grok-4.5',
              wireProtocol: WireProtocol.openaiChat.id),
          WireProtocol.openaiChat);
      // And the generic host keeps ① unless pinned.
      expect(
          LLMDispatcher.resolvedChatFace(
              channelType: Vendors.openAIRest, modelId: 'gpt-5.5'),
          WireProtocol.openaiChat);
      expect(
          LLMDispatcher.resolvedChatFace(
              channelType: Vendors.openAIRest,
              modelId: 'gpt-5.5',
              wireProtocol: WireProtocol.openaiResponses.id),
          WireProtocol.openaiResponses);
    });

    test('the ladder has six rungs and is not trimmed per model', () {
      const six = <ReasoningEffort?>[
        null,
        ReasoningEffort.off,
        ReasoningEffort.low,
        ReasoningEffort.medium,
        ReasoningEffort.high,
        ReasoningEffort.max,
      ];
      for (final id in ['grok-4.5', 'gpt-5.4']) {
        expect(
            LLMDispatcher.reasoningLadder(
                channelType: Vendors.xaiApi,
                modelId: id,
                wireProtocol: WireProtocol.openaiResponses.id),
            six,
            reason: id);
      }
    });
  });
}
