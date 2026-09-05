import 'dart:async';

import 'package:flutter/foundation.dart';

import '../database_service.dart';
import 'llm_config_resolver.dart';
import 'llm_dispatcher.dart';
import 'llm_types.dart';
import 'turn_continuation.dart';

class LLMService {
  static final LLMService _instance = LLMService._internal();
  factory LLMService() => _instance;
  LLMService._internal();

  final Map<String, List<LLMMessage>> _sessions = {};
  final LLMConfigResolver _configResolver = LLMConfigResolver();
  final LLMDispatcher _dispatcher = LLMDispatcher();

  Function(String, {String level, String? contextId})? onLogAdded;

  /// [isCancelled] is polled at the points where this method would
  /// otherwise keep working for a caller that has already withdrawn: before
  /// each attempt, between stream chunks, and once the reply is complete.
  ///
  /// It cannot abort a *non-streaming* request in flight. The HTTP client is
  /// pooled and shared per endpoint ([LLMModelConfig.createClient]), so its
  /// `close()` is a deliberate no-op and closing the inner one would tear
  /// down every other request sharing that connection. On the streaming path
  /// there is a real abort: abandoning the subscription cancels the response
  /// stream, which drops the connection for this request alone.
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
    String? sessionId,
    String? contextId,
    Map<String, dynamic>? options,
    List<LLMTool>? tools,
    bool useStream = true,
    bool Function()? isCancelled,
  }) async {
    final config = await _configResolver.resolveConfig(
      modelIdentifier,
      logger: (msg, {level = 'INFO'}) => onLogAdded?.call(msg, level: level, contextId: contextId),
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
    List<LLMMessage> fullHistory = messages;
    if (sessionId != null) {
      _sessions[sessionId] ??= [];
      _sessions[sessionId]!.addAll(messages);
      fullHistory = _sessions[sessionId]!;
    }

    final int maxRetries = options?['retryCount'] ?? 0;
    int attempt = 0;
    void log(String msg, {String level = 'INFO'}) =>
        onLogAdded?.call(msg, level: level, contextId: contextId);

    // The turn so far: the history this request is asked against (grows by
    // one continuation at a time) and the partial replies collected on the
    // way to a finished one.
    var turnHistory = fullHistory;
    final parts = <LLMResponse>[];

    while (true) {
      // Checked before opening a connection rather than only after: the
      // window between the user pressing stop and this loop starting its
      // next attempt is exactly where a cancelled turn used to spend another
      // full request.
      if (isCancelled?.call() ?? false) throw const LLMCancelled();
      try {
        final LLMResponse response;
        var cancelledMidStream = false;
        if (useStream) {
          log('Connecting to ${config.channelType} (streaming)... ${attempt > 0 ? "(Retry $attempt/$maxRetries)" : ""}', level: 'DEBUG');
          final streamed = await _streamOnce(config, turnHistory,
              options: options,
              tools: tools,
              toolBearing: toolBearing,
              isCancelled: isCancelled,
              log: log);
          response = streamed.response;
          cancelledMidStream = streamed.cancelled;
        } else {
          log('Connecting to ${config.channelType} (standard)... ${attempt > 0 ? "(Retry $attempt/$maxRetries)" : ""}', level: 'DEBUG');
          final deadline = _dispatcher.generateTimeout(config, options: options);
          response = await _dispatcher.generate(
            config,
            turnHistory,
            options: options,
            tools: tools,
            logger: log,
            // Its own type rather than the bare TimeoutException Future
            // supplies, so the retry decision can tell "the generation ran
            // long" apart from "the connection died" — see
            // [LLMDeadlineExceeded].
          ).timeout(deadline, onTimeout: () => throw LLMDeadlineExceeded(deadline));
          if (response.text.isNotEmpty) {
            log('[AI]: ${response.text}');
          }
        }

        // Record usage per part, before anything else: whatever the provider
        // generated was billed, whether or not the turn goes on or the caller
        // is still there.
        if (response.metadata.isNotEmpty) {
          _recordUsage(config.modelId, config, response.metadata, modelDbId: modelIdentifier is int ? modelIdentifier : null, taskTag: options?['usageTag']?.toString());
        }

        // Deliberately after [_recordUsage] and before the session is
        // touched: whatever the provider streamed before an abort was
        // generated and billed, so it belongs in the usage table — but a
        // half-received reply must never enter a conversation, and a caller
        // that already stopped must not be handed one to display.
        if (cancelledMidStream || (isCancelled?.call() ?? false)) {
          throw const LLMCancelled();
        }

        parts.add(response);

        // A turn the host stopped halfway is asked to go on — up to the cap.
        // The retry counter is untouched: this is not a failure, and a
        // continuation that then fails still gets its own retries.
        final continuation = continuationFor(response, config.modelId);
        if (continuation != null) {
          final done = parts.length - 1;
          if (done < maxTurnContinuations) {
            log('The host paused the turn after a server-side tool run; '
                'continuing (${done + 1}/$maxTurnContinuations).');
            turnHistory = [...turnHistory, ...continuation];
            attempt = 0;
            continue;
          }
          log('The host paused the turn $done times; delivering the partial '
              'answer as-is.', level: 'WARN');
        }

        final merged = mergeTurnParts(parts);

        // Update session
        if (sessionId != null) {
          _sessions[sessionId]!.add(LLMMessage(
            role: LLMRole.assistant,
            content: merged.text,
          ));
        }

        return merged;
      } catch (e) {
        attempt++;
        if (attempt > maxRetries || !isRetryable(e)) {
          rethrow;
        }
        // Asked again here, not just at the top: the failure may well *be*
        // the cancellation tearing the connection down, and the two-second
        // sleep below is time a stopped turn should not spend waiting to
        // re-send a request nobody is waiting for.
        if (isCancelled?.call() ?? false) throw const LLMCancelled();
        log('Request failed: $e. Retrying in 2 seconds...', level: 'WARN');
        await Future.delayed(const Duration(seconds: 2));
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
  }) async {
    String accumulatedText = "";
    String accumulatedReasoning = "";
    String? reasoningFieldName;
    List<Uint8List> accumulatedImages = [];
    List<LLMToolCall> accumulatedToolCalls = [];
    Map<String, dynamic>? finalMetadata;
    List<Map<String, dynamic>>? rawThinkingBlocks;
    List<Map<String, dynamic>>? rawContentBlocks;
    String? reasoningSignature;

    final stream = _dispatcher.generateStream(
      config,
      history,
      options: options,
      tools: tools,
      logger: log,
    );

    var cancelledMidStream = false;
    await for (final chunk
        in _idleGuarded(stream, first: _firstChunkGapFor(config, options))) {
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
      if (chunk.reasoningSignature != null) {
        reasoningSignature = chunk.reasoningSignature;
      }
      if (chunk.metadata != null) finalMetadata = chunk.metadata;
    }

    if (toolBearing && accumulatedText.isNotEmpty) {
      log('[AI]: $accumulatedText');
    }

    final response = LLMResponse(
      text: accumulatedText,
      generatedImages: accumulatedImages,
      metadata: finalMetadata ?? {},
      toolCalls: accumulatedToolCalls,
      reasoningContent:
          accumulatedReasoning.isEmpty ? null : accumulatedReasoning,
      reasoningFieldName:
          accumulatedReasoning.isEmpty ? null : reasoningFieldName,
      reasoningSignature: reasoningSignature,
      rawThinkingBlocks: rawThinkingBlocks,
      rawContentBlocks: rawContentBlocks,
      rawThinkingModelId:
          rawThinkingBlocks == null && rawContentBlocks == null
              ? null
              : config.modelId,
    );

    return (response: response, cancelled: cancelledMidStream);
  }

  /// How long the *first* chunk may take.
  ///
  /// Longer than [_idleGap] because a silent stream means different things
  /// before and after the first byte. Afterwards, two minutes of nothing is a
  /// dead connection. Beforehand it is ambiguous — a large prompt still
  /// prefilling behind a queue at a busy relay looks exactly the same — and
  /// treating that as a dead connection re-sends the entire request, which is
  /// the waste this whole change set exists to remove
  /// (docs/plans/2026-08-assistant-timeout.md).
  static const Duration _firstChunkGap = Duration(seconds: 180);

  /// How long any subsequent chunk may take.
  static const Duration _idleGap = Duration(seconds: 120);

  /// [stream] with an idle guard that is generous about the first chunk.
  ///
  /// Written over a [StreamIterator] rather than with `Stream.timeout`, which
  /// takes one fixed duration for every element. The rewrite pays for itself
  /// twice: cancelling the iterator in the `finally` actually tears down the
  /// subscription, where the non-streaming `Future.timeout` leaves its request
  /// running upstream and billing.
  static Stream<LLMResponseChunk> _idleGuarded(
          Stream<LLMResponseChunk> stream, {Duration? first}) =>
      _guard(stream, first: first ?? _firstChunkGap, subsequent: _idleGap);

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
  Duration _firstChunkGapFor(
      LLMModelConfig config, Map<String, dynamic>? options) {
    if (!_dispatcher.streamIsSingleShot(config)) return _firstChunkGap;
    final deadline = _dispatcher.generateTimeout(config, options: options);
    return deadline > _firstChunkGap ? deadline : _firstChunkGap;
  }

  @visibleForTesting
  static Stream<T> idleGuardedForTest<T>(
    Stream<T> stream, {
    required Duration first,
    required Duration subsequent,
  }) =>
      _guard(stream, first: first, subsequent: subsequent);

  static Stream<T> _guard<T>(
    Stream<T> stream, {
    required Duration first,
    required Duration subsequent,
  }) async* {
    final iterator = StreamIterator(stream);
    var gap = first;
    try {
      while (await iterator.moveNext().timeout(gap)) {
        gap = subsequent;
        yield iterator.current;
      }
    } finally {
      await iterator.cancel();
    }
  }

  /// Whether a failed attempt is worth retrying: network-level failures and
  /// transient HTTP codes (5xx / 429), nothing else.
  ///
  /// Structured errors ([LLMApiException]) answer directly. The regex is a
  /// legacy fallback for protocols still throwing plain Exceptions with
  /// `... failed: <status> - <body>` prose — anchored to that shape because
  /// the old version grabbed the *first* three-digit number anywhere in the
  /// message, which read "retry after 500ms" in an error body as a server
  /// error and re-sent a request that was going to fail (and bill) again.
  @visibleForTesting
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
    if (e is TimeoutException) return true;
    if (e is LLMApiException) return e.isTransient;

    final errorStr = e.toString();
    if (errorStr.contains('SocketException') ||
        errorStr.contains('Connection closed')) {
      return true;
    }

    final statusCodeMatch =
        RegExp(r'failed:?\s+(\d{3})\b').firstMatch(errorStr);
    if (statusCodeMatch != null) {
      final code = int.tryParse(statusCodeMatch.group(1)!);
      if (code != null &&
          (code == 429 || (code >= 500 && code < 600))) {
        return true;
      }
    }

    return false;
  }

  Stream<LLMResponseChunk> requestStream({
    required dynamic modelIdentifier, // Can be String (legacy ID) or int (DbId)
    required List<LLMMessage> messages,
    String? sessionId,
    String? contextId,
    Map<String, dynamic>? options,
  }) async* {
    onLogAdded?.call('Preparing request for model: $modelIdentifier', level: 'DEBUG', contextId: contextId);
    final config = await _configResolver.resolveConfig(
      modelIdentifier, 
      logger: (msg, {level = 'INFO'}) => onLogAdded?.call(msg, level: level, contextId: contextId),
    );
    List<LLMMessage> fullHistory = messages;
    if (sessionId != null) {
      _sessions[sessionId] ??= [];
      _sessions[sessionId]!.addAll(messages);
      fullHistory = _sessions[sessionId]!;
    }

    onLogAdded?.call('Connecting to ${config.channelType}...', level: 'DEBUG', contextId: contextId);

    final int maxRetries = options?['retryCount'] ?? 0;
    int attempt = 0;
    // Chunks already yielded to the consumer cannot be retracted, and there
    // is no reset signal in the chunk protocol — a retry after the first
    // yield would replay the stream from the start and duplicate everything
    // downstream (doubled text, duplicate images written to disk). So retry
    // only covers failures that happen before any chunk was delivered.
    var deliveredAnyChunk = false;

    while (true) {
      try {
        String accumulatedText = "";
        int imageCount = 0;
        Map<String, dynamic>? finalMetadata;
        
        final stream = _dispatcher.generateStream(
          config, 
          fullHistory, 
          options: options, 
          logger: (msg, {level = 'INFO'}) => onLogAdded?.call(msg, level: level, contextId: contextId),
        );

        await for (final chunk
            in _idleGuarded(stream, first: _firstChunkGapFor(config, options))) {
          if (chunk.reasoningPart != null) {
            onLogAdded?.call('[AI thinking]: ${chunk.reasoningPart}', level: 'DEBUG', contextId: contextId);
          }
          if (chunk.textPart != null) {
            accumulatedText += chunk.textPart!;
            onLogAdded?.call('[AI]: ${chunk.textPart}', level: 'INFO', contextId: contextId);
          }
          if (chunk.imagePart != null) {
            imageCount++;
            onLogAdded?.call('Received image part ($imageCount)', level: 'DEBUG', contextId: contextId);
          }
          if (chunk.metadata != null) finalMetadata = chunk.metadata;
          deliveredAnyChunk = true;
          yield chunk;
        }

        onLogAdded?.call('Stream completed. Total images: $imageCount', level: 'DEBUG', contextId: contextId);

        // Unified Token Usage Recording
        if (finalMetadata != null) {
          onLogAdded?.call('Recording token usage...', level: 'DEBUG', contextId: contextId);
          _recordUsage(config.modelId, config, finalMetadata, modelDbId: modelIdentifier is int ? modelIdentifier : null);
        }

        if (sessionId != null) {
          _sessions[sessionId]!.add(LLMMessage(
            role: LLMRole.assistant,
            content: accumulatedText,
          ));
        }
        return; // Success, exit retry loop
      } catch (e) {
        attempt++;
        if (deliveredAnyChunk || attempt > maxRetries || !isRetryable(e)) {
          rethrow;
        }
        onLogAdded?.call('Stream failed: $e. Retrying in 2 seconds...', level: 'WARN', contextId: contextId);
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }

  Future<void> _recordUsage(String modelId, LLMModelConfig config, Map<String, dynamic> metadata, {int? modelDbId, String? taskTag}) async {
    final db = DatabaseService();

    // Standardize metadata keys. Three spellings are in play: Google
    // (`promptTokenCount`), OpenAI chat (`prompt_tokens`) and the OpenAI
    // *Images* API (`input_tokens`) — gpt-image-1 reports only the third, so
    // reading the first two alone recorded every image generation as zero
    // tokens and only request-billed channels came out right.
    final promptTokens = _asTokenCount(metadata['promptTokenCount'] ??
        metadata['prompt_tokens'] ??
        metadata['input_tokens']);
    final outputTokens = _asTokenCount(metadata['candidatesTokenCount'] ??
        metadata['completion_tokens'] ??
        metadata['output_tokens']);
    final cacheTokens = _extractCacheTokens(metadata, promptTokens);

    await db.recordTokenUsage({
      // The tag makes delegated work distinguishable in the usage table
      // (e.g. `task_id LIKE 'subagent:%'`) — a sub-agent's spend should be
      // attributable to delegation, not blended into ordinary requests.
      'task_id': '${taskTag ?? 'req'}_${DateTime.now().millisecondsSinceEpoch}',
      'model_id': modelId,
      'model_pk': modelDbId,
      'timestamp': DateTime.now().toIso8601String(),
      // Both providers count cached tokens inside their prompt total, so the
      // cached part is subtracted out here — input_tokens and cache_tokens are
      // stored disjoint and sum back to the full input.
      'input_tokens': promptTokens - cacheTokens,
      'cache_tokens': cacheTokens,
      'output_tokens': outputTokens,
      'input_price': config.inputFee,
      'cache_price': config.effectiveCacheInputFee,
      'output_price': config.outputFee,
      'request_count': 1,
      'request_price': config.requestFee,
      'billing_mode': config.billingMode,
    });
  }

  /// Cache-hit tokens from a usage payload: `cachedContentTokenCount` (Google),
  /// `prompt_tokens_details.cached_tokens` (OpenAI) or `cache_read_input_tokens`
  /// (Anthropic). Clamped to [promptTokens] so a malformed payload can never
  /// drive the uncached remainder negative.
  ///
  /// Anthropic's bucket is only comparable to the other two because its
  /// protocol already republished the *inclusive* prompt total as
  /// `prompt_tokens` — its own `input_tokens` excludes the cached part, so
  /// subtracting one from the other would count the cache twice.
  int _extractCacheTokens(Map<String, dynamic> metadata, int promptTokens) {
    final details = metadata['prompt_tokens_details'];
    final raw = metadata['cachedContentTokenCount'] ??
        metadata['cache_read_input_tokens'] ??
        (details is Map ? details['cached_tokens'] : null);
    return _asTokenCount(raw).clamp(0, promptTokens);
  }

  /// Token counts arrive as int, double or String depending on provider and
  /// transport; anything unparseable counts as zero.
  int _asTokenCount(dynamic value) {
    final count = value is num ? value.toInt() : (value is String ? int.tryParse(value) : null);
    return (count == null || count < 0) ? 0 : count;
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
    final raw = metadata['promptTokenCount'] ??
        metadata['prompt_tokens'] ??
        metadata['input_tokens'];
    if (raw == null) return null;
    final count = raw is num ? raw.toInt() : int.tryParse(raw.toString());
    return (count == null || count <= 0) ? null : count;
  }

  void clearSession(String sessionId) {
    _sessions.remove(sessionId);
  }

  Future<LLMOperationTicket> startLongRunning({
    required dynamic modelIdentifier,
    required List<LLMMessage> messages,
    String? contextId,
    Map<String, dynamic>? options,
  }) async {
    final config = await _configResolver.resolveConfig(
      modelIdentifier,
      logger: (msg, {level = 'INFO'}) => onLogAdded?.call(msg, level: level, contextId: contextId),
    );
    final ticket = await _dispatcher.startLongRunning(
      config,
      messages,
      options: options,
      logger: (msg, {level = 'INFO'}) => onLogAdded?.call(msg, level: level, contextId: contextId),
    );
    // Video jobs never flow back through request()/requestStream(), so the
    // accepted submission is the only moment they can be billed at all —
    // without this every Veo/Sora/xAI generation was invisible to the metrics
    // page and to request-billed channels. Providers report no token usage at
    // submit time; the row records the request itself (tokens 0).
    _recordUsage(config.modelId, config, const {'operation': 'submit'},
        modelDbId: modelIdentifier is int ? modelIdentifier : null);
    return ticket;
  }

  Future<Map<String, dynamic>> checkOperation({
    required dynamic modelIdentifier,
    required String operationName,
    String? operationSurface,
    String? contextId,
  }) async {
    final config = await _configResolver.resolveConfig(
      modelIdentifier,
      logger: (msg, {level = 'INFO'}) => onLogAdded?.call(msg, level: level, contextId: contextId),
    );
    return await _dispatcher.checkOperation(
      config,
      operationName,
      surfaceId: operationSurface,
      logger: (msg, {level = 'INFO'}) => onLogAdded?.call(msg, level: level, contextId: contextId),
    );
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
      final config = await _configResolver.resolveConfig(
        modelIdentifier,
        logger: (msg, {level = 'INFO'}) =>
            onLogAdded?.call(msg, level: level, contextId: contextId),
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
                onLogAdded?.call(msg, level: level, contextId: contextId),
          )
          .timeout(_cancelTimeout);
    } catch (e) {
      onLogAdded?.call('Upstream cancel failed for $operationName: $e',
          level: 'WARN', contextId: contextId);
      return null;
    }
  }
}
