import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'core/app_theme.dart';
import 'core/design_tokens.dart';
import 'core/responsive.dart';
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
import 'services/video_thumbnail_service.dart';
import 'services/window_chrome_service.dart';
import 'state/app_state.dart';
import 'widgets/app_status_badge.dart';
import 'widgets/app_window_frame.dart';
import 'widgets/task_capsule_monitor.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _hideNativeTitleBar();

  await NotificationService().init();

  final packageInfo = await PackageInfo.fromPlatform();

  final appState = AppState();
  await appState.loadSettings();

  // Prune stale video thumbnails in the background; don't block startup.
  unawaited(VideoThumbnailService.instance.cleanup());

  // Reap H3 local-video reference temp files left behind by past submits;
  // background, best-effort. See MiniMaxH3BaseVideoProtocol.sweepStaleTempRefs.
  unawaited(MiniMaxH3BaseVideoProtocol.sweepStaleTempRefs());

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appState),
        ChangeNotifierProvider<TaskQueueService>.value(value: appState.taskQueue),
        ChangeNotifierProvider.value(value: appState.workbenchUIState),
        ChangeNotifierProvider.value(value: appState.fileBrowserState),
        ChangeNotifierProvider.value(value: appState.fileStagingState),
        ChangeNotifierProvider.value(value: appState.downloaderState),
        ChangeNotifierProvider.value(value: appState.galleryState),
        // Separate from AppState on purpose — see LogState.
        ChangeNotifierProvider.value(value: appState.logState),
      ],
      child: MyApp(version: packageInfo.version),
    ),
  );
}

/// Hands the window's caption over to [AppTitleBar].
///
/// The spec draws the app with a title bar of its own, and there is no way to
/// have both — so this hides the native one. Everything it used to do is now
/// [AppTitleBar]'s job, which is why that widget carries drag-to-move, a
/// double-click target and the three buttons rather than just the look.
///
/// macOS keeps its traffic lights (`windowButtonVisibility`) and gets no
/// buttons drawn for it: they sit *inside* the window there, so hiding the bar
/// does not take them away, and a second set would be two ways to close one
/// window.
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
    final themeSeedColor = context.select<AppState, Color>((s) => s.themeSeedColor);
    final fontFamily = context.select<AppState, String?>((s) => s.themeFontFamily);

    final app = MaterialApp(
      onGenerateTitle: (context) => '${AppLocalizations.of(context)!.appTitle} v$version',
      themeMode: themeMode,
      locale: locale,
      scrollBehavior: const _AppScrollBehavior(),
      theme: buildAppTheme(
        seedColor: themeSeedColor,
        brightness: Brightness.light,
        fontFamily: fontFamily,
      ),
      darkTheme: buildAppTheme(
        seedColor: themeSeedColor,
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
      // Wrapped here rather than around MaterialApp: both of these need the
      // theme that actually resolved, and themeMode.system is only settled
      // below this point. [AppWindowFrame] is inside the sync rather than
      // outside so its own colours come from the same resolved theme.
      builder: (context, child) =>
          _WindowChromeSync(child: AppWindowFrame(child: child!)),
      home: const MainNavigationScreen(),
    );

    // Windows only: the engine's accessibility bridge mirrors every semantics
    // update into a ui::AXTree, and that mirror desyncs when overlay routes
    // (dropdown menus, tooltips) tear down mid-animation or when the tree is
    // rebuilt during a resize -- it logs "Failed to update ui::AXTree" and can
    // take the process down (flutter/flutter#182444, #100610). Keeping the
    // semantics tree empty removes the updates that desync it. The runner also
    // blocks WM_GETOBJECT so the bridge is never built in the first place; this
    // is the belt to that pair of braces. Remove both once upstream is fixed.
    //
    // Deliberately not applied on Android/iOS, where TalkBack and VoiceOver
    // need the semantics tree.
    if (Platform.isWindows) {
      return ExcludeSemantics(child: app);
    }
    return app;
  }
}

