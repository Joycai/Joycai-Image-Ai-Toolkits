import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/constants.dart';
import '../models/app_image.dart';
import '../services/database_service.dart';
import '../services/file_permission_service.dart';

/// Top-level function for background disk scanning to keep UI smooth.
List<String> _scanImagesIsolate(List<String> paths) {
  List<String> results = [];
  for (var path in paths) {
    try {
      final dir = Directory(path);
      // On iOS, listing arbitrary external directories might throw even if exists() is true
      if (dir.existsSync()) {
        for (var file in dir.listSync(recursive: false)) {
          if (file is File && AppConstants.isImageFile(file.path)) {
            results.add(file.path);
          }
        }
      }
    } catch (_) {}
  }
  return results;
}

enum GalleryViewMode {
  all,
  processed,
  temp,
  folder,
}

class GalleryState extends ChangeNotifier {
  final DatabaseService _db = DatabaseService();
  
  List<String> sourceDirectories = [];
  List<String> activeSourceDirectories = [];
  Set<String> unreachableDirectories = {};
  
  // View State
  GalleryViewMode viewMode = GalleryViewMode.all;
  String? viewSourcePath; // Used when viewMode is folder

  // Model-based image lists
  List<AppImage> galleryImages = [];
  List<AppImage> folderImages = [];
  List<AppImage> processedImages = [];
  List<AppImage> selectedImages = [];
  List<AppImage> droppedImages = []; // Transient workspace
  
  String? outputDirectory;
  double thumbnailSize = 150.0;
  String imagePrefix = "result";

  // Directory watchers
  final Map<String, StreamSubscription> _watchers = {};
  StreamSubscription? _outputWatcher;
  Timer? _sourceScanTimer;
  Timer? _outputScanTimer;

  // Callback for logging to the main app log
  Function(String, {String level})? onLog;

  int _refreshCounter = 0;
  int get refreshCounter => _refreshCounter;

  GalleryState() {
    _loadSettings();
  }

  @override
  void dispose() {
    for (var sub in _watchers.values) {
      sub.cancel();
    }
    _outputWatcher?.cancel();
    _sourceScanTimer?.cancel();
    _outputScanTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final savedThumbSize = await _db.getSetting('thumbnail_size');
    if (savedThumbSize != null) {
      thumbnailSize = double.tryParse(savedThumbSize) ?? 150.0;
    }

    imagePrefix = await _db.getSetting('image_prefix') ?? "result";
    outputDirectory = await _db.getSetting('output_directory');

    // On iOS, we use the System Cache folder as a "Result Cache"
    if (Platform.isIOS) {
      final cacheDir = await getTemporaryDirectory();
      outputDirectory = p.join(cacheDir.path, 'result_cache');
      final dir = Directory(outputDirectory!);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      await _db.saveSetting('output_directory', outputDirectory!);
    }
    
    final dirs = await _db.getSourceDirectories();
    sourceDirectories = dirs.map((d) => d['path'] as String).toList();
    activeSourceDirectories = dirs
        .where((d) => d['is_selected'] == 1)
        .map((d) => d['path'] as String)
        .toList();

    _setupOutputWatcher();
    _setupSourceWatchers();
    _scanImages();
    _scanProcessedImages();
    notifyListeners();
  }

  void _log(String message, {String level = 'INFO'}) {
    onLog?.call(message, level: level);
  }

  void _setupSourceWatchers() {
    for (var sub in _watchers.values) {
      sub.cancel();
    }
    _watchers.clear();

    // iOS does not support directory watching
    if (Platform.isIOS) return;

    for (var path in activeSourceDirectories) {
      try {
        final dir = Directory(path);
        if (dir.existsSync()) {
          _watchers[path] = dir.watch().listen((event) {
            _debouncedSourceScan();
          });
        }
      } catch (e) {
        _log('Failed to watch directory $path: $e', level: 'ERROR');
      }
    }
  }

