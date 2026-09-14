import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';

/// B5: every generated-image fetch goes through resolveImageRef, which
/// retries a link once, refuses bodies that are not images, and accepts a
/// `data:` URI wherever a relay puts it (standard 13 §6).
void main() {
  final png = Uint8List.fromList(
      [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 1, 2]);
  const noDelay = Duration.zero;

  test('a failed link is retried once and the second answer used', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return calls == 1
          ? http.Response('bad gateway', 502)
          : http.Response.bytes(png, 200);
    });
    final bytes = await resolveImageRef(
        'https://cdn.example/a.png', client, null,
        retryDelay: noDelay);
    expect(bytes, png);
    expect(calls, 2);
  });

  test('an HTML 200 is not an image, even after the retry', () async {
    var calls = 0;
    final logs = <String>[];
    final client = MockClient((_) async {
      calls++;
      return http.Response('<html>link expired</html>', 200,
          headers: {'content-type': 'text/html'});
    });
    final bytes = await resolveImageRef(
        'https://cdn.example/a.png',
        client,
        (m, {level = 'INFO'}) => logs.add('$level $m'),
        retryDelay: noDelay);
    expect(bytes, isNull);
    expect(calls, 2);
    expect(logs.any((l) => l.startsWith('WARN') && l.contains('not an image')),
        isTrue);
  });

  test('a data: URI in a url field is decoded, not fetched', () async {
    final client = MockClient((_) async => fail('must not fetch a data URI'));
    final bytes = await resolveImageRef(
        'data:image/png;base64,${base64Encode(png)}', client, null);
    expect(bytes, png);
  });

  test('inline data that is not an image is refused', () async {
    final client = MockClient((_) async => fail('no fetch'));
    expect(
        await resolveImageRef(base64Encode(utf8.encode('{"error":"nope"}')),
            client, null),
        isNull);
  });

  test('line-wrapped base64 still decodes', () async {
    final client = MockClient((_) async => fail('no fetch'));
    final wrapped = base64Encode(png).replaceAllMapped(
        RegExp(r'.{4}'), (m) => '${m.group(0)}\n');
    expect(await resolveImageRef(wrapped, client, null), png);
  });

  test('a partial result is delivered with a WARN naming the shortfall',
      () async {
    final logs = <String>[];
    final client = MockClient((req) async => req.url.path.endsWith('ok.png')
        ? http.Response.bytes(png, 200)
        : http.Response('gone', 404));
    final images = await resolveImageRefs(
      ['https://cdn.example/ok.png', 'https://cdn.example/gone.png'],
      client,
      (m, {level = 'INFO'}) => logs.add('$level $m'),
      source: 'Test surface',
      retryDelay: noDelay,
    );
    expect(images, hasLength(1));
    expect(
        logs.any((l) =>
            l.startsWith('WARN') && l.contains('only 1 of 2')),
        isTrue);
  });
}
