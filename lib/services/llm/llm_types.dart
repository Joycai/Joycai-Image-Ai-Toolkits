import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

enum LLMRole { system, user, assistant, tool }

/// The app's own reasoning-intensity vocabulary (playbook 03: never let one
/// vendor's spelling into configuration). Absence — a null wherever this is
/// carried — means *default*: no field is sent at all, and the endpoint does
/// whatever it does on its own.
///
/// Each protocol family owns its translation: ① spells these as
/// `reasoning_effort` values; ④'s budget dialect has no intensity knob, so
/// any level simply means "thinking on" and [off] means the field is not
/// sent. [off] is sent to ① as `"none"` — an endpoint that predates that
/// value rejects it audibly (a 400 naming the field), which beats silently
/// thinking anyway.
enum ReasoningEffort {
  off,
  low,
  medium,
  high,
  max;

  /// Parses a stored name; null/unknown → null (default). Unknown values
  /// come from newer builds via backup restore — degrading to default beats
  /// failing the whole model row.
  static ReasoningEffort? tryParse(String? name) =>
      name == null ? null : ReasoningEffort.values.asNameMap()[name];
}

/// A failed API call, structured enough that retry policy can be decided
/// without parsing exception prose.
///
/// Protocols throw this for non-2xx responses (with [statusCode] set) and for
/// 200-with-error-envelope bodies ([isEnvelope] true, [statusCode] null).
/// `LLMService` retries only transient codes (5xx / 429). Before this existed
/// it fished the first three-digit number out of `e.toString()` with a regex,
/// which read "retry after 500ms" in an error body as a server error — and
/// missed real 5xxs whose message led with some other number.
/// Option key for the caller's cancellation probe: a `bool Function()` that
/// returns true once the surrounding task has been cancelled.
///
/// Single-request protocols never look at it — one HTTP call has no
/// checkpoint to stop at — but a protocol that hides an async task loop
/// behind the synchronous surface (DashScope's image task flow) polls for
/// minutes and must stop within seconds of the user pressing stop. Passed
/// through `options` because that is the only channel an executor already
/// has to a protocol; the value is a function, so the map carrying it must
/// never be persisted or JSON-encoded (executors build a fresh map at the
/// call site).
const String llmCancellationProbeKey = 'isCancelled';

class LLMApiException implements Exception {
  final String message;

  /// HTTP status of the failed response, or null when the failure was carried
  /// inside a 2xx body ([isEnvelope]) or never reached HTTP at all.
  final int? statusCode;

  /// True when a 2xx response body was an error envelope (`error` field or
  /// MiniMax `base_resp`). Envelope errors are never retried — the transport
  /// succeeded; the request itself was rejected.
  final bool isEnvelope;

  /// True when the response body was not JSON at all (an HTML error page, a
  /// login page, a CDN interstitial) — the classic "the base URL points at
  /// something that is not this API" signature. Structured so the channel
  /// probe can classify it without matching message prose.
  final bool isNonJsonBody;

  LLMApiException(this.message,
      {this.statusCode, this.isEnvelope = false, this.isNonJsonBody = false});

  bool get isTransient =>
      statusCode != null &&
      (statusCode == 429 || (statusCode! >= 500 && statusCode! < 600));

  @override
  String toString() => message;
}

/// The whole-request deadline on the **non-streaming** path expired.
///
/// Its own type, and deliberately not a [TimeoutException], because
/// `LLMService.isRetryable` answers the two cases oppositely and they mean
/// opposite things:
///
///  * On the streaming path the deadline is per *chunk*. It expiring means
///    no bytes at all arrived for two minutes — a dead connection, where
///    reconnecting is exactly the right move. That stays retryable.
///  * Here it means the generation did not finish in time. The input is
///    unchanged and so is the amount of output being asked for, so a retry
///    re-runs the identical request and misses the identical deadline. It is
///    worse than useless: `Future.timeout` cancels nothing, so the abandoned
///    request keeps running upstream, keeps holding the connection, and is
///    billed in full — while its replacement competes with it. The Prompt
///    Assistant used to spend three Opus generations and six minutes this
///    way and deliver nothing (docs/plans/2026-08-assistant-timeout.md).
/// The caller withdrew while the request was in flight.
///
/// Its own type so it can be told apart from a failure everywhere the two
/// would otherwise look alike: [LLMService.isRetryable] must answer false (a
/// cancelled request retried is the bug this exists to prevent), and a caller
/// showing an error card must not show one for it — nobody needs to be told
/// that the button they just pressed worked.
///
/// Thrown rather than returned as an empty response because "cancelled" and
/// "the model answered with nothing" have to be distinguishable at every
/// call site, and only one of them may be written into a conversation.
class LLMCancelled implements Exception {
  const LLMCancelled();

