import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/app_semantic_colors.dart';
import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../models/browser_file.dart';
import '../../services/file_permission_service.dart';
import '../../services/file_transfer_service.dart';
import '../../services/folder_operations_service.dart';
import '../../state/app_state.dart';
import '../../state/file_browser_state.dart';
import '../../state/file_staging_state.dart';
import '../../state/gallery_state.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/drag/app_drag_follower.dart';
import '../../widgets/drag/app_drag_session.dart';
import '../../widgets/drag/app_drop_zone.dart';
import '../../widgets/glass/glass_controls.dart' show measureGlassText;
import '../browser/folder_move_flow.dart';
import '../browser/staging_paste_flow.dart';
import '../browser/widgets/folder_context_menu.dart';
import '../browser/widgets/folder_delete_dialog.dart';
import '../browser/widgets/folder_name_editor.dart';

/// What a folder row hands to a drop target when it is dragged — `B1b 13e`.
///
/// Its own type rather than a path string, so a target can tell a folder from
/// the file browser's `List<BrowserFile>` payload by type alone.
class FolderDragPayload {
  final String path;

  const FolderDragPayload(this.path);
}

/// Why a folder row refuses what is dragged over it (`00d · 1d` 拒绝).
enum FolderDropRejection {
  /// A folder over itself, or over one of its own subfolders.
  intoItself,

  /// Everything dragged already sits in this folder — a release would do
  /// nothing.
  sameFolder,

  /// A registered root, which stays where it is.
  root,

  /// The folder grants no one write permission.
  readOnly,

  /// The folder already holds an entry with the dragged folder's name.
  nameTaken,
}

extension FolderDropRejectionLabel on FolderDropRejection {
  /// The reason, as the row's chip and the follower say it.
  String label(AppLocalizations l10n) => switch (this) {
        FolderDropRejection.intoItself => l10n.dropRejectIntoItself,
        FolderDropRejection.sameFolder => l10n.dropRejectSameFolder,
        FolderDropRejection.root => l10n.dropRejectRoot,
        FolderDropRejection.readOnly => l10n.dropRejectReadOnly,
        FolderDropRejection.nameTaken => l10n.dropRejectNameTaken,
      };
}

/// The refusal of the folder row under the pointer, told to the drag follower
/// (`00d · 1e` 拒绝态).
///
/// A [DragTarget] learns the payload but has no way to reach the feedback
/// widget, so the row under the pointer posts its verdict here and the
/// follower listens. Only that row writes it, and only it clears it.
class FolderDropFeedback {
  FolderDropFeedback._();

  static final ValueNotifier<FolderDropRejection?> _rejection = ValueNotifier(null);
  static Object? _owner;

  /// The reason the row under the pointer gives, or null when there is none —
  /// no row, or one that takes the drag.
  static ValueListenable<FolderDropRejection?> get rejection => _rejection;

  static void _post(Object owner, FolderDropRejection? why) {
    _owner = owner;
    _rejection.value = why;
  }

  static void _withdraw(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _rejection.value = null;
  }
}

/// A drag follower for payloads the file browser's folder rows take: [builder]
/// draws the move or copy chip, following the copy key live; over a row that
/// refuses the payload the follower becomes that refusal instead.
class FolderDropFollower extends StatelessWidget {
  const FolderDropFollower({super.key, required this.builder});

  final Widget Function(BuildContext context, bool copying) builder;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ValueListenableBuilder<FolderDropRejection?>(
      valueListenable: FolderDropFeedback.rejection,
      builder: (context, why, _) {
        if (why != null) {
          return AppDragFollower(icon: Icons.block, label: why.label(l10n), tone: AppDragTone.reject);
        }
        return ValueListenableBuilder<bool>(
          valueListenable: AppCopyModifier.instance,
          builder: (context, copying, _) => builder(context, copying),
        );
      },
    );
  }
}

/// What a folder row shows while something is dragged over it (`00d · 1d`).
enum FolderDropTone {
  /// A release moves it here: `--tint` and the accent ring.
  move,

  /// A release copies it here: the success container and ring.
  copy,

  /// This row will not take it: the error container and ring.
  reject,
}

