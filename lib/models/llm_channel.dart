class LLMChannel {
  final int? id;
  final String displayName;
  final String endpoint;
  final String apiKey;
  final String type; // google-genai-rest, openai-api-rest, etc.
  final bool enableDiscovery;
  final String? tag;
  final int? tagColor;

  /// Position in the channel rail, ascending. Rows are ordered by this and
  /// then by [id], so equal values (an old backup restored without the
  /// column) degrade to creation order — what the rail showed before it was
  /// sortable.
  ///
  /// Deliberately absent from [toMap]: the order is owned by
  /// `ModelRepository.updateChannelOrder` alone. Round-tripping it through
  /// every edit would let the channel editor — which builds a fresh
  /// [LLMChannel] with no idea of its position — silently reset a channel to
  /// the top of the rail on save.
  final int sortOrder;

  LLMChannel({
    this.id,
    required this.displayName,
    required this.endpoint,
    required this.apiKey,
    required this.type,
    this.enableDiscovery = true,
    this.tag,
    this.tagColor,
    this.sortOrder = 0,
  });

  factory LLMChannel.fromMap(Map<String, dynamic> map) {
    return LLMChannel(
      id: map['id'] as int?,
      displayName: map['display_name'] as String,
      endpoint: map['endpoint'] as String,
      apiKey: map['api_key'] as String,
      type: map['type'] as String,
      enableDiscovery: (map['enable_discovery'] ?? 1) == 1,
      tag: map['tag'] as String?,
      tagColor: map['tag_color'] as int?,
      sortOrder: map['sort_order'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap({bool includeId = true}) {
    final map = {
      'display_name': displayName,
      'endpoint': endpoint,
      'api_key': apiKey,
      'type': type,
      'enable_discovery': enableDiscovery ? 1 : 0,
      'tag': tag,
      'tag_color': tagColor,
    };
    if (includeId) {
      map['id'] = id;
    }
    return map;
  }
}