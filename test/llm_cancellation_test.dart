import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/sub_agent_runner.dart';

/// Pins what "stop" means once it reaches the LLM layer.
///
/// The stop button was cooperative in name only: the agent loops checked a
/// flag between turns and between tool calls, but a turn *is* one long
/// request, so almost all of the waiting happened at a point nothing was
/// watching. Pressing stop left the current request running to completion,
/// let the retry loop re-send it up to `retryCount` more times, and then
/// wrote the answer into the conversation as though nothing had happened.
void main() {
  group('LLMCancelled', () {
    test('is never retryable', () {
      // The contract that makes the hook worth having. `retryCount: 2` is
      // what the Prompt Assistant sends, so a cancellation classed as
      // transient would buy two more full requests after the user asked for
      // zero.
      //
      // This pins the *outcome*, not the guard clause that states it: no
      // input can tell the explicit `e is LLMCancelled` check apart from the
      // fall-through, since nothing else in the classifier matches this type
      // either. Deleting that line leaves this test green. It is worth
      // keeping regardless — see the comment there — and worth not claiming
      // coverage it cannot have.
      expect(LLMService.isRetryable(const LLMCancelled()), isFalse);
    });

    test('the socket rule it must not be folded into still fires', () {
      // The neighbouring rule, pinned so that widening it to catch a
      // cancellation's torn-down connection would have to be a deliberate
      // edit to this expectation rather than a silent side effect.
      expect(
          LLMService.isRetryable(Exception('SocketException: reset by peer')),
          isTrue);
    });

    test('says what happened without naming an error', () {
      // Surfaced in logs on a path the user just triggered deliberately.
      expect(const LLMCancelled().toString(), contains('cancelled'));
    });

    test('is distinct from a deadline, which is also not retryable', () {
      // Both answer false, for opposite reasons: a deadline means the work
      // was too slow, a cancel means nobody wants the work. Keeping them
      // separate types is what lets a caller show an error for one and
      // nothing at all for the other.
      expect(LLMService.isRetryable(LLMDeadlineExceeded(Duration.zero)),
          isFalse);
      expect(const LLMCancelled(), isNot(isA<LLMDeadlineExceeded>()));
    });
  });

  group('SubAgentRunner cancellation', () {
    LLMToolCall toolCall(String id) =>
        LLMToolCall(id: id, name: 'read_knowledge_file', arguments: {'path': 'x'});

    test('a cancelled request becomes a cancelled result, not a failure',
        () async {
      // The delegate's caller reads `cancelled` to decide what to tell the
      // parent agent. Letting the exception escape would surface a stop as a
      // failed delegation — an error card for pressing a button that worked.
      var turns = 0;
      final result = await SubAgentRunner.run(
        modelIdentifier: 'm',
        systemPrompt: 'sys',
        task: 'brief',
        tools: const [],
        executeTool: (_, _) => {},
        request: (messages, tools) async {
          turns++;
          throw const LLMCancelled();
        },
      );
      expect(result.cancelled, isTrue);
      expect(result.turnsUsed, 0);
      expect(turns, 1, reason: 'the loop must not try another turn');
    });

    test('work already delivered survives the cancellation', () async {
      // A delegate that answered once and was stopped on its second turn has
      // produced something worth keeping — the parent gets the partial note
      // rather than an empty string.
      var turn = 0;
      final result = await SubAgentRunner.run(
        modelIdentifier: 'm',
        systemPrompt: 'sys',
        task: 'brief',
        tools: [
          LLMTool(name: 'read_knowledge_file', description: 'd', parameters: const {})
        ],
        executeTool: (_, _) => {'ok': true},
        request: (messages, tools) async {
          if (turn++ == 0) {
            return LLMResponse(
                text: 'partial findings', toolCalls: [toolCall('c1')]);
          }
          throw const LLMCancelled();
        },
      );
      expect(result.cancelled, isTrue);
      expect(result.output, 'partial findings');
      expect(result.turnsUsed, 1);
    });

    test('the between-turns check still short-circuits before any request',
        () async {
      // The pre-existing checkpoint, kept: cancelling before the loop starts
      // must not open a connection at all.
      var requested = 0;
      final result = await SubAgentRunner.run(
        modelIdentifier: 'm',
        systemPrompt: 'sys',
        task: 'brief',
        tools: const [],
        executeTool: (_, _) => {},
        isCancelled: () => true,
        request: (messages, tools) async {
          requested++;
          return LLMResponse(text: 'should never be asked for');
        },
      );
      expect(result.cancelled, isTrue);
      expect(requested, 0);
    });

    test('an ordinary failure is still a failure, not a cancellation',
        () async {
      // The guard on the guard: `on LLMCancelled` must not have widened into
      // a catch-all that turns every delegate error into a quiet stop.
      expect(
        () => SubAgentRunner.run(
          modelIdentifier: 'm',
          systemPrompt: 'sys',
          task: 'brief',
          tools: const [],
          executeTool: (_, _) => {},
          request: (messages, tools) async =>
              throw LLMApiException('relay exploded'),
        ),
        throwsA(isA<LLMApiException>()),
      );
    });
  });
}