  void _setupOutputWatcher() {
    _outputWatcher?.cancel();
    // iOS does not support directory watching
    if (Platform.isIOS) return;

    if (outputDirectory != null && outputDirectory!.isNotEmpty) {
      try {
        final dir = Directory(outputDirectory!);
        if (dir.existsSync()) {
          _outputWatcher = dir.watch().listen((event) {
            _debouncedOutputScan();
          });
        }
      } catch (e) {
        _log('Failed to watch output directory: $e', level: 'ERROR');
      }
    }
  }

  void _debouncedSourceScan() {
    _sourceScanTimer?.cancel();
    _sourceScanTimer = Timer(const Duration(milliseconds: 500), () {
      _scanImages();
    });
  }

  void _debouncedOutputScan() {
    _outputScanTimer?.cancel();
    _outputScanTimer = Timer(const Duration(milliseconds: 500), () {
      _scanProcessedImages();
    });
  }

  Future<void> addBaseDirectory(String path) async {
    if (!sourceDirectories.contains(path)) {
      sourceDirectories.add(path);
      activeSourceDirectories.add(path);
      await _db.addSourceDirectory(path);
      _log('Added base directory: $path');
      _scanImages();
      _setupSourceWatchers(); 
      notifyListeners();
    }
  }

  Future<void> removeBaseDirectory(String path) async {
    if (sourceDirectories.contains(path)) {
      sourceDirectories.remove(path);
      activeSourceDirectories.removeWhere((p) => p.startsWith(path));
      await _db.removeSourceDirectory(path);
      _log('Removed base directory: $path');
      _scanImages();
      _setupSourceWatchers();
      notifyListeners();
    }
  }

  Future<void> toggleDirectory(String path) async {
    bool isSelected;
    if (activeSourceDirectories.contains(path)) {
      activeSourceDirectories.remove(path);
      isSelected = false;
      _log('Deselected directory: $path');
    } else {
      activeSourceDirectories.add(path);
      isSelected = true;
      _log('Selected directory: $path');
    }
    await _db.updateDirectorySelection(path, isSelected);
    _scanImages();
    _setupSourceWatchers();
    notifyListeners();
  }

  Future<void> refreshImages() async {
    _log('Manually refreshing images...');
    _refreshCounter++;
    await _scanImages();
    await _scanProcessedImages();
    if (viewMode == GalleryViewMode.folder && viewSourcePath != null) {
      await _scanFolder(viewSourcePath!);
    }
    notifyListeners();
  }

  void _evictImages(List<String> paths) {
    for (var path in paths) {
      PaintingBinding.instance.imageCache.evict(FileImage(File(path)));
    }
  }

  Future<void> _scanFolder(String path) async {
    final List<String> paths = await compute(_scanImagesIsolate, [path]);
    _evictImages(paths); // Ensure edited images are re-loaded from disk
    folderImages = paths.map((p) => AppImage.fromFile(File(p))).toList();
    notifyListeners();
  }

  Future<void> _scanImages() async {
    final newUnreachable = <String>{};
    for (var path in sourceDirectories) {
      if (isPathUnreachable(path)) {
        newUnreachable.add(path);
      }
    }
    unreachableDirectories = newUnreachable;

    if (activeSourceDirectories.isEmpty) {
      galleryImages = [];
      notifyListeners();
      return;
    }

    final List<String> paths = await compute(_scanImagesIsolate, activeSourceDirectories);
    _evictImages(paths);
    galleryImages = paths.map((p) => AppImage.fromFile(File(p))).toList();
    
    final validSelection = selectedImages.where((selected) => 
      galleryImages.any((img) => img.path == selected.path) ||
      processedImages.any((img) => img.path == selected.path) ||
      droppedImages.any((img) => img.path == selected.path)
    ).toList();
    
    if (validSelection.length != selectedImages.length) {
      selectedImages = validSelection;
    }
    notifyListeners();
  }

