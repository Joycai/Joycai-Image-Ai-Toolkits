import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/collapsible_card.dart';
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
            children: [
              SourceExplorerWidget(),
              VerticalDivider(width: 1, thickness: 1),
              Expanded(child: GalleryWidget()),
              VerticalDivider(width: 1, thickness: 1),
              ControlPanelWidget(),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1),
        
        // Collapsible Console section
        Container(
          color: colorScheme.surfaceContainerHighest.withAlpha((255 * AppConstants.opacityLow).round()),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: CollapsibleCard(
            title: l10n.executionLogs,
            subtitle: _isConsoleExpanded ? null : l10n.clickToExpand,
            isExpanded: _isConsoleExpanded,
            onToggle: () => setState(() => _isConsoleExpanded = !_isConsoleExpanded),
            collapsedIcon: Icons.keyboard_arrow_up,
            expandedIcon: Icons.keyboard_arrow_down,
            content: const SizedBox(
              height: 200,
              child: LogConsoleWidget(),
            ),
          ),
        ),
      ],
    );
  }
}
