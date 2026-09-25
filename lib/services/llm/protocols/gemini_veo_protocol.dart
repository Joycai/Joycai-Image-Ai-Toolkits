import 'dart:convert';

import '../../../core/safety_settings.dart';
import '../llm_debug_logger.dart';
import '../llm_types.dart';
import '../output_spec.dart' show reportedCostKey;
import 'gemini_payload.dart';
import 'protocol.dart';

/// Veo long-running video generation via the Gemini
/// `POST /models/{model}:predictLongRunning` surface, polled through the
/// generic `GET /{operationName}` operations endpoint.
class GeminiVeoProtocol implements VideoJobProtocol {
  @override
  Future<VideoSubmission> submit(
    LLMTarget target,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    LLMLogger? logger,
  }) async {
    final config = target.config;
    final baseUrl = trimBaseUrl(config.endpoint);
    final url = target.decorateUrl(
      Uri.parse('$baseUrl/models/${config.modelId}:predictLongRunning'),
    );

    final headers = target.headers();
    final payload = prepareVeoPayload(history, options);

    // Veo's :predictLongRunning surface has no safetySettings field — the
    // user-configured thresholds only apply to generateContent models.
    if (options?[SafetySettings.paramKey] != null) {
      logger?.call('Safety settings not supported by Veo API — skipped.', level: 'DEBUG');
    }

    // Debug logging for the user to see what's happening
    // Never log the full URL: for Google channels it carries `?key=<API_KEY>`
    // (see VendorProfile.decorateUrl), and this logger feeds the user-visible
    // console.
    logger?.call('POST URL: ${redactUrl(url)}', level: 'DEBUG');
    logger?.call('Headers: ${headers.keys.join(', ')}', level: 'DEBUG');

    // Log payload structure (without large data)
    final safePayload = getSafePayload(payload);
    logger?.call('Payload Structure: ${jsonEncode(safePayload)}', level: 'DEBUG');

    final client = config.createClient();
    try {
      LLMDebugLog? debugFile;
      if (LLMDebugLogger.enabled) {
        debugFile = await LLMDebugLogger.startLog(config.modelId, 'GoogleVeo (LRO Start)', {
          'url': redactUrl(url),
          'headers': headers,
          'body': payload,
        });
      }

      final response = await sendJsonRequest(
        client,
        url,
        headers: headers,
        body: jsonEncode(payload),
        options: options,
      );

      if (debugFile != null) {
        await LLMDebugLogger.appendLine(debugFile, 'Status: ${response.statusCode}');
        await LLMDebugLogger.appendLine(debugFile, 'Body: ${response.body}');
      }

      final data = decodeJsonBody(response, apiName: 'Google LRO');

      final name = data['name'] as String?;
      if (name == null) {
        throw LLMApiException('Failed to get operation name from response');
      }

      return VideoSubmission(name, inputImages: veoInputImages(payload));
    } finally {
      client.close();
    }
  }

  @override
  Future<Map<String, dynamic>> poll(
    LLMTarget target,
    String operationName, {
    Map<String, dynamic>? options,
    LLMLogger? logger,
  }) async {
    final config = target.config;
    // Operation name usually starts with 'operations/'
    final url = target.decorateUrl(Uri.parse('${config.endpoint}/$operationName'));
    logger?.call('Checking Google operation: $operationName', level: 'DEBUG');

    final headers = target.headers();
    final client = config.createClient();
    try {
      final response = await sendJsonRequest(
        client,
        url,
        headers: headers,
        body: '',
        options: options,
        method: 'GET',
      );

      // checkEnvelope: false — a *failed operation* is reported inside a 200
      // as `{done: true, error: {...}}`; [veoPollResult] turns it into an
      // error that names the operation, instead of the generic envelope check
      // discarding that context.
      final data = decodeJsonBody(response, apiName: 'Google operation poll', checkEnvelope: false);
      return veoPollResult(data, operationName, config.endpoint);
    } finally {
      client.close();
    }
  }
}

/// One Veo operation body, checked against the poll contract every other
/// video protocol already honours: **failure is thrown, never returned**
/// (standard 14 §1).
///
/// Veo was the exemption. Its poll handed back `{done: true, error: {...}}`
/// verbatim, the executor read only `response`, and the user saw "Operation
/// finished but no video URI found. Response: null" — the provider's code and
/// message were discarded. Now:
/// * `done` with `error` → [LLMApiException] carrying code and message;
/// * `done` with no samples but `raiMediaFilteredReasons` → the filter's
///   reasons, not a missing-URI mystery;
/// * `done` with samples → each `video` map gains [videoRequiresAuthKey]:
///   Google's `files/…:download` URIs live on the API host and need the key,
///   a relay's own storage link does not.
Map<String, dynamic> veoPollResult(
  Map<String, dynamic> data,
  String operationName,
  String endpoint,
) {
  if (data['done'] != true) return data;

  // The operation body goes back to the executor as it came, not as an
  // envelope of this app's making — so the two keys the executor reads as
  // *this app's* conclusions (the rendered length and the reported cost,
  // `videoDoneEnvelope`) are taken off it first. Veo reports neither; left
  // on, a relay serving the Gemini shape could name a field `reported_cost_usd`
  // and have it outrank the fee group (the reserved-key rule `upstreamUsage`
  // keeps on every other surface).
  data.remove(reportedCostKey);
  data.remove(videoRenderedSecondsKey);

  final error = data['error'];
  if (error != null) {
    final code = error is Map ? error['code'] : null;
    final message = error is Map ? (error['message'] ?? error) : error;
    throw LLMApiException(
      'Veo operation $operationName failed'
      '${code != null ? ' (code $code)' : ''}: $message',
      isJobEnded: true,
    );
  }

  final response = data['response'];
  final generated = response is Map ? response['generateVideoResponse'] : null;
  final samples = generated is Map ? generated['generatedSamples'] : null;
  if (samples is List && samples.isNotEmpty) {
    for (final sample in samples) {
      final video = sample is Map ? sample['video'] : null;
      final uri = video is Map ? video['uri'] : null;
      if (video is Map && uri is String) {
        video[videoRequiresAuthKey] = videoUriNeedsAuth(uri, endpoint);
      }
    }
  } else if (generated is Map && generated['raiMediaFilteredReasons'] != null) {
    throw LLMApiException(
      'Veo operation $operationName finished without a video — filtered by '
      'safety: ${generated['raiMediaFilteredReasons']}',
      isJobEnded: true,
    );
  }
  return data;
}
