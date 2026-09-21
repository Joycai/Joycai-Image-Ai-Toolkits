import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../../core/image_magic.dart';
import '../llm_types.dart';
import '../model_descriptor.dart';
import '../output_spec.dart' show inputImageCountKey, parseWxH;
import '../vendors/vendor_profile.dart';

// Every debug-log line that prints a request URL must redact it first —
// Google-keyed vendors carry `?key=<API_KEY>` in the URL (VendorProfile
// .decorateUrl), and relying on the log sink's regex to catch it made one
// mechanism's bug a credential leak. Re-exported here so protocols need no
// extra import.
export '../vendors/vendor_profile.dart' show redactUrl;
export '../output_spec.dart' show parseWxH;
// The shared async-job poll loop (cancel probe, sliced sleep, consecutive
// failure tolerance, non-retryable abandon) — see job_poll.dart.
export '../job_poll.dart';

/// **Layer 1 — the protocol.**
///
/// A protocol is one *wire format*: an endpoint shape, a request payload, a
/// response/stream parsing rule. Protocols are stateless and vendor-agnostic —
/// the only vendor input they take is authentication ([VendorProfile.headers] /
/// [VendorProfile.decorateUrl]) and the only model input is the resolved
/// [ModelDescriptor]. A protocol must never branch on a vendor id and never
/// sniff a model id.
///
/// The dispatcher (`llm_dispatcher.dart`) composes the three layers: it picks
/// the protocol from `vendor.family` + `model.family` and hands the protocol a
/// fully-resolved [LLMTarget].

/// Everything a protocol needs to execute one request: the channel config
/// (endpoint, key, proxy), the vendor profile (auth) and the model descriptor
/// (capabilities, extension flags).
class LLMTarget {
  final LLMModelConfig config;
  final VendorProfile vendor;
  final ModelDescriptor model;

  const LLMTarget({
    required this.config,
    required this.vendor,
    required this.model,
  });

  Map<String, String> headers() =>
      vendor.headers(config.apiKey, config.endpoint);

  Uri decorateUrl(Uri url) => vendor.decorateUrl(url, config.apiKey);
}

/// The output cap this request carries, in tokens, or null for "send none".
///
/// The one place the protocol layer ranks its sources, so every chat wire
/// agrees: a per-request `options['maxTokens']` first (the channel probe asks
/// for one token so a connection test does not pay for a generation), then
/// the model's stored cap ([LLMModelConfig.maxOutputTokens], the user's
/// declaration in the model editor), then nothing. Null means the family's
/// own behaviour — ①②③ leave the field off and the host applies its default,
/// ④ substitutes `anthropicDefaultMaxTokens` because its field is mandatory.
/// A stored cap is deliberately not clamped against the context window here:
/// a hosted endpoint refuses an impossible request audibly, a local runtime
/// truncates on its own, and a silent rewrite would be a third behaviour the
/// user cannot see. The editor warns instead.
int? outputCapFor(LLMTarget target, Map<String, dynamic>? options) =>
    requestedMaxTokens(options) ?? target.config.maxOutputTokens;

typedef LLMLogger = Function(String, {String level});

/// Synchronous + streaming conversation surface.
abstract class ChatProtocol {
  Future<LLMResponse> generate(
    LLMTarget target,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    List<LLMTool>? tools,
    LLMLogger? logger,
  });

  /// Whether [generateStream] declares client tools and can return complete
  /// calls through [LLMResponseChunk.toolCallPart].
  ///
  /// False by default, because assembling a call out of deltas is real
  /// machinery and each family needs its own: ④ buffers `input_json_delta`
  /// per content-block index, while on ① `function.arguments` arrives
  /// fragmented across chunks and `delta.tool_calls[].index` — not `id`,
  /// which is fragmented too — is the only reliable grouping key
  /// (docs/api/tools.md §4).
  ///
  /// ① and DashScope's native face share one accumulator
  /// (`StreamingToolCallAccumulator`) because they share the wire spelling;
  /// ④ and ③ each have their own. A new family arrives without one, hence the
  /// default.
  ///
  /// `LLMService.request` reads this (via `LLMDispatcher.streamSupportsTools`)
  /// and falls back to [generate] where it is false. Overriding it without
  /// implementing the accumulator means a tool-bearing request silently
  /// answers as though no tools existed — the one failure mode an agent loop
  /// cannot detect.
  bool get streamingDeclaresTools => false;

  /// [tools] is ignored unless [streamingDeclaresTools] is true.
  ///
  /// Streaming matters for a tool-bearing request even though an agent loop
  /// cannot act on a partial batch — it needs every call in the message
  /// before it can pair a single result. The reason is not incremental
  /// consumption but **keeping the request alive**: `LLMService`'s streaming
  /// guard is per chunk and resets on every one, where the non-streaming
  /// guard has to cover the whole generation. A 6-7 K-token answer has no
  /// realistic flat deadline, which is what made every Prompt Assistant
  /// delivery time out mid-write (docs/plans/2026-08-assistant-timeout.md).
  Stream<LLMResponseChunk> generateStream(
    LLMTarget target,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    List<LLMTool>? tools,
    LLMLogger? logger,
  });
}

