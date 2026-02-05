import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
// import 'package:flutter/material.dart'; // Unnecessary

import '../core/constants.dart';
import '../services/database_service.dart';

/// Top-level function for background disk scanning to keep UI smooth.
List<String> _scanImagesIsolate(List<String> paths) {
  List<String> results = [];
  for (var path in paths) {
    try {
      final dir = Directory(path);
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

class GalleryState extends ChangeNotifier {
  final DatabaseService _db = DatabaseService();
  
  List<String> sourceDirectories = [];
  List<String> activeSourceDirectories = [];
  List<File> galleryImages = [];
  List<File> processedImages = [];
  List<File> selectedImages = [];
  
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
      _setupSourceWatchers(); // Re-setup watchers to include new dir
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
    // Watchers are based on activeSourceDirectories, so refresh them
    _setupSourceWatchers();
    notifyListeners();
  }

  Future<void> refreshImages() async {
    _log('Manually refreshing images...');
    await _scanImages();
    await _scanProcessedImages();
  }

  Future<void> _scanImages() async {
    if (activeSourceDirectories.isEmpty) {
      galleryImages = [];
      notifyListeners();
      return;
    }

    final List<String> paths = await compute(_scanImagesIsolate, activeSourceDirectories);
    galleryImages = paths.map((p) => File(p)).toList();
    
    selectedImages.removeWhere((selected) => 
      !galleryImages.any((img) => img.path == selected.path)
    );
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
      List<File> results = paths.map((p) => File(p)).toList();
      
      results.sort((a, b) {
        try {
          return b.lastModifiedSync().compareTo(a.lastModifiedSync());
        } catch (e) {
          return 0;
        }
      });
      processedImages = results;
    } catch (e) {
      processedImages = [];
    }
    notifyListeners();
  }

  void toggleImageSelection(File image) {
    final index = selectedImages.indexWhere((img) => img.path == image.path);
    if (index != -1) {
      selectedImages.removeAt(index);
    } else {
      selectedImages.add(image);
    }
    notifyListeners();
  }

  void clearImageSelection() {
    selectedImages.clear();
    notifyListeners();
  }

  void selectAllImages() {
    selectedImages.addAll(galleryImages);
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
}
