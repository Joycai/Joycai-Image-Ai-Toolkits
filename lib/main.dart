import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/batch/batch_screen.dart';
import 'screens/metrics/token_usage_screen.dart';
import 'screens/models/models_screen.dart';
import 'screens/prompts/prompts_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/workbench/workbench_screen.dart';
import 'services/llm/llm_service.dart';
import 'services/llm/providers/google_genai_provider.dart';
import 'services/llm/providers/openai_api_provider.dart';
import 'state/app_state.dart';

void main() {
  LLMService().registerProvider('google-genai', GoogleGenAIProvider());
  LLMService().registerProvider('openai-api', OpenAIAPIProvider());

  runApp(
    ChangeNotifierProvider(
      create: (context) => AppState(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    return MaterialApp(
      title: 'Joycai Image AI Toolkits',
      debugShowCheckedModeBanner: false,
      themeMode: appState.themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey, brightness: Brightness.light),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey, brightness: Brightness.dark),
      ),
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

  final List<Widget> _screens = [
    const WorkbenchScreen(),
    const BatchScreen(),
    const PromptsScreen(),
    const TokenUsageScreen(),
    const ModelsScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.work_outline),
                selectedIcon: Icon(Icons.work),
                label: Text('Workbench'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.assignment_outlined),
                selectedIcon: Icon(Icons.assignment),
                label: Text('Tasks'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.notes_outlined),
                selectedIcon: Icon(Icons.notes),
                label: Text('Prompts'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.analytics_outlined),
                selectedIcon: Icon(Icons.analytics),
                label: Text('Usage'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.model_training_outlined),
                selectedIcon: Icon(Icons.model_training),
                label: Text('Models'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('Settings'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: _screens[_selectedIndex],
          ),
        ],
      ),
    );
  }
}
