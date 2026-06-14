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
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surfaceContainerHighest.withAlpha((255 * 0.2).round()),
      child: FolderList(useFileBrowserState: useFileBrowserState),
    );
  }
}
