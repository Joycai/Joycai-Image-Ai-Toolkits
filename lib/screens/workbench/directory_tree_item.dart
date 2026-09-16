import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../models/browser_file.dart';
import '../../services/files/file_permission_service.dart';
import '../../services/files/file_transfer_service.dart';
import '../../services/files/folder_operations_service.dart';
import '../../state/app_state.dart';
import '../../state/file_browser_state.dart';
import '../../state/file_staging_state.dart';
import '../../state/gallery_state.dart';
import '../../widgets/ui/app_snackbar.dart';
import '../../widgets/drag/app_drag_follower.dart';
import '../../widgets/drag/app_drag_session.dart';
import '../../widgets/drag/app_drop_zone.dart';
import '../browser/folder_move_flow.dart';
import '../browser/staging_paste_flow.dart';
import '../browser/widgets/folder_context_menu.dart';
import '../browser/widgets/folder_delete_dialog.dart';
import '../browser/widgets/folder_name_editor.dart';
import '../../widgets/files/folder_drop_feedback.dart';
import 'folder_tree_row.dart';

part 'folder_drop_target.dart';

/// What a folder row hands to a drop target when it is dragged — `B1b 13e`.
///
/// Its own type rather than a path string, so a target can tell a folder from
/// the file browser's `List<BrowserFile>` payload by type alone.
class FolderDragPayload {
  final String path;

  const FolderDragPayload(this.path);
}

/// Which in-row edit a tree row is running.
enum _RowEdit { creating, renaming }

class DirectoryTreeItem extends StatefulWidget {
  final String path;

  /// Whether this item heads a registered tree. Kept for callers; the row's
  /// geometry comes from [depth], and "is this a registration" is asked of
  /// the state, not of this flag.
  final bool isRoot;

  /// Nesting level — 0 for a root. Indents the row's *content* by
  /// [FolderTreeMetrics.indentStep] per level while its ground keeps the
  /// column's full width (`A1` `srcFolders`: 10px root, 26px child).
  final int depth;

  final bool useFileBrowserState;
  final Function(String, String)? onRemove;

  const DirectoryTreeItem({
    super.key,
    required this.path,
    this.isRoot = false,
    this.depth = 0,
    this.useFileBrowserState = false,
    this.onRemove,
  });

  @override
  State<DirectoryTreeItem> createState() => _DirectoryTreeItemState();
}

class _DirectoryTreeItemState extends State<DirectoryTreeItem> {
  bool _isExpanded = false;
  List<Directory>? _subDirectories;
  bool _isLoading = false;

  /// Keyboard focus for the row, so F2 and Delete know which folder is meant.
  /// Taken on click (either button); the tree has no other focus concept.
  final FocusNode _focusNode = FocusNode(debugLabel: 'directory-tree-row');

  _RowEdit? _edit;

  /// This folder is being dragged.
  bool _dragging = false;

  /// Bumped when the browser asks this row to pulse; 0 means never.
  int _pulse = 0;
  String? _pulsedFor;
  ValueListenable<int>? _refreshTick;
  ValueListenable<FolderFlash>? _flashCue;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The notifier that owns the counter — AppState no longer forwards
    // either one — but subscribed to the *tick*, not to the notifier at
    // large. A listening `Provider.of` here read one integer and paid for
    // every notification the state made, so a row of the expanded tree
    // rebuilt on each selection change and each frame of a size drag.
    final tick = widget.useFileBrowserState
        ? Provider.of<FileBrowserState>(context, listen: false).refreshTick
        : Provider.of<GalleryState>(context, listen: false).refreshTick;
    if (!identical(tick, _refreshTick)) {
      _refreshTick?.removeListener(_onRefreshed);
      _refreshTick = tick..addListener(_onRefreshed);
    }

