import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/workbench/folder_list.dart';
import '../state/app_state.dart';

class UnifiedSidebar extends StatelessWidget {
  final bool useFileBrowserState;

  const UnifiedSidebar({
    super.key,
    this.useFileBrowserState = false,
  });

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        // Content Area (Now takes full width of the panel)
        Expanded(
          child: Container(
            color: colorScheme.surfaceContainerHighest.withAlpha((255 * 0.2).round()),
            child: FolderList(useFileBrowserState: useFileBrowserState),
          ),
        ),

        // Resize Handle (Desktop Only)
        GestureDetector(
          onHorizontalDragStart: (_) => appState.setIsSidebarResizing(true),
          onHorizontalDragUpdate: (details) {
            appState.setSidebarWidth(appState.sidebarWidth + details.delta.dx);
          },
          onHorizontalDragEnd: (_) => appState.setIsSidebarResizing(false),
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            child: Container(
              width: 4,
              color: colorScheme.outlineVariant.withAlpha(50),
              child: Center(
                child: Container(
                  width: 1,
                  color: colorScheme.outlineVariant.withAlpha(100),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
