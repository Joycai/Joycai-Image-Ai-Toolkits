import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'l10n/app_localizations.dart';
import 'screens/batch/task_queue_screen.dart';
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
    ChangeNotifierProvider.value(
      value: appState,
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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey, brightness: Brightness.light),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey, brightness: Brightness.dark),
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

  final List<Widget> _screens = [
    const WorkbenchScreen(),
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

    return Stack(
      children: [
        Scaffold(
          body: Row(
            children: [
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
                destinations: [
                  NavigationRailDestination(
                    icon: const Icon(Icons.work_outline),
                    selectedIcon: const Icon(Icons.work),
                    label: Text(l10n.workbench),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.assignment_outlined),
                    selectedIcon: const Icon(Icons.assignment),
                    label: Text(l10n.tasks),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.cloud_download_outlined),
                    selectedIcon: const Icon(Icons.cloud_download),
                    label: Text(l10n.downloader),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.notes_outlined),
                    selectedIcon: const Icon(Icons.notes),
                    label: Text(l10n.prompts),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.analytics_outlined),
                    selectedIcon: const Icon(Icons.analytics),
                    label: Text(l10n.usage),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.model_training_outlined),
                    selectedIcon: const Icon(Icons.model_training),
                    label: Text(l10n.models),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.settings_outlined),
                    selectedIcon: const Icon(Icons.settings),
                    label: Text(l10n.settings),
                  ),
                ],
              ),
              const VerticalDivider(thickness: 1, width: 1),
              Expanded(
                child: _screens[_selectedIndex],
              ),
            ],
          ),
        ),
        const FloatingPreviewHost(),
        const FloatingComparatorHost(),
      ],
    );
  }
}
