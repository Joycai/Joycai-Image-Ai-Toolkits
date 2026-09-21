import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/spec_rate.dart';
import 'package:joycai_image_ai_toolkits/models/token_usage.dart';
import 'package:joycai_image_ai_toolkits/services/billing/spec_billing.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

/// A video is billed at submit by the seconds it asked for; once the job is
/// done, the seconds the provider reports it rendered correct that row. A
/// wan `duration: -1` ("let the model decide") asked for none and used to be
/// billed zero seconds.
void main() {
  group('videoDoneEnvelope', () {
    test('carries a reported length', () {
      final done = videoDoneEnvelope('op', 'https://x/v.mp4',
          requiresAuth: false, renderedSeconds: 7);
      expect(done[videoRenderedSecondsKey], 7);
      expect(videoDoneEnvelope('op', 'u', requiresAuth: false,
          renderedSeconds: '5')[videoRenderedSecondsKey], 5);
    });

    test('an absent or zero length is left out', () {
      expect(videoDoneEnvelope('op', 'u', requiresAuth: false)
          .containsKey(videoRenderedSecondsKey), isFalse);
      expect(videoDoneEnvelope('op', 'u', requiresAuth: false, renderedSeconds: 0)
          .containsKey(videoRenderedSecondsKey), isFalse);
    });
  });

  group('settleVideoUsage', () {
    late List<(String, UsageSpecBilling)> updates;

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
      LLMService.usageUpdateOverride = (id, billing) async {
        updates.add((id, billing));
        return 1;
      };
    });

    tearDown(() {
      LLMService.usageUpdateOverride = null;
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
    });

    test('other billing modes are left as recorded', () async {
      LLMService.configResolverOverride = (_) => config('request');
      await LLMService().settleVideoUsage(
        modelIdentifier: 1,
        operationName: 'task-2',
        renderedSeconds: 10,
      );
      expect(updates, isEmpty);
    });
  });
}
