import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/app_paths.dart';

/// Which request, continuation leg and retry attempt one debug log belongs
/// to (errors 06 §4: request-body entries carry their leg).
///
/// Without it every retry, continuation leg and agent tool round opened an
/// unrelated file, and "which of these fifty logs was the second attempt of
/// that turn" could only be answered by comparing timestamps. `LLMService`
/// makes one per attempt and runs the attempt inside it
/// ([LLMDebugLogger.runCorrelated] / [LLMDebugLogger.correlatedStream]);
/// [LLMDebugLogger.startLog] reads it from the zone, so no protocol has to
/// forward anything. It also collects the logs the attempt opened, so the
/// service can append the normalised response summary to each.
class LLMLogCorrelation {
  final String? contextId;

  /// Serial of the `LLMService` call — shared by its legs and attempts.
  final int request;

  /// Continuation leg within the call, from 0.
  final int leg;

  /// Retry attempt within the leg, from 0.
  final int attempt;

  /// The logs opened while this correlation was current.
  final List<LLMDebugLog> opened = [];

  LLMLogCorrelation({
    required this.contextId,
    required this.request,
    required this.leg,
    required this.attempt,
  });

  String get header => 'Correlation: context=${contextId ?? '-'} '
      'request=#$request leg=$leg attempt=$attempt';
}

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

  static const Symbol _correlationZoneKey = #llmDebugLogCorrelation;

  /// The correlation of the attempt running in the current zone, or null
  /// outside any `LLMService` attempt.
  static LLMLogCorrelation? get currentCorrelation {
    final value = Zone.current[_correlationZoneKey];
    return value is LLMLogCorrelation ? value : null;
  }

  /// Runs [body] with [correlation] current for everything it starts —
  /// awaited continuations included, since they keep their zone.
  static R runCorrelated<R>(LLMLogCorrelation correlation, R Function() body) =>
      runZoned(body, zoneValues: {_correlationZoneKey: correlation});

  /// [open]'s stream, opened *and listened to* inside [correlation]'s zone.
  ///
  /// For a caller that is itself an `async*` generator: it cannot wrap its
  /// own `await for` in [runCorrelated], so the protocol's stream is created
  /// and subscribed here instead, where the zone value is visible to the
  /// protocol's body. Pause, resume and cancel pass straight through, so an
  /// idle guard tearing the subscription down still drops the connection.
  static Stream<T> correlatedStream<T>(
    LLMLogCorrelation correlation,
    Stream<T> Function() open,
  ) {
    late final StreamController<T> controller;
    StreamSubscription<T>? subscription;
    controller = StreamController<T>(
      onListen: () {
        runCorrelated(correlation, () {
          subscription = open().listen(
            controller.add,
            onError: controller.addError,
            onDone: controller.close,
          );
        });
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }

  /// The one-line normalised outcome appended to every log an attempt
  /// opened: finish reason, usage, and `wire_rewrites` when the response
  /// reported any — or the failure, when there was no response.
  ///
  /// "The answer just stopped" is the question these logs exist to answer
  /// (errors 06 §4), and only the finish reason tells a length cut from a
  /// tool turn from a model that thought it was done. Written by the service
  /// from the merged metadata, so it reads the same on every wire.
  static String responseSummary(Map<String, dynamic>? metadata,
      {Object? error}) {
    if (error != null) {
      final text = error.toString().replaceAll('\n', ' ');
      return 'Summary: error=${error.runtimeType} '
          '${text.length > 300 ? '${text.substring(0, 300)}…' : text}';
    }
    final m = metadata ?? const <String, dynamic>{};
    final parts = <String>['finish_reason=${m['finish_reason'] ?? '-'}'];
    const usageKeys = [
      'prompt_tokens',
      'completion_tokens',
      'input_tokens',
      'output_tokens',
      'promptTokenCount',
      'candidatesTokenCount',
      'thoughtsTokenCount',
      'cache_read_input_tokens',
      'total_tokens',
    ];
    final usage = [
      for (final key in usageKeys)
        if (m[key] != null) '$key=${m[key]}',
    ];
    parts.add(usage.isEmpty ? 'usage=none' : 'usage{${usage.join(' ')}}');
    if (m['stream_incomplete'] == true) parts.add('stream_incomplete');
    if (m['continuations'] != null) {
      parts.add('continuations=${m['continuations']}');
    }
    final rewrites = m['wire_rewrites'];
    if (rewrites != null) parts.add('wire_rewrites=${jsonEncode(rewrites)}');
    return 'Summary: ${parts.join(' ')}';
  }

  /// Appends [responseSummary] to every log [correlation] opened.
  /// Best-effort like every write here; a no-op when debug logging is off,
  /// because then nothing was opened.
  static Future<void> appendSummaries(
    LLMLogCorrelation correlation,
    Map<String, dynamic>? metadata, {
    Object? error,
  }) async {
    if (correlation.opened.isEmpty) return;
    final line = responseSummary(metadata, error: error);
    for (final log in correlation.opened) {
      await appendLine(log, line);
    }
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
      final correlation = currentCorrelation;
      if (correlation != null) buffer.writeln(correlation.header);
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
      final log = LLMDebugLog(file, startedAt);
      correlation?.opened.add(log);
      return log;
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
      await log.file
          .writeAsString('${sanitizeLine(line)}\n', mode: FileMode.append);
    } catch (_) {}
  }

  /// A base64-looking run at least this long is replaced in logged lines.
  /// The same threshold [_sanitize] truncates request strings at.
  static const int base64RunThreshold = _maxStringChars;

  /// [line] with every base64 payload of [base64RunThreshold] characters or
  /// more — bare, or as a `data:` URL — collapsed to `<base64 N chars>`.
  /// A payload is an unbroken run of base64 / base64url characters with up to
  /// two `=` of padding; a `data:<mime>;base64,` directly in front of it is
  /// collapsed with it.
  ///
  /// Response lines are written raw: the image surfaces log `Body:` with
  /// `b64_json` / `bytesBase64Encoded` inside, and a Gemini image stream logs
  /// each SSE line with its `inlineData`. One generated picture is megabytes
  /// of text, and a log nobody can open explains nothing (errors 06 §4).
  /// Done here, on the text, so it holds for every protocol without each one
  /// remembering a "safe body" helper; [_sanitize] covers the request map the
  /// same way structurally. Prose never matches — it has spaces and
  /// punctuation long before 2048 characters.
  ///
  /// A hand-written scan, not a RegExp: `[A-Za-z0-9+/_-]{2048,}` over one
  /// streamed Gemini image — a single SSE line of 5+ million characters —
  /// threw `StackOverflowError` inside the VM's regexp engine, and that threw
  /// out of the stream loop and failed a generation that had succeeded.
  static String sanitizeLine(String line) {
    final n = line.length;
    if (n < base64RunThreshold) return line;
    StringBuffer? out;
    var copied = 0;
    var i = 0;
    while (i < n) {
      if (!_isBase64Char(line.codeUnitAt(i))) {
        i++;
        continue;
      }
      var end = i + 1;
      while (end < n && _isBase64Char(line.codeUnitAt(end))) {
        end++;
      }
      if (end - i >= base64RunThreshold) {
        for (var pad = 0; pad < 2 && end < n && line.codeUnitAt(end) == 0x3D; pad++) {
          end++;
        }
        final prefix = _dataUrlPrefixStart(line, i);
        final start = prefix != null && prefix >= copied ? prefix : i;
        (out ??= StringBuffer())
          ..write(line.substring(copied, start))
          ..write('<base64 ${end - start} chars>');
        copied = end;
      }
      i = end;
    }
    if (out == null) return line;
    out.write(line.substring(copied));
    return out.toString();
  }

  /// `A-Z a-z 0-9 + / _ -` — base64 and base64url together.
  static bool _isBase64Char(int c) =>
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      (c >= 0x30 && c <= 0x39) ||
      c == 0x2B ||
      c == 0x2F ||
      c == 0x5F ||
      c == 0x2D;

  /// `A-Z a-z 0-9 . + / -` — the characters a `data:` URL's mime type may use.
  static bool _isMimeChar(int c) =>
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      (c >= 0x30 && c <= 0x39) ||
      c == 0x2E ||
      c == 0x2B ||
      c == 0x2F ||
      c == 0x2D;

  /// Where `data:<mime>;base64,` starts when it ends right before [runStart],
  /// otherwise null.
  static int? _dataUrlPrefixStart(String line, int runStart) {
    const marker = ';base64,';
    final markerStart = runStart - marker.length;
    if (markerStart < 1 || !line.startsWith(marker, markerStart)) return null;
    var mimeStart = markerStart;
    while (mimeStart > 0 && _isMimeChar(line.codeUnitAt(mimeStart - 1))) {
      mimeStart--;
    }
    if (mimeStart == markerStart) return null;
    final prefixStart = mimeStart - 'data:'.length;
    if (prefixStart < 0 || !line.startsWith('data:', prefixStart)) return null;
    return prefixStart;
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
    // Every SSE loop awaits this before it parses the line, so anything
    // escaping here fails the request itself. A debug log may lose a line;
    // it may never cost the user a generation. Same contract as [appendLine].
    try {
      log.pending.writeln(sanitizeLine(line));
      if (log.pending.length >= _flushThresholdChars) {
        await _flush(log);
      }
    } catch (_) {}
  }

  static Future<void> _flush(LLMDebugLog log) async {
    if (log.pending.isEmpty) return;
    final text = log.pending.toString();
    log.pending.clear();
    try {
      await log.file.writeAsString(text, mode: FileMode.append);
    } catch (_) {
      // A failed write wrote nothing, so the buffer goes back rather than
      // being dropped — up to [_flushThresholdChars] of stream log is
      // exactly the data the buffering exists to preserve, and a transient
      // IO error is the case it was bought for. It goes out with the next
      // flush, or with [finish].
      //
      // Ahead of whatever arrived while the write was in flight: the buffer
      // is cleared *before* the await (lines appended during it must not be
      // lost either), so restoring means re-joining the two halves in order.
      final arrived = log.pending.toString();
      log.pending
        ..clear()
        ..write(text)
        ..write(arrived);
    }
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