/// A row's drop state and the wording at its end.
typedef _RowDrop = ({FolderDropTone tone, String note});

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

    if (widget.useFileBrowserState) {
      final browser = Provider.of<FileBrowserState>(context);
      final flash = browser.flashPath;
      if (flash != null && flash != _pulsedFor) {
        if (p.equals(flash, widget.path)) {
          _pulsedFor = flash;
          _pulse++;
          // A renamed row comes back under its new key, closed. `13c`: it
          // was open before, so it is open after — the state follows the
          // directory even though the widget could not.
          if (browser.flashExpanded && !_isExpanded) {
            _isExpanded = true;
            _loadSubDirectories();
          }
        } else if (p.equals(p.dirname(flash), widget.path) && !_isExpanded) {
          // The row to pulse is a child of this one and this one is closed:
          // open it, or the pulse plays to nobody.
          _pulsedFor = flash;
          _isExpanded = true;
          _loadSubDirectories();
        }
      }
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
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _reAuthorize(BuildContext context, AppState appState) async {
    final String? newPath = await FilePermissionService().reAuthorize(
      widget.path,
      title: "Authorize Access to: ${widget.path}",
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

    // In the gallery, the checkbox controls aggregate inclusion while tapping
    // the name browses just that folder — so the row highlight tracks "you are
    // here" (viewing), distinct from the checkbox/inclusion state.
    final isViewing = !widget.useFileBrowserState &&
        context.select<GalleryState, bool>((state) =>
            state.viewMode == GalleryViewMode.folder &&
            !state.folderViewIsResult &&
            state.viewSourcePath == widget.path);
    final highlight = widget.useFileBrowserState ? isSelected : isViewing;

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
        message: "Access Denied (Click to re-authorize)",
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
        // File Browser keeps tap-to-toggle.
        appState.fileBrowserState.toggleDirectory(widget.path);
      } else {
        // Gallery: tapping the name browses just this folder.
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

/// Whether a tree row draws a disclosure chevron, and which way it points.
///
/// A row with no disclosure *slot* at all — a fixed node such as All Sources —
/// passes null instead of [none].
enum TreeDisclosure {
  /// The slot is kept, empty, so a leaf's name lines up with its siblings'.
  none,
  collapsed,
  expanded,
  loading,
}

/// The geometry of one row of the folder column: `A1 1a` under a pointer,
/// `A1 1e`'s drawer below the phone breakpoint.
///
/// Shared by the source tree, the result tree and the fixed nodes above them,
/// so the three read as one list.
@immutable
class FolderTreeMetrics {
  const FolderTreeMetrics._({
    required this.touch,
    required this.height,
    required this.margin,
    required this.padding,
    required this.gap,
    required this.fixedGap,
    required this.icon,
    required this.markerBox,
    required this.markerGap,
    required this.markerDensity,
    required this.headerInset,
  });

  /// Whether this is the phone drawer's variant.
  final bool touch;

  /// Row height: 32, or 44 for a finger.
  final double height;

  /// Horizontal gap between the row's ground and the column's edge.
  final double margin;

  /// Horizontal padding inside the ground, before any indent.
  final double padding;

  /// Gap between a row's pieces when it has a disclosure slot.
  final double gap;

  /// Gap between a fixed node's icon and label (`1a`: 8 there, 6 in the tree).
  final double fixedGap;

  /// The row's leading glyph.
  final double icon;

  /// The square the checkbox (or its blank stand-in) occupies.
  final double markerBox;

  /// Space after the marker. The checkbox's box already pads its glyph.
  final double markerGap;

  final VisualDensity markerDensity;

  /// Horizontal inset of a group caption.
  final double headerInset;

  /// Content indent per nesting level (`A1` `srcFolders`: 10 → 26).
  static const double indentStep = 16;

  /// The chevron glyph, and the width its slot reserves.
  static const double disclosureSize = AppSize.iconSm;

  static const FolderTreeMetrics _pointer = FolderTreeMetrics._(
    touch: false,
    height: AppSize.control,
    margin: AppSpace.s6,
    padding: AppSpace.s10,
    gap: AppSpace.s6,
    fixedGap: 8,
    icon: AppSize.iconMd,
    markerBox: 24,
    markerGap: 2,
    markerDensity: VisualDensity(
      horizontal: VisualDensity.minimumDensity,
      vertical: VisualDensity.minimumDensity,
    ),
    headerInset: AppSpace.s16,
  );

  static const FolderTreeMetrics _touch = FolderTreeMetrics._(
    touch: true,
    height: AppSize.touch,
    margin: 8,
    padding: 12,
    gap: AppSpace.s10,
    fixedGap: AppSpace.s10,
    icon: AppSize.iconLg,
    markerBox: 32,
    markerGap: 0,
    markerDensity: VisualDensity.compact,
    headerInset: 18,
  );

  /// A touch tablet keeps the pointer geometry at a finger's 40
  /// (`B1a · 1c`: drawer rows 40).
  static const FolderTreeMetrics _tablet = FolderTreeMetrics._(
    touch: false,
    height: AppSize.large,
    margin: AppSpace.s6,
    padding: AppSpace.s10,
    gap: AppSpace.s6,
    fixedGap: 8,
    icon: AppSize.iconMd,
    markerBox: 24,
    markerGap: 2,
    markerDensity: VisualDensity(
      horizontal: VisualDensity.minimumDensity,
      vertical: VisualDensity.minimumDensity,
    ),
    headerInset: AppSpace.s16,
  );

  static FolderTreeMetrics of(BuildContext context) {
    if (Responsive.isMobile(context)) return _touch;
    if (Platform.isAndroid || Platform.isIOS) return _tablet;
    return _pointer;
  }

  /// The row's name: 13, or the drawer's 14.
  TextStyle labelStyle(TextTheme textTheme) =>
      (touch ? textTheme.bodyLarge : textTheme.bodyMedium) ?? const TextStyle();

  /// A row's count: mono 11 (12 in the drawer) at regular weight, untracked.
  TextStyle countStyle(TextTheme textTheme) =>
      ((touch ? textTheme.bodySmall : textTheme.labelSmall) ?? const TextStyle())
          .mono
          .copyWith(fontWeight: FontWeight.w400, letterSpacing: 0);
}

/// One row of the folder column — `A1 1a`.
///
/// Draws its own ground (selected wash, hover wash, drop-target edge) inside
/// the margin its caller gives it, so a drop target wrapped around it frames
/// the ground and not the gutter.
class FolderTreeRow extends StatefulWidget {
  const FolderTreeRow({
    super.key,
    required this.icon,
    required this.label,
    this.depth = 0,
    this.disclosure,
    this.onToggle,
    this.marker,
    this.iconColor,
    this.labelColor,
    this.count,
    this.hoverAction,
    this.editor,
    this.selected = false,
    this.dropTone,
    this.dropNote,
    this.onTap,
    this.onSecondaryTapDown,
  });

  final IconData icon;
  final String label;
  final int depth;

  /// Null for a row with no disclosure slot at all.
  final TreeDisclosure? disclosure;

  final VoidCallback? onToggle;

  /// Drawn between the chevron and the icon — the tree's checkbox.
  final Widget? marker;

  /// Overrides the icon's colour, which otherwise follows [selected]. A
  /// [dropTone] outranks it.
  final Color? iconColor;

  /// Overrides the label's colour, which otherwise follows [selected]. A
  /// [dropTone] outranks it.
  final Color? labelColor;

  final String? count;

  /// Revealed while the row is hovered or selected, and always on a phone.
  final Widget? hoverAction;

  /// Replaces the label, count and action — the in-row name field.
  final Widget? editor;

  final bool selected;

  /// Something is dragged over this row (`00d · 1d`): what a release does,
  /// or that it is refused. Null at rest.
  final FolderDropTone? dropTone;

  /// The destination wording or the reason for a refusal, set at the row's
  /// end in place of the count and action — while the row has room for it
  /// beside the name.
  final String? dropNote;

  final VoidCallback? onTap;
  final GestureTapDownCallback? onSecondaryTapDown;

  @override
  State<FolderTreeRow> createState() => _FolderTreeRowState();
}

class _FolderTreeRowState extends State<FolderTreeRow> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered != value) setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final metrics = FolderTreeMetrics.of(context);
    final duration = AppMotion.durationOf(context, AppMotion.hover);
    final selected = widget.selected;
    final editing = widget.editor != null;

    // In an editing row the leading pieces sit level with the 32px field
    // rather than centred on a row the error line may have made taller.
    final double band = editing ? AppSize.control : metrics.height;
    final double gap = widget.disclosure == null ? metrics.fixedGap : metrics.gap;

    // `00d · 1d`: the ground, ring and ink of a row something is dragged over.
    // Move is `--tint` under the accent ring and the deep ink; copy swaps the
    // set for the success colours, a refusal for the error colours.
    final semantic = context.semantic;
    final (Color? dropGround, Color? dropEdge, Color? dropInk) = switch (widget.dropTone) {
      null => (null, null, null),
      FolderDropTone.move => (colorScheme.accentTint, colorScheme.primary, colorScheme.onAccentTint),
      FolderDropTone.copy => (semantic.successContainer, semantic.success, semantic.onSuccessContainer),
      FolderDropTone.reject => (colorScheme.errorContainer, colorScheme.error, colorScheme.onErrorContainer),
    };

    final Color ground = dropGround ??
        (selected
            ? colorScheme.accentTint
            : (_hovered && !editing
                ? colorScheme.onSurface.withValues(alpha: 0.06)
                : colorScheme.onSurface.withValues(alpha: 0)));
    final Color iconColor =
        dropEdge ?? widget.iconColor ?? (selected ? colorScheme.primary : colorScheme.onSurfaceVariant);
    final Color labelColor =
        dropInk ?? widget.labelColor ?? (selected ? colorScheme.onAccentTint : colorScheme.onSurface);
    final Color countColor = selected ? colorScheme.onAccentTint : colorScheme.onSurfaceVariant;

    final bool showAction =
        _hovered || selected || metrics.touch || Platform.isIOS || Platform.isAndroid;

    final children = <Widget>[
      if (widget.disclosure != null) _disclosure(colorScheme, band, gap),
      if (widget.marker != null) ...[
        SizedBox(height: band, child: Center(child: widget.marker)),
        if (metrics.markerGap > 0) SizedBox(width: metrics.markerGap),
      ],
      SizedBox(
        height: band,
        child: Center(child: Icon(widget.icon, size: metrics.icon, color: iconColor)),
      ),
      SizedBox(width: gap),
      if (editing)
        Expanded(child: widget.editor!)
      else if (widget.dropNote != null && dropInk != null)
        Expanded(
          child: _DropNoteSlot(
            label: widget.label,
            labelStyle: metrics.labelStyle(theme.textTheme).copyWith(color: labelColor),
            note: widget.dropNote!,
            ink: dropInk,
            gap: gap,
          ),
        )
      else ...[
        Expanded(
          child: Text(
            widget.label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: metrics.labelStyle(theme.textTheme).copyWith(
                  color: labelColor,
                  fontWeight: selected ? FontWeight.w500 : null,
                ),
          ),
        ),
        if (widget.count != null) ...[
          SizedBox(width: gap),
          Text(widget.count!, style: metrics.countStyle(theme.textTheme).copyWith(color: countColor)),
        ],
        if (widget.hoverAction != null) ...[
          const SizedBox(width: AppSpace.s4),
          ExcludeSemantics(
            excluding: !showAction,
            child: IgnorePointer(
              ignoring: !showAction,
              child: AnimatedOpacity(
                opacity: showAction ? 1 : 0,
                duration: duration,
                curve: AppMotion.quick,
                child: widget.hoverAction,
              ),
            ),
          ),
        ],
      ],
    ];

    final double vertical = editing ? AppSpace.s4 : 0;
    final body = AnimatedContainer(
      duration: duration,
      curve: AppMotion.quick,
      constraints: BoxConstraints(minHeight: metrics.height),
      padding: EdgeInsets.fromLTRB(
        metrics.padding + widget.depth * FolderTreeMetrics.indentStep,
        vertical,
        metrics.padding,
        vertical,
      ),
      decoration: BoxDecoration(
        color: ground,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      // Foreground, so the edge does not push the content over by its width;
      // drawn inside the ground (`outline-offset: -2`), so it frames the row
      // and not the gutter. Always 2px, only the colour changes, so the M1
      // transition fades the ring rather than growing it.
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: dropEdge ?? colorScheme.primary.withValues(alpha: 0),
          width: 2,
        ),
      ),
      child: Row(
        crossAxisAlignment: editing ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: children,
      ),
    );

    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: Semantics(
        button: widget.onTap != null,
        selected: selected,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onSecondaryTapDown: widget.onSecondaryTapDown,
          child: body,
        ),
      ),
    );
  }

  Widget _disclosure(ColorScheme colorScheme, double band, double gap) {
    final disclosure = widget.disclosure!;
    final Widget glyph = switch (disclosure) {
      TreeDisclosure.none => const SizedBox.shrink(),
      TreeDisclosure.loading => SizedBox.square(
          dimension: 10,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: colorScheme.outline),
        ),
      TreeDisclosure.collapsed =>
        Icon(Icons.chevron_right, size: FolderTreeMetrics.disclosureSize, color: colorScheme.outline),
      TreeDisclosure.expanded =>
        Icon(Icons.expand_more, size: FolderTreeMetrics.disclosureSize, color: colorScheme.outline),
    };

    // The gap after the chevron is part of its hit area: a 14px glyph alone
    // is too small a target.
    final slot = SizedBox(
      width: FolderTreeMetrics.disclosureSize + gap,
      height: band,
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox.square(
          dimension: FolderTreeMetrics.disclosureSize,
          child: Center(child: glyph),
        ),
      ),
    );

    final interactive = widget.onToggle != null &&
        (disclosure == TreeDisclosure.collapsed || disclosure == TreeDisclosure.expanded);
    if (!interactive) return slot;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onToggle,
        child: slot,
      ),
    );
  }
}

