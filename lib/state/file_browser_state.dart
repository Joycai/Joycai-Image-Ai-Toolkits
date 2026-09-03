import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/file_utils.dart';
import '../models/browser_file.dart';
import '../services/database_service.dart';
import '../services/file_permission_service.dart';

List<Map<String, dynamic>> _scanFilesIsolate(List<String> paths) {
  List<Map<String, dynamic>> results = [];
  for (var path in paths) {
    try {
      final dir = Directory(path);
      if (dir.existsSync()) {
        for (var file in dir.listSync(recursive: false)) {
          if (file is File) {
            final stat = file.statSync();
            final filePath = file.path;
            final name = p.basename(filePath);
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
              'name': name,
              'categoryIndex': categoryIndex,
              'size': stat.size,
              'modified': stat.modified.millisecondsSinceEpoch,
            });
          }
        }
      }
    } catch (_) {}
  }
  return results;
}

enum BrowserViewMode {
  grid,
  list,
}

enum BrowserSortField {
  name,
  date,
  type,
}

class FileBrowserState extends ChangeNotifier {
  final DatabaseService _db = DatabaseService();
  
  List<BrowserFile> allFiles = [];
  List<BrowserFile> filteredFiles = [];
  Set<BrowserFile> selectedFiles = {};

  /// The last file clicked without Shift — the fixed end of a Shift-click
  /// range. Stored by path, not index, so it survives a re-sort or re-filter;
  /// [selectRangeTo] resolves it back to an index against the current
  /// [filteredFiles] at click time.
  String? _selectionAnchorPath;
  
  FileCategory currentFilter = FileCategory.all;
  String searchQuery = '';
  BrowserViewMode viewMode = BrowserViewMode.grid;
  BrowserSortField sortField = BrowserSortField.date;
  bool sortAscending = false;
  double thumbnailSize = 150.0;

  // Directory management
  List<String> sourceDirectories = [];
  List<String> activeDirectories = [];
  Set<String> unreachableDirectories = {};
  int _refreshCounter = 0;
  int get refreshCounter => _refreshCounter;
  
  FileBrowserState() {
    reloadSettings();
  }

  Future<void> reloadSettings() async {
    final savedThumbSize = await _db.getSetting('browser_thumbnail_size');
    if (savedThumbSize != null) {
      thumbnailSize = double.tryParse(savedThumbSize) ?? 150.0;
    }
    
    final savedViewMode = await _db.getSetting('browser_view_mode');
    if (savedViewMode != null) {
      viewMode = BrowserViewMode.values.firstWhere(
        (e) => e.name == savedViewMode, 
        orElse: () => BrowserViewMode.grid
      );
    }

    final savedSortField = await _db.getSetting('browser_sort_field');
    if (savedSortField != null) {
      sortField = BrowserSortField.values.firstWhere(
        (e) => e.name == savedSortField,
        orElse: () => BrowserSortField.date
      );
    }

    final savedSortAsc = await _db.getSetting('browser_sort_ascending');
    if (savedSortAsc != null) {
      sortAscending = savedSortAsc == 'true';
    }

    // Load browser-specific root directories
    final savedRoots = await _db.getSetting('browser_source_directories');
    if (savedRoots != null && savedRoots.isNotEmpty) {
      sourceDirectories = savedRoots.split('|');
    }

    // Load browser-specific active directories if they exist
    final savedActive = await _db.getSetting('browser_active_directories');
    if (savedActive != null && savedActive.isNotEmpty) {
      activeDirectories = savedActive.split('|');
    }

    await refresh();
    notifyListeners();
  }

  Future<void> addBaseDirectory(String path) async {
    if (!sourceDirectories.contains(path)) {
      sourceDirectories.add(path);
      activeDirectories.add(path);
      await _db.saveSetting('browser_source_directories', sourceDirectories.join('|'));
      await _db.saveSetting('browser_active_directories', activeDirectories.join('|'));
      refresh();
      notifyListeners();
    }
  }

  Future<void> removeBaseDirectory(String path) async {
    if (sourceDirectories.contains(path)) {
      sourceDirectories.remove(path);
      activeDirectories.removeWhere((p) => p.startsWith(path));
      await _db.saveSetting('browser_source_directories', sourceDirectories.join('|'));
      await _db.saveSetting('browser_active_directories', activeDirectories.join('|'));
      refresh();
      notifyListeners();
    }
  }