/// Single-shot image generation/editing surface (no streaming).
abstract class ImageGenProtocol {
  Future<LLMResponse> generateImage(
    LLMTarget target,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    LLMLogger? logger,
  });
}

/// Asynchronous job surface: submit returns an operation id, poll reports
/// status. Poll results use the Veo-shaped envelope
/// (`{done, response: {generateVideoResponse: ...}}`) the task executor
/// already speaks, regardless of the upstream's native format.
abstract class VideoJobProtocol {
  Future<String> submit(
    LLMTarget target,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    LLMLogger? logger,
  });

  Future<Map<String, dynamic>> poll(
    LLMTarget target,
    String operationName, {
    Map<String, dynamic>? options,
    LLMLogger? logger,
  });
}

/// An async job surface that can also be *stopped* upstream.
///
/// Optional, and deliberately not folded into [VideoJobProtocol]: most
/// upstreams have no cancel at all, and the ones that do disagree about what
/// it means. Implementing this is a claim that abandoning the local task can
/// be made to mean something upstream — the dispatcher asks whether the
/// resolved protocol implements it and skips the call otherwise, so a family
/// without one keeps today's behaviour (give up locally, let the job run).
///
/// Best-effort by contract: a cancel that upstream refuses is a fact to log,
/// not a task failure. The local task is already going away either way.
abstract class CancellableJobProtocol {
  /// Returns what upstream reports it did, or null when it declined (or when
  /// the task was past the point where cancelling is safe). Implementations
  /// must not throw for an ordinary refusal.
  Future<String?> cancel(
    LLMTarget target,
    String operationName, {
    LLMLogger? logger,
  });
}

/// A model surfaced by a [DiscoveryProtocol] listing.
class DiscoveredModel {
  final String modelId;
  final String displayName;
  final String description;
  final Map<String, dynamic> rawData;

  DiscoveredModel({
    required this.modelId,
    required this.displayName,
    this.description = '',
    required this.rawData,
  });
}

/// Model listing surface.
abstract class DiscoveryProtocol {
  Future<List<DiscoveredModel>> fetchModels(LLMTarget target);
}

// ---------------------------------------------------------------------------
// Shared wire-level helpers
// ---------------------------------------------------------------------------

/// Throws when a 200 response body is actually an error envelope.
///
/// Compat layers deliver failures inside a successful HTTP response in at
/// least two spellings (streaming.md §3.1/§3.2): an `error` field (relays,
/// audits, quota), or MiniMax's `base_resp.status_code != 0` (auth 1004,
/// balance 1008, rate 1002, token limit 1039). A client that only checks the
/// HTTP status reads an expired key as a normal empty reply.
///
/// Lives here rather than in one protocol because every JSON surface a relay
/// fronts can return it — the images endpoints as much as chat.
void throwIfEnvelopeError(Map<String, dynamic> data) {
  final err = data['error'];
  if (err != null) {
    final msg = err is Map ? (err['message'] ?? err.toString()) : err.toString();
    throw LLMApiException('API error in response body: $msg',
        isEnvelope: true);
  }
  final baseResp = data['base_resp'];
  if (baseResp is Map) {
    final code = baseResp['status_code'];
    if (code is num && code != 0) {
      throw LLMApiException(
          'API error (base_resp $code): ${baseResp['status_msg'] ?? 'unknown'}',
          isEnvelope: true);
    }
  }
}

