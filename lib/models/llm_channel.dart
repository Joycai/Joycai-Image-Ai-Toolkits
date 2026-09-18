class LLMChannel {
  final int? id;
  final String displayName;
  final String endpoint;
  final String apiKey;
  final String type; // google-genai-rest, openai-api-rest, etc.
  final bool enableDiscovery;
  final String? tag;
  final int? tagColor;

  /// The fee group a model added to this channel starts in (`D1b · 1e` 计费)
  /// — by discovery, or by hand in the model editor, where it is only the
  /// initial choice. Null is no default. Not a foreign key: deleting a group
  /// clears it here in `ModelRepository.deletePricingGroup`.
  final int? defaultFeeGroupId;

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

  /// The channel's routes as an embedded JSON document (`llm_channels.routes`,
  /// v45), or null for a channel written before routes existed.
  ///
  /// Raw here for the same reason as `LLMModel.wireProtocol`: the LLM layer
  /// (`services/llm/channel_routes.dart`) parses and normalizes it against
  /// [type] and [endpoint], which always hold the primary route — so this
  /// model stays dumb and a document from a newer build survives a
  /// round-trip.
  final String? routes;

  LLMChannel({
    this.id,
    required this.displayName,
    required this.endpoint,
    required this.apiKey,
    required this.type,
    this.enableDiscovery = true,
    this.tag,
    this.tagColor,
    this.defaultFeeGroupId,
    this.sortOrder = 0,
    this.routes,
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
      defaultFeeGroupId: map['default_fee_group_id'] as int?,
      sortOrder: map['sort_order'] as int? ?? 0,
      routes: map['routes'] as String?,
    );
  }

  /// This channel with its flat primary-route columns and route document
  /// replaced — what the repository writes after normalizing.
  LLMChannel withRoutes({
    required String type,
    required String endpoint,
    required String routes,
  }) =>
      LLMChannel(
        id: id,
        displayName: displayName,
        endpoint: endpoint,
        apiKey: apiKey,
        type: type,
        enableDiscovery: enableDiscovery,
        tag: tag,
        tagColor: tagColor,
        defaultFeeGroupId: defaultFeeGroupId,
        sortOrder: sortOrder,
        routes: routes,
      );

  Map<String, dynamic> toMap({bool includeId = true}) {
    final map = {
      'display_name': displayName,
      'endpoint': endpoint,
      'api_key': apiKey,
      'type': type,
      'enable_discovery': enableDiscovery ? 1 : 0,
      'tag': tag,
      'tag_color': tagColor,
      'default_fee_group_id': defaultFeeGroupId,
      'routes': routes,
    };
    if (includeId) {
      map['id'] = id;
    }
    return map;
  }
}