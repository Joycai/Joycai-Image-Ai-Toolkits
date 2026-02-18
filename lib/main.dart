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
import 'services/llm/providers/openai_api_provider.dart';
import 'services/notification_service.dart';
import 'services/task_queue_service.dart';
import 'state/app_state.dart';
import 'widgets/task_capsule_monitor.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await NotificationService().init();

  LLMService().registerProvider('google-genai', GoogleGenAIProvider());
  LLMService().registerProvider('openai-api', OpenAIAPIProvider());
  
  ModelDiscoveryService().registerProvider('google-genai', GoogleDiscoveryProvider());
  ModelDiscoveryService().registerProvider('openai-api', OpenAIAPIProvider());

  final packageInfo = await PackageInfo.fromPlatform();

  final appState = AppState();
  await appState.loadSettings();

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
    final appState = Provider.of<AppState>(context);

    return MaterialApp(
      onGenerateTitle: (context) => '${AppLocalizations.of(context)!.appTitle} v$version',
      debugShowCheckedModeBanner: false,
      themeMode: appState.themeMode,
      locale: appState.locale,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: appState.themeSeedColor, brightness: Brightness.light),
        fontFamily: 'NotoSansSC',
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: appState.themeSeedColor, brightness: Brightness.dark),
        fontFamily: 'NotoSansSC',
      ),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('zh'),
      ],
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
  bool _isRailExtended = false;
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

  // Define all possible nav items
  List<({Icon icon, Icon selectedIcon, String label, Widget screen, bool hideOnMobile})> _getNavDefinitions(AppLocalizations l10n) {
    return [
      (
        icon: const Icon(Icons.work_outline),
        selectedIcon: const Icon(Icons.work),
        label: l10n.workbench,
        screen: const WorkbenchScreen(),
        hideOnMobile: false,
      ),
      (
        icon: const Icon(Icons.folder_copy_outlined),
        selectedIcon: const Icon(Icons.folder_copy),
        label: l10n.fileBrowser,
        screen: const FileBrowserScreen(),
        hideOnMobile: true,
      ),
      (
        icon: const Icon(Icons.assignment_outlined),
        selectedIcon: const Icon(Icons.assignment),
        label: l10n.tasks,
        screen: const TaskQueueScreen(),
        hideOnMobile: false,
      ),
      (
        icon: const Icon(Icons.cloud_download_outlined),
        selectedIcon: const Icon(Icons.cloud_download),
        label: l10n.downloader,
        screen: const ImageDownloaderScreen(),
        hideOnMobile: true,
      ),
      (
        icon: const Icon(Icons.notes_outlined),
        selectedIcon: const Icon(Icons.notes),
        label: l10n.prompts,
        screen: const PromptsScreen(),
        hideOnMobile: false,
      ),
      (
        icon: const Icon(Icons.analytics_outlined),
        selectedIcon: const Icon(Icons.analytics),
        label: l10n.usage,
        screen: const TokenUsageScreen(),
        hideOnMobile: false,
      ),
      (
        icon: const Icon(Icons.model_training_outlined),
        selectedIcon: const Icon(Icons.model_training),
        label: l10n.models,
        screen: const ModelsScreen(),
        hideOnMobile: false,
      ),
      (
        icon: const Icon(Icons.settings_outlined),
        selectedIcon: const Icon(Icons.settings),
        label: l10n.settings,
        screen: const SettingsScreen(),
        hideOnMobile: false,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final l10n = AppLocalizations.of(context)!;
    final isMobileUI = Responsive.isMobile(context);
    final isTabletUI = Responsive.isTablet(context);
    final isMobilePlatform = Platform.isAndroid || Platform.isIOS;

    // Filter items based on platform
    final allDefinitions = _getNavDefinitions(l10n);
    final filteredDefinitions = isMobilePlatform 
        ? allDefinitions.where((d) => !d.hideOnMobile).toList()
        : allDefinitions;

    final screens = filteredDefinitions.map((d) => d.screen).toList();
    final navItems = filteredDefinitions.map((d) => (
      icon: d.icon,
      selectedIcon: d.selectedIcon,
      label: d.label,
    )).toList();

    // Mapping logic for active index
    // If current index is out of bounds for filtered list (e.g. switched from desktop to mobile via dev tools?)
    // But here we care about platform. If platform is mobile, index must be mapped.
    int displayIndex = appState.activeScreenIndex;
    if (isMobilePlatform) {
      // Find the index of the screen in the filtered list
      final currentScreen = allDefinitions[appState.activeScreenIndex].screen;
      displayIndex = screens.indexOf(currentScreen);
      if (displayIndex == -1) {
        displayIndex = 0; // Fallback to workbench
        // Optionally update appState here, but we should be careful with side effects in build
      }
    }

    // If rail extended state hasn't been set by user, default based on tablet/desktop
    if (isTabletUI) _isRailExtended = false;

    // Split for mobile UI (NavigationBar): first 4 items + "More"
    final primaryItems = navItems.take(4).toList();
    final secondaryItems = navItems.skip(4).toList();

    return Stack(
      children: [
        Scaffold(
          key: _scaffoldKey,
          drawer: isMobileUI ? _buildMobileDrawer(secondaryItems, l10n, filteredDefinitions, displayIndex) : null,
          body: SafeArea(
            child: Row(
              children: [
                if (!isMobileUI)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: constraints.maxHeight),
                          child: IntrinsicHeight(
                            child: NavigationRail(
                              extended: _isRailExtended,
                              selectedIndex: displayIndex,
                              onDestinationSelected: (int index) {
                                // Map back to original index
                                final targetScreen = filteredDefinitions[index].screen;
                                final originalIndex = allDefinitions.indexWhere((d) => d.screen == targetScreen);
                                appState.navigateToScreen(originalIndex);
                              },
                              leading: IconButton(
                                icon: Icon(_isRailExtended ? Icons.menu_open : Icons.menu),
                                onPressed: () => setState(() => _isRailExtended = !_isRailExtended),
                              ),
                              labelType: _isRailExtended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
                              destinations: navItems
                                  .map((d) => NavigationRailDestination(
                                        icon: d.icon,
                                        selectedIcon: d.selectedIcon,
                                        label: Text(d.label),
                                      ))
                                  .toList(),
                            ),
                          ),
                        ),
                      );
                    }
                  ),
                if (!isMobileUI) const VerticalDivider(thickness: 1, width: 1),
                Expanded(
                  child: screens[displayIndex],
                ),
              ],
            ),
          ),
          bottomNavigationBar: isMobileUI
              ? NavigationBar(
                  selectedIndex: displayIndex < 4 ? displayIndex : 4,
                  onDestinationSelected: (int index) {
                    if (index < 4) {
                      final targetScreen = filteredDefinitions[index].screen;
                      final originalIndex = allDefinitions.indexWhere((d) => d.screen == targetScreen);
                      appState.navigateToScreen(originalIndex);
                    } else {
                      _scaffoldKey.currentState?.openDrawer();
                    }
                  },
                  destinations: [
                    ...primaryItems.map((d) => NavigationDestination(
                          icon: d.icon,
                          selectedIcon: d.selectedIcon,
                          label: d.label,
                        )),
                    const NavigationDestination(
                      icon: Icon(Icons.more_horiz_outlined),
                      selectedIcon: Icon(Icons.more_horiz),
                      label: "More", 
                    ),
                  ],
                )
              : null,
        ),
        const TaskCapsuleMonitor(),
      ],
    );
  }

  Widget _buildMobileDrawer(List<dynamic> items, AppLocalizations l10n, List<dynamic> filteredDefinitions, int displayIndex) {
    final appState = Provider.of<AppState>(context, listen: false);
    final allDefinitions = _getNavDefinitions(l10n);

    return Drawer(
      child: Column(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome, size: 48, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 8),
                  Text(
                    l10n.appTitle,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),
          ...items.asMap().entries.map((entry) {
            final index = entry.key + 4; // Skip first 4
            final d = entry.value;
            final isSelected = displayIndex == index;
            return ListTile(
              leading: isSelected ? d.selectedIcon : d.icon,
              title: Text(d.label),
              selected: isSelected,
              onTap: () {
                final targetScreen = filteredDefinitions[index].screen;
                final originalIndex = allDefinitions.indexWhere((d) => d.screen == targetScreen);
                appState.navigateToScreen(originalIndex);
                Navigator.pop(context);
              },
            );
          }),
          const Spacer(),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              "Joycai Toolkits",
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ),
        ],
      ),
    );
  }
}