/// Decodes a JSON API response in the one safe order: status first, then
/// JSON, then shape, then in-body error envelopes. Returns the body as a map.
///
/// The order matters. The Gemini protocols used to `jsonDecode` before
/// checking the status code, so a gateway's HTML 502 surfaced as
/// `FormatException: Unexpected character` — the real status never appeared
/// anywhere and the retry policy could not see the 5xx. Checking the status
/// first keeps the code in the error; decoding second turns "the base URL
/// points at something that is not this API" (nginx 404 pages, login pages,
/// CDN errors) into words instead of a parser crash; the envelope check last
/// catches relays that deliver failures inside a 200 (protocol.dart
/// [throwIfEnvelopeError]).
///
/// On a non-2xx status the body is still probed for a JSON `error.message` so
/// the thrown message leads with the provider's own words when there are any.
///
/// [checkEnvelope] exists for the async-job *poll* surfaces, which must pass
/// false: a failed job arrives inside a 200 as `{status: "failed", error:
/// {...}}` and the poller's own status machine turns that into an error that
/// names the operation — the generic envelope check would fire first and
/// discard that context. Every request/submit surface keeps the default.
Map<String, dynamic> decodeJsonBody(http.Response response,
    {String apiName = 'API', bool checkEnvelope = true}) {
  final status = response.statusCode;
  if (status < 200 || status >= 300) {
    String detail = _bodyExcerpt(response.body);
    final decoded = _tryJsonDecode(response.body);
    if (decoded is Map) {
      final err = decoded['error'];
      if (err is Map && err['message'] != null) {
        detail = '${err['message']}'
            '${err['status'] != null ? ' (${err['status']})' : ''}';
      }
    }
    throw LLMApiException(
        '$apiName request failed: $status${_requestUrlNote(response)} - '
        '$detail',
        statusCode: status,
        retryAfter: parseRetryAfter(response.headers));
  }

  final decoded = _tryJsonDecode(response.body);
  if (decoded == null) {
    throw LLMApiException(
        '$apiName returned a non-JSON body (HTML error page?)'
        '${_requestUrlNote(response)} — the base URL may point at something '
        'that is not this API. Body: ${_bodyExcerpt(response.body)}',
        isNonJsonBody: true);
  }
  if (decoded is! Map) {
    throw LLMApiException(
        '$apiName returned an unexpected body shape '
        '(${decoded.runtimeType})${_requestUrlNote(response)}: '
        '${_bodyExcerpt(response.body)}');
  }

  final data = decoded.cast<String, dynamic>();
  if (checkEnvelope) throwIfEnvelopeError(data);
  return data;
}

/// Reads a required status from an asynchronous job response.
///
/// An empty status is a malformed poll response, not a future in-progress
/// state. Treating it as the latter makes callers poll the wrong endpoint or
/// envelope until the multi-minute job deadline.
String requireJobStatus(
  Object? value, {
  required String job,
  required String jobId,
}) {
  final status = value?.toString().trim() ?? '';
  if (status.isEmpty) {
    throw LLMApiException(
      '$job $jobId returned no status; the poll response has an unexpected '
      'shape.',
    );
  }
  return status;
}

/// The wait a failed response asked for, read off its headers, or null when
/// it named none (or named one that does not parse).
///
/// Three spellings, checked in this order:
///  * `retry-after-ms` — milliseconds, fractional allowed (OpenAI and several
///    relays send it beside `retry-after` with more precision);
///  * `retry-after` as delay-seconds (RFC 9110 §10.2.3);
///  * `retry-after` as an HTTP-date, turned into a delay from [now]; a date
///    already past means "now" ([Duration.zero]).
///
/// Transport facts, so they live here and are read on every surface alike —
/// no vendor branch decides whether a 429 is honoured.
Duration? parseRetryAfter(Map<String, String> headers, {DateTime? now}) {
  String? header(String name) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name) return entry.value.trim();
    }
    return null;
  }

  final ms = header('retry-after-ms');
  if (ms != null) {
    final value = double.tryParse(ms);
    if (value != null && value >= 0 && value.isFinite) {
      return Duration(microseconds: (value * 1000).round());
    }
  }

  final raw = header('retry-after');
  if (raw == null || raw.isEmpty) return null;
  final seconds = double.tryParse(raw);
  if (seconds != null) {
    if (seconds < 0 || !seconds.isFinite) return null;
    return Duration(milliseconds: (seconds * 1000).round());
  }
  try {
    final at = HttpDate.parse(raw);
    final delay = at.difference(now ?? DateTime.now());
    return delay.isNegative ? Duration.zero : delay;
  } on HttpException {
    return null;
  } on FormatException {
    return null;
  }
}

