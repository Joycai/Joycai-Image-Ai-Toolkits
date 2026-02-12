import 'dart:async';

import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../l10n/app_localizations.dart';
import '../models/app_file.dart';
import '../models/fee_group.dart';
import '../models/llm_channel.dart';
import '../models/llm_model.dart';
import '../models/log_entry.dart';
import '../models/prompt.dart';
import '../models/tag.dart';
import '../services/database_service.dart';
import '../services/llm/llm_service.dart';
import '../services/notification_service.dart';
import '../services/task_queue_service.dart';
import '../services/web_scraper_service.dart';
import 'browser_state.dart';
import 'downloader_state.dart';
import 'gallery_state.dart';
import 'window_state.dart';

enum SidebarMode {
  directories,
  preview,
  comparator,
  maskEditor,
}

class AppState extends ChangeNotifier {
  static final AppState _instance = AppState._internal();
  factory AppState() => _instance;

  final DatabaseService _db = DatabaseService();
  final TaskQueueService taskQueue = TaskQueueService();
  final GalleryState galleryState = GalleryState();
  final DownloaderState downloaderState = DownloaderState();
  final BrowserState browserState = BrowserState();
  final WindowState windowState = WindowState();

  AppState._internal() {
    taskQueue.addListener(notifyListeners);
    galleryState.addListener(notifyListeners);
    downloaderState.addListener(notifyListeners);
    browserState.addListener(notifyListeners);
    windowState.addListener(notifyListeners);
    
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
  int retryCount = 0;
  bool notificationsEnabled = true;
  bool isConsoleExpanded = false;
  bool isSidebarExpanded = true;
  SidebarMode sidebarMode = SidebarMode.directories;
  double sidebarWidth = 280.0;
  bool enableApiDebug = false;

  // Navigation State
  int activeScreenIndex = 0;
  int workbenchTabIndex = 0;

  // Theme configuration
  ThemeMode themeMode = ThemeMode.system;
  Color themeSeedColor = Colors.blueGrey;
  
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
  List<LLMModel> _models = [];
  List<LLMChannel> _channels = [];
  List<FeeGroup> _feeGroups = [];

  List<LLMModel> get allModels => _models;
  List<LLMChannel> get allChannels => _channels;
  List<FeeGroup> get allFeeGroups => _feeGroups;

  List<LLMModel> get imageModels => _models.where((m) => 
    m.tag == ModelTag.image.value || m.tag == ModelTag.multimodal.value
  ).toList();

  List<LLMModel> get chatModels => _models.where((m) =>
      m.tag == ModelTag.chat.value || m.tag == ModelTag.multimodal.value
  ).toList();

  Future<int> getDownloaderCacheSize() async {
    return await WebScraperService().getCacheSize();
  }

  Future<void> clearDownloaderCache() async {
    await WebScraperService().clearCache();
    notifyListeners();
  }

  List<LLMModel> getModelsForChannel(int? channelId) {
    if (channelId == null) return [];
    return _models.where((m) => m.channelId == channelId).toList();
  }

  @override
  void dispose() {
    galleryState.dispose();
    browserState.dispose();
    taskQueue.removeListener(notifyListeners);
    galleryState.removeListener(notifyListeners);
    downloaderState.removeListener(notifyListeners);
    browserState.removeListener(notifyListeners);
    windowState.removeListener(notifyListeners);
    super.dispose();
  }

  // Proxies for Gallery State
  List<AppFile> get galleryImages => galleryState.galleryImages;
  List<AppFile> get processedImages => galleryState.processedImages;
  List<AppFile> get selectedImages => galleryState.selectedImages;
  List<AppFile> get droppedImages => galleryState.droppedImages;
  
  String? get outputDirectory => galleryState.outputDirectory;
  String get imagePrefix => galleryState.imagePrefix;
  double get thumbnailSize => galleryState.thumbnailSize;
  List<String> get sourceDirectories => galleryState.sourceDirectories;
  List<String> get activeSourceDirectories => galleryState.activeSourceDirectories;

  Future<void> updateOutputDirectory(String path) => galleryState.updateOutputDirectory(path);
  Future<void> setImagePrefix(String prefix) => galleryState.setImagePrefix(prefix);
  void clearImageSelection() => galleryState.clearImageSelection();
  void toggleImageSelection(AppFile image) => galleryState.toggleImageSelection(image);
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

    final savedRetry = await _db.getSetting('retry_count');
    if (savedRetry != null) {
      retryCount = int.tryParse(savedRetry) ?? 0;
    }

    notificationsEnabled = (await _db.getSetting('notifications_enabled') ?? 'true') == 'true';
    isConsoleExpanded = (await _db.getSetting('is_console_expanded') ?? 'false') == 'true';
    isSidebarExpanded = (await _db.getSetting('is_sidebar_expanded') ?? 'true') == 'true';
    
    final savedSidebarWidth = await _db.getSetting('sidebar_width');
    if (savedSidebarWidth != null) {
      sidebarWidth = double.tryParse(savedSidebarWidth) ?? 280.0;
    }

    final savedSidebarMode = await _db.getSetting('sidebar_mode');
    if (savedSidebarMode != null) {
      sidebarMode = SidebarMode.values.firstWhere(
        (e) => e.name == savedSidebarMode, 
        orElse: () => SidebarMode.directories
      );
    }

    enableApiDebug = (await _db.getSetting('enable_api_debug') ?? 'false') == 'true';

    // Load theme mode
    final savedTheme = await _db.getSetting('theme_mode');
    if (savedTheme != null) {
      themeMode = ThemeMode.values.firstWhere((e) => e.name == savedTheme, orElse: () => ThemeMode.system);
    }

    final savedSeed = await _db.getSetting('theme_seed_color');
    if (savedSeed != null) {
      try {
        themeSeedColor = Color(int.parse(savedSeed));
      } catch (_) {}
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
    
    final savedWorkbenchTab = await _db.getSetting('workbench_tab_index');
    if (savedWorkbenchTab != null) {
      workbenchTabIndex = (int.tryParse(savedWorkbenchTab) ?? 0).clamp(0, 2);
    }
    
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
    
    // Maintain maximum log size
    if (logs.length > 1000) {
      logs.removeRange(0, logs.length - 1000);
    }
    
    notifyListeners();
  }

  void clearLogs() {
    logs.clear();
    notifyListeners();
  }

  Future<void> setConcurrency(int limit) async {
    concurrencyLimit = limit;
    taskQueue.updateConcurrency(limit);
    await _db.saveSetting('concurrency_limit', limit.toString());
    addLog('Concurrency limit set to $limit');
    notifyListeners();
  }

  Future<void> setRetryCount(int count) async {
    retryCount = count;
    await _db.saveSetting('retry_count', count.toString());
    addLog('Retry count set to $count');
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    await _db.saveSetting('theme_mode', mode.name);
    notifyListeners();
  }

  Future<void> setThemeSeedColor(Color color) async {
    themeSeedColor = color;
    await _db.saveSetting('theme_seed_color', color.toARGB32().toString());
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

  Future<void> setSidebarExpanded(bool value) async {
    isSidebarExpanded = value;
    await _db.saveSetting('is_sidebar_expanded', value.toString());
    notifyListeners();
  }

  Future<void> setSidebarMode(SidebarMode mode) async {
    sidebarMode = mode;
    await _db.saveSetting('sidebar_mode', mode.name);
    notifyListeners();
  }

  Timer? _sidebarWidthSaveTimer;

  Future<void> setSidebarWidth(double width) async {
    sidebarWidth = width.clamp(200.0, 800.0);
    notifyListeners();

    _sidebarWidthSaveTimer?.cancel();
    _sidebarWidthSaveTimer = Timer(const Duration(milliseconds: 500), () async {
      await _db.saveSetting('sidebar_width', sidebarWidth.toString());
    });
  }
  
  void navigateToScreen(int index) {
    activeScreenIndex = index;
    notifyListeners();
  }

  void setWorkbenchTab(int index) {
    workbenchTabIndex = index.clamp(0, 2);
    _db.saveSetting('workbench_tab_index', workbenchTabIndex.toString());
    notifyListeners();
  }
  
  Future<void> setLocale(Locale? newLocale) async {
    locale = newLocale;
    await _db.saveSetting('locale', newLocale?.languageCode ?? '');
    notifyListeners();
  }

  Future<void> setEnableApiDebug(bool value) async {
    enableApiDebug = value;
    await _db.saveSetting('enable_api_debug', value.toString());
    notifyListeners();
  }

  // Prompt Tags Methods
  Future<List<PromptTag>> getPromptTags() => _db.getPromptTags();
  Future<int> addPromptTag(Map<String, dynamic> tag) async {
    final id = await _db.addPromptTag(tag);
    notifyListeners();
    return id;
  }
  Future<void> updatePromptTag(int id, Map<String, dynamic> tag) async {
    await _db.updatePromptTag(id, tag);
    notifyListeners();
  }
  Future<void> deletePromptTag(int id) async {
    await _db.deletePromptTag(id);
    notifyListeners();
  }
  Future<void> updateTagOrder(List<int> ids) => _db.updateTagOrder(ids);

  // Prompts Methods
  Future<List<Prompt>> getPrompts() => _db.getPrompts();
  Future<int> addPrompt(Map<String, dynamic> prompt, {List<int>? tagIds}) async {
    final id = await _db.addPrompt(prompt, tagIds: tagIds);
    notifyListeners();
    return id;
  }
  Future<void> updatePrompt(int id, Map<String, dynamic> prompt, {List<int>? tagIds}) async {
    await _db.updatePrompt(id, prompt, tagIds: tagIds);
    notifyListeners();
  }
  Future<void> deletePrompt(int id) async {
    await _db.deletePrompt(id);
    notifyListeners();
  }
  Future<void> updatePromptOrder(List<int> ids) => _db.updatePromptOrder(ids);

  // System Prompts Methods
  Future<List<SystemPrompt>> getSystemPrompts({String? type}) => _db.getSystemPrompts(type: type);
  Future<int> addSystemPrompt(Map<String, dynamic> prompt, {List<int>? tagIds}) async {
    final id = await _db.addSystemPrompt(prompt, tagIds: tagIds);
    notifyListeners();
    return id;
  }
  Future<void> updateSystemPrompt(int id, Map<String, dynamic> prompt, {List<int>? tagIds}) async {
    await _db.updateSystemPrompt(id, prompt, tagIds: tagIds);
    notifyListeners();
  }
  Future<void> deleteSystemPrompt(int id) async {
    await _db.deleteSystemPrompt(id);
    notifyListeners();
  }
  Future<void> updateSystemPromptOrder(List<int> ids) => _db.updateSystemPromptOrder(ids);

  Future<void> importPromptData(Map<String, dynamic> data, {bool replace = false}) async {
    await _db.importPromptData(data, replace: replace);
    notifyListeners();
  }

  Future<void> restoreBackup(Map<String, dynamic> data) async {
    await _db.restoreBackup(data);
    await loadSettings();
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
    params['retryCount'] = retryCount;
    
    final imagePaths = galleryState.selectedImages.map((f) => f.path).toList();
    await taskQueue.addTask(imagePaths, modelIdentifier, params, modelIdDisplay: modelIdDisplay);
    
    addLog('Task submitted for ${imagePaths.length} images.');
  }
}
