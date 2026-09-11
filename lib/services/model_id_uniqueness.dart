import '../models/llm_model.dart';

/// Whether [modelId] is already used by another model on [channelId].
///
/// A channel's model IDs must be unique (`D1c` 保存校验): the ID is what goes
/// on the wire, so two rows with one ID on one channel are the same model
/// under two names, listed twice in every picker. The comparison is exact
/// after trimming — providers treat IDs as case-sensitive — which is also the
/// rule the discovery dialog marks 「Already Added」 by.
///
/// [exceptId] is the database id of the model being edited, which does not
/// collide with itself.
bool isModelIdTaken(
  Iterable<LLMModel> models, {
  required int? channelId,
  required String modelId,
  int? exceptId,
}) {
  final id = modelId.trim();
  if (channelId == null || id.isEmpty) return false;
  return models.any((m) => m.channelId == channelId && m.id != exceptId && m.modelId.trim() == id);
}
