import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/generation/generation_param.dart';
import 'package:joycai_image_ai_toolkits/services/llm/generation/generation_schema.dart';
import 'package:joycai_image_ai_toolkits/services/llm/generation/generation_value.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_capabilities.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

void main() {
  test('semantic numeric types work for new keys independently of the editor', () {
    const count = GenerationParam(
      ParamSpec(
        key: 'seed',
        labelKey: 'seed',
        control: ParamControl.dropdown,
        valueType: ParamValueType.integer,
        defaultValue: '42',
        options: [ParamOption('42')],
      ),
    );
    expect(count.decode('42'), const GenerationValue(GenerationValueKind.integer, 42));
    expect(count.accepts(count.decode('42')), isTrue);
    const weight = GenerationParam(
      ParamSpec(
        key: 'weight',
        labelKey: 'weight',
        control: ParamControl.segmented,
        valueType: ParamValueType.decimal,
        defaultValue: '0.5',
        options: [ParamOption('0.5')],
      ),
    );
    expect(weight.decode('0.5'), const GenerationValue(GenerationValueKind.decimal, 0.5));
    expect(weight.accepts(weight.decode('0.5')), isTrue);
    expect(() => weight.decode('NaN'), throwsFormatException);
  });
  test('every declared profile preserves defaults and types through JSON and legacy encoding', () {
    for (final entry in ModelCapabilities.profiles.entries) {
      final schema = GenerationSchema(
        protocol: null,
        capabilities: entry.value,
        profileId: entry.key,
      );
      final values = schema.readLegacy({});
      for (final param in schema.params) {
        final value = values[param.key]!;
        expect(param.accepts(value), isTrue, reason: '${entry.key}.${param.key}');
        expect(GenerationValue.fromJson(value.toJson()), value);
        expect(schema.legacyOptions(values)[param.key], param.legacy.defaultValue);
      }
    }
  });

  test('video wires sharing a family resolve distinct alias contracts', () {
    for (final (channel, wire) in [
      (Vendors.openAIRest, WireProtocol.openaiVideos),
      (Vendors.xaiApi, WireProtocol.xaiVideos),
      (Vendors.minimax, WireProtocol.minimaxVideo),
    ]) {
      final schema = LLMDispatcher.generationSchemaFor(
        channelType: channel,
        modelId: 'alias',
        tag: 'video',
        wireProtocol: wire.id,
      );
      expect(schema.protocol, wire);
      expect(schema.capabilities, same(ModelCapabilities.forProtocol(wire)));
    }
  });

  test('xAI blocks last frames and mutually exclusive reference input', () {
    final schema = GenerationSchema(
      protocol: WireProtocol.xaiVideos,
      capabilities: ModelCapabilities.forProtocol(WireProtocol.xaiVideos),
      profileId: 'xai',
    );
    final diagnostics = schema.validate(schema.readLegacy({}), const [
      GenerationMedia(GenerationMediaRole.firstFrame, 'first.png'),
      GenerationMedia(GenerationMediaRole.lastFrame, 'last.png'),
      GenerationMedia(GenerationMediaRole.reference, 'ref.png'),
    ]);
    expect(
      diagnostics.map((d) => d.code),
      containsAll(['unsupportedLastFrame', 'conflictingMedia']),
    );
  });

  test('mode switches exclude inactive fields and fix PNG without losing draft', () {
    final schema = GenerationSchema(
      protocol: WireProtocol.arkImages,
      capabilities: ModelCapabilities.forModel('doubao-seedream-5-0-pro-260628'),
      profileId: 'seedream',
    );
    final draft = schema.readLegacy({'aspectRatio': '16:9', 'outputFormat': 'jpeg'});
    expect(schema.effective(draft, GenerationOperation.layers), isNot(contains('aspectRatio')));
    final transparent = schema.effective(draft, GenerationOperation.transparent);
    expect(transparent['outputFormat']?.value, 'png');
    expect(draft['outputFormat']?.value, 'jpeg');
    expect(schema.effective(draft, GenerationOperation.textImage)['aspectRatio']?.value, '16:9');
  });

  test('explicit out-of-range slider values are rejected, not clamped', () {
    final schema = GenerationSchema(
      protocol: WireProtocol.xaiVideos,
      capabilities: ModelCapabilities.forProtocol(WireProtocol.xaiVideos),
      profileId: 'xai',
    );
    expect(
      schema.validate(schema.readLegacy({'seconds': '99'}), []).single.code,
      'invalidParameter',
    );
  });

  test('typed JSON refuses inconsistent numeric and sentinel representations', () {
    expect(
      () => GenerationValue.fromJson({'kind': 'integer', 'value': '5'}),
      throwsFormatException,
    );
    expect(
      () => GenerationValue.fromJson({'kind': 'auto', 'value': 'auto'}),
      throwsFormatException,
    );
  });
}
