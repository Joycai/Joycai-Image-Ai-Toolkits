import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/file_utils.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../models/app_image.dart';
import '../../models/browser_file.dart';
import '../../services/database_service.dart';
import '../../services/image_metadata_service.dart';
import '../../state/app_state.dart';
import '../../state/file_browser_state.dart';
import '../../state/workbench_ui_state.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/panel_resizer.dart';
import '../../widgets/unified_sidebar.dart';
import '../workbench/widgets/preview/media_preview_dialog.dart';
import 'ai_rename_dialog.dart';
import 'widgets/browser_filter_bar.dart';
import 'widgets/browser_selection_bar.dart';
import 'widgets/file_card.dart';
import 'widgets/file_context_menu.dart';

class FileBrowserScreen extends StatefulWidget {
  const FileBrowserScreen({super.key});

  @override
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen> {
  static const double _minSidebarWidth = 180;
  static const double _maxSidebarWidth = 420;

  final TextEditingController _searchController = TextEditingController();
  double _sidebarWidth = 260;

  @override
  void initState() {
    super.initState();
    _loadSidebarWidth();
  }

  Future<void> _loadSidebarWidth() async {
    final saved = await DatabaseService().getSetting('browser_sidebar_width');
    final width = double.tryParse(saved ?? '');
    if (width != null && mounted) {
      setState(() => _sidebarWidth = width.clamp(_minSidebarWidth, _maxSidebarWidth));
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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
                l10n.featureLimitedOnMobile,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.fileBrowserDesktopOnlyDesc,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 32),
              Text(
                Platform.isIOS
                    ? l10n.fileBrowseriOSHint
                    : l10n.fileBrowserAndroidHint,
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
    final fileBrowserState = appState.fileBrowserState;
    final colorScheme = Theme.of(context).colorScheme;
    final isNarrow = Responsive.isNarrow(context);

    final fileCount = fileBrowserState.filteredFiles.length;
    final selectedCount = fileBrowserState.selectedFiles.length;

    // Header lives inside the content card (its bottom border becomes an
    // internal divider on the inset-panel canvas).
    final header = Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withAlpha(90))),
      ),
      child: Row(
        children: [
          if (isNarrow)
            Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            )
          else ...[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.folder_open_rounded, size: 22, color: colorScheme.primary),
            ),
            const SizedBox(width: 14),
          ],
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.fileBrowser,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
              ),
              const SizedBox(height: 3),
              _buildHeaderSummary(fileCount, selectedCount, l10n, colorScheme),
            ],
          ),
          const SizedBox(width: 20),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: _buildSearchField(fileBrowserState, l10n, colorScheme),
            ),
          ),
          const Spacer(),
          AppIconButton(
            icon: fileBrowserState.viewMode == BrowserViewMode.grid
                ? Icons.view_list
                : Icons.grid_view,
            tooltip: l10n.switchViewMode,
            onPressed: () => fileBrowserState.setViewMode(
              fileBrowserState.viewMode == BrowserViewMode.grid
                  ? BrowserViewMode.list
                  : BrowserViewMode.grid,
            ),
          ),
          const SizedBox(width: 8),
          AppIconButton(
            icon: Icons.refresh,
            tooltip: l10n.refresh,
            onPressed: () => fileBrowserState.refresh(),
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainer,
      drawer: isNarrow
          ? const Drawer(child: UnifiedSidebar(useFileBrowserState: true))
          : null,
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            if (!isNarrow) ...[
              PanelCard(
                width: _sidebarWidth,
                child: const UnifiedSidebar(useFileBrowserState: true),
              ),
              PanelResizer(
                onDrag: (dx) => setState(() {
                  _sidebarWidth = (_sidebarWidth + dx).clamp(_minSidebarWidth, _maxSidebarWidth);
                }),
                onDragEnd: () => DatabaseService()
                    .saveSetting('browser_sidebar_width', _sidebarWidth.round().toString()),
              ),
            ],
            Expanded(
              child: PanelCard(
                child: Column(
                  children: [
                    header,
                    BrowserFilterBar(state: fileBrowserState),
                    Expanded(
                      child: Stack(
                        children: [
                          fileBrowserState.viewMode == BrowserViewMode.grid
                              ? _buildFileGrid(context, fileBrowserState)
                              : _buildFileListView(context, fileBrowserState),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 16,
                            child: Center(
                              child: BrowserSelectionBar(
                                state: fileBrowserState,
                                onAiRename: () => _showAiRenameDialog(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// What the folder holds, and how much of it you have picked. The selection
  /// is in the primary colour because it is the half that changes as you work.
  Widget _buildHeaderSummary(
    int fileCount,
    int selectedCount,
    AppLocalizations l10n,
    ColorScheme colorScheme,
  ) {
    return Text.rich(
      TextSpan(
        style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
        children: [
          TextSpan(
            text: l10n.filesCount(fileCount),
            style: TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.w600),
          ),
          if (selectedCount > 0) ...[
            TextSpan(text: '  ·  ', style: TextStyle(color: colorScheme.outline)),
            TextSpan(
              text: l10n.imagesSelected(selectedCount),
              style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildSearchField(FileBrowserState state, AppLocalizations l10n, ColorScheme colorScheme) {
    return SizedBox(
      height: 40,
      child: TextField(
        controller: _searchController,
        onChanged: (v) => state.setSearchQuery(v),
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: l10n.searchFilesHint,
          hintStyle: TextStyle(fontSize: 13, color: colorScheme.outline),
          prefixIcon: Icon(Icons.search, size: 18, color: colorScheme.outline),
          suffixIcon: state.searchQuery.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () {
                    _searchController.clear();
                    state.setSearchQuery('');
                  },
                  visualDensity: VisualDensity.compact,
                ),
          isDense: true,
          contentPadding: EdgeInsets.zero,
          filled: true,
          fillColor: colorScheme.surfaceContainerHighest.withAlpha(80),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildFileGrid(BuildContext context, FileBrowserState state) {
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
              onDoubleTap: () => _openWithPreview(context, file, state),
              onSecondaryTap: (pos) => _showContextMenu(context, file, pos),
            );
          },
        );
      }
    );
  }

  Widget _buildFileListView(BuildContext context, FileBrowserState state) {
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
          onDoubleTap: () => _openWithPreview(context, file, state),
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

  void _openWithPreview(BuildContext context, BrowserFile file, FileBrowserState state) {
    if (file.category == FileCategory.image || file.category == FileCategory.video) {
      final mediaFiles = state.filteredFiles
          .where((f) => f.category == file.category)
          .map((f) => AppImage(path: f.path, name: f.name))
          .toList();
      final idx = mediaFiles.indexWhere((m) => m.path == file.path);
      showMediaPreview(context, galleryImages: mediaFiles, initialIndex: idx >= 0 ? idx : 0);
    } else {
      _handleOpenFile(file);
    }
  }

  Future<void> _handleOpenFile(BrowserFile file) async {
    await FileUtils.openPath(file.path);
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
    final state = Provider.of<AppState>(context, listen: false).fileBrowserState;
    showFileContextMenu(
      context: context,
      file: file,
      position: position,
      workbenchUIState: Provider.of<WorkbenchUIState>(context, listen: false),
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