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
import '../../services/file_permission_service.dart';
import '../../services/file_transfer_service.dart';
import '../../services/folder_operations_service.dart';
import '../../state/app_state.dart';
import '../../state/file_browser_state.dart';
import '../../state/file_staging_state.dart';
import '../../state/gallery_state.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/dashed_border.dart';
import '../browser/folder_move_flow.dart';
import '../browser/staging_paste_flow.dart';
import '../browser/widgets/folder_context_menu.dart';
import '../browser/widgets/folder_delete_dialog.dart';
import '../browser/widgets/folder_name_editor.dart';

/// Folders are amber everywhere in the app. It is the one colour in the tree
/// that is not reporting state, which is exactly why a folder can keep it.
const Color kFolderAmber = Color(0xFFE0A64B);

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
  final bool isRoot;
  final bool useFileBrowserState;
  final Function(String, String)? onRemove; // Only needed for roots

  const DirectoryTreeItem({
    super.key,
    required this.path,
    this.isRoot = false,
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
  int _lastRefreshCounter = 0;

  /// Keyboard focus for the row, so F2 and Delete know which folder is meant.
  /// Taken on click (either button); the tree has no other focus concept.
  final FocusNode _focusNode = FocusNode(debugLabel: 'directory-tree-row');

  _RowEdit? _edit;

  /// Follows Ctrl/Meta while this row is being dragged, so the chip can say
  /// "copy" the moment the key goes down rather than at drag start.
  final ValueNotifier<bool> _copyModifier = ValueNotifier(false);

  /// Bumped when the browser asks this row to pulse; 0 means never.
  int _pulse = 0;
  String? _pulsedFor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Depend on the notifier that owns the counter — AppState no longer
    // forwards either one.
    final currentCounter = widget.useFileBrowserState
        ? Provider.of<FileBrowserState>(context).refreshCounter
        : Provider.of<GalleryState>(context).refreshCounter;

    if (currentCounter != _lastRefreshCounter) {
      _lastRefreshCounter = currentCounter;
      if (_isExpanded) {
        // Reload in place, keeping the stale list rendered until fresh data
        // arrives — nulling it first unmounts every child DirectoryTreeItem,
        // which destroys their expansion state (deep branches collapse).
        _loadSubDirectories(force: true);
      } else {
        _subDirectories = null;
      }
    }

    if (widget.useFileBrowserState) {
      final flash = Provider.of<FileBrowserState>(context).flashPath;
      if (flash != null && flash != _pulsedFor) {
        if (p.equals(flash, widget.path)) {
          _pulsedFor = flash;
          _pulse++;
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

  @override
  void dispose() {
    _focusNode.dispose();
    _copyModifier.dispose();
    HardwareKeyboard.instance.removeHandler(_trackCopyModifier);
    super.dispose();
  }

  Future<void> _reAuthorize(BuildContext context, AppState appState) async {
    final String? newPath = await FilePermissionService().reAuthorize(
      widget.path,
      title: "Authorize Access to: ${widget.path}",
    );

    if (newPath != null) {
      // If it was a root, we might need to replace it in the list
      if (widget.isRoot) {
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
    // and the renamed row comes back under its new key, pulsing.
    appState.fileBrowserState.flash(renamed);
    await applyFolderPathChange(appState, staging, widget.path, renamed);
    if (mounted) AppSnackBar.success(context, l10n.folderRenamed(p.basename(renamed)));
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
    if (widget.isRoot) {
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
      isRoot: widget.isRoot,
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

  void _syncCopyModifier() {
    final hw = HardwareKeyboard.instance;
    _copyModifier.value = hw.isControlPressed || hw.isMetaPressed;
  }

  /// Observes only — never claims the key, so Ctrl keeps doing whatever else
  /// it does while the drag is live.
  bool _trackCopyModifier(KeyEvent event) {
    _syncCopyModifier();
    return false;
  }

  void _onDragStarted() {
    _syncCopyModifier();
    HardwareKeyboard.instance.addHandler(_trackCopyModifier);
  }

  void _onDragEnded() {
    HardwareKeyboard.instance.removeHandler(_trackCopyModifier);
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
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    // A root is boxed so the eye can find where one tree ends and the next
    // begins; below it, only the highlighted row is drawn. Nesting already says
    // a child is a child — an outline on each one would say it twice.
    final colorScheme = theme.colorScheme;
    final Color? boxColor = highlight ? colorScheme.primary.withValues(alpha: 0.14) : null;
    final Color borderColor = highlight
        ? colorScheme.primary.withValues(alpha: 0.6)
        : (widget.isRoot ? colorScheme.outlineVariant.withAlpha(120) : Colors.transparent);

    final leading = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isUnreachable)
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Tooltip(
              message: "Access Denied (Click to re-authorize)",
              child: InkWell(
                onTap: () => _reAuthorize(context, appState),
                child: Icon(Icons.lock_person, size: 18, color: theme.colorScheme.error),
              ),
            ),
          )
        else
          Checkbox(
            value: isSelected,
            onChanged: (val) {
              if (widget.useFileBrowserState) {
                appState.fileBrowserState.toggleDirectory(widget.path);
              } else {
                // Checkbox = include/exclude from the aggregate; the live
                // aggregate rescans, no forced view switch.
                appState.galleryState.toggleDirectory(widget.path);
              }
            },
            visualDensity: VisualDensity.compact,
            // The box, not the 48px tap target around it. `16a` draws a
            // 16px square, and in a 236px column the target's padding is
            // the difference between a readable name and an ellipsis.
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        Icon(
          _isExpanded ? Icons.folder_open : Icons.folder,
          size: 20,
          // Folders keep their own colour rather than tracking selection:
          // the checkbox beside it and the box around it already report
          // that, and a tree of grey folders reads as a tree of disabled
          // ones.
          color: isUnreachable ? colorScheme.error.withAlpha(100) : kFolderAmber,
        ),
        const SizedBox(width: 8),
      ],
    );

    final Widget rowBody;
    if (_edit == _RowEdit.renaming) {
      rowBody = _EditorRow(
        indentRoot: widget.isRoot,
        checkboxSlot: !isUnreachable,
        editor: FolderNameEditor(
          initialName: folderName,
          validate: (name) => _nameError(l10n, p.dirname(widget.path), name, currentPath: widget.path),
          onSubmit: _commitRename,
          onCancel: _cancelEdit,
        ),
      );
    } else {
      rowBody = ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: EdgeInsets.only(left: widget.isRoot ? 8 : 4, right: 4),
        // ListTile budgets 40px for a leading slot and 16 between it and the
        // title, both of which this row has already spent inside its own
        // leading Row. At `16a`'s 236px column that reserved-but-unused
        // space came out of the folder name — a six-letter name ellipsized
        // to two.
        minLeadingWidth: 0,
        horizontalTitleGap: 6,
        leading: leading,
        title: Text(
          folderName,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: highlight ? FontWeight.w600 : FontWeight.w500,
            color: highlight ? theme.colorScheme.primary : (isUnreachable ? theme.colorScheme.error : null),
          ),
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isUnreachable && (_subDirectories == null || _subDirectories!.isNotEmpty))
              IconButton(
                icon: _isLoading
                  ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(_isExpanded ? Icons.expand_less : Icons.expand_more, size: 18),
                onPressed: () => _handleExpansionChanged(!_isExpanded),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                visualDensity: VisualDensity.compact,
              ),

            if (widget.isRoot && widget.onRemove != null)
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () => widget.onRemove!(widget.path, folderName),
                padding: const EdgeInsets.only(left: 4),
                constraints: const BoxConstraints(),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        onTap: () {
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
        },
      );
    }

    final row = Container(
      margin: const EdgeInsets.fromLTRB(6, 2, 6, 2),
      // `12d`'s second way to name a destination: drop the selection on a
      // folder. Default is move, Ctrl copies — the convention every file
      // manager already trained the user on. Browser only; the workbench
      // shares this tree and has nothing to paste. `13e` adds folders to
      // what can be dropped here, under the same rule.
      child: _MaybeDropTarget(
        enabled: widget.useFileBrowserState && _edit == null,
        path: widget.path,
        onHoverExpand: () {
          if (!_isExpanded) _handleExpansionChanged(true);
        },
        builder: (context, hovered) {
          // The box is a Material rather than a decorated Container: ListTile
          // paints its own fill and its ink onto the nearest Material
          // ancestor, and a Container painting on top of that hid both — the
          // framework says so at every build. Same fill, same border, same
          // radius.
          Widget material = Material(
            color: hovered ? colorScheme.accentTint : (boxColor ?? Colors.transparent),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: hovered
                  ? BorderSide(color: colorScheme.primary, width: 1.5)
                  : BorderSide(color: borderColor),
            ),
            clipBehavior: Clip.antiAlias,
            // The file browser's paste target is named here and nowhere else.
            // `12d` puts it on the folder's own context menu because that is
            // the only place in the app where a folder is a thing you can
            // point at — the grid shows a merged listing with no folder of its
            // own. Gated on the browser: the workbench's copy of this tree has
            // no staging area behind it.
            child: Focus(
              focusNode: _focusNode,
              onKeyEvent: _onKey,
              child: GestureDetector(
                onSecondaryTapDown: widget.useFileBrowserState && _edit == null
                    ? (details) => _showMenu(details.globalPosition)
                    : null,
                child: rowBody,
              ),
            ),
          );
          if (_pulse > 0) material = _Pulsed(key: ValueKey(_pulse), child: material);
          return material;
        },
      ),
    );

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row,
        if (_isExpanded && (_subDirectories != null || _edit == _RowEdit.creating))
          Padding(
            padding: const EdgeInsets.only(left: 24.0),
            child: Column(
              children: [
                if (_edit == _RowEdit.creating)
                  Container(
                    margin: const EdgeInsets.fromLTRB(6, 2, 6, 2),
                    child: _EditorRow(
                      indentRoot: false,
                      checkboxSlot: true,
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
                    useFileBrowserState: widget.useFileBrowserState,
                    // onRemove not needed for children
                  );
                }),
              ],
            ),
          ),
      ],
    );

    // Roots do not move — they are registrations, and "remove from list" is
    // how one changes. So a root row is not draggable at all: no chip, no
    // dimming, nothing lights up. The tree simply does not answer.
    if (!widget.useFileBrowserState || widget.isRoot || isUnreachable) return column;

    return Draggable<FolderDragPayload>(
      data: FolderDragPayload(widget.path),
      maxSimultaneousDrags: _edit == null ? 1 : 0,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _FolderDragChip(name: folderName, copying: _copyModifier),
      // The row and its subtree fade together: what is being picked up is
      // the whole branch, and the tree must not reflow under the pointer.
      childWhenDragging: Opacity(opacity: 0.45, child: column),
      onDragStarted: _onDragStarted,
      onDragEnd: (_) => _onDragEnded(),
      child: column,
    );
  }
}

