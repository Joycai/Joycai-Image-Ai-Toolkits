import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/browser_file.dart';
import '../../state/app_state.dart';
import '../../state/browser_state.dart';
import '../../state/window_state.dart';
import '../workbench/source_explorer.dart';
import 'ai_rename_dialog.dart';
import 'widgets/browser_filter_bar.dart';
import 'widgets/browser_toolbar.dart';
import 'widgets/file_card.dart';
import 'widgets/file_context_menu.dart';

class FileBrowserScreen extends StatefulWidget {
  const FileBrowserScreen({super.key});

  @override
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final browserState = appState.browserState;
    final size = MediaQuery.of(context).size;
    final isNarrow = size.width < 1000;

    return Scaffold(
      key: _scaffoldKey,
      drawer: isNarrow ? const Drawer(width: 300, child: SourceExplorerWidget(useBrowserState: true)) : null,
      body: Row(
        children: [
          if (!isNarrow) ...[
            const SizedBox(width: 280, child: SourceExplorerWidget(useBrowserState: true)),
            const VerticalDivider(width: 1, thickness: 1),
          ],
          Expanded(
            child: Column(
              children: [
                BrowserToolbar(
                  state: browserState,
                  onAiRename: () => _showAiRenameDialog(context),
                ),
                BrowserFilterBar(state: browserState),
                Expanded(
                  child: Stack(
                    children: [
                      browserState.viewMode == BrowserViewMode.grid
                          ? _buildFileGrid(context, browserState)
                          : _buildFileListView(context, browserState),
                      if (isNarrow)
                        Positioned(
                          left: 16,
                          bottom: 16,
                          child: FloatingActionButton.small(
                            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                            child: const Icon(Icons.folder_open),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileGrid(BuildContext context, BrowserState state) {
    if (state.filteredFiles.isEmpty) return _buildEmptyState(context);

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: state.thumbnailSize,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: state.filteredFiles.length,
      itemBuilder: (context, index) {
        final file = state.filteredFiles[index];
        return FileCard(
          file: file,
          isSelected: state.selectedFiles.contains(file),
          thumbnailSize: state.thumbnailSize,
          onTap: () => state.toggleSelection(file),
          onSecondaryTap: (pos) => _showContextMenu(context, file, pos),
        );
      },
    );
  }

  Widget _buildFileListView(BuildContext context, BrowserState state) {
    if (state.filteredFiles.isEmpty) return _buildEmptyState(context);

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: state.filteredFiles.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final file = state.filteredFiles[index];
        final isSelected = state.selectedFiles.contains(file);
        return GestureDetector(
          onSecondaryTapDown: (details) => _showContextMenu(context, file, details.globalPosition),
          child: ListTile(
            leading: Icon(file.icon, color: file.color),
            title: Text(file.name, style: const TextStyle(fontSize: 13)),
            subtitle: Text(
              "${(file.size / 1024).toStringAsFixed(1)} KB | ${file.modified.toString().substring(0, 16)}",
              style: const TextStyle(fontSize: 11),
            ),
            selected: isSelected,
            onTap: () => state.toggleSelection(file),
            trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.blue) : null,
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(child: Text(AppLocalizations.of(context)!.noFilesFound));
  }

  void _showAiRenameDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AiRenameDialog(),
    );
  }

  void _showContextMenu(BuildContext context, BrowserFile file, Offset position) {
    showFileContextMenu(
      context: context,
      file: file,
      position: position,
      windowState: Provider.of<WindowState>(context, listen: false),
    );
  }
}