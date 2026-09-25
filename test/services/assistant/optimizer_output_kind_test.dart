// `A3e`: a task preset says what it hands back. A prompt preset keeps the
// frame it always had, to the letter; an analysis preset gets one that lets
// it answer in the chat, and its answer is marked as the deliverable.
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/prompt.dart';
import 'package:joycai_image_ai_toolkits/services/assistant/prompt_optimizer_agent.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/private_data_dir.dart';

/// The frame as it stood before presets had an output kind. Spelled out
/// rather than rebuilt from the agent's constants: the promise of this round
/// is that no existing preset behaves differently, and only a copy can hold
/// the agent to it. Rewording the frame on purpose means rewording this.
const _promptFrame =
    'PRESET\n\n'
    '---\n'
    'You are working inside an interactive prompt-optimization chat. The '
    'user gives you a rough idea or an existing prompt and you produce a '
    'refined, high-quality prompt. There are currently '
    '0 reference image(s) available.\n'
    'Tools:\n'
    '- list_reference_images: list the attached reference images.\n'
    '- view_image: look at one reference image before relying on it.\n'
    '- submit_prompt: deliver an optimized prompt. This is the ONLY way to '
    'deliver a result — never paste the final prompt as plain chat text.\n'
    '- ask_user: ask up to 4 structured questions with concrete options.\n'
    'Workflow:\n'
    '1. If reference images could be relevant, inspect them with '
    'list_reference_images and view_image first.\n'
    '2. Call submit_prompt with the complete optimized prompt (plus a '
    'short note describing what you changed).\n'
    '3. When the request is too ambiguous to optimize, ask via ask_user '
    '(structured options, at most once per turn) instead of a plain-text '
    'question — but never ask about details you can reasonably infer. '
    'Afterwards you may also reply with a brief comment.\n'
    'The user may reply with follow-up adjustments — deliver every '
    'revision through submit_prompt again, always with the full prompt.'
    '\nFeedback rounds: a user message starting with "[result_feedback]" '
    'reports what happened when the user generated with one of your '
    'submitted prompts. Its JSON header names the prompt version and the '
    'result image, and may carry "rating" ("satisfied" / "unsatisfied") '
    'and "reasons" (tags such as prompt_mismatch, composition, '
    'color_light, detail, style); the text after it, when present, is the '
    'user\'s critique in their own words. A satisfied report means keep '
    'what that version did; an unsatisfied one asks for a fix. The result '
    'image is in list_reference_images with kind "result" — view it when '
    'the critique concerns something visual, diagnose the gap against the '
    'references and the rules you are working from, and deliver a complete '
    'revised prompt via submit_prompt (never a fragment).'
    '\nKeep chat text brief. Never write a prompt (or a knowledge file\'s '
    'content) as plain text and then again inside the tool call — the tool '
    'call is the only copy. Think, read, then deliver in one call.';