/// Rubber-banding on every scrollable, on every platform.
///
/// Windows' platform default is [ClampingScrollPhysics]: a fling into either
/// end stops flat on the boundary frame, with no overscroll signal at all. A
/// boundary should resist progressively and settle back — continuous
/// resistance reads as "responsive, but there's nothing more here", where a
/// hard stop reads as frozen. [RangeMaintainingScrollPhysics] as the parent is
/// what the framework pairs with bouncing on iOS: it keeps the offset stable
/// when the content under the scrollable grows or shrinks mid-scroll.
///
/// Deliberately not gated on reduce-motion: the bounce only ever happens under
/// the user's own gesture and moves with it, which is the one kind of motion
/// that setting does not ask to remove.
class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: RangeMaintainingScrollPhysics());
}

/// Pushes the resolved theme's canvas colour out to the OS title bar.
///
/// A widget rather than a call in `build` because the trigger is a change in
/// the inherited [Theme] — [didChangeDependencies] fires exactly then, and
/// only then, whether the theme moved because the user picked a new seed or
/// because the system flipped to dark underneath `ThemeMode.system`.
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
    // Logged, not fire-and-forget. Whether the OS took the colours is the one
    // thing the app cannot see by looking at itself — the caption is drawn by
    // the window manager, outside anything Flutter renders or a test can
    // assert. Putting the platform's answer in the execution log is the only
    // way this is checkable at all.
    WindowChromeService.applyTheme(Theme.of(context).colorScheme).then((report) {
      if (report != null) appState.addLog(report);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  bool _wizardShown = false;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Ctrl+1..8 (Cmd on macOS) jumps to the corresponding nav destination.
  // Registered as a HardwareKeyboard handler rather than a Focus/Shortcuts
  // widget so it works no matter where focus currently sits (screens swap in
  // and out and may leave focus on a scope outside any screen subtree).
  // Order must match _getNavDefinitions.
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

    // Only while this screen is frontmost — never underneath a dialog, the
    // setup wizard, or any other pushed route.
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
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SetupWizard()),
        );
      });
    }
  }

  List<_NavDef> _getNavDefinitions(AppLocalizations l10n) {
    return [
      _NavDef(icon: Icons.dashboard_outlined,   selectedIcon: Icons.dashboard,         label: l10n.workbench,   screen: const WorkbenchScreen(),       hideOnMobile: false),
      _NavDef(icon: Icons.folder_open_outlined, selectedIcon: Icons.folder_open,       label: l10n.fileBrowser, screen: const FileBrowserScreen(),     hideOnMobile: true),
      _NavDef(icon: Icons.checklist_outlined,   selectedIcon: Icons.checklist,         label: l10n.tasks,       screen: const TaskQueueScreen(),       hideOnMobile: false, showBadge: true),
      _NavDef(icon: Icons.cloud_download_outlined, selectedIcon: Icons.cloud_download, label: l10n.downloader,  screen: const ImageDownloaderScreen(), hideOnMobile: true),
      _NavDef(icon: Icons.auto_awesome_outlined, selectedIcon: Icons.auto_awesome,     label: l10n.prompts,     screen: const PromptsScreen(),         hideOnMobile: false),
      _NavDef(icon: Icons.memory_outlined,      selectedIcon: Icons.memory,            label: l10n.models,      screen: const ModelsScreen(),          hideOnMobile: false),
      _NavDef(icon: Icons.analytics_outlined,   selectedIcon: Icons.analytics,         label: l10n.usage,       screen: const TokenUsageScreen(),      hideOnMobile: false),
      _NavDef(icon: Icons.settings_outlined,    selectedIcon: Icons.settings,          label: l10n.settings,    screen: const SettingsScreen(),        hideOnMobile: false, isSettings: true),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final l10n = AppLocalizations.of(context)!;
    final isMobileUI = Responsive.isMobile(context);
    final isMobilePlatform = Platform.isAndroid || Platform.isIOS;

    final allDefinitions = _getNavDefinitions(l10n);
    final filteredDefinitions = isMobilePlatform
        ? allDefinitions.where((d) => !d.hideOnMobile).toList()
        : allDefinitions;

    final screens = filteredDefinitions.map((d) => d.screen).toList();

    int displayIndex = appState.activeScreenIndex;
    if (isMobilePlatform) {
      final currentScreen = allDefinitions[appState.activeScreenIndex].screen;
      displayIndex = screens.indexOf(currentScreen);
      if (displayIndex == -1) {
        displayIndex = 0;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) appState.navigateToScreen(0);
        });
      }
    }

    // Badge count: pending + running tasks.
    //
    // `select`, not `watch`. The queue notifies twice a second for as long as
    // anything is running (its progress timer), and watching it from here —
    // the shell every screen is drawn inside — rebuilt the nav rail and the
    // scaffold on every one of those ticks for a number that had not changed.
    // The active screen itself is a canonicalised const, so it was always
    // skipped; the chrome around it was not.
    final taskBadge = context.select<TaskQueueService, int>((q) => q.queue
        .where((t) => t.status == TaskStatus.pending || t.status == TaskStatus.processing)
        .length);

    void onNavSelect(int filteredIdx) {
      final targetScreen = filteredDefinitions[filteredIdx].screen;
      final originalIndex = allDefinitions.indexWhere((d) => d.screen == targetScreen);
      appState.navigateToScreen(originalIndex);
    }

    // Mobile: first 4 in bottom bar, rest in drawer
    final primaryItems = filteredDefinitions.take(4).toList();
    final secondaryItems = filteredDefinitions.skip(4).toList();

    return Stack(
      children: [
        Scaffold(
          key: _scaffoldKey,
          // Transparent so [AppWindowBackdrop] shows through wherever a screen
          // leaves a gap. Most screens paint over all of it; the workbench's
          // gallery column is the one the spec deliberately leaves bare.
          //
          // On mobile there is no backdrop behind this, so it falls back to
          // the canvas colour the way it always did.
          backgroundColor: usesCustomWindowChrome
              ? Colors.transparent
              : Theme.of(context).colorScheme.surfaceContainer,
          drawer: isMobileUI
              ? _buildMobileDrawer(l10n, filteredDefinitions, secondaryItems, displayIndex, appState, allDefinitions, taskBadge)
              : null,
          body: SafeArea(
            child: Row(
              children: [
                if (!isMobileUI)
                  _AppNavRail(
                    definitions: filteredDefinitions,
                    selectedIndex: displayIndex,
                    taskBadge: taskBadge,
                    onSelect: onNavSelect,
                    onSettings: () {
                      final idx = allDefinitions.indexWhere((d) => d.screen is SettingsScreen);
                      if (idx != -1) appState.navigateToScreen(idx);
                    },
                    isSettingsActive: filteredDefinitions[displayIndex].screen is SettingsScreen,
                    l10n: l10n,
                  ),
                // No transition between destinations, deliberately. This is
                // the most frequent action in the app and it carries a
                // keyboard shortcut (Ctrl/Cmd+1..8, above), which puts it in
                // the band where the correct animation is none: a shortcut
                // means "be there now". A crossfade would also double-expose
                // two opaque screens that share no structure, and pay for two
                // full subtrees at the one moment the new one is most
                // expensive to build.
                Expanded(child: screens[displayIndex]),
              ],
            ),
          ),
          bottomNavigationBar: isMobileUI
              ? NavigationBar(
                  selectedIndex: displayIndex < primaryItems.length ? displayIndex : primaryItems.length,
                  onDestinationSelected: (int index) {
                    if (index < primaryItems.length) {
                      onNavSelect(index);
                    } else {
                      _scaffoldKey.currentState?.openDrawer();
                    }
                  },
                  destinations: [
                    ...primaryItems.asMap().entries.map((e) {
                      final d = e.value;
                      return NavigationDestination(
                        icon: d.showBadge && taskBadge > 0
                            ? Badge(label: Text('$taskBadge'), child: Icon(d.icon))
                            : Icon(d.icon),
                        selectedIcon: d.showBadge && taskBadge > 0
                            ? Badge(label: Text('$taskBadge'), child: Icon(d.selectedIcon))
                            : Icon(d.selectedIcon),
                        label: d.label,
                      );
                    }),
                    NavigationDestination(
                      icon: const Icon(Icons.more_horiz_outlined),
                      selectedIcon: const Icon(Icons.more_horiz),
                      label: l10n.more,
                    ),
                  ],
                )
              : null,
        ),
        // Unconditional: the capsule governs its own visibility (queue state
        // and the workbench check) so it can fade out instead of unmounting
        // between two frames — a conditional here would cut its exit off.
        const TaskCapsuleMonitor(),
      ],
    );
  }

  Widget _buildMobileDrawer(
    AppLocalizations l10n,
    List<_NavDef> filteredDefinitions,
    List<_NavDef> secondaryItems,
    int displayIndex,
    AppState appState,
    List<_NavDef> allDefinitions,
    int taskBadge,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final primaryCount = filteredDefinitions.length - secondaryItems.length;

    return Drawer(
      width: 270,
      backgroundColor: colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          // Header
          Container(
            height: 70,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withAlpha(80))),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    // Both stops from the seed. The second used to be a fixed
                    // lavender, which read as intentional only for the one
                    // seed near it and fought the other six — an indigo app
                    // with a purple-tipped logo looks like a rendering bug.
                    // `primaryContainer` is the seed's own lighter tone, so
                    // the sweep stays a sweep at every theme.
                    gradient: LinearGradient(
                      colors: [colorScheme.primary, colorScheme.primaryContainer],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: const Icon(Icons.auto_awesome, size: 20, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.appTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Secondary nav items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              children: secondaryItems.asMap().entries.map((entry) {
                final idx = entry.key + primaryCount;
                final d = entry.value;
                final isSelected = displayIndex == idx;
                return _DrawerItem(
                  icon: isSelected ? d.selectedIcon : d.icon,
                  label: d.label,
                  isSelected: isSelected,
                  badge: d.showBadge && taskBadge > 0 ? taskBadge : 0,
                  onTap: () {
                    final targetScreen = filteredDefinitions[idx].screen;
                    final originalIndex = allDefinitions.indexWhere((dd) => dd.screen == targetScreen);
                    appState.navigateToScreen(originalIndex);
                    Navigator.pop(context);
                  },
                );
              }).toList(),
            ),
          ),
          // Settings at bottom
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
            child: _DrawerItem(
              icon: Icons.settings_outlined,
              label: l10n.settings,
              isSelected: filteredDefinitions[displayIndex].screen is SettingsScreen,
              badge: 0,
              onTap: () {
                final idx = allDefinitions.indexWhere((d) => d.screen is SettingsScreen);
                if (idx != -1) appState.navigateToScreen(idx);
                Navigator.pop(context);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Nav definition ─────────────────────────────────────────────────────────

class _NavDef {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final Widget screen;
  final bool hideOnMobile;
  final bool showBadge;
  final bool isSettings;

  const _NavDef({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.screen,
    this.hideOnMobile = false,
    this.showBadge = false,
    this.isSettings = false,
  });
}

// ── Custom app-level nav rail ───────────────────────────────────────────────

class _AppNavRail extends StatelessWidget {
  final List<_NavDef> definitions;
  final int selectedIndex;
  final int taskBadge;
  final ValueChanged<int> onSelect;
  final VoidCallback onSettings;
  final bool isSettingsActive;
  final AppLocalizations l10n;

  const _AppNavRail({
    required this.definitions,
    required this.selectedIndex,
    required this.taskBadge,
    required this.onSelect,
    required this.onSettings,
    required this.isSettingsActive,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final isTablet = Responsive.isTablet(context) && !Responsive.isDesktop(context);
    // 72 at desktop, per `A1 16a` — a 58px item with 7px either side. The 78
    // it shipped at was six pixels the centre column never got, which at the
    // iPad band (a screen just over the desktop breakpoint, a content box just
    // under it) is the difference the whole band is measured in.
    final railWidth = isTablet ? 64.0 : 72.0;
    final showLabels = !isTablet;

    final colorScheme = Theme.of(context).colorScheme;

    // The Ctrl/Cmd+digit shortcut a rail item answers to. Its number is the
    // item's position in the full nav list (1-based) — the same order
    // _handleGlobalKey maps the digit keys onto — and only the first eight,
    // which are the only digits bound. Surfaced in the tooltip so the shortcut
    // is discoverable at all; nothing else in the UI hints it exists.
    final modifier = Platform.isMacOS ? '⌘' : 'Ctrl';
    String? shortcutHint(int oneBasedIndex) =>
        oneBasedIndex <= _MainNavigationScreenState._navDigitKeys.length
            ? '$modifier+$oneBasedIndex'
            : null;

    return Container(
      width: railWidth,
      // Opaque since the restyle. `A1` and `D1` both give the rail a ground of
      // its own — #F5F7FD, a step under the toolbar — and a hairline down its
      // right edge. It used to float transparently on the canvas, which only
      // read as deliberate while the screens beside it were inset cards.
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          right: BorderSide(color: colorScheme.surfaceContainerHigh),
        ),
      ),
      child: Column(
        children: [
          // Main nav items
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  ...definitions.asMap().entries.where((e) => !e.value.isSettings).map((e) {
                    final idx = e.key;
                    final d = e.value;
                    final isSelected = selectedIndex == idx;
                    final badge = d.showBadge && taskBadge > 0 ? taskBadge : 0;
                    return _RailItem(
                      icon: isSelected ? d.selectedIcon : d.icon,
                      label: d.label,
                      isSelected: isSelected,
                      showLabel: showLabels,
                      badge: badge,
                      railWidth: railWidth,
                      shortcutHint: shortcutHint(idx + 1),
                      onTap: () => onSelect(idx),
                    );
                  }),
                ],
              ),
            ),
          ),
          // Settings pinned at bottom
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _RailItem(
              icon: isSettingsActive ? Icons.settings : Icons.settings_outlined,
              label: l10n.settings,
              isSelected: isSettingsActive,
              showLabel: showLabels,
              badge: 0,
              railWidth: railWidth,
              shortcutHint: shortcutHint(definitions.length),
              onTap: onSettings,
            ),
          ),
        ],
      ),
    );
  }
}

