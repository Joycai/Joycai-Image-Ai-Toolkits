import 'dart:convert';

/// Independent credentials for temporary media upload. Never used for inference.
class ChannelUploadConfig {
  const ChannelUploadConfig({
    required this.tokenPlan,
    required this.endpoint,
    required this.apiKey,
  });
  final bool tokenPlan;
  final String endpoint;
  final String apiKey;

  Map<String, Object> toJson() => {'tokenPlan': tokenPlan, 'endpoint': endpoint, 'apiKey': apiKey};

  static ChannelUploadConfig? fromJson(Object? value) {
    if (value is! Map) return null;
    return ChannelUploadConfig(
      tokenPlan: value['tokenPlan'] == true,
      endpoint: value['endpoint'] is String ? (value['endpoint'] as String).trim() : '',
      apiKey: value['apiKey'] is String ? (value['apiKey'] as String).trim() : '',
    );
  }

  /// Transforms only the secret, preserving route metadata and future fields.
  static String? mapDocumentKey(String? document, String Function(String) transform) {
    if (document == null) return null;
    dynamic json;
    try {
      json = jsonDecode(document);
    } on FormatException {
      return document;
    }
    if (json is! Map || json['mediaUpload'] is! Map) return document;
    final upload = json['mediaUpload'] as Map;
    final key = upload['apiKey'];
    if (key is! String || key.isEmpty) return document;
    upload['apiKey'] = transform(key);
    return jsonEncode(json);
  }

  static String documentKey(String? document) {
    var key = '';
    mapDocumentKey(document, (value) {
      key = value;
      return value;
    });
    return key;
  }

  static bool isTokenPlan(String endpoint) =>
      Uri.tryParse(endpoint)?.host == 'token-plan.cn-beijing.maas.aliyuncs.com';
}
