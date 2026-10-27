/// Wire usage normalization. Raw totals overlap modality details and are never
/// extra billable components. No vendor price or internal accounting key is read.
Map<String, dynamic> normalizeTokenUsage(
  Map<String, dynamic> usage, {
  bool imageOutput = false,
  bool hasGeneratedImages = false,
}) {
  var invalid = false;
  num? count(Object? value) {
    if (value == null) return null;
    if (value is String) value = num.tryParse(value);
    if (value is num && value.isFinite && value >= 0 && value == value.truncateToDouble()) {
      return value;
    }
    invalid = true;
    return null;
  }

  final details = usage['input_tokens_details'] ?? usage['prompt_tokens_details'];
  final inputDetails = details is Map ? details : const {};
  final cached = inputDetails['cached_tokens_details'];
  final cacheDetails = cached is Map ? cached : const {};
  final modalities = usage['promptTokensDetails'];
  num? modality(Object? list, String type) {
    if (list == null) return null;
    if (list is! List || list.isEmpty) return null;
    num total = 0;
    var malformed = false;
    for (final item in list) {
      if (item is! Map || item['modality'] is! String) {
        malformed = true;
        continue;
      }
      final value = count(item['tokenCount']);
      if (value == null) malformed = true;
      if (item['modality'] == type && value != null) total += value;
    }
    if (malformed) {
      invalid = true;
      return null;
    }
    // A nonempty modality breakdown enumerates the modalities present.
    // An absent breakdown, unlike an absent entry in one, remains unknown.
    return total;
  }

  final text = count(inputDetails['text_tokens'] ?? modality(modalities, 'TEXT'));
  final image = count(inputDetails['image_tokens'] ?? modality(modalities, 'IMAGE'));
  final candidates = count(usage['candidatesTokenCount']);
  final thoughts = count(usage['thoughtsTokenCount']);
  final output = count(
    usage['completion_tokens'] ??
        usage['output_tokens'] ??
        (candidates == null ? null : candidates + (thoughts ?? 0)),
  );
  final imageOutputCount = modality(usage['candidatesTokensDetails'], 'IMAGE');
  final textOutputCount = modality(usage['candidatesTokensDetails'], 'TEXT');
  final multimodal = imageOutput || text != null || image != null;
  final result = <String, dynamic>{
    'input': count(usage['promptTokenCount'] ?? usage['prompt_tokens'] ?? usage['input_tokens']),
    'output': output,
    'cache': count(
      usage['cachedContentTokenCount'] ??
          usage['cache_read_input_tokens'] ??
          inputDetails['cached_tokens'],
    ),
    'multimodal': multimodal,
    'output_split':
        imageOutput || hasGeneratedImages || (imageOutputCount != null && imageOutputCount > 0),
    if (multimodal || hasGeneratedImages || usage['candidatesTokensDetails'] != null) ...{
      'text_input': text,
      'image_input': image,
      'text_cache': count(
        cacheDetails['text_tokens'] ?? modality(usage['cacheTokensDetails'], 'TEXT'),
      ),
      'image_cache': count(
        cacheDetails['image_tokens'] ?? modality(usage['cacheTokensDetails'], 'IMAGE'),
      ),
      'image_output': imageOutput ? output : imageOutputCount,
      'text_output': imageOutput
          ? 0
          : textOutputCount == null
          ? null
          : textOutputCount + (thoughts ?? 0),
    },
  };
  result['invalid'] = invalid;
  return result;
}
