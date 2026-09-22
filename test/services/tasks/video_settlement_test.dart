import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/output_spec.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';
import 'package:joycai_image_ai_toolkits/services/tasks/task_queue_service.dart';

/// The seam between a video poll's done envelope and the settle of its
/// submit row: the executor settles when the envelope reports the length
/// rendered, the cost, or both — and leaves the row alone otherwise.
void main() {
  Map<String, dynamic> done({Object? renderedSeconds, double? reportedCost}) =>
      videoDoneEnvelope('op', 'https://x/v.mp4',
          requiresAuth: false, renderedSeconds: renderedSeconds, reportedCost: reportedCost);

  test('both facts, as xAI reports them', () {
    final settle = videoSettlementOf(done(renderedSeconds: 1, reportedCost: 0.10))!;
    expect(settle.renderedSeconds, 1);
    expect(settle.reportedCost, 0.10);
  });

  test('either fact alone still settles', () {
    expect(videoSettlementOf(done(renderedSeconds: 8))!.reportedCost, isNull);
    expect(videoSettlementOf(done(renderedSeconds: 8))!.renderedSeconds, 8);
    final costOnly = videoSettlementOf(done(reportedCost: 0.08))!;
    expect(costOnly.renderedSeconds, isNull);
    expect(costOnly.reportedCost, 0.08);
  });

  test('an envelope that says neither leaves the row as the submit priced it', () {
    expect(videoSettlementOf(done()), isNull);
    // Only the executor's two keys count, not the raw upstream spellings.
    expect(videoSettlementOf({...done(), 'duration': 5, 'cost_in_usd_ticks': 800000000}), isNull);
    expect(videoSettlementOf({...done(), videoRenderedSecondsKey: 'soon'}), isNull);
    expect(reportedCostKey, isNot(videoRenderedSecondsKey));
  });
}
