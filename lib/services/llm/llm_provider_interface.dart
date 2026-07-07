import 'llm_types.dart';

abstract class ILLMProvider {
  /// Simple request-response.
  ///
  /// [tools] enables native tool/function calling: when provided, the model
  /// may answer with [LLMResponse.toolCalls] instead of (or alongside) text.
  Future<LLMResponse> generate(
    LLMModelConfig config,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    List<LLMTool>? tools,
    Function(String, {String level})? logger,
  });

  /// Streaming response
  Stream<LLMResponseChunk> generateStream(
    LLMModelConfig config,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    Function(String, {String level})? logger,
  });

  /// Start a long-running operation (e.g., Veo video generation)
  Future<String> startLongRunning(
    LLMModelConfig config,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    Function(String, {String level})? logger,
  });

  /// Check the status of a long-running operation
  Future<Map<String, dynamic>> checkOperation(
    LLMModelConfig config,
    String operationName, {
    Function(String, {String level})? logger,
  });
}
