import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/spec_rate.dart';
import 'package:joycai_image_ai_toolkits/models/token_usage.dart';
import 'package:joycai_image_ai_toolkits/services/billing/spec_billing.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/output_spec.dart';

/// The provider's own figure for a request's cost reaches the usage row
/// from the neutral metadata key alone, under every billing mode, with the
/// fee group's snapshot still written beside it.
void main() {
  tearDown(() => LLMService.usageSinkOverride = null);

  LLMModelConfig config({String billingMode = 'token'}) => LLMModelConfig(
    modelId: 'grok-imagine-image-2.0',
    channelType: 'xai-api',
    endpoint: 'https://example.invalid/v1',
    apiKey: 'k',
    billingMode: billingMode,
    requestFee: 0.02,
    outputRates: const [SpecRate(size: '1K', quality: 'medium', price: 0.06)],
    inputUnitFee: 0.01,
  );

  Future<TokenUsage> record(
    LLMModelConfig config,
    Map<String, dynamic> metadata, {
    Map<String, dynamic>? options,
    int imageCount = 1,
  }) async {
    final rows = <TokenUsage>[];
    LLMService.usageSinkOverride = (row) async => rows.add(row);
    await LLMService().recordUsageForTest(
      config,
      metadata,
      options: options,
      imageCount: imageCount,
    );
    return rows.single;
  }

  test('a spec-billed row carries the report and keeps its snapshot', () async {
    final row = await record(
      config(billingMode: specBillingMode),
      {reportedCostKey: 0.09, 'cost_in_usd_ticks': 900000000, inputImageCountKey: 1},
      options: {'imageSize': '1k', 'quality': 'medium'},
    );

    expect(row.reportedCost, closeTo(0.09, 1e-12));
    expect(row.cost, closeTo(0.09, 1e-12));
    // The table's side is still on the row: 1 × $0.06 + 1 × $0.01.
    expect(row.spec!.unitPrice, 0.06);
    expect(row.spec!.inputImages, 1);
    expect(row.snapshotCost, closeTo(0.07, 1e-12));
    expect(row.specLabel, '1K · medium');
  });

  test('a token-billed and a request-billed group take the report too', () async {
    final token = await record(config(), {reportedCostKey: 0.04});
    final request = await record(config(billingMode: 'request'), {reportedCostKey: 0.04});

    expect(token.reportedCost, 0.04);
    expect(token.cost, closeTo(0.04, 1e-12));
    expect(request.reportedCost, 0.04);
    expect(request.cost, closeTo(0.04, 1e-12));
    expect(request.snapshotCost, closeTo(0.02, 1e-12));
  });

  test('the vendor field alone is not read — only the neutral key', () async {
    final row = await record(config(billingMode: 'request'), {'cost_in_usd_ticks': 400000000});

    expect(row.reportedCost, isNull);
    expect(row.cost, closeTo(0.02, 1e-12));
  });

  test('no key, no report: the row prices off its snapshot as before', () async {
    final row = await record(
      config(billingMode: specBillingMode),
      const {'operation': 'submit'},
      options: {'imageSize': '1k', 'quality': 'medium'},
    );

    expect(row.reportedCost, isNull);
    expect(row.unmatched, isFalse);
    expect(row.cost, closeTo(0.06, 1e-12));
  });
}
