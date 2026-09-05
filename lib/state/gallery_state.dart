import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/constants.dart';
import '../core/file_utils.dart';
import '../models/app_image.dart';
import '../services/database_service.dart';
import '../services/file_permission_service.dart';

/// Top-level function for background disk scanning to keep UI smooth.
///
/// Yields `path → [modifiedMsSinceEpoch, sizeBytes]` rather than a bare list of
/// paths, because both callers that want those numbers used to take them on the
/// UI thread. The result gallery sorted newest-first by calling
/// `lastModifiedSync()` *inside the comparator* — O(n log n) blocking stats, on
/// the order of twenty thousand syscalls for a thousand pictures, on the thread
/// that draws the frame. Reading them once here costs one stat per file and
/// happens off the UI isolate.
///
/// A map rather than a list of records: only primitives, lists and maps are
/// guaranteed to survive the [compute] hop. Insertion order is preserved, so
/// callers that want directory order still have it, and overlapping roots
/// dedupe for free.
Map<String, List<int>> _scanImagesIsolate(List<String> paths) {
  final Map<String, List<int>> results = {};
  for (var path in paths) {
    try {
      final dir = Directory(path);
      if (dir.existsSync()) {
        final entities = dir.listSync(recursive: false);
        for (var entity in entities) {
          try {
            if (entity is File && AppConstants.isSupportedFile(entity.path)) {
              final stat = entity.statSync();
              results[entity.path] = [
                stat.modified.millisecondsSinceEpoch,
                stat.size,
              ];
            }
          } catch (_) {
            // Ignore individual file access errors
          }
        }
      }
    } catch (_) {
      // Ignore directory access errors
    }
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
  bool folderViewIsResult = false; // Whether the browsed folder belongs to the result tree

  // Model-based image lists
  List<AppImage> galleryImages = [];
  List<AppImage> folderImages = [];
  List<AppImage> processedImages = [];
  List<AppImage> _selectedImages = [];
  Map<String, int> _selectionOrder = {};
  List<AppImage> droppedImages = []; // Transient workspace

  List<AppImage> get selectedImages => _selectedImages;

  /// Assigning a new selection list also rebuilds the position index so callers
  /// can test membership and read a picture's place in the selection in O(1),
  /// instead of scanning the list once per grid cell.
  set selectedImages(List<AppImage> value) {
    _selectedImages = value;
    _selectionOrder = {
      for (var i = 0; i < value.length; i++) value[i].path: i,
    };
  }

  /// O(1) selection membership check (avoids O(n) `selectedImages.any(...)`).
  bool isImageSelected(String path) => _selectionOrder.containsKey(path);

  /// Where [path] sits in the selection, counting from 1; `0` when it is not
  /// selected.
  ///
  /// Surfaced so a thumbnail can label itself with the same ordinal the
  /// reference-image strip uses. The order is not cosmetic: it is the order
  /// the pictures reach the model, and a prompt that says "use the second
  /// image's pose" is wrong the moment the two disagree.
  int selectionNumberOf(String path) => (_selectionOrder[path] ?? -1) + 1;
  
  String? outputDirectory;
  String? resultCacheDirectory;
  double thumbnailSize = 150.0;
  String imagePrefix = "result";

  /// Root directories of the result tree (dedup, non-empty): the configured
  /// output directory plus the platform result cache when it differs.
  List<String> get resultRootDirectories {
    final roots = <String>[];
    if (outputDirectory != null && outputDirectory!.isNotEmpty) roots.add(outputDirectory!);
    if (resultCacheDirectory != null &&
        resultCacheDirectory!.isNotEmpty &&
        resultCacheDirectory != outputDirectory) {
      roots.add(resultCacheDirectory!);
    }
    return roots;
  }

  // Directory watchers
  final Map<String, StreamSubscription> _watchers = {};
  StreamSubscription? _outputWatcher;
  Timer? _sourceScanTimer;
  Timer? _outputScanTimer;

  // Callback for logging to the main app log
  Function(String, {String level})? onLog;

  // Cached image grouping — recomputed only when the source list changes identity
  List<AppImage>? _lastGroupedList;
  Map<String, List<AppImage>> _cachedGrouped = {};
  Map<String, int> _cachedGlobalIndex = {};
  List<String> _cachedSortedPaths = [];

  /// Returns the grouped map for [images], using a cached result when the list
  /// has not changed since the last call (identity comparison).
  Map<String, List<AppImage>> getGrouped(List<AppImage> images) {
    if (!identical(images, _lastGroupedList)) {
      _rebuildGroupCache(images);
    }
    return _cachedGrouped;
  }

  Map<String, int> getGlobalIndex(List<AppImage> images) {
    if (!identical(images, _lastGroupedList)) {
      _rebuildGroupCache(images);
    }
    return _cachedGlobalIndex;
  }

  List<String> getSortedPaths(List<AppImage> images) {
    if (!identical(images, _lastGroupedList)) {
      _rebuildGroupCache(images);
    }
    return _cachedSortedPaths;
  }

  void _rebuildGroupCache(List<AppImage> images) {
    _lastGroupedList = images;
    _cachedGrouped = {};
    _cachedGlobalIndex = {};
    for (var i = 0; i < images.length; i++) {
      final img = images[i];
      final parent = File(img.path).parent.path;
      _cachedGrouped.putIfAbsent(parent, () => []).add(img);
      _cachedGlobalIndex[img.path] = i;
    }
    _cachedSortedPaths = _cachedGrouped.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  bool isScanning = false;

  int _refreshCounter = 0;
  int get refreshCounter => _refreshCounter;

  GalleryState() {
    reloadSettings();
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

  Future<void> reloadSettings() async {
    final savedThumbSize = await _db.getSetting('thumbnail_size');
    if (savedThumbSize != null) {
      thumbnailSize = double.tryParse(savedThumbSize) ?? 150.0;
    }

    imagePrefix = await _db.getSetting('image_prefix') ?? "result";
    outputDirectory = await _db.getSetting('output_directory');

    // Result Cache initialization (Fallback for sandboxed environments like iOS/macOS)
    if (Platform.isIOS || Platform.isMacOS) {
      final cacheDir = await getTemporaryDirectory();
      resultCacheDirectory = p.join(cacheDir.path, 'result_cache');
      final dir = Directory(resultCacheDirectory!);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      
      await _db.saveSetting('result_cache_directory', resultCacheDirectory!);
      
      // On iOS, we also treat this as the primary output if not set
      if (Platform.isIOS && (outputDirectory == null || outputDirectory!.isEmpty)) {
        outputDirectory = resultCacheDirectory;
        await _db.saveSetting('output_directory', outputDirectory!);
      }
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

  /// Follows a folder that the file browser renamed or moved, when the
  /// workbench had registered it (or something inside it) as a source or as
  /// the output directory. Otherwise that registration would turn
  /// "unreachable" the moment the browser finished.
  Future<void> rewritePathPrefix(String from, String to) async {
    var changed = false;
    final sources = <String>[];
    for (final path in sourceDirectories) {
      final moved = FileUtils.rebasePath(path, from: from, to: to);
      if (moved != null) {
        await _db.renameSourceDirectory(path, moved);
        changed = true;
      }
      sources.add(moved ?? path);
    }
    final active = [
      for (final path in activeSourceDirectories)
        FileUtils.rebasePath(path, from: from, to: to) ?? path,
    ];

    final output = outputDirectory == null
        ? null
        : FileUtils.rebasePath(outputDirectory!, from: from, to: to);
    if (output != null) {
      outputDirectory = output;
      await _db.saveSetting('output_directory', output);
      _setupOutputWatcher();
      changed = true;
    }
    if (!changed) return;

    sourceDirectories = sources;
    activeSourceDirectories = active;
    _log('Followed folder change: $from -> $to');
    _scanImages();
    _scanProcessedImages();
    _setupSourceWatchers();
    notifyListeners();
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
    isScanning = true;
    notifyListeners();
    _log('Manually refreshing images...');
    _refreshCounter++;
    await _scanImages();
    await _scanProcessedImages();
    
    // Verify droppedImages (Temporary Workspace)
    final List<AppImage> existingDropped = [];
    for (var img in droppedImages) {
      if (await File(img.path).exists()) {
        existingDropped.add(img);
      }
    }
    if (existingDropped.length != droppedImages.length) {
      droppedImages = existingDropped;
    }

    if (viewMode == GalleryViewMode.folder && viewSourcePath != null) {
      await _scanFolder(viewSourcePath!);
    }

    _cleanupSelection();
    isScanning = false;
    notifyListeners();
  }

  void _cleanupSelection() {
    final validSelection = selectedImages.where((selected) => 
      galleryImages.any((img) => img.path == selected.path) ||
      processedImages.any((img) => img.path == selected.path) ||
      droppedImages.any((img) => img.path == selected.path) ||
      folderImages.any((img) => img.path == selected.path)
    ).toList();
    
    if (validSelection.length != selectedImages.length) {
      selectedImages = validSelection;
    }
  }

  /// `[modifiedMs, size]` per path, as of the last scan that covered it.
  final Map<String, List<int>> _fingerprints = {};

  /// Drops the decoded bitmap of every file that actually changed on disk.
  ///
  /// The crop and mask tools overwrite the original, which leaves the path — and
  /// therefore the image cache key — untouched, so without this the cache keeps
  /// serving the picture from before the edit. What it used to do was evict
  /// *every* scanned path on *every* scan, and the scans are driven by directory
  /// watchers: a batch writing its results made the output watcher fire twice a
  /// second, and each time the whole gallery's decoded bitmaps were thrown away
  /// and immediately decoded again.
  ///
  /// [roots] is the set of directories [scanned] covers, used to forget files
  /// that have since left them so this map tracks the disk instead of growing
  /// for the life of the process.
  void _evictChanged(List<String> roots, Map<String, List<int>> scanned) {
    final rootSet = roots.toSet();
    _fingerprints.removeWhere((path, _) =>
        rootSet.contains(p.dirname(path)) && !scanned.containsKey(path));

    scanned.forEach((path, current) {
      final previous = _fingerprints[path];
      if (previous == null) {
        // First sighting — nothing can be cached under this path yet.
        _fingerprints[path] = current;
      } else if (previous[0] != current[0] || previous[1] != current[1]) {
        PaintingBinding.instance.imageCache.evict(FileImage(File(path)));
        _fingerprints[path] = current;
      }
    });
  }

  Future<void> _scanFolder(String path) async {
    _refreshReachability([path]);
    final scanned = await compute(_scanImagesIsolate, [path]);
    _evictChanged([path], scanned);
    folderImages = scanned.keys.map((p) => AppImage.fromFile(File(p))).toList();
    notifyListeners();
  }

  Future<void> _scanImages() async {
    _refreshReachability(sourceDirectories);
    unreachableDirectories = {
      for (final path in sourceDirectories)
        if (isPathUnreachable(path)) path,
    };

    if (activeSourceDirectories.isEmpty) {
      galleryImages = [];
      notifyListeners();
      return;
    }

    final scanned = await compute(_scanImagesIsolate, activeSourceDirectories);
    _evictChanged(activeSourceDirectories, scanned);
    galleryImages = scanned.keys.map((p) => AppImage.fromFile(File(p))).toList();
    notifyListeners();
  }

  Future<void> _scanProcessedImages() async {
    final List<String> scanPaths = [];
    if (outputDirectory != null && outputDirectory!.isNotEmpty) scanPaths.add(outputDirectory!);
    if (resultCacheDirectory != null && resultCacheDirectory!.isNotEmpty && resultCacheDirectory != outputDirectory) {
      scanPaths.add(resultCacheDirectory!);
    }

    if (scanPaths.isEmpty) {
      processedImages = [];
      notifyListeners();
      return;
    }

    _refreshReachability(scanPaths);

    try {
      // Overlapping roots dedupe on the way in — the isolate keys by path.
      final scanned = await compute(_scanImagesIsolate, scanPaths);
      _evictChanged(scanPaths, scanned);

      // Newest first, from the modification times the isolate already read.
      // This comparator used to call lastModifiedSync() on both sides of every
      // comparison, which put an O(n log n) pile of blocking stats on the UI
      // thread every time the output directory changed.
      final sorted = scanned.keys.toList()
        ..sort((a, b) => scanned[b]![0].compareTo(scanned[a]![0]));
      processedImages = sorted.map((p) => AppImage.fromFile(File(p))).toList();
    } catch (e) {
      processedImages = [];
    }
    notifyListeners();
  }

  void addDroppedFiles(List<AppImage> files) {
    final existingPaths = droppedImages.map((img) => img.path).toSet();
    final newFiles = files.where((file) => !existingPaths.contains(file.path));
    droppedImages = [...droppedImages, ...newFiles];
    notifyListeners();
  }

  /// Drops one picture out of the temporary workspace.
  ///
  /// The file is left alone: what the workspace holds is a reference, and the
  /// picture usually lives in a folder of the user's own. Deleting from disk
  /// is a separate action with its own confirmation.
  void removeDroppedImage(String path) {
    final remaining = droppedImages.where((img) => img.path != path).toList();
    if (remaining.length == droppedImages.length) return;
    droppedImages = remaining;
    _cleanupSelection();
    notifyListeners();
  }

  void clearDroppedImages() {
    droppedImages = [];
    _cleanupSelection();
    notifyListeners();
  }

  void toggleImageSelection(AppImage image) {
    if (AppConstants.isVideoFile(image.path)) return; // Prevent selecting videos
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
    // Select all from current active collections that are not videos
    selectedImages = galleryImages.where((img) => !AppConstants.isVideoFile(img.path)).toList();
    notifyListeners();
  }

  /// Resizes the grid, live. Deliberately does not touch the database.
  ///
  /// The size comes off a slider, so this is called on every frame of a drag.
  /// It used to write the setting each time, which put sixty SQLite writes
  /// through one gesture; the value is persisted once, by
  /// [persistThumbnailSize], when the drag ends.
  void setThumbnailSize(double size) {
    if (thumbnailSize == size) return;
    thumbnailSize = size;
    notifyListeners();
  }

  /// Writes the size the user settled on. Call from a slider's `onChangeEnd`.
  Future<void> persistThumbnailSize() =>
      _db.saveSetting('thumbnail_size', thumbnailSize.toString());

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
    folderViewIsResult = false;
    notifyListeners();
  }

  void setViewFolder(String path, {bool isResult = false}) {
    viewMode = GalleryViewMode.folder;
    viewSourcePath = path;
    folderViewIsResult = isResult;
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

  /// Whether the last scan that covered [path] could not read it.
  ///
  /// A lookup, not a probe. [FilePermissionService.isPathUnreachable] is an
  /// `existsSync` plus a blocking `listSync` of the whole directory — it has
  /// to be, since on the macOS sandbox a directory can exist and still refuse
  /// to be listed — and the gallery asks this question from its `build`
  /// method. Answering it live meant enumerating the output folder on the UI
  /// thread on every rebuild, so the cost of drawing a frame scaled with how
  /// many results the user had ever generated. The probe now runs once per
  /// scan, in [_refreshReachability], where a scan already is.
  bool isPathUnreachable(String? path) =>
      path != null && path.isNotEmpty && _unreachablePaths.contains(path);

  /// Paths the last scan could not read. See [isPathUnreachable].
  final Set<String> _unreachablePaths = {};

  /// Re-probes [paths] and folds the answers into [_unreachablePaths].
  void _refreshReachability(List<String> paths) {
    final permissions = FilePermissionService();
    for (final path in paths) {
      if (path.isEmpty) continue;
      if (permissions.isPathUnreachable(path)) {
        _unreachablePaths.add(path);
      } else {
        _unreachablePaths.remove(path);
      }
    }
  }
}