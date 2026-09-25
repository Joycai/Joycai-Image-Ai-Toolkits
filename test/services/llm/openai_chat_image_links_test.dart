import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/openai_chat_protocol.dart';

/// Image links in a ① chat reply's text used to be fetched with a bare
/// `client.get`: any 200 was kept as a picture (an expired link's HTML page
/// included), no retry, and failures were swallowed without a word. They now
/// go through the shared `resolveImageRef(s)` — validated, retried once,
/// logged.
void main() {
  final png = Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  ]);

  test('a markdown link to an image is kept; one to an HTML page is not', () async {
    final hits = <String, int>{};
    final client = MockClient((req) async {
      hits.update(req.url.path, (n) => n + 1, ifAbsent: () => 1);
      if (req.url.path == '/ok.png') return http.Response.bytes(png, 200);
      return http.Response('<html>expired</html>', 200, headers: {'content-type': 'text/html'});
    });
    final logs = <String>[];

    final result = await OpenAIChatProtocol.extractTextImages(
      'Here: ![a](https://cdn.example.invalid/ok.png) and '
      '![b](https://cdn.example.invalid/gone.png)',
      client,
      imageReply: false,
      logger: (msg, {level = 'INFO'}) => logs.add('$level $msg'),
      retryDelay: Duration.zero,
    );

    expect(result.images, hasLength(1));
    expect(result.images.single, png);
    // The HTML link was retried once, then warned about — never saved.
    expect(hits['/gone.png'], 2);
    expect(logs.where((l) => l.startsWith('WARN') && l.contains('not an image')), isNotEmpty);
    expect(logs.where((l) => l.contains('only 1 of 2')), isNotEmpty);
  });

  test('a reply that is one bare link retries once, then gives up loudly', () async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      return http.Response('nope', 404);
    });
    final logs = <String>[];

    final result = await OpenAIChatProtocol.extractTextImages(
      'https://cdn.example.invalid/picture.png',
      client,
      imageReply: true,
      logger: (msg, {level = 'INFO'}) => logs.add('$level $msg'),
      retryDelay: Duration.zero,
    );

    expect(result.images, isEmpty);
    expect(calls, 2);
    expect(logs.where((l) => l.startsWith('WARN') && l.contains('404')), isNotEmpty);
  });

  test('a bare link to real image bytes becomes the reply', () async {
    final client = MockClient((req) async => http.Response.bytes(png, 200));
    final result = await OpenAIChatProtocol.extractTextImages(
      'https://cdn.example.invalid/picture.png',
      client,
      imageReply: true,
      retryDelay: Duration.zero,
    );
    expect(result.images.single, png);
    expect(result.text, '');
  });
}