  @override
  String toString() => 'Request cancelled by the caller.';
}

class LLMDeadlineExceeded implements Exception {
  final Duration deadline;

  const LLMDeadlineExceeded(this.deadline);

  @override
  String toString() =>
      'No response within ${deadline.inSeconds}s. The request was not '
      'cancelled upstream — it may still complete, and it is billed either '
      'way. Nothing was retried, because an identical request would miss the '
      'same deadline.';
}

/// The output cap the caller asked for, or null when it did not ask.
///
/// Shared so the deadline and the payload agree on what "the caller asked
/// for" means — they read the same key out of the same options map, and a
/// deadline sized against a different number than the request carries is a
/// deadline sized against nothing.
int? requestedMaxTokens(Map<String, dynamic>? options) {
  final raw = options?['maxTokens'];
  if (raw is num && raw >= 1) return raw.toInt();
  if (raw is String) {
    final parsed = int.tryParse(raw);
    if (parsed != null && parsed >= 1) return parsed;
  }
  return null;
}

enum LLMReferenceType {
  media,
  asset,
  firstFrame,
  lastFrame,

  /// The model only looks at this attachment to describe it in text — it is
  /// never fed into image generation/editing. Eligible for lossy
  /// recompression when oversized; see [ImageCompressor].
  viewOnly,
}

class LLMAttachment {
  final String? path;
  final Uint8List? bytes;
  final String mimeType;
  final LLMReferenceType referenceType;

  LLMAttachment.fromFile(File file, this.mimeType, {this.referenceType = LLMReferenceType.media}) : path = file.path, bytes = null;
  LLMAttachment.fromBytes(this.bytes, this.mimeType, {this.referenceType = LLMReferenceType.media}) : path = null;

  /// Persistence: only file-backed attachments are serialized (bytes are
  /// intentionally not stored — the file is re-read on demand at replay time).
  Map<String, dynamic>? toJson() => path == null
      ? null
      : {'path': path, 'mime': mimeType, 'ref': referenceType.name};

  static LLMAttachment? fromJson(Map<String, dynamic> json) {
    final path = json['path'] as String?;
    if (path == null) return null;
    return LLMAttachment.fromFile(
      File(path),
      json['mime'] as String? ?? 'image/jpeg',
      referenceType: LLMReferenceType.values.asNameMap()[json['ref']] ?? LLMReferenceType.media,
    );
  }
}

/// A tool (function) the model is allowed to call.
///
/// [parameters] is a JSON-Schema object describing the arguments, e.g.
/// `{"type": "object", "properties": {...}, "required": [...]}`.
class LLMTool {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;

  LLMTool({
    required this.name,
    required this.description,
    required this.parameters,
  });
}

/// A tool invocation emitted by the model.
class LLMToolCall {
  /// Provider-assigned call id (OpenAI). Synthesized for providers that don't
  /// supply one (Google).
  final String id;
  final String name;
  final Map<String, dynamic> arguments;

  /// Gemini thought signature attached to the functionCall part. Must be
  /// echoed back verbatim when the call is replayed into history, or the API
  /// rejects the request with INVALID_ARGUMENT.
  final String? thoughtSignature;

  LLMToolCall({
    required this.id,
    required this.name,
    required this.arguments,
    this.thoughtSignature,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'arguments': arguments,
        // Gemini rejects replayed histories whose thought signatures are
        // missing, so it must round-trip through persistence.
        if (thoughtSignature != null) 'thoughtSignature': thoughtSignature,
      };

  factory LLMToolCall.fromJson(Map<String, dynamic> json) => LLMToolCall(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        arguments: (json['arguments'] as Map?)?.cast<String, dynamic>() ?? {},
        thoughtSignature: json['thoughtSignature'] as String?,
      );
}

class LLMMessage {
  final LLMRole role;
  final String content;
  final List<LLMAttachment> attachments;

