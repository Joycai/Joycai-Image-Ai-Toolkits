import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/workbench/sidebar/mask_editor_sidebar.dart';
import '../screens/workbench/source_explorer.dart';
import '../screens/workbench/tabs/comparator_tab.dart';
import '../screens/workbench/tabs/preview_tab.dart';
import '../state/app_state.dart';

class UnifiedSidebar extends StatelessWidget {
  final bool useBrowserState;

  const UnifiedSidebar({
    super.key,
    this.useBrowserState = false,
  });

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final colorScheme = Theme.of(context).colorScheme;

    if (!appState.isSidebarExpanded) {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        // Navigation Rail
        Container(
          width: 50,
          color: colorScheme.surfaceContainerHighest.withAlpha((255 * 0.5).round()),
          child: Column(
            children: [
              const SizedBox(height: 8),
              _SidebarNavItem(
                icon: Icons.folder_open,
                isSelected: appState.sidebarMode == SidebarMode.directories,
                onTap: () => appState.setSidebarMode(SidebarMode.directories),
                tooltip: "Directories",
              ),
              _SidebarNavItem(
                icon: Icons.visibility,
                isSelected: appState.sidebarMode == SidebarMode.preview,
                onTap: () => appState.setSidebarMode(SidebarMode.preview),
                tooltip: "Preview",
              ),
              _SidebarNavItem(
                icon: Icons.compare,
                isSelected: appState.sidebarMode == SidebarMode.comparator,
                onTap: () => appState.setSidebarMode(SidebarMode.comparator),
                tooltip: "Comparator",
              ),
              _SidebarNavItem(
                icon: Icons.brush,
                isSelected: appState.sidebarMode == SidebarMode.maskEditor,
                onTap: () => appState.setSidebarMode(SidebarMode.maskEditor),
                tooltip: "Mask Editor",
              ),
            ],
          ),
        ),
        
        // Content Area (Expanded to take remaining space)
        Expanded(
          child: Container(
            color: colorScheme.surfaceContainerHighest.withAlpha((255 * 0.2).round()),
            child: _buildSidebarContent(context, appState),
          ),
        ),

        // Resize Handle
        GestureDetector(
          onHorizontalDragUpdate: (details) {
            appState.setSidebarWidth(appState.sidebarWidth + details.delta.dx);
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            child: Container(
              width: 4,
              color: colorScheme.outlineVariant.withAlpha(50),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSidebarContent(BuildContext context, AppState appState) {
    switch (appState.sidebarMode) {
      case SidebarMode.directories:
        return SourceExplorerWidget(useBrowserState: useBrowserState);
      case SidebarMode.preview:
        return const PreviewTab();
      case SidebarMode.comparator:
        return const ComparatorTab();
      case SidebarMode.maskEditor:
        return const MaskEditorSidebarView();
    }
  }
}

class _SidebarNavItem extends StatelessWidget {
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final String tooltip;

  const _SidebarNavItem({
    required this.icon,
    required this.isSelected,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: IconButton(
        icon: Icon(icon, color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant),
        onPressed: onTap,
        tooltip: tooltip,
        style: IconButton.styleFrom(
          backgroundColor: isSelected ? colorScheme.primaryContainer : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}
