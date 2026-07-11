import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

enum LLMRole { system, user, assistant, tool }

enum LLMReferenceType { media, asset, firstFrame, lastFrame }

class LLMAttachment {
  final String? path;
  final Uint8List? bytes;
  final String mimeType;
  final LLMReferenceType referenceType;

  LLMAttachment.fromFile(File file, this.mimeType, {this.referenceType = LLMReferenceType.media}) : path = file.path, bytes = null;
  LLMAttachment.fromBytes(this.bytes, this.mimeType, {this.referenceType = LLMReferenceType.media}) : path = null;
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
}

class LLMMessage {
  final LLMRole role;
  final String content;
  final List<LLMAttachment> attachments;

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
    this.toolCalls = const [],
    this.toolCallId,
    this.toolName,
  });
}

class LLMModelConfig {
  final int? id; // Database Primary Key
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
    this.id,
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
  final String? videoUri;
  final String? operationName;
  final Map<String, dynamic> metadata;

  /// Tool calls requested by the model (empty when it answered directly).
  final List<LLMToolCall> toolCalls;

  LLMResponse({
    required this.text,
    this.generatedImages = const [],
    this.videoUri,
    this.operationName,
    this.metadata = const {},
    this.toolCalls = const [],
  });
}

class LLMResponseChunk {
  final String? textPart;
  final Uint8List? imagePart;
  final Map<String, dynamic>? metadata;
  final LLMToolCall? toolCallPart;
  final bool isDone;

  LLMResponseChunk({this.textPart, this.imagePart, this.metadata, this.toolCallPart, this.isDone = false});
}
