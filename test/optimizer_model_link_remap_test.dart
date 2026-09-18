import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/assistant/prompt_optimizer_agent.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';

/// A channel merge reaches a conversation that is open right now: its reply
/// links follow in the transcript, and in the history a compaction would
/// write back over the remapped rows.
void main() {
  test('an open session follows a merge', () {
    final session = PromptOptimizerSession.fromStored(
      id: 's',
      mode: AssistantMode.systemPrompt,
      history: [
        LLMMessage(role: LLMRole.user, content: 'hi'),
        LLMMessage(role: LLMRole.assistant, content: 'a', modelDbId: 20, truncated: true),
        LLMMessage(role: LLMRole.assistant, content: 'b', modelDbId: 30),
      ],
    );
    var notified = 0;
    session.addListener(() => notified++);
    final before = session.transcript;

    session.remapModelLinks({20: 10});

    expect([for (final m in session.history) m.modelDbId], [null, 10, 30]);
    // Everything else about the message is kept.
    expect(session.history[1].truncated, isTrue);
    expect(session.history[1].content, 'a');
    expect(
      [for (final e in session.transcript) if (e.modelDbId != null) e.modelDbId],
      [10, 30],
    );
    expect(identical(session.transcript, before), isFalse);
    expect(notified, 1);

    session.remapModelLinks({99: 1});
    expect(notified, 1, reason: 'nothing linked 99');
  });
}
