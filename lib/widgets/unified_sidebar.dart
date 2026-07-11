import 'package:flutter/material.dart';

import '../screens/workbench/folder_list.dart';

class UnifiedSidebar extends StatelessWidget {
  final bool useFileBrowserState;

  const UnifiedSidebar({
    super.key,
    this.useFileBrowserState = false,
  });

  @override
  Widget build(BuildContext context) {
    // Transparent: the hosting PanelCard (desktop) or Drawer (narrow/mobile)
    // provides the background surface.
    return Material(
      color: Colors.transparent,
      child: FolderList(useFileBrowserState: useFileBrowserState),
    );
  }
}
