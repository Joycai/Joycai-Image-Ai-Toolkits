import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../billing/spec_billing.dart';
import '../db/database_service.dart';
import 'context_budget.dart';
import 'llm_config_resolver.dart';
import 'llm_debug_logger.dart';
import 'job_poll.dart' show cancellableSleep, cancellationProbeOf;
import 'llm_dispatcher.dart';
import 'llm_types.dart';
import 'output_spec.dart';
import 'turn_continuation.dart';

part 'llm_stream_idle_guard.dart';
part 'llm_usage_recording.dart';

class LLMService {
  static final LLMService _instance = LLMService._internal();
  factory LLMService() => _instance;
  LLMService._internal();

  final LLMConfigResolver _configResolver = LLMConfigResolver();
  final LLMDispatcher _dispatcher = LLMDispatcher();

  /// Serial of `request` / `requestStream` calls, for the debug log's
  /// correlation header ([LLMLogCorrelation.request]).
  static int _requestSerial = 0;

  /// Everyone listening to this service's execution log.
  ///
  /// A list, not one assignable field (pitfalls 11 §H72, errors 06 §4.2): a
  /// second consumer that *assigned* the old `onLogAdded` silently replaced
  /// the app's console sink, and whichever ran last won. Listeners are called
  /// in registration order over a snapshot, so one that removes itself while
  /// being called does not skip its neighbour.
  final List<LLMLogListener> _logListeners = [];

  /// Registers [listener]; returns it so a caller can keep the handle for
  /// [removeLogListener]. Adding the same function twice is a no-op.
  LLMLogListener addLogListener(LLMLogListener listener) {
    if (!_logListeners.contains(listener)) _logListeners.add(listener);
    return listener;
  }

  void removeLogListener(LLMLogListener listener) =>
      _logListeners.remove(listener);

  /// Delivers one log line to every listener. A listener that throws is
  /// skipped rather than allowed to break the request it is observing.
  void _emitLog(String msg, {String level = 'INFO', String? contextId}) {
    for (final listener in List.of(_logListeners)) {
      try {
        listener(msg, level: level, contextId: contextId);
      } catch (_) {}
    }
  }

  /// Test door onto [_emitLog].
  @visibleForTesting
  void emitLogForTest(String msg, {String level = 'INFO', String? contextId}) =>
      _emitLog(msg, level: level, contextId: contextId);

