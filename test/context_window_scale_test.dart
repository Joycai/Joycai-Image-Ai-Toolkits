import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/context_window_scale.dart';

void main() {
  group('ContextWindowScale', () {
    test('every stop sits on its own index and reads back exactly', () {
      for (var i = 0; i < ContextWindowScale.stops.length; i++) {
        final stop = ContextWindowScale.stops[i];
        expect(ContextWindowScale.positionOf(stop), i.toDouble());
        expect(ContextWindowScale.tokensAt(i.toDouble()), stop);
      }
    });

    test('labels are 8k through 512k, then 1M', () {
      expect(ContextWindowScale.stops.map(ContextWindowScale.label).toList(),
          ['8k', '16k', '32k', '64k', '96k', '128k', '256k', '512k', '1M']);
    });

    test('a typed value between two stops sits in proportion between them', () {
      // 200 000 is 52.6% of the way from 128k (131 072) to 256k (262 144).
      final p = ContextWindowScale.positionOf(200000);
      expect(p, closeTo(5 + (200000 - 131072) / 131072, 1e-9));
      expect(p, greaterThan(5));
      expect(p, lessThan(6));
    });

    test('values outside the presets rest at the ends', () {
      expect(ContextWindowScale.positionOf(4000), 0);
      expect(ContextWindowScale.positionOf(2000000), ContextWindowScale.maxPosition);
    });

    test('dragging lands on whole multiples of 1024 inside the stops', () {
      for (var p = 0.0; p <= ContextWindowScale.maxPosition; p += 0.037) {
        final tokens = ContextWindowScale.tokensAt(p);
        expect(tokens % ContextWindowScale.step, 0, reason: 'at $p');
        expect(tokens, inInclusiveRange(ContextWindowScale.stops.first, ContextWindowScale.stops.last));
      }
      expect(ContextWindowScale.tokensAt(-3), ContextWindowScale.stops.first);
      expect(ContextWindowScale.tokensAt(99), ContextWindowScale.stops.last);
    });

    test('a multiple of 1024 survives the trip through the track', () {
      for (final tokens in [9216, 40960, 100352, 200704, 700416, 1047552]) {
        expect(ContextWindowScale.tokensAt(ContextWindowScale.positionOf(tokens)), tokens);
      }
    });

    test('the value only ever grows as the thumb moves right', () {
      var last = 0;
      for (var p = 0.0; p <= ContextWindowScale.maxPosition; p += 0.01) {
        final tokens = ContextWindowScale.tokensAt(p);
        expect(tokens, greaterThanOrEqualTo(last));
        last = tokens;
      }
    });
  });
}
