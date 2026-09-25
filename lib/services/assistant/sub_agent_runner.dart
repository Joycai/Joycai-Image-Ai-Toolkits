import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../llm/llm_dispatcher.dart';
import '../llm/llm_service.dart';
import '../llm/llm_types.dart';

/// How one sub-agent run ended.
class SubAgentResult {
  /// The run's final plain-text reply — the one reply that carried no tool
  /// calls, which is what ends a run normally. Empty on every other exit (a
  /// cancellation, or the turn limit reached while the model still called
  /// tools): text that rode along with a tool round is narration ("Let me read
  /// x.md first"), not findings, and the caller must treat empty output as an
  /// error result, not a silent success.
  final String output;

  /// True when the run stopped because [SubAgentRunner.run]'s `isCancelled`
  /// flipped. [output] is empty then — see its dartdoc.
  final bool cancelled;

  final int turnsUsed;

  const SubAgentResult({required this.output, required this.cancelled, required this.turnsUsed});
}

/// The request a sub-agent turn makes — injectable so the loop's invariants
/// (pairing, force-text, cancellation) are testable without a network.
/// How many consecutive replies cut at the output limit while carrying tool
/// calls end a run — the parent turn's and a sub-agent's alike. Two: the
/// first cut gets a directed retry (answer with the call alone, tighten),
/// which is the one thing the model can do about it; a second cut says the
/// cap is the problem, and only the user can move that.
const int maxTruncatedRounds = 2;

/// The result paired with every tool call of a reply that hit the output
/// limit (`finish_reason == 'length'`). None of the calls ran: a call cut
/// mid-JSON decodes to empty arguments, and executing that is how a
/// `submit_prompt` used to answer "prompt must not be empty" and a
/// `write_knowledge_file` would stage half a file (the KB card's
/// `suspiciousShrink` was the only brake). The message is directed — reply
/// with the call alone, tighten rather than restart — because the model
/// otherwise re-does the whole analysis and is cut in the same place again.
///
/// [emittedTokens] is what the host reported generating, when it did; the
/// cap itself is resolved inside the request layer and is not known here.
Map<String, dynamic> truncatedToolResult({int? emittedTokens}) => {
  'status': 'error',
  'code': 'output_truncated',
  'message':
      'Your reply hit the model\'s output-token limit'
      '${emittedTokens != null && emittedTokens > 0 ? ' after $emittedTokens tokens' : ''}'
      ' before this call was complete, so it did NOT run and nothing was '
      'delivered. Reply with ONLY the tool call — no text before it. If '
      'the content itself cannot fit, tighten it; do not restart the '
      'analysis.',
};

typedef SubAgentRequestFn =
    Future<LLMResponse> Function(List<LLMMessage> messages, List<LLMTool>? tools);

/// A tool executor for one sub-agent run. [occupiedChars] is the run's
/// current context occupancy (every message so far, including results already
/// paired in this batch) — recomputed **per call**, not per turn, so a batch
/// of reads converges on the remaining window instead of each claiming all
/// of it. The same rule the main loop's read cap follows.
typedef SubAgentToolFn = Map<String, dynamic> Function(LLMToolCall call, int occupiedChars);

/// A bounded, reusable tool loop for delegated work — the sub-agent runtime.
///
/// This is deliberately *not* a refactor of [PromptOptimizerAgent.runTurn]:
/// it has no session, no persistence, no transcript, no context compaction.
/// A sub-agent starts from exactly two freshly-built messages (zero context
/// inheritance — the caller writes everything the sub-agent may know into
/// `task`), runs at most [_defaultMaxTurns] turns, and its deliverable is its
/// final plain-text reply.
///
/// Invariants, shared with the main agent loop and pinned in
/// `test/services/assistant/sub_agent_runner_test.dart`:
///
///  * **Pairing.** Once an assistant message with tool calls is echoed into
///    the history, every call gets a paired tool result before the loop moves
///    on — a throwing executor becomes an error result, and a cancellation
///    mid-batch stubs the remaining calls. An unpaired call would poison the
///    history for every later request of the run.
///  * **Force-text last round.** The final turn is sent without tools, so a
///    run that would otherwise keep browsing is forced to write its findings
///    down. A sub-agent never asks the user for more rounds — it wraps up
///    (playbook: sub-runs do not interrupt the author).
///  * **Output = the tool-free final reply, and nothing else** (standard 07
///    §2, 09 §2.3). The text of a reply that also calls tools is never kept
///    as output, so a run that ends any other way delivers nothing rather than
///    its last piece of narration. (In a streaming runtime the finishing
///    turn's text never enters the history and must be captured from a
///    callback — if this loop ever goes streaming, that trap is documented in
///    the playbook, 09 §output.)
///  * **Echo obligations ride along.** The assistant echo carries the ①
///    reasoning fields, ③ thoughtSignatures (inside the tool calls) and ④
///    raw thinking blocks, same as every other loop in the app.
class SubAgentRunner {
  static const int _defaultMaxTurns = 6;