/// A small glyph action at the end of a [FolderTreeRow] — remove a folder
/// from the list.
///
/// No ink: the row paints its own ground above the nearest [Material], which
/// would hide a splash. The glyph darkens on hover instead.
class FolderTreeRowAction extends StatefulWidget {
  const FolderTreeRowAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  State<FolderTreeRowAction> createState() => _FolderTreeRowActionState();
}

class _FolderTreeRowActionState extends State<FolderTreeRowAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final metrics = FolderTreeMetrics.of(context);
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Semantics(
          button: true,
          label: widget.tooltip,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: SizedBox.square(
              dimension: metrics.touch ? AppSize.control : 20,
              child: Center(
                child: Icon(
                  widget.icon,
                  size: AppSize.iconSm,
                  color: _hovered ? colorScheme.onSurface : colorScheme.outline,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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

/// A folder row's name with the drop wording at its end (`00d · 1d`): 「移动到
/// X」, 「复制 12 项到 X」, or the reason for a refusal, on a small panel chip.
///
/// The chip takes the room the name does not need, down to half the slot;
/// past that the name matters more, and the follower already says what a
/// release does. Measured, so the rule holds in every language. Either way
/// the wording is announced.
class _DropNoteSlot extends StatelessWidget {
  const _DropNoteSlot({
    required this.label,
    required this.labelStyle,
    required this.note,
    required this.ink,
    required this.gap,
  });

  final String label;
  final TextStyle labelStyle;
  final String note;
  final Color ink;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final noteStyle = theme.textTheme.labelSmall!.copyWith(
      color: ink,
      fontWeight: FontWeight.w500,
      height: AppType.tightHeight,
    );
    final name = Text(label, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: labelStyle);

    return LayoutBuilder(
      builder: (context, constraints) {
        final double chipWidth = (measureGlassText(context, note, noteStyle) + AppSpace.s6 * 2).ceilToDouble();
        final double nameWidth = measureGlassText(context, label, labelStyle);
        final double room = constraints.maxWidth - chipWidth - gap;
        final bool fits = room >= math.min(nameWidth, constraints.maxWidth / 2);

        if (!fits) {
          return Row(
            children: [
              Expanded(child: name),
              Semantics(liveRegion: true, label: note),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: name),
            SizedBox(width: gap),
            Semantics(
              liveRegion: true,
              child: Container(
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Text(note, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: noteStyle),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Builds with the copy key's state, following [AppCopyModifier] only while
/// [active] — a tree of rows is not listening to the keyboard for the whole of
/// its life, only the one row a drag is over.
///
/// A widget of its own rather than a [ValueListenableBuilder] swapped in and
/// out, so the row under it keeps its element while hover comes and goes.
class _CopyModifierListener extends StatefulWidget {
  const _CopyModifierListener({required this.active, required this.builder});

  final bool active;
  final Widget Function(BuildContext context, bool copying) builder;

  @override
  State<_CopyModifierListener> createState() => _CopyModifierListenerState();
}

class _CopyModifierListenerState extends State<_CopyModifierListener> {
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_CopyModifierListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    if (_listening) AppCopyModifier.instance.removeListener(_changed);
    super.dispose();
  }

  void _sync() {
    if (widget.active == _listening) return;
    _listening = widget.active;
    if (_listening) {
      AppCopyModifier.instance.addListener(_changed);
    } else {
      AppCopyModifier.instance.removeListener(_changed);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _listening && AppCopyModifier.instance.value);
}

/// A folder row that takes a dragged selection or a dragged folder, when the
/// browser owns this tree — `00d · 1d` 投放到对象.
///
/// Split out so the tree item itself stays one widget whichever screen it is
/// on: the workbench's copy builds the row through the same builder with the
/// target simply absent.
///
/// What this folder will not take — a folder over itself or one of its own
/// subfolders, a payload already in this folder — is refused at
/// [DragTarget.onWillAcceptWithDetails], and the row says why: the error ring
/// and the reason at its end, with the follower carrying the same reason.
/// Never lit as a place to drop, never a haptic, never a toast.
class _MaybeDropTarget extends StatefulWidget {
  final bool enabled;
  final String path;

  /// Called after the pointer has rested on the row with a payload it takes,
  /// so a closed folder opens to receive a deeper drop.
  final VoidCallback onHoverExpand;

  final Widget Function(BuildContext context, _RowDrop? drop) builder;

  const _MaybeDropTarget({
    required this.enabled,
    required this.path,
    required this.onHoverExpand,
    required this.builder,
  });

  @override
  State<_MaybeDropTarget> createState() => _MaybeDropTargetState();
}

class _MaybeDropTargetState extends State<_MaybeDropTarget> {
  /// `00d`: a closed folder opens once an accepted drag has rested on it this
  /// long. Opening changes the view, not the target.
  static const Duration _expandDelay = Duration(milliseconds: 600);

  Timer? _expandTimer;

  /// The verdict on the payload over the row, reached once as it enters:
  /// deciding touches the disk, and [DragTarget.onMove] fires per pointer
  /// event.
  bool _hoverAccepted = false;
  FolderDropRejection? _hoverRejection;

  /// Replaced on every drop this row takes, to flash the confirmation ring.
  Object? _dropped;

  @override
  void dispose() {
    _expandTimer?.cancel();
    // A row torn down mid-hover is never told the pointer left. Withdrawn
    // after the frame: the follower cannot be asked to rebuild while this
    // tree is being taken apart.
    final Object owner = this;
    WidgetsBinding.instance.addPostFrameCallback((_) => FolderDropFeedback._withdraw(owner));
    super.dispose();
  }

  /// Why this folder refuses [data], or null when a release here lands.
  ///
  /// A move and a copy are judged alike: a copy into the folder the payload
  /// already sits in collides with itself, which is "already here" too.
  FolderDropRejection? _rejection(Object data) {
    if (data is List<BrowserFile>) {
      // Only when all of it is here. A mixed selection still has somewhere
      // to go, and the transfer plan skips the files already in place.
      if (data.every((file) => p.equals(p.dirname(file.path), widget.path))) {
        return FolderDropRejection.sameFolder;
      }
    } else if (data is FolderDragPayload) {
      final roots = Provider.of<FileBrowserState>(context, listen: false).sourceDirectories.toSet();
      final refused = FolderOperationsService.canTransfer(
        data.path,
        widget.path,
        roots: roots,
        mode: AppCopyModifier.isDown ? FolderTransferMode.copy : FolderTransferMode.move,
      );
      if (refused != null) {
        return switch (refused) {
          FolderMoveRejection.isRoot => FolderDropRejection.root,
          FolderMoveRejection.intoSelf || FolderMoveRejection.intoDescendant => FolderDropRejection.intoItself,
          FolderMoveRejection.sameParent => FolderDropRejection.sameFolder,
          FolderMoveRejection.targetExists => p.equals(p.dirname(data.path), widget.path)
              ? FolderDropRejection.sameFolder
              : FolderDropRejection.nameTaken,
        };
      }
    }
    return _isReadOnly(widget.path) ? FolderDropRejection.readOnly : null;
  }

  /// A folder that grants no one write permission. Only the POSIX mode bits
  /// are read: Windows keeps a folder's read-only attribute for the shell and
  /// ignores it for writes, and ownership, ACLs and sandboxes are left to the
  /// transfer, which reports what it could not do.
  static bool _isReadOnly(String path) {
    if (Platform.isWindows) return false;
    final stat = FileStat.statSync(path);
    // 0x92 is 0o222: the write bit for owner, group and others.
    return stat.type == FileSystemEntityType.directory && (stat.mode & 0x92) == 0;
  }

  bool _willAccept(Object data) {
    if (data is! List<BrowserFile> && data is! FolderDragPayload) {
      _hoverAccepted = false;
      _hoverRejection = null;
      return false;
    }
    final why = _rejection(data);
    _hoverAccepted = why == null;
    _hoverRejection = why;
    FolderDropFeedback._post(this, why);
    return why == null;
  }

  void _armExpand() {
    _expandTimer ??= Timer(_expandDelay, () {
      _expandTimer = null;
      if (mounted) widget.onHoverExpand();
    });
  }

  void _endHover() {
    _expandTimer?.cancel();
    _expandTimer = null;
    _hoverAccepted = false;
    _hoverRejection = null;
    FolderDropFeedback._withdraw(this);
  }

  void _drop(Object data) {
    _endHover();
    // Read at drop time, not at drag start: the user can reach for the copy
    // key (Ctrl, ⌥ on macOS) after picking the files up, which is when they
    // decide it is a copy.
    final copying = AppCopyModifier.isDown;
    setState(() => _dropped = Object());
    if (data is List<BrowserFile>) {
      runStagingPaste(
        context,
        mode: copying ? FileTransferMode.copy : FileTransferMode.move,
        destination: widget.path,
        files: data,
      );
    } else if (data is FolderDragPayload) {
      runFolderTransfer(
        context,
        source: data.path,
        destination: widget.path,
        mode: copying ? FolderTransferMode.copy : FolderTransferMode.move,
      );
    }
  }

  /// What a release of an accepted [data] does, in the row's words.
  String _note(AppLocalizations l10n, Object? data, bool copying) {
    final name = p.basename(widget.path);
    if (!copying) return l10n.dropMoveTo(name);
    return data is List<BrowserFile> ? l10n.dropCopyItemsTo(data.length, name) : l10n.dropCopyTo(name);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.builder(context, null);
    final l10n = AppLocalizations.of(context)!;

    return DragTarget<Object>(
      onWillAcceptWithDetails: (details) => _willAccept(details.data),
      onMove: (_) {
        if (_hoverAccepted) _armExpand();
      },
      onLeave: (_) => _endHover(),
      onAcceptWithDetails: (details) => _drop(details.data),
      builder: (context, candidate, rejected) {
        final bool accepted = candidate.isNotEmpty;
        // A payload from elsewhere in the app lands in `rejected` too; only
        // one this row judged has a reason to show.
        final FolderDropRejection? why = rejected.isNotEmpty ? _hoverRejection : null;
        return AppDropConfirmRing(
          trigger: _dropped,
          radius: AppRadius.sm,
          child: _CopyModifierListener(
            active: accepted,
            builder: (context, copying) {
              final _RowDrop? drop = why != null
                  ? (tone: FolderDropTone.reject, note: why.label(l10n))
                  : accepted
                      ? (
                          tone: copying ? FolderDropTone.copy : FolderDropTone.move,
                          note: _note(l10n, candidate.first, copying),
                        )
                      : null;
              return widget.builder(context, drop);
            },
          ),
        );
      },
    );
  }
}
