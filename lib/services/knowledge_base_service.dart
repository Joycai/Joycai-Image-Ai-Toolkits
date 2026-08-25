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

/// What a knowledge base contains, as the agent sees it.
///
/// [newestModified] is the most recent modification time among the markdown
/// files counted — the honest answer to "will the assistant see the edit I
/// just made", which is what a freshness line on the status card is really
/// being asked. Null when the base holds no readable files.
class KbTreeStats {
  final int files;
  final int directories;
  final DateTime? newestModified;

  const KbTreeStats({
    required this.files,
    required this.directories,
    this.newestModified,
  });
}

/// One row of the knowledge tree as the assistant's left column draws it.
///
/// Flat, in display order, with [depth] carrying the indent — rather than a
/// nested structure. The panel renders a lazy list, and a list is what a lazy
/// list wants; nesting would have to be flattened at every build anyway.
class KbTreeEntry {
  final String relPath;
  final String name;
  final bool isDir;
  final int depth;

  const KbTreeEntry({
    required this.relPath,
    required this.name,
    required this.isDir,
    required this.depth,
  });
}

/// What the agent is allowed to do to the knowledge base, from `A2 10h`'s
/// 写入权限 card.
///
/// Three separate switches rather than one, because they fail differently:
/// [allowWrites] decides whether the write tool is offered at all,
/// [confirmEachWrite] decides whether what it proposes reaches disk without a
/// human seeing it, and [backupBeforeOverwrite] decides whether the previous
/// version survives either way.
class KbWritePolicy {
  final bool allowWrites;
  final bool confirmEachWrite;
  final bool backupBeforeOverwrite;

  const KbWritePolicy({
    this.allowWrites = true,
    this.confirmEachWrite = true,
    this.backupBeforeOverwrite = false,
  });

  /// The defaults, spelled out: the agent may propose, nothing lands without
  /// approval, and no backups are kept — because with approval on there is
  /// nothing to recover from that the user did not read first.
  static const KbWritePolicy defaults = KbWritePolicy();

  KbWritePolicy copyWith({
    bool? allowWrites,
    bool? confirmEachWrite,
    bool? backupBeforeOverwrite,
  }) =>
      KbWritePolicy(
        allowWrites: allowWrites ?? this.allowWrites,
        confirmEachWrite: confirmEachWrite ?? this.confirmEachWrite,
        backupBeforeOverwrite: backupBeforeOverwrite ?? this.backupBeforeOverwrite,
      );

  @override
  bool operator ==(Object other) =>
      other is KbWritePolicy &&
      other.allowWrites == allowWrites &&
      other.confirmEachWrite == confirmEachWrite &&
      other.backupBeforeOverwrite == backupBeforeOverwrite;

  @override
  int get hashCode => Object.hash(allowWrites, confirmEachWrite, backupBeforeOverwrite);
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

  static const String _allowWritesKey = 'kb_allow_writes';
  static const String _confirmWritesKey = 'kb_confirm_writes';
  static const String _backupWritesKey = 'kb_backup_writes';

  /// Suffix for the copy [backupFile] leaves behind. Deliberately appended to
  /// the whole name rather than replacing `.md`: `listFiles` only surfaces
  /// `.md`, so `07b.md.bak` is invisible to the agent while `07b.bak.md`
  /// would come back as a second document saying nearly the same thing.
  static const String backupSuffix = '.bak';

  Future<KbWritePolicy> getWritePolicy() async {
    final db = DatabaseService();
    Future<bool> read(String key, bool fallback) async {
      final raw = await db.getSetting(key);
      if (raw == null || raw.isEmpty) return fallback;
      return raw == '1' || raw.toLowerCase() == 'true';
    }

    return KbWritePolicy(
      allowWrites: await read(_allowWritesKey, KbWritePolicy.defaults.allowWrites),
      confirmEachWrite: await read(_confirmWritesKey, KbWritePolicy.defaults.confirmEachWrite),
      backupBeforeOverwrite:
          await read(_backupWritesKey, KbWritePolicy.defaults.backupBeforeOverwrite),
    );
  }