  /// Chain-of-thought text carried by an assistant message, for OpenAI-family
  /// vendors that expose one (DeepSeek's `reasoning_content`, OpenRouter's
  /// `reasoning`, or an inline `<think>…</think>` span some relays emit).
  ///
  /// DeepSeek rejects a tool-calling conversation with 400 when the reasoning
  /// of a tool-call-bearing assistant turn is not replayed, so this must
  /// round-trip through history and persistence — the ① family sibling of
  /// [LLMToolCall.thoughtSignature].
  final String? reasoningContent;

  /// The wire field name [reasoningContent] arrived under
  /// (`reasoning_content` / `reasoning`), or null when it was extracted from
  /// an inline `<think>` span or absent. Echo-back uses this exact name —
  /// "return it under the name you received it" survives vendors the app has
  /// never heard of, unlike hardcoding one spelling. Inline reasoning carries
  /// no echo obligation and is never sent back.
  final String? reasoningFieldName;

  /// ④'s cryptographic seal over [reasoningContent], present only on the
  /// Anthropic Messages surface.
  ///
  /// Where ① echoes reasoning as a *field* named by [reasoningFieldName], ④
  /// echoes it as a whole `thinking` **block**, and the API verifies this
  /// signature before accepting it. A tool-calling turn produced with thinking
  /// on is rejected when its thinking block is missing or unsealed — the ④
  /// sibling of [LLMToolCall.thoughtSignature] and of ①'s echo-back rule.
  ///
  /// Its presence is also what marks reasoning as ④-shaped: [reasoningFieldName]
  /// stays null there, so the ① payload builder never invents a field for it.
  final String? reasoningSignature;

  /// ④'s thinking-class blocks **verbatim** (sealed `thinking` +
  /// `redacted_thinking`, original order), for replay into a tool-calling
  /// conversation. [reasoningContent]/[reasoningSignature] stay the display
  /// carriers; this exists because a redacted block has no text to
  /// reconstruct from, and ④ answers an incomplete thinking history by
  /// *silently disabling thinking* (while billing it) rather than erroring.
  final List<Map<String, dynamic>>? rawThinkingBlocks;

  /// The model that produced [rawThinkingBlocks]. Replay is model-scoped:
  /// another model silently ignores foreign blocks and still bills them as
  /// input, so the payload builder drops the group on mismatch.
  final String? rawThinkingModelId;

  /// Tool calls carried by an assistant message (echoed back into history
  /// during an agent loop).
  final List<LLMToolCall> toolCalls;

  /// For [LLMRole.tool] messages: which call this result answers.
  final String? toolCallId;

  /// For [LLMRole.tool] messages: the tool's name (required by Google's
  /// functionResponse format).
  final String? toolName;

  LLMMessage({
    required this.role,
    required this.content,
    this.attachments = const [],
    this.reasoningContent,
    this.reasoningFieldName,
    this.reasoningSignature,
    this.rawThinkingBlocks,
    this.rawThinkingModelId,
    this.toolCalls = const [],
    this.toolCallId,
    this.toolName,
  });

  Map<String, dynamic> toJson() => {
        'role': role.name,
        'content': content,
        // The reasoning of a tool-calling turn must survive restarts — the
        // echo-back obligation does not expire with the session.
        if (reasoningContent != null) 'reasoningContent': reasoningContent,
        if (reasoningFieldName != null) 'reasoningFieldName': reasoningFieldName,
        if (reasoningSignature != null) 'reasoningSignature': reasoningSignature,
        if (rawThinkingBlocks != null && rawThinkingBlocks!.isNotEmpty)
          'rawThinkingBlocks': rawThinkingBlocks,
        if (rawThinkingModelId != null) 'rawThinkingModelId': rawThinkingModelId,
        if (attachments.isNotEmpty)
          'attachments': attachments.map((a) => a.toJson()).whereType<Map<String, dynamic>>().toList(),
        if (toolCalls.isNotEmpty) 'toolCalls': toolCalls.map((c) => c.toJson()).toList(),
        if (toolCallId != null) 'toolCallId': toolCallId,
        if (toolName != null) 'toolName': toolName,
      };