  Future<void> _scanProcessedImages() async {
    if (outputDirectory == null || outputDirectory!.isEmpty) {
      processedImages = [];
      notifyListeners();
      return;
    }

    try {
      final List<String> paths = await compute(_scanImagesIsolate, [outputDirectory!]);
      _evictImages(paths);
      List<File> files = paths.map((p) => File(p)).toList();
      
      files.sort((a, b) {
        try {
          return b.lastModifiedSync().compareTo(a.lastModifiedSync());
        } catch (e) {
          return 0;
        }
      });
      processedImages = files.map((f) => AppImage.fromFile(f)).toList();
      
      // Also clean up selection if images were deleted from disk
      final validSelection = selectedImages.where((selected) => 
        galleryImages.any((img) => img.path == selected.path) ||
        processedImages.any((img) => img.path == selected.path) ||
        droppedImages.any((img) => img.path == selected.path)
      ).toList();
      
      if (validSelection.length != selectedImages.length) {
        selectedImages = validSelection;
      }
    } catch (e) {
      processedImages = [];
    }
    notifyListeners();
  }

  void addDroppedFiles(List<AppImage> files) {
    for (var file in files) {
      if (!droppedImages.any((img) => img.path == file.path)) {
        droppedImages.add(file);
      }
    }
    notifyListeners();
  }

  void clearDroppedImages() {
    droppedImages.clear();
    // Also remove from selection if they were selected and are not in other collections
    final validSelection = selectedImages.where((s) => 
      galleryImages.any((g) => g.path == s.path) ||
      processedImages.any((p) => p.path == s.path)
    ).toList();
    
    if (validSelection.length != selectedImages.length) {
      selectedImages = validSelection;
    }
    notifyListeners();
  }

  void toggleImageSelection(AppImage image) {
    final newList = List<AppImage>.from(selectedImages);
    final index = newList.indexWhere((img) => img.path == image.path);
    if (index != -1) {
      newList.removeAt(index);
    } else {
      newList.add(image);
    }
    selectedImages = newList;
    notifyListeners();
  }

  void reorderSelectedImages(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final newList = List<AppImage>.from(selectedImages);
    final AppImage item = newList.removeAt(oldIndex);
    newList.insert(newIndex, item);
    selectedImages = newList;
    notifyListeners();
  }

  void clearImageSelection() {
    selectedImages = [];
    notifyListeners();
  }

  void selectAllImages() {
    // Select all from current active collections? 
    // Usually it's better to select from the currently visible list, 
    // but the state doesn't know what's visible (Tab index).
    // For now, let's select from galleryImages.
    selectedImages = List<AppImage>.from(galleryImages);
    notifyListeners();
  }

  Future<void> setThumbnailSize(double size) async {
    thumbnailSize = size;
    await _db.saveSetting('thumbnail_size', size.toString());
    notifyListeners();
  }

  Future<void> setImagePrefix(String prefix) async {
    imagePrefix = prefix;
    await _db.saveSetting('image_prefix', prefix);
    notifyListeners();
  }

  Future<void> updateOutputDirectory(String path) async {
    outputDirectory = path;
    await _db.saveSetting('output_directory', path);
    _setupOutputWatcher();
    _scanProcessedImages();
    notifyListeners();
  }

  void setViewMode(GalleryViewMode mode) {
    viewMode = mode;
    viewSourcePath = null;
    notifyListeners();
  }

  void setViewFolder(String path) {
    viewMode = GalleryViewMode.folder;
    viewSourcePath = path;
    _scanFolder(path);
    notifyListeners();
  }

  List<AppImage> get currentViewImages {
    switch (viewMode) {
      case GalleryViewMode.all: return galleryImages;
      case GalleryViewMode.processed: return processedImages;
      case GalleryViewMode.temp: return droppedImages;
      case GalleryViewMode.folder: return folderImages;
    }
  }

  bool isPathUnreachable(String? path) => FilePermissionService().isPathUnreachable(path);
}