  /// [isCancelled] is polled at the points where this method would
  /// otherwise keep working for a caller that has already withdrawn: before
  /// each attempt, between stream chunks, and once the reply is complete.
  ///
  /// Both paths abort the request itself. The HTTP client is pooled and
  /// shared per endpoint ([LLMModelConfig.createClient]), so it cannot be
  /// closed for one request; instead each attempt carries an abort trigger in
  /// its options ([llmAbortTriggerKey]), which the protocols' shared
  /// non-streaming send (`sendJsonRequest`) wires to an abortable request. It
  /// fires when [isCancelled] (or a probe the caller already put in
  /// [options]) turns true, and whenever an attempt ends without a response —
  /// the non-streaming deadline included, which used to leave the request
  /// running and billing upstream. On the streaming path abandoning the
  /// subscription still cancels the response stream as before.
  ///
  /// One call may take more than one request. A host running a server-side
  /// tool can stop a turn halfway — ④'s `pause_turn`, or MiniMax's `end_turn`
  /// on a search result — and the turn is then continued here, up to
  /// [maxTurnContinuations] times, with the partial replies folded into the
  /// one the caller receives ([mergeTurnParts]). Every part is billed and is
  /// recorded as usage on its own.
  Future<LLMResponse> request({
    required dynamic modelIdentifier, // Can be String (legacy ID) or int (DbId)
    required List<LLMMessage> messages,
    String? contextId,
    Map<String, dynamic>? options,
    List<LLMTool>? tools,
    bool useStream = true,
    bool Function()? isCancelled,
    // Called with [LLMResponseChunk.toolArgumentChars] as a streamed call
    // grows. Progress for display only; restarts from zero on a retry.
    void Function(int chars)? onToolArgumentChars,
  }) async {
    final config = await _resolveConfig(
      modelIdentifier,
      logger: (msg, {level = 'INFO'}) =>
          _emitLog(msg, level: level, contextId: contextId),
    );
    // Tool calling reaches the streaming surface only where the protocol
    // assembles calls out of deltas — every chat family does now, but
    // Midjourney's stream still cannot, see
    // [ChatProtocol.streamingDeclaresTools]. Everywhere else, downgrading
    // silently beats honouring useStream: a caller that passed tools needs
    // them, and a stream that never declares them just answers as if there
    // were none, which is the one failure an agent loop cannot detect.
    //
    // This has to come *after* resolveConfig — the answer is a property of
    // the resolved route, not of the caller.
    final bool toolBearing = tools != null && tools.isNotEmpty;
    if (toolBearing && !_dispatcher.streamSupportsTools(config)) {
      useStream = false;
    }
    final int maxRetries = options?['retryCount'] ?? 0;
    // Asked once: on a route that bills at acceptance only failures provably
    // before acceptance are retried — see [shouldRetry].
    final billedOnSubmit = _dispatcher.isBilledOnSubmit(config);
    int attempt = 0;
    void log(String msg, {String level = 'INFO'}) =>
        _emitLog(msg, level: level, contextId: contextId);

    // Before anything is sent, and outside the retry loop: an oversized
    // request fails the same way every time.
    final oversized = preflightContextSize(config, messages, tools);
    if (oversized != null) {
      log(oversized.toString(), level: 'ERROR');
      throw oversized;
    }

    // The turn so far: the history this request is asked against (grows by
    // one continuation at a time) and the partial replies collected on the
    // way to a finished one.
    // The caller's own probe (an executor passes one in the options) and the
    // isCancelled hook, chained — never one replacing the other (pitfalls 11
    // §H72). Protocols that poll (job_poll) and the abort watcher read it.
    final requestOptions = chainCancellationProbe(options, isCancelled);
    final cancelProbe = cancellationProbeOf(requestOptions);
    final requestSerial = ++_requestSerial;

    var turnHistory = messages;
    final parts = <LLMResponse>[];
    // [usageMissing] is warned about once per call, not once per leg.
    var warnedMissingUsage = false;

    while (true) {
      // Checked before opening a connection rather than only after: the
      // window between the user pressing stop and this loop starting its
      // next attempt is exactly where a cancelled turn used to spend another
      // full request.
      if (cancelProbe?.call() ?? false) throw const LLMCancelled();
      // One trigger per attempt, fired by the watcher on cancel and by the
      // `finally` below whenever the attempt ends — completing it after the
      // response has fully arrived has no effect.
      final abort = Completer<void>();
      final cancelWatch = _abortWhenCancelled(cancelProbe, abort);
      // Every debug log this attempt opens is stamped with it, and gets the
      // normalised outcome appended (errors 06 §4).
      final correlation = LLMLogCorrelation(
        contextId: contextId,
        request: requestSerial,
        leg: parts.length,
        attempt: attempt,
      );
      final attemptOptions = <String, dynamic>{
        ...?requestOptions,
        llmAbortTriggerKey: abort.future,
      };
      try {
        final LLMResponse response;
        var cancelledMidStream = false;
        if (useStream) {
          log(
            'Connecting to ${config.channelType} (streaming)... ${attempt > 0 ? "(Retry $attempt/$maxRetries)" : ""}',
            level: 'DEBUG',
          );
          final streamed = await LLMDebugLogger.runCorrelated(
            correlation,
            () => _streamOnce(
              config,
              turnHistory,
              options: attemptOptions,
              tools: tools,
              toolBearing: toolBearing,
              isCancelled: cancelProbe,
              log: log,
              onToolArgumentChars: onToolArgumentChars,
            ),
          );
          response = streamed.response;
          cancelledMidStream = streamed.cancelled;
        } else {
          log(
            'Connecting to ${config.channelType} (standard)... ${attempt > 0 ? "(Retry $attempt/$maxRetries)" : ""}',
            level: 'DEBUG',
          );
          final deadline = _dispatcher.generateTimeout(
            config,
            options: options,
          );
          response = await LLMDebugLogger.runCorrelated(
              correlation,
              () => _dispatcher.generate(
                config,
                turnHistory,
                options: attemptOptions,
                tools: tools,
                logger: log,
                // Its own type rather than the bare TimeoutException Future
                // supplies, so the retry decision can tell "the generation ran
                // long" apart from "the connection died" — see
                // [LLMDeadlineExceeded].
              ))
              .timeout(
                deadline,
                onTimeout: () => throw LLMDeadlineExceeded(deadline),
              );
          if (response.text.isNotEmpty) {
            log('[AI]: ${response.text}');
          }
        }

        await LLMDebugLogger.appendSummaries(correlation, response.metadata);

        // Record usage per part, before anything else: whatever the provider
        // generated was billed, whether or not the turn goes on or the caller
        // is still there.
        //
        // A spec-billed group prices the pictures, not the usage payload, so
        // for it a response that carried images is recorded even when the
        // provider reported no usage at all — relays that draw through the
        // chat surface commonly report none.
        final specBilled = config.billingMode == specBillingMode;
        if (response.metadata.isNotEmpty ||
            (specBilled && response.generatedImages.isNotEmpty)) {
          await _recordUsage(
            config.modelId,
            config,
            response.metadata,
            modelDbId: modelIdentifier is int ? modelIdentifier : null,
            taskTag: options?['usageTag']?.toString(),
            options: options,
            imageCount: response.generatedImages.length,
          );
        }

        if (!warnedMissingUsage && usageMissing(config, response.metadata)) {
          warnedMissingUsage = true;
          log(_missingUsageWarning(config), level: 'WARN');
        }

        // Deliberately after [_recordUsage] and before the session is
        // touched: whatever the provider streamed before an abort was
        // generated and billed, so it belongs in the usage table — but a
        // half-received reply must never enter a conversation, and a caller
        // that already stopped must not be handed one to display.
        if (cancelledMidStream || (cancelProbe?.call() ?? false)) {
          throw const LLMCancelled();
        }

        // Also after [_recordUsage]: a content-filter stop voids the reply
        // even when text had already arrived (see [contentBlockedFailure]).
        final blocked = contentBlockedFailure(response.metadata);
        if (blocked != null) throw blocked;

        parts.add(response);

        // A turn the host stopped halfway is asked to go on — up to the cap.
        // The retry counter is untouched: this is not a failure, and a
        // continuation that then fails still gets its own retries.
        final continuation = continuationFor(response, config.modelId);
        if (continuation != null) {
          final done = parts.length - 1;
          if (done < maxTurnContinuations) {
            log(
              'The host paused the turn after a server-side tool run; '
              'continuing (${done + 1}/$maxTurnContinuations).',
            );
            turnHistory = [...turnHistory, ...continuation];
            attempt = 0;
            continue;
          }
          log(
            'The host paused the turn $done times; delivering the partial '
            'answer as-is.',
            level: 'WARN',
          );
        }

        return mergeTurnParts(parts);
      } catch (e) {
        await LLMDebugLogger.appendSummaries(correlation, null, error: e);
        // An abort the cancellation fired is a cancellation, not a transport
        // failure — and an aborted attempt is never retried.
        if (e is http.RequestAbortedException) {
          if (cancelProbe?.call() ?? false) throw const LLMCancelled();
          rethrow;
        }
        attempt++;
        if (attempt > maxRetries ||
            !shouldRetry(e, billedOnSubmit: billedOnSubmit)) {
          rethrow;
        }
        // Asked again here, not just at the top: the failure may well *be*
        // the cancellation tearing the connection down, and the sleep below
        // is time a stopped turn should not spend waiting to re-send a
        // request nobody is waiting for.
        if (cancelProbe?.call() ?? false) throw const LLMCancelled();
        final delay = retryDelayFor(e, attempt);
        if (delay == null) {
          log(
            'Request failed: $e. The server asked to wait longer than '
            '${maxRetryAfter.inSeconds}s before retrying; not retrying.',
            level: 'WARN',
          );
          rethrow;
        }
        log('Request failed: $e. Retrying in ${_describeDelay(delay)}...',
            level: 'WARN');
        // Sliced, so pressing stop during a long Retry-After wait ends the
        // turn within half a second instead of after the whole wait.
        await cancellableSleep(delay, cancelProbe);
        if (cancelProbe?.call() ?? false) throw const LLMCancelled();
      } finally {
        cancelWatch?.cancel();
        // Ends whatever this attempt still has in flight — a timed-out
        // non-streaming request, a single-shot generation behind a stream
        // whose first-chunk guard expired. No effect on a finished one.
        if (!abort.isCompleted) abort.complete();
      }
    }
  }

