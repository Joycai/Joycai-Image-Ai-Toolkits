import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/generation/generation_preferences.dart';
import 'package:joycai_image_ai_toolkits/services/llm/generation/generation_schema.dart';

void main() {
  test('models, channels, wires and operations never share parameter memory', () {
    String base(int model, int channel, String wire) =>
        GenerationPreferences.base(model: model, channel: channel, protocol: wire);
    final keys = {
      GenerationPreferences.key(
        base(1, 2, 'arkImages'),
        GenerationOperation.textImage,
        'aspectRatio',
      ),
      GenerationPreferences.key(
        base(3, 2, 'arkImages'),
        GenerationOperation.textImage,
        'aspectRatio',
      ),
      GenerationPreferences.key(
        base(1, 4, 'arkImages'),
        GenerationOperation.textImage,
        'aspectRatio',
      ),
      GenerationPreferences.key(
        base(1, 2, 'openaiImages'),
        GenerationOperation.textImage,
        'aspectRatio',
      ),
      GenerationPreferences.key(base(1, 2, 'arkImages'), GenerationOperation.layers, 'aspectRatio'),
    };
    expect(keys, hasLength(5));
  });

  test('new writes preserve legacy seeds and drafts parked in other operations', () {
    final base = GenerationPreferences.base(model: 1, channel: 2, protocol: 'arkImages');
    final generate = GenerationPreferences.key(base, GenerationOperation.textImage, 'outputFormat');
    final transparent = GenerationPreferences.key(
      base,
      GenerationOperation.transparent,
      'outputFormat',
    );
    const legacy = 'seedream.outputFormat';
    const before = {legacy: 'jpeg'};
    expect(GenerationPreferences.read(before, generate, legacy), 'jpeg');
    final after = {...before, generate: 'jpeg', transparent: 'png'};
    expect(GenerationPreferences.read(after, generate, legacy), 'jpeg');
    expect(GenerationPreferences.read(after, transparent, legacy), 'png');
    expect(after[legacy], 'jpeg');
    expect(before, {legacy: 'jpeg'});
    expect(
      GenerationPreferences.key(base, GenerationOperation.layers, 'imageTask'),
      GenerationPreferences.key(base, GenerationOperation.textImage, 'imageTask'),
    );
  });
}
