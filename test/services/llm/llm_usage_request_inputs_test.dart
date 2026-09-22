import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/token_usage.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/output_spec.dart';

/// A request-billed group charges the reference images a request sent
/// (`D2e`): the row's input three are written from the neutral count key,
/// its output four stay empty, and a group that charges no inputs — or a
/// request that sent none — leaves the row exactly as it always was.
void main() {
  tearDown(() => LLMService.usageSinkOverride = null);

  LLMModelConfig config({double inputUnitFee = 0.01, int inputFreeUnits = 0}) =>
      LLMModelConfig(
        modelId: 'grok-imagine-video-1.5',
        channelType: 'openai-api',
        endpoint: 'https://relay.invalid/v1',
        apiKey: 'k',
        billingMode: 'request',
        requestFee: 0.08,
        inputUnitFee: inputUnitFee,
        inputFreeUnits: inputFreeUnits,
      );

  Future<TokenUsage> record(LLMModelConfig config, Map<String, dynamic> metadata) async {
    final rows = <TokenUsage>[];
    LLMService.usageSinkOverride = (row) async => rows.add(row);
    await LLMService().recordUsageForTest(config, metadata);
    return rows.single;
  }

  test('the images sent are billed beside the request price', () async {
    final row = await record(config(inputFreeUnits: 1), const {inputImageCountKey: 3});

    expect(row.billing, UsageBilling.request);
    expect(row.spec!.inputImages, 3);
    expect(row.spec!.inputUnits, 2);
    expect(row.spec!.inputUnitPrice, 0.01);
    expect(row.spec!.unit, isNull, reason: 'no output side on a request-billed row');
    expect(row.spec!.units, 0);
    expect(row.costParts.request, closeTo(0.08, 1e-12));
    expect(row.costParts.specInput, closeTo(0.02, 1e-12));
    expect(row.cost, closeTo(0.10, 1e-12));
    // What the row inserts: the input three set, the output four empty.
    final map = row.toMap();
    expect(map['input_images'], 3);
    expect(map['input_units'], 2.0);
    expect(map['output_units'], anyOf(isNull, 0.0));
    expect(map['output_unit'], isNull);
  });

  test('a request that sent none, or a group that charges none, writes nothing', () async {
    final none = await record(config(), const {});
    final free = await record(config(inputUnitFee: 0), const {inputImageCountKey: 3});

    expect(none.spec, isNull);
    expect(free.spec, isNull);
    expect(none.cost, closeTo(0.08, 1e-12));
    expect(free.cost, closeTo(0.08, 1e-12));
  });

  test('requestInputBilling is null under the other two modes', () {
    for (final mode in ['token', 'spec']) {
      final c = LLMModelConfig(
        modelId: 'm',
        channelType: 'openai-api',
        endpoint: 'https://x',
        apiKey: 'k',
        billingMode: mode,
        inputUnitFee: 0.01,
      );
      expect(LLMService.requestInputBilling(c, const {inputImageCountKey: 2}), isNull, reason: mode);
    }
  });
}