  /// One streamed request, assembled into a whole [LLMResponse].
  ///
  /// [cancelled] is true when the caller withdrew mid-stream. The partial
  /// reply is still returned — its usage has to be recorded, since whatever
  /// arrived was generated and billed — and it is the caller's job to throw
  /// [LLMCancelled] instead of using it.
  Future<({LLMResponse response, bool cancelled})> _streamOnce(
    LLMModelConfig config,
    List<LLMMessage> history, {
    required Map<String, dynamic>? options,
    required List<LLMTool>? tools,
    required bool toolBearing,
    required bool Function()? isCancelled,
    required void Function(String msg, {String level}) log,
    void Function(int chars)? onToolArgumentChars,
  }) async {
    String accumulatedText = '';
    String accumulatedReasoning = '';
    String fieldReasoning = '';
    String? reasoningFieldName;
    final List<Uint8List> accumulatedImages = [];
    final List<GeneratedImageLayer?> accumulatedLayers = [];
    final List<LLMToolCall> accumulatedToolCalls = [];
    Map<String, dynamic>? finalMetadata;
    List<Map<String, dynamic>>? rawThinkingBlocks;
    List<Map<String, dynamic>>? rawContentBlocks;
    List<Map<String, dynamic>>? rawModelParts;
    List<Map<String, dynamic>>? rawResponseItems;
    String? reasoningSignature;

    final stream = _dispatcher.generateStream(
      config,
      history,
      options: options,
      tools: tools,
      logger: log,
    );

    var cancelledMidStream = false;
    await for (final chunk in _idleGuarded(
      stream,
      first: _firstChunkGapFor(config, options),
      subsequent: _dispatcher.imageStreamChunkGap(config),
      firstIsDeadline: _firstChunkIsDeadline(config),
    )) {
      if (isCancelled?.call() ?? false) {
        // Leaving the loop is the abort. `await for` cancels its
        // subscription on break, which propagates to the response
        // stream and drops this request's connection — the only
        // interruption available while the client itself is pooled.
        cancelledMidStream = true;
        break;
      }
      if (chunk.reasoningPart != null) {
        // Surfaced to the console and kept for replay, but never glued
        // into the deliverable — that must not contain the chain of
        // thought.
        accumulatedReasoning += chunk.reasoningPart!;
        // The part that arrived under a wire field is kept apart: it is the
        // only reasoning with an echo obligation, and inline `<think>` text
        // folded into it would be sent back under that field's name
        // (reasoning 03 §6 rule 3).
        if (chunk.reasoningFieldName != null) {
          fieldReasoning += chunk.reasoningPart!;
        }
        log('[AI thinking]: ${chunk.reasoningPart}', level: 'DEBUG');
      }
      // The ①/C2 echo-back key, carried per chunk — losing it here is
      // what silently dropped tool-turn reasoning from replayed history
      // and broke DeepSeek's echo-back contract once tool-bearing
      // requests started streaming. ④ never sets it, so its history
      // keeps a null field name and the ① payload builder does not
      // invent a key for a signed-block obligation.
      if (chunk.reasoningFieldName != null) {
        reasoningFieldName = chunk.reasoningFieldName;
      }
      if (chunk.textPart != null) {
        accumulatedText += chunk.textPart!;
        // A tool-bearing caller is an agent loop: it consumes whole
        // responses, and its console is a transcript rather than a live
        // feed. Logging every fragment would bury that transcript under
        // hundreds of lines, so the text goes out once at the end
        // exactly as the standard path does it.
        if (!toolBearing) {
          log('[AI]: ${chunk.textPart}');
        }
      }
      if (chunk.imagePart != null) {
        accumulatedImages.add(chunk.imagePart!);
        accumulatedLayers.add(chunk.imageLayer);
      }
      // Collected rather than ignored: a dropped tool call reads to the
      // caller as "the model chose to answer directly", which is the one
      // failure mode an agent loop cannot detect.
      if (chunk.toolCallPart != null) {
        accumulatedToolCalls.add(chunk.toolCallPart!);
      }
      // The replay carriers arrive once, whole, at stream end — a
      // tool-calling turn replayed without them is an incomplete
      // thinking history, which ④ silently strips rather than rejects;
      // a server-tool turn replayed without its content array loses the
      // search and cannot be continued.
      if (chunk.rawThinkingBlocks != null) {
        rawThinkingBlocks = chunk.rawThinkingBlocks;
      }
      if (chunk.rawContentBlocks != null) {
        rawContentBlocks = chunk.rawContentBlocks;
      }
      if (chunk.rawModelParts != null) {
        rawModelParts = chunk.rawModelParts;
      }
      if (chunk.rawResponseItems != null) {
        rawResponseItems = chunk.rawResponseItems;
      }
      if (chunk.reasoningSignature != null) {
        reasoningSignature = chunk.reasoningSignature;
      }
      if (chunk.toolArgumentChars != null) {
        onToolArgumentChars?.call(chunk.toolArgumentChars!);
      }
      // Merged, not replaced: ③ can send a trailing usage-only chunk after
      // the one that carried `finishReason`, and replacing lost the finish —
      // a `content_filter` among them, which then passed as success.
      finalMetadata = mergeChunkMetadata(finalMetadata, chunk.metadata);
    }

    if (toolBearing && accumulatedText.isNotEmpty) {
      log('[AI]: $accumulatedText');
    }

    final response = LLMResponse(
      text: accumulatedText,
      generatedImages: accumulatedImages,
      imageLayers: accumulatedLayers.any((l) => l != null)
          ? accumulatedLayers
          : const [],
      metadata: finalMetadata ?? {},
      toolCalls: accumulatedToolCalls,
      // With a native reasoning field present, the response carries that
      // field's text alone — it is what the next request echoes under
      // [reasoningFieldName]. Inline `<think>` reasoning is then console-only.
      reasoningContent: fieldReasoning.isNotEmpty
          ? fieldReasoning
          : (accumulatedReasoning.isEmpty ? null : accumulatedReasoning),
      reasoningFieldName: fieldReasoning.isEmpty ? null : reasoningFieldName,
      reasoningSignature: reasoningSignature,
      rawThinkingBlocks: rawThinkingBlocks,
      rawContentBlocks: rawContentBlocks,
      rawModelParts: rawModelParts,
      rawResponseItems: rawResponseItems,
      // The producer of every replay carrier this turn captured: ④'s blocks,
      // a ①/DashScope reasoning field, ③'s raw parts and thought signatures,
      // ②'s output items.
      // The payload builders echo them only to the same model (reasoning 03
      // §5 rule 2) — a DeepSeek `reasoning_content` sent on to official
      // OpenAI is a 400, to a relay a bill.
      rawThinkingModelId:
          rawThinkingBlocks != null ||
              rawContentBlocks != null ||
              rawModelParts != null ||
              rawResponseItems != null ||
              fieldReasoning.isNotEmpty ||
              accumulatedToolCalls.any((c) => c.thoughtSignature != null)
          ? config.modelId
          : null,
    );

    return (response: response, cancelled: cancelledMidStream);
  }

