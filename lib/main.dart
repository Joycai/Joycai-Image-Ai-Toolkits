import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'bench/render_bench.dart';
import 'core/app_distribution.dart';
import 'core/app_effects.dart';
import 'core/app_paths.dart';
import 'core/app_shortcuts.dart';
import 'core/app_theme.dart';
import 'core/constants.dart';
import 'core/design_tokens.dart';
import 'core/responsive.dart';
import 'core/theme_accent.dart';
import 'l10n/app_localizations.dart';
import 'screens/batch/task_queue_screen.dart';
import 'screens/browser/file_browser_screen.dart';
import 'screens/downloader/image_downloader_screen.dart';
import 'screens/metrics/token_usage_screen.dart';
import 'screens/models/models_screen.dart';
import 'screens/prompts/prompts_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/wizard/credential_recovery_screen.dart';
import 'screens/wizard/installation_migration_screen.dart';
import 'screens/wizard/setup_wizard.dart';
import 'screens/workbench/workbench_screen.dart';
import 'services/db/database_service.dart';
import 'services/files/directory_access_service.dart';
import 'services/files/installation_migration_service.dart';
import 'services/files/legacy_result_migration.dart';
import 'services/files/temp_storage_service.dart';
import 'services/llm/protocols/minimax_h3_base_video_protocol.dart';
import 'services/media/video_thumbnail_service.dart';
import 'services/privacy/ai_consent_service.dart';
import 'services/security/credential_protection.dart';
import 'services/security/credential_recovery_service.dart';
import 'services/security/windows_credential_protection.dart';
import 'services/system/dock_badge_service.dart';
import 'services/system/notification_service.dart';
import 'services/system/window_chrome_service.dart';
import 'services/tasks/task_queue_service.dart';
import 'state/app_state.dart';
import 'state/installation_migration_state.dart';
import 'widgets/privacy/ai_consent_dialog.dart';
import 'widgets/shell/app_destinations.dart';
import 'widgets/shell/app_top_bar.dart';
import 'widgets/shell/app_window_frame.dart';
import 'widgets/shell/phone_dock.dart';
import 'widgets/shell/shell_cover.dart';
import 'widgets/shell/shortcut_panel.dart';
import 'widgets/tasks/task_capsule_monitor.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isMacOS && !AppDistribution.direct) {
    DatabaseService().configureCredentialProtection(const MacCredentialProtection());
  } else if (AppPaths.usesWindowsPackageStorage) {
    DatabaseService().configureCredentialProtection(const WindowsCredentialProtection());
  }

  await _hideNativeTitleBar();

  final packageInfo = await PackageInfo.fromPlatform();

  await DirectoryAccessService.instance.restoreAll();

  if (AppPaths.supportsInstallationImport) {
    final migration = InstallationMigrationService();
    if (await migration.shouldOffer()) {
      final done = Completer<void>();
      final state = InstallationMigrationState(service: migration);
      runApp(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(
            accent: AppConstants.presetThemes.values.first,
            brightness: Brightness.light,
          ),
          darkTheme: buildAppTheme(
            accent: AppConstants.presetThemes.values.first,
            brightness: Brightness.dark,
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => Column(
            children: [
              DragToMoveArea(
                child: Material(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: SizedBox(
                    height: kTitleBarHeight,
                    width: double.infinity,
                    child: Center(child: Text(AppLocalizations.of(context)!.appTitle)),
                  ),
                ),
              ),
              Expanded(child: child!),
            ],
          ),
          home: InstallationMigrationScreen(
            windows: AppPaths.usesWindowsPackageStorage,
            state: state,
            onContinue: () {
              if (!done.isCompleted) done.complete();
            },
          ),
        ),
      );
      await done.future;
      // Unmount listeners before disposing the bootstrap state. The live app
      // and its database have not been constructed yet.
      runApp(const SizedBox.shrink());
      await WidgetsBinding.instance.endOfFrame;
      state.dispose();
    }
  }

  if (AppPaths.supportsInstallationImport) {
    try {
      await DatabaseService().database;
    } on CredentialProtectionException {
      final recovered = Completer<void>();
      runApp(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(
            accent: AppConstants.presetThemes.values.first,
            brightness: Brightness.light,
          ),
          darkTheme: buildAppTheme(
            accent: AppConstants.presetThemes.values.first,
            brightness: Brightness.dark,
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: CredentialRecoveryScreen(
            onReset: AppPaths.usesWindowsPackageStorage
                ? () async {
                    // Do not discard saved credentials while the OS protector
                    // itself is unavailable; clearing cannot repair that case.
                    await const WindowsCredentialProtection().prepare(allowCreate: true);
                    await CredentialRecoveryService().reset();
                    await DatabaseService().database;
                    if (!recovered.isCompleted) recovered.complete();
                  }
                : null,
            onRetry: () async {
              await DatabaseService().database;
              if (!recovered.isCompleted) recovered.complete();
            },
          ),
        ),
      );
      await recovered.future;
    }
  }

  String? migrationError;
  if (Platform.isMacOS || Platform.isIOS) {
    try {
      await LegacyResultMigration().run();
    } catch (error) {
      migrationError = 'Legacy result migration deferred; originals retained. $error';
    }
  }
  String? consentLoadError;
  try {
    await AiConsentService.instance.load();
  } catch (_) {
    consentLoadError =
        'AI consent storage unavailable. AI requests remain blocked until it can be read.';
  }
  final appState = AppState();
  if (migrationError != null) appState.addLog(migrationError, level: 'ERROR');
  if (consentLoadError != null) appState.addLog(consentLoadError, level: 'ERROR');
  await appState.loadSettings();
  await appState.galleryState.settingsLoaded;

  // Prune stale video thumbnails in the background; don't block startup.
  unawaited(VideoThumbnailService.instance.cleanup());

  // Reap H3 local-video reference temp files left behind by past submits;
  // background, best-effort. See MiniMaxH3BaseVideoProtocol.sweepStaleTempRefs.
  unawaited(MiniMaxH3BaseVideoProtocol.sweepStaleTempRefs());

  // Take the masks, crop copies and page cache that have gone cold. Startup is
  // the one moment nothing holds them — see TempStorageService.sweep.
  unawaited(TempStorageService.instance.sweep());

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appState),
        ChangeNotifierProvider<TaskQueueService>.value(value: appState.taskQueue),
        ChangeNotifierProvider.value(value: appState.workbenchUIState),
        ChangeNotifierProvider.value(value: appState.taskListState),
        ChangeNotifierProvider.value(value: appState.modelListState),
        ChangeNotifierProvider.value(value: appState.fileBrowserState),
        ChangeNotifierProvider.value(value: appState.fileStagingState),
        ChangeNotifierProvider.value(value: appState.downloaderState),
        ChangeNotifierProvider.value(value: appState.galleryState),
        // Separate from AppState on purpose — see LogState.
        ChangeNotifierProvider.value(value: appState.logState),
      ],
      child: maybeWrapWithBench(
        MyApp(version: packageInfo.version, consentService: AiConsentService.instance),
      ),
    ),
  );
  // A first-run macOS notification permission request can remain unanswered.
  // Never hold the bootstrap/import UI (or the first app frame) behind it.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(appState.taskQueue.resumePendingTasks());
    unawaited(NotificationService().init());
  });
}

