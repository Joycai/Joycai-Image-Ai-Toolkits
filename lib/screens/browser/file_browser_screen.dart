import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_semantic_colors.dart';
import '../../core/design_tokens.dart';
import '../../core/file_utils.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../models/app_image.dart';
import '../../models/browser_file.dart';
import '../../services/database_service.dart';
import '../../state/app_state.dart';
import '../../state/file_browser_state.dart';
import '../../state/file_staging_state.dart';
import '../../state/workbench_ui_state.dart';
import '../../widgets/app_run_console.dart';
import '../../widgets/app_window_frame.dart';
import '../../widgets/dialogs/file_rename_dialog.dart';
import '../../widgets/panel_resizer.dart';
import '../../widgets/shell/app_destinations.dart';
import '../../widgets/unified_sidebar.dart';
import '../workbench/widgets/preview/media_preview_dialog.dart';
import 'ai_rename_dialog.dart';
import 'staging_paste_flow.dart';
import 'widgets/browser_file_area_states.dart';
import 'widgets/browser_file_list_row.dart';
import 'widgets/browser_filter_bar.dart';
import 'widgets/browser_header.dart';
import 'widgets/browser_selection_bar.dart';
import 'widgets/browser_staging_panel.dart';
import 'widgets/file_card.dart';
import 'widgets/file_context_menu.dart';

/// The file browser — `B1a` (layout and selection) with `B1b`'s staging
/// column on the right.
///
/// Same skeleton as the workbench: the directory column on the left (its
/// width dragged and persisted), the file area in the middle, the optional
/// staging column on the right, the run console along the bottom. Below
/// 1000px the directory column becomes a 260px drawer behind the header's
/// hamburger and the staging column a right-hand slide-out.
///
/// The header and filter bar are opaque; the grid under them is transparent
/// over the window backdrop; list rows are opaque. The only glass here is the
/// floating selection bar, the context menu and the drag chip.
class FileBrowserScreen extends StatefulWidget {
  const FileBrowserScreen({super.key});

  @override
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen> {
  static const double _minSidebarWidth = 180;
  static const double _maxSidebarWidth = 420;

  /// `1c`: the drawer is the column at a fixed width, not Material's 304.
  static const double _drawerWidth = 260;

  /// The grid's gutter, both ways (`1a`).

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  /// `1a`: 240 at rest; a width the user dragged to wins once loaded.
  double _sidebarWidth = 240;

  /// Whether the staging column is showing. It stays out of the way until it
  /// has something to hold — it costs 320px of grid — so it opens the first
  /// time anything is staged and is toggled from the header afterwards.
  bool _stagingOpen = false;
  bool _stagingAutoOpened = false;

  /// Whether the narrow-window slide-out is open, so the header button can
  /// show it.
  bool _stagingDrawerOpen = false;

  /// Whether a header search that collapsed to its icon has been opened.
  bool _searchOpen = false;

  /// Rescans this screen started and has not seen finish — what the scanning
  /// state over an empty file area keys on.
  int _pendingRefreshes = 0;

  /// Drag accumulator, allowed [_kDragSlack] past the limits so the handle
  /// re-engages where the pointer actually is after a drag past the end,
  /// instead of the instant the pointer reverses. Null when no drag is live.
  static const double _kDragSlack = 24;
  double? _dragSidebarWidth;

  @override
  void initState() {
    super.initState();
    _loadSidebarWidth();
    _searchFocusNode.addListener(_onSearchFocusChanged);
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
    _searchFocusNode.removeListener(_onSearchFocusChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// A collapsed search closes again once it has lost focus with nothing in
  /// it.
  void _onSearchFocusChanged() {
    if (!_searchFocusNode.hasFocus && _searchOpen && _searchController.text.isEmpty) {
      setState(() => _searchOpen = false);
    }
  }

  /// Focuses the header search, opening it first if it had collapsed — the
  /// field only exists after the next frame in that case.
  void _focusSearch() {
    if (!_searchOpen) setState(() => _searchOpen = true);
    _searchFocusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_searchFocusNode.hasFocus) _searchFocusNode.requestFocus();
    });
  }