Object? _tryJsonDecode(String body) {
  try {
    return jsonDecode(body);
  } on FormatException {
    return null;
  }
}

/// ` (<url>)` for the request [response] answered, redacted — or empty when
/// the response carries no request (tests build bare ones).
///
/// Errors name the URL because the commonest third-party failure is a base
/// URL that resolved somewhere unexpected, and a bare `404: <html>` gives the
/// user nothing to compare against what they pasted (errors 06 §2). Never the
/// key: [redactUrl] masks `?key=`, and auth headers are not part of the URL.
String _requestUrlNote(http.Response response) {
  final url = response.request?.url;
  return url == null ? '' : ' (${redactUrl(url)})';
}

String _bodyExcerpt(String body) {
  final s = body.trim();
  return s.length > 500 ? '${s.substring(0, 500)}…' : s;
}

/// The payload of one SSE line, or null when the line carries none.
///
/// The single space after `data:` is *optional* in the SSE grammar — a relay
/// emitting `data:{"id":…}` is as conformant as one emitting `data: {"id":…}` —
/// but only the spaced spelling was recognized, and an unrecognized line fell
/// through to a JSON decode of the whole `data:{…}` string, which fails and is
/// skipped as noise. The reply arrived in full and parsed as nothing, with no
/// error anywhere.
///
/// Comments (`:` keep-alives), blank lines and the `[DONE]` terminator carry no
/// payload. A line with no `data:` prefix at all is returned unchanged, keeping
/// the tolerance for relays that stream bare JSON lines without SSE framing —
/// which is also why a caller that receives named events (④'s `event: …`
/// lines) must skip those itself before calling this.
///
/// Lives here rather than in one protocol because two families now parse SSE
/// and the `data:`-framing rules are the transport's, not either family's.
String? sseDataPayload(String line) {
  var s = line.trimRight();
  if (s.isEmpty) return null;
  if (s.startsWith('data:')) {
    s = s.substring(5);
    if (s.startsWith(' ')) s = s.substring(1);
  } else if (s.startsWith(':')) {
    return null;
  }
  if (s.isEmpty || s == '[DONE]') return null;
  return s;
}

/// [endpoint] without any trailing slashes.
///
/// Redundant for a [LLMModelConfig.endpoint], which is normalized on
/// construction — kept so every protocol builds its URL the same way and a
/// raw string from elsewhere is safe too.
String trimBaseUrl(String endpoint) {
  var base = endpoint.trim();
  while (base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }
  return base;
}

