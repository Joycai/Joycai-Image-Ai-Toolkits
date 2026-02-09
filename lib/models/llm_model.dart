class LLMModel {
  final int? id;
  final String modelId;
  final String modelName;
  final String type; // google-genai, openai-api
  final String tag; // image, chat, multimodal
  final bool isPaid;
  final int sortOrder;
  final int? channelId;
  final int? feeGroupId;
  
  // Performance metrics
  final double? estMeanMs;
  final double? estSdMs;
  final int tasksSinceUpdate;

  LLMModel({
    this.id,
    required this.modelId,
    required this.modelName,
    required this.type,
    required this.tag,
    this.isPaid = true,
    this.sortOrder = 0,
    this.channelId,
    this.feeGroupId,
    this.estMeanMs,
    this.estSdMs,
    this.tasksSinceUpdate = 0,
  });

  factory LLMModel.fromMap(Map<String, dynamic> map) {
    return LLMModel(
      id: map['id'] as int?,
      modelId: map['model_id'] as String,
      modelName: map['model_name'] as String,
      type: map['type'] as String,
      tag: map['tag'] as String,
      isPaid: (map['is_paid'] ?? 1) == 1,
      sortOrder: map['sort_order'] as int? ?? 0,
      channelId: map['channel_id'] as int?,
      feeGroupId: map['fee_group_id'] as int?,
      estMeanMs: map['est_mean_ms'] as double?,
      estSdMs: map['est_sd_ms'] as double?,
      tasksSinceUpdate: map['tasks_since_update'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'model_id': modelId,
      'model_name': modelName,
      'type': type,
      'tag': tag,
      'is_paid': isPaid ? 1 : 0,
      'sort_order': sortOrder,
      'channel_id': channelId,
      'fee_group_id': feeGroupId,
      'est_mean_ms': estMeanMs,
      'est_sd_ms': estSdMs,
      'tasks_since_update': tasksSinceUpdate,
    };
  }
}