class _RailItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool showLabel;
  final int badge;
  final double railWidth;

  /// e.g. "Ctrl+1"; appended to the tooltip so the keyboard shortcut is
  /// discoverable. Null for items with no bound shortcut.
  final String? shortcutHint;
  final VoidCallback onTap;

  const _RailItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.showLabel,
    required this.badge,
    required this.railWidth,
    this.shortcutHint,
    required this.onTap,
  });

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Selected takes `onAccentTint`, not `primary`: the label sits on a wash
    // of primary, and primary on its own tint is one tone reading against
    // itself — fine in light by accident, washed out in dark where primary is
    // already the pale tone 80.
    final color = widget.isSelected
        ? colorScheme.onAccentTint
        : _hovering
            ? colorScheme.onSurfaceVariant
            : colorScheme.onSurfaceVariant.withAlpha(140);
    final bgColor = widget.isSelected
        ? colorScheme.accentTint
        : _hovering
            ? colorScheme.onSurfaceVariant.withAlpha(16)
            : Colors.transparent;

    final tooltip = widget.shortcutHint == null
        ? widget.label
        : '${widget.label} · ${widget.shortcutHint}';

    return Padding(
      // 7, so the item lands on `16a`'s 58 inside the 72px rail.
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      child: Tooltip(
        message: tooltip,
        // Off to the side, clear of the rail item it describes.
        preferBelow: false,
        child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: AppMotion.durationOf(context, AppMotion.state),
            curve: AppMotion.enter,
            width: widget.railWidth - 14,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(widget.icon, size: AppSize.iconLg, color: color),
                    if (widget.badge > 0)
                      Positioned(
                        top: -5,
                        right: -8,
                        // Deliberately not the spec's red. This counts work in
                        // flight, and red already means "a task failed" all
                        // over this app — a busy queue would read as a broken
                        // one. See AppCountBadge.
                        child: AppCountBadge(count: widget.badge),
                      ),
                  ],
                ),
                if (widget.showLabel) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }
}

// ── Mobile drawer item ─────────────────────────────────────────────────────

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final int badge;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Same pairing as _RailItem above — this is the drawer's copy of it.
    final color = isSelected ? colorScheme.onAccentTint : colorScheme.onSurfaceVariant;
    final bg = isSelected ? colorScheme.accentTint : Colors.transparent;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            badge > 0
                ? Badge(label: Text('$badge'), child: Icon(icon, size: 22, color: color))
                : Icon(icon, size: 22, color: color),
            const SizedBox(width: 13),
            Text(
              label,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