void main() {
  usePrivateDataDir('joycai_output_kind_test');

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() => PromptOptimizerAgent.debugRequestOverride = null);

  /// Runs one turn that the model closes with [reply], and returns the system
  /// prompt it was sent.
  Future<String> runTurn(
    PromptOptimizerSession session, {
    PresetOutputKind? kind,
    String reply = 'done',
    List<Map<String, String>> refs = const [],
    bool forceView = false,
  }) async {
    late String system;
    PromptOptimizerAgent.debugRequestOverride = (messages, tools, options) async {
      system = messages.firstWhere((m) => m.role == LLMRole.system).content;
      return LLMResponse(text: reply);
    };
    session.addUserTurn('look at reference image 1');
    if (kind == null) {
      await PromptOptimizerAgent.runTurn(
        session: session,
        modelIdentifier: 'm',
        systemPrompt: 'PRESET',
        referenceImages: refs,
      );
    } else {
      await PromptOptimizerAgent.runTurn(
        session: session,
        modelIdentifier: 'm',
        systemPrompt: 'PRESET',
        outputKind: kind,
        referenceImages: refs,
        forceViewAllImages: forceView,
      );
    }
    return system;
  }

  group('a prompt preset', () {
    test('is framed exactly as before, asked for or not', () async {
      expect(await runTurn(PromptOptimizerSession()), _promptFrame);
      expect(await runTurn(PromptOptimizerSession(), kind: PresetOutputKind.prompt), _promptFrame);
    });

    test('closes on a remark, not a deliverable', () async {
      final session = PromptOptimizerSession();
      await runTurn(session, kind: PresetOutputKind.prompt);
      expect(session.transcript.last.kind, OptimizerEntryKind.assistant);
      expect(session.transcript.last.deliverable, isFalse);
      expect(session.history.last.deliverable, isFalse);
    });
  });

  group('an analysis preset', () {
    test('keeps the preset first and drops what only a prompt frame can say', () async {
      final system = await runTurn(PromptOptimizerSession(), kind: PresetOutputKind.analysis);
      expect(system, startsWith('PRESET\n\n---\n'));
      expect(system, isNot(contains('ONLY way')));
      expect(system, isNot(contains('Keep chat text brief')));
      expect(system, isNot(contains('you produce a refined')));
      expect(system, contains('The reply IS the deliverable'));
      // Still there for "now give me a prompt for this" — as an option.
      expect(system, contains('submit_prompt'));
      expect(system, contains('Optional here'));
    });

    test('made to view every image, must do so before answering', () async {
      final system = await runTurn(
        PromptOptimizerSession(),
        kind: PresetOutputKind.analysis,
        refs: const [
          {'path': '/nowhere/a.png', 'name': 'a.png'},
        ],
        forceView: true,
      );
      expect(system, contains('MANDATORY'));
      expect(system, contains('before answering'));
      expect(system, isNot(contains('before calling submit_prompt')));
    });

    test('closes on the deliverable, and a restored session still knows it', () async {
      final session = PromptOptimizerSession();
      await runTurn(session, kind: PresetOutputKind.analysis, reply: '## Overview\nA jacket.');
      expect(session.transcript.last.deliverable, isTrue);
      expect(session.history.last.deliverable, isTrue);

      final stored = [
        for (final m in session.history) LLMMessage.fromJson(m.toJson()).withModelDbId(7),
      ];
      final restored = PromptOptimizerSession.fromStored(
        id: session.id,
        mode: AssistantMode.systemPrompt,
        history: stored,
      );
      expect(restored.transcript.last.text, '## Overview\nA jacket.');
      expect(restored.transcript.last.deliverable, isTrue);
    });

    test('a remark beside a tool call is not the deliverable', () async {
      final session = PromptOptimizerSession()..addUserTurn('go');
      var calls = 0;
      PromptOptimizerAgent.debugRequestOverride = (messages, tools, options) async {
        calls++;
        if (calls == 1) {
          return LLMResponse(
            text: 'Let me look.',
            toolCalls: [LLMToolCall(id: 'c1', name: 'list_reference_images', arguments: const {})],
          );
        }
        return LLMResponse(text: 'The answer.');
      };
      await PromptOptimizerAgent.runTurn(
        session: session,
        modelIdentifier: 'm',
        outputKind: PresetOutputKind.analysis,
        referenceImages: const [],
      );
      final replies = [
        for (final e in session.transcript)
          if (e.kind == OptimizerEntryKind.assistant) (e.text, e.deliverable),
      ];
      expect(replies, [('Let me look.', false), ('The answer.', true)]);
    });
  });

  test('an analysis turn may end in silence only after delivering a prompt', () async {
    Future<List<bool>> declared(String tool, Map<String, dynamic> args) async {
      final session = PromptOptimizerSession()..addUserTurn('go');
      final seen = <bool>[];
      PromptOptimizerAgent.debugRequestOverride = (messages, tools, options) async {
        seen.add(options[emptyReplyEndsTurnKey] == true);
        if (seen.length == 1) {
          return LLMResponse(
            text: '',
            toolCalls: [LLMToolCall(id: 'c1', name: tool, arguments: args)],
          );
        }
        return LLMResponse(text: 'The answer.');
      };
      await PromptOptimizerAgent.runTurn(
        session: session,
        modelIdentifier: 'm',
        outputKind: PresetOutputKind.analysis,
        referenceImages: const [],
      );
      return seen;
    }

    // After looking, an empty reply is a missing answer, and must fail as one.
    expect(await declared('list_reference_images', const {}), [false, false]);
    expect(await declared('submit_prompt', const {'prompt': 'p'}), [false, true]);
  });

  test('cleared text is the built-in, framed as a prompt whatever kind arrives', () async {
    late String system;
    PromptOptimizerAgent.debugRequestOverride = (messages, tools, options) async {
      system = messages.firstWhere((m) => m.role == LLMRole.system).content;
      return LLMResponse(text: 'ok');
    };
    final session = PromptOptimizerSession()..addUserTurn('go');
    await PromptOptimizerAgent.runTurn(
      session: session,
      modelIdentifier: 'm',
      systemPrompt: '  ',
      outputKind: PresetOutputKind.analysis,
      referenceImages: const [],
    );
    expect(system, startsWith(PromptOptimizerAgent.builtinPresetInstructions));
    expect(system, contains('ONLY way'));
  });

  test('a channel merge re-linking an entry keeps it the deliverable', () {
    final entry = OptimizerChatEntry(
      kind: OptimizerEntryKind.assistant,
      text: 'a',
      deliverable: true,
      modelDbId: 1,
    );
    expect(entry.copyWith(modelDbId: 2).deliverable, isTrue);
  });

  test('a prompt delivered beside a view_image still ends the answer', () async {
    final session = PromptOptimizerSession()..addUserTurn('look, then a prompt');
    var calls = 0;
    PromptOptimizerAgent.debugRequestOverride = (messages, tools, options) async {
      calls++;
      if (calls == 1) {
        return LLMResponse(
          text: '',
          toolCalls: [
            LLMToolCall(id: 'c1', name: 'submit_prompt', arguments: const {'prompt': 'p'}),
          ],
        );
      }
      return LLMResponse(text: 'There you go.');
    };
    await PromptOptimizerAgent.runTurn(
      session: session,
      modelIdentifier: 'm',
      outputKind: PresetOutputKind.analysis,
      referenceImages: const [],
    );
    // What a view_image in that batch leaves after the tool results.
    final withView = [
      ...session.history.take(session.history.length - 1),
      LLMMessage(
        role: LLMRole.user,
        content: '${PromptOptimizerAgent.viewResultMarker} Reference image #1 (a.png) is attached.',
      ),
    ];
    expect(PromptOptimizerAgent.lastBatchSubmittedPromptForTest(withView), isTrue);
    expect(
      PromptOptimizerAgent.lastBatchSubmittedPromptForTest([
        ...withView,
        LLMMessage(role: LLMRole.user, content: 'thanks'),
      ]),
      isFalse,
    );
  });

  test('the word after a delivered prompt is a remark', () async {
    final session = PromptOptimizerSession()..addUserTurn('now a prompt for it');
    var calls = 0;
    PromptOptimizerAgent.debugRequestOverride = (messages, tools, options) async {
      calls++;
      if (calls == 1) {
        return LLMResponse(
          text: '',
          toolCalls: [
            LLMToolCall(id: 'c1', name: 'submit_prompt', arguments: const {'prompt': 'p'}),
          ],
        );
      }
      return LLMResponse(text: 'There you go.');
    };
    await PromptOptimizerAgent.runTurn(
      session: session,
      modelIdentifier: 'm',
      outputKind: PresetOutputKind.analysis,
      referenceImages: const [],
    );
    expect(session.transcript.last.text, 'There you go.');
    expect(session.transcript.last.deliverable, isFalse);
  });

  test('a knowledge session is never framed by a preset\'s kind', () async {
    final session = PromptOptimizerSession(mode: AssistantMode.knowledgeBase)..addUserTurn('go');
    late String system;
    PromptOptimizerAgent.debugRequestOverride = (messages, tools, options) async {
      system = messages.firstWhere((m) => m.role == LLMRole.system).content;
      return LLMResponse(text: 'ok');
    };
    await PromptOptimizerAgent.runTurn(
      session: session,
      modelIdentifier: 'm',
      outputKind: PresetOutputKind.analysis,
      referenceImages: const [],
      knowledgeRoot: '/nowhere',
      knowledgeEntryContent: 'MAP',
    );
    expect(system, contains('KNOWLEDGE BASE ENTRY'));
    expect(system, isNot(contains('The reply IS the deliverable')));
    expect(session.transcript.last.deliverable, isFalse);
  });
}
