import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/log_entry.dart';
import '../services/database_service.dart';
import '../services/llm/llm_service.dart';
import '../services/task_queue_service.dart';

class AppState extends ChangeNotifier {
  final DatabaseService _db = DatabaseService();
  final TaskQueueService taskQueue = TaskQueueService();

  List<String> baseDirectories = [];
  List<String> selectedDirectories = [];
  List<File> galleryImages = [];
  List<File> processedImages = [];
  List<File> selectedImages = [];
  List<LogEntry> logs = [];
  bool isProcessing = false;
  bool settingsLoaded = false;
  int concurrencyLimit = 2;
  String? outputDirectory;

  // Theme configuration
  ThemeMode themeMode = ThemeMode.system;
  
  // Language configuration
  Locale? locale;

  // Gallery configuration
  double thumbnailSize = 150.0;

  // Workbench configurations
  String? lastSelectedModelId;
  String lastAspectRatio = "not_set";
  String lastResolution = "1K";
  String lastPrompt = "";

  // Directory watchers
  final Map<String, StreamSubscription> _watchers = {};
  StreamSubscription? _outputWatcher;

  AppState() {
    _loadSettings();
    
    taskQueue.onTaskCompleted = (file) {
      _scanProcessedImages();
    };
    
    taskQueue.onLogAdded = (msg, {level = 'INFO', taskId}) {
      addLog(msg, level: level, taskId: taskId);
    };

    LLMService().onLogAdded = (msg, {level = 'INFO', contextId}) {
      addLog(msg, level: level, taskId: contextId);
    };

    taskQueue.addListener(() {
      isProcessing = taskQueue.runningCount > 0;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    for (var sub in _watchers.values) {
      sub.cancel();
    }
    _outputWatcher?.cancel();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    addLog('Loading settings from database...');
    
    final savedLimit = await _db.getSetting('concurrency_limit');
    if (savedLimit != null) {
      concurrencyLimit = int.tryParse(savedLimit) ?? 2;
      taskQueue.updateConcurrency(concurrencyLimit);
    }

    // Load theme mode
    final savedTheme = await _db.getSetting('theme_mode');
    if (savedTheme != null) {
      themeMode = ThemeMode.values.firstWhere((e) => e.name == savedTheme, orElse: () => ThemeMode.system);
    }
    
    // Load locale
    final savedLocale = await _db.getSetting('locale');
    if (savedLocale != null && savedLocale.isNotEmpty) {
      locale = Locale(savedLocale);
    }

    // Load thumbnail size
    final savedThumbSize = await _db.getSetting('thumbnail_size');
    if (savedThumbSize != null) {
      thumbnailSize = double.tryParse(savedThumbSize) ?? 150.0;
    }

    outputDirectory = await _db.getSetting('output_directory');
    _setupOutputWatcher();

    lastSelectedModelId = await _db.getSetting('last_model_id');
    lastAspectRatio = await _db.getSetting('last_aspect_ratio') ?? "not_set";
    lastResolution = await _db.getSetting('last_resolution') ?? "1K";
    lastPrompt = await _db.getSetting('last_prompt') ?? "";

    final dirs = await _db.getSourceDirectories();
    baseDirectories = dirs.map((d) => d['path'] as String).toList();
    selectedDirectories = dirs
        .where((d) => d['is_selected'] == 1)
        .map((d) => d['path'] as String)
        .toList();

    _scanImages();
    _scanProcessedImages();
    _setupSourceWatchers();
    
    settingsLoaded = true;
    notifyListeners();
  }

  void _setupSourceWatchers() {
    for (var sub in _watchers.values) {
      sub.cancel();
    }
    _watchers.clear();

    for (var path in selectedDirectories) {
      try {
        final dir = Directory(path);
        if (dir.existsSync()) {
          _watchers[path] = dir.watch().listen((event) {
            _scanImages();
          });
        }
      } catch (e) {
        addLog('Failed to watch directory $path: $e', level: 'ERROR');
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
            _scanProcessedImages();
          });
        }
      } catch (e) {
        addLog('Failed to watch output directory: $e', level: 'ERROR');
      }
    }
  }

  void addLog(String message, {String level = 'INFO', String? taskId}) {
    // If it's a streaming AI response, append to the last log if the last log was also an AI response AND task ID matches
    if (message.startsWith('[AI]: ') && logs.isNotEmpty && logs.last.message.startsWith('[AI]: ')) {
      final lastLog = logs.last;
      if (lastLog.taskId == taskId) {
        final newText = message.substring(6); // Remove the '[AI]: ' prefix
        logs[logs.length - 1] = LogEntry(
          timestamp: lastLog.timestamp,
          level: lastLog.level,
          message: lastLog.message + newText,
          taskId: taskId,
        );
        notifyListeners();
        return;
      }
    }
    
    logs.add(LogEntry(timestamp: DateTime.now(), level: level, message: message, taskId: taskId));
    notifyListeners();
  }

  Future<void> addBaseDirectory(String path) async {
    if (!baseDirectories.contains(path)) {
      baseDirectories.add(path);
      selectedDirectories.add(path);
      await _db.addSourceDirectory(path);
      addLog('Added base directory: $path');
      _scanImages();
      notifyListeners();
    }
  }

  Future<void> removeBaseDirectory(String path) async {
    if (baseDirectories.contains(path)) {
      baseDirectories.remove(path);
      selectedDirectories.remove(path);
      await _db.removeSourceDirectory(path);
      addLog('Removed base directory: $path');
      _scanImages();
      notifyListeners();
    }
  }

  Future<void> toggleDirectory(String path) async {
    bool isSelected;
    if (selectedDirectories.contains(path)) {
      selectedDirectories.remove(path);
      isSelected = false;
      addLog('Deselected directory: $path');
    } else {
      selectedDirectories.add(path);
      isSelected = true;
      addLog('Selected directory: $path');
    }
    await _db.updateDirectorySelection(path, isSelected);
    _scanImages();
    notifyListeners();
  }

  Future<void> refreshImages() async {
    addLog('Manually refreshing images...');
    await _scanImages();
    await _scanProcessedImages();
  }

  Future<void> _scanImages() async {
    if (selectedDirectories.isEmpty) {
      galleryImages = [];
      notifyListeners();
      return;
    }

    List<File> newImages = [];
    for (var path in selectedDirectories) {
      try {
        final dir = Directory(path);
        if (await dir.exists()) {
          await for (var file in dir.list(recursive: false)) {
            if (file is File && _isImageFile(file.path)) {
              newImages.add(file);
            }
          }
        }
      } catch (e) {
        // Silent fail
      }
    }

    galleryImages = newImages;
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
      final dir = Directory(outputDirectory!);
      if (await dir.exists()) {
        List<File> results = [];
        await for (var file in dir.list(recursive: false)) {
          if (file is File && _isImageFile(file.path)) {
            results.add(file);
          }
        }
        results.sort((a, b) {
          try {
            return b.lastModifiedSync().compareTo(a.lastModifiedSync());
          } catch (e) {
            return 0;
          }
        });
        processedImages = results;
      } else {
        processedImages = [];
      }
    } catch (e) {
      processedImages = [];
    }
    notifyListeners();
  }

  bool _isImageFile(String path) {
    final ext = path.toLowerCase();
    return ext.endsWith('.jpg') || 
           ext.endsWith('.jpeg') || 
           ext.endsWith('.png') || 
           ext.endsWith('.webp') || 
           ext.endsWith('.bmp');
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
    selectedImages = List.from(galleryImages);
    notifyListeners();
  }

  Future<void> setConcurrency(int limit) async {
    concurrencyLimit = limit;
    taskQueue.updateConcurrency(limit);
    await _db.saveSetting('concurrency_limit', limit.toString());
    addLog('Concurrency limit set to $limit');
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    await _db.saveSetting('theme_mode', mode.name);
    notifyListeners();
  }
  
  Future<void> setLocale(Locale? newLocale) async {
    locale = newLocale;
    await _db.saveSetting('locale', newLocale?.languageCode ?? '');
    notifyListeners();
  }

  Future<void> setThumbnailSize(double size) async {
    thumbnailSize = size;
    await _db.saveSetting('thumbnail_size', size.toString());
    notifyListeners();
  }

  Future<void> updateOutputDirectory(String path) async {
    outputDirectory = path;
    await _db.saveSetting('output_directory', path);
    _setupOutputWatcher();
    _scanProcessedImages();
    notifyListeners();
  }

  Future<void> updateWorkbenchConfig({
    String? modelId,
    String? aspectRatio,
    String? resolution,
    String? prompt,
  }) async {
    if (modelId != null) {
      lastSelectedModelId = modelId;
      await _db.saveSetting('last_model_id', modelId);
    }
    if (aspectRatio != null) {
      lastAspectRatio = aspectRatio;
      await _db.saveSetting('last_aspect_ratio', aspectRatio);
    }
    if (resolution != null) {
      lastResolution = resolution;
      await _db.saveSetting('last_resolution', resolution);
    }
    if (prompt != null) {
      lastPrompt = prompt;
      await _db.saveSetting('last_prompt', prompt);
    }
    notifyListeners();
  }

  void submitTask(dynamic modelIdentifier, Map<String, dynamic> params, {String? modelIdDisplay}) {
    final prompt = params['prompt'] as String? ?? '';
    if (prompt.isEmpty && selectedImages.isEmpty) return;
    
    final imagePaths = selectedImages.map((f) => f.path).toList();
    taskQueue.addTask(imagePaths, modelIdentifier, params, modelIdDisplay: modelIdDisplay);
    
    addLog('Task submitted for ${imagePaths.length} images.');
  }
}