  Future<void> toggleDirectory(String path) async {
    if (activeDirectories.contains(path)) {
      activeDirectories.remove(path);
    } else {
      activeDirectories.add(path);
    }
    await _db.saveSetting('browser_active_directories', activeDirectories.join('|'));
    refresh();
  }

  Future<void> clearActiveDirectories() async {
    if (activeDirectories.isEmpty) return;
    activeDirectories = [];
    await _db.saveSetting('browser_active_directories', '');
    refresh();
  }

  Future<void> setExclusiveDirectory(String path) async {
    activeDirectories = [path];
    await _db.saveSetting('browser_active_directories', activeDirectories.join('|'));
    refresh();
  }

  /// Points every registered and active directory under [from] at [to]
  /// instead — what a rename or move of a folder in the tree has to do to the
  /// lists that name it, roots included. No-op when nothing pointed there.
  /// Does not rescan: the caller refreshes once after every list is in step.
  Future<void> rewritePathPrefix(String from, String to) async {
    List<String> rewrite(List<String> paths) => [
          for (final path in paths) FileUtils.rebasePath(path, from: from, to: to) ?? path,
        ];
    final newSources = rewrite(sourceDirectories);
    final newActive = rewrite(activeDirectories);
    final changed = !listEquals(newSources, sourceDirectories) || !listEquals(newActive, activeDirectories);
    if (!changed) return;

    sourceDirectories = newSources;
    activeDirectories = newActive;
    await _db.saveSetting('browser_source_directories', sourceDirectories.join('|'));
    await _db.saveSetting('browser_active_directories', activeDirectories.join('|'));
    notifyListeners();
  }

  /// Forgets the active directories at or under [path] after the folder was
  /// deleted. If the user was looking at one of them, its parent takes over —
  /// the grid going blank because the folder under it vanished reads as a
  /// bug, not as a consequence.
  Future<void> pruneRemoved(String path) async {
    final removed = activeDirectories
        .where((d) => p.equals(d, path) || p.isWithin(path, d))
        .toList();
    if (removed.isEmpty) return;

    final kept = activeDirectories.where((d) => !removed.contains(d)).toList();
    final parent = p.dirname(path);
    final parentInTree = sourceDirectories.any((r) => p.equals(r, parent) || p.isWithin(r, parent));
    if (parentInTree && !kept.any((d) => p.equals(d, parent))) kept.add(parent);

    activeDirectories = kept;
    await _db.saveSetting('browser_active_directories', activeDirectories.join('|'));
    notifyListeners();
  }

  /// The row the tree should pulse once it next draws — a folder just
  /// created, renamed or dropped somewhere, so the eye finds where it landed.
  /// Cleared on its own after the pulse has had time to play.
  String? get flashPath => _flashPath;
  String? _flashPath;
  Timer? _flashTimer;

  void flash(String path) {
    _flashTimer?.cancel();
    _flashPath = path;
    notifyListeners();
    _flashTimer = Timer(const Duration(milliseconds: 1500), () {
      _flashPath = null;
      notifyListeners();
    });
  }

  void updateDirectories(List<String> dirs) {
    // This method was previously used for syncing, but we'll remove the sync in AppState.
    // For now, we can keep it as a setter if needed, but the primary way will be toggleDirectory.
    activeDirectories = dirs;
    refresh();
  }

  Future<void> refresh() async {
    _refreshCounter++;
    
    // Check for unreachable directories
    final newUnreachable = <String>{};
    for (var path in sourceDirectories) {
      if (FilePermissionService().isPathUnreachable(path)) {
        newUnreachable.add(path);
      }
    }
    unreachableDirectories = newUnreachable;

    if (activeDirectories.isEmpty) {
      allFiles = [];
      _applyFilterAndSort();
      return;
    }

    final List<Map<String, dynamic>> rawFiles = await compute(_scanFilesIsolate, activeDirectories);
    
    final newAllFiles = rawFiles.map((m) => BrowserFile.fromMap(m)).toList();

    // Evict from image cache only if the file was modified or removed.
    //
    // Indexed rather than searched: this was a linear `firstWhere` over the
    // previous listing per file, so a directory of a thousand pictures cost
    // half a million comparisons on the UI thread every time the watcher fired.
    final previousModified = {
      for (final f in allFiles) f.path: f.modified,
    };
    for (var file in newAllFiles) {
      if (file.category == FileCategory.image) {
        final existing = previousModified[file.path];
        if (existing != null && existing != file.modified) {
          PaintingBinding.instance.imageCache.evict(FileImage(File(file.path)));
        }
      }
    }

    allFiles = newAllFiles;
    _applyFilterAndSort();
  }

