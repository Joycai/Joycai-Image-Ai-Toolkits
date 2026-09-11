import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/llm_model.dart';
import 'package:joycai_image_ai_toolkits/services/model_id_uniqueness.dart';

/// `isModelIdTaken`: the model editor's 「该渠道下已有同名 Model ID」 check.
void main() {
  LLMModel model(int id, String modelId, int channelId) =>
      LLMModel(id: id, modelId: modelId, modelName: modelId, tag: 'chat', channelId: channelId);

  final models = [model(1, 'gpt-4o', 10), model(2, 'gemini-2.5-flash', 20)];

  test('an ID already on the same channel is taken', () {
    expect(isModelIdTaken(models, channelId: 10, modelId: 'gpt-4o'), isTrue);
  });

  test('surrounding spaces do not make it a different ID', () {
    expect(isModelIdTaken(models, channelId: 10, modelId: '  gpt-4o '), isTrue);
  });

  test('the same ID on another channel is free', () {
    expect(isModelIdTaken(models, channelId: 20, modelId: 'gpt-4o'), isFalse);
  });

  test('the model being edited does not collide with itself', () {
    expect(isModelIdTaken(models, channelId: 10, modelId: 'gpt-4o', exceptId: 1), isFalse);
  });

  test('IDs are case-sensitive, as providers treat them', () {
    expect(isModelIdTaken(models, channelId: 10, modelId: 'GPT-4o'), isFalse);
  });

  test('no channel, or a blank ID, is never taken', () {
    expect(isModelIdTaken(models, channelId: null, modelId: 'gpt-4o'), isFalse);
    expect(isModelIdTaken(models, channelId: 10, modelId: '   '), isFalse);
  });
}
