import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/catalogue/output_cap_scale.dart';

void main() {
  group('OutputCapScale', () {
    test('every stop sits on its own index and reads back exactly', () {
      for (var i = 0; i < OutputCapScale.stops.length; i++) {
        final stop = OutputCapScale.stops[i];
        expect(OutputCapScale.positionOf(stop), i.toDouble());
        expect(OutputCapScale.tokensAt(i.toDouble()), stop);
        expect(OutputCapScale.stopIndexOf(stop), i);
      }
    });

    test('labels are 4k through 128k', () {
      expect(OutputCapScale.stops.map(OutputCapScale.label).toList(), [
        '4k',
        '8k',
        '16k',
        '32k',
        '64k',
        '128k',
      ]);
    });

    test('a typed value between two stops sits in proportion between them', () {
      // 48k is exactly halfway from 32k to 64k.
      expect(OutputCapScale.positionOf(49152), closeTo(3.5, 1e-9));
      expect(OutputCapScale.stopIndexOf(49152), isNull);
    });

    test('values outside the presets rest at the ends', () {
      expect(OutputCapScale.positionOf(1000), 0);
      expect(OutputCapScale.positionOf(400000), OutputCapScale.maxPosition);
    });

    test('a track position rounds to the nearest stop, inside the scale', () {
      expect(OutputCapScale.tokensAt(3.4), 32768);
      expect(OutputCapScale.tokensAt(3.6), 65536);
      expect(OutputCapScale.tokensAt(-2), OutputCapScale.stops.first);
      expect(OutputCapScale.tokensAt(99), OutputCapScale.stops.last);
    });

    test('the field grammar is the context field\'s', () {
      expect(OutputCapScale.parse('64k'), 65536);
      expect(OutputCapScale.parse('65 536'), 65536);
      expect(OutputCapScale.parse(''), isNull);
      expect(OutputCapScale.parse('abc'), isNull);
    });
  });
}
