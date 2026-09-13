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

    test('major stops are every other one from 8k', () {
      final majors = [
        for (var i = 0; i < ContextWindowScale.stops.length; i++)
          if (ContextWindowScale.isMajor(i)) ContextWindowScale.label(ContextWindowScale.stops[i]),
      ];
      expect(majors, ['8k', '32k', '96k', '256k', '1M']);
    });

    test('the magnet pulls a position within 3% of the track onto the stop', () {
      // 3% of eight stop units is 0.24.
      expect(ContextWindowScale.magnet(5.2), 5.0);
      expect(ContextWindowScale.magnet(4.8), 5.0);
      expect(ContextWindowScale.magnet(5.3), 5.3);
      expect(ContextWindowScale.magnet(-1), 0.0);
      expect(ContextWindowScale.magnet(9), ContextWindowScale.maxPosition);
    });

    test('parse takes digits, grouped digits and the k / m shorthand', () {
      expect(ContextWindowScale.parse('131072'), 131072);
      expect(ContextWindowScale.parse('200 000'), 200000);
      expect(ContextWindowScale.parse('200,000'), 200000);
      expect(ContextWindowScale.parse('128k'), 131072);
      expect(ContextWindowScale.parse('128K'), 131072);
      expect(ContextWindowScale.parse('1m'), 1048576);
      expect(ContextWindowScale.parse('1.5M'), 1572864);
      expect(ContextWindowScale.parse(''), isNull);
      expect(ContextWindowScale.parse('abc'), isNull);
      expect(ContextWindowScale.parse('1.5'), isNull);
    });

    test('stepping walks the stops, from between two as well', () {
      expect(ContextWindowScale.stepFrom(131072, 1), 262144);
      expect(ContextWindowScale.stepFrom(131072, -1), 98304);
      expect(ContextWindowScale.stepFrom(200000, 1), 262144);
      expect(ContextWindowScale.stepFrom(200000, -1), 131072);
      expect(ContextWindowScale.stepFrom(1048576, 1), isNull);
      expect(ContextWindowScale.stepFrom(8192, -1), isNull);
    });

    test('stepping major-only skips the minor stops', () {
      expect(ContextWindowScale.stepFrom(131072, 1, majorOnly: true), 262144);
      expect(ContextWindowScale.stepFrom(131072, -1, majorOnly: true), 98304);
      expect(ContextWindowScale.stepFrom(98304, 1, majorOnly: true), 262144);
      expect(ContextWindowScale.stepFrom(98304, -1, majorOnly: true), 32768);
      expect(ContextWindowScale.stepFrom(200000, -1, majorOnly: true), 98304);
    });

    test('stepping from off the scale lands on the end stop first', () {
      expect(ContextWindowScale.stepFrom(2000000, -1), 1048576);
      expect(ContextWindowScale.stepFrom(4000, 1), 8192);
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