  factory LLMMessage.fromJson(Map<String, dynamic> json) => LLMMessage(
        role: LLMRole.values.asNameMap()[json['role']] ?? LLMRole.user,
        content: json['content'] as String? ?? '',
        reasoningContent: json['reasoningContent'] as String?,
        reasoningFieldName: json['reasoningFieldName'] as String?,
        reasoningSignature: json['reasoningSignature'] as String?,
        rawThinkingBlocks: json['rawThinkingBlocks'] is List
            ? [
                for (final b in json['rawThinkingBlocks'] as List)
                  if (b is Map) b.cast<String, dynamic>(),
              ]
            : null,
        rawThinkingModelId: json['rawThinkingModelId'] as String?,
        attachments: [
          for (final a in (json['attachments'] as List? ?? []))
            if (a is Map && LLMAttachment.fromJson(a.cast<String, dynamic>()) != null)
              LLMAttachment.fromJson(a.cast<String, dynamic>())!,
        ],
        toolCalls: [
          for (final c in (json['toolCalls'] as List? ?? []))
            if (c is Map) LLMToolCall.fromJson(c.cast<String, dynamic>()),
        ],
        toolCallId: json['toolCallId'] as String?,
        toolName: json['toolName'] as String?,
      );
}

class LLMModelConfig {
  final int? id; // Database Primary Key
  final String modelId;

  /// The channel's stored vendor id (`llm_channels.type`) — resolved to a
  /// [VendorProfile] by the dispatcher. See `vendors/vendors.dart`.
  final String channelType;

  /// Channel base URL, always without surrounding whitespace or a trailing
  /// slash — normalized here rather than at each call site.
  ///
  /// Protocols append their path to this (`$endpoint/chat/completions`), so a
  /// channel saved as `https://relay.example.com/v1/` used to produce
  /// `/v1//chat/completions`, which fails on gateways that do not collapse
  /// empty path segments. Only the surfaces that happened to call
  /// [trimBaseUrl] were safe — `/models` was, `/chat/completions` was not, so
  /// model discovery succeeded and every request failed. Normalizing on the
  /// way in covers channels already stored with a slash too; no migration.
  final String endpoint;

  final String apiKey;

  /// Per-model opt-in: ask the model to reason before answering.
  ///
  /// Carried on the config rather than passed as a request option because it
  /// is a property of *this model on this channel*, resolved once by
  /// [LLMConfigResolver] — so the assistant, prompt refinement and AI rename
  /// all honor it without each having to remember to pass it along. What the
  /// parameter looks like on the wire is the vendor's business
  /// (`ThinkingDialect`); whether to ask for it at all is this flag's.
  final bool enableThinking;

  /// Per-model reasoning intensity, or null for default (nothing sent).
  /// Prefer [effectiveReasoningEffort], which folds in the legacy flag.
  final ReasoningEffort? reasoningEffort;

  /// The reasoning level requests should honor.
  ///
  /// Falls back to the legacy [enableThinking] flag when no explicit level is
  /// stored: rows written before v35 (and backups restored from older
  /// builds) carry only the boolean, and a ④ model that had thinking on must
  /// keep it on — reading the flag here instead of migrating data keeps that
  /// true for every past and future restore path.
  ReasoningEffort? get effectiveReasoningEffort =>
      reasoningEffort ?? (enableThinking ? ReasoningEffort.medium : null);

  /// Per-model opt-in: let the host run its own web searches during a turn.
  final bool enableWebSearch;

  /// The model's explicit wire-protocol selection (`llm_models.wire_protocol`
  /// verbatim), or null for "auto". Stored as the raw string — the dispatcher
  /// parses and validates it against the vendor's menu, so a value written by
  /// a newer build, or one stranded by a channel-type change, degrades to
  /// auto instead of failing (and survives a save/restore round-trip intact).
  final String? wireProtocol;

  final double inputFee;

  /// Rate for cached input tokens, or null when the fee group leaves it unset —
  /// in which case cache hits bill at [inputFee]. Read via [effectiveCacheInputFee].
  final double? cacheInputFee;

  final double outputFee;
  final String billingMode; // 'token' or 'request'
  final double requestFee;

