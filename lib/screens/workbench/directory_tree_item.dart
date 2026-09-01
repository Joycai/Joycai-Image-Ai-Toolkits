import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../services/file_permission_service.dart';
import '../../state/app_state.dart';
import '../../state/file_browser_state.dart';
import '../../state/gallery_state.dart';
import '../../core/design_tokens.dart';
import '../../widgets/dashed_border.dart';
import '../../models/browser_file.dart';
import '../../services/file_transfer_service.dart';
import '../browser/staging_paste_flow.dart';
import '../browser/widgets/folder_context_menu.dart';

/// Folders are amber everywhere in the app. It is the one colour in the tree
/// that is not reporting state, which is exactly why a folder can keep it.
const Color kFolderAmber = Color(0xFFE0A64B);

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

    // We no longer need the separate 'isViewing' concept for highlighting, 
    // we use 'isSelected' for the primary visual feedback.
    final appState = Provider.of<AppState>(context, listen: false);
    final isUnreachable = widget.useFileBrowserState 
        ? appState.unreachableBrowserDirectories.contains(widget.path)
        : appState.galleryState.unreachableDirectories.contains(widget.path);
    final folderName = p.basename(widget.path);
    final theme = Theme.of(context);

    // A root is boxed so the eye can find where one tree ends and the next
    // begins; below it, only the highlighted row is drawn. Nesting already says
    // a child is a child — an outline on each one would say it twice.
    final colorScheme = theme.colorScheme;
    final Color? boxColor = highlight ? colorScheme.primary.withValues(alpha: 0.14) : null;
    final Color borderColor = highlight
        ? colorScheme.primary.withValues(alpha: 0.6)
        : (widget.isRoot ? colorScheme.outlineVariant.withAlpha(120) : Colors.transparent);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The box is a Material rather than a decorated Container: ListTile
        // paints its own fill and its ink onto the nearest Material ancestor,
        // and a Container painting on top of that hid both — the framework
        // says so at every build. Same fill, same border, same radius.
        Container(
          margin: const EdgeInsets.fromLTRB(6, 2, 6, 2),
          // `12d`'s second way to name a destination: drop the selection on a
          // folder. Default is move, Ctrl copies — the convention every file
          // manager already trained the user on. Browser only; the workbench
          // shares this tree and has nothing to paste.
          child: _MaybeDropTarget(
            enabled: widget.useFileBrowserState,
            path: widget.path,
            builder: (context, hovered) => Material(
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
            child: GestureDetector(
              onSecondaryTapDown: widget.useFileBrowserState
                  ? (details) => showFolderContextMenu(
                        context: context,
                        path: widget.path,
                        position: details.globalPosition,
                      )
                  : null,
              child: ListTile(
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
          leading: Row(
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
          ),
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
              ),
            ),
            ),
          ),
        ),

        if (_isExpanded && _subDirectories != null)
          Padding(
            padding: const EdgeInsets.only(left: 24.0),
            child: Column(
              children: _subDirectories!.map((dir) {
                return DirectoryTreeItem(
                  // Keyed by path so expansion state follows the directory
                  // when siblings are added/removed across refreshes.
                  key: ValueKey(dir.path),
                  path: dir.path,
                  isRoot: false,
                  useFileBrowserState: widget.useFileBrowserState,
                  // onRemove not needed for children
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}
/// A folder row that accepts a dragged selection, when the browser owns this
/// tree.
///
/// Split out so the tree item itself stays one widget whichever screen it is
/// on: the workbench's copy builds the row through the same builder with the
/// target simply absent.
class _MaybeDropTarget extends StatelessWidget {
  final bool enabled;
  final String path;
  final Widget Function(BuildContext context, bool hovered) builder;

  const _MaybeDropTarget({
    required this.enabled,
    required this.path,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return builder(context, false);

    return DragTarget<List<BrowserFile>>(
      onWillAcceptWithDetails: (details) => details.data.isNotEmpty,
      onAcceptWithDetails: (details) {
        // Read at drop time, not at drag start: the user can reach for Ctrl
        // after picking the files up, which is when they decide it is a copy.
        final copying = HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed;
        runStagingPaste(
          context,
          mode: copying ? FileTransferMode.copy : FileTransferMode.move,
          destination: path,
          files: details.data,
        );
      },
      builder: (context, candidate, rejected) => Stack(
        children: [
          builder(context, candidate.isNotEmpty),
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
