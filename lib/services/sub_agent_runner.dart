import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'llm/llm_service.dart';
import 'llm/llm_types.dart';

/// How one sub-agent run ended.
class SubAgentResult {
  /// The last plain-text reply the model produced — the deliverable. Empty
  /// when the run produced nothing (the caller must treat that as an error
  /// result, not a silent success).
  final String output;

  /// True when the run stopped because [SubAgentRunner.run]'s `isCancelled`
  /// flipped. The partial [output] (if any) is still returned; the caller
  /// decides whether a cancelled run's partial findings are worth anything.
  final bool cancelled;

  final int turnsUsed;

  const SubAgentResult({
    required this.output,
    required this.cancelled,
    required this.turnsUsed,
  });
}

/// The request a sub-agent turn makes — injectable so the loop's invariants
/// (pairing, force-text, cancellation) are testable without a network.
typedef SubAgentRequestFn = Future<LLMResponse> Function(
  List<LLMMessage> messages,
  List<LLMTool>? tools,
);

/// A tool executor for one sub-agent run. [occupiedChars] is the run's
/// current context occupancy (every message so far, including results already
/// paired in this batch) — recomputed **per call**, not per turn, so a batch
/// of reads converges on the remaining window instead of each claiming all
/// of it. The same rule the main loop's read cap follows.
typedef SubAgentToolFn = Map<String, dynamic> Function(
  LLMToolCall call,
  int occupiedChars,
);

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
/// `test/sub_agent_runner_test.dart`:
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
///  * **Output = last plain text.** This loop is synchronous per turn, so the
///    final text reply is simply the return value of the last request. (In a
///    streaming runtime the finishing turn's text never enters the history
///    and must be captured from a callback — if this loop ever goes
///    streaming, that trap is documented in the playbook, 09 §output.)
///  * **Echo obligations ride along.** The assistant echo carries the ①
///    reasoning fields, ③ thoughtSignatures (inside the tool calls) and ④
///    raw thinking blocks, same as every other loop in the app.
class SubAgentRunner {
  static const int _defaultMaxTurns = 6;

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
    @visibleForTesting SubAgentRequestFn? request,
  }) async {
    final requestFn = request ??
        (messages, tools) => LLMService().request(
              modelIdentifier: modelIdentifier,
              messages: messages,
              options: {
                'retryCount': 2,
                'usageTag': ?usageTag,
              },
              tools: tools,
              contextId: contextId,
              useStream: false,
            );

    final messages = <LLMMessage>[
      LLMMessage(role: LLMRole.system, content: systemPrompt),
      LLMMessage(role: LLMRole.user, content: task, attachments: attachments),
    ];

    var lastText = '';
    for (var turn = 0; turn < maxTurns; turn++) {
      if (isCancelled?.call() ?? false) {
        return SubAgentResult(
            output: lastText, cancelled: true, turnsUsed: turn);
      }

      final isLastTurn = turn == maxTurns - 1;
      final response = await requestFn(messages, isLastTurn ? null : tools);

      final text = response.text.trim();
      if (text.isNotEmpty) lastText = text;

      if (response.toolCalls.isEmpty) {
        return SubAgentResult(
            output: lastText, cancelled: false, turnsUsed: turn + 1);
      }

      messages.add(LLMMessage(
        role: LLMRole.assistant,
        content: response.text,
        reasoningContent: response.reasoningContent,
        reasoningFieldName: response.reasoningFieldName,
        reasoningSignature: response.reasoningSignature,
        rawThinkingBlocks: response.rawThinkingBlocks,
        rawThinkingModelId: response.rawThinkingModelId,
        toolCalls: response.toolCalls,
      ));

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
            // Occupancy folds over the *current* messages, so a result
            // paired earlier in this same batch already counts against the
            // next call's budget.
            final occupied =
                messages.fold<int>(0, (sum, m) => sum + m.content.length);
            result = executeTool(call, occupied);
          } catch (e) {
            onLog?.call('Tool ${call.name} failed: $e');
            result = {
              'status': 'error',
              'message': 'Tool ${call.name} failed: $e',
            };
          }
        }
        messages.add(LLMMessage(
          role: LLMRole.tool,
          content: jsonEncode(result),
          toolCallId: call.id,
          toolName: call.name,
        ));
      }
      if (cancelledMidBatch) {
        return SubAgentResult(
            output: lastText, cancelled: true, turnsUsed: turn + 1);
      }
    }

    // Only reachable if the force-text turn still answered with tool calls
    // (a misbehaving endpoint that invents calls with no tools declared).
    // The calls above were paired, so the history stayed valid; deliver
    // whatever text exists.
    onLog?.call('Sub-agent hit the $maxTurns-turn limit without a text '
        'deliverable.');
    return SubAgentResult(
        output: lastText, cancelled: false, turnsUsed: maxTurns);
  }
}