/// Turn one image reference from a response into bytes.
///
/// Three spellings, because the surfaces that hand back images disagree:
///  * an `http(s)` URL — fetched here rather than passed onward as a link.
///    These are signed object-storage URLs that expire (24 h on both
///    DashScope and MiniMax), so a gallery holding them is empty a day later.
///    The GET carries no auth header: the signature is in the URL and the API
///    key has no meaning at that host.
///  * a `data:<mime>;base64,…` URI.
///  * a bare base64 payload, which is what `response_format: base64` returns.
///
/// Shared rather than per-protocol: every image surface that receives a
/// reference needs exactly this — the Images APIs' `url` / `b64_json` items,
/// DashScope, MiniMax, Midjourney — and a fix to the fetch path has to land
/// in one place to be worth making (standard 13 §6).
///
/// Two rules every path obeys:
///  * **Bytes must be an image** ([imageMimeFromBytes]). Relays answer an
///    expired or unauthorised link with `200` + an HTML page; accepting it
///    wrote a `.png` nobody could open while the task reported success.
///    Unrecognised bytes are rejected with a WARN, never returned.
///  * **A URL gets one retry** after [retryDelay]. The image is already
///    billed, a freshly minted signed link plus a jittery network fail
///    together often enough, and the alternative is the whole generation
///    thrown away.
///
/// A `data:` URI or bare base64 is accepted wherever it turns up — relays
/// put it in the `url` field, where fetching it as a link fails on a desktop
/// HTTP stack.
Future<Uint8List?> resolveImageRef(
  String ref,
  http.Client client,
  LLMLogger? logger, {
  Duration retryDelay = const Duration(seconds: 1),
  Future<void>? abortTrigger,
}) async {
  final trimmed = ref.trim();
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    const attempts = 2;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        final request = http.AbortableRequest('GET', Uri.parse(trimmed),
            abortTrigger: abortTrigger);
        final resp =
            await http.Response.fromStream(await client.send(request));
        if (resp.statusCode == 200) {
          final bytes = resp.bodyBytes;
          if (imageMimeFromBytes(bytes) != null) return bytes;
          logger?.call(
              'Image URL answered 200 but the body is not an image '
              '(${resp.headers['content-type'] ?? 'no content-type'}, '
              '${bytes.length} bytes): $trimmed',
              level: 'WARN');
        } else {
          logger?.call('Image URL returned ${resp.statusCode}: $trimmed',
              level: 'WARN');
        }
      } on http.RequestAbortedException {
        rethrow;
      } catch (e) {
        logger?.call('Failed to fetch image URL: $e', level: 'WARN');
      }
      if (attempt < attempts) {
        logger?.call('Retrying the image download once.', level: 'INFO');
        await Future<void>.delayed(retryDelay);
      }
    }
    return null;
  }

  var payload = trimmed;
  if (trimmed.startsWith('data:')) {
    final comma = trimmed.indexOf(',');
    if (comma < 0) {
      // Length-guarded: a truncated ref can be shorter than the excerpt, and
      // a RangeError out of the *log line* would abort the generation this
      // path exists to skip past.
      final excerpt =
          trimmed.length > 32 ? '${trimmed.substring(0, 32)}…' : trimmed;
      logger?.call('Malformed data URI (no comma): $excerpt', level: 'WARN');
      return null;
    }
    payload = trimmed.substring(comma + 1);
  }
  final Uint8List bytes;
  try {
    // Line-wrapped and URL-safe base64 both occur in relay output.
    bytes = base64Decode(base64.normalize(payload.replaceAll(RegExp(r'\s'), '')));
  } catch (e) {
    logger?.call('Failed to decode inline image: $e', level: 'WARN');
    return null;
  }
  if (imageMimeFromBytes(bytes) == null) {
    logger?.call(
        'Inline image data is not a recognisable image (${bytes.length} '
        'bytes); skipped.',
        level: 'WARN');
    return null;
  }
  return bytes;
}

/// [resolveImageRef] over every reference one response carried, warning when
/// only some of them could be turned into images.
///
/// A partial result is still delivered — the pictures that arrived were paid
/// for — but it must not read as complete: the missing ones were billed too,
/// and their links expire. [source] names the surface in that warning.
Future<List<Uint8List>> resolveImageRefs(
  Iterable<String> refs,
  http.Client client,
  LLMLogger? logger, {
  required String source,
  Duration retryDelay = const Duration(seconds: 1),
  Future<void>? abortTrigger,
}) async {
  final all = refs.toList();
  final images = <Uint8List>[];
  for (final ref in all) {
    final bytes = await resolveImageRef(ref, client, logger,
        retryDelay: retryDelay, abortTrigger: abortTrigger);
    if (bytes != null) images.add(bytes);
  }
  if (images.isNotEmpty && images.length < all.length) {
    logger?.call(
        '$source: only ${images.length} of ${all.length} generated image(s) '
        'could be retrieved; the rest were billed but are not saved.',
        level: 'WARN');
  }
  return images;
}

/// The abort trigger `LLMService` put in [options] ([llmAbortTriggerKey]),
/// or null when the caller supplied none.
Future<void>? abortTriggerOf(Map<String, dynamic>? options) {
  final trigger = options?[llmAbortTriggerKey];
  return trigger is Future<void> ? trigger : null;
}

/// One non-streaming request that `LLMService` can abort while it is in
/// flight — the shared send path for JSON request/submit surfaces.
///
/// Byte-for-byte what `client.post(url, headers:, body:)` sends (headers
/// first, then the string body, so a declared `Content-Type` is kept and
/// only gains a charset), but as an [http.AbortableRequest] wired to
/// [abortTriggerOf] `options`. The client is pooled per endpoint and its
/// `close()` is a lease release, so closing it cannot stop one request; the
/// trigger can, and only this one.
///
/// Aborting throws [http.RequestAbortedException]. A billed submit aborted
/// after upstream accepted it is still billed — the user asked to stop, and
/// `LLMService` never retries an aborted attempt.
Future<http.Response> sendJsonRequest(
  http.Client client,
  Uri url, {
  required Map<String, String> headers,
  required String body,
  Map<String, dynamic>? options,
  String method = 'POST',
}) async {
  final request = buildJsonRequest(
    method,
    url,
    headers: headers,
    body: body,
    options: options,
  );
  return http.Response.fromStream(
      await client.send(trackBodySent(request, options)));
}

