import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/app_paths.dart';

/// One open debug log: the file, plus when the request that owns it started.
///
/// A handle rather than a bare [File] so [LLMDebugLogger.finish] can report
/// how long the request actually took. That number is not a nicety — the
/// timeout investigation this logger exists for could only be run by
/// subtracting the file's `Timestamp:` header from its mtime by hand, and
/// three of the seven requests in that session turned out to have completed
/// *after* the client had already given up on them
/// (docs/plans/2026-08-assistant-timeout.md).
class LLMDebugLog {
  final File file;
  final DateTime startedAt;

  LLMDebugLog(this.file, this.startedAt);

  /// Unwritten [LLMDebugLogger.appendStreamLine] output.
  ///
  /// A streamed answer arrives as hundreds of SSE lines, and writing each one
  /// was an open/write/close of its own — cheap enough when almost nothing
  /// streamed, and squarely on the hot path now that the agent loops do
  /// (docs/plans/2026-08-assistant-timeout.md). Only the stream path buffers:
  /// [LLMDebugLogger.appendLine] still writes through, because several
  /// protocols log a response and never call [LLMDebugLogger.finish], and
  /// buffered output they never flush is output that silently vanishes.
  final StringBuffer pending = StringBuffer();
}

class LLMDebugLogger {
  static Future<String> _getLogDir() async {
    final dataDir = await AppPaths.getDataDirectory();
    final logDir = Directory(p.join(dataDir, 'api_logs'));
    if (!logDir.existsSync()) {
      logDir.createSync(recursive: true);
    }
    return logDir.path;
  }

  static Future<LLMDebugLog?> startLog(
      String modelId, String type, Map<String, dynamic> request) async {
    try {
      final dirPath = await _getLogDir();
      
      // Auto-cleanup: remove logs older than 7 days or keep only latest 50
      _cleanupOldLogs(dirPath);

      final startedAt = DateTime.now();
      final fileName = 'log_${startedAt.millisecondsSinceEpoch}_'
          '${modelId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}.txt';
      final file = File(p.join(dirPath, fileName));

      final buffer = StringBuffer();
      buffer.writeln('=== API DEBUG LOG ===');
      buffer.writeln('Timestamp: ${startedAt.toIso8601String()}');
      buffer.writeln('Model: $modelId');
      buffer.writeln('Type: $type');
      // What actually goes on the wire, before any of it is truncated for
      // readability below. Base64 attachments are invisible in a truncated
      // log, and "this request is 8 MB" is the single most useful line in it
      // — an 8 MB upload to a distant relay is tens of seconds of latency
      // that looks, from the outside, exactly like a slow model.
      buffer.writeln('Body bytes: ${_bodyBytes(request['body'])}');
      buffer.writeln('--- REQUEST ---');

      // Mask API Key if present in headers or body
      final sanitizedRequest = _sanitize(request);
      buffer.writeln(sanitizedRequest);
      buffer.writeln('--- RESPONSE ---');

      await file.writeAsString(buffer.toString());
      return LLMDebugLog(file, startedAt);
    } catch (_) {
      return null;
    }
  }

  /// Serialized size of [body], or `unknown` when it cannot be encoded.
  ///
  /// Runs only behind the API-debug toggle, so the extra encode is paid for
  /// by someone who asked to see exactly this.
  static String _bodyBytes(Object? body) {
    if (body == null) return '0';
    try {
      return utf8.encode(jsonEncode(body)).length.toString();
    } catch (_) {
      return 'unknown';
    }
  }

  static Future<void> appendLine(LLMDebugLog? log, String line) async {
    if (log == null) return;
    try {
      await _flush(log);
      await log.file.writeAsString('$line\n', mode: FileMode.append);
    } catch (_) {}
  }

  /// Buffer size above which [appendStreamLine] writes through.
  ///
  /// Large enough that a whole streamed answer is a handful of writes rather
  /// than hundreds, small enough that a crash mid-stream loses a readable
  /// tail rather than the whole response.
  static const int _flushThresholdChars = 64 * 1024;

  /// [appendLine] for lines arriving one SSE event at a time.
  ///
  /// Buffered, so the caller **must** end with [finish] — every SSE loop does,
  /// in a `finally`.
  static Future<void> appendStreamLine(LLMDebugLog? log, String line) async {
    if (log == null) return;
    log.pending.writeln(line);
    if (log.pending.length >= _flushThresholdChars) {
      await _flush(log);
    }
  }

  static Future<void> _flush(LLMDebugLog log) async {
    if (log.pending.isEmpty) return;
    final text = log.pending.toString();
    log.pending.clear();
    try {
      await log.file.writeAsString(text, mode: FileMode.append);
    } catch (_) {}
  }

  /// Closes [log] with how long the whole request took.
  ///
  /// Worth a line of its own because the interesting case is when it exceeds
  /// the caller's deadline: the response still arrives, is still billed, and
  /// is still written here — long after whoever was waiting for it gave up.
  /// Also flushes whatever [appendStreamLine] has buffered, which is why
  /// every streaming path calls it in a `finally`.
  static Future<void> finish(LLMDebugLog? log) async {
    if (log == null) return;
    final elapsed = DateTime.now().difference(log.startedAt);
    // appendLine flushes first, so the Elapsed line lands after the body
    // rather than in front of it.
    await appendLine(log, 'Elapsed: ${elapsed.inMilliseconds} ms');
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

  /// Credentials embedded inside string values, which key-name masking cannot
  /// catch: Google-style `?key=<API_KEY>` query parameters (the request maps
  /// include the full URL under the innocuous key `url`) and bearer tokens.
  static final RegExp _keyQueryParam = RegExp(r'([?&]key=)[^&\s"]+');
  static final RegExp _bearerToken =
      RegExp(r'(Bearer\s+)[A-Za-z0-9._~+/=-]+');

  /// Any string value longer than this is truncated in the log. Catches
  /// base64 image payloads (MB-sized) protocol-agnostically: the chat
  /// protocols log their request map as-is, and per-protocol "safe payload"
  /// helpers only exist where someone remembered to write one.
  static const int _maxStringChars = 2048;

  /// Header and payload keys whose value is a credential.
  ///
  /// Matched **exactly** (lower-cased), never by substring. The old
  /// `contains('token')` rule masked `max_tokens`, `budget_tokens` and every
  /// usage counter in the file — which are the numbers someone opens this log
  /// to read. `contains('key')` had the same problem waiting for any payload
  /// field named `keywords`.
  static const Set<String> _secretKeys = {
    'key',
    'apikey',
    'api_key',
    'api-key',
    'x-api-key',
    'x-goog-api-key',
    'authorization',
    'proxy-authorization',
    'token',
    'access_token',
    'refresh_token',
    'secret',
    'client_secret',
    'password',
    'passwd',
  };

  static dynamic _sanitize(dynamic obj) {
    if (obj is Map) {
      return obj.map((k, v) {
        if (_secretKeys.contains(k.toString().toLowerCase())) {
          return MapEntry(k, '***MASKED***');
        }
        return MapEntry(k, _sanitize(v));
      });
    } else if (obj is List) {
      return obj.map((e) => _sanitize(e)).toList();
    } else if (obj is String) {
      final masked = obj
          .replaceAllMapped(_keyQueryParam, (m) => '${m[1]}***MASKED***')
          .replaceAllMapped(_bearerToken, (m) => '${m[1]}***MASKED***');
      if (masked.length > _maxStringChars) {
        return '${masked.substring(0, _maxStringChars)}'
            '…<${masked.length - _maxStringChars} chars omitted>';
      }
      return masked;
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