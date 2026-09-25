import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/gemini_chat_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/gemini_payload.dart';
import 'package:joycai_image_ai_toolkits/services/llm/turn_continuation.dart';

/// ③'s replay carrier (protocol 02 §2.2 rule 3, reasoning 03 §5): a
/// tool-calling model turn is kept as its raw `parts` array — thought parts,
/// signatures and order included — and replayed verbatim to the model that
/// produced it. Rebuilt from text + calls, the `thoughtSignature` on a text
/// part and the thought parts themselves are exactly what gets lost, and ③
/// answers with `MISSING_THOUGHT_SIGNATURE` rather than a 400.
void main() {
  Map<String, dynamic> chunk(List<Map<String, dynamic>> parts) => {
    'candidates': [
      {
        'content': {'role': 'model', 'parts': parts},
      },
    ],
  };

  final thought = <String, dynamic>{'text': 'plan', 'thought': true};
  final lead = <String, dynamic>{'text': 'Let me check.'};
  final call = <String, dynamic>{
    'functionCall': {
      'name': 'list_files',
      'args': {'dir': '.'},
    },
    'thoughtSignature': 'sig-call',
  };
  final trailingSig = <String, dynamic>{'text': '', 'thoughtSignature': 'sig-tail'};

  group('GeminiModelPartsCollector', () {
    test('collects parts across chunks, verbatim and in order', () {
      final collector = GeminiModelPartsCollector()
        ..feed(chunk([thought, lead]))
        ..feed(chunk([call]))
        ..feed(chunk([trailingSig]));
      expect(collector.toolTurnParts, [thought, lead, call, trailingSig]);
    });

    test('a turn without a function call carries nothing', () {
      final collector = GeminiModelPartsCollector()..feed(chunk([thought, lead]));
      expect(collector.toolTurnParts, isNull);
    });

    test('a usage-only chunk adds nothing', () {
      final collector = GeminiModelPartsCollector()
        ..feed({
          'usageMetadata': {'promptTokenCount': 3},
        })
        ..feed(chunk([call]));
      expect(collector.toolTurnParts, [call]);
    });

    test('the stream parser feeds it', () {
      final collector = GeminiModelPartsCollector();
      geminiChunksFromSseLine(
        'data: {"candidates":[{"content":{"parts":[{"functionCall":'
        '{"name":"f","args":{}},"thoughtSignature":"s"}]}}]}',
        modelParts: collector,
      ).toList();
      expect(collector.toolTurnParts, hasLength(1));
      expect(collector.toolTurnParts!.single['thoughtSignature'], 's');
    });
  });

  group('replay', () {
    LLMMessage turn({String? producer, bool withCalls = true}) => LLMMessage(
      role: LLMRole.assistant,
      content: 'Let me check.',
      rawThinkingModelId: producer,
      rawModelParts: [thought, lead, call, trailingSig],
      toolCalls: withCalls
          ? [
              LLMToolCall(
                id: 'gtc_1',
                name: 'list_files',
                arguments: const {'dir': '.'},
                thoughtSignature: 'sig-call',
              ),
            ]
          : const [],
    );

    List modelParts(LLMMessage m, String target) =>
        ((prepareGooglePayload(
                      [LLMMessage(role: LLMRole.user, content: 'go'), m],
                      null,
                      null,
                      modelId: target,
                    )['contents']
                    as List)[1]
                as Map)['parts']
            as List;

    test('the producing model gets the whole parts array back verbatim', () {
      expect(modelParts(turn(producer: 'gemini-3-pro'), 'gemini-3-pro'), [
        thought,
        lead,
        call,
        trailingSig,
      ]);
    });

    test('another model gets a rebuild with no signature and no thought', () {
      final parts = modelParts(turn(producer: 'gemini-3-pro'), 'gemini-2.5-pro');
      expect(parts, [
        {'text': 'Let me check.'},
        {
          'functionCall': {
            'name': 'list_files',
            'args': {'dir': '.'},
          },
        },
      ]);
    });

    test('a turn without tool calls is never replayed verbatim', () {
      final parts = modelParts(turn(producer: 'gemini-3-pro', withCalls: false), 'gemini-3-pro');
      expect(parts, [
        {'text': 'Let me check.'},
      ]);
    });

    test('the replayed copy is not the stored list', () {
      // A payload the transport mutates must never write back into history.
      final m = turn(producer: 'gemini-3-pro');
      final parts = modelParts(m, 'gemini-3-pro');
      expect(identical(parts, m.rawModelParts), isFalse);
    });
  });

  group('carrier lifecycle', () {
    test('survives persistence', () {
      final m = LLMMessage(
        role: LLMRole.assistant,
        content: '',
        rawThinkingModelId: 'gemini-3-pro',
        rawModelParts: [thought, call],
        toolCalls: [LLMToolCall(id: 'g', name: 'list_files', arguments: const {})],
      );
      final back = LLMMessage.fromJson(m.toJson());
      expect(back.rawModelParts, [thought, call]);
      expect(back.rawThinkingModelId, 'gemini-3-pro');
    });

    test('absent stays absent in JSON', () {
      expect(
        LLMMessage(role: LLMRole.assistant, content: 'x').toJson().containsKey('rawModelParts'),
        isFalse,
      );
    });

    test('a merged turn keeps the parts of the part that called the tools', () {
      final merged = mergeTurnParts([
        LLMResponse(text: 'a', metadata: const {}),
        LLMResponse(
          text: 'b',
          metadata: const {},
          rawModelParts: [call],
          rawThinkingModelId: 'gemini-3-pro',
          toolCalls: [LLMToolCall(id: 'g', name: 'list_files', arguments: const {})],
        ),
      ]);
      expect(merged.rawModelParts, [call]);
    });
  });
}
