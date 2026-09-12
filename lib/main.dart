import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'bench/render_bench.dart';
import 'core/app_effects.dart';
import 'core/app_theme.dart';
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
import 'screens/wizard/setup_wizard.dart';
import 'screens/workbench/workbench_screen.dart';
import 'services/llm/protocols/minimax_h3_base_video_protocol.dart';
import 'services/notification_service.dart';
import 'services/task_queue_service.dart';
import 'services/temp_storage_service.dart';
import 'services/video_thumbnail_service.dart';
import 'services/window_chrome_service.dart';
import 'state/app_state.dart';
import 'widgets/app_window_frame.dart';
import 'widgets/shell/app_destinations.dart';
import 'widgets/shell/app_top_bar.dart';
import 'widgets/shell/phone_dock.dart';
import 'widgets/task_capsule_monitor.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _hideNativeTitleBar();

  await NotificationService().init();

  final packageInfo = await PackageInfo.fromPlatform();

  final appState = AppState();
  await appState.loadSettings();
  await appState.taskQueue.resumePendingTasks();

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
        ChangeNotifierProvider<TaskQueueService>.value(
          value: appState.taskQueue,
        ),
        ChangeNotifierProvider.value(value: appState.workbenchUIState),
        ChangeNotifierProvider.value(value: appState.taskListState),
        ChangeNotifierProvider.value(value: appState.fileBrowserState),
        ChangeNotifierProvider.value(value: appState.fileStagingState),
        ChangeNotifierProvider.value(value: appState.downloaderState),
        ChangeNotifierProvider.value(value: appState.galleryState),
        // Separate from AppState on purpose — see LogState.
        ChangeNotifierProvider.value(value: appState.logState),
      ],
      child: maybeWrapWithBench(MyApp(version: packageInfo.version)),
    ),
  );
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
    const WindowOptions(
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: true,
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
}

class MyApp extends StatelessWidget {
  final String version;

  const MyApp({super.key, required this.version});

  @override
  Widget build(BuildContext context) {
    final themeMode = context.select<AppState, ThemeMode>((s) => s.themeMode);
    final locale = context.select<AppState, Locale?>((s) => s.locale);
    final themeAccent = context.select<AppState, ThemeAccent>(
      (s) => s.themeAccent,
    );
    final fontFamily = context.select<AppState, String?>(
      (s) => s.themeFontFamily,
    );
    final reduceEffects = context.select<AppState, bool>(
      (s) => s.reduceVisualEffects,
    );

    final app = MaterialApp(
      onGenerateTitle: (context) =>
          '${AppLocalizations.of(context)!.appTitle} v$version',
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
      builder: (context, child) => AppEffects(
        reduceVisualEffects: reduceEffects,
        child: _WindowChromeSync(child: AppWindowFrame(child: child!)),
      ),
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
    WindowChromeService.applyTheme(Theme.of(context).colorScheme).then((
      report,
    ) {
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

  // Ctrl+1..8 (Cmd on macOS) jumps to the corresponding destination.
  // Registered on HardwareKeyboard rather than as a Shortcuts widget so it
  // works wherever focus sits. Order matches [AppDestination].
  static const List<LogicalKeyboardKey> _navDigitKeys = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
  ];

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

  bool _handleGlobalKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    if (Platform.isAndroid || Platform.isIOS) return false;

    final hw = HardwareKeyboard.instance;
    final isCtrl = Platform.isMacOS ? hw.isMetaPressed : hw.isControlPressed;
    if (!isCtrl) return false;

    final index = _navDigitKeys.indexOf(event.logicalKey);
    if (index == -1) return false;

    // Only while this screen is frontmost — never under a dialog or the
    // setup wizard.
    if (ModalRoute.of(context)?.isCurrent != true) return false;

    Provider.of<AppState>(context, listen: false).navigateToScreen(index);
    return true;
  }

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
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const SetupWizard()));
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
    final activeIndex = context.select<AppState, int>(
      (s) => s.activeScreenIndex,
    );
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
      // what [PhoneDock.clearanceOf] measures from: overriding it too made
      // the clearance count itself, and anything computing it from a screen's
      // context — a snackbar's bottom margin — cleared the dock twice.
      final mq = MediaQuery.of(context);
      final clearance = PhoneDock.clearanceOf(context);
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
              : SafeArea(
                  top: isTouchOs,
                  bottom: false,
                  left: false,
                  right: false,
                  child: screen,
                ),
        ),
        if (isPhone)
          const Positioned(left: 0, right: 0, bottom: 0, child: PhoneDock()),
        // Unconditional: the capsule governs its own visibility so it can
        // fade out instead of unmounting between two frames.
        const TaskCapsuleMonitor(),
      ],
    );
  }
}
