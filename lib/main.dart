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
import 'state/app_state.dart';
import 'widgets/floating_comparator.dart';
import 'widgets/floating_preview.dart';
import 'widgets/window_dock.dart';

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
        ChangeNotifierProvider.value(value: appState.windowState),
        ChangeNotifierProvider.value(value: appState.browserState),
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
  int _selectedIndex = 0;
  bool _isRailExtended = false;
  bool _wizardShown = false;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkFirstRun();

    // Update window state with current screen size
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final size = MediaQuery.of(context).size;
        Provider.of<AppState>(context, listen: false).windowState.updateScreenSize(size);
      }
    });
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

  final List<Widget> _screens = [
    const WorkbenchScreen(),
    const FileBrowserScreen(),
    const TaskQueueScreen(),
    const ImageDownloaderScreen(),
    const PromptsScreen(),
    const TokenUsageScreen(),
    const ModelsScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isMobile = Responsive.isMobile(context);
    final isTablet = Responsive.isTablet(context);

    // If rail extended state hasn't been set by user, default based on tablet/desktop
    if (isTablet) _isRailExtended = false;

    final allNavItems = [
      (
        icon: const Icon(Icons.work_outline),
        selectedIcon: const Icon(Icons.work),
        label: l10n.workbench,
      ),
      (
        icon: const Icon(Icons.folder_copy_outlined),
        selectedIcon: const Icon(Icons.folder_copy),
        label: l10n.fileBrowser,
      ),
      (
        icon: const Icon(Icons.assignment_outlined),
        selectedIcon: const Icon(Icons.assignment),
        label: l10n.tasks,
      ),
      (
        icon: const Icon(Icons.cloud_download_outlined),
        selectedIcon: const Icon(Icons.cloud_download),
        label: l10n.downloader,
      ),
      (
        icon: const Icon(Icons.notes_outlined),
        selectedIcon: const Icon(Icons.notes),
        label: l10n.prompts,
      ),
      (
        icon: const Icon(Icons.analytics_outlined),
        selectedIcon: const Icon(Icons.analytics),
        label: l10n.usage,
      ),
      (
        icon: const Icon(Icons.model_training_outlined),
        selectedIcon: const Icon(Icons.model_training),
        label: l10n.models,
      ),
      (
        icon: const Icon(Icons.settings_outlined),
        selectedIcon: const Icon(Icons.settings),
        label: l10n.settings,
      ),
    ];

    // Split for mobile: 4 items + "More"
    final primaryItems = allNavItems.take(4).toList();
    final secondaryItems = allNavItems.skip(4).toList();

    return Stack(
      children: [
        Scaffold(
          key: _scaffoldKey,
          drawer: isMobile ? _buildMobileDrawer(secondaryItems, l10n) : null,
          body: Row(
            children: [
              if (!isMobile)
                NavigationRail(
                  extended: _isRailExtended,
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (int index) {
                    setState(() {
                      _selectedIndex = index;
                    });
                  },
                  leading: IconButton(
                    icon: Icon(_isRailExtended ? Icons.menu_open : Icons.menu),
                    onPressed: () => setState(() => _isRailExtended = !_isRailExtended),
                  ),
                  labelType: _isRailExtended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
                  destinations: allNavItems
                      .map((d) => NavigationRailDestination(
                            icon: d.icon,
                            selectedIcon: d.selectedIcon,
                            label: Text(d.label),
                          ))
                      .toList(),
                ),
              if (!isMobile) const VerticalDivider(thickness: 1, width: 1),
              Expanded(
                child: _screens[_selectedIndex],
              ),
            ],
          ),
          bottomNavigationBar: isMobile
              ? NavigationBar(
                  selectedIndex: _selectedIndex < 4 ? _selectedIndex : 4,
                  onDestinationSelected: (int index) {
                    if (index < 4) {
                      setState(() {
                        _selectedIndex = index;
                      });
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
                      label: "More", // Usually stays English or translated if needed
                    ),
                  ],
                )
              : null,
        ),
        if (isMobile) 
          const Padding(
            padding: EdgeInsets.only(bottom: 80), // Offset above BottomNavigationBar
            child: WindowDock(),
          )
        else
          const WindowDock(),
        const FloatingPreviewHost(),
        const FloatingComparatorHost(),
      ],
    );
  }

  Widget _buildMobileDrawer(List<dynamic> items, AppLocalizations l10n) {
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
            final isSelected = _selectedIndex == index;
            return ListTile(
              leading: isSelected ? d.selectedIcon : d.icon,
              title: Text(d.label),
              selected: isSelected,
              onTap: () {
                setState(() {
                  _selectedIndex = index;
                });
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
