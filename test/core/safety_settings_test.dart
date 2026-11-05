import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_distribution.dart';
import 'package:joycai_image_ai_toolkits/core/safety_settings.dart';

void main() {
  test('new defaults enable medium filtering in both distribution modes', () {
    expect(SafetySettings.defaults().values.toSet(), {'BLOCK_MEDIUM_AND_ABOVE'});
  });
  test('legacy task JSON cannot disable store filtering at the payload boundary', () {
    final raw = jsonDecode(
      '{"HARM_CATEGORY_HARASSMENT":"OFF",'
      '"HARM_CATEGORY_HATE_SPEECH":"BLOCK_NONE",'
      '"HARM_CATEGORY_SEXUALLY_EXPLICIT":"BLOCK_ONLY_HIGH",'
      '"HARM_CATEGORY_DANGEROUS_CONTENT":"BLOCK_LOW_AND_ABOVE","unknown":"OFF"}',
    );
    final api = SafetySettings.toApiList(raw);
    expect(api, hasLength(4));
    expect(api.last['threshold'], 'BLOCK_LOW_AND_ABOVE');
    expect(
      api.take(3).map((e) => e['threshold']),
      AppDistribution.direct
          ? ['OFF', 'BLOCK_NONE', 'BLOCK_ONLY_HIGH']
          : everyElement('BLOCK_MEDIUM_AND_ABOVE'),
    );
    expect(SafetySettings.thresholds.contains('OFF'), AppDistribution.direct);
  });
  test('malformed input falls back safely without retaining unknown keys', () {
    for (final raw in [
      null,
      'OFF',
      {'unknown': 'OFF'},
      {SafetySettings.categories.first: 42},
    ]) {
      expect(
        SafetySettings.toApiList(raw).map((e) => e['threshold']),
        everyElement('BLOCK_MEDIUM_AND_ABOVE'),
      );
    }
  });
}
