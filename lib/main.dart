import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

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
import 'services/llm/llm_service.dart';
import 'services/llm/model_discovery_service.dart';
import 'services/llm/providers/google_genai_provider.dart';
import 'services/llm/providers/midjourney_proxy_provider.dart';
import 'services/llm/providers/openai_api_provider.dart';
import 'services/notification_service.dart';
import 'services/task_queue_service.dart';
import 'services/video_thumbnail_service.dart';
import 'state/app_state.dart';
import 'widgets/task_capsule_monitor.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await NotificationService().init();

  final midjourneyProvider = MidjourneyProxyProvider();
  LLMService().registerProvider('google-genai', GoogleGenAIProvider());
  LLMService().registerProvider('openai-api', OpenAIAPIProvider());
  LLMService().registerProvider('midjourney-proxy', midjourneyProvider);

  ModelDiscoveryService().registerProvider('google-genai', GoogleDiscoveryProvider());
  ModelDiscoveryService().registerProvider('openai-api', OpenAIAPIProvider());
  ModelDiscoveryService().registerProvider('midjourney-proxy', midjourneyProvider);

  final packageInfo = await PackageInfo.fromPlatform();

  final appState = AppState();
  await appState.loadSettings();

  // Prune stale video thumbnails in the background; don't block startup.
  unawaited(VideoThumbnailService.instance.cleanup());

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appState),
        ChangeNotifierProvider<TaskQueueService>.value(value: appState.taskQueue),
        ChangeNotifierProvider.value(value: appState.workbenchUIState),
        ChangeNotifierProvider.value(value: appState.fileBrowserState),
        ChangeNotifierProvider.value(value: appState.downloaderState),
      ],
      child: MyApp(version: packageInfo.version),
    ),
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

    return MaterialApp(
      onGenerateTitle: (context) => '${AppLocalizations.of(context)!.appTitle} v$version',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      locale: locale,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: themeSeedColor, brightness: Brightness.light),
        fontFamily: 'NotoSansSC',
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: themeSeedColor, brightness: Brightness.dark),
        fontFamily: 'NotoSansSC',
      ),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const MainNavigationScreen(),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  bool _wizardShown = false;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

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
    final taskQueue = context.watch<TaskQueueService>();

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

    // Badge count: pending + running tasks
    final taskBadge = taskQueue.queue
        .where((t) => t.status == TaskStatus.pending || t.status == TaskStatus.processing)
        .length;

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
          drawer: isMobileUI
              ? _buildMobileDrawer(l10n, filteredDefinitions, secondaryItems, displayIndex, appState, allDefinitions, taskBadge)
              : null,
          body: SafeArea(
            child: Row(
              children: [
                if (!isMobileUI) ...[
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
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: Theme.of(context).colorScheme.outlineVariant.withAlpha(80),
                  ),
                ],
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
        if (appState.activeScreenIndex != 0) const TaskCapsuleMonitor(),
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
                    gradient: LinearGradient(
                      colors: [colorScheme.primary, const Color(0xFFB794F6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
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
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
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
    final colorScheme = Theme.of(context).colorScheme;
    final isTablet = Responsive.isTablet(context) && !Responsive.isDesktop(context);
    final railWidth = isTablet ? 64.0 : 78.0;
    final showLabels = !isTablet;

    return Container(
      width: railWidth,
      color: colorScheme.surfaceContainerLow,
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
  final VoidCallback onTap;

  const _RailItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.showLabel,
    required this.badge,
    required this.railWidth,
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
    final color = widget.isSelected
        ? colorScheme.primary
        : _hovering
            ? colorScheme.onSurfaceVariant
            : colorScheme.onSurfaceVariant.withAlpha(140);
    final bgColor = widget.isSelected
        ? colorScheme.primary.withAlpha(28)
        : _hovering
            ? colorScheme.onSurfaceVariant.withAlpha(16)
            : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: widget.railWidth - 16,
            padding: const EdgeInsets.symmetric(vertical: 10),
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
                    Icon(widget.icon, size: 22, color: color),
                    if (widget.badge > 0)
                      Positioned(
                        top: -5,
                        right: -8,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 15),
                          height: 15,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              widget.badge > 99 ? '99+' : '${widget.badge}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (widget.showLabel) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: color,
                      letterSpacing: 0.2,
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
    final color = isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant;
    final bg = isSelected ? colorScheme.primary.withAlpha(24) : Colors.transparent;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          children: [
            badge > 0
                ? Badge(label: Text('$badge'), child: Icon(icon, size: 22, color: color))
                : Icon(icon, size: 22, color: color),
            const SizedBox(width: 13),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
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
