import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../models/browser_file.dart';
import '../../services/image_metadata_service.dart';
import '../../state/app_state.dart';
import '../../state/browser_state.dart';
import '../../state/window_state.dart';
import '../../widgets/unified_sidebar.dart';
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
    final l10n = AppLocalizations.of(context)!;
    final isNarrow = Responsive.isNarrow(context);

    return Scaffold(
      key: _scaffoldKey,
      appBar: isNarrow ? AppBar(
        title: Text(l10n.fileBrowser),
        leading: IconButton(
          icon: const Icon(Icons.view_sidebar),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          tooltip: l10n.sidebar,
        ),
        actions: [
          IconButton(
            icon: Icon(browserState.viewMode == BrowserViewMode.grid ? Icons.view_list : Icons.grid_view),
            onPressed: () => browserState.setViewMode(
              browserState.viewMode == BrowserViewMode.grid ? BrowserViewMode.list : BrowserViewMode.grid
            ),
            tooltip: l10n.switchViewMode,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => browserState.refresh(),
            tooltip: l10n.refresh,
          ),
        ],
      ) : null,
      drawer: isNarrow ? const Drawer(width: 300, child: UnifiedSidebar(useBrowserState: true)) : null,
      body: Stack(
        children: [
          // Layer 1: Main Content
          Row(
            children: [
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1600),
                    child: Column(
                      children: [
                        if (!isNarrow)
                          Row(
                            children: [
                              IconButton(
                                icon: Icon(appState.isSidebarExpanded ? Icons.menu_open : Icons.menu),
                                onPressed: () => appState.setSidebarExpanded(!appState.isSidebarExpanded),
                                tooltip: appState.isSidebarExpanded ? "Collapse Sidebar" : "Expand Sidebar",
                              ),
                              Expanded(
                                child: BrowserToolbar(
                                  state: browserState,
                                  onAiRename: () => _showAiRenameDialog(context),
                                ),
                              ),
                            ],
                          )
                        else
                          BrowserToolbar(
                            state: browserState,
                            onAiRename: () => _showAiRenameDialog(context),
                          ),
                        
                        BrowserFilterBar(state: browserState),
                        Expanded(
                          child: browserState.viewMode == BrowserViewMode.grid
                              ? _buildFileGrid(context, browserState)
                              : _buildFileListView(context, browserState),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Layer 2: Scrim
          if (!isNarrow && appState.isSidebarExpanded)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => appState.setSidebarExpanded(false),
                child: Container(
                  color: Colors.black.withAlpha(100),
                ),
              ),
            ),

          // Layer 3: Overlay Sidebar
          if (!isNarrow)
            AnimatedPositioned(
              duration: appState.isSidebarResizing ? Duration.zero : const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              left: appState.isSidebarExpanded ? 0 : -appState.sidebarWidth,
              top: 0,
              bottom: 0,
              width: appState.sidebarWidth,
              child: Material(
                elevation: 16,
                shadowColor: Colors.black54,
                child: const UnifiedSidebar(useBrowserState: true),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFileGrid(BuildContext context, BrowserState state) {
    if (state.filteredFiles.isEmpty) return _buildEmptyState(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= 0) return const SizedBox.shrink();

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
              onDoubleTap: () {
                if (file.category == FileCategory.image) {
                  final appState = Provider.of<AppState>(context, listen: false);
                  appState.windowState.openPreview(file.path);
                  appState.setSidebarMode(SidebarMode.preview);
                  if (!appState.isSidebarExpanded) appState.setSidebarExpanded(true);
                } else {
                  _handleOpenFile(file);
                }
              },
              onSecondaryTap: (pos) => _showContextMenu(context, file, pos),
            );
          },
        );
      }
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
          onDoubleTap: () {
            if (file.category == FileCategory.image) {
              final appState = Provider.of<AppState>(context, listen: false);
              appState.windowState.openPreview(file.path);
              appState.setSidebarMode(SidebarMode.preview);
              if (!appState.isSidebarExpanded) appState.setSidebarExpanded(true);
            } else {
              _handleOpenFile(file);
            }
          },
          child: ListTile(
            leading: Icon(file.icon, color: file.color),
            title: Text(file.name, style: const TextStyle(fontSize: 13)),
            subtitle: _FileListItemSubtitle(file: file),
            selected: isSelected,
            onTap: () => state.toggleSelection(file),
            trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.blue) : null,
          ),
        );
      },
    );
  }

  Future<void> _handleOpenFile(BrowserFile file) async {
    final uri = Uri.file(file.path);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
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
    final state = Provider.of<AppState>(context, listen: false).browserState;
    showFileContextMenu(
      context: context,
      file: file,
      position: position,
      windowState: Provider.of<WindowState>(context, listen: false),
      onRefresh: () => state.refresh(),
    );
  }
}

class _FileListItemSubtitle extends StatefulWidget {
  final BrowserFile file;
  const _FileListItemSubtitle({required this.file});

  @override
  State<_FileListItemSubtitle> createState() => _FileListItemSubtitleState();
}

class _FileListItemSubtitleState extends State<_FileListItemSubtitle> {
  String _extraInfo = "";

  @override
  void initState() {
    super.initState();
    if (widget.file.category == FileCategory.image) {
      _loadDimensions();
    }
  }

  @override
  void didUpdateWidget(_FileListItemSubtitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.file.path != oldWidget.file.path) {
      _extraInfo = "";
      if (widget.file.category == FileCategory.image) {
        _loadDimensions();
      }
    }
  }

  Future<void> _loadDimensions() async {
    final metadata = await ImageMetadataService().getMetadata(widget.file.path);
    if (metadata != null && mounted) {
      setState(() {
        _extraInfo = " | ${metadata.width}x${metadata.height} (${metadata.aspectRatio})";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sizeStr = AppConstants.formatFileSize(widget.file.size);
    return Text(
      "$sizeStr | ${widget.file.modified.toString().substring(0, 16)}$_extraInfo",
      style: const TextStyle(fontSize: 11),
    );
  }
}