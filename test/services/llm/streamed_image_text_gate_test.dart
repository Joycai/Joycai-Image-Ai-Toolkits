import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/openai_chat_protocol.dart';

void main() {
  group('StreamedImageTextGate', () {
    test('plain text is shown as it arrives and never repeated', () {
      final gate = StreamedImageTextGate();
      final pieces = List.generate(40, (i) => 'word$i and more text. ');
      final shown = pieces.map(gate.feed).join();
      expect(shown, pieces.join());
      expect(gate.finish(gate.text.trim()), isEmpty);
    });

    test('a short token-like chunk is not swallowed', () {
      final gate = StreamedImageTextGate();
      expect(gate.feed('Hello'), 'Hello');
      expect(gate.feed(' world'), ' world');
    });

    test('text before an inline image is shown once, text after it at the end',
        () {
      final gate = StreamedImageTextGate();
      final b64 = 'A' * 2000;
      var shown = gate.feed('Here is your picture: ');
      shown += gate.feed('data:image/png;base64,$b64');
      shown += gate.feed(' Hope you like it.');
      expect(shown, 'Here is your picture: ');
      // What the extraction leaves: the payload swapped for a marker.
      final rest = gate.finish('Here is your picture: [Image Data] Hope you like it.');
      expect(rest, '[Image Data] Hope you like it.');
      expect(shown + rest, isNot(contains('Here is your picture: Here')));
    });

    test('a data URI split across chunks does not duplicate the prefix', () {
      final gate = StreamedImageTextGate();
      final intro = 'x ' * 300; // > 500 chars shown before the image starts
      var shown = gate.feed(intro);
      shown += gate.feed('data:ima');
      shown += gate.feed('ge/png;base64,${'B' * 1000}');
      final rest = gate.finish('${intro.trim()} [Image Data]');
      expect(shown.startsWith(intro), isTrue);
      expect(rest, isNot(contains(intro.trim())));
    });

    test('a bare base64 reply leaves nothing to show', () {
      final gate = StreamedImageTextGate();
      for (var i = 0; i < 20; i++) {
        gate.feed('QUJD' * 20);
      }
      expect(gate.finish(''), isEmpty);
    });
  });
}
