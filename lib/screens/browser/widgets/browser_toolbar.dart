import 'package:flutter/material.dart';

import '../../../core/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../../state/browser_state.dart';

class BrowserToolbar extends StatelessWidget {
  final BrowserState state;
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
    final isMobile = Responsive.isMobile(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor, width: 0.5)),
      ),
      child: Row(
        children: [
          Text(
            isMobile ? '${state.selectedFiles.length}' : l10n.imagesSelected(state.selectedFiles.length),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 16),
          if (!isMobile) ...[
            TextButton.icon(
              onPressed: () => state.selectAll(),
              icon: const Icon(Icons.select_all, size: 18),
              label: Text(l10n.selectAll),
            ),
            TextButton.icon(
              onPressed: state.selectedFiles.isEmpty ? null : () => state.clearSelection(),
              icon: const Icon(Icons.deselect, size: 18),
              label: Text(l10n.clear),
            ),
            const Spacer(),
            if (state.selectedFiles.isNotEmpty)
              FilledButton.icon(
                onPressed: onAiRename,
                icon: const Icon(Icons.auto_fix_high, size: 18),
                label: Text(l10n.aiBatchRename),
              ),
            const SizedBox(width: 8),
            
            if (state.viewMode == BrowserViewMode.grid) ...[
              const VerticalDivider(width: 24, indent: 8, endIndent: 8),
              Tooltip(
                message: l10n.thumbnailSize,
                child: Row(
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
              ),
            ],

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
            const Spacer(),
            if (state.selectedFiles.isNotEmpty)
              IconButton(
                onPressed: onAiRename,
                icon: const Icon(Icons.auto_fix_high, color: Colors.blue),
                tooltip: l10n.aiBatchRename,
              ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (val) {
                if (val == 'select_all') state.selectAll();
                if (val == 'clear') state.clearSelection();
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'select_all',
                  child: ListTile(
                    leading: const Icon(Icons.select_all),
                    title: Text(l10n.selectAll),
                    dense: true,
                  ),
                ),
                PopupMenuItem(
                  value: 'clear',
                  enabled: state.selectedFiles.isNotEmpty,
                  child: ListTile(
                    leading: const Icon(Icons.deselect),
                    title: Text(l10n.clear),
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