import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/dashscope_files.dart';

void main() {
  final file = File('test/support/reference_media/three_seconds.mp4');
  late Map<String, Object> content;
  setUp(() async {
    final bytes = await file.readAsBytes();
    content = {'file_id': 'existing', 'size': bytes.length, 'md5': md5.convert(bytes).toString()};
  });
  http.Response data(Object data) => http.Response(jsonEncode({'data': data}), 200);
  Future<String> upload(
    http.Client client, {
    String key = 'upload-key',
    String base = 'https://upload.test/api/v1',
    void Function()? cancelled,
    Map<String, dynamic>? options,
  }) => uploadDashScopeFile(
    client: client,
    base: base,
    apiKey: key,
    file: file,
    mime: 'video/mp4',
    checkCancelled: cancelled ?? () {},
    options: options,
  );

  test('paginates by returned count, matches content not name, refreshes signed URL', () async {
    var refresh = 0;
    final client = MockClient((r) async {
      expect(r.headers['Authorization'], 'Bearer upload-key');
      expect(r.method, 'GET');
      if (r.url.path.endsWith('/existing')) {
        refresh++;
        return data({...content, 'url': 'https://media.test/video?signature=$refresh'});
      }
      final page = r.url.queryParameters['page_no'];
      expect(r.url.queryParameters['page_size'], '100');
      return data({
        'total': 2,
        'files': page == '1'
            ? [
                {...content, 'file_id': 'wrong', 'name': file.path, 'md5': 'wrong'},
              ]
            : [
                {...content, 'name': 'renamed.mp4'},
              ],
      });
    });
    expect(await upload(client), endsWith('signature=1'));
    expect(await upload(client), endsWith('signature=2'));
  });

  test('supports actual Base64 MD5 responses as well as documented hex MD5', () async {
    final digest = md5.convert(await file.readAsBytes());
    for (final remote in [base64Encode(digest.bytes), digest.toString().toUpperCase()]) {
      final client = MockClient((r) async {
        expect(r.method, 'GET');
        final entry = {...content, 'md5': remote};
        if (r.url.path.endsWith('/existing')) {
          return data({...entry, 'url': 'https://media.test/video'});
        }
        return data({
          'total': 1,
          'files': [entry],
        });
      });
      expect(await upload(client), 'https://media.test/video');
    }
  });

  test('deleted or changed candidates are skipped; new upload is verified', () async {
    var posts = 0;
    final client = MockClient((r) async {
      if (r.method == 'POST') {
        posts++;
        expect(r.followRedirects, false);
        expect(r.headers['Authorization'], 'Bearer upload-key');
        expect(latin1.decode(r.bodyBytes), contains('name="files"'));
        expect(latin1.decode(r.bodyBytes), contains('file-extract'));
        return data({
          'uploaded_files': [
            {'file_id': 'new'},
          ],
          'failed_uploads': [],
        });
      }
      if (r.url.path.endsWith('/gone')) return http.Response('', 404);
      if (r.url.path.endsWith('/changed')) return data({...content, 'md5': 'changed'});
      if (r.url.path.endsWith('/new')) {
        return data({...content, 'url': 'http://media.test/new?signed=1'});
      }
      return data({
        'total': 2,
        'files': [
          {...content, 'file_id': 'gone'},
          {...content, 'file_id': 'changed'},
        ],
      });
    });
    var paid = 0;
    expect(
      await upload(client, options: {llmBodySentKey: () => paid++}),
      startsWith('http://media.test/'),
    );
    expect(posts, 1);
    expect(paid, 0);
  });

  test('same-scope concurrent callers query after first upload, with fresh metadata', () async {
    var posts = 0;
    var listed = 0;
    var stored = false;
    final client = MockClient((r) async {
      if (r.method == 'POST') {
        posts++;
        await Future<void>.delayed(Duration.zero);
        stored = true;
        return data({
          'uploaded_files': [
            {'file_id': 'existing'},
          ],
        });
      }
      if (r.url.path.endsWith('/existing')) {
        return data({...content, 'url': 'https://media.test/video'});
      }
      listed++;
      return data({
        'total': stored ? 1 : 0,
        'files': stored ? [content] : [],
      });
    });
    expect(await Future.wait([upload(client), upload(client)]), hasLength(2));
    expect(posts, 1);
    expect(listed, 2);
  });

  test('credentials and endpoints remain isolated with no cached URLs', () async {
    final scopes = <String>{};
    final client = MockClient((r) async {
      scopes.add('${r.url.host}/${r.headers['Authorization']}');
      if (r.url.path.endsWith('/existing')) {
        return data({...content, 'url': 'https://media.test/video'});
      }
      return data({
        'total': 1,
        'files': [content],
      });
    });
    await upload(client);
    await upload(client, key: 'another-key');
    await upload(client, base: 'https://another.test/api/v1');
    expect(scopes, hasLength(3));
  });

  test('failure never falls back to upload and never echoes sensitive body', () async {
    for (final response in [
      http.Response('secret signed-url', 401),
      http.Response('{"code":"Error","message":"secret"}', 200),
      data({'total': 1, 'files': []}),
      data({'total': 0, 'files': 'bad'}),
    ]) {
      var calls = 0;
      final client = MockClient((r) async {
        calls++;
        return response;
      });
      await expectLater(
        upload(client),
        throwsA(
          isA<LLMApiException>().having((e) => e.toString(), 'redacted', isNot(contains('secret'))),
        ),
      );
      expect(calls, 1);
    }
  });

  test('rejects unsafe URLs, upload failures and mismatched uploaded bytes', () async {
    for (final result in [
      {
        'uploaded_files': [],
        'failed_uploads': [
          {'message': 'secret'},
        ],
      },
      {
        'uploaded_files': [
          {'file_id': 'existing'},
        ],
      },
    ]) {
      final client = MockClient((r) async {
        if (r.method == 'POST') return data(result);
        if (r.url.path.endsWith('/existing')) return data({...content, 'url': 'file:///secret'});
        return data({'total': 0, 'files': []});
      });
      await expectLater(upload(client), throwsA(isA<LLMApiException>()));
    }
    final client = MockClient((r) async {
      if (r.method == 'POST') {
        return data({
          'uploaded_files': [
            {'file_id': 'existing'},
          ],
        });
      }
      if (r.url.path.endsWith('/existing')) {
        return data({...content, 'md5': 'mismatch', 'url': 'https://media.test/video'});
      }
      return data({'total': 0, 'files': []});
    });
    await expectLater(upload(client), throwsA(isA<LLMApiException>()));
  });

  test('retries rate-limited GETs only, bounded and honoring Retry-After', () async {
    var calls = 0;
    final client = MockClient((r) async {
      expect(r.method, 'GET');
      calls++;
      if (calls <= 2) return http.Response('', 429, headers: {'retry-after': '0'});
      if (r.url.path.endsWith('/existing')) {
        return data({...content, 'url': 'https://media.test/video'});
      }
      return data({
        'total': 1,
        'files': [content],
      });
    });
    expect(await upload(client), 'https://media.test/video');
    expect(calls, 4);
    var limited = 0;
    await expectLater(
      upload(
        MockClient((r) async {
          limited++;
          return http.Response('', 429, headers: {'retry-after': '0'});
        }),
      ),
      throwsA(isA<LLMApiException>()),
    );
    expect(limited, 3);
  });

  test('rate-limit wait respects cancellation; uploads are never automatically retried', () async {
    var cancelled = false;
    var gets = 0;
    await expectLater(
      upload(
        MockClient((r) async {
          gets++;
          cancelled = true;
          return http.Response('', 429, headers: {'retry-after': '2'});
        }),
        cancelled: () {
          if (cancelled) throw const LLMCancelled();
        },
      ),
      throwsA(isA<LLMCancelled>()),
    );
    expect(gets, 1);
    var posts = 0;
    await expectLater(
      upload(
        MockClient((r) async {
          if (r.method == 'POST') {
            posts++;
            return http.Response('sensitive response', 429);
          }
          return data({'total': 0, 'files': []});
        }),
      ),
      throwsA(isA<LLMApiException>()),
    );
    expect(posts, 1);
  });

  test('cancellation prevents networking and releases turn for next request', () async {
    var calls = 0;
    final client = MockClient((r) async {
      calls++;
      if (r.url.path.endsWith('/existing')) {
        return data({...content, 'url': 'https://media.test/video'});
      }
      return data({
        'total': 1,
        'files': [content],
      });
    });
    await expectLater(
      upload(client, cancelled: () => throw const LLMCancelled()),
      throwsA(isA<LLMCancelled>()),
    );
    expect(calls, 0);
    await upload(client);
    expect(calls, 2);
  });
}
