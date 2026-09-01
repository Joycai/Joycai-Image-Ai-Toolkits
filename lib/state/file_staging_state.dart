import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/browser_file.dart';
import '../services/database_service.dart';

/// The file browser's staging area: a list of files the user has marked for a
/// later move or copy.
///
/// Marks only — nothing here touches the disk. That is the whole point of the
/// feature: the browser shows the merged contents of several active
/// directories at once, so "select, then navigate elsewhere, then act" is not
/// a thing the selection can express. The selection is cleared by a re-filter
/// or a re-sort ([FileBrowserState] prunes it on every refresh); this list
/// survives all of that, and the app restart besides.
///
/// The disk is only consulted by [revalidate], which is how an entry becomes
/// [missingPaths] — the file was moved, renamed or deleted behind the app's
/// back. Missing entries are *kept*, not dropped, so the user can see what was
/// lost instead of finding the list quietly shorter.
class FileStagingState extends ChangeNotifier {
  /// Where the marks are persisted, as one path per line.
  ///
  /// Newline rather than the `|` the directory lists use: `|` is legal in a
  /// POSIX filename and this list holds files, not folders the user picked
  /// from a native dialog. A newline is legal too, in theory, and would
  /// corrupt one entry into two — accepted, because every alternative
  /// separator has the same hole and this one is not reachable through any
  /// file picker.
  static const String settingsKey = 'browser_staging_paths';

  final DatabaseService _db = DatabaseService();

  List<BrowserFile> _items = const [];
  Set<String> _paths = const {};
  Set<String> _missingPaths = const {};

  late final Future<void> _ready = _restore();

  FileStagingState() {
    // Kicks off the restore; `_ready` is lazy, so without this nothing would
    // read the setting until someone awaited it.
    unawaited(_ready);
  }

  /// Completes once the persisted marks have been read back.
  ///
  /// Only the first frame and the tests need this — every later change
  /// notifies. Await it before asserting on a freshly constructed instance,
  /// or the assertion races the database.
  Future<void> get ready => _ready;

  /// Staged files in the order they were added.
  List<BrowserFile> get items => List.unmodifiable(_items);

  /// Every staged path, for the grid's per-card lookup. Unmodifiable, and
  /// replaced rather than mutated on every change, so a widget holding the
  /// previous set sees a different object.
  Set<String> get stagedPaths => _paths;

  /// Staged paths whose file was not on disk at the last [revalidate].
  Set<String> get missingPaths => _missingPaths;

  int get count => _items.length;

  bool get isEmpty => _items.isEmpty;

  bool get isNotEmpty => _items.isNotEmpty;

  bool get hasMissing => _missingPaths.isNotEmpty;

  bool contains(String path) => _paths.contains(path);

  bool isMissing(String path) => _missingPaths.contains(path);

  /// Sum of the staged files' sizes. Entries restored but not yet revalidated
  /// contribute 0 — see [BrowserFile.unresolved].
  int get totalBytes => _items.fold(0, (sum, f) => sum + f.size);

  /// The distinct folders the staged files came from, in first-seen order.
  ///
  /// What the panel groups by, and the reason a paste destination has to be
  /// named explicitly: with more than one entry here there is no "the folder
  /// these are in".
  List<String> get sourceDirectories {
    final seen = <String>[];
    for (final file in _items) {
      final dir = p.dirname(file.path);
      if (!seen.any((d) => p.equals(d, dir))) seen.add(dir);
    }
    return seen;
  }

  /// Marks [files], ignoring any already staged. New ones go on the tail, so
  /// the list reads in the order the user built it.
  void addAll(Iterable<BrowserFile> files) {
    final added = files.where((f) => !_paths.contains(f.path)).toList();
    if (added.isEmpty) return;

    _items = [..._items, ...added];
    _paths = {..._paths, ...added.map((f) => f.path)};
    _persist();
    notifyListeners();
  }

  void add(BrowserFile file) => addAll([file]);

  void remove(String path) => removeAll([path]);

  void removeAll(Iterable<String> paths) {
    final drop = paths.toSet();
    if (!drop.any(_paths.contains)) return;

    _items = _items.where((f) => !drop.contains(f.path)).toList();
    _paths = _paths.where((path) => !drop.contains(path)).toSet();
    _missingPaths = _missingPaths.where((path) => !drop.contains(path)).toSet();
    _persist();
    notifyListeners();
  }

  void clear() {
    if (_items.isEmpty) return;

    _items = const [];
    _paths = const {};
    _missingPaths = const {};
    _persist();
    notifyListeners();
  }

  /// Drops the entries whose files are gone.
  void removeMissing() => removeAll(_missingPaths.toList());

  /// Re-reads every staged file's size and timestamp, and recomputes
  /// [missingPaths].
  ///
  /// Call after anything that could have moved files under the staging area —
  /// a completed paste, a rename, a browser refresh — and after the restore,
  /// which is the only way a restored entry gets its metadata at all.
  Future<void> revalidate() async {
    if (_items.isEmpty) {
      if (_missingPaths.isNotEmpty) {
        _missingPaths = const {};
        notifyListeners();
      }
      return;
    }

    final refreshed = <BrowserFile>[];
    final missing = <String>{};

    for (final item in _items) {
      final file = File(item.path);
      try {
        final stat = await file.stat();
        if (stat.type == FileSystemEntityType.notFound) {
          missing.add(item.path);
          refreshed.add(item);
        } else {
          refreshed.add(BrowserFile(
            path: item.path,
            name: item.name,
            category: item.category,
            size: stat.size,
            modified: stat.modified,
          ));
        }
      } on FileSystemException {
        // Unreachable is not the same as gone — a disconnected network share
        // comes back. Marked missing all the same, because the one thing the
        // user can do about either is take it out of the list.
        missing.add(item.path);
        refreshed.add(item);
      }
    }

    _items = refreshed;
    _missingPaths = missing;
    notifyListeners();
  }

  Future<void> _restore() async {
    final saved = await _db.getSetting(settingsKey);
    if (saved == null || saved.isEmpty) return;

    final paths = saved.split('\n').where((line) => line.isNotEmpty).toList();
    if (paths.isEmpty) return;

    _items = paths.map(BrowserFile.unresolved).toList();
    _paths = paths.toSet();
    notifyListeners();

    // Sizes and timestamps are not persisted — they are the disk's to report,
    // and a stored one would be stale exactly when it mattered. This also
    // populates `missingPaths` for anything that went away while the app was
    // closed.
    await revalidate();
  }

  /// Fire-and-forget, like the browser's other settings writes: nothing on
  /// screen waits for the row to land, and a failed write costs the user the
  /// list on next launch, not this session.
  void _persist() {
    unawaited(_db.saveSetting(settingsKey, _items.map((f) => f.path).join('\n')));
  }
}
