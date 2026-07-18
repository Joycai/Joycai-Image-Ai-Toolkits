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

  /// Rejects paths with hidden (dot-prefixed) segments. [listFiles] never
  /// surfaces them, so the model has no legitimate way to name one — but a
  /// prompt-injected model could still probe `.git/config`, `.env` and the
  /// like, whose content would then be shipped to a third-party provider.
  static void _rejectHiddenSegments(String relPath) {
    if (p.split(relPath).any((segment) => segment.startsWith('.'))) {
      throw KbPathException('Paths must not contain hidden (dot-prefixed) segments.');
    }
  }

  /// Read-side twin of the [writeFile] policy: only the markdown files that
  /// [listFiles] surfaces are readable.
  static void _requireReadableMarkdown(String relPath) {
    if (!relPath.toLowerCase().endsWith('.md')) {
      throw KbPathException('Only markdown (.md) files can be read.');
    }
    _rejectHiddenSegments(relPath);
  }

  /// Verifies that [resolved] does not escape [root] once symbolic links are
  /// followed. [resolvePath]'s containment check is purely lexical, so a
  /// symlink inside the root pointing outside it would pass while actually
  /// reading foreign files. [resolved] must exist; [relPath] is only used for
  /// the error message.
  static void _requireInsideRootResolvingLinks(String root, String resolved, String relPath) {
    final String realRoot;
    final String real;
    try {
      realRoot = Directory(root).resolveSymbolicLinksSync();
      real = FileSystemEntity.isDirectorySync(resolved)
          ? Directory(resolved).resolveSymbolicLinksSync()
          : File(resolved).resolveSymbolicLinksSync();
    } on FileSystemException {
      throw KbPathException('File not found: $relPath');
    }
    if (real != realRoot && !p.isWithin(realRoot, real)) {
      throw KbPathException('Path escapes the knowledge base folder.');
    }
  }

  /// Lists markdown files and subdirectories directly under [dir] (relative
  /// to [root]; empty/null = root). Subdirectories are returned as entries so
  /// the model can descend on demand.
  List<KbFileInfo> listFiles(String root, {String? dir}) {
    final String target;
    if (dir == null || dir.trim().isEmpty) {
      target = p.normalize(root);
    } else {
      _rejectHiddenSegments(dir);
      target = resolvePath(root, dir);
    }
    final directory = Directory(target);
    if (!directory.existsSync()) {
      throw KbPathException('Directory not found: ${dir ?? '.'}');
    }
    _requireInsideRootResolvingLinks(root, target, dir ?? '.');
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

  /// Reads a knowledge file in full, unpaged. Returns null when it does not
  /// exist — callers use that to distinguish a create from an overwrite.
  String? readFullFile(String root, String relPath) {
    _requireReadableMarkdown(relPath);
    final resolved = resolvePath(root, relPath);
    final file = File(resolved);
    if (!file.existsSync()) return null;
    _requireInsideRootResolvingLinks(root, resolved, relPath);
    return file.readAsStringSync();
  }

  /// Creates or overwrites a knowledge file, creating parent directories as
  /// needed. Stricter than [resolvePath] alone: the target must be a markdown
  /// file that [listFiles] would surface, and can never be the root itself.
  Future<void> writeFile(String root, String relPath, String content) async {
    final resolved = resolvePath(root, relPath);
    if (p.equals(resolved, p.normalize(root))) {
      throw KbPathException('The knowledge base root is not a file.');
    }
    if (!relPath.toLowerCase().endsWith('.md')) {
      throw KbPathException('Only markdown (.md) files can be written.');
    }
    // Mirrors the dot-prefix skip in listFiles: a hidden file would be written
    // but stay invisible to the agent afterwards.
    _rejectHiddenSegments(relPath);
    // The target may not exist yet, so check symlink containment on its
    // deepest existing ancestor instead.
    var probe = p.dirname(resolved);
    while (!Directory(probe).existsSync()) {
      final parent = p.dirname(probe);
      if (parent == probe) break;
      probe = parent;
    }
    _requireInsideRootResolvingLinks(root, probe, relPath);
    final file = File(resolved);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  /// How far back a page boundary may be pulled to land on a paragraph break,
  /// as a fraction of [pageSize]. Beyond this the text is treated as having no
  /// usable break (a huge table, minified content) and is cut at the limit.
  static const double _snapTolerance = 0.25;

  /// Page start offsets for [content] at [pageSize], snapped to paragraph or
  /// heading breaks where one is close enough.
  ///
  /// A page cut at a raw offset lands mid-sentence, mid-table or mid-code-fence
  /// and hands the model half a rule. Snapping costs a little page capacity and
  /// buys pages that end where a thought does.
  ///
  /// Pure and deterministic given [content] and [pageSize]: page numbers are
  /// used as cache keys, so the same page must always mean the same bytes.
  static List<int> pageBoundaries(String content, int pageSize) {
    if (content.isEmpty) return [0];
    final starts = <int>[0];
    int cursor = 0;
    while (cursor + pageSize < content.length) {
      final limit = cursor + pageSize;
      final earliest = limit - (pageSize * _snapTolerance).round();
      // Prefer a heading: it starts a section, so the break reads as intended
      // rather than incidental. Fall back to any blank line.
      int cut = _lastIndexOfWithin(content, '\n#', earliest, limit);
      cut = cut >= 0 ? cut + 1 : _lastIndexOfWithin(content, '\n\n', earliest, limit);
      if (cut >= 0 && cut > cursor) {
        // Land after the break so the page starts on real text.
        cursor = content.startsWith('\n\n', cut) ? cut + 2 : cut;
      } else {
        cursor = limit;
      }
      starts.add(cursor);
    }
    return starts;
  }

  /// Last index of [needle] in `content[from, to)`, or -1.
  static int _lastIndexOfWithin(String content, String needle, int from, int to) {
    final found = content.lastIndexOf(needle, to - needle.length);
    return found >= from ? found : -1;
  }

  /// Reads one page of a knowledge file. [page] is 1-based.
  ///
  /// [maxChars] is what the caller has room for right now. A file that fits
  /// comes back whole as page 1 of 1 — cheaper than several round trips, and
  /// better than handing the model a slice of a rule. When it does not fit,
  /// pages stay at [pageSize] so that page numbers keep meaning the same bytes
  /// from one read to the next; the exception is a window too small to hold
  /// even one full page, where the page shrinks rather than blowing the budget.
  KbReadResult readFile(String root, String relPath, {int page = 1, int? maxChars}) {
    _requireReadableMarkdown(relPath);
    final resolved = resolvePath(root, relPath);
    final file = File(resolved);
    if (!file.existsSync()) {
      throw KbPathException('File not found: $relPath');
    }
    _requireInsideRootResolvingLinks(root, resolved, relPath);
    final content = file.readAsStringSync();
    if (maxChars != null && content.length <= maxChars) {
      return KbReadResult(content: content, page: 1, totalPages: 1);
    }
    final effectivePageSize =
        (maxChars != null && maxChars < pageSize) ? maxChars : pageSize;
    final starts = pageBoundaries(content, effectivePageSize);
    final clamped = page.clamp(1, starts.length);
    final start = starts[clamped - 1];
    final end = clamped < starts.length ? starts[clamped] : content.length;
    return KbReadResult(
      content: content.substring(start, end),
      page: clamped,
      totalPages: starts.length,
    );
  }
}
