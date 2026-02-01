import 'dart:io';
import 'dart:typed_data';

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
  final String modelId;
  final String type; // 'google-genai' or 'openai-api'
  final String endpoint;
  final String apiKey;
  final Map<String, dynamic> extraParams;

  LLMModelConfig({
    required this.modelId,
    required this.type,
    required this.endpoint,
    required this.apiKey,
    this.extraParams = const {},
  });
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