    // The pulse cue, on its own notifier for the same reason as the tick: a
    // listening `Provider.of` here put every row of the tree on all of the
    // browser's traffic — its selection, its scans, its size slider — to read
    // one cue that names at most one row.
    final cue = widget.useFileBrowserState
        ? Provider.of<FileBrowserState>(context, listen: false).flashCue
        : Provider.of<GalleryState>(context, listen: false).flashCue;
    if (!identical(cue, _flashCue)) {
      _flashCue?.removeListener(_onFlash);
      _flashCue = cue..addListener(_onFlash);
      // Read what is already there. A row created by the very action that
      // set the cue — a new folder, a rename — mounts after it fired, so a
      // listener alone would never hear its own pulse. A build follows
      // this, so nothing needs marking dirty.
      _applyFlash(cue.value, notify: false);
    }
  }

  void _onFlash() {
    final cue = _flashCue?.value;
    if (!mounted || cue == null) return;
    _applyFlash(cue, notify: true);
  }

  void _applyFlash(FolderFlash cue, {required bool notify}) {
    final String? flash = cue.path;
    if (flash == null || flash == _pulsedFor) return;

    void mutate(VoidCallback change) => notify ? setState(change) : change();

    if (p.equals(flash, widget.path)) {
      _pulsedFor = flash;
      mutate(() => _pulse++);
      // A renamed row comes back under its new key, closed. `13c`: it was
      // open before, so it is open after — the state follows the directory
      // even though the widget could not.
      if (cue.expanded && !_isExpanded) {
        mutate(() => _isExpanded = true);
        _loadSubDirectories();
      }
    } else if (p.equals(p.dirname(flash), widget.path) && !_isExpanded) {
      // The row to pulse is a child of this one and this one is closed: open
      // it, or the pulse plays to nobody.
      _pulsedFor = flash;
      mutate(() => _isExpanded = true);
      _loadSubDirectories();
    }
  }

  void _onRefreshed() {
    if (!mounted) return;
    if (_isExpanded) {
      // Reload in place, keeping the stale list rendered until fresh data
      // arrives — nulling it first unmounts every child DirectoryTreeItem,
      // which destroys their expansion state (deep branches collapse).
      _loadSubDirectories(force: true);
    } else {
      setState(() => _subDirectories = null);
    }
  }

  @override
  void dispose() {
    _refreshTick?.removeListener(_onRefreshed);
    _flashCue?.removeListener(_onFlash);
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _reAuthorize(BuildContext context, AppState appState) async {
    final String? newPath = await FilePermissionService().reAuthorize(
      widget.path,
      title: 'Authorize Access to: ${widget.path}',
    );

    if (newPath != null) {
      // If it was a root, we might need to replace it in the list
      if (_isRegisteredRoot) {
        if (widget.useFileBrowserState) {
          await appState.fileBrowserState.removeBaseDirectory(widget.path);
          await appState.fileBrowserState.addBaseDirectory(newPath);
        } else {
          await appState.removeBaseDirectory(widget.path);
          await appState.addBaseDirectory(newPath);
        }
      } else {
        // Just refresh the whole state
        if (widget.useFileBrowserState) {
          appState.fileBrowserState.refresh();
        } else {
          appState.galleryState.refreshImages();
        }
      }
    }
  }

  Future<void> _loadSubDirectories({bool force = false}) async {
    if (_subDirectories != null && !force) return;

    setState(() => _isLoading = true);
    try {
      final dir = Directory(widget.path);
      final List<Directory> subDirs = [];
      await for (final entity in dir.list(recursive: false)) {
        if (entity is Directory) {
          // Filter out hidden directories
          if (!p.basename(entity.path).startsWith('.')) {
            subDirs.add(entity);
          }
        }
      }

      // Sort alphabetically
      subDirs.sort((a, b) =>
        p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase())
      );

      if (mounted) {
        setState(() {
          _subDirectories = subDirs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _subDirectories = []; // Treat error/access denied as empty
          _isLoading = false;
        });
      }
    }
  }

  void _handleExpansionChanged(bool expanded) {
    setState(() => _isExpanded = expanded);
    if (expanded) {
      _loadSubDirectories();
    }
  }

  // ------------------------------------------------------------ 13a actions

  Set<String> get _roots =>
      Provider.of<FileBrowserState>(context, listen: false).sourceDirectories.toSet();

  bool get _isRegisteredRoot {
    final roots = widget.useFileBrowserState
        ? Provider.of<FileBrowserState>(context, listen: false).sourceDirectories
        : Provider.of<GalleryState>(context, listen: false).sourceDirectories;
    return FolderOperationsService.isRegisteredRoot(widget.path, roots);
  }

  String? _nameError(AppLocalizations l10n, String parent, String name, {String? currentPath}) {
    final error = FolderOperationsService.validateName(
      parent: parent,
      name: name,
      currentPath: currentPath,
      registered: _roots,
    );
    return switch (error) {
      null => null,
      FolderNameError.empty => l10n.folderNameEmpty,
      FolderNameError.illegalChars => l10n.folderNameIllegalChars(FolderOperationsService.illegalChars()),
      FolderNameError.reservedName => l10n.folderNameReserved,
      FolderNameError.exists => l10n.folderNameExists,
      FolderNameError.registered => l10n.folderPathRegistered,
    };
  }

  void _startCreate() {
    setState(() {
      _edit = _RowEdit.creating;
      _isExpanded = true;
    });
    _loadSubDirectories();
  }

  void _startRename() => setState(() => _edit = _RowEdit.renaming);

  void _cancelEdit() {
    if (mounted && _edit != null) setState(() => _edit = null);
  }

  Future<String?> _commitCreate(String name) async {
    final l10n = AppLocalizations.of(context)!;
    final browser = Provider.of<FileBrowserState>(context, listen: false);
    final String created;
    try {
      created = await FolderOperationsService.create(widget.path, name);
    } on FileSystemException catch (e) {
      return l10n.folderOpFailed(e.message);
    }
    if (!mounted) return null;
    setState(() => _edit = null);
    browser.flash(created);
    await _loadSubDirectories(force: true);
    if (mounted) AppSnackBar.success(context, l10n.folderCreated(p.basename(created)));
    return null;
  }

  Future<String?> _commitRename(String name) async {
    final l10n = AppLocalizations.of(context)!;
    final appState = Provider.of<AppState>(context, listen: false);
    final staging = Provider.of<FileStagingState>(context, listen: false);
    final String renamed;
    try {
      renamed = await FolderOperationsService.rename(widget.path, name);
    } on FileSystemException catch (e) {
      return l10n.folderOpFailed(e.message);
    }
    if (!mounted) return null;
    setState(() => _edit = null);
    if (p.equals(renamed, widget.path)) return null;

    // Everything that named the old path follows it — this row's own
    // registration too, when it is a root. The parent reloads on the refresh
    // and the renamed row comes back under its new key, pulsing, and open if
    // this one was.
    appState.fileBrowserState.flash(renamed, expand: _isExpanded);
    // Said now, while this row is still here to say it: by the time the lists
    // are in step the tree has been rebuilt and this row is gone.
    AppSnackBar.success(context, l10n.folderRenamed(p.basename(renamed)));
    await applyFolderPathChange(appState, staging, widget.path, renamed);
    return null;
  }

  Future<void> _moveTo() async {
    final l10n = AppLocalizations.of(context)!;
    final picked = await FilePicker.getDirectoryPath(dialogTitle: l10n.moveFolderTo);
    if (picked == null || !mounted) return;
    await runFolderTransfer(
      context,
      source: widget.path,
      destination: picked,
      mode: FolderTransferMode.move,
    );
  }

  void _delete() {
    if (_isRegisteredRoot) {
      widget.onRemove?.call(widget.path, p.basename(widget.path));
    } else {
      runFolderDelete(context, widget.path);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!widget.useFileBrowserState || _edit != null || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.f2) {
      _startRename();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) {
      _delete();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _showMenu(Offset position) {
    _focusNode.requestFocus();
    // The menu pops itself before running an item's callback, so the tree is
    // free to rebuild by the time these fire.
    showFolderContextMenu(
      context: context,
      path: widget.path,
      position: position,
      isRoot: _isRegisteredRoot,
      onNewSubfolder: () => WidgetsBinding.instance.addPostFrameCallback((_) => _startCreate()),
      onRename: () => WidgetsBinding.instance.addPostFrameCallback((_) => _startRename()),
      onMoveTo: () => WidgetsBinding.instance.addPostFrameCallback((_) => _moveTo()),
      onDelete: () => WidgetsBinding.instance.addPostFrameCallback((_) => _delete()),
      onRemoveFromList: widget.onRemove == null
          ? null
          : () => WidgetsBinding.instance.addPostFrameCallback((_) => _delete()),
    );
  }

  // --------------------------------------------------------------- 13e drag

  /// The copy key is followed by [AppCopyModifier], which the follower and
  /// the row under the pointer listen to; this row only reports that a drag
  /// is in flight, so the tree can show it will take it.
  void _onDragStarted() {
    setState(() => _dragging = true);
    AppDragSession.begin(FolderDragPayload(widget.path));
  }

  /// Wired to every end callback: `onDragEnd` is skipped once this row has
  /// been unmounted — a drop that moved the folder away — and the session
  /// must end regardless.
  void _onDragEnded() {
    if (mounted && _dragging) setState(() => _dragging = false);
    AppDragSession.end();
  }

  @override
  Widget build(BuildContext context) {
    // Listen to selection changes efficiently based on the target state.
    // Selected off the owning notifier, not off AppState: AppState stopped
    // re-broadcasting its sub-states, so a selector reading through it would
    // never fire.
    final isSelected = widget.useFileBrowserState
        ? context.select<FileBrowserState, bool>(
            (state) => state.activeDirectories.contains(widget.path))
        : context.select<GalleryState, bool>(
            (state) => state.activeSourceDirectories.contains(widget.path));

    // Both trees work the same way: the checkbox adds a folder to or drops it
    // from the merged view, and tapping the name browses just that folder. The
    // row highlight tracks "you are here" (viewing), distinct from the
    // checkbox — in the browser, that is being the only active folder.
    final isViewing = widget.useFileBrowserState
        ? context.select<FileBrowserState, bool>((state) =>
            state.activeDirectories.length == 1 &&
            state.activeDirectories.first == widget.path)
        : context.select<GalleryState, bool>((state) =>
            state.viewMode == GalleryViewMode.folder &&
            !state.folderViewIsResult &&
            state.viewSourcePath == widget.path);
    final highlight = isViewing;

    final appState = Provider.of<AppState>(context, listen: false);
    final isUnreachable = widget.useFileBrowserState
        ? appState.unreachableBrowserDirectories.contains(widget.path)
        : appState.galleryState.unreachableDirectories.contains(widget.path);
    final folderName = p.basename(widget.path);
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final metrics = FolderTreeMetrics.of(context);
    final renaming = _edit == _RowEdit.renaming;

    // The checkbox is not in `A1 1a`, which draws the tree bare. It stays: in
    // the gallery it is the only control for what All Sources aggregates, in
    // the browser it is which folders are listed. While the name is being
    // typed its slot is kept blank, so the field lines up with the rows
    // around it.
    final Widget marker;
    if (renaming) {
      marker = SizedBox(width: metrics.markerBox);
    } else if (isUnreachable) {
      marker = Tooltip(
        message: 'Access Denied (Click to re-authorize)',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _reAuthorize(context, appState),
          child: SizedBox.square(
            dimension: metrics.markerBox,
            child: Icon(Icons.lock_person, size: AppSize.iconMd, color: colorScheme.error),
          ),
        ),
      );
    } else {
      marker = SizedBox.square(
        dimension: metrics.markerBox,
        child: Checkbox(
          value: isSelected,
          onChanged: (_) {
            if (widget.useFileBrowserState) {
              appState.fileBrowserState.toggleDirectory(widget.path);
            } else {
              // Checkbox = include/exclude from the aggregate; the live
              // aggregate rescans, no forced view switch.
              appState.galleryState.toggleDirectory(widget.path);
            }
          },
          visualDensity: metrics.markerDensity,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }

    final canExpand = !isUnreachable &&
        !renaming &&
        (_subDirectories == null || _subDirectories!.isNotEmpty);
    final TreeDisclosure disclosure = !canExpand
        ? TreeDisclosure.none
        : _isLoading
            ? TreeDisclosure.loading
            : (_isExpanded ? TreeDisclosure.expanded : TreeDisclosure.collapsed);

    void onTap() {
      _focusNode.requestFocus();
      if (isUnreachable) {
        _reAuthorize(context, appState);
      } else if (widget.useFileBrowserState) {
        // Tapping the name browses just this folder, as in the gallery.
        appState.fileBrowserState.setExclusiveDirectory(widget.path);
      } else {
        appState.galleryState.setViewFolder(widget.path);
      }
    }

    // [drop]: something is dragged over this row (`00d · 1d`). A folder about
    // to take it shows open — the glyph it will have once the drop goes in —
    // and one refusing it shows the block glyph.
    Widget row(_RowDrop? drop) => FolderTreeRow(
          depth: widget.depth,
          disclosure: disclosure,
          onToggle: () => _handleExpansionChanged(!_isExpanded),
          marker: marker,
          icon: switch (drop?.tone) {
            null => Icons.folder_outlined,
            FolderDropTone.reject => Icons.block,
            FolderDropTone.move || FolderDropTone.copy => Icons.folder_open_outlined,
          },
          iconColor: isUnreachable ? colorScheme.error.withValues(alpha: AppAlpha.disabled) : null,
          label: folderName,
          labelColor: isUnreachable ? colorScheme.error : null,
          selected: highlight,
          dropTone: drop?.tone,
          dropNote: drop?.note,
          // The workbench has no context menu, so this is its only way to
          // take a folder off the list.
          hoverAction: _isRegisteredRoot && widget.onRemove != null && _edit == null
              ? FolderTreeRowAction(
                  icon: Icons.close,
                  tooltip: l10n.remove,
                  onPressed: () => widget.onRemove!(widget.path, folderName),
                )
              : null,
          editor: renaming
              ? FolderNameEditor(
                  initialName: folderName,
                  validate: (name) => _nameError(l10n, p.dirname(widget.path), name, currentPath: widget.path),
                  onSubmit: _commitRename,
                  onCancel: _cancelEdit,
                )
              : null,
          onTap: renaming ? null : onTap,
          // The file browser's paste target is named on the folder's own
          // context menu (`12d`); the workbench's copy of this tree has no
          // staging area behind it.
          onSecondaryTapDown: widget.useFileBrowserState && _edit == null
              ? (details) => _showMenu(details.globalPosition)
              : null,
        );

    final rowWidget = Padding(
      padding: EdgeInsets.symmetric(horizontal: metrics.margin),
      // `12d`'s second way to name a destination: drop the selection on a
      // folder. Default is move; the copy key (Ctrl, ⌥ on macOS) copies — the
      // convention every file manager already trained the user on. Browser
      // only; the workbench shares this tree and has nothing to paste. `13e`
      // adds folders to what can be dropped here, under the same rule.
      child: _MaybeDropTarget(
        enabled: widget.useFileBrowserState && _edit == null,
        path: widget.path,
        onHoverExpand: () {
          if (!_isExpanded) _handleExpansionChanged(true);
        },
        builder: (context, drop) {
          Widget child = Focus(
            focusNode: _focusNode,
            onKeyEvent: _onKey,
            child: row(drop),
          );
          if (_pulse > 0) child = _Pulsed(key: ValueKey(_pulse), child: child);
          return child;
        },
      ),
    );

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        rowWidget,
        if (_isExpanded && (_subDirectories != null || _edit == _RowEdit.creating)) ...[
          if (_edit == _RowEdit.creating)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: metrics.margin),
              child: FolderTreeRow(
                depth: widget.depth + 1,
                disclosure: TreeDisclosure.none,
                marker: SizedBox(width: metrics.markerBox),
                icon: Icons.folder_outlined,
                label: l10n.newFolderDefaultName,
                editor: FolderNameEditor(
                  initialName: l10n.newFolderDefaultName,
                  validate: (name) => _nameError(l10n, widget.path, name),
                  onSubmit: _commitCreate,
                  onCancel: _cancelEdit,
                ),
              ),
            ),
          ...(_subDirectories ?? const <Directory>[]).map((dir) {
            return DirectoryTreeItem(
              // Keyed by path so expansion state follows the directory
              // when siblings are added/removed across refreshes.
              key: ValueKey(dir.path),
              path: dir.path,
              isRoot: false,
              depth: widget.depth + 1,
              useFileBrowserState: widget.useFileBrowserState,
              // Registered roots can also appear below another root.
              // Carry this callback so those rows remain protected.
              onRemove: widget.onRemove,
            );
          }),
        ],
      ],
    );

    // Roots do not move — they are registrations, and "remove from list" is
    // how one changes. So a root row is not draggable at all: no chip, no
    // dimming, nothing lights up. The tree simply does not answer.
    if (!widget.useFileBrowserState || _isRegisteredRoot || isUnreachable) return column;

    return Draggable<FolderDragPayload>(
      data: FolderDragPayload(widget.path),
      maxSimultaneousDrags: _edit == null ? 1 : 0,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _FolderDragChip(name: folderName),
      onDragStarted: _onDragStarted,
      onDragEnd: (_) => _onDragEnded(),
      onDragCompleted: _onDragEnded,
      onDraggableCanceled: (_, _) => _onDragEnded(),
      // `00d`: a drag out of its place leaves the source at half strength.
      // The row and its subtree fade together — what is picked up is the whole
      // branch, and the tree must not reflow under the pointer. An Opacity in
      // place rather than `childWhenDragging`, which would remount the subtree
      // and close every open subfolder the moment the drag began.
      child: Opacity(opacity: _dragging ? 0.5 : 1, child: column),
    );
  }
}

// ------------------------------------------------------------ shared rows

/// One fade of the selection tint over a row — how a folder that was just
/// created, renamed or dropped says "here I am" and then stops.
class _Pulsed extends StatelessWidget {
  final Widget child;

  const _Pulsed({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: 0),
      duration: const Duration(milliseconds: 1200),
      curve: Curves.easeOut,
      builder: (context, t, child) => Stack(
        children: [
          child!,
          if (t > 0)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: AppAlpha.tint * t),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ),
              ),
            ),
        ],
      ),
      child: child,
    );
  }
}

/// What follows the pointer while a folder is dragged (`00d · 1e`): the
/// opaque follower chip with the folder glyph and its name, saying move or
/// copy as the copy key goes down and up — or, over a row that refuses the
/// folder, that row's reason.
class _FolderDragChip extends StatelessWidget {
  final String name;

  const _FolderDragChip({required this.name});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return FolderDropFollower(
      builder: (context, copying) => AppDragFollower(
        icon: Icons.folder_outlined,
        label: copying ? l10n.dragCopyFolderHint(name) : l10n.dragMoveFolderHint(name),
        tone: copying ? AppDragTone.copy : AppDragTone.move,
      ),
    );
  }
}
