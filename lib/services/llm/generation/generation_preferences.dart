import 'dart:convert';

import 'generation_schema.dart';

/// Keys describe user intent, not a capability-table version. A new schema
/// validates a stored draft instead of erasing it. Family keys are read-only
/// migration seeds and are never written by new controls.
class GenerationPreferences {
  static String base({required Object model, required int? channel, required String? protocol}) =>
      jsonEncode(['generation-v1', model, channel, protocol]);

  static String key(String base, GenerationOperation operation, String param) =>
      param == 'imageTask' ? '$base.mode' : '$base.${operation.name}.$param';

  static String? read(Map<String, String> store, String key, String legacyKey) =>
      store[key] ?? store[legacyKey];
}
