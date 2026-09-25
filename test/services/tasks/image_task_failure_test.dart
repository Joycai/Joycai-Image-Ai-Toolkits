import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/tasks/task_queue_service.dart';

void main() {
  group('imageTaskFailure', () {
    test('a saved image is success', () {
      expect(imageTaskFailure(received: 1, unrecognised: 0, reply: ''), isNull);
      expect(imageTaskFailure(received: 2, unrecognised: 1, reply: ''), isNull);
    });

    test('zero results fails and carries what the model said', () {
      final failure = imageTaskFailure(
        received: 0,
        unrecognised: 0,
        reply: '  I cannot draw that.  ',
      );
      expect(failure, 'The model returned no image. Model said: I cannot draw that.');
    });

    test('zero results with no text still fails', () {
      expect(
        imageTaskFailure(received: 0, unrecognised: 0, reply: ''),
        'The model returned no image.',
      );
    });

    test('only unrecognisable bytes fails', () {
      expect(imageTaskFailure(received: 2, unrecognised: 2, reply: ''), contains('None of the 2'));
    });

    test('a long reply is cut', () {
      final failure = imageTaskFailure(received: 0, unrecognised: 0, reply: 'x' * 900)!;
      expect(failure.length, lessThan(600));
      expect(failure, endsWith('…'));
    });
  });
}