/// Builds an abortable JSON request for one-shot and streaming paths alike.
///
/// Cancelling a response subscription only helps after headers arrive. While
/// a stream waits for its first byte (or uploads a multimodal body), the
/// request-level trigger is the only way to stop it without closing the
/// channel's shared pooled client.
http.AbortableRequest buildJsonRequest(
  String method,
  Uri url, {
  required Map<String, String> headers,
  required String body,
  Map<String, dynamic>? options,
}) {
  final request = http.AbortableRequest(method, url,
      abortTrigger: abortTriggerOf(options));
  request.headers.addAll(headers);
  request.body = body;
  return request;
}

/// The body-sent callback `LLMService` put in [options] ([llmBodySentKey]),
/// or null when the caller supplied none.
void Function()? bodySentHookOf(Map<String, dynamic>? options) {
  final hook = options?[llmBodySentKey];
  return hook is void Function() ? hook : null;
}

/// [request] as it should be handed to `client.send`: unchanged, or — when
/// `options` carry [llmBodySentKey] — reporting the moment its body has been
/// handed to the connection in full. Apply it to a fully built request, at
/// the send call.
http.BaseRequest trackBodySent(
  http.BaseRequest request,
  Map<String, dynamic>? options,
) {
  final hook = bodySentHookOf(options);
  return hook == null ? request : _BodySentRequest(request, hook);
}

/// Forwards everything to [_inner] and calls [_onBodySent] when the body
/// stream ends. The client pipes [finalize] into the socket, so that end is
/// the moment the whole body has left this process. A wrapper because
/// `package:http`'s abortable request classes are final.
class _BodySentRequest extends http.BaseRequest with http.Abortable {
  final http.BaseRequest _inner;
  final void Function() _onBodySent;

  _BodySentRequest(this._inner, this._onBodySent)
      : super(_inner.method, _inner.url) {
    followRedirects = _inner.followRedirects;
    maxRedirects = _inner.maxRedirects;
    persistentConnection = _inner.persistentConnection;
  }

  @override
  Future<void>? get abortTrigger {
    final inner = _inner;
    return inner is http.Abortable ? inner.abortTrigger : null;
  }

  @override
  http.ByteStream finalize() {
    final body = _inner.finalize();
    // Copied after the inner finalize: a multipart request only settles its
    // boundary Content-Type and length there.
    headers.addAll(_inner.headers);
    contentLength = _inner.contentLength;
    super.finalize();
    return http.ByteStream(body.transform(
        StreamTransformer<List<int>, List<int>>.fromHandlers(
            handleDone: (sink) {
      _onBodySent();
      sink.close();
    })));
  }
}

/// The prompt the provider actually drew from, when it rewrote the one it
/// was sent — or `''` when none of [items] carries one.
///
/// Image surfaces that rewrite prompts say so per result item, under a key
/// the surface names ([key]): OpenAI's Images API `data[].revised_prompt`
/// (dall-e-3), DashScope's async task `output.results[].actual_prompt` (only
/// when `prompt_extend` is on). Returned as the response's text so the
/// executor's log shows what was really generated (standard 13 §1) — the
/// saved image is unaffected. Distinct values are joined by a blank line; a
/// batch that rewrote every picture the same way reads as one prompt.
String revisedPromptFrom(Object? items, {String key = 'revised_prompt'}) {
  if (items is! List) return '';
  final prompts = <String>[];
  for (final item in items) {
    if (item is! Map) continue;
    final value = item[key];
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty && !prompts.contains(trimmed)) {
        prompts.add(trimmed);
      }
    }
  }
  return prompts.join('\n\n');
}

