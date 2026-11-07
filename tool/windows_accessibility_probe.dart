// Native regression probe: flutter run -d windows --release
//   -t tool/windows_accessibility_probe.dart
// Uses the production runner but never opens the application database or network.
// Attach a native accessibility client before pressing Run; inspect stderr for
// AXTree errors. A completed counter alone is NOT an accessibility pass.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_menu_anchor.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  runApp(const _Probe());
}

class _Probe extends StatefulWidget {
  const _Probe();

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  final _tooltips = List.generate(3, (_) => GlobalKey<TooltipState>());
  final _menu = MenuController();
  final _navigator = GlobalKey<NavigatorState>();
  int _cycle = 0;
  bool _running = false;

  Future<void> _run() async {
    setState(() => _running = true);
    try {
      for (var i = 0; i < 60 && mounted; i++) {
        final target = i % _tooltips.length;
        if (target == 2) _menu.open();
        _tooltips[target].currentState!.ensureTooltipVisible();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        Tooltip.dismissAllToolTips();
        if (_menu.isOpen) _menu.close();
        // Resize while the tooltip is leaving, the original crash boundary.
        await windowManager.setSize(Size(i.isEven ? 1000 : 900, 700));
        if (!mounted) return;
        if (i % 5 == 0) {
          final closed = showDialog<void>(
            context: _navigator.currentContext!,
            builder: (context) => const AlertDialog(
              title: Text('Probe dialog'),
              content: TextField(decoration: InputDecoration(labelText: 'Probe input')),
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 100));
          _navigator.currentState!.pop();
          await closed;
        }
        if (!mounted) return;
        setState(() => _cycle = i + 1);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: _navigator,
    theme: ThemeData(brightness: _cycle.isEven ? Brightness.light : Brightness.dark),
    home: Scaffold(
      appBar: AppBar(title: const Text('Windows accessibility probe')),
      body: ListView(
        children: [
          Text('Completed cycles: $_cycle / 60', semanticsLabel: 'Completed cycles $_cycle'),
          FilledButton(onPressed: _running ? null : _run, child: const Text('Run probe')),
          for (var i = 0; i < 2; i++)
            Tooltip(
              key: _tooltips[i],
              message: 'Tooltip $i',
              child: SizedBox(height: 100, child: Center(child: Text('Target $i'))),
            ),
          _probeMenu(
            controller: _menu,
            menuChildren: [MenuItemButton(onPressed: () {}, child: const Text('Probe menu item'))],
            builder: (context, controller, child) => Tooltip(
              key: _tooltips[2],
              message: 'Menu tooltip',
              child: TextButton(
                onPressed: () => controller.isOpen ? controller.close() : controller.open(),
                child: const Text('Menu anchor'),
              ),
            ),
          ),
          DropdownButton<int>(
            value: 0,
            items: const [
              DropdownMenuItem(value: 0, child: Text('First option')),
              DropdownMenuItem(value: 1, child: Text('Second option')),
            ],
            onChanged: (_) {},
          ),
        ],
      ),
    ),
  );
}

// Negative control, intentionally only in this isolated tool. Never expose a
// production flag that disables accessibility or opts back into a broken tree.
Widget _probeMenu({
  required MenuController controller,
  required List<Widget> menuChildren,
  required MenuAnchorChildBuilder builder,
}) => const bool.fromEnvironment('PROBE_RAW_MENU')
    ? MenuAnchor(controller: controller, menuChildren: menuChildren, builder: builder)
    : AppMenuAnchor(controller: controller, menuChildren: menuChildren, builder: builder);