  Future<void> _refresh(FileBrowserState state) async {
    setState(() => _pendingRefreshes++);
    try {
      await state.refresh();
    } finally {
      if (mounted) setState(() => _pendingRefreshes--);
    }
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
      _focusSearch();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f5 || (isCtrl && key == LogicalKeyboardKey.keyR)) {
      _refresh(state);
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

  /// `1d`, last frame: the browser needs a desktop file system, so a phone or
  /// tablet OS gets why, where to go instead, and a way to the workbench.
  Widget _buildMobileRestrictedView(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final semantic = context.semantic;
    final bodyStyle = textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      height: AppType.proseHeight,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpace.s28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: AppSize.touch,
                      height: AppSize.touch,
                      decoration: BoxDecoration(
                        color: semantic.warningContainer,
                        borderRadius: BorderRadius.circular(AppRadius.control),
                      ),
                      child: Icon(Icons.phonelink_off, size: 24, color: semantic.warning),
                    ),
                  ),
                  const SizedBox(height: AppSpace.s16),
                  Text(
                    l10n.featureLimitedOnMobile,
                    textAlign: TextAlign.center,
                    style: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
                  ),
                  const SizedBox(height: AppSpace.s10),
                  Text(l10n.fileBrowserDesktopOnlyDesc, textAlign: TextAlign.center, style: bodyStyle),
                  const SizedBox(height: AppSpace.s10),
                  Text(
                    Platform.isIOS ? l10n.fileBrowseriOSHint : l10n.fileBrowserAndroidHint,
                    textAlign: TextAlign.center,
                    style: bodyStyle,
                  ),
                  const SizedBox(height: AppSpace.s22),
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSize.touch)),
                    onPressed: () =>
                        context.read<AppState>().navigateToScreen(AppDestination.workbench.index),
                    child: Text(l10n.goToWorkbench),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(AppLocalizations l10n) {
    // Unlistened: the layout hands this down for its actions, and every piece
    // that *draws* something out of it — the header's counts, the filter
    // bar's chips, the selection bar, each tile — now subscribes to the slice
    // it draws. The layout itself has no reason to rebuild when a file is
    // picked, and rebuilding it took the whole browser with it.
    final browser = Provider.of<FileBrowserState>(context, listen: false);
    final staging = context.select<FileStagingState, _StagingInputs>(_stagingInputs);
    final scheme = Theme.of(context).colorScheme;
    final isNarrow = Responsive.isNarrow(context);

    // The column earns its width the moment there is something in it, and
    // only the first time — reopening it after the user closed it would be
    // the app arguing with them.
    if (staging.count > 0 && !_stagingAutoOpened) {
      _stagingAutoOpened = true;
      _stagingOpen = true;
    } else if (staging.count == 0 && _stagingAutoOpened) {
      _stagingAutoOpened = false;
    }

    // Below 1000 the grid cannot spare the column, so staging slides out from
    // the right edge instead (`1c`).
    final showStagingColumn = _stagingOpen && !isNarrow;

    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        key: _scaffoldKey,
        // Transparent over the window's backdrop, exactly as `A1` does it: the
        // columns and the header are opaque and paint over the mesh, and the
        // file grid between them does not. Falls back to the canvas colour
        // where there is no custom window frame to show through to.
        backgroundColor: usesCustomWindowChrome ? Colors.transparent : scheme.surfaceContainer,
        drawer: isNarrow
            ? const Drawer(
                width: _drawerWidth,
                child: UnifiedSidebar(useFileBrowserState: true),
              )
            : null,
        endDrawer: isNarrow
            ? Drawer(
                width: kStagingPanelWidth,
                child: BrowserStagingPanel(
                  destination: staging.destination,
                  onPaste: (mode) {
                    _scaffoldKey.currentState?.closeEndDrawer();
                    runStagingPaste(context, mode: mode);
                  },
                ),
              )
            : null,
        // Opened from the header only: an edge-swipe zone on a desktop window
        // would sit over the grid's scrollbar.
        endDrawerEnableOpenDragGesture: false,
        onEndDrawerChanged: (open) {
          if (open != _stagingDrawerOpen) setState(() => _stagingDrawerOpen = open);
        },
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
                  DatabaseService().saveSetting('browser_sidebar_width', _sidebarWidth.round().toString());
                },
              ),
            ],
            Expanded(
              child: PanelCard(
                shape: PanelShape.column,
                // The centre column paints nothing; its header and filter bar
                // carry their own opaque grounds and the grid below them is
                // bare.
                ground: Colors.transparent,
                child: Column(
                  children: [
                    BrowserHeader(
                      state: browser,
                      stagingCount: staging.count,
                      stagingOpen: isNarrow ? _stagingDrawerOpen : _stagingOpen,
                      onStagingPressed: () {
                        if (isNarrow) {
                          _scaffoldKey.currentState?.openEndDrawer();
                        } else {
                          setState(() => _stagingOpen = !_stagingOpen);
                        }
                      },
                      searchController: _searchController,
                      searchFocusNode: _searchFocusNode,
                      searchOpen: _searchOpen,
                      onSearchOpen: _focusSearch,
                      onSearchChanged: browser.setSearchQuery,
                      onRefresh: () => _refresh(browser),
                      onOpenDrawer: isNarrow ? () => _scaffoldKey.currentState?.openDrawer() : null,
                    ),
                    BrowserFilterBar(state: browser),
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: _FileArea(
                              pendingRefreshes: _pendingRefreshes,
                              onTap: (file) => _handleSelectionTap(browser, file),
                              onDoubleTap: (file) =>
                                  _openWithPreview(context, file, browser),
                              onSecondaryTap: (file, pos) =>
                                  _showContextMenu(context, file, pos),
                            ),
                          ),
                          Positioned(
                            left: AppSpace.s16,
                            right: AppSpace.s16,
                            bottom: BrowserSelectionBar.bottomInset,
                            child: Center(
                              child: BrowserSelectionBar(
                                onAiRename: () => _showAiRenameDialog(context),
                                onAddToStaging: () => _addSelectionToStaging(
                                  browser,
                                  Provider.of<FileStagingState>(context, listen: false),
                                ),
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

  void _addSelectionToStaging(FileBrowserState state, FileStagingState staging) {
    staging.addAll(state.selectedFiles);
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
      showMediaPreview(
        context,
        galleryImages: mediaFiles,
        initialIndex: idx >= 0 ? idx : 0,
        heroScope: kBrowserPreviewHeroScope,
      );
    } else {
      _handleOpenFile(file);
    }
  }

  Future<void> _handleOpenFile(BrowserFile file) async {
    await FileUtils.openPath(file.path);
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

/// What the file area draws out of [FileBrowserState] — and pointedly not the
/// selection.
///
/// The selection is read per tile, by the [Selector2] inside the builders
/// below. Putting it here would rebuild every visible card for a change that
/// concerns one of them, which is what the area did when it was a method on
/// the screen and the screen watched the whole notifier: picking one file
/// rebuilt the header, the filter bar, the folder tree and all ~130 tiles.
///
/// [files] compares by identity, which [FileBrowserState] guarantees — the
/// filter pass assigns a fresh list before notifying.
/// What the layout itself draws out of the staging area: whether the column
/// has earned its width, where a paste would land, and the count on the
/// header's button. Not `items` — the column reads those.
typedef _StagingInputs = ({int count, String? destination});

_StagingInputs _stagingInputs(FileStagingState s) =>
    (count: s.count, destination: s.destination);

typedef _AreaInputs = ({
  List<BrowserFile> files,
  BrowserViewMode viewMode,
  double thumbnailSize,
  bool isScanning,
  bool hasFolders,
});

_AreaInputs _areaInputs(FileBrowserState s) => (
      files: s.filteredFiles,
      viewMode: s.viewMode,
      thumbnailSize: s.thumbnailSize,
      isScanning: s.isScanning,
      hasFolders: s.sourceDirectories.isNotEmpty,
    );

/// What one tile reads. [payloadCount] is what its drag chip would say — the
/// whole selection when the tile is in it, one otherwise — so an *unselected*
/// tile's value never moves, whatever the selection does around it.
typedef _TileFlags = ({bool selected, bool staged, int payloadCount});

/// The grid or the list of files (`B1a · 1a`).
class _FileArea extends StatelessWidget {
  const _FileArea({
    required this.pendingRefreshes,
    required this.onTap,
    required this.onDoubleTap,
    required this.onSecondaryTap,
  });

  final int pendingRefreshes;
  final void Function(BrowserFile) onTap;
  final void Function(BrowserFile) onDoubleTap;
  final void Function(BrowserFile, Offset) onSecondaryTap;

  /// The grid's gutter, both ways (`1a`).
  static const double _gap = 12;

  @override
  Widget build(BuildContext context) {
    final _AreaInputs area = context.select<FileBrowserState, _AreaInputs>(_areaInputs);

    if (area.files.isEmpty) {
      if (pendingRefreshes > 0 || area.isScanning) {
        return BrowserScanningState(
          progress: Provider.of<FileBrowserState>(context, listen: false).scanProgress,
        );
      }
      return BrowserFilesEmptyState(noFolders: !area.hasFolders);
    }
    return area.viewMode == BrowserViewMode.grid
        ? _buildGrid(context, area)
        : _buildList(context, area);
  }

  /// Wraps one tile in the subscription that is allowed to rebuild it.
  ///
  /// Two notifiers because the two flags are orthogonal and live apart: what
  /// is selected is the browser's, what is staged is the staging area's, and
  /// a card draws both.
  Widget _tile(
    BrowserFile file,
    Widget Function(BuildContext, _TileFlags, List<BrowserFile>) build,
  ) {
    return Selector2<FileBrowserState, FileStagingState, _TileFlags>(
      selector: (_, browser, staging) {
        final bool selected = browser.selectedFiles.contains(file);
        return (
          selected: selected,
          staged: staging.contains(file.path),
          payloadCount: selected ? browser.selectedFiles.length : 1,
        );
      },
      builder: (context, flags, _) {
        // Resolved here rather than passed down: every selected tile carries
        // the same list instance (see [FileBrowserState.selectionPayload]),
        // so this allocates nothing.
        final List<BrowserFile> payload = flags.selected
            ? Provider.of<FileBrowserState>(context, listen: false).selectionPayload
            : <BrowserFile>[file];
        return build(context, flags, payload);
      },
    );
  }

  Widget _buildGrid(BuildContext context, _AreaInputs area) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= 0) return const SizedBox.shrink();

        // The width each card actually gets, computed the way the delegate
        // below will, so its height can follow it.
        final double usable = math.max(0, constraints.maxWidth - AppSpace.s16 * 2);
        final int columns =
            math.max(1, (usable / (area.thumbnailSize + _gap)).ceil());
        final double cardWidth = math.max(1, (usable - _gap * (columns - 1)) / columns);

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.s16,
            _gap,
            AppSpace.s16,
            _gap + BrowserSelectionBar.clearance,
          ),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: area.thumbnailSize,
            mainAxisSpacing: _gap,
            crossAxisSpacing: _gap,
            mainAxisExtent: FileCard.mainAxisExtentFor(context, cardWidth),
          ),
          itemCount: area.files.length,
          itemBuilder: (context, index) {
            final BrowserFile file = area.files[index];
            return _tile(file, (context, flags, payload) => FileCard(
                  file: file,
                  isSelected: flags.selected,
                  isStaged: flags.staged,
                  // Dragging a card inside the selection drags the whole
                  // selection; dragging one outside it drags only that file.
                  // Same rule the context menu uses, so the count in the drag
                  // chip and the count in the menu never disagree.
                  dragPayload: payload,
                  thumbnailSize: area.thumbnailSize,
                  heroScope: kBrowserPreviewHeroScope,
                  onTap: () => onTap(file),
                  onDoubleTap: () => onDoubleTap(file),
                  onSecondaryTap: (pos) => onSecondaryTap(file, pos),
                ));
          },
        );
      },
    );
  }

  Widget _buildList(BuildContext context, _AreaInputs area) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: BrowserSelectionBar.clearance),
      itemExtent: BrowserFileListRow.height,
      itemCount: area.files.length,
      itemBuilder: (context, index) {
        final BrowserFile file = area.files[index];
        return _tile(file, (context, flags, payload) => BrowserFileListRow(
              key: ValueKey(file.path),
              file: file,
              isSelected: flags.selected,
              isStaged: flags.staged,
              dragPayload: payload,
              onTap: () => onTap(file),
              onDoubleTap: () => onDoubleTap(file),
              onSecondaryTap: (pos) => onSecondaryTap(file, pos),
            ));
      },
    );
  }
}
