// Native menu acceptance probe. No app database, task queue or network is opened.
// flutter run -d macos --release -t tool/macos_menu_probe.dart
import 'package:flutter/material.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/widgets/shell/app_native_menu.dart';

void main() => runApp(const _Probe());

class _Probe extends StatefulWidget {
  const _Probe();
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  Locale _locale = const Locale('en');
  int _calls = 0;
  String _last = 'none';

  void _record(String command) => setState(() {
    _calls++;
    _last = command;
  });

  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: _locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) => AppNativeMenu(
        onNavigate: (index) => _record('destination:$index'),
        onShortcuts: () => showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Shortcut help probe'),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
            ],
          ),
        ),
        child: Scaffold(
          appBar: AppBar(title: const Text('Native menu probe — isolated, no user data')),
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text('Command calls: $_calls; last: $_last'),
                const TextField(
                  decoration: InputDecoration(labelText: 'Edit / undo / copy / paste probe'),
                ),
                Wrap(
                  children: [
                    for (final locale in AppLocalizations.supportedLocales)
                      TextButton(
                        onPressed: () => setState(() => _locale = locale),
                        child: Text(locale.toLanguageTag()),
                      ),
                    TextButton(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Navigation must be disabled'),
                          content: const TextField(
                            decoration: InputDecoration(
                              labelText: 'Modal editing remains available',
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      ),
                      child: const Text('Open modal'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