  // Proxy settings
  final bool proxyEnabled;
  final String? proxyUrl;
  final String? proxyUsername;
  final String? proxyPassword;

  LLMModelConfig({
    this.id,
    required this.modelId,
    required this.channelType,
    required String endpoint,
    required this.apiKey,
    this.enableThinking = false,
    this.reasoningEffort,
    this.enableWebSearch = false,
    this.wireProtocol,
    this.inputFee = 0.0,
    this.cacheInputFee,
    this.outputFee = 0.0,
    this.billingMode = 'token',
    this.requestFee = 0.0,
    this.proxyEnabled = false,
    this.proxyUrl,
    this.proxyUsername,
    this.proxyPassword,
  }) : endpoint = normalizeEndpoint(endpoint);

  /// This config pointed at a different base URL — used by the dispatcher
  /// when a vendor serves a *generic* protocol on an alternate face (e.g.
  /// DashScope's Anthropic-compatible chat under `/apps/anthropic/v1`), so
  /// the protocol itself stays vendor-blind. Everything else is carried over
  /// verbatim.
  LLMModelConfig withEndpoint(String newEndpoint) => LLMModelConfig(
        id: id,
        modelId: modelId,
        channelType: channelType,
        endpoint: newEndpoint,
        apiKey: apiKey,
        enableThinking: enableThinking,
        reasoningEffort: reasoningEffort,
        enableWebSearch: enableWebSearch,
        wireProtocol: wireProtocol,
        inputFee: inputFee,
        cacheInputFee: cacheInputFee,
        outputFee: outputFee,
        billingMode: billingMode,
        requestFee: requestFee,
        proxyEnabled: proxyEnabled,
        proxyUrl: proxyUrl,
        proxyUsername: proxyUsername,
        proxyPassword: proxyPassword,
      );

  /// Strips surrounding whitespace and trailing slashes from a base URL.
  /// See [endpoint].
  static String normalizeEndpoint(String raw) {
    var base = raw.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return base;
  }

  /// Rate actually charged per cached input token.
  double get effectiveCacheInputFee => cacheInputFee ?? inputFee;

  /// A client for this channel, shared with every other request that would
  /// open the same connection.
  ///
  /// A client per request is a TCP connection per request, which means a TLS
  /// handshake and a fresh slow-start ramp for every upload — paid a dozen or
  /// more times in a single agent turn, against a host that is usually far
  /// away.
  ///
  /// The returned handle's `close()` does nothing: ownership stays with
  /// [LLMClientPool]. Every protocol closes its client in a `finally`, which
  /// is right for a private client and fatal for a shared one, and swallowing
  /// the call is safer than teaching twenty-seven call sites the difference.
  http.Client createClient() => LLMClientPool.take(this);

  /// Everything that determines which connection a request opens.
  ///
  /// The API key is deliberately absent: it travels as a header, so two
  /// channels with different keys against the same endpoint can share a
  /// connection. Endpoint and proxy are what cannot be shared.
  ///
  /// Being derived rather than stored is what removes the invalidation
  /// problem: edit a channel's endpoint and the next request simply computes
  /// a different key and takes a different client.
  String get connectionKey => proxyEnabled && (proxyUrl?.isNotEmpty ?? false)
      ? '$endpoint|$proxyUrl|$proxyUsername|$proxyPassword'
      : endpoint;

