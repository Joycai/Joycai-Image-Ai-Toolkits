import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../widgets/log_console.dart';
import 'control_panel.dart';
import 'gallery.dart';
import 'source_explorer.dart';

class WorkbenchScreen extends StatefulWidget {
  const WorkbenchScreen({super.key});

  @override
  State<WorkbenchScreen> createState() => _WorkbenchScreenState();
}

class _WorkbenchScreenState extends State<WorkbenchScreen> {
  bool _isConsoleExpanded = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Column(
      children: [
        Expanded(
          child: Row(
            children: const [
              SourceExplorerWidget(),
              VerticalDivider(width: 1, thickness: 1),
              Expanded(child: GalleryWidget()),
              VerticalDivider(width: 1, thickness: 1),
              ControlPanelWidget(),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1),
        
        // Collapsible Console Header
        GestureDetector(
          onTap: () => setState(() => _isConsoleExpanded = !_isConsoleExpanded),
          child: Container(
            height: 32,
            color: colorScheme.surfaceVariant,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(
                  _isConsoleExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.executionLogs,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurfaceVariant,
                    letterSpacing: 1.2,
                  ),
                ),
                const Spacer(),
                if (!_isConsoleExpanded)
                  Text(
                    l10n.clickToExpand,
                    style: TextStyle(fontSize: 10, color: colorScheme.outline),
                  ),
              ],
            ),
          ),
        ),
        
        // Console Content
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: _isConsoleExpanded ? 200 : 0,
          child: const LogConsoleWidget(),
        ),
      ],
    );
  }
}
