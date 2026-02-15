import 'dart:io';

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
import '../workbench/widgets/image_preview_dialog.dart';
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
    final l10n = AppLocalizations.of(context)!;
    final bool isMobile = Platform.isIOS || Platform.isAndroid;

    if (isMobile) {
      return _buildMobileRestrictedView(l10n);
    }

    return _buildDesktopLayout(l10n);
  }

  Widget _buildMobileRestrictedView(AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.fileBrowser),
        backgroundColor: colorScheme.surface,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.desktop_access_disabled_outlined, size: 80, color: colorScheme.outline.withAlpha(100)),
              const SizedBox(height: 24),
              Text(
                "Feature Limited on Mobile",
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                "Due to OS sandboxing restrictions, the advanced file browser and mass renaming features are only available on Desktop versions.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 32),
              Text(
                Platform.isIOS 
                  ? "Please use the system 'Files' app to manage your generated images."
                  : "Please use your device's file manager to organize files.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: colorScheme.primary, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(AppLocalizations l10n) {
    final appState = Provider.of<AppState>(context);
    final browserState = appState.browserState;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(l10n.fileBrowser, style: const TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colorScheme.surface,
        centerTitle: false,
        actions: [
          IconButton.filledTonal(
            icon: Icon(browserState.viewMode == BrowserViewMode.grid ? Icons.view_list : Icons.grid_view, size: 20),
            onPressed: () => browserState.setViewMode(
              browserState.viewMode == BrowserViewMode.grid ? BrowserViewMode.list : BrowserViewMode.grid
            ),
            tooltip: l10n.switchViewMode,
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: () => browserState.refresh(),
            tooltip: l10n.refresh,
          ),
          const SizedBox(width: 16),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: colorScheme.outlineVariant.withAlpha(100)),
        ),
      ),
      body: Row(
        children: [
          // Sidebar
          Container(
            width: 300,
            color: colorScheme.surfaceContainerLow,
            child: const UnifiedSidebar(useBrowserState: true),
          ),
          const VerticalDivider(width: 1),
          // Main Content
          Expanded(
            child: Container(
              color: colorScheme.surface,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: BrowserToolbar(
                      state: browserState,
                      onAiRename: () => _showAiRenameDialog(context),
                    ),
                  ),
                  BrowserFilterBar(state: browserState),
                  const Divider(height: 1),
                  Expanded(
                    child: browserState.viewMode == BrowserViewMode.grid
                        ? _buildFileGrid(context, browserState)
                        : _buildFileListView(context, browserState),
                  ),
                ],
              ),
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
                  showImagePreview(context, file.path);
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
              showImagePreview(context, file.path);
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