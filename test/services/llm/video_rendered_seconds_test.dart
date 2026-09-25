import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/spec_rate.dart';
import 'package:joycai_image_ai_toolkits/models/token_usage.dart';
import 'package:joycai_image_ai_toolkits/services/billing/spec_billing.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/output_spec.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

/// A video is billed at submit by the seconds it asked for; once the job is
/// done, the seconds the provider reports it rendered correct that row. A
/// wan `duration: -1` ("let the model decide") asked for none and used to be
/// billed zero seconds. Where the terminal poll also says what the job cost
/// (xAI), that figure lands on the row too, under every billing mode.
void main() {
  group('videoDoneEnvelope', () {
    test('carries a reported length', () {
      final done = videoDoneEnvelope(
        'op',
        'https://x/v.mp4',
        requiresAuth: false,
        renderedSeconds: 7,
      );
      expect(done[videoRenderedSecondsKey], 7);
      expect(
        videoDoneEnvelope(
          'op',
          'u',
          requiresAuth: false,
          renderedSeconds: '5',
        )[videoRenderedSecondsKey],
        5,
      );
    });

    test('an absent or zero length is left out', () {
      expect(
        videoDoneEnvelope('op', 'u', requiresAuth: false).containsKey(videoRenderedSecondsKey),
        isFalse,
      );
      expect(
        videoDoneEnvelope(
          'op',
          'u',
          requiresAuth: false,
          renderedSeconds: 0,
        ).containsKey(videoRenderedSecondsKey),
        isFalse,
      );
    });

    test('carries a reported cost under the images protocols\' key', () {
      final done = videoDoneEnvelope('op', 'u', requiresAuth: false, reportedCost: 0.09);
      expect(reportedCostOf(done), 0.09);
      expect(
        videoDoneEnvelope('op', 'u', requiresAuth: false).containsKey(reportedCostKey),
        isFalse,
      );
      expect(
        videoDoneEnvelope(
          'op',
          'u',
          requiresAuth: false,
          reportedCost: -1,
        ).containsKey(reportedCostKey),
        isFalse,
      );
      expect(
        reportedCostOf(videoDoneEnvelope('op', 'u', requiresAuth: false, reportedCost: 0)),
        0,
        reason: 'a reported zero is a report',
      );
    });
  });

  group('settleVideoUsage', () {
    late List<(String, UsageSpecBilling)> updates;
    late List<(String, double)> costs;

    LLMModelConfig config(String billingMode) => LLMModelConfig(
      modelId: 'wan3.0-video',
      channelType: Vendors.dashscopeNative,
      endpoint: 'https://dashscope.aliyuncs.com/api/v1',
      apiKey: 'k',
      billingMode: billingMode,
      outputUnit: OutputUnit.second,
      outputRates: const [
        SpecRate(size: '1080p', price: 0.2),
        SpecRate(size: '1080p', seconds: 10, price: 0.15),
      ],
    );

    setUp(() {
      updates = [];
      costs = [];
      LLMService.usageUpdateOverride = (id, billing) async {
        updates.add((id, billing));
        return 1;
      };
      LLMService.reportedCostUpdateOverride = (id, cost) async {
        costs.add((id, cost));
        return 1;
      };
    });

    tearDown(() {
      LLMService.usageUpdateOverride = null;
      LLMService.reportedCostUpdateOverride = null;
      LLMService.configResolverOverride = null;
    });

    test('a spec-billed row is re-priced by the rendered seconds', () async {
      LLMService.configResolverOverride = (_) => config(specBillingMode);
      await LLMService().settleVideoUsage(
        modelIdentifier: 1,
        operationName: 'task-1',
        renderedSeconds: 10,
        options: const {'resolution': '1080P', 'seconds': -1},
      );
      final (id, billing) = updates.single;
      expect(id, LLMService.videoUsageRowId('task-1'));
      expect(billing.units, 10);
      // The duration-keyed tier matches now that the length is known.
      expect(billing.unitPrice, 0.15);
      expect(billing.snapshot!.seconds, 10);
      expect(costs, isEmpty, reason: 'nothing was reported');
    });

    test('other billing modes are left as recorded', () async {
      LLMService.configResolverOverride = (_) => config('request');
      await LLMService().settleVideoUsage(
        modelIdentifier: 1,
        operationName: 'task-2',
        renderedSeconds: 10,
      );
      expect(updates, isEmpty);
      expect(costs, isEmpty);
    });

    test('a reported cost is written under every mode, beside the re-pricing', () async {
      LLMService.configResolverOverride = (_) => config(specBillingMode);
      await LLMService().settleVideoUsage(
        modelIdentifier: 1,
        operationName: 'task-3',
        renderedSeconds: 1,
        reportedCost: 0.10,
        options: const {'resolution': '1080P', 'seconds': 1},
      );
      expect(updates.single.$1, LLMService.videoUsageRowId('task-3'));
      expect(costs.single, (LLMService.videoUsageRowId('task-3'), 0.10));

      updates.clear();
      costs.clear();
      LLMService.configResolverOverride = (_) => config('request');
      await LLMService().settleVideoUsage(
        modelIdentifier: 1,
        operationName: 'task-4',
        reportedCost: 0.10,
      );
      expect(updates, isEmpty, reason: 'a request-billed row has no seconds to re-price');
      expect(costs.single, (LLMService.videoUsageRowId('task-4'), 0.10));
    });

    test('a failing re-pricing does not lose the reported cost, nor the reverse', () async {
      LLMService.configResolverOverride = (_) => config(specBillingMode);
      LLMService.usageUpdateOverride = (_, _) async => throw StateError('db locked');
      await LLMService().settleVideoUsage(
        modelIdentifier: 1,
        operationName: 'task-5',
        renderedSeconds: 1,
        reportedCost: 0.08,
      );
      expect(costs.single.$2, 0.08);

      LLMService.usageUpdateOverride = (id, billing) async {
        updates.add((id, billing));
        return 1;
      };
      LLMService.reportedCostUpdateOverride = (_, _) async => throw StateError('db locked');
      await LLMService().settleVideoUsage(
        modelIdentifier: 1,
        operationName: 'task-6',
        renderedSeconds: 1,
        reportedCost: 0.08,
      );
      expect(updates.single.$1, LLMService.videoUsageRowId('task-6'));
    });
  });
}