/// Hands the window's caption over to [AppTitleBar].
///
/// The design draws the title bar as part of the app — it carries the
/// navigation — so the native one is hidden. macOS keeps its traffic lights
/// (`windowButtonVisibility`), which sit inside the window there.
Future<void> _hideNativeTitleBar() async {
  if (!usesCustomWindowChrome) return;

  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(titleBarStyle: TitleBarStyle.hidden, windowButtonVisibility: true),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
}

class MyApp extends StatefulWidget {
  final String version;
  final AiConsentService? consentService;

  const MyApp({super.key, required this.version, this.consentService});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final ShellCoverController _shellCover = ShellCoverController();
  late final DockBadgeService _dockBadge;
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _dockBadge = DockBadgeService(context.read<AppState>().taskQueue);
    widget.consentService?.requestConsent = (scope) async {
      final context = _navigatorKey.currentContext;
      if (context == null || !mounted) return null;
      return AiConsentDialog.show(context, scope);
    };
  }

  @override
  void dispose() {
    widget.consentService?.requestConsent = null;
    _dockBadge.dispose();
    _shellCover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = context.select<AppState, ThemeMode>((s) => s.themeMode);
    final locale = context.select<AppState, Locale?>((s) => s.locale);
    final themeAccent = context.select<AppState, ThemeAccent>((s) => s.themeAccent);
    final fontFamily = context.select<AppState, String?>((s) => s.themeFontFamily);
    final reduceEffects = context.select<AppState, bool>((s) => s.reduceVisualEffects);

    final app = MaterialApp(
      navigatorKey: _navigatorKey,
      onGenerateTitle: (context) => '${AppLocalizations.of(context)!.appTitle} v${widget.version}',
      themeMode: themeMode,
      locale: locale,
      scrollBehavior: const _AppScrollBehavior(),
      theme: buildAppTheme(
        accent: themeAccent,
        brightness: Brightness.light,
        fontFamily: fontFamily,
      ),
      darkTheme: buildAppTheme(
        accent: themeAccent,
        brightness: Brightness.dark,
        fontFamily: fontFamily,
      ),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      // Wrapped here rather than around MaterialApp: the frame and the chrome
      // sync both need the theme that actually resolved, and
      // `themeMode.system` is only settled below this point. [AppEffects] sits
      // outermost so the title bar's glass reads it too.
      builder: (context, child) {
        widget.consentService?.denialMessage = AppLocalizations.of(context)!.aiConsentBlockedError;
        return AppEffects(
          reduceVisualEffects: reduceEffects,
          // Above the Navigator on purpose: a route that covers the shell has to
          // be able to find this from `navigator.context`. See [ShellCover].
          child: ShellCover(
            controller: _shellCover,
            child: _WindowChromeSync(child: AppWindowFrame(child: child!)),
          ),
        );
      },
      home: const MainNavigationScreen(),
    );

    // Windows only: the engine's accessibility bridge desyncs its AXTree when
    // overlay routes tear down mid-animation and can take the process down
    // (flutter/flutter#182444, #100610). Keeping the semantics tree empty
    // removes the updates that desync it; the runner also blocks
    // WM_GETOBJECT. Remove both once upstream is fixed. Not applied on
    // Android/iOS, where TalkBack and VoiceOver need the tree.
    if (Platform.isWindows) {
      return ExcludeSemantics(child: app);
    }
    return app;
  }
}