  /// [previous] metadata with [next]'s folded in, as one stream's chunks
  /// arrive.
  ///
  /// Later non-null values win — usage counters grow as a stream goes on, and
  /// the last report is the complete one. Two things are never lost to a
  /// later chunk: a key the later chunk simply does not carry (a ③ usage-only
  /// chunk has no `finishReason`), and a `content_filter` finish once seen —
  /// interception is sticky, and a later `STOP` must not turn blocked output
  /// back into a success (errors 06 §2.3).
  @visibleForTesting
  static Map<String, dynamic>? mergeChunkMetadata(
    Map<String, dynamic>? previous,
    Map<String, dynamic>? next,
  ) {
    if (next == null) return previous;
    if (previous == null) return Map<String, dynamic>.of(next);
    final merged = Map<String, dynamic>.of(previous);
    final blocked = previous['finish_reason'] == contentFilterFinishReason;
    next.forEach((key, value) {
      if (value == null) return;
      if (blocked &&
          (key == 'finish_reason' || key == 'finish_reason_raw')) {
        return;
      }
      merged[key] = value;
    });
    return merged;
  }

  /// How long the first chunk may take on this particular route.
  ///
  /// [_firstChunkGap] asks "is this connection alive", which is the right
  /// question only while something upstream is actually streaming. On a
  /// route [LLMDispatcher.streamIsSingleShot] calls out, nothing is: the
  /// dispatcher awaits the whole single-shot `generate()` and only then
  /// re-emits it as chunks, so the first chunk cannot arrive before the
  /// generation is *finished*. DashScope's async image task is the case that
  /// forced this — its poll loop runs up to nine minutes inside one call, and
  /// a 180 s guard turned it into a [TimeoutException], which
  /// [isRetryable] answers `true` to: the task is abandoned, already billed,
  /// still running upstream, and submitted a second time.
  ///
  /// So such a route borrows the non-streaming deadline, which is sized for
  /// exactly that. Never *shorter* than [_firstChunkGap] — the chat formula's
  /// 120 s floor would otherwise tighten the guard on the image routes it
  /// does not describe.
  ///
  /// A live image stream ([LLMDispatcher.imageStreamChunkGap]) is the same
  /// story one image at a time: its first chunk is a whole finished image,
  /// so it borrows that gap — and, like the single-shot routes, expiring is
  /// a deadline rather than a dead connection.
  Duration _firstChunkGapFor(
    LLMModelConfig config,
    Map<String, dynamic>? options,
  ) {
    final imageGap = _dispatcher.imageStreamChunkGap(config);
    if (imageGap != null) {
      return imageGap > _firstChunkGap ? imageGap : _firstChunkGap;
    }
    if (!_dispatcher.streamIsSingleShot(config)) return _firstChunkGap;
    final deadline = _dispatcher.generateTimeout(config, options: options);
    return deadline > _firstChunkGap ? deadline : _firstChunkGap;
  }

  /// Whether the first-chunk gap is a generation deadline ([LLMDeadlineExceeded],
  /// never retried) rather than a liveness check.
  bool _firstChunkIsDeadline(LLMModelConfig config) =>
      _dispatcher.streamIsSingleShot(config) ||
      _dispatcher.imageStreamChunkGap(config) != null;

  @visibleForTesting
  static Stream<T> idleGuardedForTest<T>(
    Stream<T> stream, {
    required Duration first,
    required Duration subsequent,
    bool firstIsDeadline = false,
  }) => _guard(stream,
      first: first, subsequent: subsequent, firstIsDeadline: firstIsDeadline);

  /// Whether a failed attempt is worth retrying: network-level failures and
  /// transient HTTP codes (5xx / 429), nothing else.
  ///
  /// Structured errors ([LLMApiException]) answer directly. The regex is a
  /// legacy fallback for protocols still throwing plain Exceptions with
  /// `... failed: <status> - <body>` prose — anchored to that shape because
  /// the old version grabbed the *first* three-digit number anywhere in the
  /// message, which read "retry after 500ms" in an error body as a server
  /// error and re-sent a request that was going to fail (and bill) again.
  ///
  /// Public because the video executor's poll loop classifies poll failures
  /// with it: a transient one is ridden out, a terminal job state is not.
  static bool isRetryable(Object e) {
    // Belt and braces: nothing below matches [LLMCancelled] today, so the
    // fall-through would answer false anyway. Stated explicitly because
    // "false by accident" is one broadly-worded rule away from becoming true
    // — the socket-error check below matches on message text, and abandoning
    // a stream is a torn-down connection. Retrying a request the user
    // cancelled is the single behaviour this whole hook exists to remove, so
    // it should not rest on the absence of a matching rule.
    //
    // Not covered by a test: no input distinguishes this line from the
    // fall-through, which is exactly why it is written down here instead.
    if (e is LLMCancelled) return false;
    // Explicit, even though it is not a TimeoutException and so would not
    // reach the branch below: distinguishing these two is the entire reason
    // the type exists. A generation that ran past its deadline will run past
    // it again; a stalled stream will not necessarily stall again.
    if (e is LLMDeadlineExceeded) return false;
    // An accepted job whose polling was abandoned: retrying re-submits and
    // pays for the same generation twice. Explicit because its message can
    // quote the last poll's "failed: 503", which the legacy regex below
    // would read as a transient server error.
    if (e is LLMJobAbandoned) return false;
    if (e is TimeoutException) return true;
    if (e is LLMApiException) return e.isTransient;

    final errorStr = e.toString();
    if (errorStr.contains('SocketException') ||
        errorStr.contains('Connection closed')) {
      return true;
    }

    final statusCodeMatch = RegExp(
      r'failed:?\s+(\d{3})\b',
    ).firstMatch(errorStr);
    if (statusCodeMatch != null) {
      final code = int.tryParse(statusCodeMatch.group(1)!);
      if (code != null && (code == 429 || (code >= 500 && code < 600))) {
        return true;
      }
    }

    return false;
  }

