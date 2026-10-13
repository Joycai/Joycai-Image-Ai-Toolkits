import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/tasks/task_queue_service.dart';
import 'package:joycai_image_ai_toolkits/state/mcp_server_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/in_memory_database.dart';

void main() {
  sqfliteFfiInit();
  late DatabaseService db;
  late TaskQueueService queue;
  late McpServerState state;
  setUp(() async {
    db = await openTestDatabase();
    queue = TaskQueueService(database: db);
    await queue.ready;
    state = McpServerState(queue: queue, database: db);
    await state.load();
  });
  tearDown(() async {
    await state.shutdown();
    state.dispose();
    queue.dispose();
    await closeTestDatabase(db);
  });

  test(
    'disabled by default, validates ports/folders and redacts connection secrets on export',
    () async {
      expect(state.enabled, false);
      expect(state.running, false);
      final token = await db.getSetting('mcp_token');
      expect(token!.length, greaterThanOrEqualTo(40));
      await state.configure(enable: true, portText: '1', folders: '');
      expect(state.errorCode, 'port');
      await state.configure(enable: true, portText: '39287', folders: 'relative-folder');
      expect(state.errorCode, 'folder');
      expect(state.running, false);
      expect(jsonEncode(await db.getAllDataRaw()), isNot(contains(token)));
    },
  );

  test('enable, credential rotation and disable manage a live loopback listener', () async {
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();
    await state.configure(enable: true, portText: '$port', folders: '');
    expect(state.running, true);
    expect(state.errorCode, null);
    final original = state.clientConfiguration;
    final http = HttpClient();
    addTearDown(() => http.close(force: true));
    Future<int> authenticate(String config) async {
      final parsed = jsonDecode(config)['mcpServers']['joycai-images'];
      final request = await http.getUrl(Uri.parse(parsed['url'] as String));
      request.headers.set('Authorization', parsed['headers']['Authorization']);
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode;
    }

    // GET without a session reaches the SDK and fails with 400, not auth 403.
    expect(await authenticate(original), 400);
    await state.rotateToken();
    expect(state.running, true);
    expect(state.clientConfiguration, isNot(original));
    expect(await authenticate(original), 403);
    expect(await authenticate(state.clientConfiguration), 400);
    await state.disable();
    expect(state.running, false);
    expect(await db.getSetting('mcp_enabled'), 'false');
  });

  test(
    'port conflicts are visible; rotate persists a new token and disable ignores missing folders',
    () async {
      final occupied = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(occupied.close);
      await state.configure(enable: true, portText: '${occupied.port}', folders: '');
      expect(state.errorCode, 'bind');
      expect(state.running, false);
      final before = await db.getSetting('mcp_token');
      await state.disable();
      await state.rotateToken();
      expect(await db.getSetting('mcp_token'), isNot(before));
      final folder = await Directory.systemTemp.createTemp('mcp-root-');
      await state.configure(enable: false, portText: '39287', folders: folder.path);
      await folder.delete();
      await state.disable();
      expect(state.errorCode, null);
      expect(await db.getSetting('mcp_enabled'), 'false');
    },
  );
}
