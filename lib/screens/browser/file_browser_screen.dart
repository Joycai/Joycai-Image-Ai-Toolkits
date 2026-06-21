import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/file_utils.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../models/app_image.dart';
import '../../models/browser_file.dart';
import '../../services/image_metadata_service.dart';
import '../../state/app_state.dart';
import '../../state/file_browser_state.dart';
import '../../state/workbench_ui_state.dart';
import '../../widgets/unified_sidebar.dart';
import '../workbench/widgets/preview/media_preview_dialog.dart';
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

    final sidebar = Container(
      width: isNarrow ? null : 300,
      color: colorScheme.surfaceContainerLow,
      child: const UnifiedSidebar(useFileBrowserState: true),
    );

    final fileCount = fileBrowserState.filteredFiles.length;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: colorScheme.surface,
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
                ),
              Icon(Icons.folder_open, size: 24, color: colorScheme.primary),
              const SizedBox(width: 12),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.fileBrowser,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  Text(
                    l10n.filesCount(fileCount),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
              const Spacer(),
              if (!isNarrow) ...[
                IconButton(
                  icon: Icon(fileBrowserState.viewMode == BrowserViewMode.grid
                      ? Icons.view_list
                      : Icons.grid_view),
                  onPressed: () => fileBrowserState.setViewMode(
                    fileBrowserState.viewMode == BrowserViewMode.grid
                        ? BrowserViewMode.list
                        : BrowserViewMode.grid,
                  ),
                  tooltip: l10n.switchViewMode,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => fileBrowserState.refresh(),
                  tooltip: l10n.refresh,
                ),
                const SizedBox(width: 4),
                _GradientButton(
                  icon: Icons.auto_fix_high,
                  label: l10n.aiBatchRename,
                  onPressed: () => _showAiRenameDialog(context),
                  colorScheme: colorScheme,
                ),
              ],
            ],
          ),
        ),
      ),
      drawer: isNarrow ? Drawer(child: sidebar) : null,
      body: Row(
        children: [
          if (!isNarrow) ...[
            sidebar,
            const VerticalDivider(width: 1),
          ],
          Expanded(
            child: Container(
              color: colorScheme.surface,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: BrowserToolbar(
                      state: fileBrowserState,
                      onAiRename: () => _showAiRenameDialog(context),
                    ),
                  ),
                  BrowserFilterBar(state: fileBrowserState),
                  const Divider(height: 1),
                  Expanded(
                    child: fileBrowserState.viewMode == BrowserViewMode.grid
                        ? _buildFileGrid(context, fileBrowserState)
                        : _buildFileListView(context, fileBrowserState),
                  ),
                ],
              ),
            ),
          ),
        ],
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

/// Gradient-filled button matching the design's accent → accent2 gradient style.
class _GradientButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final ColorScheme colorScheme;

  const _GradientButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [colorScheme.primary, const Color(0xFFB794F6)],
          ),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
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