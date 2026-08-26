import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_debug_logger.dart';

/// Pins what the API debug log does and does not hide.
///
/// Both directions matter and they pull against each other: a leaked key is a
/// security bug, and an over-eager mask is a debugging one. The rule used to
/// be `key.contains('token')`, which hid `max_tokens` and every usage counter
/// — the exact numbers the timeout investigation needed, in the exact file
/// written to support it.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory home;

  setUp(() {
    // A data directory of this file's own: `flutter test` runs files
    // concurrently, and the logger prunes the directory it writes into.
    home = Directory.systemTemp.createTempSync('joycai_log');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => home.path,
    );
  });
  tearDown(() {
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  Future<String> write(Map<String, dynamic> request) async {
    final log = await LLMDebugLogger.startLog('m', 'Test', request);
    expect(log, isNotNull, reason: 'the logger must have produced a file');
    return log!.file.readAsStringSync();
  }

  group('masking', () {
    test('credentials are hidden', () async {
      final text = await write({
        'headers': {
          'x-api-key': 'sk-secret-1',
          'Authorization': 'Bearer sk-secret-2',
          'X-Goog-Api-Key': 'sk-secret-3',
        },
        'body': {'password': 'hunter2', 'api_key': 'sk-secret-4'},
      });

      for (final secret in ['sk-secret-1', 'sk-secret-2', 'sk-secret-3', 'sk-secret-4', 'hunter2']) {
        expect(text, isNot(contains(secret)));
      }
      expect(text, contains('***MASKED***'));
    });

    test('token counts and output caps stay readable', () async {
      // The regression this file exists for. Every one of these was masked by
      // the old substring rule.
      final text = await write({
        'body': {
          'max_tokens': 8192,
          'thinking': {'budget_tokens': 4096},
          'usage': {'input_tokens': 161, 'output_tokens': 7131},
        },
      });

      expect(text, contains('8192'));
      expect(text, contains('4096'));
      expect(text, contains('7131'));
    });

    test('a key embedded in a URL is still caught', () async {
      // Key-name masking cannot see this one: the URL lives under `url`.
      final text = await write({
        'url': 'https://host/v1/models?key=AIzaSecret&alt=sse',
      });

      expect(text, isNot(contains('AIzaSecret')));
      expect(text, contains('alt=sse'));
    });
  });

  group('request size', () {
    test('reports the serialized body size, not the truncated one', () async {
      // The line that makes an 8 MB upload visible. The body is truncated for
      // readability further down, so without this the size is unknowable
      // from the file.
      final big = 'A' * 100000;
      final text = await write({
        'body': {'messages': big},
      });

      final expected = utf8.encode(jsonEncode({'messages': big})).length;
      expect(text, contains('Body bytes: $expected'));
      // ...and the body itself is still truncated, which is the whole reason
      // the count has to be taken before the truncation.
      expect(text, contains('chars omitted'));
    });

    test('a bodyless request reports zero rather than failing', () async {
      final text = await write({'url': 'https://host/v1/models'});
      expect(text, contains('Body bytes: 0'));
    });
  });

  group('elapsed', () {
    test('finish records how long the request took', () async {
      final log = await LLMDebugLogger.startLog('m', 'Test', {'body': {}});
      await LLMDebugLogger.appendLine(log, 'Status: 200');
      await LLMDebugLogger.finish(log);

      expect(log!.file.readAsStringSync(), matches(RegExp(r'Elapsed: \d+ ms')));
    });

    test('finish on a log that was never opened is a no-op', () async {
      // startLog returns null when logging is off or the write failed; every
      // call site passes that through without checking.
      await LLMDebugLogger.finish(null);
    });
  });

  group('streamed lines', () {
    test('are buffered and land in order once finished', () async {
      final log = await LLMDebugLogger.startLog('m', 'Test', {'body': {}});
      for (var i = 0; i < 200; i++) {
        await LLMDebugLogger.appendStreamLine(log, 'data: {"i":$i}');
      }
      await LLMDebugLogger.finish(log);

      final text = log!.file.readAsStringSync();
      final lines = text
          .split('\n')
          .where((l) => l.startsWith('data:'))
          .toList();
      expect(lines, hasLength(200));
      expect(lines.first, 'data: {"i":0}');
      expect(lines.last, 'data: {"i":199}');
    });

    test('a stream that never finishes still wrote what overflowed', () async {
      // The trade the buffer makes: a crash mid-stream costs the readable
      // tail, not the whole response.
      final log = await LLMDebugLogger.startLog('m', 'Test', {'body': {}});
      final fat = 'data: ${'x' * 4096}';
      for (var i = 0; i < 40; i++) {
        await LLMDebugLogger.appendStreamLine(log, fat);
      }
      // No finish().

      expect(log!.file.readAsStringSync(), contains('xxxx'));
    });

    test('a failed write keeps the buffer instead of dropping it', () async {
      // The buffer exists so a stream is a handful of writes rather than
      // hundreds. Clearing it on a write that failed would spend that
      // trade-off on losing up to 64 KB of the very log it was bought for.
      final log = await LLMDebugLogger.startLog('m', 'Test', {'body': {}});
      final dir = log!.file.parent;
      final marker = 'data: ${'x' * 70000}';

      dir.deleteSync(recursive: true); // nothing can land while this is gone
      await LLMDebugLogger.appendStreamLine(log, marker);
      dir.createSync(recursive: true); // ...and now it can again

      await LLMDebugLogger.finish(log);
      expect(log.file.readAsStringSync(), contains(marker));
    });

    test('an unbuffered line does not overtake buffered ones', () async {
      // appendLine flushes first, so `Elapsed:` cannot land in front of the
      // body it is supposed to follow.
      final log = await LLMDebugLogger.startLog('m', 'Test', {'body': {}});
      await LLMDebugLogger.appendStreamLine(log, 'first');
      await LLMDebugLogger.appendLine(log, 'second');
      await LLMDebugLogger.finish(log);

      final text = log!.file.readAsStringSync();
      expect(text.indexOf('first'), lessThan(text.indexOf('second')));
      expect(text.indexOf('second'), lessThan(text.indexOf('Elapsed:')));
    });
  });
}
