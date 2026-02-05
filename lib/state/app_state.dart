import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/log_entry.dart';
import '../services/database_service.dart';
import '../services/llm/llm_service.dart';
import '../services/task_queue_service.dart';
import 'gallery_state.dart';

class AppState extends ChangeNotifier {
  final DatabaseService _db = DatabaseService();
  final TaskQueueService taskQueue = TaskQueueService();
  final GalleryState galleryState = GalleryState();

  List<LogEntry> logs = [];
  bool isProcessing = false;
  bool settingsLoaded = false;
  bool setupCompleted = true; 
  int concurrencyLimit = 2;

  // Theme configuration
  ThemeMode themeMode = ThemeMode.system;
  
  // Language configuration
  Locale? locale;

  // Workbench configurations
  String? lastSelectedModelId;
  String lastAspectRatio = "not_set";
  String lastResolution = "1K";
  String lastPrompt = "";

  AppState() {
    _loadSettings();
    
    // Wire up logs
    galleryState.onLog = (msg, {level = 'INFO'}) {
      addLog(msg, level: level);
    };

    taskQueue.onTaskCompleted = (file) {
      galleryState.refreshImages();
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
    
    // Propagate gallery changes
    galleryState.addListener(notifyListeners);
  }

  @override
  void dispose() {
    galleryState.dispose();
    super.dispose();
  }

  // Proxies for Gallery State (for backward compatibility if needed, or consumers should access galleryState directly)
  List<File> get galleryImages => galleryState.galleryImages;
  List<File> get processedImages => galleryState.processedImages;
  List<File> get selectedImages => galleryState.selectedImages;
  String? get outputDirectory => galleryState.outputDirectory;
  String get imagePrefix => galleryState.imagePrefix;
  double get thumbnailSize => galleryState.thumbnailSize;
  List<String> get sourceDirectories => galleryState.sourceDirectories;
  List<String> get activeSourceDirectories => galleryState.activeSourceDirectories;

  Future<void> updateOutputDirectory(String path) => galleryState.updateOutputDirectory(path);
  Future<void> setImagePrefix(String prefix) => galleryState.setImagePrefix(prefix);
  void clearImageSelection() => galleryState.clearImageSelection();
  void toggleImageSelection(File image) => galleryState.toggleImageSelection(image);
  Future<void> toggleDirectory(String path) => galleryState.toggleDirectory(path);
  Future<void> addBaseDirectory(String path) => galleryState.addBaseDirectory(path);
  Future<void> removeBaseDirectory(String path) => galleryState.removeBaseDirectory(path);
  Future<void> setThumbnailSize(double size) => galleryState.setThumbnailSize(size);
  Future<void> refreshImages() => galleryState.refreshImages();
  void selectAllImages() => galleryState.selectAllImages();

  Future<void> _loadSettings() async {
    addLog('Loading settings from database...');
    
    final setupVal = await _db.getSetting('setup_completed');
    setupCompleted = setupVal == 'true';

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

    lastSelectedModelId = await _db.getSetting('last_model_id');
    lastAspectRatio = await _db.getSetting('last_aspect_ratio') ?? "not_set";
    lastResolution = await _db.getSetting('last_resolution') ?? "1K";
    lastPrompt = await _db.getSetting('last_prompt') ?? "";
    
    settingsLoaded = true;
    notifyListeners();
  }

  Future<void> completeSetup() async {
    setupCompleted = true;
    await _db.saveSetting('setup_completed', 'true');
    notifyListeners();
  }

  void addLog(String message, {String level = 'INFO', String? taskId}) {
    if (message.startsWith('[AI]: ') && logs.isNotEmpty && logs.last.message.startsWith('[AI]: ')) {
      final lastLog = logs.last;
      if (lastLog.taskId == taskId) {
        final newText = message.substring(6); 
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

  Future<void> submitTask(dynamic modelIdentifier, Map<String, dynamic> params, {String? modelIdDisplay}) async {
    final prompt = params['prompt'] as String? ?? '';
    if (prompt.isEmpty && galleryState.selectedImages.isEmpty) return;
    
    params['imagePrefix'] = galleryState.imagePrefix;
    
    final imagePaths = galleryState.selectedImages.map((f) => f.path).toList();
    await taskQueue.addTask(imagePaths, modelIdentifier, params, modelIdDisplay: modelIdDisplay);
    
    addLog('Task submitted for ${imagePaths.length} images.');
  }
}