/// One image as a multipart part, with the `Content-Type` the bytes actually
/// are.
///
/// `MultipartFile.fromBytes` without a content type labels the part
/// `application/octet-stream`. The official Images API tolerates that; a relay
/// that translates the multipart edit into its own JSON request (`images[]`
/// with `data:` URLs) copies the part's declared type into the data URL and
/// then rejects its own request with 400 "unsupported MIME type
/// 'application/octet-stream'" (seen live, 2026-09-05). The type is read off
/// the bytes ([resolveImageMime]) so a `.png` that holds JPEG is labelled
/// truthfully — the same rule every other surface follows.
http.MultipartFile imageMultipartFile(
  String field,
  Uint8List bytes, {
  required String declaredMime,
  required String baseName,
}) {
  final mime = resolveImageMime(bytes, declaredMime);
  return http.MultipartFile.fromBytes(
    field,
    bytes,
    filename: '$baseName.${extForMime(mime)}',
    contentType: MediaType.parse(mime),
  );
}

/// An input image as a `data:` URL whose MIME type is what the bytes are.
///
/// The declared type is the attachment's *file extension* (the executor
/// labels a `.png` as `image/png` whatever it holds), and renamed downloads
/// or relay output saved under the wrong name are ordinary. Hosts that
/// validate the declaration against the bytes reject the whole request; the
/// lenient ones decode by content and bill the same. [resolveImageMime] keeps
/// the declaration only for bytes it cannot recognise — the rule the
/// multipart path ([imageMultipartFile]) already follows.
String imageDataUrl(Uint8List bytes, String declaredMime) =>
    'data:${resolveImageMime(bytes, declaredMime)};base64,${base64Encode(bytes)}';

/// [attachments] cut to the [maxRef] reference images a model accepts —
/// the first ones, since the prompt numbers them in order. Null is no cap.
/// Said at WARN: the user picked more than were used.
///
/// Not the number that is *sent*: an attachment that cannot be read is
/// dropped afterwards, while the request body is built. A protocol counts
/// what it put in the body and publishes that — [sentInputImages].
List<LLMAttachment> capReferenceImages(
  List<LLMAttachment> attachments,
  int? maxRef,
  LLMLogger? logger,
) {
  if (maxRef == null || maxRef < 0 || attachments.length <= maxRef) {
    return attachments;
  }
  logger?.call(
    'Model accepts at most $maxRef reference image(s); using the first '
    '$maxRef of ${attachments.length}.',
    level: 'WARN',
  );
  return attachments.sublist(0, maxRef);
}

/// The metadata entry saying how many reference images a request carried
/// ([inputImageCountKey]) — spread into an images protocol's response
/// metadata, which is how a spec-billed fee group comes to charge for them.
/// [reported] is the provider's own count where it gives one, and outranks
/// [sent], the entries this client put in the body — the same precedence the
/// echoed output size has over the requested one. Empty for a request that
/// carried none, so text-to-image metadata stays as it was — but a
/// *reported* zero is published as a zero: on a stream the pictures already
/// went out carrying [sent], merged metadata keeps a key a later chunk
/// merely omits, and only an explicit value can lower it.
Map<String, dynamic> sentInputImages(int sent, {Object? reported}) {
  if (reported is num && reported.isFinite && reported >= 0) {
    return {inputImageCountKey: reported.toInt()};
  }
  return {if (sent > 0) inputImageCountKey: sent};
}

Future<Uint8List?> readAttachmentBytes(LLMAttachment att) async {
  if (att.path != null) return File(att.path!).readAsBytes();
  if (att.bytes != null) return att.bytes;
  return null;
}

String extForMime(String mime) {
  if (mime.contains('png')) return 'png';
  if (mime.contains('webp')) return 'webp';
  return 'jpg';
}

String? readStringOption(Map<String, dynamic>? options, String key) {
  final v = options?[key];
  if (v is String && v.isNotEmpty) return v;
  return null;
}

