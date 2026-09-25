import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/assistant/prompt_optimizer_agent.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/private_data_dir.dart';

/// Standard 07 §3.8: the last round of a turn offers no tools, so a model that
/// would keep calling them has to answer; one that still does not answer
/// leaves a visible notice rather than a silent stop.
void main() {
  usePrivateDataDir('joycai_round_limit_test');

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() => PromptOptimizerAgent.debugRequestOverride = null);

  LLMResponse toolRound(int n) => LLMResponse(text: '', toolCalls: [
        LLMToolCall(id: 'call_$n', name: 'list_reference_images', arguments: const {}),
      ]);

  test('the final round sends no tools, and a model that still calls one leaves a notice', () async {
    final session = PromptOptimizerSession();
    session.addUserTurn('go');
    final toolsPerRequest = <List<LLMTool>?>[];
    List<LLMMessage>? lastRequest;
    PromptOptimizerAgent.debugRequestOverride = (messages, tools, options) async {
      toolsPerRequest.add(tools);
      lastRequest = List.of(messages);
      return toolRound(toolsPerRequest.length); // never answers
    };

    await PromptOptimizerAgent.runTurn(
        session: session, modelIdentifier: 'm', referenceImages: const []);

    expect(toolsPerRequest.length, greaterThan(1));
    expect(toolsPerRequest.sublist(0, toolsPerRequest.length - 1),
        everyElement(isNotNull));
    expect(toolsPerRequest.last, isNull);

    // The force-text instruction goes out with that one request only.
    expect(lastRequest!.last.role, LLMRole.user);
    expect(session.history.any((m) => identical(m, lastRequest!.last)), isFalse);
    expect(
        session.history.where((m) => m.role == LLMRole.user).map((m) => m.content), ['go'],
        reason: 'no one-shot instruction may persist as a standing one (07 §3.5)');

    // The history stays pairable, and the stop is visible.
    expect(PromptOptimizerAgent.repairToolCallPairing(session.history),
        hasLength(session.history.length));
    expect(session.transcript.last.kind, OptimizerEntryKind.notice);
  });

  test('a model that answers in the final round ends normally, without a notice', () async {
    final session = PromptOptimizerSession();
    session.addUserTurn('go');
    var requests = 0;
    PromptOptimizerAgent.debugRequestOverride = (messages, tools, options) async {
      requests++;
      if (tools == null) return LLMResponse(text: 'Here is where I got to.');
      return toolRound(requests);
    };

    await PromptOptimizerAgent.runTurn(
        session: session, modelIdentifier: 'm', referenceImages: const []);

    expect(session.transcript.last.kind, OptimizerEntryKind.assistant);
    expect(session.transcript.last.text, 'Here is where I got to.');
    expect(session.transcript.any((e) => e.kind == OptimizerEntryKind.notice), isFalse);
  });
}
