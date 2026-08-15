import 'dart:convert';
import 'dart:io';

import '../../../core/safety_settings.dart';
import '../../../state/app_state.dart';
import '../llm_debug_logger.dart';
import '../llm_types.dart';
import 'gemini_payload.dart';
import 'protocol.dart';

/// Veo long-running video generation via the Gemini
/// `POST /models/{model}:predictLongRunning` surface, polled through the
/// generic `GET /{operationName}` operations endpoint.
class GeminiVeoProtocol implements VideoJobProtocol {
  @override
  Future<String> submit(
    LLMTarget target,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    LLMLogger? logger,
  }) async {
    final config = target.config;
    final baseUrl = trimBaseUrl(config.endpoint);
    final url = target.decorateUrl(
        Uri.parse('$baseUrl/models/${config.modelId}:predictLongRunning'));

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
      final appState = AppState();
      File? debugFile;
      if (appState.enableApiDebug) {
        debugFile = await LLMDebugLogger.startLog(config.modelId, 'GoogleVeo (LRO Start)', {
          'url': redactUrl(url),
          'headers': headers,
          'body': payload,
        });
      }

      final response = await client.post(url, headers: headers, body: jsonEncode(payload));

      if (debugFile != null) {
        await LLMDebugLogger.appendLine(debugFile, 'Status: ${response.statusCode}');
        await LLMDebugLogger.appendLine(debugFile, 'Body: ${response.body}');
      }

      final data = decodeJsonBody(response, apiName: 'Google LRO');

      final name = data['name'] as String?;
      if (name == null) {
        throw Exception('Failed to get operation name from response');
      }

      return name;
    } finally {
      client.close();
    }
  }

  @override
  Future<Map<String, dynamic>> poll(
    LLMTarget target,
    String operationName, {
    LLMLogger? logger,
  }) async {
    final config = target.config;
    // Operation name usually starts with 'operations/'
    final url = target.decorateUrl(
        Uri.parse('${config.endpoint}/$operationName'));
    logger?.call('Checking Google operation: $operationName', level: 'DEBUG');

    final headers = target.headers();
    final client = config.createClient();
    try {
      final response = await client.get(url, headers: headers);

      if (response.statusCode != 200) {
        throw LLMApiException(
            'Failed to check operation: ${response.statusCode} - ${response.body}',
            statusCode: response.statusCode);
      }

      // Deliberately not [decodeJsonBody]: a *failed operation* is reported
      // inside a 200 as `{done: true, error: {...}}`, and the task executor
      // consumes that envelope — the shared decoder would turn it into a
      // thrown exception and change the poll contract.
      return jsonDecode(response.body);
    } finally {
      client.close();
    }
  }
}