  Future<void> setWritePolicy(KbWritePolicy policy) async {
    final db = DatabaseService();
    await db.saveSetting(_allowWritesKey, policy.allowWrites ? '1' : '0');
    await db.saveSetting(_confirmWritesKey, policy.confirmEachWrite ? '1' : '0');
    await db.saveSetting(_backupWritesKey, policy.backupBeforeOverwrite ? '1' : '0');
  }

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

  /// Walks the whole tree, counting what the agent can reach and noting when
  /// that content last changed.
  ///
  /// Built on [listFiles] rather than a raw directory walk so the numbers
  /// match exactly what the model is shown — same hidden-segment skip, same
  /// markdown-only filter. A count that included files the agent cannot read
  /// would be worse than no count.
  ///
  /// Deliberately not cached, and deliberately not an "index". This service
  /// reads the folder on demand and is therefore never stale; a stored count
  /// would be the only stale thing in the subsystem. Callers that want to show
  /// freshness should show [KbTreeStats.newestModified] — the content's own
  /// timestamp — rather than when some scan last ran.
  KbTreeStats scanTree(String root, {String? dir, int depth = 0}) {
    // Symlink loops inside the root survive resolvePath's containment check,
    // which is lexical. A depth cap is cheaper than tracking visited inodes
    // and no real knowledge base nests this far.
    if (depth > 12) return const KbTreeStats(files: 0, directories: 0);

    var files = 0;
    var directories = 0;
    DateTime? newest;

    for (final entry in listFiles(root, dir: dir)) {
      if (entry.isDir) {
        directories++;
        final nested = scanTree(root, dir: entry.relPath, depth: depth + 1);
        files += nested.files;
        directories += nested.directories;
        newest = _laterOf(newest, nested.newestModified);
      } else {
        files++;
        final stat = File(resolvePath(root, entry.relPath)).statSync();
        newest = _laterOf(newest, stat.modified);
      }
    }

    return KbTreeStats(files: files, directories: directories, newestModified: newest);
  }

  /// Every folder and markdown file under [root], in display order.
  ///
  /// Built on [listFiles] for the same reason [scanTree] is: the panel must
  /// show exactly what the agent can reach, and a tree that listed files the
  /// model cannot read would invite the user to ask about documents that are
  /// not there.
  ///
  /// [limit] is a backstop, not a feature. A folder someone pointed at their
  /// home directory would otherwise walk it synchronously; the count on the
  /// header comes from [scanTree] and stays truthful either way.
  List<KbTreeEntry> walkTree(String root, {String? dir, int depth = 0, int limit = 2000}) {
    if (depth > 12) return const [];

    final entries = <KbTreeEntry>[];
    for (final entry in listFiles(root, dir: dir)) {
      if (entries.length >= limit) break;
      final name = p.basename(entry.relPath);
      entries.add(KbTreeEntry(
        relPath: entry.relPath,
        name: name,
        isDir: entry.isDir,
        depth: depth,
      ));
      if (entry.isDir) {
        entries.addAll(walkTree(
          root,
          dir: entry.relPath,
          depth: depth + 1,
          limit: limit - entries.length,
        ));
      }
    }
    // Alphabetical within each level, folders and files together — whatever
    // [listFiles] sorted, with each folder's contents spliced in behind it.
    return entries;
  }

  /// Copies [relPath] beside itself as `<name>.bak` before it is overwritten.
  ///
  /// A no-op when the file does not exist yet: a create has no previous
  /// version, and writing an empty `.bak` would invent one. Any existing
  /// backup is replaced — the point is to be able to undo *this* write, and a
  /// chain of numbered copies inside a folder the agent reads from is litter
  /// the user did not ask for.
  Future<void> backupFile(String root, String relPath) async {
    final resolved = resolvePath(root, relPath);
    final file = File(resolved);
    if (!file.existsSync()) return;
    _requireInsideRootResolvingLinks(root, resolved, relPath);
    await file.copy('$resolved$backupSuffix');
  }

  static DateTime? _laterOf(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
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