  /// Builds the underlying client this config needs. Called by
  /// [LLMClientPool] on a miss, never directly.
  http.Client buildClient() {
    if (!proxyEnabled || proxyUrl == null || proxyUrl!.isEmpty) {
      return http.Client();
    }

    // Clean proxy URL (remove http:// or https:// if present for HttpClient.findProxy)
    String hostPort = proxyUrl!;
    if (hostPort.startsWith('http://')) hostPort = hostPort.substring(7);
    if (hostPort.startsWith('https://')) hostPort = hostPort.substring(8);
    // Remove trailing slash
    if (hostPort.endsWith('/')) hostPort = hostPort.substring(0, hostPort.length - 1);

    final httpClient = HttpClient();
    httpClient.findProxy = (uri) {
      return "PROXY $hostPort";
    };

    if (proxyUsername != null && proxyUsername!.isNotEmpty && proxyPassword != null) {
      httpClient.authenticateProxy = (host, port, scheme, realm) {
        httpClient.addProxyCredentials(host, port, realm ?? '', HttpClientBasicCredentials(proxyUsername!, proxyPassword!));
        return Future.value(true);
      };
    }

    return IOClient(httpClient);
  }
}

/// Keeps one live [http.Client] per distinct connection, so requests to the
/// same endpoint reuse the same sockets.
///
/// Deliberately keyed and capped rather than lifecycle-managed. There is no
/// "channel was edited" hook to forget to call: a changed endpoint or proxy
/// is a changed [LLMModelConfig.connectionKey], and the stale entry ages out
/// of the cap on its own.
class LLMClientPool {
  /// Small on purpose — a user has a handful of channels, and an entry holds
  /// open sockets. Past this the least-recently-taken client is evicted.
  static const int _maxClients = 8;

  /// Insertion-ordered, and re-inserted on every hit, so `keys.first` is the
  /// least recently used.
  static final Map<String, _PooledClient> _clients = {};

  static http.Client take(LLMModelConfig config) {
    final key = config.connectionKey;
    final cached = _clients.remove(key);
    if (cached != null) {
      _clients[key] = cached; // Re-inserted: now the most recently used.
      return _SharedClient(cached);
    }

    while (_clients.length >= _maxClients) {
      final oldest = _clients.keys.first;
      _clients.remove(oldest)?.evict();
    }

    final client = _PooledClient(config.buildClient());
    _clients[key] = client;
    return _SharedClient(client);
  }

  /// Closes every pooled client. For tests and shutdown; nothing in a normal
  /// session needs to call it.
  static void disposeAll() {
    for (final client in _clients.values) {
      client.evict();
    }
    _clients.clear();
  }

  @visibleForTesting
  static int get liveClients => _clients.length;
}

/// One pooled connection, plus a count of the requests still riding on it.
///
/// The count is what makes eviction safe. Eviction and use are unrelated
/// events — a video poll loop or an SSE stream can be mid-transfer when a
/// ninth endpoint pushes its client past the cap — and closing an
/// [IOClient] is `close(force: true)`: it does not drain, it tears the
/// sockets down, and the in-flight request dies with a `ClientException`.
/// One multi-face channel occupies up to three [LLMModelConfig.connectionKey]s
/// on its own, so the cap is reachable with a handful of channels and this is
/// an ordinary session, not a corner.
///
/// So eviction drops the *pool's* reference and nothing more; whoever leaves
/// last closes the client.
class _PooledClient {
  final http.Client inner;

  int _inFlight = 0;
  bool _evicted = false;

  _PooledClient(this.inner);

  void retain() => _inFlight++;

  void release() {
    if (--_inFlight <= 0 && _evicted) inner.close();
  }

  /// Drops the pool's reference. Closes now only if nothing is using it.
  void evict() {
    _evicted = true;
    if (_inFlight <= 0) inner.close();
  }

  @visibleForTesting
  int get inFlight => _inFlight;
}

/// A pooled client handle whose [close] is a no-op — see
/// [LLMModelConfig.createClient].
class _SharedClient extends http.BaseClient {
  final _PooledClient _pooled;

  _SharedClient(this._pooled);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    _pooled.retain();
    final http.StreamedResponse response;
    try {
      response = await _pooled.inner.send(request);
    } catch (_) {
      _pooled.release();
      rethrow;
    }

    // Held until the *body* is finished, not until the headers arrive: on a
    // streamed response `send` returns at the first byte, and a stream whose
    // client was closed underneath it is exactly what the count exists to
    // prevent.
    var released = false;
    void release() {
      if (released) return;
      released = true;
      _pooled.release();
    }

