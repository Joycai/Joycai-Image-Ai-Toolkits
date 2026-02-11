import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../models/app_file.dart';
import '../../models/browser_file.dart';
import '../../services/image_metadata_service.dart';
import '../../state/app_state.dart';
import '../../state/browser_state.dart';
import '../../state/window_state.dart';
import '../../widgets/dialogs/image_preview_dialog.dart';
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
    final isNarrow = Responsive.isNarrow(context);

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
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1600),
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
          onDoubleTap: () {
            if (file.category == FileCategory.image) {
              _showPreviewDialog(context, state.filteredFiles, index);
            } else {
              _handleOpenFile(file);
            }
          },
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
          onDoubleTap: () {
            if (file.category == FileCategory.image) {
              _showPreviewDialog(context, state.filteredFiles, index);
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

  void _showPreviewDialog(BuildContext context, List<BrowserFile> allFiles, int initialIndex) {
    // Filter only images for the multi-image preview
    final images = allFiles.where((f) => f.category == FileCategory.image).toList();
    final currentFile = allFiles[initialIndex];
    final imageIndex = images.indexOf(currentFile);

    if (imageIndex == -1) return;

    showDialog(
      context: context,
      builder: (context) => ImagePreviewDialog(
        images: images.map((f) => AppFile(path: f.path, name: f.name)).toList(),
        initialIndex: imageIndex,
      ),
    );
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

  