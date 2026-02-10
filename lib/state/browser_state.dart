import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/browser_file.dart';
import '../services/database_service.dart';

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
            } else if (['.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm'].contains(ext)) {
              categoryIndex = 2; // video
            } else if (['.mp3', '.wav', '.flac', '.m4a', '.ogg', '.aac'].contains(ext)) {
              categoryIndex = 3; // audio
            } else if (['.txt', '.md', '.json', '.xml', '.yaml', '.yml', '.srt', '.ass', '.vtt'].contains(ext)) {
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

class BrowserState extends ChangeNotifier {
  final DatabaseService _db = DatabaseService();
  
  List<BrowserFile> allFiles = [];
  List<BrowserFile> filteredFiles = [];
  Set<BrowserFile> selectedFiles = {};
  
  FileCategory currentFilter = FileCategory.all;
  BrowserViewMode viewMode = BrowserViewMode.grid;
  BrowserSortField sortField = BrowserSortField.date;
  bool sortAscending = false;
  double thumbnailSize = 150.0;

  // Directory management
  List<String> sourceDirectories = [];
  List<String> activeDirectories = [];
  
  BrowserState() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
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

  void updateDirectories(List<String> dirs) {
    // This method was previously used for syncing, but we'll remove the sync in AppState.
    // For now, we can keep it as a setter if needed, but the primary way will be toggleDirectory.
    activeDirectories = dirs;
    refresh();
  }

  Future<void> refresh() async {
    if (activeDirectories.isEmpty) {
      allFiles = [];
      _applyFilterAndSort();
      return;
    }

    final List<Map<String, dynamic>> rawFiles = await compute(_scanFilesIsolate, activeDirectories);
    
    final newAllFiles = rawFiles.map((m) => BrowserFile.fromMap(m)).toList();

    // Evict from image cache only if the file was modified or removed
    for (var file in newAllFiles) {
      if (file.category == FileCategory.image) {
        final existing = allFiles.cast<BrowserFile?>().firstWhere((f) => f?.path == file.path, orElse: () => null);
        if (existing != null && existing.modified != file.modified) {
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
    notifyListeners();
  }

  void selectAll() {
    selectedFiles.addAll(filteredFiles);
    notifyListeners();
  }

  void clearSelection() {
    selectedFiles.clear();
    notifyListeners();
  }

  void setViewMode(BrowserViewMode mode) {
    viewMode = mode;
    _db.saveSetting('browser_view_mode', mode.name);
    notifyListeners();
  }

  void setThumbnailSize(double size) {
    thumbnailSize = size;
    _db.saveSetting('browser_thumbnail_size', size.toString());
    notifyListeners();
  }
}