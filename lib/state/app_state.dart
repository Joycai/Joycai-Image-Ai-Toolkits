import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/safety_settings.dart';
import '../l10n/app_localizations.dart';
import '../services/llm/model_capabilities.dart';
import '../services/llm/model_descriptor.dart';
import '../services/llm/model_family.dart';
import '../services/llm/vendors/vendors.dart';
import '../models/app_image.dart';
import '../models/llm_channel.dart';
import '../models/llm_model.dart';
import '../models/pricing_group.dart';
import '../models/prompt.dart';
import '../models/prompt_history_entry.dart';
import '../models/tag.dart';
import '../services/database_service.dart';
import '../services/font_service.dart';
import '../services/llm/llm_service.dart';
import '../services/notification_service.dart';
import '../services/task_queue_service.dart';
import '../services/web_scraper_service.dart';
import 'downloader_state.dart';
import 'file_browser_state.dart';
import 'gallery_state.dart';
import 'log_state.dart';
import 'workbench_ui_state.dart';

part 'app_state_data.dart';
part 'app_state_workbench.dart';

class AppState extends ChangeNotifier {
  static final AppState _instance = AppState._internal();
  factory AppState() => _instance;

  final DatabaseService _db = DatabaseService();
  final TaskQueueService taskQueue = TaskQueueService();
  final GalleryState galleryState = GalleryState();
  final DownloaderState downloaderState = DownloaderState();
  final FileBrowserState fileBrowserState = FileBrowserState();
  final WorkbenchUIState workbenchUIState = WorkbenchUIState();

  /// Execution log. Pointedly absent from the listener wiring below: log lines
  /// arrive one per streamed chunk, and forwarding them here would rebuild
  /// every screen in the app for each one. See [LogState].
  final LogState logState = LogState();

