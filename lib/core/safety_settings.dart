/// Gemini per-request safety-filter configuration shared by the state layer,
/// the workbench UI sliders and the request-payload builders.
///
/// See https://ai.google.dev/gemini-api/docs/safety-settings — four adjustable
/// harm categories, each with a block threshold ranging from strictest
/// (BLOCK_LOW_AND_ABOVE) to fully off (OFF).
library;

class SafetySettings {
  SafetySettings._();

  /// Adjustable harm categories, in the order shown in the UI.
  static const List<String> categories = [
    'HARM_CATEGORY_HARASSMENT',
    'HARM_CATEGORY_HATE_SPEECH',
    'HARM_CATEGORY_SEXUALLY_EXPLICIT',
    'HARM_CATEGORY_DANGEROUS_CONTENT',
  ];

  /// Thresholds ordered strict → permissive (slider left → right).
  static const List<String> thresholds = [
    'BLOCK_LOW_AND_ABOVE',
    'BLOCK_MEDIUM_AND_ABOVE',
    'BLOCK_ONLY_HIGH',
    'BLOCK_NONE',
    'OFF',
  ];

  /// Default matches the app's historical hardcoded behaviour.
  static const String defaultThreshold = 'BLOCK_NONE';

  /// Key used both for the DB setting and for the task-parameter map.
  static const String paramKey = 'safetySettings';

  static Map<String, String> defaults() =>
      {for (final c in categories) c: defaultThreshold};

  /// Validates a raw (possibly persisted/JSON-decoded) map into a complete
  /// category→threshold map, dropping unknown keys and bad values.
  static Map<String, String> normalize(Map<dynamic, dynamic>? raw) {
    final result = defaults();
    if (raw == null) return result;
    raw.forEach((key, value) {
      if (categories.contains(key) && thresholds.contains(value)) {
        result[key as String] = value as String;
      }
    });
    return result;
  }

  /// Builds the REST `safetySettings` list from task options. [raw] is the
  /// value of `options['safetySettings']` (a category→threshold map); missing
  /// or invalid input falls back to the defaults.
  static List<Map<String, String>> toApiList(dynamic raw) {
    final map = normalize(raw is Map ? raw : null);
    return [
      for (final entry in map.entries)
        {'category': entry.key, 'threshold': entry.value}
    ];
  }

  /// One-line human-readable summary for logs, e.g.
  /// `HARASSMENT=BLOCK_NONE, HATE_SPEECH=OFF, ...`.
  static String describe(dynamic raw) {
    final map = normalize(raw is Map ? raw : null);
    return map.entries
        .map((e) => '${e.key.replaceFirst('HARM_CATEGORY_', '')}=${e.value}')
        .join(', ');
  }
}
