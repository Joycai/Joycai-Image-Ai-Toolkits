import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/app_paths.dart';

class LLMDebugLogger {
  static Future<String> _getLogDir() async {
    final dataDir = await AppPaths.getDataDirectory();
    final logDir = Directory(p.join(dataDir, 'api_logs'));
    if (!logDir.existsSync()) {
      logDir.createSync(recursive: true);
    }
    return logDir.path;
  }

  static Future<File?> startLog(String modelId, String type, Map<String, dynamic> request) async {
    try {
      final dirPath = await _getLogDir();
      
      // Auto-cleanup: remove logs older than 7 days or keep only latest 50
      _cleanupOldLogs(dirPath);

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'log_${timestamp}_${modelId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}.txt';
      final file = File(p.join(dirPath, fileName));

      final buffer = StringBuffer();
      buffer.writeln('=== API DEBUG LOG ===');
      buffer.writeln('Timestamp: ${DateTime.now().toIso8601String()}');
      buffer.writeln('Model: $modelId');
      buffer.writeln('Type: $type');
      buffer.writeln('--- REQUEST ---');
      
      // Mask API Key if present in headers or body
      final sanitizedRequest = _sanitize(request);
      buffer.writeln(sanitizedRequest);
      buffer.writeln('--- RESPONSE ---');
      
      await file.writeAsString(buffer.toString());
      return file;
    } catch (_) {
      return null;
    }
  }

  static Future<void> appendLine(File? file, String line) async {
    if (file == null) return;
    try {
      await file.writeAsString('$line\n', mode: FileMode.append);
    } catch (_) {}
  }

  static void _cleanupOldLogs(String dirPath) {
    try {
      final dir = Directory(dirPath);
      final List<FileSystemEntity> files = dir.listSync();
      if (files.length <= 50) return;

      // Sort by creation/modification date
      files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));

      // Remove files beyond the 50th or older than 7 days
      final now = DateTime.now();
      for (int i = 0; i < files.length; i++) {
        final f = files[i];
        final stat = f.statSync();
        final age = now.difference(stat.modified).inDays;
        
        if (i >= 50 || age > 7) {
          f.deleteSync();
        }
      }
    } catch (_) {}
  }

  static dynamic _sanitize(dynamic obj) {
    if (obj is Map) {
      return obj.map((k, v) {
        final keyStr = k.toString().toLowerCase();
        // Mask common sensitive header and payload keys
        if (keyStr.contains('key') || 
            keyStr.contains('api-key') || 
            keyStr.contains('authorization') ||
            keyStr.contains('token')) {
          return MapEntry(k, '***MASKED***');
        }
        return MapEntry(k, _sanitize(v));
      });
    } else if (obj is List) {
      return obj.map((e) => _sanitize(e)).toList();
    }
    return obj;
  }

  static Future<void> openLogFolder() async {
    final dir = await _getLogDir();
    if (Platform.isWindows) {
      await Process.run('explorer.exe', [dir]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [dir]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [dir]);
    }
  }
}