import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_service.dart';

/// The service's execution log is a listener list, not one assignable field
/// (pitfalls 11 §H72, errors 06 §4.2): a second subscriber that assigned the
/// old `onLogAdded` silently replaced the app's console sink.
void main() {
  test('two listeners both receive every line, with level and context', () {
    final service = LLMService();
    final a = <String>[];
    final b = <String>[];
    final la = service.addLogListener(
      (msg, {level = 'INFO', contextId}) => a.add('$level|$contextId|$msg'),
    );
    final lb = service.addLogListener(
      (msg, {level = 'INFO', contextId}) => b.add('$level|$contextId|$msg'),
    );
    addTearDown(() {
      service.removeLogListener(la);
      service.removeLogListener(lb);
    });

    service.emitLogForTest('hello', level: 'WARN', contextId: 'task-1');

    expect(a, ['WARN|task-1|hello']);
    expect(b, ['WARN|task-1|hello']);
  });

  test('a removed listener hears nothing more; the other still does', () {
    final service = LLMService();
    final a = <String>[];
    final b = <String>[];
    final la = service.addLogListener((msg, {level = 'INFO', contextId}) => a.add(msg));
    final lb = service.addLogListener((msg, {level = 'INFO', contextId}) => b.add(msg));
    addTearDown(() => service.removeLogListener(lb));

    service.emitLogForTest('one');
    service.removeLogListener(la);
    service.emitLogForTest('two');

    expect(a, ['one']);
    expect(b, ['one', 'two']);
  });

  test('a throwing listener does not starve the ones after it', () {
    final service = LLMService();
    final heard = <String>[];
    final bad = service.addLogListener(
      (msg, {level = 'INFO', contextId}) => throw StateError('boom'),
    );
    final good = service.addLogListener((msg, {level = 'INFO', contextId}) => heard.add(msg));
    addTearDown(() {
      service.removeLogListener(bad);
      service.removeLogListener(good);
    });

    expect(() => service.emitLogForTest('still delivered'), returnsNormally);
    expect(heard, ['still delivered']);
  });
}
