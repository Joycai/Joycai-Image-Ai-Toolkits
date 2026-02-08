import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../l10n/app_localizations.dart';
import '../models/log_entry.dart';
import '../services/database_service.dart';
import '../services/llm/llm_service.dart';
import '../services/notification_service.dart';
import '../services/task_queue_service.dart';
import '../services/web_scraper_service.dart';
import 'downloader_state.dart';
import 'gallery_state.dart';

class PreviewWindowState {
  final String id;
  final String imagePath;
  Offset position;
  Size size;

  PreviewWindowState({
    required this.id,
    required this.imagePath,
    this.position = const Offset(100, 100),
    this.size = const Size(400, 300),
  });
}

class AppState extends ChangeNotifier {
  final DatabaseService _db = DatabaseService();
  final TaskQueueService taskQueue = TaskQueueService();
  final GalleryState galleryState = GalleryState();
  final DownloaderState downloaderState = DownloaderState();

  final List<PreviewWindowState> floatingPreviews = [];

  void openFloatingPreview(String path) {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    // Offset each new window slightly
    final offset = Offset(
      100.0 + (floatingPreviews.length % 5) * 30,
      100.0 + (floatingPreviews.length % 5) * 30,
    );
    floatingPreviews.add(PreviewWindowState(id: id, imagePath: path, position: offset));
    notifyListeners();
  }

  void closeFloatingPreview(String id) {
    floatingPreviews.removeWhere((p) => p.id == id);
    notifyListeners();
  }

  void updateFloatingPreviewPosition(String id, Offset newPosition) {
    final index = floatingPreviews.indexWhere((p) => p.id == id);
    if (index != -1) {
      floatingPreviews[index].position = newPosition;
      notifyListeners();
    }
  }

  void updateFloatingPreviewSize(String id, Size newSize) {
    final index = floatingPreviews.indexWhere((p) => p.id == id);
    if (index != -1) {
      floatingPreviews[index].size = newSize;
      notifyListeners();
    }
  }

