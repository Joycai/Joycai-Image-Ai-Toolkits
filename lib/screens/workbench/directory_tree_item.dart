import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../services/file_permission_service.dart';
import '../../state/app_state.dart';
import '../../state/gallery_state.dart';

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
    final appState = Provider.of<AppState>(context);
    final currentCounter = widget.useFileBrowserState ? appState.browserRefreshCounter : appState.galleryState.refreshCounter;
    
    if (currentCounter != _lastRefreshCounter) {
      _lastRefreshCounter = currentCounter;
      _subDirectories = null;
      if (_isExpanded) _loadSubDirectories();
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

  Future<void> _loadSubDirectories() async {
    if (_subDirectories != null) return;

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
    // Listen to selection changes efficiently based on the target state
    final isSelected = context.select<AppState, bool>((state) {
      if (widget.useFileBrowserState) {
        return state.fileBrowserState.activeDirectories.contains(widget.path);
      } else {
        return state.activeSourceDirectories.contains(widget.path);
      }
    });

    final isViewing = context.select<AppState, bool>((state) {
      if (widget.useFileBrowserState) return false;
      return state.galleryState.viewMode == GalleryViewMode.folder && state.galleryState.viewSourcePath == widget.path;
    });
    
    final appState = Provider.of<AppState>(context, listen: false);
    final isUnreachable = widget.useFileBrowserState 
        ? appState.unreachableBrowserDirectories.contains(widget.path)
        : appState.galleryState.unreachableDirectories.contains(widget.path);
    final folderName = p.basename(widget.path);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          dense: true,
          selected: isViewing,
          contentPadding: EdgeInsets.only(left: widget.isRoot ? 8 : 0, right: 4),
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
                      appState.galleryState.toggleDirectory(widget.path);
                      if (val == true) {
                        appState.galleryState.setViewMode(GalleryViewMode.all);
                      }
                    }
                  },
                  visualDensity: VisualDensity.compact,
                ),
              Icon(
                _isExpanded ? Icons.folder_open : Icons.folder,
                size: 20,
                color: isUnreachable 
                  ? theme.colorScheme.error.withAlpha(100)
                  : (isViewing ? theme.colorScheme.primary : (isSelected ? theme.colorScheme.primary.withAlpha(150) : theme.colorScheme.outline)),
              ),
              const SizedBox(width: 8),
            ],
          ),
          title: InkWell(
            onTap: () {
              if (isUnreachable) {
                _reAuthorize(context, appState);
              } else if (!widget.useFileBrowserState) {
                appState.galleryState.setViewFolder(widget.path);
              }
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    folderName,
                    style: TextStyle(
                      fontSize: 13, 
                      fontWeight: isViewing ? FontWeight.bold : FontWeight.w500,
                      color: isViewing ? theme.colorScheme.primary : (isUnreachable ? theme.colorScheme.error : null),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
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
                  padding: const EdgeInsets.only(left: 8),
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          onTap: () {
            if (isUnreachable) {
              _reAuthorize(context, appState);
            } else {
              _handleExpansionChanged(!_isExpanded);
            }
          },
        ),
        
        if (_isExpanded && _subDirectories != null)
          Padding(
            padding: const EdgeInsets.only(left: 24.0),
            child: Column(
              children: _subDirectories!.map((dir) {
                return DirectoryTreeItem(
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