/// One output target configured in the Image Workbench's Output Configs card.
///
/// Each entry pins a model, its parameter choices, an optional user label,
/// an enabled toggle, and an optional asynchronous batch flag. Multiple entries
/// can be enabled at once to run and compare several models or parameter sets
/// concurrently for the same prompt and reference images.
class ImageOutputConfig {
  final String id;
  final int? modelDbId;
  final String? modelIdFallback;
  final bool enabled;
  final String alias;
  final Map<String, String> params;
  final bool useBatch;

  ImageOutputConfig({
    required this.id,
    this.modelDbId,
    this.modelIdFallback,
    this.enabled = true,
    this.alias = '',
    Map<String, String> params = const {},
    this.useBatch = false,
  }) : params = Map.unmodifiable(params);

  static const Object _sentinel = Object();

  ImageOutputConfig copyWith({
    String? id,
    Object? modelDbId = _sentinel,
    Object? modelIdFallback = _sentinel,
    bool? enabled,
    String? alias,
    Map<String, String>? params,
    bool? useBatch,
  }) {
    return ImageOutputConfig(
      id: id ?? this.id,
      modelDbId: identical(modelDbId, _sentinel) ? this.modelDbId : modelDbId as int?,
      modelIdFallback: identical(modelIdFallback, _sentinel)
          ? this.modelIdFallback
          : modelIdFallback as String?,
      enabled: enabled ?? this.enabled,
      alias: alias ?? this.alias,
      params: params ?? this.params,
      useBatch: useBatch ?? this.useBatch,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'modelDbId': modelDbId,
    'modelIdFallback': modelIdFallback,
    'enabled': enabled,
    'alias': alias,
    'params': params,
    'useBatch': useBatch,
  };

  factory ImageOutputConfig.fromJson(Map<String, dynamic> json) {
    final rawParams = json['params'];
    final parsedParams = <String, String>{};
    if (rawParams is Map) {
      for (final entry in rawParams.entries) {
        if (entry.value != null) {
          parsedParams[entry.key.toString()] = entry.value.toString();
        }
      }
    }

    final rawDbId = json['modelDbId'];
    final int? parsedDbId = switch (rawDbId) {
      int v => v,
      num v => v.toInt(),
      String s => int.tryParse(s),
      _ => null,
    };

    return ImageOutputConfig(
      id: (json['id'] ?? '').toString(),
      modelDbId: parsedDbId,
      modelIdFallback: json['modelIdFallback']?.toString(),
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      alias: (json['alias'] ?? '').toString(),
      params: parsedParams,
      useBatch: json['useBatch'] is bool ? json['useBatch'] as bool : false,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ImageOutputConfig) return false;
    if (id != other.id ||
        modelDbId != other.modelDbId ||
        modelIdFallback != other.modelIdFallback ||
        enabled != other.enabled ||
        alias != other.alias ||
        useBatch != other.useBatch ||
        params.length != other.params.length) {
      return false;
    }
    for (final entry in params.entries) {
      if (other.params[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    id,
    modelDbId,
    modelIdFallback,
    enabled,
    alias,
    useBatch,
    Object.hashAllUnordered(params.entries.map((e) => Object.hash(e.key, e.value))),
  );
}