/// Map the per-model aspectRatio + resolution options onto a `WxH` size
/// string shared by the Sora-style and xAI video surfaces. Falls back to the
/// upstream default if neither is set.
///
/// Three-tier resolution ladder (480p / 720p / 1080p, defaulting to 720p for
/// anything unrecognized — e.g. the legacy Veo "4k" option) crossed with the
/// aspect ratios exposed across families.
String? resolveVideoSize(Map<String, dynamic>? options) {
  if (options == null) return null;

  // Explicit WxH wins, in any of the spellings [parseWxH] reads.
  final explicit = parseWxH(options['size']);
  if (explicit != null) return '${explicit.width}x${explicit.height}';

  final aspect = options['aspectRatio']?.toString();
  final resolution = options['resolution']?.toString() ?? '720p';

  final tier = resolution.contains('1080')
      ? '1080'
      : resolution.contains('480')
          ? '480'
          : '720';

  const sizes = {
    '16:9': {'480': '854x480', '720': '1280x720', '1080': '1920x1080'},
    '9:16': {'480': '480x854', '720': '720x1280', '1080': '1080x1920'},
    '1:1': {'480': '480x480', '720': '720x720', '1080': '1080x1080'},
    '4:3': {'480': '640x480', '720': '960x720', '1080': '1440x1080'},
    '3:4': {'480': '480x640', '720': '720x960', '1080': '1080x1440'},
    '3:2': {'480': '720x480', '720': '1080x720', '1080': '1620x1080'},
    '2:3': {'480': '480x720', '720': '720x1080', '1080': '1080x1620'},
  };

  return sizes[aspect]?[tier];
}

String? resolveVideoSeconds(Map<String, dynamic>? options) {
  final s = options?['seconds'];
  if (s == null) return null;
  return s.toString();
}

/// Whether a result URL points back at the API origin itself — the one case
/// where the channel's key belongs on the download. A signed storage or CDN
/// link lives on another origin. Host alone is insufficient: sending a key to
/// the same hostname over a different scheme or port can disclose it to an
/// unrelated service.
bool videoUriNeedsAuth(String uri, String endpoint) {
  final u = Uri.tryParse(uri);
  final e = Uri.tryParse(endpoint);
  if (u == null || e == null || u.host.isEmpty || e.host.isEmpty) {
    return false;
  }
  int effectivePort(Uri value) {
    if (value.hasPort) return value.port;
    return switch (value.scheme.toLowerCase()) {
      'https' => 443,
      'http' => 80,
      _ => -1,
    };
  }

  return u.scheme.toLowerCase() == e.scheme.toLowerCase() &&
      u.host.toLowerCase() == e.host.toLowerCase() &&
      effectivePort(u) == effectivePort(e);
}

num? _positiveSeconds(Object? raw) {
  final n = raw is num ? raw : num.tryParse(raw?.toString() ?? '');
  return n != null && n > 0 ? n : null;
}

/// [options] with its `imageSize` checked against the size control the
/// target's model declares (layer 3) — the same guard DashScope's payload
/// has always applied (`ParamSpec.normalize`), for every other image route.
///
/// A size the model does not take — kept from a model of another family, a
/// hand-typed `WxH` past gpt-image-2's area cap, `4K` on a Gemini that stops
/// at 2K — used to go out as stored, and the answer was a 400 at best and a
/// silently re-sized (and re-priced) picture at worst. It is replaced by the
/// control's default and the swap is logged. Returned unchanged when the
/// model declares no size control, when no size was chosen, or when the
/// chosen one is valid.
Map<String, dynamic>? optionsWithCheckedSize(
  LLMTarget target,
  Map<String, dynamic>? options, {
  LLMLogger? logger,
}) {
  final raw = options?['imageSize'];
  if (raw is! String || raw.isEmpty) return options;
  final spec = target.model.capabilities.imageParams
      .where((p) => p.key == 'imageSize')
      .firstOrNull;
  if (spec == null || spec.isValid(raw)) return options;
  final fallback = spec.defaultValue;
  logger?.call(
    'Size "$raw" is not one ${target.config.modelId} accepts; sending '
    '"$fallback" instead.',
    level: 'WARN',
  );
  return {...options!, 'imageSize': fallback};
}

/// The Veo-shaped "done" envelope every video poll returns
/// ([VideoJobProtocol.poll]), with the download-auth decision attached.
///
/// [renderedSeconds] is the length the provider reports it rendered, when it
/// reports one ([videoRenderedSecondsKey]).
Map<String, dynamic> videoDoneEnvelope(
  String operationName,
  String uri, {
  required bool requiresAuth,
  Object? renderedSeconds,
}) =>
    {
      'name': operationName,
      'done': true,
      videoRenderedSecondsKey: ?_positiveSeconds(renderedSeconds),
      'response': {
        'generateVideoResponse': {
          'generatedSamples': [
            {
              'video': {'uri': uri, videoRequiresAuthKey: requiresAuth},
            }
          ],
        },
      },
    };