  /// The retry decision for one failed attempt on a route whose billing
  /// posture is [billedOnSubmit] ([LLMDispatcher.isBilledOnSubmit]).
  ///
  /// A chat route keeps [isRetryable]. A billed route — image generation,
  /// Midjourney, any non-chat surface — retries only what
  /// [isRetryableBeforeAcceptance] can prove never reached upstream. A 502,
  /// a 524 or a "Connection closed" there is just as often a relay that gave
  /// up *after* upstream finished drawing; re-sending pays for the picture
  /// twice (standards 13 §4.3, 14 §3, 06 §3).
  @visibleForTesting
  static bool shouldRetry(Object e, {required bool billedOnSubmit}) =>
      billedOnSubmit ? isRetryableBeforeAcceptance(e) : isRetryable(e);

  /// The pre-send size failure for [messages] + [tools] on [config], or null
  /// when the request may go out (provider layering 01 §6, pitfalls 11 §A5).
  ///
  /// Counts what a request carries — message text, replayed reasoning,
  /// tool-call arguments, one flat cost per attachment, and the tool schemas
  /// — and asks [ContextBudget] (the only reader of the window tri-state)
  /// whether that is clearly over. An unset or unlimited window is never
  /// checked. The estimate is deliberately a floor, so this is a backstop for
  /// the silent head-truncation local servers do, not a budget: the Prompt
  /// Assistant compacts against a budget this check cannot pre-empt.
  @visibleForTesting
  static LLMContextSizeError? preflightContextSize(
    LLMModelConfig config,
    List<LLMMessage> messages,
    List<LLMTool>? tools,
  ) {
    final window = config.contextWindow;
    if (ContextBudget.modeOf(window) != ContextWindowMode.specified) {
      return null;
    }
    var chars = 0;
    var images = 0;
    for (final m in messages) {
      chars += m.content.length + (m.reasoningContent?.length ?? 0);
      images += m.attachments.length;
      for (final call in m.toolCalls) {
        chars += call.name.length + _jsonLength(call.arguments);
      }
    }
    var schemaChars = 0;
    for (final tool in tools ?? const <LLMTool>[]) {
      schemaChars += tool.name.length +
          tool.description.length +
          _jsonLength(tool.parameters);
    }
    final estimate = ContextBudget.estimateRequestTokens(
      chars: chars,
      toolSchemaChars: schemaChars,
      images: images,
    );
    return ContextBudget.exceedsWindow(estimate, window)
        ? LLMContextSizeError(estimate, window!)
        : null;
  }

  static int _jsonLength(Object? value) {
    try {
      return jsonEncode(value).length;
    } catch (_) {
      return value.toString().length;
    }
  }

  /// [options] with a cancellation probe that asks both the caller's own
  /// probe ([llmCancellationProbeKey], an executor's) and [isCancelled].
  ///
  /// Chained, never replaced (pitfalls 11 §H72, errors 06 §4.2): a wrapper
  /// that installs its own hook over the caller's silently disconnects the
  /// caller. Returns [options] itself when there is nothing to chain, and a
  /// new map otherwise — the caller's map is never mutated (it may be const,
  /// and it may be shared).
  @visibleForTesting
  static Map<String, dynamic>? chainCancellationProbe(
    Map<String, dynamic>? options,
    bool Function()? isCancelled,
  ) {
    final caller = cancellationProbeOf(options);
    if (isCancelled == null) return options;
    bool chained() => (caller?.call() ?? false) || isCancelled();
    return {...?options, llmCancellationProbeKey: chained};
  }

  /// A watcher that completes [abort] once [probe] turns true, or null when
  /// there is no probe to watch. Cancelled by the attempt's `finally`.
  static Timer? _abortWhenCancelled(
    bool Function()? probe,
    Completer<void> abort,
  ) {
    if (probe == null) return null;
    return Timer.periodic(const Duration(milliseconds: 250), (timer) {
      if (probe()) {
        timer.cancel();
        if (!abort.isCompleted) abort.complete();
      }
    });
  }

  /// The longest server-requested wait ([LLMApiException.retryAfter]) this
  /// service will sit out before a retry. A provider asking for more — a
  /// quota window measured in minutes or hours — is not a transient blip, and
  /// a turn silently parked that long reads as a hang; the error surfaces
  /// instead, naming the wait.
  static const Duration maxRetryAfter = Duration(seconds: 60);

  /// One step of the linear backoff: attempt n waits at least n × this.
  static const Duration retryBackoffStep = Duration(seconds: 2);

  /// How long to wait before retry number [attempt] (1-based) after [e], or
  /// null when [e] carries a server wait above [maxRetryAfter] and so must
  /// not be retried at all.
  ///
  /// Asked only *after* [shouldRetry] said yes, so it can never widen what is
  /// retried — the billed-route rule stays where it is. The wait is the larger
  /// of the linear backoff and the server's `Retry-After`: retrying a 429
  /// sooner than asked is a guaranteed second 429, and the old flat two
  /// seconds did exactly that.
  @visibleForTesting
  static Duration? retryDelayFor(Object e, int attempt) {
    final backoff = retryBackoffStep * (attempt < 1 ? 1 : attempt);
    final asked = e is LLMApiException ? e.retryAfter : null;
    if (asked == null) return backoff;
    if (asked > maxRetryAfter) return null;
    return asked > backoff ? asked : backoff;
  }

