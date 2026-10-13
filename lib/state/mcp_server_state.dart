import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../services/db/database_service.dart';
import '../services/mcp/image_mcp_server.dart';
import '../services/tasks/generation_submission_service.dart';
import '../services/tasks/task_queue_service.dart';

/// Owns desktop server lifecycle and persisted settings; UI only edits a draft.
class McpServerState extends ChangeNotifier {
  McpServerState({required TaskQueueService queue, DatabaseService? database})
    : _db = database ?? DatabaseService() {
    _server = ImageMcpServer(
      generation: GenerationSubmissionService(
        queue: queue,
        database: _db,
        allowedRoots: () => roots,
      ),
    );
  }
  final DatabaseService _db;
  late final ImageMcpServer _server;
  bool enabled = false;
  bool busy = false;
  bool loaded = false;
  int port = 39287;
  List<String> roots = const [];
  String? errorCode;
  String _token = '';
  bool get supported => Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  bool get running => _server.port != null;
  String get endpoint => 'http://127.0.0.1:${_server.port ?? port}/mcp';

  Future<void> load() async {
    if (busy) return;
    busy = true;
    try {
      await _server.stop();
      enabled = await _db.getSetting('mcp_enabled') == 'true';
      port = int.tryParse(await _db.getSetting('mcp_port') ?? '') ?? 39287;
      if (port < 1024 || port > 65535) port = 39287;
      _token = await _db.getSetting('mcp_token') ?? '';
      if (_token.isEmpty) {
        _token = _newToken();
        await _db.saveSetting('mcp_token', _token);
      }
      try {
        roots = List<String>.unmodifiable(
          jsonDecode(await _db.getSetting('mcp_roots') ?? '[]') as List,
        );
      } catch (_) {
        roots = const [];
      }
      errorCode = null;
      if (enabled && supported) await _server.start(port: port, token: _token);
    } on SocketException {
      errorCode = 'bind';
    } catch (_) {
      errorCode = 'settings';
    } finally {
      loaded = true;
      busy = false;
      notifyListeners();
    }
  }

  Future<void> configure({
    required bool enable,
    required String portText,
    required String folders,
  }) async {
    if (busy || !supported) return;
    final parsed = int.tryParse(portText);
    if (parsed == null || parsed < 1024 || parsed > 65535) {
      errorCode = 'port';
      notifyListeners();
      return;
    }
    busy = true;
    errorCode = null;
    notifyListeners();
    try {
      final canonical = <String>[];
      for (final root in folders.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty)) {
        if (!Directory(root).isAbsolute || !await Directory(root).exists()) {
          errorCode = 'folder';
          return;
        }
        canonical.add(await Directory(root).resolveSymbolicLinks());
      }
      await _server.stop();
      port = parsed;
      roots = List.unmodifiable(canonical.toSet());
      enabled = enable;
      await _db.saveSetting('mcp_port', '$port');
      await _db.saveSetting('mcp_roots', jsonEncode(roots));
      await _db.saveSetting('mcp_enabled', '$enabled');
      if (enabled) await _server.start(port: port, token: _token);
    } on SocketException {
      errorCode = 'bind';
    } catch (_) {
      errorCode = 'settings';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> disable() async {
    if (busy) return;
    busy = true;
    notifyListeners();
    try {
      // Stopping must work even if a configured folder has disappeared.
      await _server.stop();
      enabled = false;
      await _db.saveSetting('mcp_enabled', 'false');
      errorCode = null;
    } catch (_) {
      errorCode = 'settings';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> rotateToken() async {
    if (busy) return;
    busy = true;
    errorCode = null;
    notifyListeners();
    try {
      await _server.stop();
      _token = _newToken();
      await _db.saveSetting('mcp_token', _token);
      if (enabled && supported) await _server.start(port: port, token: _token);
    } catch (_) {
      errorCode = 'settings';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  String get clientConfiguration => const JsonEncoder.withIndent('  ').convert({
    'mcpServers': {
      'joycai-images': {
        'url': endpoint,
        'headers': {'Authorization': 'Bearer $_token'},
      },
    },
  });

  static String _newToken() {
    final random = Random.secure();
    return base64UrlEncode(List.generate(32, (_) => random.nextInt(256)));
  }

  Future<void> shutdown() => _server.stop();
}
