import 'dart:async';
import 'dart:typed_data';
import 'llm_models.dart';
import 'llm_provider_interface.dart';
import '../database_service.dart';

class LLMService {
  static final LLMService _instance = LLMService._internal();
  factory LLMService() => _instance;
  LLMService._internal();

  final Map<String, ILLMProvider> _providers = {};
  final Map<String, List<LLMMessage>> _sessions = {};

  void registerProvider(String type, ILLMProvider provider) {
    _providers[type] = provider;
  }

  /// Main entry point for high-level usage (Now uses requestStream internally)
  Future<LLMResponse> request({
    required String modelId,
    required List<LLMMessage> messages,
    String? sessionId,
    Map<String, dynamic>? options,
  }) async {
    String accumulatedText = "";
    List<Uint8List> accumulatedImages = [];
    Map<String, dynamic> metadata = {};

    await for (final chunk in requestStream(
      modelId: modelId,
      messages: messages,
      sessionId: sessionId,
      options: options,
    )) {
      if (chunk.textPart != null) accumulatedText += chunk.textPart!;
      if (chunk.imagePart != null) accumulatedImages.add(chunk.imagePart!);
    }

    return LLMResponse(
      text: accumulatedText,
      generatedImages: accumulatedImages,
      metadata: metadata,
    );
  }

  /// Streaming entry point
  Stream<LLMResponseChunk> requestStream({
    required String modelId,
    required List<LLMMessage> messages,
    String? sessionId,
    Map<String, dynamic>? options,
  }) async* {
    final config = await _getModelConfig(modelId);
    final provider = _getProvider(config.type);

    List<LLMMessage> fullHistory = messages;
    if (sessionId != null) {
      _sessions[sessionId] ??= [];
      _sessions[sessionId]!.addAll(messages);
      fullHistory = _sessions[sessionId]!;
    }

    String accumulatedText = "";
    
    await for (final chunk in provider.generateStream(config, fullHistory, options: options)) {
      if (chunk.textPart != null) accumulatedText += chunk.textPart!;
      yield chunk;
    }

    if (sessionId != null) {
      _sessions[sessionId]!.add(LLMMessage(
        role: LLMRole.assistant,
        content: accumulatedText,
      ));
    }
  }

  void clearSession(String sessionId) {
    _sessions.remove(sessionId);
  }

  ILLMProvider _getProvider(String type) {
    final provider = _providers[type];
    if (provider == null) {
      throw Exception("LLM Provider for type '$type' not registered.");
    }
    return provider;
  }

  Future<LLMModelConfig> _getModelConfig(String modelId) async {
    final db = DatabaseService();
    final models = await db.getModels();
    final modelData = models.firstWhere(
      (m) => m['model_id'] == modelId,
      orElse: () => throw Exception("Model $modelId not found in database"),
    );

    final type = modelData['type'] as String;
    final isPaid = modelData['is_paid'] == 1;

    String prefix = type == 'google-genai' 
        ? (isPaid ? 'google_paid' : 'google_free') 
        : 'openai';

    final endpoint = await db.getSetting('${prefix}_endpoint') ?? "";
    final apiKey = await db.getSetting('${prefix}_apikey') ?? "";

    return LLMModelConfig(
      modelId: modelId,
      type: type,
      endpoint: endpoint,
      apiKey: apiKey,
    );
  }
}