  static String _describeDelay(Duration d) => d.inMilliseconds % 1000 == 0
      ? '${d.inSeconds} seconds'
      : '${(d.inMilliseconds / 1000).toStringAsFixed(1)} seconds';

  /// Failures that provably happened before any upstream accepted the
  /// request: a rate limit (429 is decided at the door), a refused connection,
  /// or a host name that did not resolve. Nothing else — not a 5xx, not a
  /// torn-down connection, not a timeout.
  @visibleForTesting
  static bool isRetryableBeforeAcceptance(Object e) {
    if (e is LLMCancelled || e is LLMDeadlineExceeded || e is LLMJobAbandoned) {
      return false;
    }
    if (e is LLMApiException) return e.statusCode == 429;
    return _neverConnected.hasMatch(e.toString());
  }

  /// Transport messages meaning the request never left this machine or never
  /// reached a listening host, across the dart:io / http spellings on
  /// Windows, macOS and Linux.
  static final RegExp _neverConnected = RegExp(
    r'Connection refused|actively refused|Failed host lookup|'
    r'No address associated with hostname|nodename nor servname|'
    r'No such host is known|Name or service not known',
    caseSensitive: false,
  );

  Stream<LLMResponseChunk> requestStream({
    required dynamic modelIdentifier, // Can be String (legacy ID) or int (DbId)
    required List<LLMMessage> messages,
    String? contextId,
    Map<String, dynamic>? options,
  }) async* {
    _emitLog(
      'Preparing request for model: $modelIdentifier',
      level: 'DEBUG',
      contextId: contextId,
    );
    final config = await _resolveConfig(
      modelIdentifier,
      logger: (msg, {level = 'INFO'}) =>
          _emitLog(msg, level: level, contextId: contextId),
    );
    _emitLog(
      'Connecting to ${config.channelType}...',
      level: 'DEBUG',
      contextId: contextId,
    );

    final int maxRetries = options?['retryCount'] ?? 0;
    // The workbench's Retry Count reaches image tasks through here — see
    // [shouldRetry] for why a billed route retries almost nothing.
    final billedOnSubmit = _dispatcher.isBilledOnSubmit(config);
    int attempt = 0;
    // Chunks already yielded to the consumer cannot be retracted, and there
    // is no reset signal in the chunk protocol — a retry after the first
    // yield would replay the stream from the start and duplicate everything
    // downstream (doubled text, duplicate images written to disk). So retry
    // only covers failures that happen before any chunk was delivered.
    var deliveredAnyChunk = false;

    final oversized = preflightContextSize(config, messages, null);
    if (oversized != null) {
      _emitLog(oversized.toString(), level: 'ERROR', contextId: contextId);
      throw oversized;
    }

    // The executor's probe rides in the options; nothing to chain here.
    final streamProbe = cancellationProbeOf(options);
    final requestSerial = ++_requestSerial;

    while (true) {
      if (streamProbe?.call() ?? false) throw const LLMCancelled();
      final abort = Completer<void>();
      final cancelWatch = _abortWhenCancelled(streamProbe, abort);
      final correlation = LLMLogCorrelation(
        contextId: contextId,
        request: requestSerial,
        leg: 0,
        attempt: attempt,
      );
      final attemptOptions = <String, dynamic>{
        ...?options,
        llmAbortTriggerKey: abort.future,
      };
      // Per attempt, outside the try: the finally below reads them.
      int imageCount = 0;
      Map<String, dynamic>? finalMetadata;
      var usageSettled = false;
      try {

        // Opened and listened to inside the correlation's zone: this method
        // is itself a generator and cannot wrap its own `await for`.
        final stream = LLMDebugLogger.correlatedStream(
          correlation,
          () => _dispatcher.generateStream(
            config,
            messages,
            options: attemptOptions,
            logger: (msg, {level = 'INFO'}) =>
                _emitLog(msg, level: level, contextId: contextId),
          ),
        );

        await for (final chunk in _idleGuarded(
          stream,
          first: _firstChunkGapFor(config, options),
          subsequent: _dispatcher.imageStreamChunkGap(config),
          firstIsDeadline: _firstChunkIsDeadline(config),
        )) {
          if (chunk.reasoningPart != null) {
            _emitLog(
              '[AI thinking]: ${chunk.reasoningPart}',
              level: 'DEBUG',
              contextId: contextId,
            );
          }
          if (chunk.textPart != null) {
            _emitLog(
              '[AI]: ${chunk.textPart}',
              level: 'INFO',
              contextId: contextId,
            );
          }
          if (chunk.imagePart != null) {
            imageCount++;
            _emitLog(
              'Received image part ($imageCount)',
              level: 'DEBUG',
              contextId: contextId,
            );
          }
          finalMetadata = mergeChunkMetadata(finalMetadata, chunk.metadata);
          deliveredAnyChunk = true;
          yield chunk;
        }

        _emitLog(
          'Stream completed. Total images: $imageCount',
          level: 'DEBUG',
          contextId: contextId,
        );

        // Unified Token Usage Recording. Same rule as request(): a
        // spec-billed group bills the pictures whether or not the stream
        // ended with a usage payload.
        final specBilled = config.billingMode == specBillingMode;
        if (finalMetadata != null || (specBilled && imageCount > 0)) {
          _emitLog(
            'Recording token usage...',
            level: 'DEBUG',
            contextId: contextId,
          );
          await _recordUsage(
            config.modelId,
            config,
            finalMetadata ?? const {},
            modelDbId: modelIdentifier is int ? modelIdentifier : null,
            options: options,
            imageCount: imageCount,
          );
        }

        usageSettled = true;

        await LLMDebugLogger.appendSummaries(correlation, finalMetadata);

        if (usageMissing(config, finalMetadata ?? const {})) {
          _emitLog(_missingUsageWarning(config),
              level: 'WARN', contextId: contextId);
        }

        // After usage, same as request(): a stream that ran to its end was
        // generated and billed even if the caller stopped in the meantime,
        // so it is recorded before the cancel is reported.
        if (streamProbe?.call() ?? false) throw const LLMCancelled();

        // After usage, same as request(): the chunks already delivered were
        // blocked output, and the consumer must see a failure, not a success.
        final blocked = contentBlockedFailure(finalMetadata);
        if (blocked != null) throw blocked;

        return; // Success, exit retry loop
      } catch (e) {
        await LLMDebugLogger.appendSummaries(correlation, null, error: e);
        if (e is http.RequestAbortedException) {
          if (streamProbe?.call() ?? false) throw const LLMCancelled();
          rethrow;
        }
        attempt++;
        if (deliveredAnyChunk ||
            attempt > maxRetries ||
            !shouldRetry(e, billedOnSubmit: billedOnSubmit)) {
          rethrow;
        }
        final delay = retryDelayFor(e, attempt);
        if (delay == null) {
          _emitLog(
            'Stream failed: $e. The server asked to wait longer than '
            '${maxRetryAfter.inSeconds}s before retrying; not retrying.',
            level: 'WARN',
            contextId: contextId,
          );
          rethrow;
        }
        _emitLog(
          'Stream failed: $e. Retrying in ${_describeDelay(delay)}...',
          level: 'WARN',
          contextId: contextId,
        );
        // This surface has no isCancelled parameter; the executor's probe
        // rides in the options, and a stopped task must not sit out a long
        // Retry-After before noticing.
        await cancellableSleep(delay, streamProbe);
        if (streamProbe?.call() ?? false) throw const LLMCancelled();
      } finally {
        cancelWatch?.cancel();
        // Also runs when the consumer stops listening (an executor breaking
        // out on cancel): a single-shot generation still in flight behind
        // the stream is aborted instead of finishing, and billing, unseen.
        if (!abort.isCompleted) abort.complete();
        // A billed stream that delivered pictures and then failed, timed
        // out or was abandoned: those pictures were drawn and billed (Ark
        // streams them one by one, and the executor has already saved
        // them), so they are recorded — the success path above never ran.
        if (!usageSettled && billedOnSubmit && imageCount > 0) {
          _emitLog(
            'Stream ended early after $imageCount image(s); recording their '
            'usage.',
            level: 'WARN',
            contextId: contextId,
          );
          await _recordUsage(
            config.modelId,
            config,
            {...?finalMetadata, 'image_count': imageCount},
            modelDbId: modelIdentifier is int ? modelIdentifier : null,
            options: options,
            imageCount: imageCount,
          );
        }
      }
    }
  }

