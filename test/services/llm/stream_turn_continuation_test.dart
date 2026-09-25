import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/token_usage.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// requestStream continues a turn the host paused after a server-side tool
/// run, exactly as request() does: the second leg is asked with the paused
/// assistant message sent back unchanged, and its text streams on after the
/// first leg's.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final home = Directory.systemTemp.createTempSync('joycai_stream_turn');

  late HttpServer server;
  late List<TokenUsage> rows;

  setUp(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => home.path,
    );
    HttpOverrides.global = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    rows = [];
    LLMService.usageSinkOverride = (row) async => rows.add(row);
    LLMService.configResolverOverride = (_) => LLMModelConfig(
      modelId: 'claude-opus-5',
      channelType: Vendors.anthropicRest,
      endpoint: 'http://127.0.0.1:${server.port}/v1',
      apiKey: 'k',
    );
  });

  tearDown(() async {
    LLMService.usageSinkOverride = null;
    LLMService.configResolverOverride = null;
    await server.close(force: true);
    LLMClientPool.disposeAll();
  });

  Future<void> sse(HttpRequest request, List<Map<String, dynamic>> events) async {
    request.response.headers.contentType = ContentType('text', 'event-stream');
    for (final event in events) {
      request.response.write('event: ${event['type']}\ndata: ${jsonEncode(event)}\n\n');
    }
    await request.response.close();
  }

  final pausedLeg = <Map<String, dynamic>>[
    {
      'type': 'message_start',
      'message': {
        'usage': {'input_tokens': 5},
      },
    },
    {
      'type': 'content_block_start',
      'index': 0,
      'content_block': {'type': 'text', 'text': ''},
    },
    {
      'type': 'content_block_delta',
      'index': 0,
      'delta': {'type': 'text_delta', 'text': 'Let me look.'},
    },
    {'type': 'content_block_stop', 'index': 0},
    {
      'type': 'content_block_start',
      'index': 1,
      'content_block': {'type': 'server_tool_use', 'id': 'srv', 'name': 'web_search', 'input': {}},
    },
    {
      'type': 'content_block_delta',
      'index': 1,
      'delta': {'type': 'input_json_delta', 'partial_json': '{"query":"q"}'},
    },
    {'type': 'content_block_stop', 'index': 1},
    {
      'type': 'message_delta',
      'delta': {'stop_reason': 'pause_turn'},
      'usage': {'output_tokens': 7},
    },
    {'type': 'message_stop'},
  ];
  final finalLeg = <Map<String, dynamic>>[
    {
      'type': 'message_start',
      'message': {
        'usage': {'input_tokens': 9},
      },
    },
    {
      'type': 'content_block_start',
      'index': 0,
      'content_block': {'type': 'text', 'text': ''},
    },
    {
      'type': 'content_block_delta',
      'index': 0,
      'delta': {'type': 'text_delta', 'text': 'Found it.'},
    },
    {'type': 'content_block_stop', 'index': 0},
    {
      'type': 'message_delta',
      'delta': {'stop_reason': 'end_turn'},
      'usage': {'output_tokens': 3},
    },
    {'type': 'message_stop'},
  ];

  test('a paused stream is continued and both legs are billed', () async {
    final bodies = <Map<String, dynamic>>[];
    server.listen((request) async {
      bodies.add(jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>);
      await sse(request, bodies.length == 1 ? pausedLeg : finalLeg);
    });

    final text = StringBuffer();
    await for (final chunk in LLMService().requestStream(
      modelIdentifier: 'claude-opus-5',
      messages: [LLMMessage(role: LLMRole.user, content: 'what happened?')],
    )) {
      if (chunk.textPart != null) text.write(chunk.textPart);
    }

    expect(bodies, hasLength(2));
    final replayed = (bodies[1]['messages'] as List).last as Map;
    expect(replayed['role'], 'assistant');
    expect(
      (replayed['content'] as List).map((b) => (b as Map)['type']),
      contains('server_tool_use'),
      reason: 'the paused message goes back unchanged',
    );
    expect(text.toString(), 'Let me look.\n\nFound it.');
    expect(rows, hasLength(2), reason: 'every leg is a billed request');
  });

  test('a finished stream is not continued', () async {
    var requests = 0;
    server.listen((request) async {
      requests++;
      await request.drain<void>();
      await sse(request, finalLeg);
    });

    await LLMService()
        .requestStream(
          modelIdentifier: 'claude-opus-5',
          messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
        )
        .drain<void>();
    expect(requests, 1);
  });
}