/// Rubber-banding on every scrollable, on every platform: a boundary should
/// resist and settle back, not stop flat on the boundary frame.
class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: RangeMaintainingScrollPhysics());
}

/// Pushes the resolved theme's colours out to the OS window caption, and logs
/// what the platform answered — the one thing the app cannot see by looking at
/// itself.
class _WindowChromeSync extends StatefulWidget {
  final Widget child;

  const _WindowChromeSync({required this.child});

  @override
  State<_WindowChromeSync> createState() => _WindowChromeSyncState();
}

class _WindowChromeSyncState extends State<_WindowChromeSync> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appState = context.read<AppState>();
    WindowChromeService.applyTheme(Theme.of(context).colorScheme).then((report) {
      if (report != null) appState.addLog(report);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The shell every destination is drawn inside (`01 全局壳层`, 「顶栏合一」).
///
/// Where the navigation lives depends on the device, not the screen:
///
/// - **Desktop, ≥ 600 wide** — in the title bar ([AppTitleBar]), so this
///   widget draws only the current screen, full bleed.
/// - **Tablet OS, ≥ 600 wide** — a 48px glass top bar ([AppTopBar]).
/// - **Anything < 600 wide** — the floating phone dock ([PhoneDock]); the
///   screen is told about the space the dock covers through its bottom
///   padding.
///
/// Switching destinations has no transition, deliberately: it is the most
/// frequent action in the app and carries `Ctrl/⌘ + 1…8`, which means "be
/// there now".
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  bool _wizardShown = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleGlobalKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKey);
    super.dispose();
  }

  /// `Ctrl/⌘ + 1…8` — the app tier (L0), read off [AppShortcuts].
  ///
  /// Registered on `HardwareKeyboard` rather than as a `Shortcuts` widget so
  /// it works wherever focus sits. The index *is* the `AppDestination` index.
  bool _handleGlobalKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    if (!AppShortcuts.registersShortcuts) return false;

    final appState = Provider.of<AppState>(context, listen: false);

    // The panel is the one app-level key that may fire while it is itself
    // frontmost — that is how it closes again.
    if (AppShortcuts.byId(AppShortcutIds.showShortcutPanel).matches(event)) {
      if (isShortcutPanelOpen || ModalRoute.of(context)?.isCurrent == true) {
        toggleShortcutPanel(context, screen: _shortcutScreen(appState));
        return true;
      }
      return false;
    }

    // Only while this screen is frontmost — never under a dialog or the
    // setup wizard.
    if (ModalRoute.of(context)?.isCurrent != true) return false;

    if (AppShortcuts.byId(AppShortcutIds.openSettings).matches(event)) {
      appState.navigateToScreen(AppDestination.settings.index);
      return true;
    }

    final index = AppShortcuts.navigationIndexFor(event);
    if (index < 0) return false;

    appState.navigateToScreen(index);
    return true;
  }

  /// Which screen's keys the panel should list, or null on a screen that
  /// claims none of its own.
  ShortcutScreen? _shortcutScreen(AppState appState) =>
      switch (AppDestination.values[appState.activeScreenIndex]) {
        AppDestination.workbench => ShortcutScreen.workbench,
        AppDestination.fileBrowser => ShortcutScreen.fileBrowser,
        _ => null,
      };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkFirstRun();
  }

  void _checkFirstRun() {
    final appState = Provider.of<AppState>(context);
    if (appState.settingsLoaded && !appState.setupCompleted && !_wizardShown) {
      _wizardShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SetupWizard()));
      });
    }
  }

  static Widget _screenFor(AppDestination destination) => switch (destination) {
    AppDestination.workbench => const WorkbenchScreen(),
    AppDestination.fileBrowser => const FileBrowserScreen(),
    AppDestination.tasks => const TaskQueueScreen(),
    AppDestination.downloader => const ImageDownloaderScreen(),
    AppDestination.prompts => const PromptsScreen(),
    AppDestination.models => const ModelsScreen(),
    AppDestination.usage => const TokenUsageScreen(),
    AppDestination.settings => const SettingsScreen(),
  };

  @override
  Widget build(BuildContext context) {
    final activeIndex = context.select<AppState, int>((s) => s.activeScreenIndex);
    var current = AppDestination.values[activeIndex];
    if (!AppDestination.isAvailable(current)) {
      // A destination this OS does not offer (restored from a desktop backup).
      current = AppDestination.workbench;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<AppState>().navigateToScreen(current.index);
      });
    }

    final isPhone = Responsive.isMobile(context);
    final isTouchOs = Platform.isAndroid || Platform.isIOS;
    final showTopBar = isTouchOs && !isPhone;

    Widget screen = _screenFor(current);
    if (isPhone) {
      // The dock floats over the bottom of the screen; the screen keeps its
      // content clear of it the same way it keeps clear of a home indicator.
      //
      // `padding` only. `viewPadding` stays the window's own, because that is
      // what [AppDock.clearanceOf] measures from: overriding it too made
      // the clearance count itself, and anything computing it from a screen's
      // context — a snackbar's bottom margin — cleared the dock twice.
      final mq = MediaQuery.of(context);
      final clearance = AppDock.clearanceOf(context);
      screen = MediaQuery(
        data: mq.copyWith(padding: mq.padding.copyWith(bottom: clearance)),
        child: screen,
      );
    }

    return Stack(
      children: [
        Scaffold(
          backgroundColor: Colors.transparent,
          body: showTopBar
              ? Column(
                  children: [
                    const AppTopBar(),
                    Expanded(
                      child: MediaQuery.removePadding(
                        context: context,
                        removeTop: true,
                        child: screen,
                      ),
                    ),
                  ],
                )
              : SafeArea(top: isTouchOs, bottom: false, left: false, right: false, child: screen),
        ),
        if (isPhone) const Positioned(left: 0, right: 0, bottom: 0, child: PhoneDock()),
        // Unconditional: the capsule governs its own visibility so it can
        // fade out instead of unmounting between two frames.
        const TaskCapsuleMonitor(),
      ],
    );
  }
}
