import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../state/app_state.dart';
import '../llm_debug_logger.dart';
import '../llm_types.dart';
import 'gemini_payload.dart';
import 'protocol.dart';

/// Imagen text-to-image via the dedicated Gemini `:predict` surface
/// (not `:generateContent`). Text-to-image only — reference images are
/// surfaced (rather than silently dropped) via a warning.
class GeminiImagenProtocol implements ImageGenProtocol {
  @override
  Future<LLMResponse> generateImage(
    LLMTarget target,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    LLMLogger? logger,
  }) async {
    final config = target.config;
    final baseUrl = trimBaseUrl(config.endpoint);
    final url = target.decorateUrl(
        Uri.parse('$baseUrl/models/${config.modelId}:predict'));
    logger?.call('Preparing Imagen request to: ${url.host}', level: 'DEBUG');

    // Imagen is text-to-image only — surface (rather than silently drop) any
    // reference images the user attached.
    final refCount = history
        .where((m) => m.role == LLMRole.user)
        .expand((m) => m.attachments)
        .length;
    if (refCount > 0) {
      logger?.call(
        'Imagen does not support reference images; ignoring $refCount attached image(s).',
        level: 'WARN',
      );
    }

    final headers = target.headers();
    final payload = prepareImagenPayload(history, options);

    final client = config.createClient();
    try {
      final appState = AppState();
      File? debugFile;
      if (appState.enableApiDebug) {
        debugFile = await LLMDebugLogger.startLog(config.modelId, 'GoogleImagen (Predict)', {
          'url': url.toString(),
          'headers': headers,
          'body': getSafePayload(payload),
        });
      }

      final response = await client.post(url, headers: headers, body: jsonEncode(payload));

      if (debugFile != null) {
        await LLMDebugLogger.appendLine(debugFile, 'Status: ${response.statusCode}');
        await LLMDebugLogger.appendLine(debugFile, 'Body: ${response.body}');
      }

      final data = jsonDecode(response.body);
      if (data['error'] != null) {
        final err = data['error'];
        final msg = 'Imagen Error: [${err['code']}] ${err['message']} (${err['status']})';
        logger?.call(msg, level: 'ERROR');
        throw Exception(msg);
      }

      if (response.statusCode != 200) {
        throw Exception('Imagen Request failed: ${response.statusCode} - ${response.body}');
      }

      final List<Uint8List> images = [];
      final predictions = data['predictions'] as List?;
      if (predictions != null) {
        for (final p in predictions) {
          final b64 = p['bytesBase64Encoded'] ?? p['image']?['bytesBase64Encoded'];
          if (b64 is String) {
            try {
              images.add(base64Decode(b64));
            } catch (_) {/* ignore */}
          }
        }
      }

      logger?.call('Imagen parse complete. Images: ${images.length}', level: 'DEBUG');
      return LLMResponse(text: '', generatedImages: images, metadata: {});
    } finally {
      client.close();
    }
  }
}
