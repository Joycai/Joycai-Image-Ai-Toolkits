import 'dart:io';

import 'package:path/path.dart' as p;

import 'database_service.dart';

/// Validation outcome for the configured knowledge-base folder.
enum KbStatus { ok, notSet, missingDir, missingEntry }

class KbFileInfo {
  final String relPath;
  final int sizeKb;
  final bool isDir;

  const KbFileInfo({required this.relPath, required this.sizeKb, required this.isDir});

  Map<String, dynamic> toJson() => {
        'path': relPath,
        if (!isDir) 'size_kb': sizeKb,
        'is_dir': isDir,
      };
}

class KbReadResult {
  final String content;
  final int page;
  final int totalPages;

  const KbReadResult({required this.content, required this.page, required this.totalPages});
}

/// Thrown when a tool-supplied path escapes the knowledge-base root or does
/// not exist. The message is safe to surface to the model.
class KbPathException implements Exception {
  final String message;
  KbPathException(this.message);
  @override
  String toString() => message;
}

/// Local-file access to the user's prompt-engineering knowledge base.
///
/// The knowledge base is a plain folder of markdown rule files with a fixed
/// entry point ([entryFileName]) acting as the file map. Files are read on
/// demand (progressive disclosure) and large files are paged so a single tool
/// result never floods the context window.
class KnowledgeBaseService {
  static final KnowledgeBaseService _instance = KnowledgeBaseService._internal();
  factory KnowledgeBaseService() => _instance;
  KnowledgeBaseService._internal();

  static const String settingKey = 'knowledge_base_path';
  static const String entryFileName = 'README.md';

  /// Max characters returned per read_knowledge_file page.
  static const int pageSize = 8000;

  Future<String?> getRoot() async {
    final path = await DatabaseService().getSetting(settingKey);
    return (path == null || path.trim().isEmpty) ? null : path.trim();
  }

  Future<void> setRoot(String path) =>
      DatabaseService().saveSetting(settingKey, path);

  Future<KbStatus> validate([String? root]) async {
    root ??= await getRoot();
    if (root == null) return KbStatus.notSet;
    if (!Directory(root).existsSync()) return KbStatus.missingDir;
    if (!File(p.join(root, entryFileName)).existsSync()) return KbStatus.missingEntry;
    return KbStatus.ok;
  }

  /// Reads the entry file (the knowledge-base file map) in full.
  String readEntry(String root) =>
      File(p.join(root, entryFileName)).readAsStringSync();

  /// Resolves a model-supplied [relative] path against [root], rejecting
  /// absolute paths and anything that escapes the root after normalization.
  String resolvePath(String root, String relative) {
    if (relative.trim().isEmpty) throw KbPathException('Path must not be empty.');
    if (p.isAbsolute(relative)) {
      throw KbPathException('Absolute paths are not allowed — use a path relative to the knowledge base root.');
    }
    final resolved = p.normalize(p.join(root, relative));
    final normalizedRoot = p.normalize(root);
    if (!p.isWithin(normalizedRoot, resolved) && resolved != normalizedRoot) {
      throw KbPathException('Path escapes the knowledge base folder.');
    }
    return resolved;
  }

  /// Lists markdown files and subdirectories directly under [dir] (relative
  /// to [root]; empty/null = root). Subdirectories are returned as entries so
  /// the model can descend on demand.
  List<KbFileInfo> listFiles(String root, {String? dir}) {
    final target = (dir == null || dir.trim().isEmpty) ? p.normalize(root) : resolvePath(root, dir);
    final directory = Directory(target);
    if (!directory.existsSync()) {
      throw KbPathException('Directory not found: ${dir ?? '.'}');
    }
    final entries = <KbFileInfo>[];
    for (final entity in directory.listSync()) {
      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue;
      final rel = p.relative(entity.path, from: root).replaceAll('\\', '/');
      if (entity is Directory) {
        entries.add(KbFileInfo(relPath: rel, sizeKb: 0, isDir: true));
      } else if (entity is File && name.toLowerCase().endsWith('.md')) {
        entries.add(KbFileInfo(
          relPath: rel,
          sizeKb: (entity.lengthSync() / 1024).round(),
          isDir: false,
        ));
      }
    }
    entries.sort((a, b) => a.relPath.compareTo(b.relPath));
    return entries;
  }

  /// Reads one page of a knowledge file. [page] is 1-based.
  KbReadResult readFile(String root, String relPath, {int page = 1}) {
    final resolved = resolvePath(root, relPath);
    final file = File(resolved);
    if (!file.existsSync()) {
      throw KbPathException('File not found: $relPath');
    }
    final content = file.readAsStringSync();
    final totalPages = content.isEmpty ? 1 : ((content.length + pageSize - 1) ~/ pageSize);
    final clamped = page.clamp(1, totalPages);
    final start = (clamped - 1) * pageSize;
    final end = (start + pageSize) > content.length ? content.length : start + pageSize;
    return KbReadResult(
      content: content.substring(start, end),
      page: clamped,
      totalPages: totalPages,
    );
  }
}