  /// Whether a response on a **token-billed** route reported no usage at all
  /// — no prompt count and no output count.
  ///
  /// Such a call is recorded (when it is recorded at all) as a row of zeros,
  /// which on the metrics page is indistinguishable from a genuinely free
  /// request (pitfalls 11 §A8). Many local runtimes and relays simply omit
  /// `usage`; the cost is real either way. Request- and spec-billed groups
  /// price something other than tokens, so an absent usage payload is not a
  /// gap there. Warned, never thrown — and no schema change: the row stays
  /// as it is.
  @visibleForTesting
  static bool usageMissing(
    LLMModelConfig config,
    Map<String, dynamic> metadata,
  ) =>
      config.billingMode == 'token' &&
      promptTokensOf(metadata) == null &&
      outputTokensOf(metadata) == 0;

  /// Where usage rows are written. Null means the real database; tests swap
  /// in a sink that throws to pin that recording is best-effort.
  @visibleForTesting
  static Future<void> Function(Map<String, dynamic> row)? usageSinkOverride;

  /// Test door in front of [LLMConfigResolver]: when set, every entry point
  /// takes its config from here instead of the model database.
  @visibleForTesting
  static LLMModelConfig Function(dynamic modelIdentifier)?
      configResolverOverride;

  Future<LLMModelConfig> _resolveConfig(
    dynamic modelIdentifier, {
    required Function(String, {String level}) logger,
  }) async {
    final override = configResolverOverride;
    if (override != null) return override(modelIdentifier);
    return _configResolver.resolveConfig(modelIdentifier, logger: logger);
  }

  /// Test door onto [_recordUsage].
  @visibleForTesting
  Future<void> recordUsageForTest(
    LLMModelConfig config,
    Map<String, dynamic> metadata, {
    Map<String, dynamic>? options,
    int imageCount = 0,
  }) =>
      _recordUsage(config.modelId, config, metadata,
          options: options, imageCount: imageCount);

  /// The spec-billing snapshot for one request, or null when [config]'s fee
  /// group is not spec-billed. Pure, so the three recording paths (request,
  /// stream, long-running submit) can be pinned by one test each without a
  /// database.
  @visibleForTesting
  static SpecUsage? specUsageFor(
    LLMModelConfig config,
    Map<String, dynamic>? options,
    Map<String, dynamic> metadata, {
    required int imageCount,
  }) {
    if (config.billingMode != specBillingMode) return null;
    return SpecUsage.price(
      unit: config.outputUnit,
      rates: config.outputRates,
      spec: OutputSpec.from(options, metadata: metadata),
      imageCount: imageCount,
    );
  }

  /// Output tokens a response reported, in the comparable "everything the
  /// model emitted" sense.
  ///
  /// ①, ② and ④ already count thinking inside `completion_tokens` /
  /// `output_tokens` (`*_details.reasoning_tokens` is a breakdown, not an
  /// addition). ③ does not: `candidatesTokenCount` is the answer alone and
  /// the thinking sits beside it in `thoughtsTokenCount` — so reading the
  /// former alone recorded a "think 5k, answer 500" request as 500, dropping
  /// exactly the expensive part. The two are summed here, and only here, so
  /// the metrics page and the billing agree with the invoice. Public like
  /// [promptTokensOf]: the assistant reads it to say where a reply was cut.
  static int outputTokensOf(Map<String, dynamic> metadata) {
    final counted =
        metadata['candidatesTokenCount'] ??
        metadata['completion_tokens'] ??
        metadata['output_tokens'];
    var total = _asTokenCountStatic(counted);
    if (metadata.containsKey('candidatesTokenCount') ||
        metadata.containsKey('thoughtsTokenCount')) {
      total += _asTokenCountStatic(metadata['thoughtsTokenCount']);
    }
    return total;
  }

  /// Prompt tokens a response reported, or null when the provider did not
  /// report any.
  ///
  /// Absent must stay distinguishable from zero: `usage` is optional in the
  /// OpenAI-compatible response and llama.cpp, LM Studio and various proxies
  /// omit it. A caller that read "not reported" as "zero tokens" would
  /// conclude the context is empty on exactly the small local models that
  /// overflow first, so this returns null and lets them fall back.
  static int? promptTokensOf(Map<String, dynamic> metadata) {
    final raw =
        metadata['promptTokenCount'] ??
        metadata['prompt_tokens'] ??
        metadata['input_tokens'];
    if (raw == null) return null;
    final count = raw is num ? raw.toInt() : int.tryParse(raw.toString());
    return (count == null || count <= 0) ? null : count;
  }