    return http.StreamedResponse(
      _releaseWhenDone(response.stream, release),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  /// [source] with [done] called once it can carry nothing more: drained, or
  /// cancelled by a caller that gave up — an idle guard tearing down its
  /// subscription is the common one, and `onDone` never fires for it.
  static Stream<List<int>> _releaseWhenDone(
      Stream<List<int>> source, void Function() done) {
    late final StreamController<List<int>> controller;
    StreamSubscription<List<int>>? sub;
    controller = StreamController<List<int>>(
      onListen: () {
        sub = source.listen(
          controller.add,
          onError: controller.addError,
          onDone: () {
            done();
            controller.close();
          },
        );
      },
      onPause: () => sub?.pause(),
      onResume: () => sub?.resume(),
      onCancel: () async {
        done();
        await sub?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  void close() {}
}

class LLMResponse {
  final String text;
  final List<Uint8List> generatedImages;
  final String? videoUri;
  final String? operationName;
  final Map<String, dynamic> metadata;

  /// Chain-of-thought the response carried, already separated from [text].
  /// See [LLMMessage.reasoningContent] for the round-trip contract.
  final String? reasoningContent;

  /// Wire field name of [reasoningContent], or null for inline/absent —
  /// see [LLMMessage.reasoningFieldName].
  final String? reasoningFieldName;

  /// ④'s seal over [reasoningContent] — see [LLMMessage.reasoningSignature].
  /// Must reach the assistant message that replays this turn, or the next
  /// request in a tool-calling conversation is rejected.
  final String? reasoningSignature;

  /// ④'s thinking-class blocks verbatim — see [LLMMessage.rawThinkingBlocks].
  final List<Map<String, dynamic>>? rawThinkingBlocks;

  /// Producer of [rawThinkingBlocks] — see [LLMMessage.rawThinkingModelId].
  final String? rawThinkingModelId;

  /// Tool calls requested by the model (empty when it answered directly).
  final List<LLMToolCall> toolCalls;

  LLMResponse({
    required this.text,
    this.generatedImages = const [],
    this.videoUri,
    this.operationName,
    this.metadata = const {},
    this.reasoningContent,
    this.reasoningFieldName,
    this.reasoningSignature,
    this.rawThinkingBlocks,
    this.rawThinkingModelId,
    this.toolCalls = const [],
  });
}

class LLMResponseChunk {
  final String? textPart;

  /// Chain-of-thought increment, kept out of [textPart] so consumers that
  /// accumulate text never glue the model's thinking into the deliverable.
  final String? reasoningPart;

  /// Wire field name of [reasoningPart] — the ①/C2 echo-back key
  /// ([LLMMessage.reasoningFieldName]), carried per chunk because the stream
  /// consumer assembles an [LLMResponse] and the replay obligation travels
  /// with the name, not just the text. Null on ④, whose obligation is the
  /// signed block ([rawThinkingBlocks]), and for inline `<think>` reasoning,
  /// which carries no obligation at all.
  final String? reasoningFieldName;

  final Uint8List? imagePart;
  final Map<String, dynamic>? metadata;

  /// One whole tool call. Emitted by the Google chunk parser, which is shared
  /// between that family's streaming and synchronous paths — the synchronous
  /// one reassembles [LLMResponse.toolCalls] from these — and by ④'s stream,
  /// which declares tools and assembles the calls itself.
  ///
  /// **Always a complete call, never a fragment.** ④ delivers tool arguments
  /// as `input_json_delta` fragments that are not valid JSON until the last
  /// one, so the accumulator lives inside the protocol and a call is emitted
  /// only at `content_block_stop`. Consumers may assume they can act on
  /// whatever arrives here.
  final LLMToolCall? toolCallPart;

  /// ④'s thinking blocks, verbatim and in order, emitted once at stream end.
  ///
  /// Not derivable from [reasoningPart]: that is display text, and the replay
  /// obligation is over the whole sealed block (including
  /// `redacted_thinking`, which has no text at all). A tool-calling turn
  /// replayed without them is an incomplete thinking history, which ④
  /// silently strips — thinking stops, billing continues — rather than
  /// rejecting. Only reachable now that the streaming surface can carry a
  /// tool call, which is the only turn whose replay needs them.
  final List<Map<String, dynamic>>? rawThinkingBlocks;

  /// The seal over the last thinking block, for [LLMMessage.reasoningSignature].
  final String? reasoningSignature;

  final bool isDone;

  LLMResponseChunk({
    this.textPart,
    this.reasoningPart,
    this.reasoningFieldName,
    this.imagePart,
    this.metadata,
    this.toolCallPart,
    this.rawThinkingBlocks,
    this.reasoningSignature,
    this.isDone = false,
  });
}
