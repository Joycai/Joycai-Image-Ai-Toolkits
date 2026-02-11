import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
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
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final appState = Provider.of<AppState>(context);
    final isNarrow = Responsive.isNarrow(context);

    return Scaffold(
      key: _scaffoldKey,
      drawer: isNarrow ? const Drawer(width: 300, child: SourceExplorerWidget()) : null,
      endDrawer: isNarrow ? const Drawer(width: 350, child: ControlPanelWidget()) : null,
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                if (!isNarrow) ...[
                  const SizedBox(width: 280, child: SourceExplorerWidget()),
                  const VerticalDivider(width: 1, thickness: 1),
                ],
                Expanded(
                  child: Stack(
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1600),
                          child: const GalleryWidget(),
                        ),
                      ),
                      if (isNarrow)
                        Positioned(
                          left: 16,
                          bottom: 16,
                          child: FloatingActionButton.small(
                            heroTag: 'source_btn',
                            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                            child: const Icon(Icons.folder_open),
                          ),
                        ),
                      if (isNarrow)
                        Positioned(
                          right: 16,
                          bottom: 16,
                          child: FloatingActionButton(
                            heroTag: 'control_btn',
                            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                            child: const Icon(Icons.tune),
                          ),
                        ),
                    ],
                  ),
                ),
                if (!isNarrow) ...[
                  const VerticalDivider(width: 1, thickness: 1),
                  const SizedBox(width: 350, child: ControlPanelWidget()),
                ],
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
              subtitle: appState.isConsoleExpanded ? null : l10n.clickToExpand,
              isExpanded: appState.isConsoleExpanded,
              onToggle: () => appState.setConsoleExpanded(!appState.isConsoleExpanded),
              collapsedIcon: Icons.keyboard_arrow_up,
              expandedIcon: Icons.keyboard_arrow_down,
              content: const SizedBox(
                height: 200,
                child: LogConsoleWidget(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
