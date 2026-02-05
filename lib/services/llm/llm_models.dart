import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

enum LLMRole { system, user, assistant }

class LLMAttachment {
  final String? path;
  final Uint8List? bytes;
  final String mimeType;

  LLMAttachment.fromFile(File file, this.mimeType) : path = file.path, bytes = null;
  LLMAttachment.fromBytes(this.bytes, this.mimeType) : path = null;
}

class LLMMessage {
  final LLMRole role;
  final String content;
  final List<LLMAttachment> attachments;

  LLMMessage({
    required this.role,
    required this.content,
    this.attachments = const [],
  });
}

class LLMModelConfig {
  final int? pk; // Database Primary Key
  final String modelId;
  final String type; // Provider type: 'google-genai' or 'openai-api'
  final String channelType; // 'google-genai-rest', 'openai-api-rest', 'official-google-genai-api'
  final String endpoint;
  final String apiKey;
  final double inputFee;
  final double outputFee;
  final String billingMode; // 'token' or 'request'
  final double requestFee;
  final Map<String, dynamic> extraParams;
  
  // Proxy settings
  final bool proxyEnabled;
  final String? proxyUrl;
  final String? proxyUsername;
  final String? proxyPassword;

  LLMModelConfig({
    this.pk,
    required this.modelId,
    required this.type,
    required this.channelType,
    required this.endpoint,
    required this.apiKey,
    this.inputFee = 0.0,
    this.outputFee = 0.0,
    this.billingMode = 'token',
    this.requestFee = 0.0,
    this.extraParams = const {},
    this.proxyEnabled = false,
    this.proxyUrl,
    this.proxyUsername,
    this.proxyPassword,
  });

  http.Client createClient() {
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

class LLMResponse {
  final String text;
  final List<Uint8List> generatedImages;
  final Map<String, dynamic> metadata;

  LLMResponse({
    required this.text,
    this.generatedImages = const [],
    this.metadata = const {},
  });
}

class LLMResponseChunk {
  final String? textPart;
  final Uint8List? imagePart;
  final Map<String, dynamic>? metadata;
  final bool isDone;

  LLMResponseChunk({this.textPart, this.imagePart, this.metadata, this.isDone = false});
}