  AppState() {
    taskQueue.addListener(notifyListeners);
    galleryState.addListener(notifyListeners);
    downloaderState.addListener(notifyListeners);
    
    // Wire up logs
    galleryState.onLog = (msg, {level = 'INFO'}) {
      addLog(msg, level: level);
    };

    taskQueue.onTaskCompleted = (file) {
      galleryState.refreshImages();
    };

    taskQueue.onTaskFinished = (task) {
      if (!notificationsEnabled) return;
      
      final l10n = lookupAppLocalizations(locale ?? const Locale('en'));
      
      if (task.status == TaskStatus.completed) {
        NotificationService().showNotification(
          title: l10n.taskCompletedNotification,
          body: l10n.taskCompletedBody(task.id.substring(0, 8)),
        );
      } else if (task.status == TaskStatus.failed) {
        NotificationService().showNotification(
          title: l10n.taskFailedNotification,
          body: l10n.taskFailedBody(task.id.substring(0, 8)),
        );
      }
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

  List<LogEntry> logs = [];
  bool isProcessing = false;
  bool settingsLoaded = false;
  bool setupCompleted = true; 
  int concurrencyLimit = 2;
  bool notificationsEnabled = true;
  bool isConsoleExpanded = false;

  // Theme configuration
  ThemeMode themeMode = ThemeMode.system;
  
  // Language configuration
  Locale? locale;

  // Workbench configurations
  String? lastSelectedModelId;
  AppAspectRatio lastAspectRatio = AppAspectRatio.notSet;
  AppResolution lastResolution = AppResolution.r1K;
  String lastPrompt = "";
  bool isMarkdownWorkbench = true;
  bool isMarkdownRefinerSource = true;
  bool isMarkdownRefinerTarget = true;

  // Data cache
  List<Map<String, dynamic>> _models = [];
  List<Map<String, dynamic>> _channels = [];
  List<Map<String, dynamic>> _feeGroups = [];

  List<Map<String, dynamic>> get allModels => _models;
  List<Map<String, dynamic>> get allChannels => _channels;
  List<Map<String, dynamic>> get allFeeGroups => _feeGroups;

  List<Map<String, dynamic>> get imageModels => _models.where((m) => 
    m['tag'] == ModelTag.image.value || m['tag'] == ModelTag.multimodal.value
  ).toList();

  List<Map<String, dynamic>> get chatModels => _models.where((m) =>
      m['tag'] == ModelTag.chat.value || m['tag'] == ModelTag.multimodal.value
  ).toList();

  Future<int> getDownloaderCacheSize() async {
    return await WebScraperService().getCacheSize();
  }

  Future<void> clearDownloaderCache() async {
    await WebScraperService().clearCache();
    notifyListeners();
  }

  List<Map<String, dynamic>> getModelsForChannel(int? channelId) {
    if (channelId == null) return [];
    return _models.where((m) => m['channel_id'] == channelId).toList();
  }

  @override
  void dispose() {
    galleryState.dispose();
    taskQueue.removeListener(notifyListeners);
    galleryState.removeListener(notifyListeners);
    downloaderState.removeListener(notifyListeners);
    super.dispose();
  }

  // Proxies for Gallery State
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

  Future<String?> getSetting(String key) => _db.getSetting(key);

  Future<void> loadSettings() async {
    addLog('Loading settings from database...');
    
    final setupVal = await _db.getSetting('setup_completed');
    setupCompleted = setupVal == 'true';

    final savedLimit = await _db.getSetting('concurrency_limit');
    if (savedLimit != null) {
      concurrencyLimit = int.tryParse(savedLimit) ?? 2;
      taskQueue.updateConcurrency(concurrencyLimit);
    }

    notificationsEnabled = (await _db.getSetting('notifications_enabled') ?? 'true') == 'true';
    isConsoleExpanded = (await _db.getSetting('is_console_expanded') ?? 'false') == 'true';

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
    lastAspectRatio = AppAspectRatio.fromString(await _db.getSetting('last_aspect_ratio'));
    lastResolution = AppResolution.fromString(await _db.getSetting('last_resolution'));
    lastPrompt = await _db.getSetting('last_prompt') ?? "";
    
    isMarkdownWorkbench = (await _db.getSetting('is_markdown_workbench') ?? 'true') == 'true';
    isMarkdownRefinerSource = (await _db.getSetting('is_markdown_refiner_source') ?? 'true') == 'true';
    isMarkdownRefinerTarget = (await _db.getSetting('is_markdown_refiner_target') ?? 'true') == 'true';
    
    _models = await _db.getModels();
    _channels = await _db.getChannels();
    _feeGroups = await _db.getFeeGroups();
    
    await downloaderState.loadCookieHistory();

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

  Future<void> setNotificationsEnabled(bool value) async {
    notificationsEnabled = value;
    await _db.saveSetting('notifications_enabled', value.toString());
    notifyListeners();
  }

  Future<void> setConsoleExpanded(bool value) async {
    isConsoleExpanded = value;
    await _db.saveSetting('is_console_expanded', value.toString());
    notifyListeners();
  }
  
  Future<void> setLocale(Locale? newLocale) async {
    locale = newLocale;
    await _db.saveSetting('locale', newLocale?.languageCode ?? '');
    notifyListeners();
  }

  // Model, Channel & Fee Group Management
  Future<void> refreshDataCache() async {
    _models = await _db.getModels();
    _channels = await _db.getChannels();
    _feeGroups = await _db.getFeeGroups();
    notifyListeners();
  }

  Future<int> addChannel(Map<String, dynamic> channel) async {
    final id = await _db.addChannel(channel);
    await refreshDataCache();
    return id;
  }

  Future<void> updateChannel(int id, Map<String, dynamic> channel) async {
    await _db.updateChannel(id, channel);
    await refreshDataCache();
  }

  Future<void> deleteChannel(int id) async {
    await _db.deleteChannel(id);
    await refreshDataCache();
  }

  Future<int> addModel(Map<String, dynamic> model) async {
    final id = await _db.addModel(model);
    await refreshDataCache();
    return id;
  }

  Future<void> updateModel(int id, Map<String, dynamic> model) async {
    await _db.updateModel(id, model);
    await refreshDataCache();
  }

  Future<void> deleteModel(int id) async {
    await _db.deleteModel(id);
    await refreshDataCache();
  }

  Future<void> updateModelOrder(List<int> ids) async {
    await _db.updateModelOrder(ids);
    await refreshDataCache();
  }

  // Fee Group Management
  Future<int> addFeeGroup(Map<String, dynamic> group) async {
    final id = await _db.addFeeGroup(group);
    await refreshDataCache();
    return id;
  }

  Future<void> updateFeeGroup(int id, Map<String, dynamic> group) async {
    await _db.updateFeeGroup(id, group);
    await refreshDataCache();
  }

  Future<void> deleteFeeGroup(int id) async {
    await _db.deleteFeeGroup(id);
    await refreshDataCache();
  }

  Future<void> setIsMarkdownWorkbench(bool value) async {
    isMarkdownWorkbench = value;
    await _db.saveSetting('is_markdown_workbench', value.toString());
    notifyListeners();
  }

  Future<void> setIsMarkdownRefinerSource(bool value) async {
    isMarkdownRefinerSource = value;
    await _db.saveSetting('is_markdown_refiner_source', value.toString());
    notifyListeners();
  }

  Future<void> setIsMarkdownRefinerTarget(bool value) async {
    isMarkdownRefinerTarget = value;
    await _db.saveSetting('is_markdown_refiner_target', value.toString());
    notifyListeners();
  }

  Future<void> updateWorkbenchConfig({
    String? modelId,
    AppAspectRatio? aspectRatio,
    AppResolution? resolution,
    String? prompt,
  }) async {
    if (modelId != null) {
      lastSelectedModelId = modelId;
      await _db.saveSetting('last_model_id', modelId);
    }
    if (aspectRatio != null) {
      lastAspectRatio = aspectRatio;
      await _db.saveSetting('last_aspect_ratio', aspectRatio.value);
    }
    if (resolution != null) {
      lastResolution = resolution;
      await _db.saveSetting('last_resolution', resolution.value);
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