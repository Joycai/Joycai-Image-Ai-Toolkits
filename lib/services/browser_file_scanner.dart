import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

/// Lists the files directly inside [paths] (not their subfolders) as the maps
/// `BrowserFile.fromMap` reads, on an isolate of its own.
///
/// [onProgress] receives how many files have been found so far, at most once
/// per [progressInterval]. It is what lets the file area say 「正在扫描 1 208
/// 个文件…」 rather than a bare spinner (`B1a · 1d`). A scan that finishes
/// inside the first interval reports nothing, which is intended: a figure that
/// shows for a single frame is noise.
///
/// A folder that cannot be read contributes nothing rather than failing the
/// scan, and a scan whose isolate dies lists nothing — the same answer an
/// empty folder gives.
Future<List<Map<String, dynamic>>> scanBrowserFiles(
  List<String> paths, {
  void Function(int found)? onProgress,
  Duration progressInterval = const Duration(milliseconds: 100),
}) async {
  final port = ReceivePort();
  final result = Completer<List<Map<String, dynamic>>>();
  port.listen((message) {
    if (result.isCompleted) return;
    if (message is int) {
      onProgress?.call(message);
    } else if (message is _ScanDone) {
      result.complete(message.files);
      port.close();
    } else {
      // The isolate's uncaught error (a pair of strings) or its exit (null)
      // before any result.
      result.complete(const []);
      port.close();
    }
  });

  try {
    await Isolate.spawn(
      _scanInIsolate,
      _ScanRequest(port.sendPort, paths, onProgress == null ? null : progressInterval),
      onError: port.sendPort,
      onExit: port.sendPort,
    );
  } catch (_) {
    port.close();
    return const [];
  }
  return result.future;
}

class _ScanRequest {
  const _ScanRequest(this.port, this.paths, this.progressInterval);

  final SendPort port;
  final List<String> paths;

  /// Null when nobody listens for progress, so nothing is sent.
  final Duration? progressInterval;
}

class _ScanDone {
  const _ScanDone(this.files);

  final List<Map<String, dynamic>> files;
}

void _scanInIsolate(_ScanRequest request) {
  final interval = request.progressInterval;
  final clock = Stopwatch()..start();
  var lastReport = Duration.zero;

  final files = _listFiles(
    request.paths,
    onFound: interval == null
        ? null
        : (found) {
            final now = clock.elapsed;
            if (now - lastReport < interval) return;
            lastReport = now;
            request.port.send(found);
          },
  );
  // Handed over rather than copied: a large folder's listing is the one big
  // message this isolate sends.
  Isolate.exit(request.port, _ScanDone(files));
}

List<Map<String, dynamic>> _listFiles(List<String> paths, {void Function(int found)? onFound}) {
  final List<Map<String, dynamic>> results = [];
  for (final path in paths) {
    try {
      final dir = Directory(path);
      if (!dir.existsSync()) continue;
      for (final file in dir.listSync(recursive: false)) {
        if (file is! File) continue;
        final stat = file.statSync();
        final filePath = file.path;
        final ext = p.extension(filePath).toLowerCase();

        int categoryIndex = 5; // other
        if (['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.avif'].contains(ext)) {
          categoryIndex = 1; // image
        } else if (['.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm', '.m4v'].contains(ext)) {
          categoryIndex = 2; // video
        } else if (['.mp3', '.wav', '.flac', '.m4a', '.ogg', '.aac', '.wma'].contains(ext)) {
          categoryIndex = 3; // audio
        } else if (['.txt', '.md', '.json', '.xml', '.yaml', '.yml', '.srt', '.ass', '.vtt', '.csv', '.log'].contains(ext)) {
          categoryIndex = 4; // text
        }

        results.add({
          'path': filePath,
          'name': p.basename(filePath),
          'categoryIndex': categoryIndex,
          'size': stat.size,
          'modified': stat.modified.millisecondsSinceEpoch,
        });
        onFound?.call(results.length);
      }
    } catch (_) {}
  }
  return results;
}
