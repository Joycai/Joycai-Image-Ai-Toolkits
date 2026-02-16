import 'package:flutter/material.dart';

import '../../../core/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../../state/file_browser_state.dart';

class BrowserToolbar extends StatelessWidget {
  final FileBrowserState state;
  final VoidCallback onAiRename;

  const BrowserToolbar({
    super.key,
    required this.state,
    required this.onAiRename,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final isNarrow = Responsive.isNarrow(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Text(
                    isNarrow ? '${state.selectedFiles.length}' : l10n.imagesSelected(state.selectedFiles.length),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => state.selectAll(),
                    icon: const Icon(Icons.select_all, size: 20),
                    tooltip: l10n.selectAll,
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    onPressed: state.selectedFiles.isEmpty ? null : () => state.clearSelection(),
                    icon: const Icon(Icons.deselect, size: 20),
                    tooltip: l10n.clear,
                    visualDensity: VisualDensity.compact,
                  ),

                  if (state.viewMode == BrowserViewMode.grid) ...[
                    const VerticalDivider(width: 24, indent: 8, endIndent: 8),
                    // Thumbnail Size Slider
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.image_outlined, size: 16, color: colorScheme.outline),
                        SizedBox(
                          width: 100,
                          child: Slider(
                            value: state.thumbnailSize,
                            min: 80,
                            max: 400,
                            onChanged: (v) => state.setThumbnailSize(v),
                          ),
                        ),
                        Icon(Icons.image, size: 20, color: colorScheme.outline),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          
          if (!isNarrow) ...[
            if (state.selectedFiles.isNotEmpty)
              FilledButton.icon(
                onPressed: onAiRename,
                icon: const Icon(Icons.auto_fix_high, size: 18),
                label: Text(l10n.aiBatchRename),
              ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(state.viewMode == BrowserViewMode.grid ? Icons.view_list : Icons.grid_view),
              onPressed: () => state.setViewMode(
                state.viewMode == BrowserViewMode.grid ? BrowserViewMode.list : BrowserViewMode.grid
              ),
              tooltip: l10n.switchViewMode,
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => state.refresh(),
              tooltip: l10n.refresh,
            ),
          ] else ...[
            if (state.selectedFiles.isNotEmpty)
              IconButton(
                onPressed: onAiRename,
                icon: const Icon(Icons.auto_fix_high, color: Colors.blue),
                tooltip: l10n.aiBatchRename,
              ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (val) {
                if (val == 'refresh') state.refresh();
                if (val == 'view_mode') {
                  state.setViewMode(
                    state.viewMode == BrowserViewMode.grid ? BrowserViewMode.list : BrowserViewMode.grid
                  );
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'refresh',
                  child: ListTile(
                    leading: const Icon(Icons.refresh),
                    title: Text(l10n.refresh),
                    dense: true,
                  ),
                ),
                PopupMenuItem(
                  value: 'view_mode',
                  child: ListTile(
                    leading: Icon(state.viewMode == BrowserViewMode.grid ? Icons.view_list : Icons.grid_view),
                    title: Text(l10n.switchViewMode),
                    dense: true,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}