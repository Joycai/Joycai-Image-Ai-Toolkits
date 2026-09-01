import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../core/constants.dart';
import '../../core/design_tokens.dart';
import '../../core/file_utils.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../models/app_image.dart';
import '../../models/browser_file.dart';
import '../../services/database_service.dart';
import '../../services/image_metadata_service.dart';
import '../../state/app_state.dart';
import '../../state/file_browser_state.dart';
import '../../state/file_staging_state.dart';
import '../../state/workbench_ui_state.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/app_search_field.dart';
import '../../widgets/app_run_console.dart';
import '../../widgets/app_segmented_control.dart';
import '../../widgets/app_side_panel.dart';
import '../../widgets/app_window_frame.dart';
import '../../widgets/dialogs/file_rename_dialog.dart';
import '../../widgets/panel_resizer.dart';
import '../../widgets/unified_sidebar.dart';
import '../workbench/widgets/preview/media_preview_dialog.dart';
import 'ai_rename_dialog.dart';
import 'staging_paste_flow.dart';
import 'widgets/browser_filter_bar.dart';
import 'widgets/browser_selection_bar.dart';
import 'widgets/browser_staging_panel.dart';
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
  final FocusNode _searchFocusNode = FocusNode();
  double _sidebarWidth = 260;

  /// Whether the staging column is showing. `12a` keeps it out of the way
  /// until it has something to hold — it costs 300px, which is two of the
  /// grid's six columns — so it opens the first time anything is staged and
  /// is closable from the toolbar afterwards.
  bool _stagingOpen = false;
  bool _stagingAutoOpened = false;

  /// Drag accumulator, allowed [_kDragSlack] past the limits so the handle
  /// re-engages where the pointer actually is after a drag past the end,
  /// instead of the instant the pointer reverses. Null when no drag is live.
  static const double _kDragSlack = 24;
  double? _dragSidebarWidth;

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
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// Screen-level shortcuts. Implemented with [Focus.onKeyEvent] rather than
  /// [CallbackShortcuts] so keys can conditionally fall through: while the
  /// search field has focus, Ctrl+A/Enter must keep their text-editing
  /// behavior, which requires returning [KeyEventResult.ignored].
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final state = Provider.of<AppState>(context, listen: false).fileBrowserState;
    final key = event.logicalKey;
    final hw = HardwareKeyboard.instance;
    final isCtrl = Platform.isMacOS ? hw.isMetaPressed : hw.isControlPressed;

    if (isCtrl && key == LogicalKeyboardKey.keyF) {
      _searchFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f5 || (isCtrl && key == LogicalKeyboardKey.keyR)) {
      state.refresh();
      return KeyEventResult.handled;
    }

    if (_searchFocusNode.hasFocus) {
      if (key == LogicalKeyboardKey.escape) {
        _searchController.clear();
        state.setSearchQuery('');
        _searchFocusNode.unfocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (isCtrl && key == LogicalKeyboardKey.keyA) {
      state.selectAll();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape && state.selectedFiles.isNotEmpty) {
      state.clearSelection();
      return KeyEventResult.handled;
    }
    if ((key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) &&
        state.selectedFiles.isNotEmpty) {
      _openWithPreview(context, state.selectedFiles.first, state);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f2 && state.selectedFiles.length == 1) {
      showFileRenameDialog(
        context: context,
        filePath: state.selectedFiles.first.path,
        onSuccess: () => state.refresh(),
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
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
                style: Theme.of(context).textTheme.titleLarge,
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
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: colorScheme.primary, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(AppLocalizations l10n) {
    final fileBrowserState = context.watch<FileBrowserState>();
    final staging = context.watch<FileStagingState>();
    final colorScheme = Theme.of(context).colorScheme;
    final isNarrow = Responsive.isNarrow(context);

    // The panel earns its width the moment there is something in it, and only
    // the first time — reopening it after the user closed it would be the app
    // arguing with them.
    if (staging.isNotEmpty && !_stagingAutoOpened) {
      _stagingAutoOpened = true;
      _stagingOpen = true;
    } else if (staging.isEmpty && _stagingAutoOpened) {
      _stagingAutoOpened = false;
    }

    // At tablet width the grid cannot spare 300px, so the panel becomes a
    // sheet reached from the toolbar button instead of a column.
    final showStagingColumn = _stagingOpen && !isNarrow;

    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        // Transparent over the window's backdrop, exactly as `A1` does it: the
        // side columns and the header are opaque and paint over the mesh, and
        // the file grid between them does not. Falls back to the canvas colour
        // where there is no custom window frame to show through to.
        backgroundColor: usesCustomWindowChrome
            ? Colors.transparent
            : colorScheme.surfaceContainer,
        drawer: isNarrow
            ? const Drawer(child: UnifiedSidebar(useFileBrowserState: true))
            : null,
        bottomNavigationBar: const AppRunConsole(),
        body: Row(
            children: [
              if (!isNarrow) ...[
                PanelCard(
                  width: _sidebarWidth,
                  shape: PanelShape.column,
                  child: const UnifiedSidebar(useFileBrowserState: true),
                ),
                PanelResizer(
                  shape: PanelShape.column,
                  onDrag: (dx) => setState(() {
                    _dragSidebarWidth = ((_dragSidebarWidth ?? _sidebarWidth) + dx)
                        .clamp(_minSidebarWidth - _kDragSlack, _maxSidebarWidth + _kDragSlack);
                    _sidebarWidth = _dragSidebarWidth!.clamp(_minSidebarWidth, _maxSidebarWidth);
                  }),
                  onDragEnd: () {
                    _dragSidebarWidth = null;
                    DatabaseService()
                        .saveSetting('browser_sidebar_width', _sidebarWidth.round().toString());
                  },
                ),
              ],
              Expanded(
                child: PanelCard(
                  shape: PanelShape.column,
                  // The centre column paints nothing; its header and filter bar
                  // carry their own opaque grounds and the grid below them is
                  // bare. This is `B1`'s answer to the question the old frame
                  // left open, and it is the same answer `A1` gives.
                  ground: Colors.transparent,
                  child: Column(
                    children: [
                      _buildHeader(fileBrowserState, staging, l10n, colorScheme, isNarrow),
                      BrowserFilterBar(state: fileBrowserState),
                      Expanded(
                        child: Stack(
                          children: [
                            fileBrowserState.viewMode == BrowserViewMode.grid
                                ? _buildFileGrid(context, fileBrowserState, staging)
                                : _buildFileListView(context, fileBrowserState, staging),
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 16,
                              child: Center(
                                child: BrowserSelectionBar(
                                  state: fileBrowserState,
                                  onAiRename: () => _showAiRenameDialog(context),
                                  onAddToStaging: () => _addSelectionToStaging(fileBrowserState, staging),
                                  allSelectionStaged: fileBrowserState.selectedFiles.isNotEmpty &&
                                      fileBrowserState.selectedFiles
                                          .every((f) => staging.contains(f.path)),
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
              if (showStagingColumn)
                BrowserStagingPanel(
                  destination: staging.destination,
                  onPaste: (mode) => runStagingPaste(context, mode: mode),
                ),
            ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    FileBrowserState state,
    FileStagingState staging,
    AppLocalizations l10n,
    ColorScheme colorScheme,
    bool isNarrow,
  ) {
    // Header lives inside the content card; its bottom border is the hairline
    // between the opaque bar and the transparent grid under it.
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
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
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colorScheme.accentTint,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Icon(Icons.folder_open_rounded, size: 20, color: colorScheme.onAccentTint),
            ),
            const SizedBox(width: 12),
          ],
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.fileBrowser, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 2),
              _buildHeaderSummary(
                state.filteredFiles.length,
                state.selectedFiles.length,
                l10n,
                colorScheme,
              ),
            ],
          ),
          const SizedBox(width: 12),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460, minWidth: 120),
              child: SizedBox(
                height: 34,
                child: AppSearchField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  hint: l10n.searchFilesHint,
                  onChanged: state.setSearchQuery,
                ),
              ),
            ),
          ),
          const Spacer(),
          _StagingToolbarButton(
            count: staging.count,
            open: _stagingOpen,
            onPressed: () {
              if (Responsive.isNarrow(context)) {
                _showStagingSheet(context);
              } else {
                setState(() => _stagingOpen = !_stagingOpen);
              }
            },
          ),
          const SizedBox(width: 10),
          AppSegmentedControl<BrowserViewMode>(
            segments: [
              AppSegment(value: BrowserViewMode.grid, label: l10n.catAll, icon: Icons.grid_view),
              AppSegment(value: BrowserViewMode.list, label: l10n.switchViewMode, icon: Icons.view_list),
            ],
            value: state.viewMode,
            onChanged: state.setViewMode,
            compact: true,
            iconOnly: true,
            // The chosen view lifts out of the track rather than tinting: the
            // accent on this screen means a selected *file*, and spending it
            // on the navigation is what leaves the selection nothing to say.
            style: AppSegmentStyle.raised,
          ),
          const SizedBox(width: 10),
          AppIconButton(
            icon: Icons.refresh,
            tooltip: l10n.refresh,
            onPressed: () => state.refresh(),
          ),
        ],
      ),
    );
  }

  /// What the folder holds, and how much of it you have picked. Both halves in
  /// mono — they are counts, and they change under the pointer, so they must
  /// not reflow the line as the digits change.
  Widget _buildHeaderSummary(
    int fileCount,
    int selectedCount,
    AppLocalizations l10n,
    ColorScheme colorScheme,
  ) {
    final base = Theme.of(context).textTheme.bodySmall?.mono;
    return Text.rich(
      TextSpan(
        style: base?.copyWith(color: colorScheme.outline),
        children: [
          TextSpan(text: l10n.filesCount(fileCount)),
          if (selectedCount > 0) ...[
            const TextSpan(text: '  ·  '),
            TextSpan(
              text: l10n.imagesSelected(selectedCount),
              style: TextStyle(color: colorScheme.onAccentTint, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  void _addSelectionToStaging(FileBrowserState state, FileStagingState staging) {
    staging.addAll(state.selectedFiles);
  }

  /// The staging panel where there is no room for a column.
  Future<void> _showStagingSheet(BuildContext context) {
    return AppSidePanel.show(
      context,
      width: kStagingPanelWidth,
      builder: (sheetContext) {
        final staging = sheetContext.watch<FileStagingState>();
        return BrowserStagingPanel(
          destination: staging.destination,
          onPaste: (mode) {
            Navigator.pop(sheetContext);
            runStagingPaste(context, mode: mode);
          },
        );
      },
    );
  }

  Widget _buildFileGrid(BuildContext context, FileBrowserState state, FileStagingState staging) {
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
              isStaged: staging.contains(file.path),
              thumbnailSize: state.thumbnailSize,
              heroScope: kBrowserPreviewHeroScope,
              onTap: () => _handleSelectionTap(state, file),
              onDoubleTap: () => _openWithPreview(context, file, state),
              onSecondaryTap: (pos) => _showContextMenu(context, file, pos),
            );
          },
        );
      }
    );
  }

  Widget _buildFileListView(BuildContext context, FileBrowserState state, FileStagingState staging) {
    if (state.filteredFiles.isEmpty) return _buildEmptyState(context);

    final colorScheme = Theme.of(context).colorScheme;

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: state.filteredFiles.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final file = state.filteredFiles[index];
        final isSelected = state.selectedFiles.contains(file);
        final isStaged = staging.contains(file.path);
        return GestureDetector(
          onSecondaryTapDown: (details) => _showContextMenu(context, file, details.globalPosition),
          onDoubleTap: () => _openWithPreview(context, file, state),
          child: ListTile(
            leading: Icon(file.icon, color: file.color),
            // ListTile tints a selected title with `primary`; the slot carries
            // `onSurface`, so that tint has to be re-stated or it is lost.
            title: Text(
              file.name,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isSelected ? colorScheme.onAccentTint : null,
              ),
            ),
            subtitle: _FileListItemSubtitle(file: file),
            selected: isSelected,
            onTap: () => _handleSelectionTap(state, file),
            // Both marks can be on one row, so they take different slots
            // rather than one trailing widget that has to choose.
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isStaged)
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: AppOverlay.ink.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                    ),
                    child: const Icon(Icons.inbox_rounded, size: 11, color: Colors.white),
                  ),
                if (isStaged && isSelected) const SizedBox(width: 8),
                if (isSelected)
                  Icon(Icons.check_circle, size: 20, color: colorScheme.primary),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Single click toggles one file; Shift+click extends the selection from the
  /// last plain click to this one (see [FileBrowserState.selectRangeTo]).
  void _handleSelectionTap(FileBrowserState state, BrowserFile file) {
    if (HardwareKeyboard.instance.isShiftPressed) {
      state.selectRangeTo(file);
    } else {
      state.toggleSelection(file);
    }
  }

  void _openWithPreview(BuildContext context, BrowserFile file, FileBrowserState state) {
    if (file.category == FileCategory.image || file.category == FileCategory.video) {
      final mediaFiles = state.filteredFiles
          .where((f) => f.category == file.category)
          .map((f) => AppImage(path: f.path, name: f.name))
          .toList();
      final idx = mediaFiles.indexWhere((m) => m.path == file.path);
      // The scope is passed from the list view too: its rows carry no Hero, so
      // the tag simply finds no match there and the route's fade covers it.
      showMediaPreview(context, galleryImages: mediaFiles, initialIndex: idx >= 0 ? idx : 0, heroScope: kBrowserPreviewHeroScope);
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

/// The toolbar's way into the staging column, carrying its count.
///
/// A badge rather than a number in the label: at zero the button is still
/// there — the feature has to be discoverable before anything is in it — and
/// a badge is the one form that can be absent without the button resizing.
class _StagingToolbarButton extends StatelessWidget {
  final int count;
  final bool open;
  final VoidCallback onPressed;

  const _StagingToolbarButton({
    required this.count,
    required this.open,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        AppIconButton(
          icon: Icons.inbox_outlined,
          tooltip: l10n.stagingArea,
          selected: open,
          onPressed: onPressed,
        ),
        if (count > 0)
          Positioned(
            top: -6,
            right: -6,
            child: Container(
              constraints: const BoxConstraints(minWidth: 17),
              height: 17,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colorScheme.primary,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                // A ring in the bar's own colour, so the badge reads as
                // sitting on the button rather than merging with whatever
                // control is beside it.
                border: Border.all(color: colorScheme.surfaceContainerLow, width: 2),
              ),
              child: Text(
                '$count',
                style: Theme.of(context).textTheme.labelSmall?.mono.copyWith(
                      color: colorScheme.onPrimary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
      ],
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
      style: Theme.of(context).textTheme.labelMedium?.metricsOnly,
    );
  }
}