  void setFilter(FileCategory category) {
    currentFilter = category;
    _applyFilterAndSort();
  }

  void setSearchQuery(String query) {
    searchQuery = query.trim();
    _applyFilterAndSort();
  }

  void setSortField(BrowserSortField field) {
    sortField = field;
    _db.saveSetting('browser_sort_field', field.name);
    _applyFilterAndSort();
  }

  void setSortAscending(bool ascending) {
    sortAscending = ascending;
    _db.saveSetting('browser_sort_ascending', ascending.toString());
    _applyFilterAndSort();
  }

  void _applyFilterAndSort() {
    if (currentFilter == FileCategory.all) {
      filteredFiles = List.from(allFiles);
    } else {
      filteredFiles = allFiles.where((f) => f.category == currentFilter).toList();
    }

    if (searchQuery.isNotEmpty) {
      final q = searchQuery.toLowerCase();
      filteredFiles = filteredFiles.where((f) => f.name.toLowerCase().contains(q)).toList();
    }

    // Apply sorting
    filteredFiles.sort((a, b) {
      int cmp;
      switch (sortField) {
        case BrowserSortField.name:
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          break;
        case BrowserSortField.date:
          cmp = a.modified.compareTo(b.modified);
          break;
        case BrowserSortField.type:
          cmp = a.category.index.compareTo(b.category.index);
          if (cmp == 0) {
            cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          }
          break;
      }
      return sortAscending ? cmp : -cmp;
    });
    
    // Cleanup selection
    selectedFiles.removeWhere((selected) => !allFiles.any((f) => f.path == selected.path));
    notifyListeners();
  }

  void toggleSelection(BrowserFile file) {
    if (selectedFiles.contains(file)) {
      selectedFiles.remove(file);
    } else {
      selectedFiles.add(file);
    }
    // A plain click re-anchors: the next Shift-click ranges from here.
    _selectionAnchorPath = file.path;
    notifyListeners();
  }

  /// Selects every file from the anchor (the last plain click) to [file],
  /// inclusive, in the current [filteredFiles] order — the Shift-click range.
  /// Adds the span to whatever is already selected rather than replacing it.
  /// Falls back to a plain toggle when there is no anchor yet, or the anchor
  /// has scrolled out of the current filter/search view.
  void selectRangeTo(BrowserFile file) {
    final anchorPath = _selectionAnchorPath;
    if (anchorPath == null) {
      toggleSelection(file);
      return;
    }
    final anchorIndex = filteredFiles.indexWhere((f) => f.path == anchorPath);
    final targetIndex = filteredFiles.indexWhere((f) => f.path == file.path);
    if (anchorIndex == -1 || targetIndex == -1) {
      toggleSelection(file);
      return;
    }
    final start = anchorIndex < targetIndex ? anchorIndex : targetIndex;
    final end = anchorIndex < targetIndex ? targetIndex : anchorIndex;
    for (var i = start; i <= end; i++) {
      selectedFiles.add(filteredFiles[i]);
    }
    // Anchor stays put, so successive Shift-clicks re-range from the same
    // origin — the behaviour every file manager has.
    notifyListeners();
  }

  void selectAll() {
    selectedFiles.addAll(filteredFiles);
    notifyListeners();
  }

  void clearSelection() {
    selectedFiles.clear();
    _selectionAnchorPath = null;
    notifyListeners();
  }

  void setViewMode(BrowserViewMode mode) {
    viewMode = mode;
    _db.saveSetting('browser_view_mode', mode.name);
    notifyListeners();
  }

  /// Resizes the grid, live — no database write. See
  /// [GalleryState.setThumbnailSize] for why the persistence is split out.
  void setThumbnailSize(double size) {
    if (thumbnailSize == size) return;
    thumbnailSize = size;
    notifyListeners();
  }

  /// Writes the size the user settled on. Call from a slider's `onChangeEnd`.
  Future<void> persistThumbnailSize() =>
      _db.saveSetting('browser_thumbnail_size', thumbnailSize.toString());
}