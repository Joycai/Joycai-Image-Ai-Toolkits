import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:joycai_image_ai_toolkits/models/llm_channel.dart';
import 'package:joycai_image_ai_toolkits/models/llm_model.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/db/repositories/task_repository.dart';
import 'package:joycai_image_ai_toolkits/services/llm/generation/generation_preferences.dart';
import 'package:joycai_image_ai_toolkits/services/llm/generation/generation_schema.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:joycai_image_ai_toolkits/services/mcp/image_mcp_server.dart';
import 'package:joycai_image_ai_toolkits/services/tasks/generation_submission_service.dart';
import 'package:joycai_image_ai_toolkits/services/tasks/task_queue_service.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/in_memory_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late DatabaseService db;
  late TaskQueueService queue;
  late Directory files;
  late HttpServer provider;
  late ImageMcpServer server;
  late GenerationSubmissionService generation;
  late McpClient client;
  late int modelId;
  final png = img.encodePng(img.Image(width: 3, height: 2));
  var calls = <String>[];
  var bodies = <String>[];
  var upstreamStatus = 200;
  var partialFailure = false;
  Completer<void>? hold;

  Future<McpClient> connect({McpProtocol protocol = McpProtocol.stable}) async {
    final client = McpClient(
      const Implementation(name: 'test-agent', version: '1'),
      options: McpClientOptions(protocol: protocol),
    );
    await client.connect(
      StreamableHttpClientTransport(
        Uri.parse('http://127.0.0.1:${server.port}/mcp'),
        opts: const StreamableHttpClientTransportOptions(
          requestInit: {
            'headers': {'Authorization': 'Bearer test-token'},
          },
        ),
      ),
    );
    return client;
  }

  Future<CallToolResult> call(String name, [Map<String, dynamic> args = const {}]) =>
      client.callTool(CallToolRequest(name: name, arguments: args));

  Future<Map<String, dynamic>> finish(String id) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      final result = (await call('get_generation', {'taskId': id})).structuredContent!;
      if (!['pending', 'processing'].contains(result['status'])) return result;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw StateError('Generation did not reach a terminal state');
  }

  setUp(() async {
    HttpOverrides.global = null;
    db = await openTestDatabase();
    files = await Directory.systemTemp.createTemp('joycai_mcp_test_');
    files = Directory(await files.resolveSymbolicLinks());
    calls = [];
    bodies = [];
    upstreamStatus = 200;
    hold = null;
    partialFailure = false;
    provider = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    provider.listen((request) async {
      if (request.method == 'GET') {
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(png);
        await request.response.close();
        return;
      }

      calls.add(request.uri.path);
      bodies.add(await const Utf8Decoder(allowMalformed: true).bind(request).join());

      if (partialFailure) {
        request.response.headers.contentType = ContentType('text', 'event-stream');
        request.response.write(
          'data: ${jsonEncode({'type': 'image_generation.partial_succeeded', 'image_index': 0, 'url': 'http://127.0.0.1:${provider.port}/output.png'})}\n\n',
        );
        request.response.write(
          'data: ${jsonEncode({
            'error': {'code': 'InternalServiceError', 'message': 'late failure'},
          })}\n\n',
        );
        await request.response.close();
        return;
      }
      await hold?.future;
      request.response.statusCode = upstreamStatus;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(
          upstreamStatus == 200
              ? {
                  'data': [
                    {'b64_json': base64Encode(png)},
                  ],
                }
              : {
                  'error': {
                    'message':
                        'Rejected secret-provider-key https://upstream.test?key=secret '
                        '${base64Encode(utf8.encode('secret-provider-key'))}',
                  },
                },
        ),
      );
      await request.response.close();
    });
    await db.saveSetting('output_directory', files.path);
    await db.saveSetting('workbench_use_stream', 'false');
    final channel = await db.addChannel(
      LLMChannel(
        displayName: 'Fake provider',
        endpoint: 'http://127.0.0.1:${provider.port}/v1',
        apiKey: 'secret-provider-key',
        type: 'openai-api-rest',
      ),
    );
    modelId = await db.addModel(
      LLMModel(modelId: 'gpt-image-1', modelName: 'Image model', tag: 'image', channelId: channel),
    );
    queue = TaskQueueService(database: db);
    await queue.ready;
    generation = GenerationSubmissionService(
      queue: queue,
      database: db,
      allowedRoots: () => [files.path],
      stagingRoot: '${files.path}/staged',
    );
    server = ImageMcpServer(generation: generation);
    await server.start(port: 0, token: 'test-token');
    client = await connect();
  });

  tearDown(() async {
    if (hold != null && !hold!.isCompleted) hold!.complete();
    for (final task in queue.queue) {
      await queue.cancelTask(task.id);
    }
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (queue.runningCount > 0 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await client.close();
    await server.stop();
    queue.dispose();
    await provider.close(force: true);
    // Flush queued SQLite writes before closing the injected connection.
    await (await db.database).rawQuery('SELECT 1');
    await closeTestDatabase(db);
    await files.delete(recursive: true);
  });

  test(
    'real MCP discovery, text generation, polling, image/resource reads and reconnect',
    () async {
      final tools = await client.listTools();
      expect(
        tools.tools.map((t) => t.name),
        containsAll(['generate_image', 'get_generation', 'read_generation_image']),
      );
      final models = await call('list_models');
      expect(jsonEncode(models.structuredContent), isNot(contains('secret-provider-key')));
      final schema = await call('get_model_schema', {'modelId': modelId});
      expect(schema.structuredContent!['parameters'], isNotEmpty);
      final args = {
        'requestId': 'text-1',
        'modelId': modelId,
        'prompt': 'A blue bird',
        'parameters': {
          'quality': {'kind': 'choice', 'value': 'high'},
        },
      };
      final submitted = await call('generate_image', args);
      expect(submitted.isError, false, reason: '${submitted.content}');
      final id = submitted.structuredContent!['taskId'] as String;
      final result = await finish(id);
      expect(result['status'], 'completed', reason: '$result');
      expect(calls, ['/v1/images/generations']);
      expect(jsonDecode(bodies.single)['quality'], 'high');
      final output = (result['outputs'] as List).single as Map;
      expect(await File(output['path'] as String).readAsBytes(), png);
      final read = await call('read_generation_image', {'taskId': id, 'outputId': 0});
      expect(read.content.whereType<ImageContent>().single.mimeType, 'image/jpeg');
      final resource = await client.readResource(ReadResourceRequest(uri: output['uri'] as String));
      expect(base64Decode((resource.contents.single as BlobResourceContents).blob), png);
      await client.close();
      client = await connect(protocol: McpProtocol.legacy);
      final duplicate = await call('generate_image', args);
      expect(duplicate.structuredContent!['taskId'], id);
      expect(calls.length, 1);
      final conflict = await call('generate_image', {...args, 'prompt': 'Different'});
      expect(conflict.structuredContent!['error']['code'], 'requestConflict');
      await queue.removeTask(id);
      final removed = await call('generate_image', args);
      expect(removed.isError, true);
      expect(calls.length, 1, reason: 'Deleting history must not buy another generation');
    },
  );

  test('reference input uses image edits and immutable staged bytes', () async {
    final source = File('${files.path}/reference.png');
    await source.writeAsBytes(png);
    final submitted = await call('generate_image', {
      'requestId': 'edit-1',
      'modelId': modelId,
      'prompt': 'Make the bird red',
      'references': [
        {'path': source.path},
      ],
    });
    expect(submitted.isError, false, reason: '${submitted.content}');
    final id = submitted.structuredContent!['taskId'] as String;
    final task = await generation.task(id);
    expect(task.imagePaths.single, isNot(source.path));
    expect(await File(task.imagePaths.single).readAsBytes(), png);
    await source.delete();
    final result = await finish(id);
    expect(result['status'], 'completed', reason: '$result');
    expect(calls, ['/v1/images/edits']);
    expect(result['operation'], 'editImage');
  });

  test(
    'invalid parameters, video and outside/symlink references fail before provider call',
    () async {
      final invalid = await call('generate_image', {
        'requestId': 'bad-1',
        'modelId': modelId,
        'prompt': 'test',
        'parameters': {
          'invented': {'kind': 'choice', 'value': 'high'},
        },
      });
      expect(invalid.structuredContent!['error']['code'], 'invalidParameter');
      final outside = await File(
        p.join(files.parent.path, 'mcp-outside-${p.basename(files.path)}.png'),
      ).writeAsBytes(png);
      addTearDown(outside.delete);
      await Link('${files.path}/escape.png').create(outside.path);
      final denied = await call('generate_image', {
        'requestId': 'bad-2',
        'modelId': modelId,
        'prompt': 'test',
        'references': [
          {'path': '${files.path}/escape.png'},
        ],
      });
      expect(denied.structuredContent!['error']['code'], 'referenceNotAllowed');
      final original = (await db.getModels()).single;
      final video = await db.addModel(
        LLMModel(
          modelId: 'sora-2',
          modelName: 'Video',
          tag: 'video',
          channelId: original.channelId,
        ),
      );
      final rejected = await call('generate_image', {
        'requestId': 'video',
        'modelId': video,
        'prompt': 'test',
      });
      expect(rejected.structuredContent!['error']['code'], 'unsupportedModel');
      expect(calls, isEmpty);
    },
  );

  test('provider errors are durable and do not disclose credentials', () async {
    upstreamStatus = 401;
    final response = await call('generate_image', {
      'requestId': 'error-1',
      'modelId': modelId,
      'prompt': 'test',
    });
    final id = response.structuredContent!['taskId'] as String;
    final failed = await finish(id);
    expect(failed['status'], 'failed');
    expect(failed['error']['code'], 'providerAuthentication');
    expect(failed['error']['upstreamStatus'], 401);
    expect(jsonEncode(failed), isNot(contains('secret-provider-key')));
    expect((await TaskRepository(db: db).getTask(id))!.error, failed['error']);
  });

  test('provider details stay local rather than exposing echoed credentials', () async {
    upstreamStatus = 400;
    final response = await call('generate_image', {
      'requestId': 'bad-provider',
      'modelId': modelId,
      'prompt': 'draw',
    });
    final result = await finish(response.structuredContent!['taskId'] as String);
    expect(result['error']['details'], isNull);
    expect(result['error']['code'], 'providerError');
    expect(result['error']['upstreamStatus'], 400);
    expect(jsonEncode(result['error']), isNot(contains('secret-provider-key')));
    expect(jsonEncode(result['error']), isNot(contains('https://upstream.test')));
    expect(
      jsonEncode(result['error']),
      isNot(contains(base64Encode(utf8.encode('secret-provider-key')))),
    );
  });

  test('failed processing persistence never reaches the paid provider', () async {
    await (await db.database).execute("""
      CREATE TRIGGER reject_processing BEFORE UPDATE ON tasks
      WHEN NEW.status = 'processing'
      BEGIN SELECT RAISE(FAIL, 'simulated storage failure'); END
    """);
    // saveTask uses INSERT OR REPLACE, so cover that path as well.
    await (await db.database).execute("""
      CREATE TRIGGER reject_processing_insert BEFORE INSERT ON tasks
      WHEN NEW.status = 'processing'
      BEGIN SELECT RAISE(FAIL, 'simulated storage failure'); END
    """);
    final result = await call('generate_image', {
      'requestId': 'storage-failure',
      'modelId': modelId,
      'prompt': 'draw',
    });
    final failed = await finish(result.structuredContent!['taskId'] as String);
    expect(failed['status'], 'failed');
    expect(calls, isEmpty);
  });

  test('preview metadata matches the actual returned image', () async {
    final result = await call('generate_image', {
      'requestId': 'preview-size',
      'modelId': modelId,
      'prompt': 'draw',
    });
    final id = result.structuredContent!['taskId'] as String;
    final done = await finish(id);
    await File(done['outputs'][0]['path'] as String)
        .writeAsBytes(img.encodePng(img.Image(width: 2048, height: 1024)));
    final preview = await call('read_generation_image', {'taskId': id, 'outputId': 0});
    final decoded = img.decodeJpg(
      base64Decode(preview.content.whereType<ImageContent>().single.data),
    )!;
    expect(preview.structuredContent!['width'], decoded.width);
    expect(preview.structuredContent!['height'], decoded.height);
    expect(decoded.width, 1024);
    expect(decoded.height, 512);
  });

  test('concurrent duplicates produce one paid request; cancellation retains handle', () async {
    hold = Completer<void>();
    final args = {'requestId': 'concurrent', 'modelId': modelId, 'prompt': 'test'};
    final results = await Future.wait([call('generate_image', args), call('generate_image', args)]);
    final id = results.first.structuredContent!['taskId'] as String;
    expect(results.last.structuredContent!['taskId'], id);
    final cancelled = await call('cancel_generation', {'taskId': id});
    expect(cancelled.structuredContent!['status'], 'cancelled');
    hold!.complete();
    expect(calls.length, lessThanOrEqualTo(1));
  });

  test('partial streamed output and error remain retrievable after service recreation', () async {
    partialFailure = true;
    await db.saveSetting('workbench_use_stream', 'true');
    final channelId = await db.addChannel(
      LLMChannel(
        displayName: 'Ark',
        endpoint: 'http://127.0.0.1:${provider.port}/api/v3',
        apiKey: 'k',
        type: Vendors.volcengineArk,
      ),
    );
    final seedream = await db.addModel(
      LLMModel(
        modelId: 'doubao-seedream-5.0-lite',
        modelName: 'Seedream',
        tag: 'image',
        channelId: channelId,
      ),
    );
    final response = await call('generate_image', {
      'requestId': 'partial',
      'modelId': seedream,
      'prompt': 'draw',
    });
    final id = response.structuredContent!['taskId'] as String;
    final failed = await finish(id);
    expect(failed['status'], 'failed');
    expect(failed['outputs'], hasLength(1));
    expect(failed['error'], isNotNull);
    final restored = GenerationSubmissionService(
      queue: queue,
      database: db,
      allowedRoots: () => [],
    );
    final result = await restored.status(id);
    expect(result['outputs'], failed['outputs']);
    expect(result['error'], failed['error']);
    expect((await call('read_generation_image', {'taskId': id, 'outputId': 0})).isError, false);
  });

  test('saved defaults are snapshotted and overrides do not change preferences', () async {
    final model = (await db.getModels()).single;
    final schema = await generation.modelSchema(modelId);
    expect(schema['operations'], contains('reference/edit'));
    // Read the resolved wire from the accepted task, then park a preference under that scope.
    final first = await generation.submit({
      'requestId': 'defaults-first',
      'modelId': modelId,
      'prompt': 'draw',
    });
    await finish(first['taskId'] as String);
    final storedTask = await generation.task(first['taskId'] as String);
    final request = storedTask.parameters['generation'] as Map;
    final actualBase = GenerationPreferences.base(
      model: modelId,
      channel: model.channelId,
      protocol: request['protocolId'] as String?,
    );
    final saved = jsonEncode({
      GenerationPreferences.key(actualBase, GenerationOperation.textImage, 'quality'): 'high',
    });
    await db.saveSetting('workbench_image_params', saved);
    final next = await generation.submit({
      'requestId': 'defaults-saved',
      'modelId': modelId,
      'prompt': 'draw',
      'defaults': 'saved',
    });
    expect(next['parameters']['quality'], {'kind': 'choice', 'value': 'high'});
    await finish(next['taskId'] as String);
    expect(await db.getSetting('workbench_image_params'), saved);
  });

  test('empty credentials cannot start a listener', () async {
    final other = ImageMcpServer(generation: generation);
    await expectLater(other.start(port: 0, token: ''), throwsArgumentError);
    expect(other.port, isNull);
  });

  test('HTTP rejects missing authentication, browser origins and oversized bodies', () async {
    final http = HttpClient();
    addTearDown(() => http.close(force: true));
    final uri = Uri.parse('http://127.0.0.1:${server.port}/mcp');
    final unauth = await http.postUrl(uri);
    unauth.write('{}');
    expect((await unauth.close()).statusCode, 403);
    final oversized = await http.postUrl(uri);
    oversized.headers.set('Authorization', 'Bearer test-token');
    oversized.contentLength = 1024 * 1024 + 1;
    oversized.add(List.filled(1024 * 1024 + 1, 32));
    expect((await oversized.close()).statusCode, 403);
    final wrongHost = await http.postUrl(uri);
    wrongHost.headers.set('Authorization', 'Bearer test-token');
    wrongHost.headers.set('Host', 'attacker.invalid');
    wrongHost.write('{}');
    expect((await wrongHost.close()).statusCode, 403);
    final origin = await http.postUrl(uri);
    origin.headers.set('Authorization', 'Bearer test-token');
    origin.headers.set('Origin', 'https://attacker.invalid');
    origin.write('{}');
    expect((await origin.close()).statusCode, 403);
  });
}