  Future<LLMOperationTicket> startLongRunning({
    required dynamic modelIdentifier,
    required List<LLMMessage> messages,
    String? contextId,
    Map<String, dynamic>? options,
  }) async {
    final config = await _resolveConfig(
      modelIdentifier,
      logger: (msg, {level = 'INFO'}) =>
          _emitLog(msg, level: level, contextId: contextId),
    );
    final cancelProbe = cancellationProbeOf(options);
    if (cancelProbe?.call() ?? false) throw const LLMCancelled();

    // Video submissions bypass request()/requestStream(), so translate the
    // executor's cancellation probe into the same per-request abort trigger —
    // but only while the body is still uploading ([llmBodySentKey]). A cancel
    // there stops a large upload before upstream can create a job from it.
    // Once the body is out the server may already have accepted and billed
    // the job, and aborting would lose its id: the submit is left to finish,
    // the ticket is recorded and persisted, and the executor's first poll
    // sees the cancel and cancels the job upstream by that id.
    final abort = Completer<void>();
    var bodySent = false;
    final cancelWatch = cancelProbe == null
        ? null
        : _abortWhenCancelled(() => !bodySent && cancelProbe(), abort);
    final submitOptions = <String, dynamic>{
      ...?options,
      llmAbortTriggerKey: abort.future,
      llmBodySentKey: () => bodySent = true,
    };
    final LLMOperationTicket ticket;
    try {
      ticket = await _dispatcher.startLongRunning(
        config,
        messages,
        options: submitOptions,
        logger: (msg, {level = 'INFO'}) =>
            _emitLog(msg, level: level, contextId: contextId),
      );
    } on http.RequestAbortedException {
      if (cancelProbe?.call() ?? false) throw const LLMCancelled();
      rethrow;
    } finally {
      cancelWatch?.cancel();
      if (!abort.isCompleted) abort.complete();
    }
    // Video jobs never flow back through request()/requestStream(), so the
    // accepted submission is the only moment they can be billed at all —
    // without this every Veo/Sora/xAI generation was invisible to the metrics
    // page and to request-billed channels. Providers report no token usage at
    // submit time; the row records the request itself (tokens 0).
    //
    // A spec-billed group prices the submission by what was asked for —
    // resolution and seconds are in the options, and no provider reports
    // the length it actually rendered — so a job that later fails is still
    // billed here, exactly as a request-billed one is.
    await _recordUsage(
      config.modelId,
      config,
      const {'operation': 'submit'},
      modelDbId: modelIdentifier is int ? modelIdentifier : null,
      options: options,
    );
    return ticket;
  }

  Future<Map<String, dynamic>> checkOperation({
    required dynamic modelIdentifier,
    required String operationName,
    String? operationSurface,
    String? contextId,
    bool Function()? isCancelled,
  }) async {
    final config = await _resolveConfig(
      modelIdentifier,
      logger: (msg, {level = 'INFO'}) =>
          _emitLog(msg, level: level, contextId: contextId),
    );
    if (isCancelled?.call() ?? false) throw const LLMCancelled();
    final abort = Completer<void>();
    final cancelWatch = _abortWhenCancelled(isCancelled, abort);
    try {
      return await _dispatcher.checkOperation(
        config,
        operationName,
        surfaceId: operationSurface,
        options: {llmAbortTriggerKey: abort.future},
        logger: (msg, {level = 'INFO'}) =>
            _emitLog(msg, level: level, contextId: contextId),
      );
    } on http.RequestAbortedException {
      if (isCancelled?.call() ?? false) throw const LLMCancelled();
      rethrow;
    } finally {
      cancelWatch?.cancel();
      if (!abort.isCompleted) abort.complete();
    }
  }

  /// Credential headers for downloading a generated asset from this model's
  /// channel. Callers apply them only to a URL its protocol marked as needing
  /// auth (`videoRequiresAuthKey`); a signed storage link gets none.
  Future<Map<String, String>> downloadHeadersFor({
    required dynamic modelIdentifier,
    String? contextId,
  }) async {
    final config = await _resolveConfig(
      modelIdentifier,
      logger: (msg, {level = 'INFO'}) =>
          _emitLog(msg, level: level, contextId: contextId),
    );
    return _dispatcher.downloadHeaders(config);
  }

  /// How long an upstream cancel may take before the local task gives up on
  /// it. Short on purpose: see [cancelOperation].
  static const Duration _cancelTimeout = Duration(seconds: 20);

  /// Best-effort: ask upstream to stop an operation the user cancelled here.
  ///
  /// Swallows everything. This runs on a task that is already being abandoned
  /// — the user pressed cancel and the local work is over — so a failure to
  /// reach upstream must not surface as a task error on top of that. Returns
  /// what upstream reports it did, or null when it had no cancel to offer,
  /// declined, or could not be reached.
  Future<String?> cancelOperation({
    required dynamic modelIdentifier,
    required String operationName,
    String? operationSurface,
    String? contextId,
  }) async {
    try {
      final config = await _resolveConfig(
        modelIdentifier,
        logger: (msg, {level = 'INFO'}) =>
            _emitLog(msg, level: level, contextId: contextId),
      );
      // Bounded, unlike the poll it replaces. This runs on a user pressing
      // cancel, and the caller cannot finalize the task until it returns —
      // the queue slot stays held, so an unreachable host would make "cancel"
      // hang for as long as the socket takes to give up. Whatever upstream
      // would have said is worth less than releasing the slot.
      return await _dispatcher
          .cancelOperation(
            config,
            operationName,
            surfaceId: operationSurface,
            logger: (msg, {level = 'INFO'}) =>
                _emitLog(msg, level: level, contextId: contextId),
          )
          .timeout(_cancelTimeout);
    } catch (e) {
      _emitLog(
        'Upstream cancel failed for $operationName: $e',
        level: 'WARN',
        contextId: contextId,
      );
      return null;
    }
  }
}