  /// The occupancy a run is measured with when the caller supplies none:
  /// message text, replayed reasoning, and tool-call arguments.
  ///
  /// Arguments count because they are not small — a call carrying a path list
  /// or a long brief sits in the assistant echo and is re-sent every turn. It
  /// cannot price attachments, which have no characters; a caller that sends
  /// them passes its own measure (the Prompt Assistant passes
  /// `PromptOptimizerAgent.occupiedChars`, which does).
  static int defaultOccupiedChars(List<LLMMessage> messages) {
    var total = 0;
    for (final m in messages) {
      total += m.content.length;
      total += m.reasoningContent?.length ?? 0;
      for (final call in m.toolCalls) {
        total += call.name.length;
        for (final entry in call.arguments.entries) {
          total += entry.key.length + entry.value.toString().length;
        }
      }
    }
    return total;
  }

  static Future<SubAgentResult> run({
    required dynamic modelIdentifier,
    required String systemPrompt,
    required String task,

    /// Attached to the task message — e.g. the single reference image of a
    /// `draft` run. The sub-agent's context is exactly these two messages,
    /// so this is the only way anything binary reaches it.
    List<LLMAttachment> attachments = const [],
    required List<LLMTool> tools,
    required SubAgentToolFn executeTool,
    int maxTurns = _defaultMaxTurns,
    bool Function()? isCancelled,
    void Function(String message)? onLog,
    String? contextId,

    /// Tags this run's usage rows (e.g. `subagent:knowledge`) so delegated
    /// spend stays attributable in the usage table.
    String? usageTag,

    /// How the occupancy handed to [executeTool] is measured. Defaults to
    /// [defaultOccupiedChars].
    int Function(List<LLMMessage> messages)? measureOccupancy,
    @visibleForTesting SubAgentRequestFn? request,
  }) async {
    final requestFn =
        request ??
        (messages, tools) => LLMService().request(
          modelIdentifier: modelIdentifier,
          messages: messages,
          options: {
            'retryCount': 2,
            'usageTag': ?usageTag,
            // A delegate returns a research note, which is long for the
            // same reason the parent's prompt is. See
            // [expectedOutputTokensKey].
            expectedOutputTokensKey: 8192,
          },
          tools: tools,
          contextId: contextId,
          // Keeps a long delegate answer alive on routes that stream
          // tool calls; downgraded automatically on the ones that do
          // not. See [ChatProtocol.streamingDeclaresTools].
          useStream: true,
          // A delegate turn is the parent's turn from the user's side of
          // the stop button: without this the request outlives the press
          // by however long the generation takes, retries included.
          isCancelled: isCancelled,
        );
    final measure = measureOccupancy ?? defaultOccupiedChars;

    final messages = <LLMMessage>[
      LLMMessage(role: LLMRole.system, content: systemPrompt),
      LLMMessage(role: LLMRole.user, content: task, attachments: attachments),
    ];

    var truncatedRounds = 0;
    for (var turn = 0; turn < maxTurns; turn++) {
      if (isCancelled?.call() ?? false) {
        return SubAgentResult(output: '', cancelled: true, turnsUsed: turn);
      }

      final isLastTurn = turn == maxTurns - 1;
      final LLMResponse response;
      try {
        response = await requestFn(messages, isLastTurn ? null : tools);
      } on LLMCancelled {
        // Cancellation reaches this loop as an exception now that the hook
        // is passed down, and it has to become the same result the
        // between-turns check produces — the caller reads `cancelled` to
        // decide what to tell the parent agent, and an exception escaping
        // here would instead surface as a failed delegation.
        return SubAgentResult(output: '', cancelled: true, turnsUsed: turn);
      }

      final truncated = response.metadata['finish_reason'] == 'length';
      if (response.toolCalls.isEmpty) {
        // The only place output is ever taken from: a reply with no tool
        // calls is the deliverable. Text beside a tool call is narration.
        if (truncated) {
          onLog?.call(
            'The sub-agent\'s answer hit the output-token limit and '
            'was cut off; delivering what arrived.',
          );
        }
        return SubAgentResult(output: response.text.trim(), cancelled: false, turnsUsed: turn + 1);
      }

      messages.add(
        LLMMessage(
          role: LLMRole.assistant,
          content: response.text,
          reasoningContent: response.reasoningContent,
          reasoningFieldName: response.reasoningFieldName,
          reasoningSignature: response.reasoningSignature,
          rawThinkingBlocks: response.rawThinkingBlocks,
          rawThinkingModelId: response.rawThinkingModelId,
          rawContentBlocks: response.rawContentBlocks,
          rawModelParts: response.rawModelParts,
          rawResponseItems: response.rawResponseItems,
          toolCalls: response.toolCalls,
        ),
      );

      // Same rule as the parent loop: a reply cut mid-call runs none of its
      // calls, gets one directed retry, and a second cut in a row ends the
      // run with no deliverable rather than a loop of identical cuts.
      if (truncated) {
        truncatedRounds++;
        final emitted = LLMService.outputTokensOf(response.metadata);
        onLog?.call(
          'The sub-agent\'s reply hit the output-token limit'
          '${emitted > 0 ? ' after $emitted tokens' : ''}; its tool calls '
          'will not run.',
        );
        for (final call in response.toolCalls) {
          messages.add(
            LLMMessage(
              role: LLMRole.tool,
              content: jsonEncode(truncatedToolResult(emittedTokens: emitted > 0 ? emitted : null)),
              toolCallId: call.id,
              toolName: call.name,
            ),
          );
        }
        if (truncatedRounds >= maxTruncatedRounds) {
          onLog?.call(
            'Two consecutive sub-agent replies were cut at the '
            'output limit — stopping the run.',
          );
          return SubAgentResult(output: '', cancelled: false, turnsUsed: turn + 1);
        }
        continue;
      }
      truncatedRounds = 0;

      var cancelledMidBatch = false;
      for (final call in response.toolCalls) {
        Map<String, dynamic> result;
        if (cancelledMidBatch || (isCancelled?.call() ?? false)) {
          cancelledMidBatch = true;
          result = {
            'status': 'cancelled',
            'message': 'The task was cancelled before this tool ran.',
          };
        } else {
          try {
            // Occupancy is measured over the *current* messages, so a result
            // paired earlier in this same batch already counts against the
            // next call's budget.
            result = executeTool(call, measure(messages));
          } catch (e) {
            onLog?.call('Tool ${call.name} failed: $e');
            result = {'status': 'error', 'message': 'Tool ${call.name} failed: $e'};
          }
        }
        messages.add(
          LLMMessage(
            role: LLMRole.tool,
            content: jsonEncode(result),
            toolCallId: call.id,
            toolName: call.name,
          ),
        );
      }
      if (cancelledMidBatch) {
        return SubAgentResult(output: '', cancelled: true, turnsUsed: turn + 1);
      }
    }

    // Only reachable if the force-text turn still answered with tool calls
    // (a misbehaving endpoint that invents calls with no tools declared).
    // The calls above were paired, so the history stayed valid — but there is
    // no deliverable, and the caller reports that rather than narration.
    onLog?.call(
      'Sub-agent hit the $maxTurns-turn limit without a text '
      'deliverable.',
    );
    return SubAgentResult(output: '', cancelled: false, turnsUsed: maxTurns);
  }
}