  // Note what is *not* here: the sub-states above used to each do
  // `addListener(notifyListeners)`, so a change anywhere — a directory rescan,
  // a queue progress tick, a hover in the comparator — was re-broadcast to
  // every widget listening to AppState, which is most of them. That made the
  // whole app rebuild for events that concerned one panel. Each sub-state is
  // now its own provider and is watched directly by the widgets that draw it;
  // AppState notifies only for the settings and model data it owns itself.
  //
  // The rule this leaves behind: never read a sub-state's data through an
  // AppState listener. The proxy getters below (`galleryImages`,
  // `selectedImages`, `outputDirectory`, …) are for one-shot reads and actions
  // with `listen: false`; anything that has to rebuild when the value changes
  // must watch the owning notifier.
  AppState._internal() {
    // Wire up logs
    galleryState.onLog = (msg, {level = 'INFO'}) {
      addLog(msg, level: level);
    };

    taskQueue.onTaskCompleted = (file) {
      galleryState.refreshImages();
    };

    taskQueue.onTaskFinished = (task) {
      if (task.type == TaskType.aiRename && task.status == TaskStatus.completed) {
        fileBrowserState.refresh();
      }

      if (!notificationsEnabled) return;

      final l10n = lookupAppLocalizations(locale ?? const Locale('en'));        

      if (task.status == TaskStatus.completed) {
        logState.clearErrorFlag(); // A success clears the stale error indicator
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
  }

  bool settingsLoaded = false;
  bool setupCompleted = true;
  int concurrencyLimit = 2;
  int retryCount = 0;
  // Per-category Gemini safety thresholds (category → threshold), applied to
  // every image/video generation request. See [SafetySettings].
  Map<String, String> safetyThresholds = SafetySettings.defaults();
  bool notificationsEnabled = true;
  bool isConsoleExpanded = false;
  bool isSidebarExpanded = true;
  double sidebarWidth = 400.0;
  double consoleHeight = 200.0;
  bool enableApiDebug = false;

  // Navigation State
  int activeScreenIndex = 0;
  int workbenchTabIndex = 0;

  // Theme configuration
  ThemeMode themeMode = ThemeMode.system;
  Color themeSeedColor = Colors.blueGrey;
  // Font family key. Defaults to the bundled NotoSansSC to preserve the
  // existing look. The sentinel [AppConstants.systemFontKey] means "use the
  // platform default", which maps to a null [ThemeData.fontFamily].
  String fontFamily = 'NotoSansSC';

  /// The value to feed into [ThemeData.fontFamily]. For the "system" choice
  /// this resolves to the platform's installed UI font (e.g. Microsoft YaHei),
  /// since a null family would fall back to the engine default rather than the
  /// real OS font. Otherwise it's the selected family name.
  String? get themeFontFamily => fontFamily == AppConstants.systemFontKey
      ? FontService.systemFontFamily
      : fontFamily;

  // Language configuration
  Locale? locale;

  // Workbench configurations
  String? lastSelectedModelId;
  // Per-family image generation parameters, namespaced as "<family>.<paramKey>"
  // so that switching between e.g. nanoBanana and an OpenAI image model does
  // not clobber each other's remembered choices. Resolved through the model
  // capability specs (see [getImageParam] / [effectiveImageParams]).
  Map<String, String> _imageParamStore = {};
  // Bumped whenever an image param changes, so selectors can rebuild the
  // parameter controls without exposing the internal store.
  int imageParamsRevision = 0;
  // Per-family video-generation parameter store (parallel to imageParamStore).
  // Holds e.g. Sora's `seconds` / `videoQuality` under
  // `openaiVideo.seconds` / `openaiVideo.videoQuality`. Veo currently has no
  // capability-driven extras so it doesn't write here.
  Map<String, String> _videoParamStore = {};
  int videoParamsRevision = 0;
  String? lastVideoModelId;
  VeoResolution lastVideoResolution = VeoResolution.r720p;
  VeoAspectRatio lastVideoAspectRatio = VeoAspectRatio.r16_9;
  String lastPrompt = "";
  String lastVideoPrompt = "";
  // Recently submitted prompts, newest first, capped per medium. Rewritten as
  // fresh lists by [loadPromptHistory] so selectors see the change.
  List<PromptHistoryEntry> imagePromptHistory = [];
  List<PromptHistoryEntry> videoPromptHistory = [];
  bool useStream = true;
  // Opt-in: recompress oversized (>3MB) reference/source images to JPEG
  // before sending, trading fidelity for smaller requests. Off by default so
  // existing behavior (original bytes reach the API) doesn't change silently.
  bool compressReferenceImages = false;
  bool isMarkdownWorkbench = true;
  bool isMarkdownRefinerSource = true;
  bool isMarkdownRefinerTarget = true;

  // Data cache
  List<LLMModel> _models = [];
  List<LLMChannel> _channels = [];
  List<PricingGroup> _pricingGroups = [];

  // Derived views of [_models], computed once per data load rather than per
  // read. They used to be `_models.where(...).toList()` getters, which meant a
  // fresh list object on every call — and `context.select` compares with `==`,
  // which lists do not override. Every selector over one of these therefore
  // reported "changed" on every notification, so the panels that read them
  // rebuilt unconditionally and the selector bought nothing.
  List<LLMModel> _imageModels = const [];
  List<LLMModel> _chatModels = const [];
  List<LLMModel> _multimodalModels = const [];
  List<LLMModel> _videoModels = const [];

  List<LLMModel> get allModels => _models;
  List<LLMChannel> get allChannels => _channels;
  List<PricingGroup> get allPricingGroups => _pricingGroups;

  List<LLMModel> get imageModels => _imageModels;
  List<LLMModel> get chatModels => _chatModels;
  List<LLMModel> get multimodalModels => _multimodalModels;
  List<LLMModel> get videoModels => _videoModels;

  /// Replaces the model/channel/pricing cache and the views derived from it.
  ///
  /// The single place these are assigned, so the derived lists cannot drift out
  /// of sync with the data they summarise. [videoModels] depends on the
  /// channels as well as the models, which is why all three land together.
  void _cacheData({
    required List<LLMModel> models,
    required List<LLMChannel> channels,
    required List<PricingGroup> pricingGroups,
  }) {
    _models = models;
    _channels = channels;
    _pricingGroups = pricingGroups;

    _imageModels =
        models.where((m) => m.tag == ModelTag.image.value).toList(growable: false);
    _chatModels = models
        .where((m) =>
            m.tag == ModelTag.chat.value || m.tag == ModelTag.multimodal.value)
        .toList(growable: false);
    _multimodalModels = models
        .where((m) => m.tag == ModelTag.multimodal.value)
        .toList(growable: false);
    _videoModels = models
        .where((m) => m.tag == ModelTag.video.value && _supportsVideoForType(m))
        .toList(growable: false);
  }

  /// Video LRO is currently implemented by:
  ///   * Gemini-family vendors — Veo via `:predictLongRunning`
  ///   * OpenAI-family vendors — Sora / grok-imagine / Wanxiang etc. via
  ///     `/v1/videos`, gated on the model classifying as
  ///     [ModelFamily.openaiVideo] so that chat-only ids on the same channel
  ///     don't slip into the picker.
  bool _supportsVideoForType(LLMModel m) {
    final channel = _channels.cast<LLMChannel?>().firstWhere(
        (c) => c?.id == m.channelId,
        orElse: () => null);
    if (channel == null) return false;
    switch (Vendors.byId(channel.type).family) {
      case ProtocolFamily.gemini:
        return true;
      case ProtocolFamily.openai:
        return ModelDescriptor.of(m.modelId).family == ModelFamily.openaiVideo;
      case ProtocolFamily.midjourney:
      case ProtocolFamily.anthropic:
        return false;
    }
  }

  bool isVideoCompatibleModel(int? modelDbId) {
    if (modelDbId == null) return false;
    final model = _models.cast<LLMModel?>().firstWhere((m) => m?.id == modelDbId, orElse: () => null);
    return model != null && _supportsVideoForType(model);
  }

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
    fileBrowserState.dispose();
    logState.dispose();
    _sidebarWidthSaveTimer?.cancel();
    _consoleHeightSaveTimer?.cancel();
    _promptSaveTimer?.cancel();
    _videoPromptSaveTimer?.cancel();
    super.dispose();
  }

  // Proxies for Gallery State
  List<AppImage> get galleryImages => galleryState.galleryImages;
  List<AppImage> get processedImages => galleryState.processedImages;
  List<AppImage> get selectedImages => galleryState.selectedImages;
  bool isImageSelected(String path) => galleryState.isImageSelected(path);
  int selectionNumberOf(String path) => galleryState.selectionNumberOf(path);
  List<AppImage> get droppedImages => galleryState.droppedImages;

  String? get outputDirectory => galleryState.outputDirectory;
  String get imagePrefix => galleryState.imagePrefix;
  double get thumbnailSize => galleryState.thumbnailSize;
  List<String> get sourceDirectories => galleryState.sourceDirectories;
  List<String> get activeSourceDirectories => galleryState.activeSourceDirectories;

  Future<void> updateOutputDirectory(String path) => galleryState.updateOutputDirectory(path);
  Future<void> setImagePrefix(String prefix) => galleryState.setImagePrefix(prefix);
  void clearImageSelection() => galleryState.clearImageSelection();
  void toggleImageSelection(AppImage image) => galleryState.toggleImageSelection(image);
  Future<void> toggleDirectory(String path) => galleryState.toggleDirectory(path);
  Future<void> addBaseDirectory(String path) => galleryState.addBaseDirectory(path);
  Future<void> removeBaseDirectory(String path) => galleryState.removeBaseDirectory(path);
  Future<void> setThumbnailSize(double size) => galleryState.setThumbnailSize(size);
  Future<void> refreshImages() => galleryState.refreshImages();
  void selectAllImages() => galleryState.selectAllImages();

  // Browser State Proxies
  Set<String> get unreachableBrowserDirectories => fileBrowserState.unreachableDirectories;
  int get browserRefreshCounter => fileBrowserState.refreshCounter;

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

    final savedSafety = await _db.getSetting('safety_thresholds');
    if (savedSafety != null && savedSafety.isNotEmpty) {
      try {
        safetyThresholds =
            SafetySettings.normalize(jsonDecode(savedSafety) as Map);
      } catch (_) {/* keep defaults on malformed data */}
    }

    notificationsEnabled = (await _db.getSetting('notifications_enabled') ?? 'true') == 'true';
    isConsoleExpanded = (await _db.getSetting('is_console_expanded') ?? 'false') == 'true';
    isSidebarExpanded = (await _db.getSetting('is_sidebar_expanded') ?? 'true') == 'true';

    final savedConsoleHeight = await _db.getSetting('console_height');
    if (savedConsoleHeight != null) {
      consoleHeight = (double.tryParse(savedConsoleHeight) ?? 200.0).clamp(100.0, 600.0);
    }

    final savedSidebarWidth = await _db.getSetting('sidebar_width');
    if (savedSidebarWidth != null) {
      sidebarWidth = double.tryParse(savedSidebarWidth) ?? 400.0;
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

    fontFamily = await _db.getSetting('font_family') ?? 'NotoSansSC';
    // Register an on-demand font up front if it was previously downloaded, so
    // the saved preference renders on launch instead of falling back.
    await FontService.instance.ensureLoadedIfPresent(fontFamily);

    // Load locale
    final savedLocale = await _db.getSetting('locale');
    if (savedLocale != null && savedLocale.isNotEmpty) {
      if (savedLocale.contains('_')) {
        final parts = savedLocale.split('_');
        locale = Locale.fromSubtags(languageCode: parts[0], scriptCode: parts[1]);
      } else {
        locale = Locale(savedLocale);
      }
    }

    lastSelectedModelId = await _db.getSetting('last_model_id');
    await loadImageParams();
    await loadVideoParams();
    lastVideoModelId = await _db.getSetting('last_video_model_id');
    lastVideoResolution = VeoResolution.fromString(await _db.getSetting('last_video_resolution'));
    lastVideoAspectRatio = VeoAspectRatio.fromString(await _db.getSetting('last_video_aspect_ratio'));
    lastPrompt = await _db.getSetting('last_prompt') ?? "";
    lastVideoPrompt = await _db.getSetting('last_video_prompt') ?? "";
    useStream = (await _db.getSetting('workbench_use_stream') ?? 'true') == 'true';
    compressReferenceImages = (await _db.getSetting('workbench_compress_reference_images') ?? 'false') == 'true';

    final savedWorkbenchTab = await _db.getSetting('workbench_tab_index');      
    if (savedWorkbenchTab != null) {
      workbenchTabIndex = (int.tryParse(savedWorkbenchTab) ?? 0).clamp(0, AppConstants.workbenchTabCount - 1);
    }

    isMarkdownWorkbench = (await _db.getSetting('is_markdown_workbench') ?? 'true') == 'true';
    isMarkdownRefinerSource = (await _db.getSetting('is_markdown_refiner_source') ?? 'true') == 'true';
    isMarkdownRefinerTarget = (await _db.getSetting('is_markdown_refiner_target') ?? 'true') == 'true';

    _cacheData(
      models: await _db.getModels(),
      channels: await _db.getChannels(),
      pricingGroups: await _db.getPricingGroups(),
    );

    await downloaderState.loadCookieHistory();
    await loadPromptHistory();

    settingsLoaded = true;
    notifyListeners();
  }

  Future<void> completeSetup() async {
    setupCompleted = true;
    await _db.saveSetting('setup_completed', 'true');
    notifyListeners();
  }

  /// The app-wide entry point for logging, kept here because every producer
  /// already reaches for [AppState]. It does not notify: the line goes to
  /// [logState], which is what the console and the run bar listen to.
  void addLog(String message, {String level = 'INFO', String? taskId}) {
    logState.add(message, level: level, taskId: taskId);
  }

  /// Forwards to the protected [notifyListeners] so the `part of` extensions
  /// ([AppStateData], [AppStateWorkbench]) can trigger rebuilds.
  void notify() => notifyListeners();

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

  Future<void> setSafetyThreshold(String category, String threshold) async {
    safetyThresholds = {...safetyThresholds, category: threshold};
    await _db.saveSetting('safety_thresholds', jsonEncode(safetyThresholds));
    addLog('Safety threshold ${category.replaceFirst('HARM_CATEGORY_', '')} set to $threshold');
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

  Future<void> setFontFamily(String family) async {
    fontFamily = family;
    await _db.saveSetting('font_family', family);
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

  Timer? _consoleHeightSaveTimer;

  Future<void> setConsoleHeight(double height) async {
    consoleHeight = height.clamp(100.0, 600.0);
    _consoleHeightSaveTimer?.cancel();
    _consoleHeightSaveTimer = Timer(const Duration(milliseconds: 500), () async {
      await _db.saveSetting('console_height', consoleHeight.toString());
    });
  }

  Timer? _sidebarWidthSaveTimer;

  // Draft-prompt write debouncers. Fields rather than locals inside the
  // extension because Dart extensions cannot declare state; see
  // [AppStateWorkbench.setPromptDraft] for why the writes are deferred at all.
  Timer? _promptSaveTimer;
  Timer? _videoPromptSaveTimer;

  Future<void> setSidebarWidth(double width) async {
    // Keep in sync with WorkbenchLayout's drag clamp (200–500) — the wider
    // save range used to snap a 250px sidebar back to 280 on restart.
    sidebarWidth = width.clamp(200.0, 500.0);
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
    workbenchTabIndex = index.clamp(0, AppConstants.workbenchTabCount - 1);
    _db.saveSetting('workbench_tab_index', workbenchTabIndex.toString());       
    notifyListeners();
  }

  Future<void> setLocale(Locale? newLocale) async {
    locale = newLocale;
    String localeStr = '';
    if (newLocale != null) {
      localeStr = newLocale.languageCode;
      if (newLocale.scriptCode != null) {
        localeStr += '_${newLocale.scriptCode}';
      }
    }
    await _db.saveSetting('locale', localeStr);
    notifyListeners();
  }

  Future<void> setEnableApiDebug(bool value) async {
    enableApiDebug = value;
    await _db.saveSetting('enable_api_debug', value.toString());
    notifyListeners();
  }
}
