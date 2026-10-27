/// Wire usage normalization. Raw totals overlap modality details and are never
/// extra billable components. No vendor price or internal accounting key is read.
Map<String, dynamic> normalizeTokenUsage(
  Map<String, dynamic> usage, {
  bool imageOutput = false,
  bool hasGeneratedImages = false,
}) {
  var invalid = false;
  Object? count(Object? value) {
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
  Object? modality(Object? list, String type) {
    if (list is! List) return null;
    final items = list.whereType<Map>().where((m) => m['modality'] == type);
    return items.isEmpty
        ? null
        : items.fold<num>(0, (sum, m) => sum + (m['tokenCount'] as num? ?? 0));
  }

  final text = count(inputDetails['text_tokens'] ?? modality(modalities, 'TEXT'));
  final image = count(inputDetails['image_tokens'] ?? modality(modalities, 'IMAGE'));
  final output = count(
    usage['completion_tokens'] ??
        usage['output_tokens'] ??
        (usage['candidatesTokenCount'] is num
            ? (usage['candidatesTokenCount'] as num) + (usage['thoughtsTokenCount'] as num? ?? 0)
            : null),
  );
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
        imageOutput ||
        hasGeneratedImages ||
        modality(usage['candidatesTokensDetails'], 'IMAGE') != null,
    if (multimodal || hasGeneratedImages || usage['candidatesTokensDetails'] != null) ...{
      'text_input': text,
      'image_input': image,
      'text_cache': count(
        cacheDetails['text_tokens'] ?? modality(usage['cacheTokensDetails'], 'TEXT'),
      ),
      'image_cache': count(
        cacheDetails['image_tokens'] ?? modality(usage['cacheTokensDetails'], 'IMAGE'),
      ),
      'image_output': imageOutput
          ? output
          : count(modality(usage['candidatesTokensDetails'], 'IMAGE')),
      'text_output': imageOutput ? 0 : count(modality(usage['candidatesTokensDetails'], 'TEXT')),
    },
  };
  result['invalid'] = invalid;
  return result;
}