/// The row while its name is being typed — `13b`. Same geometry as the
/// [ListTile] it replaces: the checkbox slot is kept (blank, same size) so the
/// folder icon and the field line up with the rows above and below.
class _EditorRow extends StatelessWidget {
  final bool indentRoot;
  final bool checkboxSlot;
  final Widget editor;

  const _EditorRow({
    required this.indentRoot,
    required this.checkboxSlot,
    required this.editor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: indentRoot ? 8 : 4, right: 4, top: 4, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (checkboxSlot)
            Visibility(
              visible: false,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: Checkbox(
                value: false,
                onChanged: null,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(Icons.folder, size: 20, color: kFolderAmber),
          ),
          const SizedBox(width: 8),
          Expanded(child: editor),
          const SizedBox(width: 4),
        ],
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
                    borderRadius: BorderRadius.circular(8),
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

/// What follows the pointer while a folder is dragged — `13e`. Same ink chip
/// as the file drag, with a small amber folder so the two read differently.
class _FolderDragChip extends StatelessWidget {
  final String name;
  final ValueListenable<bool> copying;

  const _FolderDragChip({required this.name, required this.copying});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.only(left: 12, top: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppOverlay.ink,
          borderRadius: BorderRadius.circular(AppRadius.control),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder, size: 14, color: kFolderAmber),
            const SizedBox(width: 6),
            ValueListenableBuilder<bool>(
              valueListenable: copying,
              builder: (context, copy, _) => Text(
                copy ? l10n.dragCopyFolderHint(name) : l10n.dragMoveFolderHint(name),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppOverlay.onInk, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A folder row that accepts a dragged selection or a dragged folder, when
/// the browser owns this tree.
///
/// Split out so the tree item itself stays one widget whichever screen it is
/// on: the workbench's copy builds the row through the same builder with the
/// target simply absent.
///
/// A folder that may not land here — itself, one of its ancestors, its own
/// parent — is refused at [DragTarget.onWillAcceptWithDetails], so the row
/// never lights up. Not lighting up *is* the refusal; there is no toast.
class _MaybeDropTarget extends StatefulWidget {
  final bool enabled;
  final String path;

  /// Called after the pointer has hovered with an acceptable payload for a
  /// moment, so a closed folder opens to receive a deeper drop.
  final VoidCallback onHoverExpand;

  final Widget Function(BuildContext context, bool hovered) builder;

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
  Timer? _expandTimer;

  @override
  void dispose() {
    _expandTimer?.cancel();
    super.dispose();
  }

  static bool get _copyKeyDown =>
      HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;

  bool _accepts(Object? data) {
    if (data is List<BrowserFile>) return data.isNotEmpty;
    if (data is FolderDragPayload) {
      final roots = Provider.of<FileBrowserState>(context, listen: false).sourceDirectories.toSet();
      return FolderOperationsService.canTransfer(
            data.path,
            widget.path,
            roots: roots,
            mode: _copyKeyDown ? FolderTransferMode.copy : FolderTransferMode.move,
          ) ==
          null;
    }
    return false;
  }

  void _armExpand() {
    _expandTimer ??= Timer(const Duration(milliseconds: 700), () {
      _expandTimer = null;
      if (mounted) widget.onHoverExpand();
    });
  }

  void _disarm() {
    _expandTimer?.cancel();
    _expandTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.builder(context, false);

    return DragTarget<Object>(
      onWillAcceptWithDetails: (details) => _accepts(details.data),
      onMove: (details) {
        if (_accepts(details.data)) _armExpand();
      },
      onLeave: (_) => _disarm(),
      onAcceptWithDetails: (details) {
        _disarm();
        // Read at drop time, not at drag start: the user can reach for Ctrl
        // after picking the files up, which is when they decide it is a copy.
        final copying = _copyKeyDown;
        final data = details.data;
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
      },
      builder: (context, candidate, rejected) => Stack(
        children: [
          widget.builder(context, candidate.isNotEmpty),
          if (candidate.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: DashedBorder(
                  color: Theme.of(context).colorScheme.primary,
                  radius: 8,
                  strokeWidth: 1.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
